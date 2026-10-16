import Foundation

/// Owns the single lane used for privileged settings requests. Keeping socket
/// operations on one serial queue prevents a request whose client deadline has
/// already elapsed from sitting behind another controller in the helper's
/// kernel accept backlog.
final class SerialOperationWorker {
    private let queue: DispatchQueue
    private let identityKey = DispatchSpecificKey<ObjectIdentifier>()
    private let identity: ObjectIdentifier

    init(label: String, qos: DispatchQoS = .default) {
        queue = DispatchQueue(label: label, qos: qos)
        identity = ObjectIdentifier(queue)
        queue.setSpecific(key: identityKey, value: identity)
    }

    var isCurrent: Bool {
        DispatchQueue.getSpecific(key: identityKey) == identity
    }

    func async(_ operation: @escaping () -> Void) {
        queue.async(execute: operation)
    }
}

enum HelperSettingsOperationWorker {
    static let shared = SerialOperationWorker(
        label: "com.leoarrow.wattson.helper-settings",
        qos: .userInitiated
    )
}

/// Runs blocking reads away from AppKit while retaining only the newest read
/// requested during an in-flight operation.
final class CoalescingReadOperationQueue<ReadValue> {
    private struct PendingRead {
        let operation: () -> ReadValue
        let completion: (ReadValue) -> Void
    }

    private let worker: SerialOperationWorker
    private let completionQueue: DispatchQueue
    private let lock = NSLock()
    private var drainScheduled = false
    private var pendingRead: PendingRead?
    private var pendingMutations: [() -> Void] = []

    init(
        label: String,
        qos: DispatchQoS = .default,
        worker: SerialOperationWorker = HelperSettingsOperationWorker.shared,
        completionQueue: DispatchQueue = .main
    ) {
        _ = label
        _ = qos
        self.worker = worker
        self.completionQueue = completionQueue
    }

    func enqueueRead(
        operation: @escaping () -> ReadValue,
        completion: @escaping (ReadValue) -> Void
    ) {
        let request = PendingRead(operation: operation, completion: completion)
        lock.lock()
        // Superseded refresh completions are intentionally dropped. This type
        // is for latest-state observation, not one-shot commands.
        pendingRead = request
        let shouldSchedule = scheduleDrainIfNeededLocked()
        lock.unlock()
        if shouldSchedule { scheduleDrain() }
    }

    func enqueueMutation<MutationValue>(
        operation: @escaping () -> MutationValue,
        completion: @escaping (MutationValue) -> Void
    ) {
        let deliveryQueue = completionQueue
        let request = {
            let value = operation()
            deliveryQueue.async { completion(value) }
        }

        lock.lock()
        // A read requested before this mutation can only report stale state.
        pendingRead = nil
        pendingMutations.append(request)
        let shouldSchedule = scheduleDrainIfNeededLocked()
        lock.unlock()
        if shouldSchedule { scheduleDrain() }
    }

    /// Drops only a refresh that has not begun. An operation already selected
    /// by the worker owns its completion; callers use generations to ignore it.
    func cancelPendingRead() {
        lock.lock()
        pendingRead = nil
        lock.unlock()
    }

    /// Synchronous compatibility for non-AppKit callers. Off the shared lane,
    /// this enters the same FIFO mutation stream and waits only for its own
    /// operation. Reentrant calls execute inline to avoid self-deadlock.
    func performMutation<MutationValue>(
        _ operation: @escaping () -> MutationValue
    ) -> MutationValue {
        if worker.isCurrent {
            lock.lock()
            pendingRead = nil
            lock.unlock()
            return operation()
        }

        let finished = DispatchSemaphore(value: 0)
        var result: (() -> MutationValue)?
        enqueueMutation(
            operation: {
                let value = operation()
                result = { value }
                finished.signal()
            },
            completion: { _ in }
        )
        finished.wait()
        return result!()
    }

