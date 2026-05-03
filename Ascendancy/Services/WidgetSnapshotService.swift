import Foundation
import SwiftData
import WidgetKit

@MainActor
enum WidgetSnapshotService {

    static func publish(protocols: [CompoundProtocol], logs: [DoseLog], now: Date = Date()) {
        guard !AppDistribution.isRunningTests else { return }

        let snapshot = makeSnapshot(protocols: protocols, logs: logs, now: now)

        do {
            try AscendancyWidgetShared.saveSnapshot(snapshot)
            WidgetCenter.shared.reloadTimelines(ofKind: AscendancyWidgetShared.kind)
        } catch {
            print("[WidgetSnapshotService] Failed to publish widget snapshot: \(error)")
        }
    }

    static func publish(from context: ModelContext, now: Date = Date()) {
        do {
            let protocolDescriptor = FetchDescriptor<CompoundProtocol>(
                predicate: #Predicate { $0.statusRaw == "Active" },
                sortBy: CompoundProtocol.listSortDescriptors
            )
            let logDescriptor = FetchDescriptor<DoseLog>(sortBy: [
                SortDescriptor(\DoseLog.timestamp, order: .reverse)
            ])

            let protocols = try context.fetch(protocolDescriptor)
            let logs = try context.fetch(logDescriptor)
            publish(protocols: protocols, logs: logs, now: now)
        } catch {
            print("[WidgetSnapshotService] Failed to fetch widget data: \(error)")
        }
    }

    private static func makeSnapshot(protocols: [CompoundProtocol], logs: [DoseLog], now: Date) -> AscendancyWidgetSnapshot {
        let today = Calendar.current.startOfDay(for: now)
        let todayRows = DoseScheduleDayHelper.mergedRows(protocols: protocols, logs: logs, on: today)
        let pendingToday = todayRows
            .filter { !DoseScheduleDayHelper.isLogged($0.0, on: today, logs: logs) }
            .map { makeDoseSnapshot(for: $0.0, scheduledAt: $0.1, logs: logs) }

        var upcomingDoses = pendingToday
        let pendingTodayIds = Set(pendingToday.map(\.protocolId))
        for protocol_ in protocols where !pendingTodayIds.contains(protocol_.id) {
            guard let nextDate = protocol_.nextDoseDate(from: now) else { continue }
            upcomingDoses.append(makeDoseSnapshot(for: protocol_, scheduledAt: nextDate, logs: logs))
        }
        upcomingDoses.sort { $0.scheduledAt < $1.scheduledAt }

        let lowInventoryItems = protocols
            .filter { $0.isLowInventory || $0.isOutOfInventory }
            .sorted { lhs, rhs in
                let lhsRatio = lhs.inventoryCount / max(lhs.inventoryLowThreshold, 1)
                let rhsRatio = rhs.inventoryCount / max(rhs.inventoryLowThreshold, 1)
                return lhsRatio < rhsRatio
            }
            .prefix(3)
            .map { makeInventorySnapshot(for: $0) }

        return AscendancyWidgetSnapshot(
            generatedAt: now,
            activeProtocolCount: protocols.count,
            todayDoseCount: todayRows.count,
            todayLoggedCount: todayRows.filter { DoseScheduleDayHelper.isLogged($0.0, on: today, logs: logs) }.count,
            nextDose: upcomingDoses.first,
            upcomingDoses: Array(upcomingDoses.prefix(5)),
            lowInventoryItems: Array(lowInventoryItems)
        )
    }

    private static func makeDoseSnapshot(
        for protocol_: CompoundProtocol,
        scheduledAt: Date,
        logs: [DoseLog]
    ) -> AscendancyWidgetDose {
        AscendancyWidgetDose(
            protocolId: protocol_.id,
            protocolName: displayName(for: protocol_),
            categoryRaw: protocol_.categoryRaw,
            doseText: "\(protocol_.doseAmount.formatted(.number.precision(.fractionLength(0...2)))) \(protocol_.doseUnit.rawValue)",
            scheduledAt: scheduledAt,
            isLoggedToday: DoseScheduleDayHelper.isLogged(protocol_, on: scheduledAt, logs: logs)
        )
    }

    private static func makeInventorySnapshot(for protocol_: CompoundProtocol) -> AscendancyWidgetInventoryItem {
        let daysRemainingText = InventoryService.shared.daysOfSupply(for: protocol_).map { days in
            let roundedDays = max(0, Int(days.rounded(.down)))
            return roundedDays == 1 ? "1 day" : "\(roundedDays) days"
        }

        return AscendancyWidgetInventoryItem(
            protocolId: protocol_.id,
            protocolName: displayName(for: protocol_),
            categoryRaw: protocol_.categoryRaw,
            remainingText: "\(protocol_.inventoryCount.formatted(.number.precision(.fractionLength(0...1)))) \(protocol_.inventoryDisplayUnitLabel)",
            daysRemainingText: daysRemainingText
        )
    }

    private static func displayName(for protocol_: CompoundProtocol) -> String {
        let trimmedName = protocol_.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? "Unnamed protocol" : trimmedName
    }
}
