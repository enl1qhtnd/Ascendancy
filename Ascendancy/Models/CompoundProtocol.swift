import Foundation
import SwiftData
import SwiftUI

// MARK: - Supporting Enums

enum CompoundCategory: String, Codable, CaseIterable {
    case medication = "Medication"
    case peptide = "Peptide"
    case trt = "TRT"
    case custom = "Custom"
    
    var icon: String {
        switch self {
        case .medication: return "pills.fill"
        case .peptide: return "syringe.fill"
        case .trt: return "cross.vial.fill"
        case .custom: return "testtube.2"
        }
    }
    
    var color: String {
        switch self {
        case .medication: return "lightBlue"
        case .peptide: return "white"
        case .trt: return "darkBlue"
        case .custom: return "teal"
        }
    }
    
    /// Canonical SwiftUI Color for all UI rendering
    var uiColor: Color {
        switch self {
        case .medication: return Color(red: 0.45, green: 0.75, blue: 1.0)    // light blue
        case .peptide:    return Color(white: 0.92)                           // near white
        case .trt:        return Color(red: 0.15, green: 0.30, blue: 0.70)   // dark blue
        case .custom:     return Color(red: 0.2, green: 0.8, blue: 0.75)     // teal
        }
    }
}

enum AdministrationForm: String, Codable, CaseIterable {
    case vial = "Vial"
    case pill = "Pill"
    case capsule = "Capsule"
    case syringe = "Syringe"
    case patch = "Patch"
    case cream = "Cream"
    case custom = "Custom"
    
    var icon: String {
        switch self {
        case .vial: return "cross.vial.fill"
        case .pill: return "pills.fill"
        case .capsule: return "capsule.fill"
        case .syringe: return "syringe.fill"
        case .patch: return "bandage.fill"
        case .cream: return "drop.fill"
        case .custom: return "square.grid.2x2.fill"
        }
    }

    var inventorySingularLabel: String {
        switch self {
        case .vial: return "vial"
        case .pill: return "pill"
        case .capsule: return "capsule"
        case .syringe: return "syringe"
        case .patch: return "patch"
        case .cream: return "cream"
        case .custom: return "unit"
        }
    }

    var inventoryPluralLabel: String {
        switch self {
        case .vial: return "vials"
        case .pill: return "pills"
        case .capsule: return "capsules"
        case .syringe: return "syringes"
        case .patch: return "patches"
        case .cream: return "creams"
        case .custom: return "units"
        }
    }
}

enum DoseUnit: String, Codable, CaseIterable {
    case mg = "mg"
    case mL = "mL"
    case IU = "IU"
    case mcg = "mcg"
    case g = "g"
}

enum HalfLifeUnit: String, Codable, CaseIterable {
    case minutes = "minutes"
    case hours = "hours"
    case days = "days"
    
    var toHours: Double {
        switch self {
        case .minutes: return 1.0 / 60.0
        case .hours: return 1.0
        case .days: return 24.0
        }
    }
}

enum ProtocolStatus: String, Codable, CaseIterable {
    case active = "Active"
    case paused = "Paused"
    case completed = "Completed"
    case archived = "Archived"
    
    var color: String {
        switch self {
        case .active: return "green"
        case .paused: return "yellow"
        case .completed: return "blue"
        case .archived: return "gray"
        }
    }
}

enum ScheduleType: String, Codable, CaseIterable {
    case daily = "Daily"
    case everyXDays = "Every X Days"
    case specificWeekdays = "Specific Weekdays"
    case timesPerWeek = "Times Per Week"
    case custom = "Custom"
}

enum Weekday: Int, Codable, CaseIterable, Identifiable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday
    
    var id: Int { rawValue }
    
    var short: String {
        switch self {
        case .sunday: return "Su"
        case .monday: return "Mo"
        case .tuesday: return "Tu"
        case .wednesday: return "We"
        case .thursday: return "Th"
        case .friday: return "Fr"
        case .saturday: return "Sa"
        }
    }
    
    var full: String {
        switch self {
        case .sunday: return "Sunday"
        case .monday: return "Monday"
        case .tuesday: return "Tuesday"
        case .wednesday: return "Wednesday"
        case .thursday: return "Thursday"
        case .friday: return "Friday"
        case .saturday: return "Saturday"
        }
    }
}

// MARK: - Schedule Model (Codable wrapper stored as JSON)

struct DoseSchedule: Codable {
    var type: ScheduleType = .daily
    var intervalDays: Int = 1           // For everyXDays
    var weekdays: [Weekday] = []        // For specificWeekdays
    var timesPerWeek: Int = 3           // For timesPerWeek
    var timesOfDay: [Date] = []         // Time component(s) only
    var customNotes: String = ""
    
