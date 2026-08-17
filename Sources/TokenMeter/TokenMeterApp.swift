import SwiftUI

@main
struct TokenMeterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            Text("TokenMeter")
        } label: {
            Text("TM")
        }
        .menuBarExtraStyle(.window)
    }
}
