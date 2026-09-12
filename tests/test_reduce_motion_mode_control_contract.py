import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
CONTENT = (ROOT / "Popover" / "PopoverContentView.swift").read_text()
NATIVE = (ROOT / "Popover" / "NativeModeSegmentedControl.swift").read_text()
GLASS = (ROOT / "Popover" / "NativeGlassModeControl.swift").read_text()


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
        self.assertIn("if #available(macOS 26.0, *), Settings.usesLiquidGlass", footer)
        self.assertIn("NativeGlassModeControl(modes: modes)", footer)
        self.assertIn("let useGlassControl = Settings.usesLiquidGlass", footer)
        self.assertIn("let useNativeControl = reduceMotion && !useGlassControl", footer)
        self.assertIn("modeControl.isHidden = useNativeControl || useGlassControl", footer)
        self.assertIn("nativeModeControl.isHidden = !useNativeControl", footer)

    def test_native_control_does_not_own_appearance_or_accessibility_preferences(self):
        footer = CONTENT.split("final class PopoverFooterView", 1)[1].split(
            "final class PopoverContentViewController", 1
        )[0]
        for source in (NATIVE, GLASS):
            self.assertNotIn("UserDefaults", source)
            self.assertNotIn("AppStorage", source)
            self.assertNotIn("Settings.", source)
        self.assertNotIn('checkboxWithTitle: "Reduce Motion"', footer)
        self.assertNotIn('title: "Reduce Motion"', footer)

    def test_footer_is_the_only_async_selection_state_owner(self):
        footer = CONTENT.split("final class PopoverFooterView", 1)[1].split(
            "final class PopoverContentViewController", 1
        )[0]
        for source in (NATIVE, GLASS):
            self.assertIn("var onSelect: ((EnergyMode) -> Void)?", source)
            self.assertNotIn("pendingSelectionIndex", source)
            self.assertNotIn("selectionGeneration", source)
            self.assertNotIn("DispatchQueue", source)
        self.assertIn("private var pendingMode: EnergyMode?", footer)
        self.assertIn("private var selectionGeneration = 0", footer)
        self.assertIn("sourceCompletion: ((EnergyMode?) -> Void)? = nil", footer)
        self.assertIn("DispatchQueue.main.async", footer)
        synchronization = footer.split("private func synchronizeModeControls()", 1)[1].split(
            "\n    private func refreshDisplayOptions()", 1
        )[0]
        self.assertIn("nativeModeControl.update(selected: displayedMode, enabledModes: enabledModes)", synchronization)
        self.assertIn("glassModeControl?.update(selected: displayedMode,", synchronization)
        self.assertIn("enabledModes: pendingMode == nil ? enabledModes : []", synchronization)
        # Finishing a request for the already displayed mode must still clear
        # busy state and re-enable the glass buttons after success or rollback.
        self.assertIn("let busy: Bool", footer)
        self.assertIn("self.busy == busy", footer)
        self.assertEqual(synchronization.count("busy: pendingMode != nil"), 2)

    def test_native_control_keeps_target_action_keyboard_and_accessibility(self):
        self.assertIn("target = self", NATIVE)
        self.assertIn("action = #selector(selectionChanged)", NATIVE)
        self.assertIn('setAccessibilityLabel("Power Mode")', NATIVE)
        self.assertIn("override func keyDown", NATIVE)
        self.assertIn("accessibilityPerformIncrement", NATIVE)
        self.assertIn("accessibilityPerformDecrement", NATIVE)

    def test_glass_buttons_restore_owner_selection_before_reporting_intent(self):
        self.assertIn("button.state = selected ? .on : .off", GLASS)
        self.assertIn("button.isEnabled = enabledModes.contains(modes[index])", GLASS)
        send = GLASS.split("private func sendSelection(_ index: Int)", 1)[1].split(
            "\n#if DEBUG", 1
        )[0]
        self.assertLess(send.index("applySelection()"), send.index("guard modes.indices.contains(index)"))
        self.assertIn("enabledModes.contains(modes[index]) else { return false }", send)
        self.assertIn("guard index != selectedIndex else { return true }", send)
        self.assertIn("guard let onSelect else { return false }", send)
        self.assertIn("onSelect(modes[index])", send)
        self.assertNotRegex(send, r"\bselectedIndex\s*=(?!=)")

    def test_glass_buttons_keep_keyboard_and_radio_group_accessibility(self):
        self.assertIn("setAccessibilityRole(.radioGroup)", GLASS)
        self.assertIn('setAccessibilityLabel("Power Mode")', GLASS)
        self.assertNotIn("button.setAccessibilityRole", GLASS)
        self.assertIn("setAccessibilityChildren(buttons)", GLASS)
        self.assertNotIn("button.setAccessibilitySelected", GLASS)
        self.assertNotIn("button.setAccessibilityValue", GLASS)
        self.assertIn("setAccessibilityValueDescription(modes[selectedIndex].title)", GLASS)
        self.assertIn("modeGroup?.handleKeyDown(event, from: tag)", GLASS)
        self.assertIn("let currentIndex = index ?? selectedIndex", GLASS)
        self.assertIn("case 123: return selectAdjacentMode(direction: -1, from: currentIndex)", GLASS)
        self.assertIn("case 124: return selectAdjacentMode(direction: 1, from: currentIndex)", GLASS)
        self.assertIn("case 36, 76: return sendSelection(currentIndex)", GLASS)
        self.assertIn("modes.indices.filter { enabledModes.contains(modes[$0]) }", GLASS)
        self.assertIn("accessibilityPerformIncrement", GLASS)
        self.assertIn("accessibilityPerformDecrement", GLASS)
        self.assertIn("accessibilityPerformPress", GLASS)
        self.assertNotIn("CAAnimation", GLASS)

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
        self.assertIn("isDescendant(of: previousControl)", refresh)
        self.assertIn("glassModeControl?.keyboardFocusView", refresh)
        self.assertIn("if transferFocus, previousControl !== nextControl {", refresh)
        self.assertIn("window?.makeFirstResponder(focusView)", refresh)
        self.assertNotRegex(refresh, r"\bpendingMode\s*=(?!=)")
        # Construction wires the callback but does not execute a mode request.
        self.assertIn("control.onSelect = { [weak self] mode in self?.requestModeSelection(mode) }", refresh)
        self.assertEqual(refresh.count("requestModeSelection("), 1)
        self.assertNotIn("Timer", refresh)


if __name__ == "__main__":
    unittest.main()
