import pathlib
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
        self.assertIn("landed == mode", setter)

    def test_open_refresh_does_not_block_appkit_or_overwrite_a_newer_set(self):
        self.assertIn("refreshQueue.async", self.mode)
        self.assertIn("DispatchQueue.main.async", self.mode)
        self.assertIn("refreshGeneration", self.mode)
        setter = self.mode.split("static func set(_ mode: EnergyMode)", 1)[1].split(
            "\n    }", 1
        )[0]
        self.assertIn("refreshGeneration += 1", setter)

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


if __name__ == "__main__":
    unittest.main()
