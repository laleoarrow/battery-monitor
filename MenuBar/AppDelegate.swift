import AppKit

/// The status item remains the UI lifetime root, including the retained
/// Settings window. Dock presentation is opt-in and applied only at launch.
final class AppDelegate: NSObject, NSApplicationDelegate {
    var onDockReopen: (() -> Void)?
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
        applyDockIconAtLaunch()
        launchUpdateCheck.start()
    }

    private func applyDockIconAtLaunch() {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        guard let resource = Settings.dockIconStyle.imageResourceName(isDark: isDark),
              let image = NSImage(named: resource) else { return }
        // The bitmap belongs to this process. Do not write the signed bundle
        // or observe live preference changes: users opt in on their next launch.
        NSApp.applicationIconImage = image
        NSApp.setActivationPolicy(.regular)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard sender.activationPolicy() == .regular else { return true }
        onDockReopen?()
        return false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
