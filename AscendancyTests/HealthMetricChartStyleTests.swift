import XCTest
@testable import Ascendancy

final class HealthMetricChartStyleTests: XCTestCase {

    func test_barBaseline_forClusteredNonZeroMetrics_matchesPaddedDomainLowerBound() {
        let style = HealthMetricChartStyle(values: [72.0, 73.0, 74.0])

        XCTAssertEqual(style.yDomain.lowerBound, 71.8, accuracy: 0.001)
        XCTAssertEqual(style.barBaseline, style.yDomain.lowerBound, accuracy: 0.001)
    }

    func test_barBaseline_forLowMetrics_doesNotDropBelowZero() {
        let style = HealthMetricChartStyle(values: [0.0, 0.3, 0.4])

        XCTAssertEqual(style.yDomain.lowerBound, 0.0, accuracy: 0.001)
        XCTAssertEqual(style.barBaseline, 0.0, accuracy: 0.001)
    }
}
