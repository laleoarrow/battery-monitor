import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
CONTENT = ROOT / "Popover" / "PopoverContentView.swift"
SLIDER = ROOT / "Popover" / "ModeSliderView.swift"
STATUS = ROOT / "MenuBar" / "StatusItemController.swift"
SYSTEM_ICON = ROOT / "Core" / "SystemBatteryIcon.swift"
ENERGY_MODE = ROOT / "Core" / "EnergyMode.swift"


class PopoverControlsContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.content = CONTENT.read_text(encoding="utf-8")
        cls.slider = SLIDER.read_text(encoding="utf-8")
        cls.status = STATUS.read_text(encoding="utf-8")
        cls.system_icon = SYSTEM_ICON.read_text(encoding="utf-8")
        cls.energy_mode = ENERGY_MODE.read_text(encoding="utf-8")

    def test_mode_picker_is_a_draggable_glass_knob(self):
        # A segmented control was correct but inert. The knob follows the
        # pointer one-to-one and springs to the nearest detent on release.
        self.assertIn("ModeSliderView(modes:", self.content)
        self.assertNotIn("NSSegmentedControl(", self.content)
        self.assertIn('NSClassFromString("NSGlassEffectView")', self.slider)
        self.assertIn("override func mouseDragged", self.slider)
        self.assertIn("CASpringAnimation", self.slider)

    def test_knob_only_springs_when_the_position_changes(self):
        # update() runs at 1 Hz with the rest of the popover. Re-adding the
        # spring every second left the knob permanently twitching.
        self.assertIn("selectedIndex != previous", self.slider)

    def test_glass_only_kvc_never_reaches_the_fallback(self):
        # tintColor exists on NSGlassEffectView and not on NSView. Sending it to
        # the pre-26 fallback raises NSUnknownKeyException and takes the app
        # down the moment the popover refreshes. The capability is a type now,
        # so the call site cannot forget which knob it is holding.
        self.assertIn("case glass(NSView)", self.slider)
        self.assertIn("case plain(NSView)", self.slider)
        self.assertIn("knob?.applyTint(", self.slider)
        self.assertNotIn("glass?.setValue", self.slider)

        # Inside applyTint, only the glass case may use KVC.
        body = self.slider.split("func applyTint(", 1)[1].split("\n    }", 1)[0]
        plain_branch = body.split("case .plain(let view):", 1)[1]
        self.assertNotIn("setValue", plain_branch)

    def test_legacy_knob_path_is_reachable_for_testing(self):
        # On a macOS 26 machine the fallback is otherwise dead code that would
        # only ever run on someone else's Mac.
        self.assertIn("WATTSON_FORCE_LEGACY_KNOB", self.slider)

    def test_knob_has_a_fallback_below_macos_26(self):
        # Liquid Glass is macOS 26 only; older systems get a plain translucent
        # pill rather than a hand-rolled imitation.
        self.assertIn("as? NSView.Type", self.slider)
        self.assertIn("} else {", self.slider)

    def test_three_modes_are_always_visible_in_requested_order(self):
        self.assertIn("[.auto, .low, .high]", self.content)
        for title in ('"\u81ea\u52a8"', '"Low Power"', '"High Power"'):
            self.assertIn(title, self.energy_mode)

    def test_unsupported_high_power_is_disabled_not_removed(self):
        # The detent stays visible but cannot be snapped to, so the control
        # never silently loses a position.
        self.assertIn("EnergyModeController.supportsHighPower", self.content)
        self.assertIn("enabledModes:", self.content)
        self.assertIn("candidates = modes.indices.filter { enabled[$0] }", self.slider)

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
