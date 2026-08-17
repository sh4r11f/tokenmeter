import XCTest
@testable import TokenMeterCore

final class StatusFileStoreTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func write(_ contents: String, name: String = "status.json") -> URL {
        let url = tempDir.appendingPathComponent(name)
        try! contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testNotInstalledWhenFileMissing() {
        let store = StatusFileStore(statusFileURL: tempDir.appendingPathComponent("missing.json"))
        XCTAssertEqual(store.load(), .notInstalled)
    }

    func testOkWhenFresh() {
        let capturedAt = Date(timeIntervalSince1970: 1_755_460_000)
        let url = write("""
        {"captured_at": 1755460000, "rate_limits": {"five_hour": {"used_percentage": 10, "resets_at": 1755470000}}}
        """)
        let store = StatusFileStore(statusFileURL: url, staleAfter: 120, now: { capturedAt.addingTimeInterval(30) })

        guard case .ok(let snapshot, let isStale) = store.load() else {
            return XCTFail("expected .ok")
        }
        XCTAssertFalse(isStale)
        XCTAssertEqual(snapshot.rateLimits?.fiveHour?.usedPercentage, 10)
    }

    func testOkButStaleWhenOld() {
        let capturedAt = Date(timeIntervalSince1970: 1_755_460_000)
        let url = write("""
        {"captured_at": 1755460000, "rate_limits": {"five_hour": {"used_percentage": 10, "resets_at": 1755470000}}}
        """)
        let store = StatusFileStore(statusFileURL: url, staleAfter: 120, now: { capturedAt.addingTimeInterval(300) })

        guard case .ok(_, let isStale) = store.load() else {
            return XCTFail("expected .ok")
        }
        XCTAssertTrue(isStale)
    }

    func testNoRateLimitDataWhenNull() {
        let url = write("""
        {"captured_at": 1755460000, "rate_limits": null}
        """)
        let store = StatusFileStore(statusFileURL: url, now: { Date(timeIntervalSince1970: 1_755_460_010) })

        guard case .noRateLimitData(let capturedAt, let isStale) = store.load() else {
            return XCTFail("expected .noRateLimitData")
        }
        XCTAssertEqual(capturedAt, Date(timeIntervalSince1970: 1_755_460_000))
        XCTAssertFalse(isStale)
    }

    func testDecodeErrorOnGarbage() {
        let url = write("not json at all")
        let store = StatusFileStore(statusFileURL: url)

        guard case .decodeError = store.load() else {
            return XCTFail("expected .decodeError")
        }
    }
}
