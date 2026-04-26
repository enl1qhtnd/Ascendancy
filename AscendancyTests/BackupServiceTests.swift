import XCTest
import SwiftData
@testable import Ascendancy

final class BackupServiceTests: XCTestCase {

    @MainActor
    func test_exportAndRestore_roundTripsProtocolsLogsDocumentsAndProfile() throws {
        let (_, sourceContext) = try makeStore()
        let (_, targetContext) = try makeStore()
        let (sourceSuite, sourceDefaults) = try makeDefaults()
        let (targetSuite, targetDefaults) = try makeDefaults()
        defer {
            sourceDefaults.removePersistentDomain(forName: sourceSuite)
            targetDefaults.removePersistentDomain(forName: targetSuite)
        }

        let startDate = Date(timeIntervalSince1970: 1_700_000_000)
        let endDate = Date(timeIntervalSince1970: 1_710_000_000)
        var schedule = DoseSchedule()
        schedule.type = .specificWeekdays
        schedule.weekdays = [.monday, .friday]
        schedule.timesOfDay = [Date(timeIntervalSince1970: 1_700_030_000)]

        let protocol_ = CompoundProtocol(
            name: "BPC",
            category: .peptide,
            administrationForm: .vial,
            doseAmount: 500,
            doseUnit: .mcg,
            schedule: schedule,
            startDate: startDate,
            endDate: endDate,
            notes: "With food",
            halfLifeValue: 6,
            halfLifeUnit: .hours,
            status: .paused,
            inventoryCount: 8,
            inventoryLowThreshold: 2,
            remindersEnabled: false,
            formDosage: 10,
            sortOrder: 3
        )
        protocol_.inventoryUnitLabel = "vials"
        sourceContext.insert(protocol_)

        let logDate = Date(timeIntervalSince1970: 1_700_100_000)
        let log = DoseLog(
            protocol_: protocol_,
            actualDoseAmount: 450,
            doseUnit: .mcg,
            timestamp: logDate,
            notes: "Left side"
        )
        sourceContext.insert(log)

        let documentDate = Date(timeIntervalSince1970: 1_700_200_000)
        let document = MediaDocument(
            title: "Bloodwork",
            imageData: Data([1, 2, 3, 4]),
            fileExtension: "pdf",
            dateAdded: documentDate
        )
        sourceContext.insert(document)
        try sourceContext.save()

        sourceDefaults.set("Nico", forKey: "userName")
        sourceDefaults.set("Recovery", forKey: "userGoal")
        sourceDefaults.set(Data([9, 8, 7]), forKey: "profileImageData")

        targetContext.insert(CompoundProtocol(
            name: "Old",
            category: .medication,
            administrationForm: .pill,
            doseAmount: 1,
            doseUnit: .mg,
            schedule: .daily
        ))
        targetDefaults.set("Old User", forKey: "userName")
        try targetContext.save()

        let data = try BackupService.exportData(from: sourceContext, userDefaults: sourceDefaults)
        let summary = try BackupService.restore(from: data, into: targetContext, userDefaults: targetDefaults)

        XCTAssertEqual(summary.protocolCount, 1)
        XCTAssertEqual(summary.logCount, 1)
        XCTAssertEqual(summary.documentCount, 1)

        let restoredProtocols = try targetContext.fetch(FetchDescriptor<CompoundProtocol>())
        XCTAssertEqual(restoredProtocols.count, 1)
        let restoredProtocol = try XCTUnwrap(restoredProtocols.first)
        XCTAssertEqual(restoredProtocol.id, protocol_.id)
        XCTAssertEqual(restoredProtocol.name, "BPC")
        XCTAssertEqual(restoredProtocol.categoryRaw, CompoundCategory.peptide.rawValue)
        XCTAssertEqual(restoredProtocol.administrationFormRaw, AdministrationForm.vial.rawValue)
        XCTAssertEqual(restoredProtocol.doseAmount, 500)
        XCTAssertEqual(restoredProtocol.doseUnitRaw, DoseUnit.mcg.rawValue)
        XCTAssertEqual(restoredProtocol.schedule.type, .specificWeekdays)
        XCTAssertEqual(Set(restoredProtocol.schedule.weekdays), Set([.monday, .friday]))
        XCTAssertEqual(restoredProtocol.startDate, startDate)
        XCTAssertEqual(restoredProtocol.endDate, endDate)
        XCTAssertEqual(restoredProtocol.notes, "With food")
        XCTAssertEqual(restoredProtocol.halfLifeValue, 6)
        XCTAssertEqual(restoredProtocol.statusRaw, ProtocolStatus.paused.rawValue)
        XCTAssertEqual(restoredProtocol.inventoryCount, 8)
        XCTAssertEqual(restoredProtocol.inventoryUnitLabel, "vials")
        XCTAssertFalse(restoredProtocol.remindersEnabled)
        XCTAssertEqual(restoredProtocol.formDosage, 10)
        XCTAssertEqual(restoredProtocol.sortOrder, 3)

        let restoredLogs = try targetContext.fetch(FetchDescriptor<DoseLog>())
        XCTAssertEqual(restoredLogs.count, 1)
        let restoredLog = try XCTUnwrap(restoredLogs.first)
        XCTAssertEqual(restoredLog.id, log.id)
        XCTAssertEqual(restoredLog.protocol_?.id, restoredProtocol.id)
        XCTAssertEqual(restoredLog.actualDoseAmount, 450)
        XCTAssertEqual(restoredLog.doseUnitRaw, DoseUnit.mcg.rawValue)
        XCTAssertEqual(restoredLog.timestamp, logDate)
        XCTAssertEqual(restoredLog.notes, "Left side")
        XCTAssertEqual(restoredLog.protocolName, "BPC")

        let restoredDocuments = try targetContext.fetch(FetchDescriptor<MediaDocument>())
        XCTAssertEqual(restoredDocuments.count, 1)
        let restoredDocument = try XCTUnwrap(restoredDocuments.first)
        XCTAssertEqual(restoredDocument.id, document.id)
        XCTAssertEqual(restoredDocument.title, "Bloodwork")
        XCTAssertEqual(restoredDocument.imageData, Data([1, 2, 3, 4]))
        XCTAssertEqual(restoredDocument.fileExtension, "pdf")
        XCTAssertEqual(restoredDocument.dateAdded, documentDate)

        XCTAssertEqual(targetDefaults.string(forKey: "userName"), "Nico")
        XCTAssertEqual(targetDefaults.string(forKey: "userGoal"), "Recovery")
        XCTAssertEqual(targetDefaults.data(forKey: "profileImageData"), Data([9, 8, 7]))
    }

    @MainActor
    func test_restoreRejectsUnsupportedFutureBackupFormat() throws {
        let (_, context) = try makeStore()
        let payload = """
        {
          "doseLogs": [],
          "mediaDocuments": [],
          "metadata": {
            "createdAt": "2026-04-23T12:00:00Z",
            "formatVersion": 999
          },
          "profile": {
            "userGoal": "",
            "userName": ""
          },
          "protocols": []
        }
        """.data(using: .utf8)!

        XCTAssertThrowsError(try BackupService.restore(from: payload, into: context)) { error in
            guard case BackupError.unsupportedVersion(999) = error else {
                XCTFail("Expected unsupportedVersion, got \(error)")
                return
            }
        }
    }

    @MainActor
    private func makeStore() throws -> (ModelContainer, ModelContext) {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: CompoundProtocol.self,
            DoseLog.self,
            MediaDocument.self,
            configurations: config
        )
        return (container, ModelContext(container))
    }

    private func makeDefaults() throws -> (String, UserDefaults) {
        let suiteName = "BackupServiceTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return (suiteName, defaults)
    }
}
