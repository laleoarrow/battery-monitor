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
    /// Reading costs nothing and needs no helper. Low power has a first-class
    /// API; high power only exists in the power-management preferences.
    static var current: EnergyMode {
        if ProcessInfo.processInfo.isLowPowerModeEnabled { return .low }
        return flag("HighPowerMode") == 1 ? .high : .auto
    }

    /// True when this Mac offers high power mode at all. A segment that can
    /// never take effect is worse than no segment.
    ///
    /// The HighPowerMode key only appears on hardware that has the feature, so
    /// its presence is the check — no chip-name guessing.
    static var supportsHighPower: Bool {
        activePreferences()?.values.contains { $0["HighPowerMode"] != nil } ?? false
    }

    /// Writing needs root, so it goes through the helper. Returns false when
    /// the helper is missing or refused.
    @discardableResult
    static func set(_ mode: EnergyMode) -> Bool {
        let reply = HelperClient.send(["op": "setMode", "value": mode.rawValue])
        return (reply?["ok"] as? Bool) ?? false
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

    /// Read from the machine's power-management preferences rather than by
    /// forking pmset. The file is world-readable; only writing needs root.
    private static func activePreferences() -> [String: [String: Any]]? {
        let directory = "/Library/Preferences"
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory) else { return nil }
        // The per-machine file carries the power-mode keys. The plain
        // com.apple.PowerManagement.plist does not.
        for name in names
        where name.hasPrefix("com.apple.PowerManagement.") && name.hasSuffix(".plist") {
            guard let raw = NSDictionary(contentsOfFile: "\(directory)/\(name)") as? [String: Any] else { continue }
            let sources = raw.compactMapValues { $0 as? [String: Any] }
            if sources.values.contains(where: { $0["HighPowerMode"] != nil || $0["LowPowerMode"] != nil }) {
                return sources
            }
        }
        return nil
    }

    private static func flag(_ key: String) -> Int {
        guard let prefs = activePreferences() else { return 0 }
        // `pmset -a` writes both sources, so either answers the question.
        for source in ["AC Power", "Battery Power"] {
            if let value = prefs[source]?[key] as? Int { return value }
        }
        return 0
    }
}
