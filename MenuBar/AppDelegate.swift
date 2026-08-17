import AppKit

/// The status item remains the UI lifetime root, including the retained
/// Settings window. The delegate only keeps the accessory process alive.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let launchUpdateCheck = UpdateLaunchController(
        shouldCheck: { Settings.checksForUpdatesOnLaunch },
        check: { UpdateChecker.shared.check(completion: $0) },
        present: { release in
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "Wattson \(release.version) is available"
            alert.informativeText =
                "You’re using an older version of Wattson. Open the GitHub release to download the update."
            alert.addButton(withTitle: "Open Release")
            alert.addButton(withTitle: "Not Now")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(release.pageURL)
            }
        }
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.disableAutomaticTermination("Wattson keeps a live power monitor in the menu bar.")
        launchUpdateCheck.start()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
