import XCTest
import SwiftData
@testable import Ascendancy

final class PharmacokineticsEngineTests: XCTestCase {

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
        halfLifeValue: Double = 24.0,
        halfLifeUnit: HalfLifeUnit = .hours,
        startDate: Date = Date()
    ) -> CompoundProtocol {
        let p = CompoundProtocol(
            name: "Test", category: .medication, administrationForm: .pill,
            doseAmount: 10.0, doseUnit: .mg, schedule: .daily,
            startDate: startDate, halfLifeValue: halfLifeValue, halfLifeUnit: halfLifeUnit
        )
        context.insert(p)
        return p
    }

    func makeLog(for p: CompoundProtocol, amount: Double, hoursAgo: Double) -> DoseLog {
        let ts = Date().addingTimeInterval(-hoursAgo * 3600)
        let log = DoseLog(protocol_: p, actualDoseAmount: amount, doseUnit: .mg, timestamp: ts)
        context.insert(log)
        return log
    }

    // MARK: - activeLevel

    func test_activeLevel_zeroHalfLife_returnsEmpty() {
        let p = makeProtocol(halfLifeValue: 0)
        XCTAssertTrue(PharmacokineticsEngine.activeLevel(for: p, logs: []).isEmpty)
    }

    func test_activeLevel_noLogs_allPointsAreZero() {
        let p = makeProtocol()
        let end = Date()
        let start = end.addingTimeInterval(-7 * 86400)
        let result = PharmacokineticsEngine.activeLevel(for: p, logs: [], startDate: start, endDate: end)
        XCTAssertEqual(result.count, 120)
        XCTAssertTrue(result.allSatisfy { $0.level == 0 })
    }

    func test_activeLevel_singleDose_decaysToHalfAfterOneHalfLife() {
        let p = makeProtocol(halfLifeValue: 24, halfLifeUnit: .hours)
        let now = Date()
        let log = makeLog(for: p, amount: 100.0, hoursAgo: 24)
        let start = now.addingTimeInterval(-48 * 3600)
        let result = PharmacokineticsEngine.activeLevel(for: p, logs: [log], startDate: start, endDate: now)
        // At t=now, dose is exactly 1 half-life old → 100 * 0.5 = 50
        XCTAssertEqual(result.last!.level, 50.0, accuracy: 1.0)
    }

    func test_activeLevel_multipleDoses_stackAdditively() {
        let p = makeProtocol(halfLifeValue: 24, halfLifeUnit: .hours)
        let now = Date()
        // Two doses, both 2 half-lives old → each contributes 100 * 0.25 = 25, total 50
        let log1 = makeLog(for: p, amount: 100.0, hoursAgo: 48)
        let log2 = makeLog(for: p, amount: 100.0, hoursAgo: 48)
        let start = now.addingTimeInterval(-96 * 3600)
        let result = PharmacokineticsEngine.activeLevel(for: p, logs: [log1, log2], startDate: start, endDate: now)
        XCTAssertEqual(result.last!.level, 50.0, accuracy: 2.0)
    }

    func test_activeLevel_futureLogsIgnored() {
        let p = makeProtocol()
        let now = Date()
        let futureLog = makeLog(for: p, amount: 999.0, hoursAgo: -1)  // 1 hour in the future
        let start = now.addingTimeInterval(-24 * 3600)
        let result = PharmacokineticsEngine.activeLevel(for: p, logs: [futureLog], startDate: start, endDate: now)
        XCTAssertTrue(result.allSatisfy { $0.level == 0 })
    }

    func test_activeLevel_resolutionControlsPointCount() {
        let p = makeProtocol()
        let end = Date()
        let start = end.addingTimeInterval(-86400)
        let result = PharmacokineticsEngine.activeLevel(for: p, logs: [], startDate: start, endDate: end, resolution: 50)
        XCTAssertEqual(result.count, 50)
    }

    func test_activeLevel_windowStartEqualsEnd_returnsEmpty() {
        let p = makeProtocol()
        let t = Date()
        let result = PharmacokineticsEngine.activeLevel(for: p, logs: [], startDate: t, endDate: t)
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - stableLevelInfo

    func test_stableLevelInfo_freshProtocol_returnsNearZero() {
        let p = makeProtocol(halfLifeValue: 24, startDate: Date())
        let info = PharmacokineticsEngine.stableLevelInfo(for: p, logs: [])
        XCTAssertEqual(info.percentage, 0.0, accuracy: 5.0)
        XCTAssertFalse(info.isStable)
    }

    func test_stableLevelInfo_oneHalfLife_returns50Percent() {
        let halfLifeHours = 24.0
        let start = Date().addingTimeInterval(-halfLifeHours * 3600)
        let p = makeProtocol(halfLifeValue: halfLifeHours, startDate: start)
        let info = PharmacokineticsEngine.stableLevelInfo(for: p, logs: [])
        XCTAssertEqual(info.percentage, 50.0, accuracy: 1.0)
        XCTAssertEqual(info.halfLivesElapsed, 1.0, accuracy: 0.05)
        XCTAssertFalse(info.isStable)
    }

    func test_stableLevelInfo_twoHalfLives_returns75Percent() {
        let halfLifeHours = 24.0
        let start = Date().addingTimeInterval(-halfLifeHours * 2 * 3600)
        let p = makeProtocol(halfLifeValue: halfLifeHours, startDate: start)
        let info = PharmacokineticsEngine.stableLevelInfo(for: p, logs: [])
        XCTAssertEqual(info.percentage, 75.0, accuracy: 1.0)
    }

    func test_stableLevelInfo_threeHalfLives_returns875Percent() {
        let halfLifeHours = 24.0
        let start = Date().addingTimeInterval(-halfLifeHours * 3 * 3600)
        let p = makeProtocol(halfLifeValue: halfLifeHours, startDate: start)
        let info = PharmacokineticsEngine.stableLevelInfo(for: p, logs: [])
        XCTAssertEqual(info.percentage, 87.5, accuracy: 1.0)
    }

    func test_stableLevelInfo_fiveHalfLives_isStable() {
        let halfLifeHours = 24.0
        let start = Date().addingTimeInterval(-halfLifeHours * 5 * 3600)
        let p = makeProtocol(halfLifeValue: halfLifeHours, startDate: start)
        let info = PharmacokineticsEngine.stableLevelInfo(for: p, logs: [])
        XCTAssertGreaterThanOrEqual(info.percentage, 96.0)
        XCTAssertTrue(info.isStable)
    }

    func test_stableLevelInfo_percentageCappedAt100() {
        // Extremely long time on protocol
        let start = Date().addingTimeInterval(-1_000_000 * 3600)
        let p = makeProtocol(halfLifeValue: 1, startDate: start)
        let info = PharmacokineticsEngine.stableLevelInfo(for: p, logs: [])
        XCTAssertLessThanOrEqual(info.percentage, 100.0)
    }

    func test_stableLevelInfo_usesEarliestLogTimestamp() {
        let halfLifeHours = 24.0
        // Protocol starts now, but a log from 2 half-lives ago should shift the reference
        let p = makeProtocol(halfLifeValue: halfLifeHours, startDate: Date())
        let earlyLog = makeLog(for: p, amount: 10, hoursAgo: halfLifeHours * 2)
        let info = PharmacokineticsEngine.stableLevelInfo(for: p, logs: [earlyLog])
        XCTAssertEqual(info.percentage, 75.0, accuracy: 2.0)
    }

    func test_stableLevelInfo_zeroHalfLife_returnsZeroInfo() {
        let p = makeProtocol(halfLifeValue: 0)
        let info = PharmacokineticsEngine.stableLevelInfo(for: p, logs: [])
        XCTAssertEqual(info.percentage, 0)
        XCTAssertEqual(info.hoursOnProtocol, 0)
    }

    // MARK: - hoursUntilBelow

    func test_hoursUntilBelow_zeroHalfLife_returnsNil() {
        let p = makeProtocol(halfLifeValue: 0)
        XCTAssertNil(PharmacokineticsEngine.hoursUntilBelow(threshold: 50, protocol_: p, logs: []))
    }

    func test_hoursUntilBelow_levelAlreadyBelowThreshold_returnsZero() {
        let p = makeProtocol(halfLifeValue: 24)
        // No logs → level is 0, already below threshold of 1
        let result = PharmacokineticsEngine.hoursUntilBelow(threshold: 1.0, protocol_: p, logs: [])
        XCTAssertNotNil(result)
        XCTAssertEqual(result!, 0, accuracy: 1.0)
    }

    func test_hoursUntilBelow_singleDose_dropsAtOneHalfLife() {
        let p = makeProtocol(halfLifeValue: 24)
        // Dose of 100 logged just now; should drop below 50 in ~24 hours
        let log = makeLog(for: p, amount: 100.0, hoursAgo: 0)
        let result = PharmacokineticsEngine.hoursUntilBelow(threshold: 50.0, protocol_: p, logs: [log])
        XCTAssertNotNil(result)
        XCTAssertEqual(result!, 24.0, accuracy: 2.0)
    }

    // MARK: - combinedActiveLevel

    func test_combinedActiveLevel_emptyProtocols_returnsEmpty() {
        XCTAssertTrue(PharmacokineticsEngine.combinedActiveLevel(protocols: []).isEmpty)
    }

    func test_combinedActiveLevel_twoProtocols_sumsLevels() {
        let now = Date()
        let start = now.addingTimeInterval(-48 * 3600)

        let p1 = makeProtocol(halfLifeValue: 24)
        let log1 = makeLog(for: p1, amount: 50.0, hoursAgo: 0)

        let p2 = makeProtocol(halfLifeValue: 24)
        let log2 = makeLog(for: p2, amount: 50.0, hoursAgo: 0)

        let single = PharmacokineticsEngine.activeLevel(for: p1, logs: [log1], startDate: start, endDate: now)
        let combined = PharmacokineticsEngine.combinedActiveLevel(
            protocols: [(p1, [log1]), (p2, [log2])],
            startDate: start, endDate: now
        )

        XCTAssertEqual(combined.count, single.count)
        XCTAssertEqual(combined.last!.level, single.last!.level * 2, accuracy: 1.0)
    }

    func test_combinedActiveLevel_singleProtocol_matchesActiveLevel() {
        let now = Date()
        let start = now.addingTimeInterval(-48 * 3600)
        let p = makeProtocol(halfLifeValue: 24)
        let log = makeLog(for: p, amount: 80.0, hoursAgo: 12)

        let single = PharmacokineticsEngine.activeLevel(for: p, logs: [log], startDate: start, endDate: now)
        let combined = PharmacokineticsEngine.combinedActiveLevel(protocols: [(p, [log])], startDate: start, endDate: now)

        XCTAssertEqual(single.count, combined.count)
        for (s, c) in zip(single, combined) {
            XCTAssertEqual(s.level, c.level, accuracy: 0.001)
        }
    }
}
