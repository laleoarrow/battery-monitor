import Foundation

enum EnergyMode: String {
    case low
    case auto
}

enum EnergyModeController {
    /// Reading is free and needs no helper.
    static var current: EnergyMode {
        ProcessInfo.processInfo.isLowPowerModeEnabled ? .low : .auto
    }

    /// Writing needs root, so it goes through the helper. Returns false when
    /// the helper is missing or refused.
    @discardableResult
    static func toggle() -> Bool {
        let target: EnergyMode = current == .low ? .auto : .low
        let reply = HelperClient.send(["op": "setMode", "value": target.rawValue])
        return (reply?["ok"] as? Bool) ?? false
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
