import Foundation

@MainActor
final class InventoryService {

    static let shared = InventoryService()

    /// Inventory units consumed by logging a dose with the given amount.
    /// Vials are restocked manually and never auto-decrement.
    func inventoryConsumption(for protocol_: CompoundProtocol, doseAmount: Double) -> Double {
        let form = protocol_.administrationForm
        guard form != .vial else { return 0 }

        if protocol_.formDosage > 0 {
            return doseAmount / protocol_.formDosage
        }

        switch form {
        case .pill, .capsule, .patch, .cream:
            return 1
        case .vial, .syringe, .custom:
            return doseAmount
        }
    }

    /// Decrement protocol inventory after a dose log is added.
    /// Returns a warning if inventory is now low or zero.
    @discardableResult
    func decrementInventory(for protocol_: CompoundProtocol, dose: DoseLog) -> InventoryWarning? {
        let consumed = inventoryConsumption(for: protocol_, doseAmount: dose.actualDoseAmount)
        guard consumed > 0 else { return nil }

        protocol_.inventoryCount = max(0, protocol_.inventoryCount - consumed)
        return inventoryWarningIfNeeded(for: protocol_)
    }

    /// Restore inventory when a dose log is deleted.
    func restoreInventory(for protocol_: CompoundProtocol, dose: DoseLog) {
        let consumed = inventoryConsumption(for: protocol_, doseAmount: dose.actualDoseAmount)
        guard consumed > 0 else { return }

        protocol_.inventoryCount += consumed
    }

    /// Apply the inventory delta when a dose log's amount is edited.
    /// Pass the pre-edit amount so count-based forms (pill/capsule) stay correct.
    @discardableResult
    func adjustInventoryOnEdit(
        for protocol_: CompoundProtocol,
        previousAmount: Double,
        updatedDose: DoseLog
    ) -> InventoryWarning? {
        let oldConsumed = inventoryConsumption(for: protocol_, doseAmount: previousAmount)
        let newConsumed = inventoryConsumption(for: protocol_, doseAmount: updatedDose.actualDoseAmount)
        let delta = newConsumed - oldConsumed
        guard delta != 0 else { return nil }

        if delta > 0 {
            protocol_.inventoryCount = max(0, protocol_.inventoryCount - delta)
        } else {
            protocol_.inventoryCount += abs(delta)
        }
        return inventoryWarningIfNeeded(for: protocol_)
    }

    private func inventoryWarningIfNeeded(for protocol_: CompoundProtocol) -> InventoryWarning? {
        if protocol_.inventoryCount == 0 {
            return .outOfStock(protocol_.name)
        } else if protocol_.isLowInventory {
            return .low(protocol_.name, protocol_.inventoryCount, protocol_.inventoryDisplayUnitLabel)
        }
        return nil
    }

    /// Add inventory (e.g. when user restocks)
    func addInventory(to protocol_: CompoundProtocol, amount: Double) {
        protocol_.inventoryCount += amount
    }

    /// Compute days of supply remaining
    func daysOfSupply(for protocol_: CompoundProtocol) -> Double? {
        let sched = protocol_.schedule
        let dosesPerDay: Double

        switch sched.type {
        case .daily:
            dosesPerDay = Double(max(1, sched.timesOfDay.count))
        case .everyXDays:
            dosesPerDay = 1.0 / Double(max(1, sched.intervalDays))
        case .specificWeekdays:
            dosesPerDay = Double(sched.weekdays.count) / 7.0
        case .timesPerWeek:
            dosesPerDay = Double(sched.timesPerWeek) / 7.0
        case .custom:
            return nil
        }

        guard dosesPerDay > 0, protocol_.doseAmount > 0 else { return nil }

        let dailyRequirement = protocol_.doseAmount * dosesPerDay

        if protocol_.formDosage > 0 {
            let totalAmount = protocol_.inventoryCount * protocol_.formDosage
            return totalAmount / dailyRequirement
        } else {
            let form = protocol_.administrationForm
            switch form {
            case .pill, .capsule, .patch, .cream:
                return protocol_.inventoryCount / dosesPerDay
            case .vial, .syringe, .custom:
                return (protocol_.inventoryCount / protocol_.doseAmount) / dosesPerDay
            }
        }
    }
}

enum InventoryWarning {
    case low(String, Double, String)
    case outOfStock(String)

    var message: String {
        switch self {
        case .low(let name, let count, let unit):
            return "\(name): Low inventory (\(count.formatted()) \(unit) remaining)"
        case .outOfStock(let name):
            return "\(name): Out of stock"
        }
    }
}
