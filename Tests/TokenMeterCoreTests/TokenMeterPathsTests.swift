import XCTest
@testable import TokenMeterCore

final class TokenMeterPathsTests: XCTestCase {
    func testPathsAreDerivedFromHome() {
        let home = URL(fileURLWithPath: "/tmp/fake-home")

        XCTAssertEqual(TokenMeterPaths.claudeDir(home: home).path, "/tmp/fake-home/.claude")
        XCTAssertEqual(TokenMeterPaths.tokenMeterDir(home: home).path, "/tmp/fake-home/.claude/tokenmeter")
        XCTAssertEqual(TokenMeterPaths.settingsFile(home: home).path, "/tmp/fake-home/.claude/settings.json")
        XCTAssertEqual(TokenMeterPaths.statusFile(home: home).path, "/tmp/fake-home/.claude/tokenmeter/status.json")
        XCTAssertEqual(TokenMeterPaths.statuslineScript(home: home).path, "/tmp/fake-home/.claude/tokenmeter/statusline.sh")
    }
}