    private func scheduleDrainIfNeededLocked() -> Bool {
        guard !drainScheduled else { return false }
        drainScheduled = true
        return true
    }

    private func scheduleDrain() {
        worker.async { [self] in
            drainOne()
        }
    }

    /// Selects work only after this controller actually owns the shared worker.
    /// Pending reads therefore remain replaceable/cancellable while another
    /// settings controller is slow, including the handoff between operations.
    private func drainOne() {
        lock.lock()
        let operation: (() -> Void)?
        if !pendingMutations.isEmpty {
            operation = pendingMutations.removeFirst()
        } else if let request = pendingRead {
            pendingRead = nil
            operation = { [completionQueue] in
                let value = request.operation()
                completionQueue.async { request.completion(value) }
            }
        } else {
            drainScheduled = false
            operation = nil
        }
        lock.unlock()

        guard let operation else { return }
        operation()

        // Do not select the next read yet. A foreign operation already queued
        // on the shared worker may run first; keeping the read in pendingRead
        // lets an intervening mutation cancel it before this drain is selected.
        scheduleDrain()
    }
}

enum SystemBatteryIconReadFailure: String, Equatable {
    case helperUnavailable
    case requestFailed
    case invalidReply
    case legacyUnavailable
    case userContextUnavailable
    case preferenceSyncFailed
    case preferenceMissing
    case preferenceTypeUnsupported
    case preferenceValueUnsupported
    case preferenceWorkerFailed
}

enum SystemBatteryIconReadStatus: Equatable {
    case notRequested
    case checking
    case ready
    case failed(SystemBatteryIconReadFailure)
}

struct SystemBatteryIconReadResult {
    let hidden: Bool?
    let failure: SystemBatteryIconReadFailure?
    let elapsedMilliseconds: Int
}

/// Reads and changes the Apple battery menu-extra through the privileged
/// helper. A sandboxed app cannot access another process's preferences.
enum SystemBatteryIconController {
    private struct RefreshWaiter {
        let sequence: Int
        let completion: (Bool?) -> Void
    }

    private struct MutationResult {
        let succeeded: Bool
        let readback: SystemBatteryIconReadResult?
        let failure: SystemBatteryIconReadFailure?
    }

    static let didChange = Notification.Name("WattsonSystemBatteryIconDidChange")

    private static let operations = CoalescingReadOperationQueue<SystemBatteryIconReadResult>(
        label: "com.leoarrow.wattson.system-battery-icon",
        qos: .userInitiated
    )
    /// Shared last-known Control Center state. `nil` means unknown, never
    /// "visible", so settings surfaces can keep their control indeterminate.
    private(set) static var cachedHidden: Bool?
    private(set) static var readStatus: SystemBatteryIconReadStatus = .notRequested
    private static var requestSequence = 0
    private static var latestSettledSequence = 0
    private static var refreshWaiters: [RefreshWaiter] = []
    private static var configurationGeneration = 0

#if DEBUG
    private static var testSend: (([String: Any], Int) -> [String: Any]?)?
    private static var testHelperAvailable: Bool?
#endif

