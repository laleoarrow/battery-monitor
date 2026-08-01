import Foundation

/// Preferences that more than one surface reads. The popover writes them; the
/// status item listens and redraws.
enum Settings {
    static let didChange = Notification.Name("WattsonSettingsDidChange")

    private static let percentageKey = "menubar.showsPercentage"

    /// Matches the system battery's "Show Percentage". On by default.
    static var showsMenuBarPercentage: Bool {
        get { UserDefaults.standard.object(forKey: percentageKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: percentageKey)
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }
}
