import XCTest
@testable import TokenMeterCore

final class SettingsInstallerTests: XCTestCase {
    private var tempDir: URL!
    private var settingsURL: URL!
    private var backupDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        settingsURL = tempDir.appendingPathComponent(".claude/settings.json")
        backupDir = tempDir.appendingPathComponent(".claude/tokenmeter")
        try! FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func makeInstaller() -> SettingsInstaller {
        SettingsInstaller(
            settingsFileURL: settingsURL,
            statuslineScriptPath: backupDir.appendingPathComponent("statusline.sh").path,
            backupDirURL: backupDir
        )
    }

    func testFreshInstallWhenNoSettingsFile() throws {
        let installer = makeInstaller()

        let outcome = try installer.install(statuslineScriptContents: "#!/bin/sh\necho hi\n")

        XCTAssertEqual(outcome, .installedFresh)
        let data = try Data(contentsOf: settingsURL)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let statusLine = dict["statusLine"] as! [String: Any]
        XCTAssertEqual(statusLine["command"] as? String, backupDir.appendingPathComponent("statusline.sh").path)
    }

    func testInstallPreservesUnrelatedKeys() throws {
        try """
        {"model": "sonnet", "permissions": {"defaultMode": "auto"}}
        """.write(to: settingsURL, atomically: true, encoding: .utf8)
        let installer = makeInstaller()

        _ = try installer.install(statuslineScriptContents: "#!/bin/sh\n")

        let data = try Data(contentsOf: settingsURL)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(dict["model"] as? String, "sonnet")
        XCTAssertNotNil(dict["statusLine"])
    }

    func testInstallWritesScriptContentsExecutable() throws {
        let installer = makeInstaller()

        _ = try installer.install(statuslineScriptContents: "#!/bin/sh\necho hi\n")

        let scriptPath = backupDir.appendingPathComponent("statusline.sh").path
        XCTAssertEqual(try String(contentsOfFile: scriptPath, encoding: .utf8), "#!/bin/sh\necho hi\n")
        let perms = try FileManager.default.attributesOfItem(atPath: scriptPath)[.posixPermissions] as! Int
        XCTAssertEqual(perms & 0o111, 0o111, "script should be executable")
    }

    func testBackupIsOwnerOnly() throws {
        try """
        {"model": "sonnet"}
        """.write(to: settingsURL, atomically: true, encoding: .utf8)
        let installer = makeInstaller()

        _ = try installer.install(statuslineScriptContents: "#!/bin/sh\n")

        let backups = try FileManager.default.contentsOfDirectory(at: backupDir, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("settings.json.bak-") }
        XCTAssertEqual(backups.count, 1)
        let perms = try FileManager.default.attributesOfItem(atPath: backups[0].path)[.posixPermissions] as! Int
        XCTAssertEqual(perms & 0o777, 0o600, "settings backups can contain secrets and must be owner-only")
    }

    func testSecondInstallIsAlreadyInstalled() throws {
        let installer = makeInstaller()
        _ = try installer.install(statuslineScriptContents: "#!/bin/sh\n")

        let outcome = try installer.install(statuslineScriptContents: "#!/bin/sh\n")

        XCTAssertEqual(outcome, .alreadyInstalled)
    }

    func testInstallWrapsExistingStatusLine() throws {
        try """
        {"statusLine": {"type": "command", "command": "my-existing-script.sh"}}
        """.write(to: settingsURL, atomically: true, encoding: .utf8)
        let installer = makeInstaller()

        let outcome = try installer.install(statuslineScriptContents: "#!/bin/sh\n")

        guard case .wrapped(let existing) = outcome else {
            return XCTFail("expected .wrapped, got \(outcome)")
        }
        XCTAssertEqual(existing, "my-existing-script.sh")
        let command = try installer.currentStatusLineCommand()
        XCTAssertTrue(command?.contains("TOKENMETER_WRAPPED_COMMAND='my-existing-script.sh'") ?? false)
        XCTAssertTrue(command?.contains(backupDir.appendingPathComponent("statusline.sh").path) ?? false)
    }

    func testUninstallRestoresBackup() throws {
        try """
        {"model": "sonnet"}
        """.write(to: settingsURL, atomically: true, encoding: .utf8)
        let installer = makeInstaller()
        _ = try installer.install(statuslineScriptContents: "#!/bin/sh\n")

        try installer.uninstall()

        let data = try Data(contentsOf: settingsURL)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(dict["model"] as? String, "sonnet")
        XCTAssertNil(dict["statusLine"])
    }

    func testUninstallThrowsWithNoBackup() {
        let installer = makeInstaller()

        XCTAssertThrowsError(try installer.uninstall()) { error in
            XCTAssertEqual(error as? SettingsInstaller.InstallerError, .noBackupFound)
        }
    }

    func testMalformedSettingsJSONThrows() throws {
        try "not json".write(to: settingsURL, atomically: true, encoding: .utf8)
        let installer = makeInstaller()

        XCTAssertThrowsError(try installer.install(statuslineScriptContents: "#!/bin/sh\n")) { error in
            XCTAssertEqual(error as? SettingsInstaller.InstallerError, .malformedSettingsJSON)
        }
    }
}
