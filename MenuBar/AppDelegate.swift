import AppKit

/// The app has no windows — the status item owns everything. This exists only
/// to keep the process alive; the desktop panel that used to need a full
/// controller is gone.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.disableAutomaticTermination("Wattson keeps a live power monitor in the menu bar.")
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
