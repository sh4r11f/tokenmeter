import SwiftUI
import TokenMeterCore

struct PreferencesView: View {
    @ObservedObject var appState: AppState
    @AppStorage("launchAtLogin") private var launchAtLogin = false

    var body: some View {
        Form {
            Picker("Menu bar label", selection: $appState.labelMetric) {
                Text("5-hour limit").tag(LabelMetric.fiveHour)
                Text("7-day limit").tag(LabelMetric.sevenDay)
                Text("Whichever is more urgent").tag(LabelMetric.mostUrgent)
            }
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { newValue in
                    LaunchAtLogin.setEnabled(newValue)
                }
        }
        .padding(16)
        .frame(width: 280)
    }
}
