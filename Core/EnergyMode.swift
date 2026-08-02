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
    /// attempting it gets the process killed. The helper still reports whether
    /// this Mac supports high power, but macOS 26's lazily-written preference
    /// values are not a reliable mode readback. `pmset -g live` is authoritative
    /// and is allowed by the shipping sandbox.
    ///
    /// Cached rather than queried per read: `current` is consulted on every 1 Hz
    /// presentation refresh. The ~76 ms live read only runs on popover opens and
    /// mode changes, never in that hot path.
    private static var cachedMode: EnergyMode?
    private static var cachedSupportsHigh = false
    private static let refreshQueue = DispatchQueue(
        label: "com.leoarrow.wattson.mode-refresh", qos: .userInitiated
    )
    /// Main-thread generation. A set invalidates any slower refresh that began
    /// first, so stale readback can never overwrite the mode that just landed.
    private static var refreshGeneration = 0

    private struct ModeState {
        let mode: EnergyMode
        let supportsHigh: Bool?
    }

    static var current: EnergyMode {
        if ProcessInfo.processInfo.isLowPowerModeEnabled { return .low }
        return cachedMode ?? .auto
    }

    /// False until the helper has been asked. A segment that cannot take effect
    /// is worse than one that appears a moment late.
    static var supportsHighPower: Bool { cachedSupportsHigh }

    /// Refresh on a serial worker so the helper wake-up and the ~76 ms legacy
    /// readback cannot stall the popover's opening animation. Cache mutation and
    /// completion return to AppKit's main thread.
    static func refreshFromHelper(completion: @escaping (Bool) -> Void) {
        refreshGeneration += 1
        let generation = refreshGeneration
        refreshQueue.async {
            let state = fetchModeState()
            DispatchQueue.main.async {
                guard generation == refreshGeneration else {
                    completion(false)
                    return
                }
                guard let state else {
                    completion(false)
                    return
                }
                apply(state)
                completion(true)
            }
        }
    }

    /// Writing needs root, so it goes through the helper. Returns false when
    /// the helper is missing, refused, or when the mode did not actually take.
    @discardableResult
    static func set(_ mode: EnergyMode) -> Bool {
        refreshGeneration += 1
        guard let reply = HelperClient.send(["op": "setMode", "value": mode.rawValue]),
              reply["ok"] as? Bool == true,
              let landed = verifiedMode(from: reply) else { return false }
        apply(ModeState(
            mode: landed,
            supportsHigh: reply["supportsHigh"] as? Bool
        ))
        return landed == mode
    }

    private static func fetchModeState() -> ModeState? {
        if let reply = HelperClient.send(["op": "getMode"]),
           reply["ok"] as? Bool == true,
           let landed = verifiedMode(from: reply) {
            return ModeState(mode: landed, supportsHigh: reply["supportsHigh"] as? Bool)
        }
        // Reading does not require the helper on macOS 26. Keep presenting the
        // real mode when the helper is absent; only writes remain unavailable.
        guard let live = readLiveMode() else { return nil }
        return ModeState(mode: live, supportsHigh: live == .high ? true : nil)
    }

    private static func apply(_ state: ModeState) {
        cachedMode = state.mode
        cachedSupportsHigh = (state.supportsHigh ?? cachedSupportsHigh) || state.mode == .high
    }

    /// Helpers installed before this fix read a stale preferences plist and
    /// can report high as auto. New helpers explicitly mark their live readback;
    /// old replies are verified locally so an app-only update fixes the machine
    /// immediately without replacing the privileged helper.
    private static func verifiedMode(from reply: [String: Any]) -> EnergyMode? {
        if reply["modeVerified"] as? Bool == true,
           let raw = reply["mode"] as? String,
           let mode = EnergyMode(rawValue: raw) {
            return mode
        }
        return readLiveMode()
    }

    private static func readLiveMode() -> EnergyMode? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g", "live"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let text = String(data: data, encoding: .utf8) else { return nil }

        for line in text.split(separator: "\n") {
            let fields = line.split(whereSeparator: { $0.isWhitespace })
            guard fields.first?.lowercased() == "powermode",
                  let value = fields.last.flatMap({ Int($0) }) else { continue }
            switch value {
            case 0: return .auto
            case 1: return .low
            case 2: return .high
            default: return nil
            }
        }
        return nil
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
            if ProcessInfo.processInfo.isLowPowerModeEnabled {
                cachedMode = .low
            } else if cachedMode == .low {
                // ProcessInfo has authoritative event delivery for Low Power.
                // Clear the cached low immediately when it turns off; high/auto
                // will be refreshed on the next popover open or explicit set.
                cachedMode = .auto
            }
            handler(current)
        }
    }

}
