import Darwin
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

/// Pure policy for the ProcessInfo notification edge. ProcessInfo is
/// authoritative only for Low Power; every non-Low event needs a live read.
struct EnergyModeNotificationPolicy {
    enum Action: Equatable {
        case reportImmediately(EnergyMode)
        case refresh(provisionalMode: EnergyMode?)
    }

    static func action(
        cachedMode: EnergyMode?,
        isLowPowerModeEnabled: Bool
    ) -> Action {
        if isLowPowerModeEnabled { return .reportImmediately(.low) }
        return .refresh(provisionalMode: cachedMode == .low ? .auto : nil)
    }

    static func refreshedMode(
        didRefresh: Bool,
        isLowPowerModeEnabled: Bool,
        currentMode: EnergyMode
    ) -> EnergyMode? {
        guard didRefresh, !isLowPowerModeEnabled else { return nil }
        return currentMode
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

/// Skips queued writes that a newer UI intent superseded. Execution generations
/// advance only for writes that actually touch the helper, so fallback evidence
/// remains adjacent across any number of skipped requests.
struct LatestWriteExecutionGate {
    private(set) var executionGeneration = 0

    mutating func execute<Value>(
        requestGeneration: Int,
        latestGeneration: Int,
        operation: (Int) -> Value?
    ) -> Value? {
        guard requestGeneration == latestGeneration else { return nil }
        executionGeneration += 1
        return operation(executionGeneration)
    }
}

enum EnergyModeController {
    private static let liveModeTimeout: TimeInterval = 1.5
    private static let maximumLiveModeOutputBytes = 65_536

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
    private static let operations = CoalescingReadOperationQueue<ModeState?>(
        label: "com.leoarrow.wattson.mode-refresh",
        qos: .userInitiated
    )
    /// Reads are main-thread generations. Writes invalidate reads, while a later
    /// read must never make an in-flight write report failure. Keeping them
    /// separate also lets the latest write recover the actual state after a
    /// refusal. The write counter is locked because workers inspect it before I/O.
    private static var readGeneration = 0
    private static var writeGeneration = 0
    private static let writeGenerationLock = NSLock()

    struct ModeState {
        let mode: EnergyMode
        let supportsHigh: Bool?
    }

    /// Only touched on `operations`' worker. A failed write may recover the state
    /// authoritatively confirmed by the immediately preceding write, but no
    /// startup refresh or older write is valid evidence for this request.
    private static var lastQueueState = GenerationBoundWriteFallback<ModeState>()
    private static var writeExecutionGate = LatestWriteExecutionGate()

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
        let writesAtStart = currentWriteGeneration()
        operations.enqueueRead(
            operation: { fetchModeState() },
            completion: { state in
                guard generation == readGeneration,
                      writesAtStart == currentWriteGeneration() else {
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
        )
    }

    /// Writing needs root, so it goes through the helper. Returns false when
    /// the helper is missing, refused, or when the mode did not actually take.
    @discardableResult
    static func set(_ mode: EnergyMode) -> Bool {
        readGeneration += 1
        let generation = beginWrite()
        guard let state = operations.performMutation({
            resolveLatestModeChange(mode, requestGeneration: generation)
        }) else { return false }
        guard generation == currentWriteGeneration() else { return false }
        apply(state)
        return state.mode == mode
    }

    /// Popover controls must not wait on the helper from AppKit's event loop.
    /// This shares the same serial queue as refreshes, then returns cache
    /// mutation and completion to the main thread. A newer request invalidates
    /// an older result before it can overwrite the visible mode.
    static func set(_ mode: EnergyMode, completion: @escaping (EnergyMode?) -> Void) {
        readGeneration += 1
        let generation = beginWrite()
        operations.enqueueMutation(
            operation: { resolveLatestModeChange(mode, requestGeneration: generation) },
            completion: { state in
                guard generation == currentWriteGeneration() else {
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
        )
    }

    private static func beginWrite() -> Int {
        writeGenerationLock.lock()
        writeGeneration += 1
        let generation = writeGeneration
        writeGenerationLock.unlock()
        return generation
    }

    private static func currentWriteGeneration() -> Int {
        writeGenerationLock.lock()
        let generation = writeGeneration
        writeGenerationLock.unlock()
        return generation
    }

    private static func resolveLatestModeChange(
        _ mode: EnergyMode,
        requestGeneration: Int
    ) -> ModeState? {
        writeExecutionGate.execute(
            requestGeneration: requestGeneration,
            latestGeneration: currentWriteGeneration()
        ) { executionGeneration in
            resolveModeChange(mode, writeGeneration: executionGeneration)
        }
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
        guard let reply = HelperClient.send(
                  ["op": "setMode", "value": mode.rawValue],
                  timeoutSeconds: 8
              ),
              HelperClient.strictJSONBool(reply["ok"]) == true,
              let landed = verifiedMode(from: reply) else { return nil }
        return ModeState(
            mode: landed,
            supportsHigh: HelperClient.strictJSONBool(reply["supportsHigh"])
        )
    }

    private static func fetchModeState() -> ModeState? {
        resolveModeState(
            helper: {
                guard let reply = HelperClient.send(
                          ["op": "getMode"], timeoutSeconds: 6
                      ),
                      HelperClient.strictJSONBool(reply["ok"]) == true,
                      let landed = verifiedMode(from: reply) else { return nil }
                return ModeState(
                    mode: landed,
                    supportsHigh: HelperClient.strictJSONBool(reply["supportsHigh"])
                )
            },
            liveMode: { readLiveMode() }
        )
    }

    static func resolveModeState(
        helper: () -> ModeState?,
        liveMode: () -> EnergyMode?
    ) -> ModeState? {
        if let state = helper() { return state }
        // Reading does not require the helper on macOS 26. Keep presenting the
        // real mode when the helper is absent; only writes remain unavailable.
        guard let live = liveMode() else { return nil }
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
        if HelperClient.strictJSONBool(reply["modeVerified"]) == true,
           let raw = reply["mode"] as? String,
           let mode = EnergyMode(rawValue: raw) {
            return mode
        }
        return readLiveMode()
    }

    private static func readLiveMode(
        executableURL: URL = URL(fileURLWithPath: "/usr/bin/pmset"),
        arguments: [String] = ["-g", "live"],
        timeout: TimeInterval = liveModeTimeout,
        maximumOutputBytes: Int = maximumLiveModeOutputBytes
    ) -> EnergyMode? {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "C"
        environment["LANG"] = "C"
        process.environment = environment
        let pipe = Pipe()
        let outputReadHandle = pipe.fileHandleForReading
        let outputWriteHandle = pipe.fileHandleForWriting
        defer {
            try? outputReadHandle.close()
            try? outputWriteHandle.close()
        }
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        let outputFD = outputReadHandle.fileDescriptor
        let originalFlags = fcntl(outputFD, F_GETFL)
        guard originalFlags >= 0,
              fcntl(outputFD, F_SETFL, originalFlags | O_NONBLOCK) == 0 else { return nil }
        defer { _ = fcntl(outputFD, F_SETFL, originalFlags) }
        guard (try? process.run()) != nil else { return nil }

        let deadline = DispatchTime.now().uptimeNanoseconds
            + UInt64(timeout * 1_000_000_000)
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        var observedChildExit = false

        while true {
            var madeProgress = false
            while true {
                let count = read(outputFD, &buffer, buffer.count)
                if count > 0 {
                    guard data.count + count <= maximumOutputBytes else {
                        stopLiveModeProcess(process)
                        return nil
                    }
                    data.append(contentsOf: buffer.prefix(count))
                    madeProgress = true
                } else if count == 0
                            || (count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
                    break
                } else if count < 0, errno == EINTR {
                    continue
                } else {
                    stopLiveModeProcess(process)
                    return nil
                }
            }

            // Drain once after observing direct-child exit: bytes can arrive
            // between the previous EAGAIN and isRunning becoming false. Do
            // not wait for EOF because a descendant may inherit stdout.
            if observedChildExit { break }
            if !process.isRunning {
                observedChildExit = true
                continue
            }
            guard DispatchTime.now().uptimeNanoseconds < deadline else {
                stopLiveModeProcess(process)
                return nil
            }
            if !madeProgress {
                usleep(5_000)
            }
        }

        guard process.terminationStatus == 0,
              let text = String(data: data, encoding: .utf8) else { return nil }

        return mode(fromLiveOutput: text)
    }

    private static func stopLiveModeProcess(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        let terminationDeadline = DispatchTime.now() + .milliseconds(100)
        while process.isRunning,
              DispatchTime.now().uptimeNanoseconds < terminationDeadline.uptimeNanoseconds {
            usleep(5_000)
        }
        if process.isRunning {
            _ = kill(process.processIdentifier, SIGKILL)
        }
    }

    static func mode(fromLiveOutput text: String) -> EnergyMode? {
        for line in text.split(separator: "\n") {
            let fields = line.split(whereSeparator: { $0.isWhitespace })
            guard let key = fields.first?.lowercased(),
                  let value = fields.last.flatMap({ Int($0) }) else { continue }
            switch (key, value) {
            case ("powermode", 0), ("lowpowermode", 0): return .auto
            case ("powermode", 1), ("lowpowermode", 1): return .low
            case ("powermode", 2): return .high
            case ("powermode", _), ("lowpowermode", _): return nil
            default: continue
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
    @discardableResult
    static func observe(_ handler: @escaping (EnergyMode) -> Void) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { _ in
            let action = EnergyModeNotificationPolicy.action(
                cachedMode: cachedMode,
                isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled
            )
            switch action {
            case .reportImmediately(let mode):
                // Prevent a non-Low read already in flight from replacing the
                // authoritative Low cache after this notification. A read that
                // has not reached the shared worker is stale work, too.
                readGeneration += 1
                operations.cancelPendingRead()
                cachedMode = mode
                handler(mode)
            case .refresh(let provisionalMode):
                if let provisionalMode {
                    // ProcessInfo is authoritative that Low Power ended even
                    // when helper readback is temporarily unavailable. Clear
                    // the visible Low state immediately, then refine Auto to
                    // High if the asynchronous live read says so.
                    cachedMode = provisionalMode
                    handler(provisionalMode)
                }
                refreshFromHelper { didRefresh in
                    guard let mode = EnergyModeNotificationPolicy.refreshedMode(
                        didRefresh: didRefresh,
                        isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled,
                        currentMode: current
                    ) else { return }
                    handler(mode)
                }
            }
        }
    }

}