    static var daily: DoseSchedule {
        var s = DoseSchedule()
        s.type = .daily
        s.timesOfDay = [Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date())!]
        return s
    }
    
    static var everyOtherDay: DoseSchedule {
        var s = DoseSchedule()
        s.type = .everyXDays
        s.intervalDays = 2
        s.timesOfDay = [Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date())!]
        return s
    }
    
    static var mondayWednesdayFriday: DoseSchedule {
        var s = DoseSchedule()
        s.type = .specificWeekdays
        s.weekdays = [.monday, .wednesday, .friday]
        s.timesOfDay = [Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date())!]
        return s
    }
    
    var description: String {
        switch type {
        case .daily:
            return "Daily"
        case .everyXDays:
            return "Every \(intervalDays) days"
        case .specificWeekdays:
            let days = weekdays.sorted { $0.rawValue < $1.rawValue }.map { $0.short }.joined(separator: ", ")
            return days.isEmpty ? "Specific days" : days
        case .timesPerWeek:
            return "\(timesPerWeek)x per week"
        case .custom:
            return customNotes.isEmpty ? "Custom" : customNotes
        }
    }
}

// MARK: - CompoundProtocol SwiftData Model

@Model
final class CompoundProtocol {
    var id: UUID = UUID()
    var name: String = ""
    var categoryRaw: String = CompoundCategory.medication.rawValue
    var administrationFormRaw: String = AdministrationForm.pill.rawValue
    var doseAmount: Double = 0.0
    var doseUnitRaw: String = DoseUnit.mg.rawValue
    var scheduleData: Data? // Encoded DoseSchedule
    var startDate: Date = Date()
    var endDate: Date? = nil
    var notes: String = ""
    var halfLifeValue: Double = 24.0
    var halfLifeUnitRaw: String = HalfLifeUnit.hours.rawValue
    var statusRaw: String = ProtocolStatus.active.rawValue
    
    // Inventory
    var inventoryCount: Double = 0.0
    var inventoryLowThreshold: Double = 5.0
    var inventoryUnitLabel: String = ""
    
    // Reminders enabled
    var remindersEnabled: Bool = true
    
    // Amount per form (e.g. 40mg per vial)
    var formDosage: Double = 0.0
    
    @Relationship(deleteRule: .cascade)
    var doseLogs: [DoseLog] = []
    
    init(
        name: String,
        category: CompoundCategory,
        administrationForm: AdministrationForm,
        doseAmount: Double,
        doseUnit: DoseUnit,
        schedule: DoseSchedule,
        startDate: Date = Date(),
        endDate: Date? = nil,
        notes: String = "",
        halfLifeValue: Double = 24.0,
        halfLifeUnit: HalfLifeUnit = .hours,
        status: ProtocolStatus = .active,
        inventoryCount: Double = 0,
        inventoryLowThreshold: Double = 5,
        remindersEnabled: Bool = true,
        formDosage: Double = 0.0
    ) {
        self.id = UUID()
        self.name = name
        self.categoryRaw = category.rawValue
        self.administrationFormRaw = administrationForm.rawValue
        self.doseAmount = doseAmount
        self.doseUnitRaw = doseUnit.rawValue
        self.startDate = startDate
        self.endDate = endDate
        self.notes = notes
        self.halfLifeValue = halfLifeValue
        self.halfLifeUnitRaw = halfLifeUnit.rawValue
        self.statusRaw = status.rawValue
        self.inventoryCount = inventoryCount
        self.inventoryLowThreshold = inventoryLowThreshold
        self.inventoryUnitLabel = administrationForm.inventoryPluralLabel
        self.remindersEnabled = remindersEnabled
        self.formDosage = formDosage
        do {
            self.scheduleData = try JSONEncoder().encode(schedule)
        } catch {
            print("[CompoundProtocol] Failed to encode schedule: \(error)")
            self.scheduleData = nil
        }
    }
    
    // MARK: - Computed Properties
    
    var category: CompoundCategory {
        get { CompoundCategory(rawValue: categoryRaw) ?? .medication }
        set { categoryRaw = newValue.rawValue }
    }
    
    var administrationForm: AdministrationForm {
        get { AdministrationForm(rawValue: administrationFormRaw) ?? .pill }
        set { administrationFormRaw = newValue.rawValue }
    }
    
    var doseUnit: DoseUnit {
        get { DoseUnit(rawValue: doseUnitRaw) ?? .mg }
        set { doseUnitRaw = newValue.rawValue }
    }
    
    var halfLifeUnit: HalfLifeUnit {
        get { HalfLifeUnit(rawValue: halfLifeUnitRaw) ?? .hours }
        set { halfLifeUnitRaw = newValue.rawValue }
    }
    
