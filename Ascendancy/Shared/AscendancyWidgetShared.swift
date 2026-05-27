import Foundation

enum AscendancyWidgetShared {
    static let kind = "AscendancyWidget"

    static var appGroupIdentifier: String {
        AppGroupSupport.appGroupIdentifier
    }

    static func loadSnapshot() -> AscendancyWidgetSnapshot? {
        AppGroupSupport.loadWidgetSnapshot()
    }

    static func saveSnapshot(_ snapshot: AscendancyWidgetSnapshot) throws {
        try AppGroupSupport.saveWidgetSnapshot(snapshot)
    }
}

enum WidgetSnapshotError: LocalizedError {
    case missingAppGroupContainer(String)

    var errorDescription: String? {
        switch self {
        case .missingAppGroupContainer(let identifier):
            "Missing app group container: \(identifier)"
        }
    }
}

struct AscendancyWidgetSnapshot: Codable, Equatable {
    var generatedAt: Date
    var activeProtocolCount: Int
    var todayDoseCount: Int
    var todayLoggedCount: Int
    var nextDose: AscendancyWidgetDose?
    var upcomingDoses: [AscendancyWidgetDose]
    var lowInventoryItems: [AscendancyWidgetInventoryItem]

    static var preview: AscendancyWidgetSnapshot {
        let now = Date()
        let next = Calendar.current.date(byAdding: .hour, value: 2, to: now) ?? now
        return AscendancyWidgetSnapshot(
            generatedAt: now,
            activeProtocolCount: 3,
            todayDoseCount: 4,
            todayLoggedCount: 2,
            nextDose: AscendancyWidgetDose(
                protocolId: UUID(),
                protocolName: "BPC-157",
                categoryRaw: "Peptide",
                doseText: "250 mcg",
                scheduledAt: next,
                isLoggedToday: false
            ),
            upcomingDoses: [
                AscendancyWidgetDose(
                    protocolId: UUID(),
                    protocolName: "BPC-157",
                    categoryRaw: "Peptide",
                    doseText: "250 mcg",
                    scheduledAt: next,
                    isLoggedToday: false
                ),
                AscendancyWidgetDose(
                    protocolId: UUID(),
                    protocolName: "Vitamin D3",
                    categoryRaw: "Medication",
                    doseText: "5000 IU",
                    scheduledAt: Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now,
                    isLoggedToday: false
                )
            ],
            lowInventoryItems: [
                AscendancyWidgetInventoryItem(
                    protocolId: UUID(),
                    protocolName: "Omega 3",
                    categoryRaw: "Medication",
                    remainingText: "4 capsules",
                    daysRemainingText: "4 days"
                )
            ]
        )
    }
}

struct AscendancyWidgetDose: Codable, Equatable, Identifiable {
    var id: String { "\(protocolId.uuidString)-\(scheduledAt.timeIntervalSince1970)" }

    var protocolId: UUID
    var protocolName: String
    var categoryRaw: String
    var doseText: String
    var scheduledAt: Date
    var isLoggedToday: Bool
}

struct AscendancyWidgetInventoryItem: Codable, Equatable, Identifiable {
    var id: UUID { protocolId }

    var protocolId: UUID
    var protocolName: String
    var categoryRaw: String
    var remainingText: String
    var daysRemainingText: String?
}
