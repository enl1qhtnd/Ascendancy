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

    /// Locale-aware very short weekday label for schedule summaries.
    var localizedShort: String {
        let cal = Calendar.current
        var comps = DateComponents()
        comps.weekday = rawValue
        guard let d = cal.nextDate(
            after: Date().addingTimeInterval(-86400 * 21),
            matching: comps,
            matchingPolicy: .nextTimePreservingSmallerComponents
        ) else { return short }
        return d.formatted(.dateTime.weekday(.narrow))
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
        s.timesOfDay = [Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()]
        return s
    }
    
    static var everyOtherDay: DoseSchedule {
        var s = DoseSchedule()
        s.type = .everyXDays
        s.intervalDays = 2
        s.timesOfDay = [Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()]
        return s
    }
    
    static var mondayWednesdayFriday: DoseSchedule {
        var s = DoseSchedule()
        s.type = .specificWeekdays
        s.weekdays = [.monday, .wednesday, .friday]
        s.timesOfDay = [Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()]
        return s
    }
    
    var description: String {
        switch type {
        case .daily:
            return String(localized: "Daily")
        case .everyXDays:
            return String(localized: "Every \(intervalDays) days")
        case .specificWeekdays:
            let days = weekdays.sorted { $0.rawValue < $1.rawValue }.map { $0.localizedShort }.joined(separator: ", ")
            return days.isEmpty ? String(localized: "Specific days") : days
        case .timesPerWeek:
            return String(localized: "\(timesPerWeek)x per week")
        case .custom:
            return customNotes.isEmpty ? String(localized: "Custom") : customNotes
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
    
    /// User-defined list order (lower = earlier). Renumbered by migration when needed.
    var sortOrder: Int = 0
    
    @Relationship(deleteRule: .cascade)
    var doseLogs: [DoseLog]? = []
    
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
        formDosage: Double = 0.0,
        sortOrder: Int = 0
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
        self.sortOrder = sortOrder
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
        let plural = administrationForm.inventoryPluralLabel
        let capitalized = plural.prefix(1).uppercased() + plural.dropFirst()
        return String(localized: "Restock \(capitalized)")
    }

    var sortedLogs: [DoseLog] {
        (doseLogs ?? []).sorted { $0.timestamp > $1.timestamp }
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
                ?? cal.date(bySettingHour: 8, minute: 0, second: 0, of: base)
                ?? base
            let comps = cal.dateComponents([.hour, .minute], from: src)
            return cal.date(bySettingHour: comps.hour ?? 8,
                            minute: comps.minute ?? 0,
                            second: 0, of: base) ?? base
        }

        // Interval-based schedules stay anchored to the protocol start date so
        // edited or incorrectly logged doses do not shift future scheduled times.
        func nextAnchoredIntervalDate(intervalDays: Int) -> Date? {
            let interval = max(1, intervalDays)
            let anchor = applyDoseTime(to: startDate)
            if anchor > date { return anchor }

            let anchorDay = cal.startOfDay(for: anchor)
            let queryDay = cal.startOfDay(for: date)
            let daysSinceAnchor = cal.dateComponents([.day], from: anchorDay, to: queryDay).day ?? 0
            let intervalsElapsed = max(0, daysSinceAnchor / interval)
            var candidate = cal.date(byAdding: .day, value: intervalsElapsed * interval, to: anchor) ?? anchor

            if candidate <= date {
                candidate = cal.date(byAdding: .day, value: interval, to: candidate) ?? candidate
            }
            return candidate
        }

        func nextAnchoredWeeklySlot(timesPerWeek: Int) -> Date? {
            let anchor = applyDoseTime(to: startDate)
            if anchor > date { return anchor }

            let clampedTimesPerWeek = max(1, timesPerWeek)
            let intervalSeconds = (7.0 / Double(clampedTimesPerWeek)) * 86400.0
            let secondsSinceAnchor = date.timeIntervalSince(anchor)
            let nextIntervalIndex = max(0, Int(floor(secondsSinceAnchor / intervalSeconds)) + 1)

            for offset in nextIntervalIndex...(nextIntervalIndex + 365) {
                guard let candidate = cal.date(byAdding: .second, value: Int(Double(offset) * intervalSeconds), to: anchor) else {
                    return nil
                }
                if candidate > date { return candidate }
            }
            return nil
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
            return nextAnchoredIntervalDate(intervalDays: sched.intervalDays)

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
            return nextAnchoredWeeklySlot(timesPerWeek: sched.timesPerWeek)

        case .custom:
            return nextAnchoredIntervalDate(intervalDays: sched.intervalDays)
        }
    }

    func refreshInventoryUnitLabel() {
        inventoryUnitLabel = administrationForm.inventoryPluralLabel
    }
}

extension CompoundProtocol {
    /// Stable ordering for lists: user order, then name.
    static let listSortDescriptors: [SortDescriptor<CompoundProtocol>] = [
        SortDescriptor(\CompoundProtocol.sortOrder),
        SortDescriptor(\CompoundProtocol.name)
    ]

    /// Cached stable level info (recalculated when logs change)
    private static var stableLevelCache: [UUID: (logsCount: Int, info: StableLevelInfo)] = [:]

    func cachedStableLevelInfo() -> StableLevelInfo {
        let logs = doseLogs ?? []
        let logsCount = logs.count
        if let cached = Self.stableLevelCache[id], cached.logsCount == logsCount {
            return cached.info
        }
        let info = PharmacokineticsEngine.stableLevelInfo(for: self, logs: logs)
        Self.stableLevelCache[id] = (logsCount, info)
        return info
    }

    /// Clear the stable level cache for this protocol
    func clearStableLevelCache() {
        Self.stableLevelCache.removeValue(forKey: id)
    }
}
