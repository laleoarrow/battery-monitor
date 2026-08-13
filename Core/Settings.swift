import Foundation

/// Preferences that more than one surface reads. The popover writes them; the
/// status item listens and redraws.
enum Settings {
    enum Module: String, CaseIterable {
        case flow, ring, lanes, history

        var title: String {
            switch self {
            case .flow: return "Energy Flow"
            case .ring: return "Ring Gauge"
            case .lanes: return "Power Lanes"
            case .history: return "Power History"
            }
        }

        var defaultsKey: String { "popover.module.\(rawValue)" }
    }

    enum Change: Equatable {
        case menuBarPercentage
        case module(Module)
    }

    static let didChange = Notification.Name("WattsonSettingsDidChange")
    static let changeUserInfoKey = "WattsonSettingsChange"

    private static let percentageKey = "menubar.showsPercentage"
    private static let registeredDefaults: [String: Any] = {
        var values: [String: Any] = [percentageKey: true]
        for module in Module.allCases {
            values[module.defaultsKey] = true
        }
        return values
    }()

#if DEBUG
    private static var testDefaults: UserDefaults?
#endif

    private static var defaults: UserDefaults {
#if DEBUG
        let defaults = testDefaults ?? .standard
#else
        let defaults = UserDefaults.standard
#endif
        defaults.register(defaults: registeredDefaults)
        return defaults
    }

    /// Matches the system battery's "Show Percentage". On by default.
    static var showsMenuBarPercentage: Bool {
        get { defaults.object(forKey: percentageKey) as? Bool ?? true }
        set {
            guard showsMenuBarPercentage != newValue else { return }
            defaults.set(newValue, forKey: percentageKey)
            postChange(.menuBarPercentage)
        }
    }

    static func isModuleVisible(_ module: Module) -> Bool {
        defaults.object(forKey: module.defaultsKey) as? Bool ?? true
    }

    static func setModule(_ module: Module, visible: Bool) {
        guard isModuleVisible(module) != visible else { return }
        defaults.set(visible, forKey: module.defaultsKey)
        postChange(.module(module))
    }

    private static func postChange(_ change: Change) {
        NotificationCenter.default.post(
            name: didChange,
            object: nil,
            userInfo: [changeUserInfoKey: change]
        )
    }

#if DEBUG
    static func configureForTest(defaults: UserDefaults) {
        testDefaults = defaults
        defaults.register(defaults: registeredDefaults)
    }

    static func resetTestConfiguration() {
        testDefaults = nil
    }
#endif
}
