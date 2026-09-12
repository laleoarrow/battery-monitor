import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
CONTENT = (ROOT / "Popover" / "PopoverContentView.swift").read_text()
NATIVE = (ROOT / "Popover" / "NativeModeSegmentedControl.swift").read_text()


class ReduceMotionModeControlContractTests(unittest.TestCase):
    def test_reduced_motion_uses_a_native_equal_width_segmented_control(self):
        self.assertIn("final class NativeModeSegmentedControl: NSSegmentedControl", NATIVE)
        self.assertIn("segmentStyle = .automatic", NATIVE)
        self.assertIn("segmentDistribution = .fillEqually", NATIVE)
        self.assertNotIn("CAAnimation", NATIVE)
        self.assertNotIn("NSGlassEffectView", NATIVE)

    def test_footer_keeps_2a_and_switches_to_2c_from_system_accessibility(self):
        footer = CONTENT.split("final class PopoverFooterView", 1)[1].split(
            "final class PopoverContentViewController", 1
        )[0]
        self.assertIn("ModeSliderView(modes: modes)", footer)
        self.assertIn("NativeModeSegmentedControl(modes: modes)", footer)
        self.assertIn("WATTSON_FORCE_REDUCE_MOTION", footer)
        self.assertIn("accessibilityDisplayShouldReduceMotion", footer)
        self.assertIn("accessibilityDisplayOptionsDidChangeNotification", footer)
        self.assertIn("let useNativeControl = reduceMotion || Settings.usesLiquidGlass", footer)
        self.assertIn("modeControl.isHidden = useNativeControl", footer)
        self.assertIn("nativeModeControl.isHidden = !useNativeControl", footer)

    def test_native_control_does_not_own_appearance_or_accessibility_preferences(self):
        footer = CONTENT.split("final class PopoverFooterView", 1)[1].split(
            "final class PopoverContentViewController", 1
        )[0]
        self.assertNotIn("UserDefaults", NATIVE)
        self.assertNotIn("AppStorage", NATIVE)
        self.assertNotIn("Settings.", NATIVE)
        self.assertNotIn('checkboxWithTitle: "Reduce Motion"', footer)
        self.assertNotIn('title: "Reduce Motion"', footer)

    def test_footer_is_the_only_async_selection_state_owner(self):
        footer = CONTENT.split("final class PopoverFooterView", 1)[1].split(
            "final class PopoverContentViewController", 1
        )[0]
        self.assertIn("var onSelect: ((EnergyMode) -> Void)?", NATIVE)
        self.assertNotIn("pendingSelectionIndex", NATIVE)
        self.assertNotIn("selectionGeneration", NATIVE)
        self.assertNotIn("DispatchQueue", NATIVE)
        self.assertIn("private var pendingMode: EnergyMode?", footer)
        self.assertIn("private var selectionGeneration = 0", footer)
        self.assertIn("sourceCompletion: ((EnergyMode?) -> Void)? = nil", footer)
        self.assertIn("DispatchQueue.main.async", footer)

    def test_native_control_keeps_target_action_keyboard_and_accessibility(self):
        self.assertIn("target = self", NATIVE)
        self.assertIn("action = #selector(selectionChanged)", NATIVE)
        self.assertIn('setAccessibilityLabel("Power Mode")', NATIVE)
        self.assertIn("override func keyDown", NATIVE)
        self.assertIn("accessibilityPerformIncrement", NATIVE)
        self.assertIn("accessibilityPerformDecrement", NATIVE)

    def test_glass_preference_changes_only_footer_presentation_and_keeps_focus(self):
        footer = CONTENT.split("final class PopoverFooterView", 1)[1].split(
            "final class PopoverContentViewController", 1
        )[0]
        self.assertIn("forName: Settings.didChange", footer)
        self.assertIn("case .liquidGlassAppearance = change", footer)
        self.assertIn("NotificationCenter.default.removeObserver(settingsObserver)", footer)
        refresh = footer.split("private func refreshDisplayOptions(reduceMotion:", 1)[1].split(
            "@objc private func systemBatteryIconChanged", 1
        )[0]
        self.assertIn("window?.firstResponder === previousControl", refresh)
        self.assertIn("window?.makeFirstResponder(nextControl)", refresh)
        self.assertNotIn("pendingMode =", refresh)
        self.assertNotIn("requestModeSelection(", refresh)
        self.assertNotIn("Timer", refresh)


if __name__ == "__main__":
    unittest.main()
