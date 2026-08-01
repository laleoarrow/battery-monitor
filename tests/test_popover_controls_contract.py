import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
CONTENT = ROOT / "Popover" / "PopoverContentView.swift"
STATUS = ROOT / "MenuBar" / "StatusItemController.swift"
SYSTEM_ICON = ROOT / "Core" / "SystemBatteryIcon.swift"
ENERGY_MODE = ROOT / "Core" / "EnergyMode.swift"


class PopoverControlsContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.content = CONTENT.read_text(encoding="utf-8")
        cls.status = STATUS.read_text(encoding="utf-8")
        cls.system_icon = SYSTEM_ICON.read_text(encoding="utf-8")
        cls.energy_mode = ENERGY_MODE.read_text(encoding="utf-8")

    def test_mode_picker_is_the_native_liquid_glass_control(self):
        # Standard AppKit controls adopt Liquid Glass when built with the
        # macOS 26 SDK, including keyboard and accessibility behavior.
        self.assertIn("NSSegmentedControl(", self.content)
        self.assertIn("segmentStyle = .automatic", self.content)
        self.assertNotIn("private let selection = CALayer()", self.content)

    def test_three_modes_are_always_visible_in_requested_order(self):
        self.assertIn("[.auto, .low, .high]", self.content)
        for title in ('"\u81ea\u52a8"', '"Low Power"', '"High Power"'):
            self.assertIn(title, self.energy_mode)

    def test_unsupported_high_power_is_disabled_not_removed(self):
        self.assertIn("EnergyModeController.supportsHighPower", self.content)
        self.assertIn("setEnabled", self.content)

    def test_system_battery_checkbox_is_in_the_footer(self):
        self.assertIn("checkboxWithTitle: \"\u9690\u85cf\u7cfb\u7edf\u7535\u6c60\u56fe\u6807\"", self.content)
        self.assertIn("onSystemBatteryIconToggle", self.content)

    def test_system_battery_state_is_queried_only_when_opening(self):
        left_up = self.status.split("case .leftMouseUp:", 1)[1].split("default:", 1)[0]
        self.assertIn("refreshSystemBatteryIconState", left_up)
        refresh = self.status.split("private func refreshPresentation()", 1)[1]
        self.assertNotIn("SystemBatteryIconController.isHidden", refresh)

    def test_system_battery_controller_uses_the_privileged_helper(self):
        self.assertIn('"getSystemBatteryIconHidden"', self.system_icon)
        self.assertIn('"setSystemBatteryIconHidden"', self.system_icon)
        self.assertNotIn("Process()", self.system_icon)


if __name__ == "__main__":
    unittest.main()
