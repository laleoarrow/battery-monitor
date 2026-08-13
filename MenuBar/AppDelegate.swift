import AppKit

/// The status item remains the UI lifetime root, including the retained
/// Settings window. The delegate only keeps the accessory process alive.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.disableAutomaticTermination("Wattson keeps a live power monitor in the menu bar.")
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
