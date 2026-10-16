import pathlib
from local_runtime import TemporaryDirectory, run
import textwrap
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
CLIENT_SOURCE = ROOT / "Core" / "HelperClient.swift"
SYSTEM_BATTERY_SOURCE = ROOT / "Core" / "SystemBatteryIcon.swift"


class SystemBatteryStateContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = SYSTEM_BATTERY_SOURCE.read_text(encoding="utf-8")

    def test_shared_state_contract_runs_against_the_production_controller(self):
        harness = textwrap.dedent(
            r"""
            import Foundation

            func require(_ condition: @autoclosure () -> Bool, _ message: String) {
                if !condition() {
                    FileHandle.standardError.write(Data((message + "\n").utf8))
                    exit(1)
                }
            }

            @discardableResult
            func waitUntil(
                timeout: TimeInterval = 2,
                _ condition: () -> Bool
            ) -> Bool {
                let deadline = Date().addingTimeInterval(timeout)
                while !condition(), Date() < deadline {
                    RunLoop.current.run(
                        mode: .default,
                        before: Date().addingTimeInterval(0.005)
                    )
                }
                return condition()
            }

            final class StubSender {
                private let lock = NSLock()
                private var responses: [[String: Any]?] = []
                private(set) var requests: [[String: Any]] = []

                func append(_ response: [String: Any]?) {
                    lock.lock()
                    responses.append(response)
                    lock.unlock()
                }

                func send(_ request: [String: Any], _: Int) -> [String: Any]? {
                    lock.lock()
                    defer { lock.unlock() }
                    requests.append(request)
                    require(!responses.isEmpty, "unexpected helper request")
                    return responses.removeFirst()
                }

                var requestCount: Int {
                    lock.lock()
                    defer { lock.unlock() }
                    return requests.count
                }
            }

            func stateName(_ state: Bool?) -> String {
                switch state {
                case true?: return "hidden"
                case false?: return "shown"
                case nil: return "unknown"
                }
            }

            let sender = StubSender()
            SystemBatteryIconController.configureForTest { request, timeout in
                sender.send(request, timeout)
            }
            defer { SystemBatteryIconController.resetTestConfiguration() }

            require(Thread.isMainThread, "fixture must start on main")
            require(
                SystemBatteryIconController.cachedHidden == nil,
                "unknown cache must remain nil rather than becoming false"
            )
            require(SystemBatteryIconController.readStatus == .notRequested,
                    "initial state is not a failed read")

            let probeCases: [(String, [String: Any]?, Bool?, SystemBatteryIconReadFailure?)] = [
                ("shown", ["ok": true, "hidden": false], false, nil),
                ("hidden", ["ok": true, "hidden": true], true, nil),
                ("transport", nil, nil, .requestFailed),
                ("missing hidden", ["ok": true], nil, .invalidReply),
                ("numeric hidden", ["ok": true, "hidden": 1], nil, .invalidReply),
                ("numeric ok", ["ok": 1, "hidden": false], nil, .invalidReply),
                ("legacy", ["ok": false, "error": "unknown battery preference"], nil, .legacyUnavailable),
                ("unknown reason", ["ok": false, "reason": "private raw detail"], nil, .requestFailed),
                ("client-only reason", ["ok": false, "reason": "helperUnavailable"], nil, .requestFailed),
                ("wrong reason type", ["ok": false, "reason": 1], nil, .invalidReply),
                ("user context", ["ok": false, "reason": "userContextUnavailable"], nil, .userContextUnavailable),
                ("sync", ["ok": false, "reason": "preferenceSyncFailed"], nil, .preferenceSyncFailed),
                ("missing", ["ok": false, "reason": "preferenceMissing"], nil, .preferenceMissing),
                ("type", ["ok": false, "reason": "preferenceTypeUnsupported"], nil, .preferenceTypeUnsupported),
                ("value", ["ok": false, "reason": "preferenceValueUnsupported"], nil, .preferenceValueUnsupported),
                ("worker", ["ok": false, "reason": "preferenceWorkerFailed"], nil, .preferenceWorkerFailed),
            ]
            for (name, response, hidden, failure) in probeCases {
                sender.append(response)
                let result = SystemBatteryIconController.probe()
                require(result.hidden == hidden && result.failure == failure, "\(name) probe classification")
                require(result.elapsedMilliseconds >= 0, "probe elapsed time is nonnegative")
                require(SystemBatteryIconController.cachedHidden == nil
                        && SystemBatteryIconController.readStatus == .notRequested,
                        "read-only probe does not publish state")
            }
            SystemBatteryIconController.configureForTest(helperAvailable: false) { _, _ in
                require(false, "absent helper must not receive an IPC request")
                return nil
            }
            let absent = SystemBatteryIconController.probe()
            require(absent.hidden == nil && absent.failure == .helperUnavailable, "absent helper classification")
            SystemBatteryIconController.configureForTest { request, timeout in
                sender.send(request, timeout)
            }

            var notifications: [String] = []
            var readNotifications: [SystemBatteryIconReadStatus] = []
            var lastNotifiedValue = stateName(SystemBatteryIconController.cachedHidden)
            var notificationsOnMain = true
            let observer = NotificationCenter.default.addObserver(
                forName: SystemBatteryIconController.didChange,
                object: nil,
                queue: .main
            ) { _ in
                notificationsOnMain = notificationsOnMain && Thread.isMainThread
                readNotifications.append(SystemBatteryIconController.readStatus)
                let value = stateName(SystemBatteryIconController.cachedHidden)
                if value != lastNotifiedValue {
                    notifications.append(value)
                    lastNotifiedValue = value
                }
            }
            defer { NotificationCenter.default.removeObserver(observer) }

            sender.append(["ok": true, "hidden": false])
            var completed = false
            var completionOnMain = false
            var refreshed: Bool?
            SystemBatteryIconController.refreshHidden { value in
                completionOnMain = Thread.isMainThread
                refreshed = value
                completed = true
            }
            require(SystemBatteryIconController.readStatus == .checking, "refresh immediately reports checking")
            require(notifications.isEmpty, "checking does not invent a battery preference")
            require(waitUntil { completed }, "successful refresh completion")
            require(completionOnMain, "refresh completion must use main thread")
            require(refreshed == false, "refresh returns authoritative shown state")
            require(SystemBatteryIconController.cachedHidden == false, "refresh updates cache")
            require(notifications == ["shown"], "first known state sends one notification")
            require(readNotifications == [.checking, .ready], "checking and ready each notify")

            sender.append(["ok": true, "hidden": false])
            completed = false
            SystemBatteryIconController.refreshHidden { value in
                refreshed = value
                completed = true
            }
            require(SystemBatteryIconController.cachedHidden == false, "checking preserves last authoritative cache")
            require(waitUntil { completed }, "same-state refresh completion")
            require(refreshed == false, "same-state refresh still completes")
            require(notifications == ["shown"], "same state must not notify twice")
            require(readNotifications == [.checking, .ready, .checking, .ready],
                    "same value still settles its new read phase")

            sender.append(["ok": true])
            completed = false
            SystemBatteryIconController.refreshHidden { value in
                refreshed = value
                completed = true
            }
            require(waitUntil { completed }, "unknown refresh completion")
            require(refreshed == nil, "missing hidden value remains unknown")
            require(SystemBatteryIconController.cachedHidden == nil, "unknown is cached as nil")
            require(SystemBatteryIconController.readStatus == .failed(.invalidReply), "invalid read is a settled failure")
            require(
                notifications == ["shown", "unknown"],
                "known-to-unknown transition must notify"
            )

            sender.append(["ok": true, "hidden": false])
            sender.append(["ok": true, "hidden": true])
            var mutationCompleted = false
            var mutationSucceeded = false
            var mutationOnMain = false
            let requestCountBeforeSuccess = sender.requestCount
            SystemBatteryIconController.setHidden(true) { succeeded in
                mutationOnMain = Thread.isMainThread
                mutationSucceeded = succeeded
                mutationCompleted = true
            }
            require(waitUntil { mutationCompleted }, "successful mutation completion")
            require(mutationOnMain, "mutation completion must use main thread")
            require(mutationSucceeded, "matching landed value confirms mutation")
            require(
                sender.requestCount == requestCountBeforeSuccess + 2,
                "mutation uses a separate authoritative getter"
            )
            require(
                sender.requests[requestCountBeforeSuccess]["op"] as? String
                    == "setSystemBatteryIconHidden",
                "mutation sends the fixed setter first"
            )
            require(
                sender.requests[requestCountBeforeSuccess + 1]["op"] as? String
                    == "getSystemBatteryIconHidden",
                "mutation reads Control Center authority second"
            )
            require(SystemBatteryIconController.cachedHidden == true, "success updates cache")
            require(
                notifications == ["shown", "unknown", "hidden"],
                "successful state change notifies once"
            )

            sender.append(["ok": true, "hidden": false])
            sender.append(["ok": true, "hidden": true])
            mutationCompleted = false
            SystemBatteryIconController.setHidden(true) { succeeded in
                mutationSucceeded = succeeded
                mutationCompleted = true
            }
            require(waitUntil { mutationCompleted }, "same-state mutation completion")
            require(mutationSucceeded, "same-state authoritative mutation succeeds")
            require(
                notifications == ["shown", "unknown", "hidden"],
                "same landed state must not notify twice"
            )

            let failureCases: [(String, Bool, [[String: Any]?], Bool?, SystemBatteryIconReadStatus)] = [
                (
                    "missing readback value", true,
                    [["ok": true], ["ok": true]], nil, .failed(.invalidReply)
                ),
                (
                    "mismatched authoritative readback", false,
                    [["ok": true], ["ok": true, "hidden": true]], true, .ready
                ),
                (
                    "reported setter failure", true,
                    [["ok": false, "hidden": false]], true, .ready
                ),
                (
                    "readback transport failure", true,
                    [["ok": true], nil], nil, .failed(.requestFailed)
                ),
                (
                    "readback preference failure", true,
                    [["ok": true], ["ok": false, "reason": "preferenceMissing"]],
                    nil, .failed(.preferenceMissing)
                ),
                (
                    "setter transport failure", true,
                    [nil], true, .ready
                ),
            ]
            for (name, previous, responses, expected, status) in failureCases {
                SystemBatteryIconController.configureForTest(initialHidden: previous) { request, timeout in
                    sender.send(request, timeout)
                }
                notifications.removeAll()
                readNotifications.removeAll()
                lastNotifiedValue = stateName(previous)
                for response in responses { sender.append(response) }
                mutationCompleted = false
                mutationSucceeded = true
                SystemBatteryIconController.setHidden(false) { succeeded in
                    mutationSucceeded = succeeded
                    mutationCompleted = true
                }
                require(waitUntil { mutationCompleted }, "\(name) completion")
                require(!mutationSucceeded, "\(name) must fail")
                require(SystemBatteryIconController.cachedHidden == expected,
                        "\(name) must preserve only the authoritative readback or unchanged setter state")
                require(SystemBatteryIconController.readStatus == status,
                        "\(name) must publish the readback's availability")
                require(notifications == (expected == previous ? [] : [stateName(expected)]),
                        "\(name) must notify the actual value transition")
                require(readNotifications == (expected == previous ? [] : [status]),
                        "\(name) must notify the actual read phase")
            }

            // Hold the shared worker so two refreshes remain replaceable. The
            // following mutation must cancel the pending helper read without
            // abandoning either caller's completion.
            let workerGate = DispatchSemaphore(value: 0)
            let workerStarted = DispatchSemaphore(value: 0)
            HelperSettingsOperationWorker.shared.async {
                workerStarted.signal()
                workerGate.wait()
            }
            require(
                workerStarted.wait(timeout: .now() + 1) == .success,
                "shared worker fixture started"
            )
            var firstCoalescedRefreshCompleted = false
            var secondCoalescedRefreshCompleted = false
            var firstCoalescedValue: Bool?
            var secondCoalescedValue: Bool?
            SystemBatteryIconController.refreshHidden { value in
                firstCoalescedValue = value
                firstCoalescedRefreshCompleted = true
            }
            SystemBatteryIconController.refreshHidden { value in
                secondCoalescedValue = value
                secondCoalescedRefreshCompleted = true
            }
            sender.append(["ok": true, "hidden": false])
            sender.append(["ok": true, "hidden": false])
            let requestCountBeforeCancellation = sender.requestCount
            mutationCompleted = false
            SystemBatteryIconController.setHidden(false) { succeeded in
                mutationSucceeded = succeeded
                mutationCompleted = true
            }
            workerGate.signal()
            require(waitUntil {
                mutationCompleted
                    && firstCoalescedRefreshCompleted
                    && secondCoalescedRefreshCompleted
            }, "mutation completes canceled refresh waiters")
            require(mutationSucceeded, "replacement mutation succeeds")
            require(firstCoalescedValue == false, "first waiter receives newer state")
            require(secondCoalescedValue == false, "latest waiter receives newer state")
            require(
                sender.requestCount == requestCountBeforeCancellation + 2,
                "canceled coalesced reads never touch the helper"
            )
            require(SystemBatteryIconController.cachedHidden == false, "mutation lands shown")
            require(notifications.last == "shown", "replacement state notifies once")

            sender.append(["ok": true, "hidden": false])
            completed = false
            completionOnMain = false
            DispatchQueue.global(qos: .userInitiated).async {
                SystemBatteryIconController.refreshHidden { value in
                    completionOnMain = Thread.isMainThread
                    refreshed = value
                    completed = true
                }
            }
            require(waitUntil { completed }, "off-main refresh completion")
            require(completionOnMain, "off-main caller still completes on main")
            require(refreshed == false, "off-main refresh returns landed value")
            require(SystemBatteryIconController.cachedHidden == false, "off-main refresh caches")
            require(notifications.last == "shown", "off-main refresh notifies shared observers")
            require(notificationsOnMain, "all notifications must use main thread")

            sender.append(["ok": true, "hidden": false])
            sender.append(["ok": true, "hidden": true])
            mutationCompleted = false
            let notificationsBeforeFalseToTrue = notifications.count
            SystemBatteryIconController.setHidden(true) { succeeded in
                mutationSucceeded = succeeded
                mutationCompleted = true
            }
            require(waitUntil { mutationCompleted }, "false-to-true mutation completion")
            require(mutationSucceeded, "false-to-true mutation succeeds")
            require(SystemBatteryIconController.cachedHidden == true, "false-to-true lands true")
            require(
                notifications.count == notificationsBeforeFalseToTrue + 1,
                "false-to-true posts exactly one notification"
            )
            require(notifications.last == "hidden", "false-to-true publishes hidden")

            sender.append(["ok": true, "hidden": true])
            sender.append(["ok": true, "hidden": false])
            let requestsBeforeSynchronousSet = sender.requestCount
            let synchronousSetSucceeded: Bool =
                SystemBatteryIconController.setHidden(false)
            require(synchronousSetSucceeded, "synchronous compatibility setter succeeds")
            require(
                sender.requestCount == requestsBeforeSynchronousSet + 2,
                "synchronous setter uses setter and authoritative getter"
            )
            require(
                SystemBatteryIconController.cachedHidden == false,
                "synchronous setter publishes authoritative state"
            )
            require(notifications.last == "shown", "synchronous setter notifies observers")

            sender.append(["ok": false])
            let notificationsBeforeSynchronousFailure = notifications.count
            let synchronousSetFailed: Bool =
                SystemBatteryIconController.setHidden(true)
            require(!synchronousSetFailed, "synchronous compatibility setter reports failure")
            require(
                SystemBatteryIconController.cachedHidden == false,
                "failed synchronous setter preserves prior state"
            )
            require(
                notifications.count == notificationsBeforeSynchronousFailure,
                "failed synchronous setter does not notify"
            )

            // A's worker result reaches the main queue while the main thread
            // is blocked in newer synchronous B. Once B publishes, delayed A
            // must still complete without rolling the shared cache back.
            sender.append(["ok": true, "hidden": false])
            sender.append(["ok": true, "hidden": true])
            sender.append(["ok": true, "hidden": true])
            sender.append(["ok": true, "hidden": false])
            var olderAsyncCompleted = false
            var olderAsyncSucceeded = false
            let notificationsBeforeOrderedMutations = notifications.count
            SystemBatteryIconController.setHidden(true) { succeeded in
                olderAsyncSucceeded = succeeded
                olderAsyncCompleted = true
            }
            let newerSynchronousSucceeded: Bool =
                SystemBatteryIconController.setHidden(false)
            require(newerSynchronousSucceeded, "newer synchronous mutation succeeds")
            require(
                SystemBatteryIconController.cachedHidden == false,
                "newer synchronous mutation initially owns the cache"
            )
            require(waitUntil { olderAsyncCompleted }, "older async completion delivered")
            require(olderAsyncSucceeded, "older async caller receives its operation result")
            require(
                SystemBatteryIconController.cachedHidden == false,
                "delayed older async completion cannot overwrite newer mutation"
            )
            require(
                notifications.count == notificationsBeforeOrderedMutations,
                "stale older mutation cannot emit a false change notification"
            )
            require(SystemBatteryIconController.readStatus == .ready,
                    "stale older mutation cannot overwrite the newer read phase")

            // Delayed mutation completions must not undo a newer readback's
            // failure, recovery or mismatched-but-authoritative value.
            let orderedReadbacks: [(String, [String: Any], Bool, [String: Any], Bool,
                                    Bool?, SystemBatteryIconReadStatus)] = [
                ("old unknown, new known", ["ok": false, "reason": "preferenceMissing"], false,
                 ["ok": true, "hidden": false], true, false, .ready),
                ("old known, new unknown", ["ok": true, "hidden": true], true,
                 ["ok": false, "reason": "preferenceSyncFailed"], false, nil, .failed(.preferenceSyncFailed)),
                ("old mismatch, new mismatch", ["ok": true, "hidden": false], false,
                 ["ok": true, "hidden": true], false, true, .ready),
            ]
            for (name, oldReadback, oldSucceeded, newReadback, newSucceeded, expected, status) in orderedReadbacks {
                SystemBatteryIconController.configureForTest(initialHidden: false) { request, timeout in
                    sender.send(request, timeout)
                }
                sender.append(["ok": true])
                sender.append(oldReadback)
                sender.append(["ok": true])
                sender.append(newReadback)
                var olderCompleted = false
                SystemBatteryIconController.setHidden(true) { succeeded in
                    require(succeeded == oldSucceeded, "\(name): old caller gets its own result")
                    olderCompleted = true
                }
                require(SystemBatteryIconController.setHidden(false) == newSucceeded,
                        "\(name): new caller gets its own result")
                require(SystemBatteryIconController.cachedHidden == expected
                        && SystemBatteryIconController.readStatus == status,
                        "\(name): newest readback owns shared state")
                require(waitUntil { olderCompleted }, "\(name): delayed completion arrives")
                require(SystemBatteryIconController.cachedHidden == expected
                        && SystemBatteryIconController.readStatus == status,
                        "\(name): delayed mutation cannot overwrite newer readback")
            }

            SystemBatteryIconController.configureForTest { request, timeout in
                sender.send(request, timeout)
            }
            readNotifications.removeAll()
            sender.append(nil)
            completed = false
            SystemBatteryIconController.refreshHidden { value in
                require(value == nil, "failed first read returns unknown")
                completed = true
            }
            require(waitUntil { completed }, "failed first read completion")
            require(readNotifications == [.checking, .failed(.requestFailed)],
                    "nil-to-nil failure still notifies both phases")

            // Canceling a not-yet-selected read must finish checking even if
            // its replacement setter fails, with and without a prior value.
            for previous in [Optional<Bool>.none, .some(false)] {
                for readbackFails in [false, true] {
                    SystemBatteryIconController.configureForTest(initialHidden: previous) { request, timeout in
                        sender.send(request, timeout)
                    }
                    let blocked = DispatchSemaphore(value: 0)
                    let started = DispatchSemaphore(value: 0)
                    HelperSettingsOperationWorker.shared.async {
                        started.signal()
                        blocked.wait()
                    }
                    require(started.wait(timeout: .now() + 1) == .success, "canceled-read worker started")
                    var readCompleted = false
                    var writeCompleted = false
                    let expected = readbackFails ? nil : previous
                    let before = sender.requestCount
                    SystemBatteryIconController.refreshHidden { value in
                        require(value == expected, "canceled read receives the actual settled value")
                        readCompleted = true
                    }
                    if readbackFails { sender.append(["ok": true]) }
                    sender.append(["ok": false, "reason": "preferenceWorkerFailed"])
                    SystemBatteryIconController.setHidden(true) { succeeded in
                        require(!succeeded, "replacement mutation must fail")
                        writeCompleted = true
                    }
                    blocked.signal()
                    require(waitUntil { readCompleted && writeCompleted }, "canceled-read failure settles both callers")
                    require(sender.requestCount == before + (readbackFails ? 2 : 1), "canceled read never reaches helper")
                    require(SystemBatteryIconController.cachedHidden == expected, "mutation publishes only authoritative cache")
                    require(SystemBatteryIconController.readStatus == (expected == nil
                        ? .failed(.preferenceWorkerFailed) : .ready),
                        "failed replacement cannot leave a canceled read checking or hide failed readback")
                }
            }

            // A failed mutation readback invalidates the old value, but a
            // later requested refresh must retain ownership of checking and
            // its own waiter until that refresh has actually finished.
            let mutationReadStarted = DispatchSemaphore(value: 0)
            let mutationReadGate = DispatchSemaphore(value: 0)
            let newerReadStarted = DispatchSemaphore(value: 0)
            let newerReadGate = DispatchSemaphore(value: 0)
            var mutationReadCount = 0
            SystemBatteryIconController.configureForTest(initialHidden: false) { request, _ in
                if request["op"] as? String == "setSystemBatteryIconHidden" { return ["ok": true] }
                mutationReadCount += 1
                if mutationReadCount == 1 {
                    mutationReadStarted.signal()
                    mutationReadGate.wait()
                    return ["ok": false, "reason": "preferenceMissing"]
                }
                newerReadStarted.signal()
                newerReadGate.wait()
                return ["ok": true, "hidden": true]
            }
            var failedMutationCompleted = false
            var newerRefreshCompleted = false
            SystemBatteryIconController.setHidden(true) { succeeded in
                require(!succeeded, "mutation with failed readback reports failure")
                failedMutationCompleted = true
            }
            require(mutationReadStarted.wait(timeout: .now() + 1) == .success, "mutation readback selected")
            SystemBatteryIconController.refreshHidden { value in
                require(value == true, "later refresh receives its own recovered value")
                newerRefreshCompleted = true
            }
            mutationReadGate.signal()
            require(waitUntil { failedMutationCompleted }, "mutation failure completes before newer refresh")
            require(newerReadStarted.wait(timeout: .now() + 1) == .success, "newer refresh selected")
            require(!newerRefreshCompleted && SystemBatteryIconController.cachedHidden == nil
                    && SystemBatteryIconController.readStatus == .checking,
                    "mutation failure cannot finish a newer refresh or retain a stale value")
            newerReadGate.signal()
            require(waitUntil { newerRefreshCompleted }, "later refresh settles after mutation failure")
            require(SystemBatteryIconController.cachedHidden == true
                    && SystemBatteryIconController.readStatus == .ready,
                    "later refresh recovers authoritative state after failed mutation readback")

            // A selected older read may finish while a newer read is blocked.
            // Its value is usable, but the newer read still owns checking.
            let firstReadStarted = DispatchSemaphore(value: 0)
            let firstReadGate = DispatchSemaphore(value: 0)
            let secondReadStarted = DispatchSemaphore(value: 0)
            let secondReadGate = DispatchSemaphore(value: 0)
            var selectedReads = 0
            SystemBatteryIconController.configureForTest(initialHidden: false) { _, _ in
                selectedReads += 1
                if selectedReads == 1 {
                    firstReadStarted.signal()
                    firstReadGate.wait()
                    return ["ok": true, "hidden": true]
                }
                secondReadStarted.signal()
                secondReadGate.wait()
                return ["ok": false, "reason": "preferenceMissing"]
            }
            var firstReadCompleted = false
            var secondReadCompleted = false
            SystemBatteryIconController.refreshHidden { _ in firstReadCompleted = true }
            require(firstReadStarted.wait(timeout: .now() + 1) == .success, "older read selected")
            SystemBatteryIconController.refreshHidden { _ in secondReadCompleted = true }
            firstReadGate.signal()
            require(waitUntil { firstReadCompleted }, "older read completed")
            require(secondReadStarted.wait(timeout: .now() + 1) == .success, "newer read selected")
            require(!secondReadCompleted && SystemBatteryIconController.cachedHidden == true
                    && SystemBatteryIconController.readStatus == .checking,
                    "older completion cannot finish a newer read")
            secondReadGate.signal()
            require(waitUntil { secondReadCompleted }, "newer read completed")
            require(SystemBatteryIconController.cachedHidden == nil
                    && SystemBatteryIconController.readStatus == .failed(.preferenceMissing),
                    "newer failure clears cache and owns the settled phase")

            // A failing older read has queued its main completion while a
            // newer synchronous setter publishes a successful readback.
            let oldReadStarted = DispatchSemaphore(value: 0)
            let oldReadGate = DispatchSemaphore(value: 0)
            var oldReadRequests = 0
            SystemBatteryIconController.configureForTest(initialHidden: false) { request, _ in
                oldReadRequests += 1
                if oldReadRequests == 1 {
                    oldReadStarted.signal()
                    oldReadGate.wait()
                    return ["ok": false, "reason": "preferenceSyncFailed"]
                }
                return request["op"] as? String == "setSystemBatteryIconHidden"
                    ? ["ok": true] : ["ok": true, "hidden": false]
            }
            var oldReadCompleted = false
            SystemBatteryIconController.refreshHidden { _ in oldReadCompleted = true }
            require(oldReadStarted.wait(timeout: .now() + 1) == .success, "old failing read selected")
            oldReadGate.signal()
            require(SystemBatteryIconController.setHidden(false), "newer synchronous write succeeds")
            require(SystemBatteryIconController.readStatus == .ready, "newer write settles ready")
            require(waitUntil { oldReadCompleted }, "old failed completion delivered")
            require(SystemBatteryIconController.cachedHidden == false
                    && SystemBatteryIconController.readStatus == .ready,
                    "old failure cannot undo newer readback or its phase")

            // A checking observer may request a newer refresh synchronously.
            // Both callers must finish even when their pending reads coalesce.
            SystemBatteryIconController.configureForTest { _, _ in ["ok": true, "hidden": false] }
            var outerCompleted = false
            var nestedCompleted = false
            var nestedRequested = false
            let reentrantObserver = NotificationCenter.default.addObserver(
                forName: SystemBatteryIconController.didChange, object: nil, queue: .main
            ) { _ in
                if SystemBatteryIconController.readStatus == .checking && !nestedRequested {
                    nestedRequested = true
                    SystemBatteryIconController.refreshHidden { _ in nestedCompleted = true }
                }
            }
            SystemBatteryIconController.refreshHidden { _ in outerCompleted = true }
            require(waitUntil { outerCompleted && nestedCompleted }, "reentrant read waiters complete")
            NotificationCenter.default.removeObserver(reentrantObserver)
            require(SystemBatteryIconController.readStatus == .ready, "reentrant refresh settles newest phase")

            // Diagnostic reads share the worker without canceling a queued UI
            // refresh or publishing their own, different observed value.
            let probeWorkerStarted = DispatchSemaphore(value: 0)
            let probeWorkerGate = DispatchSemaphore(value: 0)
            var probeRequests = 0
            SystemBatteryIconController.configureForTest(initialHidden: true) { _, _ in
                probeRequests += 1
                return ["ok": true, "hidden": probeRequests != 1]
            }
            HelperSettingsOperationWorker.shared.async {
                probeWorkerStarted.signal()
                probeWorkerGate.wait()
            }
            require(probeWorkerStarted.wait(timeout: .now() + 1) == .success, "diagnostic worker fixture started")
            var uiReadCompleted = false
            var diagnosticResult: SystemBatteryIconReadResult?
            SystemBatteryIconController.refreshHidden { _ in uiReadCompleted = true }
            DispatchQueue.global(qos: .utility).async {
                let result = SystemBatteryIconController.probe()
                DispatchQueue.main.async { diagnosticResult = result }
            }
            probeWorkerGate.signal()
            require(waitUntil { uiReadCompleted && diagnosticResult != nil }, "UI refresh and diagnostic both complete")
            require(probeRequests == 2, "diagnostic does not coalesce or cancel a UI read")
            require(diagnosticResult?.hidden == true && diagnosticResult?.failure == nil,
                    "diagnostic returns its own observed value")
            require(SystemBatteryIconController.cachedHidden == false
                    && SystemBatteryIconController.readStatus == .ready,
                    "diagnostic never publishes its different value")

            sender.append(["ok": false, "reason": "preferenceMissing"])
            sender.append(["ok": true, "hidden": false])
            SystemBatteryIconController.configureForTest { request, timeout in
                sender.send(request, timeout)
            }
            readNotifications.removeAll()
            completed = false
            SystemBatteryIconController.refreshHidden { _ in completed = true }
            require(waitUntil { completed }, "recoverable failure completes")
            require(SystemBatteryIconController.readStatus == .failed(.preferenceMissing), "failure remains classified")
            completed = false
            SystemBatteryIconController.refreshHidden { _ in completed = true }
            require(waitUntil { completed }, "next read recovers")
            require(SystemBatteryIconController.cachedHidden == false
                    && readNotifications == [.checking, .failed(.preferenceMissing), .checking, .ready],
                    "later successful refresh clears the failure phase")

            print("system battery shared-state contract passed")
            """
        )
        with TemporaryDirectory() as directory:
            directory_path = pathlib.Path(directory)
            main = directory_path / "main.swift"
            binary = directory_path / "system-battery-state-contract"
            main.write_text(harness, encoding="utf-8")
            compile_result = run(
                [
                    "/usr/bin/xcrun",
                    "swiftc",
                    "-D",
                    "DEBUG",
                    "-swift-version",
                    "5",
                    str(CLIENT_SOURCE),
                    str(SYSTEM_BATTERY_SOURCE),
                    str(main),
                    "-o",
                    str(binary),
                ],
                check=False,
                text=True,
                capture_output=True,
            )
            self.assertEqual(compile_result.returncode, 0, compile_result.stderr)
            run_result = run(
                [str(binary)],
                check=False,
                text=True,
                capture_output=True,
                timeout=15,
            )
            self.assertEqual(run_result.returncode, 0, run_result.stderr)
            self.assertIn(
                "system battery shared-state contract passed",
                run_result.stdout,
            )


if __name__ == "__main__":
    unittest.main()