    var status: ProtocolStatus {
        get { ProtocolStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }
    
    var schedule: DoseSchedule {
        get {
            guard let data = scheduleData else { return .daily }
            do {
                return try JSONDecoder().decode(DoseSchedule.self, from: data)
            } catch {
                print("[CompoundProtocol] Failed to decode schedule: \(error)")
                return .daily
            }
        }
        set {
            do {
                scheduleData = try JSONEncoder().encode(newValue)
            } catch {
                print("[CompoundProtocol] Failed to encode schedule: \(error)")
            }
        }
    }
    
    var halfLifeInHours: Double {
        halfLifeValue * halfLifeUnit.toHours
    }
    
    var isLowInventory: Bool {
        inventoryCount <= inventoryLowThreshold && inventoryCount > 0
    }

    var isOutOfInventory: Bool {
        inventoryCount == 0
    }

    var inventoryDisplayUnitLabel: String {
        inventoryUnitLabel.isEmpty ? administrationForm.inventoryPluralLabel : inventoryUnitLabel
    }

    var restockButtonTitle: String {
        "Restock \(administrationForm.inventoryPluralLabel.capitalized)"
    }

    var sortedLogs: [DoseLog] {
        doseLogs.sorted { $0.timestamp > $1.timestamp }
    }
    
    var lastLoggedDate: Date? {
        sortedLogs.first?.timestamp
    }
    
    func nextDoseDate(from date: Date = Date()) -> Date? {
        let sched = schedule
        let cal = Calendar.current

        // Apply the stored dose time (hour/minute) to any candidate date.
        func applyDoseTime(to base: Date) -> Date {
            let src = sched.timesOfDay.first
                ?? cal.date(bySettingHour: 8, minute: 0, second: 0, of: base)!
            let comps = cal.dateComponents([.hour, .minute], from: src)
            return cal.date(bySettingHour: comps.hour ?? 8,
                            minute: comps.minute ?? 0,
                            second: 0, of: base) ?? base
        }

        switch sched.type {
        case .daily:
            var candidate = applyDoseTime(to: date)
            if candidate <= date {
                candidate = cal.date(byAdding: .day, value: 1, to: candidate)
                    .map { applyDoseTime(to: $0) } ?? candidate
            }
            return candidate

        case .everyXDays:
            // Calculate next dose by advancing from last logged dose (or start date)
            // by the interval, ensuring the result is always in the future.
            let base = lastLoggedDate ?? startDate
            let interval = max(1, sched.intervalDays)
            var candidate = base
            // Advance in interval-sized steps until we find a future date
            for _ in 0..<365 { // safety limit to prevent infinite loop
                guard let next = cal.date(byAdding: .day, value: interval, to: candidate) else { return nil }
                candidate = next
                let result = applyDoseTime(to: candidate)
                if result > date { return result }
            }
            return nil

        case .specificWeekdays:
            let targetWeekdays = Set(sched.weekdays.map { $0.rawValue })
            guard !targetWeekdays.isEmpty else { return nil }
            // Search forward up to 14 days for the next matching weekday
            for offset in 1...14 {
                guard let candidate = cal.date(byAdding: .day, value: offset, to: date) else { continue }
                let weekday = cal.component(.weekday, from: candidate)
                if targetWeekdays.contains(weekday) {
                    return applyDoseTime(to: candidate)
                }
            }
            return nil

        case .timesPerWeek:
            // Distribute doses evenly: e.g., 3x/week → every ~2.33 days, 5x/week → every ~1.4 days
            let timesPerWeek = max(1, sched.timesPerWeek)
            let intervalSeconds = (7.0 / Double(timesPerWeek)) * 86400.0
            let base = lastLoggedDate ?? startDate
            
            // Calculate how many intervals have passed since base
            let secondsSinceBase = date.timeIntervalSince(base)
            guard secondsSinceBase >= 0 else {
                // date is before base, return first scheduled dose after base
                return applyDoseTime(to: base)
            }
            
            // Find the next interval boundary after `date`
            let intervalsElapsed = floor(secondsSinceBase / intervalSeconds)
            var nextIntervalIndex = intervalsElapsed + 1
            
            // Advance from base by successive intervals until we find a future date
            for _ in 0..<365 { // safety limit
                let offsetSeconds = nextIntervalIndex * intervalSeconds
                guard let nextDate = cal.date(byAdding: .second, value: Int(offsetSeconds), to: base) else { return nil }
                let result = applyDoseTime(to: nextDate)
                if result > date { return result }
                nextIntervalIndex += 1
            }
            return nil

        case .custom:
            // Custom schedules use the same interval logic as everyXDays,
            // defaulting to daily if no interval is specified.
            let base = lastLoggedDate ?? startDate
            let interval = max(1, sched.intervalDays)
            var candidate = base
            for _ in 0..<365 {
                guard let next = cal.date(byAdding: .day, value: interval, to: candidate) else { return nil }
                candidate = next
                let result = applyDoseTime(to: candidate)
                if result > date { return result }
            }
            return nil
        }
    }

    func refreshInventoryUnitLabel() {
        inventoryUnitLabel = administrationForm.inventoryPluralLabel
    }
}
