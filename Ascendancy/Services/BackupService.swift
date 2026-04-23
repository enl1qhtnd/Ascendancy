import Foundation
import SwiftData
import UniformTypeIdentifiers

enum BackupError: LocalizedError {
    case creationFailed(String)
    case restorationFailed(String)
    case invalidBackup(String)
    case fileAccessError(String)

    var errorDescription: String? {
        switch self {
        case .creationFailed(let message):
            return "Backup creation failed: \(message)"
        case .restorationFailed(let message):
            return "Backup restoration failed: \(message)"
        case .invalidBackup(let message):
            return "Invalid backup: \(message)"
        case .fileAccessError(let message):
            return "File access error: \(message)"
        }
    }
}

enum MergeStrategy {
    case replaceAll
    case merge
}

@MainActor
class BackupService {
    static let shared = BackupService()

    private init() {}

    // MARK: - Export

    func createBackup(
        context: ModelContext,
        userName: String,
        userGoal: String,
        profileImageData: Data?
    ) async throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Fetch all data
        let protocols = try context.fetch(FetchDescriptor<CompoundProtocol>())
        let logs = try context.fetch(FetchDescriptor<DoseLog>())
        let documents = try context.fetch(FetchDescriptor<MediaDocument>())

        // Create exportable models
        let exportableProtocols = protocols.map { ExportableProtocol(from: $0) }
        let exportableLogs = logs.map { ExportableDoseLog(from: $0) }
        let exportableDocuments = documents.map { ExportableMediaDocument(from: $0) }

        // Create metadata
        var metadata = BackupMetadata.current
        metadata = BackupMetadata(
            version: metadata.version,
            appVersion: metadata.appVersion,
            appBuild: metadata.appBuild,
            createdAt: metadata.createdAt,
            deviceName: metadata.deviceName,
            protocolCount: protocols.count,
            logCount: logs.count,
            documentCount: documents.count
        )

        // Encode to JSON
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let metadataData = try encoder.encode(metadata)
        let protocolsData = try encoder.encode(ProtocolsBackup(protocols: exportableProtocols))
        let logsData = try encoder.encode(LogsBackup(logs: exportableLogs))
        let documentsData = try encoder.encode(DocumentsBackup(documents: exportableDocuments))
        let profileData = try encoder.encode(ExportableProfile(
            userName: userName,
            userGoal: userGoal,
            profileImageData: profileImageData
        ))

        // Write JSON files
        try metadataData.write(to: tempDir.appendingPathComponent("metadata.json"))
        try protocolsData.write(to: tempDir.appendingPathComponent("protocols.json"))
        try logsData.write(to: tempDir.appendingPathComponent("logs.json"))
        try documentsData.write(to: tempDir.appendingPathComponent("documents.json"))
        try profileData.write(to: tempDir.appendingPathComponent("profile.json"))

        // Create media directory and copy files
        let mediaDir = tempDir.appendingPathComponent("media")
        try FileManager.default.createDirectory(at: mediaDir, withIntermediateDirectories: true)

        for document in documents {
            if let data = document.imageData, let fileName = ExportableMediaDocument(from: document).mediaFileName {
                let fileURL = mediaDir.appendingPathComponent(fileName)
                try data.write(to: fileURL)
            }
        }

        // Create ZIP archive
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let zipFileName = "ascendancy_backup_\(timestamp).zip"
        let zipURL = FileManager.default.temporaryDirectory.appendingPathComponent(zipFileName)

        try await zipDirectory(at: tempDir, to: zipURL)

