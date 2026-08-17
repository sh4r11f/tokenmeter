import AppKit

/// Suppresses the Dock icon and app switcher entry — TokenMeter only
/// lives in the menu bar. Set programmatically (rather than relying only
/// on Info.plist's LSUIElement) so `swift run` behaves correctly during
/// development, where there's no bundled Info.plist.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
