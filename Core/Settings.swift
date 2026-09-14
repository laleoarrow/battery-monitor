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

    enum LiquidGlassStyle: String, CaseIterable {
        case regular
        case clear
    }

    enum ColorScheme: String, CaseIterable {
        case system, light, dark

        var title: String {
            switch self {
            case .system: return "System"
            case .light: return "Light"
            case .dark: return "Dark"
            }
        }
    }

    /// Branding inside Wattson only, independent of the system and menu-bar icons.
    enum InAppLogoStyle: String, CaseIterable {
        case color
        case clear
    }

    /// Applied at launch only. Hidden preserves the menu-bar-only default;
    /// visible choices use static Dock artwork, never the Finder bundle icon.
    enum DockIconStyle: String, CaseIterable {
        case hidden
        case color
        case clear

        var title: String {
            switch self {
            case .hidden: return "Hidden"
            case .color: return "Color"
            case .clear: return "Clear"
            }
        }

        func imageResourceName(isDark: Bool) -> String? {
            switch self {
            case .hidden: return nil
            case .color: return "AppDockLogoColor"
            case .clear: return isDark ? "AppDockLogoClearDark" : "AppDockLogoClearLight"
            }
        }
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
        case checkForUpdatesOnLaunch
        case liquidGlassAppearance
        case liquidGlassTransparency
        case colorScheme
        case inAppLogoStyle
        case dockIconStyle
        case module(Module)
    }

    static let didChange = Notification.Name("WattsonSettingsDidChange")
    static let changeUserInfoKey = "WattsonSettingsChange"

    private static let percentageKey = "menubar.showsPercentage"
    private static let iconStyleKey = "menubar.iconStyle"
    private static let checkForUpdatesOnLaunchKey = "updates.checkOnLaunch"
    private static let liquidGlassKey = "appearance.liquidGlassEnabled"
    private static let liquidGlassStyleKey = "appearance.liquidGlassStyle"
    private static let liquidGlassTransparencyKey = "appearance.liquidGlassTransparency"
    private static let colorSchemeKey = "appearance.colorScheme"
    private static let inAppLogoStyleKey = "appearance.inAppLogoStyle"
    private static let dockIconStyleKey = "appearance.dockIconStyle"
#if DEBUG
    private static var testDefaults: UserDefaults?
#endif

    // Each typed getter owns its fallback; no second default table is needed.
    private static var defaults: UserDefaults {
#if DEBUG
        return testDefaults ?? .standard
#else
        return .standard
#endif
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

    /// Checks the stable GitHub release once per process launch. This is on by
    /// default, matching the conventional behavior of native Mac apps, and it
    /// never downloads or installs an update without a separate user action.
    static var checksForUpdatesOnLaunch: Bool {
        get { defaults.object(forKey: checkForUpdatesOnLaunchKey) as? Bool ?? true }
        set {
            guard checksForUpdatesOnLaunch != newValue else { return }
            defaults.set(newValue, forKey: checkForUpdatesOnLaunchKey)
            postChange(.checkForUpdatesOnLaunch)
        }
    }

    /// Opt-in presentation only. Upgrades retain the 4.0.0 appearance, including
    /// the materials supplied by the operating system in that version.
    static var liquidGlassEnabled: Bool {
        get { defaults.object(forKey: liquidGlassKey) as? Bool ?? false }
        set {
            guard liquidGlassEnabled != newValue else { return }
            defaults.set(newValue, forKey: liquidGlassKey)
            postChange(.liquidGlassAppearance)
        }
    }

    /// The popup background choice survives turning glass off or using an
    /// older macOS version. Unknown values retain the more legible default.
    static var liquidGlassStyle: LiquidGlassStyle {
        get {
            guard let value = defaults.string(forKey: liquidGlassStyleKey) else {
                return .regular
            }
            return LiquidGlassStyle(rawValue: value) ?? .regular
        }
        set {
            guard liquidGlassStyle != newValue else { return }
            defaults.set(newValue.rawValue, forKey: liquidGlassStyleKey)
            postChange(.liquidGlassAppearance)
        }
    }

    /// Relative background transparency: 0 is solid, 1 retains native glass.
    /// The default adds no fill, preserving the existing material on upgrade.
    static var liquidGlassTransparency: Double {
        get {
            guard let value = defaults.object(forKey: liquidGlassTransparencyKey) as? Double,
                  value.isFinite else { return 1 }
            return min(max(value, 0), 1)
        }
        set {
            guard newValue.isFinite else { return }
            let value = min(max(newValue, 0), 1)
            guard liquidGlassTransparency != value else { return }
            defaults.set(value, forKey: liquidGlassTransparencyKey)
            postChange(.liquidGlassTransparency)
        }
    }

    /// Independent of glass materials; System follows macOS without an override.
    static var colorScheme: ColorScheme {
        get {
            guard let value = defaults.string(forKey: colorSchemeKey) else { return .system }
            return ColorScheme(rawValue: value) ?? .system
        }
        set {
            guard colorScheme != newValue else { return }
            defaults.set(newValue.rawValue, forKey: colorSchemeKey)
            postChange(.colorScheme)
        }
    }

    static var inAppLogoStyle: InAppLogoStyle {
        get {
            guard let value = defaults.string(forKey: inAppLogoStyleKey) else { return .color }
            return InAppLogoStyle(rawValue: value) ?? .color
        }
        set {
            guard inAppLogoStyle != newValue else { return }
            defaults.set(newValue.rawValue, forKey: inAppLogoStyleKey)
            postChange(.inAppLogoStyle)
        }
    }

    static var dockIconStyle: DockIconStyle {
        get {
            guard let value = defaults.string(forKey: dockIconStyleKey) else { return .hidden }
            return DockIconStyle(rawValue: value) ?? .hidden
        }
        set {
            guard dockIconStyle != newValue else { return }
            defaults.set(newValue.rawValue, forKey: dockIconStyleKey)
            postChange(.dockIconStyle)
        }
    }

    /// Keep the saved choice when moving between OS versions; never simulate
    /// native Liquid Glass on systems that do not provide it.
    static var usesLiquidGlass: Bool {
        if #available(macOS 26.0, *) { return liquidGlassEnabled }
        return false
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
    }

    static func resetTestConfiguration() {
        testDefaults = nil
    }
#endif
}
