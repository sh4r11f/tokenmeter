import Foundation

/// Installs (or removes) TokenMeter's `statusLine` hook in
/// `~/.claude/settings.json`, preserving every unrelated key and always
/// backing up the file first. Also writes the `statusline.sh` script
/// contents to disk as an executable file.
public struct SettingsInstaller {
    public enum InstallOutcome: Equatable {
        case installedFresh
        case alreadyInstalled
        case wrapped(existingCommand: String)
    }

    public enum InstallerError: Error, Equatable, LocalizedError {
        case settingsUnreadable(String)
        case settingsUnwritable(String)
        case malformedSettingsJSON
        case noBackupFound

        public var errorDescription: String? {
            switch self {
            case .settingsUnreadable(let path): return "Couldn't read \(path)."
            case .settingsUnwritable(let path): return "Couldn't write \(path)."
            case .malformedSettingsJSON: return "settings.json isn't valid JSON."
            case .noBackupFound: return "No TokenMeter backup found to restore."
            }
        }
    }

    public let settingsFileURL: URL
    public let statuslineScriptPath: String
    public let backupDirURL: URL
    public let now: () -> Date

    public init(
        settingsFileURL: URL,
        statuslineScriptPath: String,
        backupDirURL: URL,
        now: @escaping () -> Date = Date.init
    ) {
        self.settingsFileURL = settingsFileURL
        self.statuslineScriptPath = statuslineScriptPath
        self.backupDirURL = backupDirURL
        self.now = now
    }

    public func currentStatusLineCommand() throws -> String? {
        let dict = try readSettingsDict()
        guard let statusLine = dict["statusLine"] as? [String: Any] else { return nil }
        return statusLine["command"] as? String
    }

    public func install(statuslineScriptContents: String) throws -> InstallOutcome {
        try writeStatuslineScript(statuslineScriptContents)

        var root = try readSettingsDict()
        try backupIfFileExists()

        if let existing = root["statusLine"] as? [String: Any],
           let existingCommand = existing["command"] as? String {
            if existingCommand == statuslineScriptPath || existingCommand.contains(statuslineScriptPath) {
                return .alreadyInstalled
            }
            let wrapped = "TOKENMETER_WRAPPED_COMMAND=\(shellSingleQuoted(existingCommand)) \(statuslineScriptPath)"
            root["statusLine"] = ["type": "command", "command": wrapped]
            try writeSettingsDict(root)
            return .wrapped(existingCommand: existingCommand)
        }

        root["statusLine"] = ["type": "command", "command": statuslineScriptPath]
        try writeSettingsDict(root)
        return .installedFresh
    }

    public func uninstall() throws {
        let backups = (try? FileManager.default.contentsOfDirectory(at: backupDirURL, includingPropertiesForKeys: nil)) ?? []
        let candidates = backups
            .filter { $0.lastPathComponent.hasPrefix("settings.json.bak-") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        guard let latest = candidates.first else {
            throw InstallerError.noBackupFound
        }
        let data = try Data(contentsOf: latest)
        let resolved = settingsFileURL.resolvingSymlinksInPath()
        do {
            try data.write(to: resolved, options: .atomic)
        } catch {
            throw InstallerError.settingsUnwritable(resolved.path)
        }
    }

    // MARK: - Private

    private func shellSingleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func writeStatuslineScript(_ contents: String) throws {
        let scriptURL = URL(fileURLWithPath: statuslineScriptPath)
        do {
            try FileManager.default.createDirectory(at: scriptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contents.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        } catch {
            throw InstallerError.settingsUnwritable(scriptURL.path)
        }
    }

    private func readSettingsDict() throws -> [String: Any] {
        let resolved = settingsFileURL.resolvingSymlinksInPath()
        guard FileManager.default.fileExists(atPath: resolved.path) else { return [:] }
        guard let data = try? Data(contentsOf: resolved) else {
            throw InstallerError.settingsUnreadable(resolved.path)
        }
        guard !data.isEmpty else { return [:] }
        guard let obj = try? JSONSerialization.jsonObject(with: data), let dict = obj as? [String: Any] else {
            throw InstallerError.malformedSettingsJSON
        }
        return dict
    }

    private func writeSettingsDict(_ dict: [String: Any]) throws {
        let resolved = settingsFileURL.resolvingSymlinksInPath()
        guard JSONSerialization.isValidJSONObject(dict) else {
            throw InstallerError.malformedSettingsJSON
        }
        let data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
        do {
            try FileManager.default.createDirectory(at: resolved.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: resolved, options: .atomic)
        } catch {
            throw InstallerError.settingsUnwritable(resolved.path)
        }
    }

    private func backupIfFileExists() throws {
        let resolved = settingsFileURL.resolvingSymlinksInPath()
        guard FileManager.default.fileExists(atPath: resolved.path) else { return }
        do {
            try FileManager.default.createDirectory(at: backupDirURL, withIntermediateDirectories: true)
            let timestamp = ISO8601DateFormatter().string(from: now()).replacingOccurrences(of: ":", with: "-")
            let backupURL = backupDirURL.appendingPathComponent("settings.json.bak-\(timestamp)")
            let data = try Data(contentsOf: resolved)
            try data.write(to: backupURL, options: .atomic)
        } catch {
            throw InstallerError.settingsUnwritable(backupDirURL.path)
        }
    }
}
