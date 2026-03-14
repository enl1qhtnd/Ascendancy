import Foundation

actor InventoryService {

    static let shared = InventoryService()

    /// Decrement protocol inventory after a dose log is added.
    /// Returns a warning if inventory is now low or zero.
    @discardableResult
    func decrementInventory(for protocol_: CompoundProtocol, dose: DoseLog) -> InventoryWarning? {
        let form = protocol_.administrationForm

        // Vials are restocked manually; do not auto-decrement on dose log.
        guard form != .vial else { return nil }

        let doseAmount = dose.actualDoseAmount

        if protocol_.formDosage > 0 {
            let fractionalUsed = doseAmount / protocol_.formDosage
            protocol_.inventoryCount = max(0, protocol_.inventoryCount - fractionalUsed)
        } else {
            switch form {
            case .pill, .capsule, .patch, .cream:
                protocol_.inventoryCount = max(0, protocol_.inventoryCount - 1)
            case .vial, .syringe, .custom:
                protocol_.inventoryCount = max(0, protocol_.inventoryCount - doseAmount)
            }
        }

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
            dosesPerDay = 1.0
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
