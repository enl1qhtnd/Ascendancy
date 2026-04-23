import Foundation
import SwiftData

// MARK: - Backup Metadata

struct BackupMetadata: Codable {
    let version: String
    let appVersion: String
    let appBuild: String
    let createdAt: Date
    let deviceName: String
    let protocolCount: Int
    let logCount: Int
    let documentCount: Int

    static var current: BackupMetadata {
        BackupMetadata(
            version: "1.0",
            appVersion: "1.4",
            appBuild: "5",
            createdAt: Date(),
            deviceName: UIDevice.current.name,
            protocolCount: 0,
            logCount: 0,
            documentCount: 0
        )
    }
}

// MARK: - Exportable Protocol

struct ExportableProtocol: Codable {
    let id: UUID
    let name: String
    let categoryRaw: String
    let administrationFormRaw: String
    let doseAmount: Double
    let doseUnitRaw: String
    let scheduleData: Data?
    let startDate: Date
    let endDate: Date?
    let notes: String
    let halfLifeValue: Double
    let halfLifeUnitRaw: String
    let statusRaw: String
    let inventoryCount: Double
    let inventoryLowThreshold: Double
    let inventoryUnitLabel: String
    let remindersEnabled: Bool
    let formDosage: Double
    let sortOrder: Int
    let doseLogIds: [UUID]

    init(from protocol_: CompoundProtocol) {
        self.id = protocol_.id
        self.name = protocol_.name
        self.categoryRaw = protocol_.categoryRaw
        self.administrationFormRaw = protocol_.administrationFormRaw
        self.doseAmount = protocol_.doseAmount
        self.doseUnitRaw = protocol_.doseUnitRaw
        self.scheduleData = protocol_.scheduleData
        self.startDate = protocol_.startDate
        self.endDate = protocol_.endDate
        self.notes = protocol_.notes
        self.halfLifeValue = protocol_.halfLifeValue
        self.halfLifeUnitRaw = protocol_.halfLifeUnitRaw
        self.statusRaw = protocol_.statusRaw
        self.inventoryCount = protocol_.inventoryCount
        self.inventoryLowThreshold = protocol_.inventoryLowThreshold
        self.inventoryUnitLabel = protocol_.inventoryUnitLabel
        self.remindersEnabled = protocol_.remindersEnabled
        self.formDosage = protocol_.formDosage
        self.sortOrder = protocol_.sortOrder
        self.doseLogIds = protocol_.doseLogs.map { $0.id }
    }

    func toProtocol() -> CompoundProtocol {
        let category = CompoundCategory(rawValue: categoryRaw) ?? .medication
        let form = AdministrationForm(rawValue: administrationFormRaw) ?? .pill
        let unit = DoseUnit(rawValue: doseUnitRaw) ?? .mg
        let halfLifeUnit = HalfLifeUnit(rawValue: halfLifeUnitRaw) ?? .hours
        let status = ProtocolStatus(rawValue: statusRaw) ?? .active

        var schedule = DoseSchedule.daily
        if let data = scheduleData {
            schedule = (try? JSONDecoder().decode(DoseSchedule.self, from: data)) ?? .daily
        }

        let proto = CompoundProtocol(
            name: name,
            category: category,
            administrationForm: form,
            doseAmount: doseAmount,
            doseUnit: unit,
            schedule: schedule,
            startDate: startDate,
            endDate: endDate,
            notes: notes,
            halfLifeValue: halfLifeValue,
            halfLifeUnit: halfLifeUnit,
            status: status,
            inventoryCount: inventoryCount,
            inventoryLowThreshold: inventoryLowThreshold,
            remindersEnabled: remindersEnabled,
            formDosage: formDosage,
            sortOrder: sortOrder
        )

        // Override the generated UUID with the original
        proto.id = id
        proto.inventoryUnitLabel = inventoryUnitLabel

        return proto
    }
}

// MARK: - Exportable Dose Log

struct ExportableDoseLog: Codable {
    let id: UUID
    let timestamp: Date
    let actualDoseAmount: Double
    let doseUnitRaw: String
    let notes: String
    let protocolName: String
    let protocolCategory: String
    let protocolId: UUID

    init(from log: DoseLog) {
        self.id = log.id
        self.timestamp = log.timestamp
        self.actualDoseAmount = log.actualDoseAmount
        self.doseUnitRaw = log.doseUnitRaw
        self.notes = log.notes
        self.protocolName = log.protocolName
        self.protocolCategory = log.protocolCategory
        self.protocolId = log.protocol_?.id ?? UUID()
    }

    func toDoseLog(protocol_: CompoundProtocol?) -> DoseLog {
        let unit = DoseUnit(rawValue: doseUnitRaw) ?? .mg

        guard let proto = protocol_ else {
            fatalError("Cannot create DoseLog without protocol reference")
        }

        let log = DoseLog(
            protocol_: proto,
            actualDoseAmount: actualDoseAmount,
            doseUnit: unit,
            timestamp: timestamp,
            notes: notes
        )

        // Override the generated UUID with the original
        log.id = id

        return log
    }
}

// MARK: - Exportable Media Document

struct ExportableMediaDocument: Codable {
    let id: UUID
    let title: String
    let fileExtension: String?
    let dateAdded: Date
    let mediaFileName: String?

    init(from document: MediaDocument) {
        self.id = document.id
        self.title = document.title
        self.fileExtension = document.fileExtension
        self.dateAdded = document.dateAdded
        self.mediaFileName = document.imageData != nil ? "\(document.id.uuidString).\(document.fileExtension ?? "dat")" : nil
    }

    func toMediaDocument(imageData: Data?) -> MediaDocument {
        let doc = MediaDocument(
            id: id,
            title: title,
            imageData: imageData,
            fileExtension: fileExtension,
            dateAdded: dateAdded
        )
        return doc
    }
}

// MARK: - Exportable Profile

struct ExportableProfile: Codable {
    let userName: String
    let userGoal: String
    let profileImageData: Data?

    init(userName: String, userGoal: String, profileImageData: Data?) {
        self.userName = userName
        self.userGoal = userGoal
        self.profileImageData = profileImageData
    }
}

// MARK: - Backup Container Structures

struct ProtocolsBackup: Codable {
    let protocols: [ExportableProtocol]
}

struct LogsBackup: Codable {
    let logs: [ExportableDoseLog]
}

struct DocumentsBackup: Codable {
    let documents: [ExportableMediaDocument]
}
