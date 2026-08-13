import pathlib
import subprocess
import tempfile
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

            var notifications: [String] = []
            var notificationsOnMain = true
            let observer = NotificationCenter.default.addObserver(
                forName: SystemBatteryIconController.didChange,
                object: nil,
                queue: .main
            ) { _ in
                notificationsOnMain = notificationsOnMain && Thread.isMainThread
                notifications.append(stateName(SystemBatteryIconController.cachedHidden))
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
            require(waitUntil { completed }, "successful refresh completion")
            require(completionOnMain, "refresh completion must use main thread")
            require(refreshed == false, "refresh returns authoritative shown state")
            require(SystemBatteryIconController.cachedHidden == false, "refresh updates cache")
            require(notifications == ["shown"], "first known state sends one notification")

            sender.append(["ok": true, "hidden": false])
            completed = false
            SystemBatteryIconController.refreshHidden { value in
                refreshed = value
                completed = true
            }
            require(waitUntil { completed }, "same-state refresh completion")
            require(refreshed == false, "same-state refresh still completes")
            require(notifications == ["shown"], "same state must not notify twice")

            sender.append(["ok": true])
            completed = false
            SystemBatteryIconController.refreshHidden { value in
                refreshed = value
                completed = true
            }
            require(waitUntil { completed }, "unknown refresh completion")
            require(refreshed == nil, "missing hidden value remains unknown")
            require(SystemBatteryIconController.cachedHidden == nil, "unknown is cached as nil")
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

            let failureCases: [(String, [[String: Any]?])] = [
                (
                    "missing readback value",
                    [["ok": true], ["ok": true]]
                ),
                (
                    "mismatched authoritative readback",
                    [["ok": true, "hidden": false], ["ok": true, "hidden": true]]
                ),
                (
                    "reported setter failure",
                    [["ok": false, "hidden": false]]
                ),
                (
                    "readback transport failure",
                    [["ok": true], nil]
                ),
            ]
            for (name, responses) in failureCases {
                for response in responses { sender.append(response) }
                mutationCompleted = false
                mutationSucceeded = true
                SystemBatteryIconController.setHidden(false) { succeeded in
                    mutationSucceeded = succeeded
                    mutationCompleted = true
                }
                require(waitUntil { mutationCompleted }, "\(name) completion")
                require(!mutationSucceeded, "\(name) must fail")
                require(
                    SystemBatteryIconController.cachedHidden == true,
                    "\(name) restores the prior authoritative state"
                )
                require(
                    notifications == ["shown", "unknown", "hidden"],
                    "\(name) must not emit a false change notification"
                )
            }

            sender.append(nil)
            mutationCompleted = false
            mutationSucceeded = true
            SystemBatteryIconController.setHidden(false) { succeeded in
                mutationSucceeded = succeeded
                mutationCompleted = true
            }
            require(waitUntil { mutationCompleted }, "transport failure completion")
            require(!mutationSucceeded, "transport failure must fail")
            require(SystemBatteryIconController.cachedHidden == true, "failure preserves cache")
            require(
                notifications == ["shown", "unknown", "hidden"],
                "transport failure must not notify"
            )

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

            print("system battery shared-state contract passed")
            """
        )
        with tempfile.TemporaryDirectory() as directory:
            directory_path = pathlib.Path(directory)
            main = directory_path / "main.swift"
            binary = directory_path / "system-battery-state-contract"
            main.write_text(harness, encoding="utf-8")
            compile_result = subprocess.run(
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
            run_result = subprocess.run(
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
