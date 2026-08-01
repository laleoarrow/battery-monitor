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

    def test_high_power_support_is_detected_not_assumed(self):
        # The HighPowerMode key only exists on hardware that has the feature.
        self.assertIn("supportsHighPower", self.mode)
        self.assertIn('"HighPowerMode"', self.mode)

    def test_mode_is_read_without_forking_pmset(self):
        self.assertIn("NSDictionary(contentsOfFile:", self.mode)
        self.assertNotIn("Process()", self.mode)

    def test_toggle_goes_through_the_helper(self):
        self.assertIn("HelperClient.send", self.mode)
        self.assertIn('"setMode"', self.mode)


if __name__ == "__main__":
    unittest.main()
