import XCTest
@testable import TokenMeterCore

final class LabelFormatterTests: XCTestCase {
    func testNotInstalled() {
        let label = LabelFormatter.compactLabel(for: .notInstalled, metric: .fiveHour)
        XCTAssertEqual(label.text, "–")
        XCTAssertEqual(label.level, .unknown)
        XCTAssertFalse(label.isStale)
    }

    func testNoRateLimitData() {
        let label = LabelFormatter.compactLabel(
            for: .noRateLimitData(capturedAt: Date(), isStale: true),
            metric: .fiveHour
        )
        XCTAssertEqual(label.text, "n/a")
        XCTAssertTrue(label.isStale)
    }

    func testDecodeError() {
        let label = LabelFormatter.compactLabel(for: .decodeError("boom"), metric: .fiveHour)
        XCTAssertEqual(label.text, "!")
    }

    private func snapshot(five: Double?, seven: Double?) -> StatusSnapshot {
        StatusSnapshot(
            capturedAt: Date(timeIntervalSince1970: 0),
            rateLimits: RateLimits(
                fiveHour: five.map { RateLimitWindow(usedPercentage: $0, resetsAt: Date()) },
                sevenDay: seven.map { RateLimitWindow(usedPercentage: $0, resetsAt: Date()) }
            )
        )
    }

    func testFiveHourMetricNormal() {
        let label = LabelFormatter.compactLabel(for: .ok(snapshot(five: 30, seven: 90), isStale: false), metric: .fiveHour)
        XCTAssertEqual(label.text, "5h 30%")
        XCTAssertEqual(label.level, .normal)
    }

    func testFiveHourMetricWarningAtFifty() {
        let label = LabelFormatter.compactLabel(for: .ok(snapshot(five: 55, seven: 0), isStale: false), metric: .fiveHour)
        XCTAssertEqual(label.level, .warning)
    }

    func testFiveHourMetricCriticalAboveEighty() {
        let label = LabelFormatter.compactLabel(for: .ok(snapshot(five: 85, seven: 0), isStale: false), metric: .fiveHour)
        XCTAssertEqual(label.level, .critical)
    }

    func testSevenDayMetric() {
        let label = LabelFormatter.compactLabel(for: .ok(snapshot(five: 10, seven: 60), isStale: false), metric: .sevenDay)
        XCTAssertEqual(label.text, "7d 60%")
        XCTAssertEqual(label.level, .warning)
    }

    func testMostUrgentPicksHigherWindow() {
        let label = LabelFormatter.compactLabel(for: .ok(snapshot(five: 10, seven: 90), isStale: false), metric: .mostUrgent)
        XCTAssertEqual(label.text, "7d 90%")
        XCTAssertEqual(label.level, .critical)
    }

    func testMissingRequestedWindowFallsBackToNA() {
        let label = LabelFormatter.compactLabel(for: .ok(snapshot(five: nil, seven: 20), isStale: false), metric: .fiveHour)
        XCTAssertEqual(label.text, "n/a")
    }

    func testStaleFlagPropagates() {
        let label = LabelFormatter.compactLabel(for: .ok(snapshot(five: 10, seven: 10), isStale: true), metric: .fiveHour)
        XCTAssertTrue(label.isStale)
    }
}
