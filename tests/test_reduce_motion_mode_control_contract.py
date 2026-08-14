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
        self.assertIn("modeControl.isHidden = reduceMotion", footer)
        self.assertIn("reducedMotionModeControl.isHidden = !reduceMotion", footer)

    def test_runtime_choice_is_accessibility_state_not_a_saved_preference(self):
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


if __name__ == "__main__":
    unittest.main()
