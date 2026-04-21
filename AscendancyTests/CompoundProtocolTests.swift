import XCTest
import SwiftData
@testable import Ascendancy

final class CompoundProtocolTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: CompoundProtocol.self, DoseLog.self, configurations: config)
        context = ModelContext(container)
    }

    override func tearDownWithError() throws {
        context = nil
        container = nil
    }

    // MARK: - Helpers

    func makeProtocol(
        schedule: DoseSchedule = .daily,
        startDate: Date = Date(),
        halfLifeValue: Double = 24.0,
        halfLifeUnit: HalfLifeUnit = .hours,
        inventory: Double = 0.0,
        lowThreshold: Double = 5.0
    ) -> CompoundProtocol {
        let p = CompoundProtocol(
            name: "Test", category: .medication, administrationForm: .pill,
            doseAmount: 10.0, doseUnit: .mg, schedule: schedule,
            startDate: startDate, halfLifeValue: halfLifeValue, halfLifeUnit: halfLifeUnit,
            inventoryCount: inventory, inventoryLowThreshold: lowThreshold
        )
        context.insert(p)
        return p
    }

    // MARK: - halfLifeInHours

    func test_halfLifeInHours_hours() {
        let p = makeProtocol(halfLifeValue: 12, halfLifeUnit: .hours)
        XCTAssertEqual(p.halfLifeInHours, 12.0)
    }

    func test_halfLifeInHours_days_convertsCorrectly() {
        let p = makeProtocol(halfLifeValue: 3, halfLifeUnit: .days)
        XCTAssertEqual(p.halfLifeInHours, 72.0)
    }

    func test_halfLifeInHours_minutes_convertsCorrectly() {
        let p = makeProtocol(halfLifeValue: 60, halfLifeUnit: .minutes)
        XCTAssertEqual(p.halfLifeInHours, 1.0)
    }

    func test_halfLifeInHours_minutesSubHour() {
        let p = makeProtocol(halfLifeValue: 30, halfLifeUnit: .minutes)
        XCTAssertEqual(p.halfLifeInHours, 0.5)
    }

    // MARK: - isLowInventory / isOutOfInventory

    func test_isLowInventory_belowThreshold() {
        let p = makeProtocol(inventory: 3.0, lowThreshold: 5.0)
        XCTAssertTrue(p.isLowInventory)
    }

    func test_isLowInventory_atThreshold() {
        let p = makeProtocol(inventory: 5.0, lowThreshold: 5.0)
        XCTAssertTrue(p.isLowInventory)
    }

    func test_isLowInventory_aboveThreshold() {
        let p = makeProtocol(inventory: 10.0, lowThreshold: 5.0)
        XCTAssertFalse(p.isLowInventory)
    }

    func test_isLowInventory_zeroCount_isFalse() {
        // isLowInventory requires inventoryCount > 0
        let p = makeProtocol(inventory: 0.0, lowThreshold: 5.0)
        XCTAssertFalse(p.isLowInventory)
    }

    func test_isOutOfInventory_atZero() {
        let p = makeProtocol(inventory: 0.0)
        XCTAssertTrue(p.isOutOfInventory)
    }

    func test_isOutOfInventory_aboveZero() {
        let p = makeProtocol(inventory: 0.1)
        XCTAssertFalse(p.isOutOfInventory)
    }

    // MARK: - nextDoseDate: daily schedule

    func test_nextDoseDate_daily_pastDoseTime_returnsTomorrow() {
        let cal = Calendar.current
        // Dose time: midnight. Query from 1 AM → midnight already passed → returns tomorrow midnight
        let midnight = cal.date(bySettingHour: 0, minute: 0, second: 0, of: Date())!
        var sched = DoseSchedule()
        sched.type = .daily
        sched.timesOfDay = [midnight]

        let p = makeProtocol(schedule: sched)
        let oneAM = cal.date(bySettingHour: 1, minute: 0, second: 0, of: Date())!
        let next = p.nextDoseDate(from: oneAM)

        XCTAssertNotNil(next)
        let tomorrow = cal.date(byAdding: .day, value: 1, to: Date())!
        XCTAssertTrue(cal.isDate(next!, inSameDayAs: tomorrow))
        let comps = cal.dateComponents([.hour, .minute], from: next!)
        XCTAssertEqual(comps.hour, 0)
        XCTAssertEqual(comps.minute, 0)
    }

    func test_nextDoseDate_daily_futureDoseTime_returnsSameDay() {
        let cal = Calendar.current
        // Dose time: 11:55 PM. Query from midnight → 11:55 PM is still in the future today
        let lateNight = cal.date(bySettingHour: 23, minute: 55, second: 0, of: Date())!
        var sched = DoseSchedule()
        sched.type = .daily
        sched.timesOfDay = [lateNight]

        let p = makeProtocol(schedule: sched)
        let midnight = cal.date(bySettingHour: 0, minute: 0, second: 0, of: Date())!
        let next = p.nextDoseDate(from: midnight)

        XCTAssertNotNil(next)
        XCTAssertTrue(cal.isDate(next!, inSameDayAs: Date()))
        let comps = cal.dateComponents([.hour, .minute], from: next!)
        XCTAssertEqual(comps.hour, 23)
        XCTAssertEqual(comps.minute, 55)
    }

    func test_nextDoseDate_daily_alwaysReturnsFutureDate() {
        let p = makeProtocol(schedule: .daily)
        let next = p.nextDoseDate(from: Date())
        XCTAssertNotNil(next)
        XCTAssertGreaterThan(next!, Date())
    }

    // MARK: - nextDoseDate: everyXDays schedule

    func test_nextDoseDate_everyXDays_returnsFutureDate() {
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -10, to: Date())!
        var sched = DoseSchedule()
        sched.type = .everyXDays
        sched.intervalDays = 3
        sched.timesOfDay = [cal.date(bySettingHour: 8, minute: 0, second: 0, of: Date())!]

        let p = makeProtocol(schedule: sched, startDate: start)
        let next = p.nextDoseDate(from: Date())

        XCTAssertNotNil(next)
        XCTAssertGreaterThan(next!, Date())
    }

    func test_nextDoseDate_everyXDays_anchoredToStartDate() {
        let cal = Calendar.current
        // Start exactly 9 days ago, interval 3 days → doses at day 0, 3, 6, 9, 12
        // Now is between day 9 and 12, so next is day 12 (3 days from now)
        let start = cal.date(bySettingHour: 8, minute: 0, second: 0,
                             of: cal.date(byAdding: .day, value: -9, to: Date())!)!
        var sched = DoseSchedule()
        sched.type = .everyXDays
        sched.intervalDays = 3
        sched.timesOfDay = [cal.date(bySettingHour: 8, minute: 0, second: 0, of: Date())!]

        let p = makeProtocol(schedule: sched, startDate: start)
        let now = cal.date(bySettingHour: 9, minute: 0, second: 0, of: Date())!  // after 8 AM today
        let next = p.nextDoseDate(from: now)

        XCTAssertNotNil(next)
        XCTAssertGreaterThan(next!, now)
        // Next should be 3 days from the last scheduled date (day 9), i.e., day 12
        let daysUntilNext = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: next!)).day ?? -1
        XCTAssertEqual(daysUntilNext, 3)
    }

    func test_nextDoseDate_everyXDays_intervalOne_isNextDay() {
        let cal = Calendar.current
        var sched = DoseSchedule()
        sched.type = .everyXDays
        sched.intervalDays = 1
        sched.timesOfDay = [cal.date(bySettingHour: 8, minute: 0, second: 0, of: Date())!]

        let p = makeProtocol(schedule: sched, startDate: cal.date(byAdding: .day, value: -5, to: Date())!)
        let next = p.nextDoseDate(from: Date())

        XCTAssertNotNil(next)
        XCTAssertGreaterThan(next!, Date())
    }

    // MARK: - nextDoseDate: specificWeekdays schedule

    func test_nextDoseDate_specificWeekdays_findsCorrectWeekday() {
        let cal = Calendar.current
        // Find the next Monday from today, then query from the Sunday before it
        var comps = DateComponents(); comps.weekday = 2  // Monday
        guard let nextMonday = cal.nextDate(after: Date(), matching: comps, matchingPolicy: .nextTimePreservingSmallerComponents) else { return }
        let sundayBefore = cal.date(byAdding: .day, value: -1, to: nextMonday)!

        var sched = DoseSchedule()
        sched.type = .specificWeekdays
        sched.weekdays = [.monday]
        sched.timesOfDay = [cal.date(bySettingHour: 8, minute: 0, second: 0, of: Date())!]

        let p = makeProtocol(schedule: sched)
        let next = p.nextDoseDate(from: sundayBefore)

        XCTAssertNotNil(next)
        XCTAssertEqual(cal.component(.weekday, from: next!), 2)  // Monday
    }

    func test_nextDoseDate_specificWeekdays_multipleDays_picksNearest() {
        let cal = Calendar.current
        // Query from a Sunday (weekday 1); schedule is Mon + Wed
        // → nearest is Monday (1 day away)
        var comps = DateComponents(); comps.weekday = 1  // Sunday
        guard let sunday = cal.nextDate(after: Date().addingTimeInterval(-86400), matching: comps, matchingPolicy: .nextTimePreservingSmallerComponents) else { return }

        var sched = DoseSchedule()
        sched.type = .specificWeekdays
        sched.weekdays = [.monday, .wednesday]
        sched.timesOfDay = []

        let p = makeProtocol(schedule: sched)
        let next = p.nextDoseDate(from: sunday)

        XCTAssertNotNil(next)
        XCTAssertEqual(cal.component(.weekday, from: next!), 2)  // Monday is closer
    }

    func test_nextDoseDate_specificWeekdays_emptySet_returnsNil() {
        var sched = DoseSchedule()
        sched.type = .specificWeekdays
        sched.weekdays = []

        let p = makeProtocol(schedule: sched)
        XCTAssertNil(p.nextDoseDate(from: Date()))
    }

    // MARK: - nextDoseDate: timesPerWeek schedule

    func test_nextDoseDate_timesPerWeek_returnsFutureDate() {
        let cal = Calendar.current
        var sched = DoseSchedule()
        sched.type = .timesPerWeek
        sched.timesPerWeek = 3
        sched.timesOfDay = [cal.date(bySettingHour: 8, minute: 0, second: 0, of: Date())!]

        let p = makeProtocol(schedule: sched, startDate: Date().addingTimeInterval(-7 * 86400))
        let next = p.nextDoseDate(from: Date())

        XCTAssertNotNil(next)
        XCTAssertGreaterThan(next!, Date())
    }

    func test_nextDoseDate_timesPerWeek_oncePer7Days_behavesLikeWeekly() {
        let cal = Calendar.current
        var sched = DoseSchedule()
        sched.type = .timesPerWeek
        sched.timesPerWeek = 1
        sched.timesOfDay = [cal.date(bySettingHour: 8, minute: 0, second: 0, of: Date())!]

        let p = makeProtocol(schedule: sched, startDate: Date().addingTimeInterval(-3 * 86400))
        let next = p.nextDoseDate(from: Date())

        XCTAssertNotNil(next)
        XCTAssertGreaterThan(next!, Date())
        // Interval should be ~7 days from anchor, so next should be within 7 days
        let daysUntil = next!.timeIntervalSince(Date()) / 86400
        XCTAssertLessThanOrEqual(daysUntil, 7.0)
    }

    // MARK: - Schedule decoding round-trip

    func test_scheduleEncoding_roundTrip() {
        var sched = DoseSchedule()
        sched.type = .specificWeekdays
        sched.weekdays = [.monday, .friday]
        sched.intervalDays = 4

        let p = makeProtocol(schedule: sched)
        let decoded = p.schedule

        XCTAssertEqual(decoded.type, .specificWeekdays)
        XCTAssertEqual(Set(decoded.weekdays), Set([Weekday.monday, Weekday.friday]))
        XCTAssertEqual(decoded.intervalDays, 4)
    }
}
