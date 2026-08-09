import pathlib
import subprocess
import tempfile
import textwrap
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
CLIENT_SOURCE = ROOT / "Core" / "HelperClient.swift"
MODE_SOURCE = ROOT / "Core" / "EnergyMode.swift"


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
        self.assertIn("timeval(tv_sec: 2", self.client)

    def test_reads_mode_without_polling(self):
        self.assertIn("isLowPowerModeEnabled", self.mode)
        self.assertIn("NSProcessInfoPowerStateDidChange", self.mode)

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

    def test_helper_reads_the_keys_the_sandbox_hides(self):
        helper = (pathlib.Path(__file__).resolve().parents[1]
                  / "Helper" / "wattson-helper.swift").read_text(encoding="utf-8")
        self.assertIn('"HighPowerMode"', helper)
        self.assertIn("com.apple.PowerManagement.", helper)

    def test_live_read_is_event_driven_not_part_of_the_refresh_loop(self):
        # pmset -g live is the only immediate source of truth on macOS 26, but
        # spawning it from `current` would put a ~76 ms process launch in every
        # 1 Hz presentation refresh. It belongs only at explicit refresh/set
        # boundaries.
        self.assertIn('URL(fileURLWithPath: "/usr/bin/pmset")', self.mode)
        self.assertIn('arguments = ["-g", "live"]', self.mode)
        current = self.mode.split("static var current: EnergyMode", 1)[1].split("\n    }", 1)[0]
        self.assertNotIn("Process()", current)
        self.assertNotIn("readLiveMode", current)

    def test_old_helper_readback_is_rechecked_before_the_slider_accepts_it(self):
        # Helpers installed before this fix report high as auto. Only a reply
        # explicitly marked as live-verified may bypass the app-side readback.
        self.assertIn('reply["modeVerified"] as? Bool == true', self.mode)
        self.assertIn("readLiveMode()", self.mode)
        setter = self.mode.split("static func set(_ mode: EnergyMode)", 1)[1].split(
            "\n    }", 1
        )[0]
        self.assertIn("state.mode == mode", setter)

    def test_open_refresh_does_not_block_appkit_or_overwrite_a_newer_set(self):
        self.assertIn("refreshQueue.async", self.mode)
        self.assertIn("DispatchQueue.main.async", self.mode)
        self.assertIn("readGeneration", self.mode)
        self.assertIn("writeGeneration", self.mode)
        self.assertIn("writesAtStart == writeGeneration", self.mode)
        setter = self.mode.split("static func set(_ mode: EnergyMode)", 1)[1].split(
            "\n    }", 1
        )[0]
        self.assertIn("readGeneration += 1", setter)
        self.assertIn("writeGeneration += 1", setter)
        self.assertIn("performOnRefreshQueue", setter)

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
        self.assertIn("refreshQueue.async", async_set)
        self.assertIn("DispatchQueue.main.async", async_set)
        self.assertLess(
            async_set.index("refreshQueue.async"),
            async_set.index("resolveModeChange(mode, writeGeneration: generation)"),
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
        self.assertIn("queue.setSpecific", self.mode)
        self.assertIn("refreshQueue.sync", self.mode)

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
