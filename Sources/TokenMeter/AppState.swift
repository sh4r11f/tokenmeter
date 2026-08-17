import Foundation
import TokenMeterCore

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var loadResult: StatusFileStore.LoadResult = .notInstalled
    @Published var labelMetric: LabelMetric {
        didSet { UserDefaults.standard.set(labelMetric.rawValue, forKey: Self.labelMetricDefaultsKey) }
    }

    private let store: StatusFileStore
    private let installer: SettingsInstaller
    private var watcher: FileWatcher?
    private var pollTimer: Timer?

    static let labelMetricDefaultsKey = "labelMetric"

    var compactLabel: CompactLabel {
        LabelFormatter.compactLabel(for: loadResult, metric: labelMetric)
    }

    init(store: StatusFileStore, installer: SettingsInstaller) {
        self.store = store
        self.installer = installer
        let saved = UserDefaults.standard.string(forKey: Self.labelMetricDefaultsKey)
        self.labelMetric = saved.flatMap(LabelMetric.init(rawValue:)) ?? .fiveHour
    }

    func start() {
        refresh()
        watcher = FileWatcher(url: store.statusFileURL) { [weak self] in
            self?.refresh()
        }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        loadResult = store.load()
    }

    func repairHook() throws -> SettingsInstaller.InstallOutcome {
        let scriptContents = (try? String(contentsOf: bundledStatuslineScriptURL(), encoding: .utf8))
            ?? SettingsInstaller.fallbackStatuslineScript
        let outcome = try installer.install(statuslineScriptContents: scriptContents)
        refresh()
        return outcome
    }

    private func bundledStatuslineScriptURL() -> URL {
        Bundle.main.url(forResource: "statusline", withExtension: "sh")
            ?? URL(fileURLWithPath: "/nonexistent")
    }
}