        return zipURL
    }

    // MARK: - Import

    func validateBackup(at url: URL) async throws -> BackupMetadata {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Extract ZIP
        try await unzipFile(at: url, to: tempDir)

        // Read and validate metadata
        let metadataURL = tempDir.appendingPathComponent("metadata.json")
        guard FileManager.default.fileExists(atPath: metadataURL.path) else {
            throw BackupError.invalidBackup("Missing metadata.json")
        }

        let metadataData = try Data(contentsOf: metadataURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let metadata = try decoder.decode(BackupMetadata.self, from: metadataData)

        // Validate required files
        let requiredFiles = ["protocols.json", "logs.json", "documents.json", "profile.json"]
        for file in requiredFiles {
            let fileURL = tempDir.appendingPathComponent(file)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                throw BackupError.invalidBackup("Missing \(file)")
            }
        }

        return metadata
    }

    func restoreBackup(
        from url: URL,
        context: ModelContext,
        strategy: MergeStrategy,
        onProfileRestore: @escaping (ExportableProfile) -> Void
    ) async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Extract ZIP
        try await unzipFile(at: url, to: tempDir)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Read all JSON files
        let protocolsData = try Data(contentsOf: tempDir.appendingPathComponent("protocols.json"))
        let logsData = try Data(contentsOf: tempDir.appendingPathComponent("logs.json"))
        let documentsData = try Data(contentsOf: tempDir.appendingPathComponent("documents.json"))
        let profileData = try Data(contentsOf: tempDir.appendingPathComponent("profile.json"))

        let protocolsBackup = try decoder.decode(ProtocolsBackup.self, from: protocolsData)
        let logsBackup = try decoder.decode(LogsBackup.self, from: logsData)
        let documentsBackup = try decoder.decode(DocumentsBackup.self, from: documentsData)
        let profile = try decoder.decode(ExportableProfile.self, from: profileData)

        // Clear existing data if replace strategy
        if strategy == .replaceAll {
            try clearAllData(context: context)
        }

        // Restore protocols
        var protocolMap: [UUID: CompoundProtocol] = [:]
        for exportableProtocol in protocolsBackup.protocols {
            // Check if protocol already exists (for merge strategy)
            if strategy == .merge {
                let descriptor = FetchDescriptor<CompoundProtocol>(
                    predicate: #Predicate { $0.id == exportableProtocol.id }
                )
                if let existing = try context.fetch(descriptor).first {
                    protocolMap[exportableProtocol.id] = existing
                    continue
                }
            }

            let proto = exportableProtocol.toProtocol()
            context.insert(proto)
            protocolMap[proto.id] = proto
        }

        // Restore logs
        for exportableLog in logsBackup.logs {
            // Check if log already exists (for merge strategy)
            if strategy == .merge {
                let descriptor = FetchDescriptor<DoseLog>(
                    predicate: #Predicate { $0.id == exportableLog.id }
                )
                if try context.fetch(descriptor).first != nil {
                    continue
                }
            }

            guard let proto = protocolMap[exportableLog.protocolId] else {
                continue // Skip logs without matching protocol
            }

            let log = exportableLog.toDoseLog(protocol_: proto)
            context.insert(log)
        }

        // Restore documents
        let mediaDir = tempDir.appendingPathComponent("media")
        for exportableDoc in documentsBackup.documents {
            // Check if document already exists (for merge strategy)
            if strategy == .merge {
                let descriptor = FetchDescriptor<MediaDocument>(
                    predicate: #Predicate { $0.id == exportableDoc.id }
                )
                if try context.fetch(descriptor).first != nil {
                    continue
                }
            }

            var imageData: Data? = nil
            if let fileName = exportableDoc.mediaFileName {
                let fileURL = mediaDir.appendingPathComponent(fileName)
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    imageData = try? Data(contentsOf: fileURL)
                }
            }

            let doc = exportableDoc.toMediaDocument(imageData: imageData)
            context.insert(doc)
        }

        // Save context
        try context.save()

        // Restore profile (always replace)
        onProfileRestore(profile)
    }

    // MARK: - Private Helpers

    private func clearAllData(context: ModelContext) throws {
        // Delete all protocols (cascade will delete logs)
        try context.delete(model: CompoundProtocol.self)
        try context.delete(model: DoseLog.self)
        try context.delete(model: MediaDocument.self)
        try context.save()
    }

    private func zipDirectory(at sourceURL: URL, to destinationURL: URL) async throws {
        // Remove existing file if present
        try? FileManager.default.removeItem(at: destinationURL)

        // Use Foundation's Archive API (iOS 16+)
        let coordinator = NSFileCoordinator()
        var coordinatorError: NSError?

        coordinator.coordinate(readingItemAt: sourceURL, options: [.forUploading], error: &coordinatorError) { zipURL in
            do {
                try FileManager.default.copyItem(at: zipURL, to: destinationURL)
            } catch {
                coordinatorError = error as NSError
            }
        }

        if let error = coordinatorError {
            throw BackupError.creationFailed("Failed to create ZIP: \(error.localizedDescription)")
        }
    }

    private func unzipFile(at sourceURL: URL, to destinationURL: URL) async throws {
        let coordinator = NSFileCoordinator()
        var coordinatorError: NSError?

        coordinator.coordinate(readingItemAt: sourceURL, options: [], error: &coordinatorError) { url in
            do {
                try FileManager.default.unzipItem(at: url, to: destinationURL)
            } catch {
                coordinatorError = error as NSError
            }
        }

        if let error = coordinatorError {
            throw BackupError.restorationFailed("Failed to extract ZIP: \(error.localizedDescription)")
        }
    }
}

// MARK: - FileManager ZIP Extension

extension FileManager {
    func unzipItem(at sourceURL: URL, to destinationURL: URL) throws {
        // For iOS 16+, we can use the built-in unarchiving
        // This is a simplified implementation - in production you might want to use a library like ZIPFoundation
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", sourceURL.path, "-d", destinationURL.path]

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw BackupError.fileAccessError("Failed to extract archive")
        }
    }
}
