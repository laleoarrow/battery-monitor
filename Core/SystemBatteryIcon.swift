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

/// Reads and changes the Apple battery menu-extra through the privileged
/// helper. A sandboxed app cannot access another process's preferences.
enum SystemBatteryIconController {
    private struct RefreshWaiter {
        let sequence: Int
        let completion: (Bool?) -> Void
    }

    private struct MutationResult {
        let succeeded: Bool
        let landedHidden: Bool?
    }

    static let didChange = Notification.Name("WattsonSystemBatteryIconDidChange")

    private static let operations = CoalescingReadOperationQueue<Bool?>(
        label: "com.leoarrow.wattson.system-battery-icon",
        qos: .userInitiated
    )
    /// Shared last-known Control Center state. `nil` means unknown, never
    /// "visible", so settings surfaces can keep their control indeterminate.
    private(set) static var cachedHidden: Bool?
    private static var requestSequence = 0
    private static var latestSettledSequence = 0
    private static var refreshWaiters: [RefreshWaiter] = []
    private static var configurationGeneration = 0

#if DEBUG
    private static var testSend: (([String: Any], Int) -> [String: Any]?)?
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
            operation: {
                let reply = send(
                    ["op": "getSystemBatteryIconHidden"], timeoutSeconds: 4
                )
                guard HelperClient.strictJSONBool(reply?["ok"]) == true else { return nil }
                return HelperClient.strictJSONBool(reply?["hidden"])
            },
            completion: { hidden in
                guard generation == configurationGeneration else { return }
                if claimPublication(for: sequence) {
                    publish(hidden)
                }
                completeRefreshWaiters(through: sequence, with: cachedHidden)
            }
        )
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
        if claimPublication(for: sequence), result.succeeded {
            publish(result.landedHidden)
        }
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
                if claimPublication(for: sequence), result.succeeded {
                    // Only the separate authoritative readback may publish a
                    // mutation. A mismatch is failure and preserves the prior
                    // cache rather than briefly advertising the requested UI.
                    publish(result.landedHidden)
                }
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
            return MutationResult(succeeded: false, landedHidden: nil)
        }

        // The setter's success means its fixed preference write and Control
        // Center restart completed. A separate fixed getter is still the
        // authority for the value that actually landed.
        let readback = send(
            ["op": "getSystemBatteryIconHidden"], timeoutSeconds: 4
        )
        guard HelperClient.strictJSONBool(readback?["ok"]) == true,
              let landedHidden = HelperClient.strictJSONBool(readback?["hidden"])
        else {
            return MutationResult(succeeded: false, landedHidden: nil)
        }
        return MutationResult(
            succeeded: landedHidden == hidden,
            landedHidden: landedHidden
        )
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

    private static func publish(_ hidden: Bool?) {
        precondition(Thread.isMainThread)
        guard cachedHidden != hidden else { return }
        cachedHidden = hidden
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
        send: @escaping ([String: Any], Int) -> [String: Any]?
    ) {
        precondition(Thread.isMainThread)
        // The injected closure runs on the shared settings worker. Cross that
        // lane before replacing it so no prior request can race test setup.
        operations.performMutation {}
        configurationGeneration += 1
        testSend = send
        requestSequence = 0
        latestSettledSequence = 0
        refreshWaiters.removeAll()
        cachedHidden = initialHidden
    }

    static func resetTestConfiguration() {
        precondition(Thread.isMainThread)
        // Cross the same worker before releasing the injected sender. Main
        // completions already queued by an older generation are then ignored.
        operations.performMutation {}
        configurationGeneration += 1
        testSend = nil
        requestSequence = 0
        latestSettledSequence = 0
        refreshWaiters.removeAll()
        cachedHidden = nil
    }
#endif
}
