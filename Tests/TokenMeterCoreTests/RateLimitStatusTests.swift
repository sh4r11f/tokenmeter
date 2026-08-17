import XCTest
@testable import TokenMeterCore

final class RateLimitStatusTests: XCTestCase {
    func testDecodesFullPayload() throws {
        let json = """
        {
          "captured_at": 1755460000,
          "rate_limits": {
            "five_hour": {"used_percentage": 42.3, "resets_at": 1755470000},
            "seven_day": {"used_percentage": 18.1, "resets_at": 1755990000}
          }
        }
        """.data(using: .utf8)!

        let snapshot = try JSONDecoder().decode(StatusSnapshot.self, from: json)

        XCTAssertEqual(snapshot.capturedAt, Date(timeIntervalSince1970: 1755460000))
        XCTAssertEqual(snapshot.rateLimits?.fiveHour?.usedPercentage, 42.3)
        XCTAssertEqual(snapshot.rateLimits?.fiveHour?.resetsAt, Date(timeIntervalSince1970: 1755470000))
        XCTAssertEqual(snapshot.rateLimits?.sevenDay?.usedPercentage, 18.1)
    }

    func testDecodesMissingSevenDay() throws {
        let json = """
        {"captured_at": 1755460000, "rate_limits": {"five_hour": {"used_percentage": 5, "resets_at": 1755470000}}}
        """.data(using: .utf8)!

        let snapshot = try JSONDecoder().decode(StatusSnapshot.self, from: json)

        XCTAssertNotNil(snapshot.rateLimits?.fiveHour)
        XCTAssertNil(snapshot.rateLimits?.sevenDay)
    }

    func testDecodesNullRateLimits() throws {
        let json = """
        {"captured_at": 1755460000, "rate_limits": null}
        """.data(using: .utf8)!

        let snapshot = try JSONDecoder().decode(StatusSnapshot.self, from: json)

        XCTAssertNil(snapshot.rateLimits)
    }

    func testThrowsOnMalformedJSON() {
        let json = "not json".data(using: .utf8)!

        XCTAssertThrowsError(try JSONDecoder().decode(StatusSnapshot.self, from: json))
    }

    func testThrowsOnMissingCapturedAt() {
        let json = """
        {"rate_limits": null}
        """.data(using: .utf8)!

        XCTAssertThrowsError(try JSONDecoder().decode(StatusSnapshot.self, from: json))
    }

    func testRoundTripsThroughEncoder() throws {
        let original = StatusSnapshot(
            capturedAt: Date(timeIntervalSince1970: 1755460000),
            rateLimits: RateLimits(
                fiveHour: RateLimitWindow(usedPercentage: 42, resetsAt: Date(timeIntervalSince1970: 1755470000)),
                sevenDay: nil
            )
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(StatusSnapshot.self, from: data)

        XCTAssertEqual(original, decoded)
    }
}
