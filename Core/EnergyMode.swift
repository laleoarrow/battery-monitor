import Foundation

/// macOS exposes three energy modes on Apple silicon that supports it.
/// `pmset` calls them powermode 0 / 1 / 2.
enum EnergyMode: String {
    case low
    case auto
    case high

    var title: String {
        switch self {
        case .low: return "Low Power"
        case .auto: return "自动"
        case .high: return "High Power"
        }
    }
}

enum EnergyModeController {
    /// The app is sandboxed, so it cannot read /Library/Preferences at all —
    /// attempting it gets the process killed. Low power still has a first-class
    /// API that works inside the sandbox; high power only exists in those
    /// preferences, so the helper (root, unsandboxed) has to report it.
    ///
    /// Cached rather than queried per read: `current` is consulted on every
    /// menu bar refresh, and each query wakes the helper through launchd.
    private static var cachedHelperMode: EnergyMode?
    private static var cachedSupportsHigh = false

    static var current: EnergyMode {
        if ProcessInfo.processInfo.isLowPowerModeEnabled { return .low }
        return cachedHelperMode == .high ? .high : .auto
    }

    /// False until the helper has been asked. A segment that cannot take effect
    /// is worse than one that appears a moment late.
    static var supportsHighPower: Bool { cachedSupportsHigh }

    /// Refresh the cache from the helper. Cheap enough for popover opens and
    /// mode changes; far too expensive for the 1 Hz refresh.
    @discardableResult
    static func refreshFromHelper() -> Bool {
        guard let reply = HelperClient.send(["op": "getMode"]),
              reply["ok"] as? Bool == true else { return false }
        if let raw = reply["mode"] as? String { cachedHelperMode = EnergyMode(rawValue: raw) }
        cachedSupportsHigh = (reply["supportsHigh"] as? Bool) ?? false
        return true
    }

    /// Writing needs root, so it goes through the helper. Returns false when
    /// the helper is missing or refused.
    @discardableResult
    static func set(_ mode: EnergyMode) -> Bool {
        guard let reply = HelperClient.send(["op": "setMode", "value": mode.rawValue]),
              reply["ok"] as? Bool == true else { return false }
        if let raw = reply["mode"] as? String { cachedHelperMode = EnergyMode(rawValue: raw) }
        cachedSupportsHigh = (reply["supportsHigh"] as? Bool) ?? cachedSupportsHigh
        return true
    }

    /// The right-click gesture stays a two-state toggle between 省电 and 自动.
    /// A three-way cycle on a control with no visible state is a guessing game;
    /// high power is reachable from the popover, where the current mode is on
    /// screen next to the alternatives.
    @discardableResult
    static func toggle() -> Bool {
        set(current == .low ? .auto : .low)
    }

    /// Event-driven. The system tells us; we never poll.
    static func observe(_ handler: @escaping (EnergyMode) -> Void) {
        NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { _ in
            handler(current)
        }
    }

}
