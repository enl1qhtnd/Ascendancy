import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let ascendancyBackup = UTType(exportedAs: "de.enl1qhtnd.asce.backup", conformingTo: .json)
}

struct AscendancyBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.ascendancyBackup, .json] }

    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw BackupError.emptyFile
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

enum BackupError: LocalizedError {
    case emptyFile
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case .emptyFile:
            return "The selected backup file is empty."
        case .unsupportedVersion(let version):
            return "This backup was created with an unsupported format version (\(version))."
        }
    }
}

struct BackupImportSummary {
    let protocolCount: Int
    let logCount: Int
    let documentCount: Int

    var message: String {
        "Imported \(protocolCount) protocols, \(logCount) logs, and \(documentCount) files."
    }
}

@MainActor
enum BackupService {
    static let currentFormatVersion = 1

    static func defaultFileName(createdAt: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return "Ascendancy-Backup-\(formatter.string(from: createdAt)).ascendancybackup"
    }

    static func exportData(from context: ModelContext, userDefaults: UserDefaults = .standard) throws -> Data {
        let protocols = try context.fetch(FetchDescriptor<CompoundProtocol>(sortBy: CompoundProtocol.listSortDescriptors))
        let logs = try context.fetch(FetchDescriptor<DoseLog>(sortBy: [
            SortDescriptor(\DoseLog.timestamp, order: .reverse)
        ]))
        let documents = try context.fetch(FetchDescriptor<MediaDocument>(sortBy: [
            SortDescriptor(\MediaDocument.dateAdded, order: .reverse)
        ]))

        let backup = BackupPayload(
            metadata: BackupMetadata(
                formatVersion: currentFormatVersion,
                createdAt: Date(),
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                buildNumber: Bundle.main.infoDictionary?["CFBundleVersion"] as? String
            ),
            profile: ProfileRecord(userDefaults: userDefaults),
            protocols: protocols.map(ProtocolRecord.init),
            doseLogs: logs.map(DoseLogRecord.init),
            mediaDocuments: documents.map(MediaDocumentRecord.init)
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(backup)
    }

    @discardableResult
    static func restore(from data: Data, into context: ModelContext, userDefaults: UserDefaults = .standard) throws -> BackupImportSummary {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(BackupPayload.self, from: data)

        guard backup.metadata.formatVersion <= currentFormatVersion else {
            throw BackupError.unsupportedVersion(backup.metadata.formatVersion)
        }

        do {
            try deleteAll(DoseLog.self, in: context)
            try deleteAll(MediaDocument.self, in: context)
            try deleteAll(CompoundProtocol.self, in: context)

            var protocolsByID: [UUID: CompoundProtocol] = [:]
            for record in backup.protocols {
                let protocol_ = record.makeModel()
                context.insert(protocol_)
                protocolsByID[protocol_.id] = protocol_
            }

            for record in backup.doseLogs {
                let log = record.makeModel(protocol_: record.protocolID.flatMap { protocolsByID[$0] })
                context.insert(log)
            }

            for record in backup.mediaDocuments {
                context.insert(record.makeModel())
            }

            try context.save()
        } catch {
            context.rollback()
            throw error
        }

        backup.profile.apply(to: userDefaults)

        return BackupImportSummary(
            protocolCount: backup.protocols.count,
            logCount: backup.doseLogs.count,
            documentCount: backup.mediaDocuments.count
        )
    }

    private static func deleteAll<T: PersistentModel>(_ modelType: T.Type, in context: ModelContext) throws {
        let models = try context.fetch(FetchDescriptor<T>())
        for model in models {
            context.delete(model)
        }
    }
}

private struct BackupPayload: Codable {
    var metadata: BackupMetadata
    var profile: ProfileRecord
    var protocols: [ProtocolRecord]
    var doseLogs: [DoseLogRecord]
    var mediaDocuments: [MediaDocumentRecord]
}

private struct BackupMetadata: Codable {
    var formatVersion: Int
    var createdAt: Date
    var appVersion: String?
    var buildNumber: String?
}

private struct ProfileRecord: Codable {
    var userName: String
    var userGoal: String
    var profileImageData: Data?

    init(userDefaults: UserDefaults) {
        userName = userDefaults.string(forKey: "userName") ?? ""
        userGoal = userDefaults.string(forKey: "userGoal") ?? ""
        profileImageData = userDefaults.data(forKey: "profileImageData")
    }

