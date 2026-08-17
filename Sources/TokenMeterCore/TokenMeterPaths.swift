import Foundation

/// All filesystem locations TokenMeter reads or writes, derived from an
/// explicit home directory so every caller (app code and tests alike) is
/// explicit about which home they mean.
public enum TokenMeterPaths {
    public static func claudeDir(home: URL) -> URL {
        home.appendingPathComponent(".claude", isDirectory: true)
    }

    public static func tokenMeterDir(home: URL) -> URL {
        claudeDir(home: home).appendingPathComponent("tokenmeter", isDirectory: true)
    }

    public static func settingsFile(home: URL) -> URL {
        claudeDir(home: home).appendingPathComponent("settings.json", isDirectory: false)
    }

    public static func statusFile(home: URL) -> URL {
        tokenMeterDir(home: home).appendingPathComponent("status.json", isDirectory: false)
    }

    public static func statuslineScript(home: URL) -> URL {
        tokenMeterDir(home: home).appendingPathComponent("statusline.sh", isDirectory: false)
    }
}