    static func refreshHidden(_ completion: @escaping (Bool?) -> Void) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { refreshHidden(completion) }
            return
        }

        requestSequence += 1
        let sequence = requestSequence
        let generation = configurationGeneration
        refreshWaiters.append(RefreshWaiter(sequence: sequence, completion: completion))
        operations.enqueueRead(
            operation: { probe() },
            completion: { result in
                guard generation == configurationGeneration else { return }
                if claimPublication(for: sequence) {
                    // An older read can supply a value while a newer request
                    // is pending, but cannot finish that request's checking.
                    publish(result.hidden, status: sequence == requestSequence
                        ? result.failure.map { .failed($0) } ?? .ready : readStatus)
                }
                completeRefreshWaiters(through: sequence, with: cachedHidden)
            }
        )
        // Enqueue first: a notification observer may request another refresh.
        // Its newer read must not be replaced by this older invocation.
        publish(cachedHidden, status: .checking)
    }

    /// Blocking, read-only diagnostics. Use a worker queue, as refreshHidden
    /// does. Sharing the settings lane never cancels pending UI reads and does
    /// not publish a cache, status, or notification.
    static func probe() -> SystemBatteryIconReadResult {
        let started = DispatchTime.now().uptimeNanoseconds
        let value: (Bool?, SystemBatteryIconReadFailure?)
        if HelperSettingsOperationWorker.shared.isCurrent {
            value = readValue()
        } else {
            let finished = DispatchSemaphore(value: 0)
            var result: (Bool?, SystemBatteryIconReadFailure?)?
            HelperSettingsOperationWorker.shared.async {
                result = readValue()
                finished.signal()
            }
            finished.wait()
            value = result!
        }
        return SystemBatteryIconReadResult(
            hidden: value.0,
            failure: value.1,
            elapsedMilliseconds: Int((DispatchTime.now().uptimeNanoseconds - started) / 1_000_000)
        )
    }

    private static func readValue() -> (Bool?, SystemBatteryIconReadFailure?) {
#if DEBUG
        let available = testHelperAvailable ?? HelperClient.isInstalled
#else
        let available = HelperClient.isInstalled
#endif
        guard available else { return (nil, .helperUnavailable) }
        let reply = send(["op": "getSystemBatteryIconHidden"], timeoutSeconds: 4)
        guard let reply else { return (nil, .requestFailed) }
        guard let ok = HelperClient.strictJSONBool(reply["ok"]) else { return (nil, .invalidReply) }
        guard ok else { return (nil, failure(from: reply)) }
        guard let hidden = HelperClient.strictJSONBool(reply["hidden"]) else {
            return (nil, .invalidReply)
        }
        return (hidden, nil)
    }

    private static func failure(from reply: [String: Any]?) -> SystemBatteryIconReadFailure {
        guard let reply else { return .requestFailed }
        guard HelperClient.strictJSONBool(reply["ok"]) == false else { return .invalidReply }
        guard let raw = reply["reason"] else { return .legacyUnavailable }
        guard let reason = raw as? String else { return .invalidReply }
        switch SystemBatteryIconReadFailure(rawValue: reason) {
        case let failure? where [.userContextUnavailable, .preferenceSyncFailed,
            .preferenceMissing, .preferenceTypeUnsupported, .preferenceValueUnsupported,
            .preferenceWorkerFailed].contains(failure): return failure
        default: return .requestFailed
        }
    }

    /// Synchronous compatibility for existing non-settings callers. AppKit
    /// controls should use the completion-based overload so helper I/O never
    /// blocks an event. The legacy caller already runs on the main thread,
    /// which also keeps the shared observable cache main-thread confined.
    @discardableResult
    static func setHidden(_ hidden: Bool) -> Bool {
        precondition(Thread.isMainThread)

        requestSequence += 1
        let sequence = requestSequence
        let generation = configurationGeneration
        let result = operations.performMutation {
            mutationResult(for: hidden)
        }
        guard generation == configurationGeneration else { return false }
        settleMutation(result, sequence: sequence)
        completeRefreshWaiters(through: sequence, with: cachedHidden)
        return result.succeeded
    }

    static func setHidden(_ hidden: Bool, completion: @escaping (Bool) -> Void) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { setHidden(hidden, completion: completion) }
            return
        }

        requestSequence += 1
        let sequence = requestSequence
        let generation = configurationGeneration
        operations.enqueueMutation(
            operation: { mutationResult(for: hidden) },
            completion: { result in
                guard generation == configurationGeneration else { return }
                settleMutation(result, sequence: sequence)
                // A mutation cancels a not-yet-selected refresh. Complete any
                // callers that preceded it with the newer landed (or restored
                // last-known) state, while leaving later refreshes pending.
                completeRefreshWaiters(
                    through: sequence,
                    with: cachedHidden
                )
                completion(result.succeeded)
            }
        )
    }

    private static func mutationResult(for hidden: Bool) -> MutationResult {
        let reply = send(
            [
                "op": "setSystemBatteryIconHidden",
                "hidden": hidden,
            ],
            timeoutSeconds: 6
        )
        guard HelperClient.strictJSONBool(reply?["ok"]) == true else {
            return MutationResult(succeeded: false, readback: nil, failure: failure(from: reply))
        }

        // The setter's success means its fixed preference write and Control
        // Center restart completed. A separate fixed getter is still the
        // authority for the value that actually landed.
        let readback = probe()
        return MutationResult(
            succeeded: readback.hidden == hidden,
            readback: readback,
            failure: readback.failure
        )
    }

    private static func settleMutation(_ result: MutationResult, sequence: Int) {
        guard claimPublication(for: sequence) else { return }
        // Only an unconfirmed setter may retain the prior value. Once the
        // write succeeded, its readback is authoritative even when different
        // from the request or unknown. Also settle any canceled refresh.
        let hidden: Bool?
        if let readback = result.readback {
            hidden = readback.hidden
        } else {
            hidden = cachedHidden
        }
        let status: SystemBatteryIconReadStatus = hidden != nil
            ? .ready : .failed(result.failure ?? .requestFailed)
        publish(hidden, status: sequence == requestSequence ? status : readStatus)
    }

    /// Worker operations are serialized, but their main-queue completions can
    /// be delayed behind a newer synchronous mutation. Once a newer sequence
    /// settles, an older completion still reports its own result but can no
    /// longer publish stale shared state.
    private static func claimPublication(for sequence: Int) -> Bool {
        precondition(Thread.isMainThread)
        guard sequence >= latestSettledSequence else { return false }
        latestSettledSequence = sequence
        return true
    }

    private static func send(
        _ request: [String: Any],
        timeoutSeconds: Int
    ) -> [String: Any]? {
#if DEBUG
        if let testSend { return testSend(request, timeoutSeconds) }
#endif
        return HelperClient.send(request, timeoutSeconds: timeoutSeconds)
    }

    private static func publish(_ hidden: Bool?, status: SystemBatteryIconReadStatus) {
        precondition(Thread.isMainThread)
        guard cachedHidden != hidden || readStatus != status else { return }
        cachedHidden = hidden
        readStatus = status
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    private static func completeRefreshWaiters(
        through sequence: Int,
        with hidden: Bool?
    ) {
        precondition(Thread.isMainThread)
        var completed: [(Bool?) -> Void] = []
        refreshWaiters.removeAll { waiter in
            guard waiter.sequence <= sequence else { return false }
            completed.append(waiter.completion)
            return true
        }
        completed.forEach { $0(hidden) }
    }

#if DEBUG
    static func configureForTest(
        initialHidden: Bool? = nil,
        helperAvailable: Bool = true,
        send: @escaping ([String: Any], Int) -> [String: Any]?
    ) {
        precondition(Thread.isMainThread)
        // The injected closure runs on the shared settings worker. Cross that
        // lane before replacing it so no prior request can race test setup.
        operations.performMutation {}
        configurationGeneration += 1
        testSend = send
        testHelperAvailable = helperAvailable
        requestSequence = 0
        latestSettledSequence = 0
        refreshWaiters.removeAll()
        cachedHidden = initialHidden
        readStatus = initialHidden == nil ? .notRequested : .ready
    }

    static func resetTestConfiguration() {
        precondition(Thread.isMainThread)
        // Cross the same worker before releasing the injected sender. Main
        // completions already queued by an older generation are then ignored.
        operations.performMutation {}
        configurationGeneration += 1
        testSend = nil
        testHelperAvailable = nil
        requestSequence = 0
        latestSettledSequence = 0
        refreshWaiters.removeAll()
        cachedHidden = nil
        readStatus = .notRequested
    }
#endif
}
