import Foundation

/// Preferences that more than one surface reads. The popover writes them; the
/// status item listens and redraws.
enum Settings {
    /// Stable persisted values for Wattson's own menu-bar glyph. A typed enum
    /// keeps unknown future values from leaking into rendering code.
    enum MenuBarIconStyle: String, CaseIterable {
        case wattson
        case native
    }

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
        case menuBarIconStyle
        case module(Module)
    }

    static let didChange = Notification.Name("WattsonSettingsDidChange")
    static let changeUserInfoKey = "WattsonSettingsChange"

    private static let percentageKey = "menubar.showsPercentage"
    private static let iconStyleKey = "menubar.iconStyle"
    private static let registeredDefaults: [String: Any] = {
        var values: [String: Any] = [
            percentageKey: true,
            iconStyleKey: MenuBarIconStyle.wattson.rawValue,
        ]
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

    /// Defaults to Wattson's existing artwork so an upgrade never changes the
    /// menu-bar appearance without the user's choice.
    static var menuBarIconStyle: MenuBarIconStyle {
        get {
            guard let rawValue = defaults.string(forKey: iconStyleKey) else {
                return .wattson
            }
            return MenuBarIconStyle(rawValue: rawValue) ?? .wattson
        }
        set {
            guard menuBarIconStyle != newValue else { return }
            defaults.set(newValue.rawValue, forKey: iconStyleKey)
            postChange(.menuBarIconStyle)
        }
    }

    /// Lands both dimensions of a complete menu-bar appearance before either
    /// existing notification is posted. Settings surfaces can therefore move
    /// between the four presets without observers briefly selecting an
    /// intermediate icon/percentage combination.
    static func setMenuBarAppearance(
        iconStyle: MenuBarIconStyle,
        showsPercentage: Bool
    ) {
        let iconStyleChanged = menuBarIconStyle != iconStyle
        let percentageChanged = showsMenuBarPercentage != showsPercentage
        guard iconStyleChanged || percentageChanged else { return }

        defaults.set(iconStyle.rawValue, forKey: iconStyleKey)
        defaults.set(showsPercentage, forKey: percentageKey)
        if iconStyleChanged { postChange(.menuBarIconStyle) }
        if percentageChanged { postChange(.menuBarPercentage) }
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
