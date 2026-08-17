import SwiftUI
import TokenMeterCore

struct MenuBarContentView: View {
    @ObservedObject var appState: AppState
    @State private var showingPreferences = false
    @State private var installerMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            statusSection
            Divider()
            Button("Repair hook") { repair() }
            Button("Preferences…") { showingPreferences = true }
            if let installerMessage {
                Text(installerMessage).font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            Button("Quit TokenMeter") { NSApplication.shared.terminate(nil) }
        }
        .padding(12)
        .frame(width: 260)
        .sheet(isPresented: $showingPreferences) {
            PreferencesView(appState: appState)
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        switch appState.loadResult {
        case .notInstalled:
            Text("Not installed yet").font(.headline)
            Text("Click Repair hook to set up the Claude Code status line integration.")
                .font(.caption).foregroundStyle(.secondary)

        case .decodeError:
            Text("Couldn't read usage data").font(.headline)

        case .noRateLimitData(let capturedAt, let isStale):
            Text("No subscription rate limit data").font(.headline)
            Text("This shows up for Claude.ai subscription plans, not API-key usage.")
                .font(.caption).foregroundStyle(.secondary)
            lastUpdated(capturedAt, isStale)

        case .ok(let snapshot, let isStale):
            if let five = snapshot.rateLimits?.fiveHour {
                windowRow(title: "5-hour session", window: five)
            }
            if let seven = snapshot.rateLimits?.sevenDay {
                windowRow(title: "7-day weekly", window: seven)
            }
            lastUpdated(snapshot.capturedAt, isStale)
        }
    }

    private func windowRow(title: String, window: RateLimitWindow) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.subheadline).bold()
            Text("\(Int(window.usedPercentage.rounded()))% used · \(Int((100 - window.usedPercentage).rounded()))% left")
            Text("Resets \(window.resetsAt.formatted(.relative(presentation: .named)))")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func lastUpdated(_ date: Date, _ isStale: Bool) -> some View {
        Text(isStale
             ? "Updated \(date.formatted(.relative(presentation: .named))) — stale"
             : "Updated \(date.formatted(.relative(presentation: .named)))")
            .font(.caption2).foregroundStyle(.secondary)
    }

    private func repair() {
        do {
            let outcome = try appState.repairHook()
            switch outcome {
            case .installedFresh: installerMessage = "Hook installed."
            case .alreadyInstalled: installerMessage = "Already installed."
            case .wrapped: installerMessage = "Hook installed alongside your existing status line."
            }
        } catch {
            installerMessage = "Couldn't install: \(error.localizedDescription)"
        }
    }
}
