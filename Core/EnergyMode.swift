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
        case .auto: return "Auto"
        case .high: return "High Power"
        }
    }
}

/// Retains an authoritative result only for the immediately following write.
/// A fallback is never re-recorded, so one confirmed state cannot leak across
/// multiple failed requests.
struct GenerationBoundWriteFallback<Value> {
    private var confirmed: (writeGeneration: Int, value: Value)?

    mutating func resolve(
        forWriteGeneration generation: Int,
        request: () -> Value?,
        readback: () -> Value?
    ) -> Value? {
        if let value = request() ?? readback() {
            confirmed = (generation, value)
            return value
        }
        guard generation > 0,
              let confirmed,
              confirmed.writeGeneration == generation - 1 else { return nil }
        return confirmed.value
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
    private static let queueKey = DispatchSpecificKey<Void>()
    private static let refreshQueue: DispatchQueue = {
        let queue = DispatchQueue(
            label: "com.leoarrow.wattson.mode-refresh", qos: .userInitiated
        )
        queue.setSpecific(key: queueKey, value: ())
        return queue
    }()
    /// Main-thread generations. Writes invalidate reads, while a later read
    /// must never make an in-flight write report failure. Keeping them separate
    /// also lets the latest write recover the actual state after a refusal.
    private static var readGeneration = 0
    private static var writeGeneration = 0

    private struct ModeState {
        let mode: EnergyMode
        let supportsHigh: Bool?
    }

    /// Only touched on `refreshQueue`. A failed write may recover the state
    /// authoritatively confirmed by the immediately preceding write, but no
    /// startup refresh or older write is valid evidence for this request.
    private static var lastQueueState = GenerationBoundWriteFallback<ModeState>()

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
        readGeneration += 1
        let generation = readGeneration
        let writesAtStart = writeGeneration
        refreshQueue.async {
            let state = fetchModeState()
            DispatchQueue.main.async {
                guard generation == readGeneration,
                      writesAtStart == writeGeneration else {
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
        readGeneration += 1
        writeGeneration += 1
        let generation = writeGeneration
        guard let state = performOnRefreshQueue({
            resolveModeChange(mode, writeGeneration: generation)
        }) else { return false }
        apply(state)
        return state.mode == mode
    }

    /// Popover controls must not wait on the helper from AppKit's event loop.
    /// This shares the same serial queue as refreshes, then returns cache
    /// mutation and completion to the main thread. A newer request invalidates
    /// an older result before it can overwrite the visible mode.
    static func set(_ mode: EnergyMode, completion: @escaping (EnergyMode?) -> Void) {
        readGeneration += 1
        writeGeneration += 1
        let generation = writeGeneration
        refreshQueue.async {
            let state = resolveModeChange(mode, writeGeneration: generation)
            DispatchQueue.main.async {
                guard generation == writeGeneration else {
                    completion(nil)
                    return
                }
                guard let state else {
                    completion(nil)
                    return
                }
                apply(state)
                completion(state.mode)
            }
        }
    }

    private static func performOnRefreshQueue<T>(_ operation: () -> T) -> T {
        if DispatchQueue.getSpecific(key: queueKey) != nil { return operation() }
        return refreshQueue.sync(execute: operation)
    }

    /// A failed write is followed by an authoritative read on the same serial
    /// queue. This makes A-success/B-failure resolve to A, not the state that
    /// happened to be cached before either request began.
    private static func resolveModeChange(
        _ mode: EnergyMode,
        writeGeneration generation: Int
    ) -> ModeState? {
        lastQueueState.resolve(
            forWriteGeneration: generation,
            request: { requestModeChange(mode) },
            readback: { fetchModeState() }
        )
    }

    private static func requestModeChange(_ mode: EnergyMode) -> ModeState? {
        guard let reply = HelperClient.send(["op": "setMode", "value": mode.rawValue]),
              reply["ok"] as? Bool == true,
              let landed = verifiedMode(from: reply) else { return nil }
        return ModeState(
            mode: landed,
            supportsHigh: reply["supportsHigh"] as? Bool
        )
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

    /// The right-click gesture stays a two-state toggle between Low Power and Auto.
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