    func apply(to userDefaults: UserDefaults) {
        userDefaults.set(userName, forKey: "userName")
        userDefaults.set(userGoal, forKey: "userGoal")
        if let profileImageData {
            userDefaults.set(profileImageData, forKey: "profileImageData")
        } else {
            userDefaults.removeObject(forKey: "profileImageData")
        }
    }
}

private struct ProtocolRecord: Codable {
    var id: UUID
    var name: String
    var categoryRaw: String
    var administrationFormRaw: String
    var doseAmount: Double
    var doseUnitRaw: String
    var scheduleData: Data?
    var startDate: Date
    var endDate: Date?
    var notes: String
    var halfLifeValue: Double
    var halfLifeUnitRaw: String
    var statusRaw: String
    var inventoryCount: Double
    var inventoryLowThreshold: Double
    var inventoryUnitLabel: String
    var remindersEnabled: Bool
    var formDosage: Double
    var sortOrder: Int

    init(_ protocol_: CompoundProtocol) {
        id = protocol_.id
        name = protocol_.name
        categoryRaw = protocol_.categoryRaw
        administrationFormRaw = protocol_.administrationFormRaw
        doseAmount = protocol_.doseAmount
        doseUnitRaw = protocol_.doseUnitRaw
        scheduleData = protocol_.scheduleData
        startDate = protocol_.startDate
        endDate = protocol_.endDate
        notes = protocol_.notes
        halfLifeValue = protocol_.halfLifeValue
        halfLifeUnitRaw = protocol_.halfLifeUnitRaw
        statusRaw = protocol_.statusRaw
        inventoryCount = protocol_.inventoryCount
        inventoryLowThreshold = protocol_.inventoryLowThreshold
        inventoryUnitLabel = protocol_.inventoryUnitLabel
        remindersEnabled = protocol_.remindersEnabled
        formDosage = protocol_.formDosage
        sortOrder = protocol_.sortOrder
    }

    func makeModel() -> CompoundProtocol {
        let decodedSchedule = scheduleData.flatMap { try? JSONDecoder().decode(DoseSchedule.self, from: $0) } ?? .daily
        let protocol_ = CompoundProtocol(
            name: name,
            category: CompoundCategory(rawValue: categoryRaw) ?? .medication,
            administrationForm: AdministrationForm(rawValue: administrationFormRaw) ?? .pill,
            doseAmount: doseAmount,
            doseUnit: DoseUnit(rawValue: doseUnitRaw) ?? .mg,
            schedule: decodedSchedule,
            startDate: startDate,
            endDate: endDate,
            notes: notes,
            halfLifeValue: halfLifeValue,
            halfLifeUnit: HalfLifeUnit(rawValue: halfLifeUnitRaw) ?? .hours,
            status: ProtocolStatus(rawValue: statusRaw) ?? .active,
            inventoryCount: inventoryCount,
            inventoryLowThreshold: inventoryLowThreshold,
            remindersEnabled: remindersEnabled,
            formDosage: formDosage,
            sortOrder: sortOrder
        )
        protocol_.id = id
        protocol_.categoryRaw = categoryRaw
        protocol_.administrationFormRaw = administrationFormRaw
        protocol_.doseUnitRaw = doseUnitRaw
        protocol_.scheduleData = scheduleData
        protocol_.halfLifeUnitRaw = halfLifeUnitRaw
        protocol_.statusRaw = statusRaw
        protocol_.inventoryUnitLabel = inventoryUnitLabel
        return protocol_
    }
}

private struct DoseLogRecord: Codable {
    var id: UUID
    var protocolID: UUID?
    var timestamp: Date
    var actualDoseAmount: Double
    var doseUnitRaw: String
    var notes: String
    var protocolName: String
    var protocolCategory: String

    init(_ log: DoseLog) {
        id = log.id
        protocolID = log.protocol_?.id
        timestamp = log.timestamp
        actualDoseAmount = log.actualDoseAmount
        doseUnitRaw = log.doseUnitRaw
        notes = log.notes
        protocolName = log.protocol_?.name ?? log.protocolName
        protocolCategory = log.protocol_?.categoryRaw ?? log.protocolCategory
    }

    func makeModel(protocol_: CompoundProtocol?) -> DoseLog {
        let log = DoseLog(
            protocol_: protocol_,
            actualDoseAmount: actualDoseAmount,
            doseUnit: DoseUnit(rawValue: doseUnitRaw) ?? .mg,
            timestamp: timestamp,
            notes: notes,
            protocolName: protocolName,
            protocolCategory: protocolCategory
        )
        log.id = id
        log.doseUnitRaw = doseUnitRaw
        return log
    }
}

private struct MediaDocumentRecord: Codable {
    var id: UUID
    var title: String
    var imageData: Data?
    var fileExtension: String?
    var dateAdded: Date

    init(_ document: MediaDocument) {
        id = document.id
        title = document.title
        imageData = document.imageData
        fileExtension = document.fileExtension
        dateAdded = document.dateAdded
    }

    func makeModel() -> MediaDocument {
        MediaDocument(id: id, title: title, imageData: imageData, fileExtension: fileExtension, dateAdded: dateAdded)
    }
}
