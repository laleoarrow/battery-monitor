import pathlib
import subprocess
import tempfile
import textwrap
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
CLIENT_SOURCE = ROOT / "Core" / "HelperClient.swift"
MODE_SOURCE = ROOT / "Core" / "EnergyMode.swift"
SYSTEM_BATTERY_SOURCE = ROOT / "Core" / "SystemBatteryIcon.swift"


class EnergyModeContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.client = CLIENT_SOURCE.read_text(encoding="utf-8")
        cls.mode = MODE_SOURCE.read_text(encoding="utf-8")

    def test_client_targets_the_helper_socket_path(self):
        self.assertIn("/var/run/wattson-helper.sock", self.client)
        self.assertIn("AF_UNIX", self.client)

    def test_client_never_shells_out(self):
        self.assertNotIn("Process()", self.client)
        self.assertNotIn("/bin/sh", self.client)

    def test_client_io_has_a_finite_timeout(self):
        self.assertIn("SO_RCVTIMEO", self.client)
        self.assertIn("SO_SNDTIMEO", self.client)
        self.assertIn("timeoutSeconds: Int = 2", self.client)
        self.assertIn("timeval(tv_sec: timeoutSeconds", self.client)

    def test_mutating_mode_request_has_budget_for_write_and_readback(self):
        request = self.mode.split("private static func requestModeChange", 1)[1].split(
            "private static func fetchModeState", 1
        )[0]
        self.assertIn("timeoutSeconds: 8", request)

    def test_mode_read_has_budget_for_live_mode_and_capability_queries(self):
        fetch = self.mode.split("private static func fetchModeState", 1)[1].split(
            "static func resolveModeState", 1
        )[0]
        self.assertIn("timeoutSeconds: 6", fetch)

    def test_reads_mode_without_polling(self):
        self.assertIn("isLowPowerModeEnabled", self.mode)
        self.assertIn("NSProcessInfoPowerStateDidChange", self.mode)

    def test_power_state_notification_decisions_and_read_fallback_in_real_swift(self):
        harness = textwrap.dedent(
            """
            import Foundation

            func require(_ condition: @autoclosure () -> Bool, _ message: String) {
                if !condition() {
                    FileHandle.standardError.write(Data((message + "\\n").utf8))
                    exit(1)
                }
            }

            let actionCases: [(
                String, EnergyMode?, Bool, EnergyModeNotificationPolicy.Action
            )] = [
                ("Auto -> High", .auto, false, .refresh(provisionalMode: nil)),
                ("High -> Auto", .high, false, .refresh(provisionalMode: nil)),
                ("leaving Low", .low, false, .refresh(provisionalMode: .auto)),
                ("entering Low", .high, true, .reportImmediately(.low)),
            ]
            for (name, cachedMode, isLow, expected) in actionCases {
                require(
                    EnergyModeNotificationPolicy.action(
                        cachedMode: cachedMode,
                        isLowPowerModeEnabled: isLow
                    ) == expected,
                    name
                )
            }

            let completionCases: [(String, Bool, Bool, EnergyMode, EnergyMode?)] = [
                ("Auto -> High", true, false, .high, .high),
                ("High -> Auto", true, false, .auto, .auto),
                ("Low -> Auto", true, false, .auto, .auto),
                ("Low -> High", true, false, .high, .high),
                ("failed or superseded", false, false, .high, nil),
                ("entered Low while refreshing", true, true, .high, nil),
            ]
            for (name, didRefresh, isLow, currentMode, expected) in completionCases {
                require(
                    EnergyModeNotificationPolicy.refreshedMode(
                        didRefresh: didRefresh,
                        isLowPowerModeEnabled: isLow,
                        currentMode: currentMode
                    ) == expected,
                    name
                )
            }

            var helperCalls = 0
            var liveCalls = 0
            let fallback = EnergyModeController.resolveModeState(
                helper: {
                    helperCalls += 1
                    return nil
                },
                liveMode: {
                    liveCalls += 1
                    return .high
                }
            )
            require(helperCalls == 1, "helper attempted once")
            require(liveCalls == 1, "helper failure falls back to live pmset")
            require(fallback?.mode == .high, "live fallback mode")
            require(fallback?.supportsHigh == true, "high fallback records support")

            var unexpectedLiveRead = false
            let helper = EnergyModeController.resolveModeState(
                helper: {
                    EnergyModeController.ModeState(mode: .auto, supportsHigh: true)
                },
                liveMode: {
                    unexpectedLiveRead = true
                    return .high
                }
            )
            require(helper?.mode == .auto, "helper result wins")
            require(!unexpectedLiveRead, "successful helper skips fallback")
            """
        )
        with tempfile.TemporaryDirectory() as temp:
            temp_path = pathlib.Path(temp)
            main = temp_path / "main.swift"
            binary = temp_path / "energy-mode-notification"
            main.write_text(harness, encoding="utf-8")
            subprocess.run(
                [
                    "xcrun",
                    "swiftc",
                    str(CLIENT_SOURCE),
                    str(SYSTEM_BATTERY_SOURCE),
                    str(MODE_SOURCE),
                    str(main),
                    "-o",
                    str(binary),
                ],
                check=True,
                capture_output=True,
                text=True,
            )
            subprocess.run([str(binary)], check=True, capture_output=True, text=True)

    def test_power_state_observer_uses_refresh_without_writing(self):
        observer = self.mode.split("static func observe", 1)[1]
        self.assertIn("EnergyModeNotificationPolicy.action", observer)
        self.assertIn("refreshFromHelper", observer)
        self.assertIn("readGeneration += 1", observer)
        self.assertIn("operations.cancelPendingRead()", observer)
        self.assertIn("handler(provisionalMode)", observer)
        self.assertNotIn("requestModeChange", observer)

    def test_three_modes_exist_but_the_right_click_toggle_uses_two(self):
        # High power is reachable from the popover, where the current mode is
        # visible. A three-way cycle on a gesture with no visible state is a
        # guessing game.
        for case in ("case low", "case auto", "case high"):
            self.assertIn(case, self.mode)
        toggle = self.mode.split("static func toggle()", 1)[1].split("}", 1)[0]
        self.assertIn("current == .low ? .auto : .low", toggle)
        self.assertNotIn(".high", toggle)

    def test_high_power_support_comes_from_the_helper(self):
        # The app is sandboxed and gets killed for touching /Library/Preferences,
        # where the power-mode keys live. The helper runs as root outside the
        # sandbox and is the only component that can answer.
        self.assertIn("supportsHighPower", self.mode)
        self.assertIn("refreshFromHelper", self.mode)
        self.assertIn('"supportsHigh"', self.mode)
        # The comment explains why; what matters is that no read remains.
        self.assertNotIn("NSDictionary(contentsOfFile:", self.mode)
        self.assertNotIn("contentsOfDirectory", self.mode)

    def test_helper_reads_high_power_capability_from_a_fixed_pmset_command(self):
        helper = (pathlib.Path(__file__).resolve().parents[1]
                  / "Helper" / "wattson-helper.swift").read_text(encoding="utf-8")
        self.assertIn('runOutput(["/usr/bin/pmset", "-g", "cap"])', helper)
        self.assertIn('$0.lowercased() == "highpowermode"', helper)
        self.assertNotIn("com.apple.PowerManagement.", helper)

    def test_live_read_is_event_driven_not_part_of_the_refresh_loop(self):
        # pmset -g live is the only immediate source of truth on macOS 26, but
        # spawning it from `current` would put a ~76 ms process launch in every
        # 1 Hz presentation refresh. It belongs only at explicit refresh/set
        # boundaries.
        self.assertIn('URL(fileURLWithPath: "/usr/bin/pmset")', self.mode)
        self.assertIn('arguments: [String] = ["-g", "live"]', self.mode)
        current = self.mode.split("static var current: EnergyMode", 1)[1].split("\n    }", 1)[0]
        self.assertNotIn("Process()", current)
        self.assertNotIn("readLiveMode", current)

    def test_live_read_has_a_locale_and_process_deadline(self):
        self.assertIn('environment["LC_ALL"] = "C"', self.mode)
        self.assertIn('environment["LANG"] = "C"', self.mode)
        self.assertIn("liveModeTimeout: TimeInterval = 1.5", self.mode)
        self.assertIn("DispatchTime.now().uptimeNanoseconds", self.mode)
        self.assertIn("O_NONBLOCK", self.mode)
        self.assertIn("maximumLiveModeOutputBytes = 65_536", self.mode)
        self.assertIn("observedChildExit", self.mode)
        self.assertNotIn("readDataToEndOfFile()", self.mode)
        self.assertIn("process.terminate()", self.mode)
        self.assertIn("SIGKILL", self.mode)

    def test_repeated_live_reads_return_file_descriptors_to_baseline(self):
        # Compile the production Process/Pipe implementation into one executable
        # so all reads share one autorelease-pool lifetime, just like repeated
        # popover opens on Wattson's long-lived settings worker.
        testable_mode = self.mode.replace(
            "private static func readLiveMode(",
            "static func readLiveMode(",
            1,
        )
        self.assertNotEqual(testable_mode, self.mode)
        harness = textwrap.dedent(
            """
            import Foundation

            func require(_ condition: @autoclosure () -> Bool, _ message: String) {
                if !condition() {
                    FileHandle.standardError.write(Data((message + "\\n").utf8))
                    exit(1)
                }
            }

            func openFDCount() -> Int {
                (try? FileManager.default.contentsOfDirectory(atPath: "/dev/fd").count) ?? -1
            }

            func assertNoLeak(_ name: String, operation: () -> Bool) {
                require(operation(), "\\(name) warm-up")
                let baseline = openFDCount()
                require(baseline >= 0, "\\(name) baseline descriptor count")
                for _ in 0..<12 {
                    require(operation(), "\\(name) stress operation")
                }
                let final = openFDCount()
                require(
                    final <= baseline + 1,
                    "\\(name) leaked descriptors: baseline=\\(baseline), final=\\(final)"
                )
            }

            let shell = URL(fileURLWithPath: "/bin/sh")
            assertNoLeak("success") {
                EnergyModeController.readLiveMode(
                    executableURL: shell,
                    arguments: ["-c", "printf 'powermode 1\\n'"],
                    timeout: 0.5,
                    maximumOutputBytes: 1_024
                ) == .low
            }
            assertNoLeak("launch failure") {
                EnergyModeController.readLiveMode(
                    executableURL: URL(fileURLWithPath: "/no/such/wattson-command"),
                    arguments: [],
                    timeout: 0.5,
                    maximumOutputBytes: 1_024
                ) == nil
            }
            assertNoLeak("nonzero exit") {
                EnergyModeController.readLiveMode(
                    executableURL: shell,
                    arguments: ["-c", "printf 'powermode 2\\n'; exit 7"],
                    timeout: 0.5,
                    maximumOutputBytes: 1_024
                ) == nil
            }
            assertNoLeak("timeout") {
                EnergyModeController.readLiveMode(
                    executableURL: URL(fileURLWithPath: "/bin/sleep"),
                    arguments: ["2"],
                    timeout: 0.005,
                    maximumOutputBytes: 1_024
                ) == nil
            }
            assertNoLeak("oversize") {
                EnergyModeController.readLiveMode(
                    executableURL: URL(fileURLWithPath: "/usr/bin/yes"),
                    arguments: ["powermode 1"],
                    timeout: 0.5,
                    maximumOutputBytes: 64
                ) == nil
            }
            """
        )
        with tempfile.TemporaryDirectory() as temp:
            temp_path = pathlib.Path(temp)
            testable_source = temp_path / "EnergyMode.swift"
            main = temp_path / "main.swift"
            binary = temp_path / "energy-mode-fd-stress"
            testable_source.write_text(testable_mode, encoding="utf-8")
            main.write_text(harness, encoding="utf-8")
            subprocess.run(
                [
                    "xcrun",
                    "swiftc",
                    str(CLIENT_SOURCE),
                    str(SYSTEM_BATTERY_SOURCE),
                    str(testable_source),
                    str(main),
                    "-o",
                    str(binary),
                ],
                check=True,
                capture_output=True,
                text=True,
            )
            run_result = subprocess.run(
                [str(binary)], check=False, capture_output=True, text=True
            )
            self.assertEqual(run_result.returncode, 0, run_result.stderr)

    def test_live_output_parser_rejects_missing_and_unknown_modes(self):
        harness = textwrap.dedent(
            """
            import Foundation

            func require(_ condition: @autoclosure () -> Bool, _ message: String) {
                if !condition() {
                    FileHandle.standardError.write(Data((message + "\\n").utf8))
                    exit(1)
                }
            }

            require(
                EnergyModeController.mode(fromLiveOutput: "powermode 0\\n") == .auto,
                "auto"
            )
            require(
                EnergyModeController.mode(fromLiveOutput: "  powermode   2  \\n") == .high,
                "high"
            )
            require(
                EnergyModeController.mode(fromLiveOutput: "lowpowermode 0\\n") == .auto,
                "low-power-only auto"
            )
            require(
                EnergyModeController.mode(fromLiveOutput: "  lowpowermode   1  \\n") == .low,
                "low-power-only low"
            )
            require(
                EnergyModeController.mode(fromLiveOutput: "other 1\\n") == nil,
                "missing"
            )
            require(
                EnergyModeController.mode(fromLiveOutput: "powermode 9\\n") == nil,
                "unknown"
            )
            require(
                EnergyModeController.mode(fromLiveOutput: "lowpowermode 2\\n") == nil,
                "low-power-only format is two-state"
            )
            """
        )
        with tempfile.TemporaryDirectory() as temp:
            temp_path = pathlib.Path(temp)
            main = temp_path / "main.swift"
            binary = temp_path / "energy-mode-parser"
            main.write_text(harness, encoding="utf-8")
            subprocess.run(
                [
                    "xcrun",
                    "swiftc",
                    str(CLIENT_SOURCE),
                    str(SYSTEM_BATTERY_SOURCE),
                    str(MODE_SOURCE),
                    str(main),
                    "-o",
                    str(binary),
                ],
                check=True,
                capture_output=True,
                text=True,
            )
            subprocess.run([str(binary)], check=True, capture_output=True, text=True)

    def test_old_helper_readback_is_rechecked_before_the_slider_accepts_it(self):
        # Helpers installed before this fix report high as auto. Only a reply
        # explicitly marked as live-verified may bypass the app-side readback.
        self.assertIn('strictJSONBool(reply["modeVerified"]) == true', self.mode)
        self.assertIn("readLiveMode()", self.mode)
        setter = self.mode.split("static func set(_ mode: EnergyMode)", 1)[1].split(
            "\n    }", 1
        )[0]
        self.assertIn("state.mode == mode", setter)

    def test_open_refresh_does_not_block_appkit_or_overwrite_a_newer_set(self):
        self.assertIn("operations.enqueueRead", self.mode)
        self.assertIn("readGeneration", self.mode)
        self.assertIn("writeGeneration", self.mode)
        self.assertIn("writesAtStart == currentWriteGeneration()", self.mode)
        setter = self.mode.split("static func set(_ mode: EnergyMode)", 1)[1].split(
            "\n    }", 1
        )[0]
        self.assertIn("readGeneration += 1", setter)
        self.assertIn("let generation = beginWrite()", setter)
        self.assertIn("operations.performMutation", setter)

    def test_mode_refreshes_coalesce_and_mutations_use_the_same_scheduler(self):
        self.assertIn(
            "CoalescingReadOperationQueue<ModeState?>", self.mode
        )
        refresh = self.mode.split("static func refreshFromHelper", 1)[1].split(
            "static func set(_ mode: EnergyMode)", 1
        )[0]
        self.assertIn("operations.enqueueRead", refresh)

        setters = self.mode.split("static func set(_ mode: EnergyMode)", 1)[1].split(
            "private static func resolveModeChange", 1
        )[0]
        self.assertIn("operations.enqueueMutation", setters)
        self.assertIn("resolveLatestModeChange", setters)
        self.assertIn("writeExecutionGate.execute", setters)
        self.assertNotIn("refreshQueue.async", setters)

    def test_verified_low_mode_is_visible_before_processinfo_catches_up(self):
        current = self.mode.split("static var current: EnergyMode", 1)[1].split("\n    }", 1)[0]
        self.assertIn("cachedMode ?? .auto", current)

    def test_live_mode_still_reads_when_the_helper_is_missing(self):
        fetch = self.mode.split("private static func fetchModeState()", 1)[1].split(
            "\n    }", 1
        )[0]
        self.assertIn("readLiveMode()", fetch)

    def test_background_fetch_does_not_read_main_thread_cache(self):
        fetch = self.mode.split("private static func fetchModeState()", 1)[1].split(
            "\n    }", 1
        )[0]
        self.assertNotIn("cachedSupportsHigh", fetch)

    def test_helper_state_is_cached_not_queried_per_read(self):
        # `current` is consulted on every menu bar refresh; each query wakes the
        # helper through launchd.
        self.assertIn("cachedSupportsHigh", self.mode)
        self.assertIn("cachedMode", self.mode)

    def test_toggle_goes_through_the_helper(self):
        self.assertIn("HelperClient.send", self.mode)
        self.assertIn('"setMode"', self.mode)

    def test_popover_mode_write_does_not_block_appkit(self):
        async_set = self.mode.split(
            "static func set(_ mode: EnergyMode, completion:", 1
        )[1].split("private static func requestModeChange", 1)[0]
        self.assertIn("operations.enqueueMutation", async_set)
        self.assertLess(
            async_set.index("operations.enqueueMutation"),
            async_set.index(
                "resolveLatestModeChange(mode, requestGeneration: generation)"
            ),
        )

    def test_failed_latest_write_only_uses_an_adjacent_confirmed_write(self):
        resolver = self.mode.split("private static func resolveModeChange", 1)[1].split(
            "private static func requestModeChange", 1
        )[0]
        self.assertIn("writeGeneration generation: Int", resolver)
        self.assertIn("lastQueueState.resolve", resolver)
        self.assertIn("request: { requestModeChange(mode) }", resolver)
        self.assertIn("readback: { fetchModeState() }", resolver)
        self.assertNotIn("?? lastQueueState", resolver)
        self.assertIn("operations.performMutation", self.mode)

        refresh = self.mode.split("static func refreshFromHelper", 1)[1].split(
            "static func set(_ mode: EnergyMode)", 1
        )[0]
        self.assertNotIn("lastQueueState.resolve", refresh)

    def test_generation_bound_fallback_rejects_stale_state_in_real_swift(self):
        harness = textwrap.dedent(
            """
            import Foundation

            func require(_ condition: @autoclosure () -> Bool, _ message: String) {
                if !condition() {
                    FileHandle.standardError.write(Data((message + "\\n").utf8))
                    exit(1)
                }
            }

            var empty = GenerationBoundWriteFallback<String>()
            require(
                empty.resolve(forWriteGeneration: 1, request: { nil }, readback: { nil }) == nil,
                "empty cache"
            )

            var stale = GenerationBoundWriteFallback<String>()
            require(
                stale.resolve(forWriteGeneration: 4, request: { "stale" }, readback: { nil })
                    == "stale",
                "seed stale state"
            )
            require(
                stale.resolve(forWriteGeneration: 6, request: { nil }, readback: { nil }) == nil,
                "stale generation"
            )

            var consecutive = GenerationBoundWriteFallback<String>()
            var unexpectedReadback = false
            require(
                consecutive.resolve(
                    forWriteGeneration: 7,
                    request: { "A" },
                    readback: {
                        unexpectedReadback = true
                        return nil
                    }
                ) == "A",
                "authoritative A"
            )
            require(!unexpectedReadback, "readback after authoritative write")
            require(
                consecutive.resolve(
                    forWriteGeneration: 8,
                    request: { nil },
                    readback: { nil }
                ) == "A",
                "adjacent A fallback"
            )
            require(
                consecutive.resolve(
                    forWriteGeneration: 9,
                    request: { nil },
                    readback: { nil }
                ) == nil,
                "fallback propagation"
            )
            """
        )
        with tempfile.TemporaryDirectory() as temp:
            temp_path = pathlib.Path(temp)
            main = temp_path / "main.swift"
            binary = temp_path / "energy-mode-fallback"
            main.write_text(harness, encoding="utf-8")
            subprocess.run(
                [
                    "xcrun",
                    "swiftc",
                    str(CLIENT_SOURCE),
                    str(SYSTEM_BATTERY_SOURCE),
                    str(MODE_SOURCE),
                    str(main),
                    "-o",
                    str(binary),
                ],
                check=True,
                capture_output=True,
                text=True,
            )
            subprocess.run([str(binary)], check=True, capture_output=True, text=True)

    def test_superseded_mode_writes_skip_work_and_keep_executed_fallback_adjacent(self):
        harness = textwrap.dedent(
            """
            import Foundation

            func require(_ condition: @autoclosure () -> Bool, _ message: String) {
                if !condition() {
                    FileHandle.standardError.write(Data((message + "\\n").utf8))
                    exit(1)
                }
            }

            var gate = LatestWriteExecutionGate()
            var fallback = GenerationBoundWriteFallback<String>()
            var executedRequests: [Int] = []

            let first = gate.execute(requestGeneration: 1, latestGeneration: 1) { execution in
                executedRequests.append(1)
                return fallback.resolve(
                    forWriteGeneration: execution,
                    request: { "A" },
                    readback: { nil }
                )
            }
            require(first == "A", "first write executes")

            let skipped = gate.execute(requestGeneration: 2, latestGeneration: 3) { execution in
                executedRequests.append(2)
                return fallback.resolve(
                    forWriteGeneration: execution,
                    request: { "obsolete" },
                    readback: { nil }
                )
            }
            require(skipped == nil, "superseded write returns nil")
            require(executedRequests == [1], "superseded helper call is skipped")

            let latest = gate.execute(requestGeneration: 3, latestGeneration: 3) { execution in
                executedRequests.append(3)
                return fallback.resolve(
                    forWriteGeneration: execution,
                    request: { nil },
                    readback: { nil }
                )
            }
            require(latest == "A", "latest failure uses adjacent executed write")
            require(executedRequests == [1, 3], "only current and latest execute")
            require(gate.executionGeneration == 2, "skips do not consume execution generations")
            """
        )
        with tempfile.TemporaryDirectory() as temp:
            temp_path = pathlib.Path(temp)
            main = temp_path / "main.swift"
            binary = temp_path / "energy-mode-latest-write"
            main.write_text(harness, encoding="utf-8")
            subprocess.run(
                [
                    "xcrun",
                    "swiftc",
                    str(CLIENT_SOURCE),
                    str(SYSTEM_BATTERY_SOURCE),
                    str(MODE_SOURCE),
                    str(main),
                    "-o",
                    str(binary),
                ],
                check=True,
                capture_output=True,
                text=True,
            )
            subprocess.run([str(binary)], check=True, capture_output=True, text=True)


if __name__ == "__main__":
    unittest.main()
