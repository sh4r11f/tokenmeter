import SwiftUI
import TokenMeterCore

@main
struct TokenMeterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState: AppState

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let store = StatusFileStore(statusFileURL: TokenMeterPaths.statusFile(home: home))
        let installer = SettingsInstaller(
            settingsFileURL: TokenMeterPaths.settingsFile(home: home),
            statuslineScriptPath: TokenMeterPaths.statuslineScript(home: home).path,
            backupDirURL: TokenMeterPaths.tokenMeterDir(home: home)
        )
        let state = AppState(store: store, installer: installer)
        _appState = StateObject(wrappedValue: state)
        state.start()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(appState: appState)
        } label: {
            MenuBarLabelView(label: appState.compactLabel)
        }
        .menuBarExtraStyle(.window)
    }
}
