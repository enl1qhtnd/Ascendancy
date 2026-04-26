import XCTest
import SwiftData
@testable import Ascendancy

final class DoseScheduleDayHelperTests: XCTestCase {

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

    func makeProtocol(schedule: DoseSchedule = .daily) -> CompoundProtocol {
        let p = CompoundProtocol(
            name: "Test \(UUID().uuidString.prefix(4))",
            category: .medication, administrationForm: .pill,
            doseAmount: 10.0, doseUnit: .mg, schedule: schedule
        )
        context.insert(p)
        try? context.save()
        return p
    }

    func makeLog(for p: CompoundProtocol, on date: Date) -> DoseLog {
        let log = DoseLog(protocol_: p, actualDoseAmount: 10.0, doseUnit: .mg, timestamp: date)
        context.insert(log)
        // Re-establish the relationship after insertion so SwiftData's backing store
        // tracks it correctly regardless of when the relationship was first assigned.
        p.doseLogs?.append(log)
        try? context.save()
        return log
    }

    // MARK: - isLogged

    func test_isLogged_logExistsOnDay_returnsTrue() throws {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let noon = cal.date(byAdding: .hour, value: 12, to: today)!

        let p = makeProtocol()
        let log = makeLog(for: p, on: noon)

        XCTAssertTrue(DoseScheduleDayHelper.isLogged(p, on: today, logs: [log]))
    }

    func test_isLogged_logOnDifferentDay_returnsFalse() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!

        let p = makeProtocol()
        let log = makeLog(for: p, on: yesterday)

        XCTAssertFalse(DoseScheduleDayHelper.isLogged(p, on: today, logs: [log]))
    }

    func test_isLogged_noLogs_returnsFalse() {
        let p = makeProtocol()
        XCTAssertFalse(DoseScheduleDayHelper.isLogged(p, on: Date(), logs: []))
    }

    func test_isLogged_logForDifferentProtocol_returnsFalse() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let noon = cal.date(byAdding: .hour, value: 12, to: today)!

        let p1 = makeProtocol()
        let p2 = makeProtocol()
        let log = makeLog(for: p1, on: noon)  // log belongs to p1

        XCTAssertFalse(DoseScheduleDayHelper.isLogged(p2, on: today, logs: [log]))
    }

    func test_isLogged_multipleProtocols_picksCorrectOne() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let noon = cal.date(byAdding: .hour, value: 12, to: today)!

        let p1 = makeProtocol()
        let p2 = makeProtocol()
        let log1 = makeLog(for: p1, on: noon)
        let log2 = makeLog(for: p2, on: noon)

        XCTAssertTrue(DoseScheduleDayHelper.isLogged(p1, on: today, logs: [log1, log2]))
        XCTAssertTrue(DoseScheduleDayHelper.isLogged(p2, on: today, logs: [log1, log2]))
    }

    // MARK: - scheduledRows

    func test_scheduledRows_dailyProtocol_appearsOnTomorrow() {
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: Date())!
        // Default .daily schedule (8 AM) → should appear tomorrow
        let p = makeProtocol(schedule: .daily)
        let rows = DoseScheduleDayHelper.scheduledRows(protocols: [p], on: tomorrow)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].0.id, p.id)
    }

    func test_scheduledRows_noMatchingDay_returnsEmpty() {
        let cal = Calendar.current
        // Schedule only on Sunday; query on a day that is definitely not that Sunday
        var sched = DoseSchedule()
        sched.type = .specificWeekdays
        sched.weekdays = [.sunday]
        sched.timesOfDay = []

        let p = makeProtocol(schedule: sched)

        // Find next Monday (not Sunday)
        var comps = DateComponents(); comps.weekday = 2
        guard let monday = cal.nextDate(after: Date(), matching: comps, matchingPolicy: .nextTimePreservingSmallerComponents) else { return }

        let rows = DoseScheduleDayHelper.scheduledRows(protocols: [p], on: monday)
        XCTAssertTrue(rows.isEmpty)
    }

    func test_scheduledRows_multipleProtocols_sortedByTime() {
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: Date())!

        var earlySchedule = DoseSchedule()
        earlySchedule.type = .daily
        earlySchedule.timesOfDay = [cal.date(bySettingHour: 7, minute: 0, second: 0, of: tomorrow)!]

        var lateSchedule = DoseSchedule()
        lateSchedule.type = .daily
        lateSchedule.timesOfDay = [cal.date(bySettingHour: 20, minute: 0, second: 0, of: tomorrow)!]

        let p1 = makeProtocol(schedule: lateSchedule)   // late
        let p2 = makeProtocol(schedule: earlySchedule)  // early

        let rows = DoseScheduleDayHelper.scheduledRows(protocols: [p1, p2], on: tomorrow)
        XCTAssertEqual(rows.count, 2)
        // p2 (early) should come first
        XCTAssertEqual(rows[0].0.id, p2.id)
        XCTAssertEqual(rows[1].0.id, p1.id)
    }

    func test_scheduledRows_emptyProtocols_returnsEmpty() {
        let rows = DoseScheduleDayHelper.scheduledRows(protocols: [], on: Date())
        XCTAssertTrue(rows.isEmpty)
    }

    // MARK: - mergedRows

    func test_mergedRows_includesScheduledProtocol() {
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: Date())!
        let p = makeProtocol(schedule: .daily)
        let rows = DoseScheduleDayHelper.mergedRows(protocols: [p], logs: [], on: tomorrow)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].0.id, p.id)
    }

    func test_mergedRows_includesOffScheduleLoggedProtocol() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let noon = cal.date(byAdding: .hour, value: 12, to: today)!
        let todayWeekday = cal.component(.weekday, from: today)

        // Schedule on a weekday that is NOT today
        let otherWeekdayInt = todayWeekday == 2 ? 3 : 2
        let otherWeekday: Weekday = otherWeekdayInt == 2 ? .monday : .tuesday

        var sched = DoseSchedule()
        sched.type = .specificWeekdays
        sched.weekdays = [otherWeekday]
        sched.timesOfDay = []

        let p = makeProtocol(schedule: sched)
        let log = makeLog(for: p, on: noon)  // logged today, but not scheduled today

        let rows = DoseScheduleDayHelper.mergedRows(protocols: [p], logs: [log], on: today)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].0.id, p.id)
    }

    func test_mergedRows_scheduledProtocolNotDuplicated() {
        // A protocol scheduled today AND logged today should appear only once
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: Date())!
        let nineAM = cal.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)!

        var sched = DoseSchedule()
        sched.type = .daily
        sched.timesOfDay = [nineAM]
        let p = makeProtocol(schedule: sched)
        let log = makeLog(for: p, on: nineAM)

        let rows = DoseScheduleDayHelper.mergedRows(protocols: [p], logs: [log], on: tomorrow)
        XCTAssertEqual(rows.count, 1)
    }

    func test_mergedRows_emptyInputs_returnsEmpty() {
        let rows = DoseScheduleDayHelper.mergedRows(protocols: [], logs: [], on: Date())
        XCTAssertTrue(rows.isEmpty)
    }
}
