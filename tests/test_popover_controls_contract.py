import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
CONTENT = ROOT / "Popover" / "PopoverContentView.swift"
SLIDER = ROOT / "Popover" / "ModeSliderView.swift"
STATUS = ROOT / "MenuBar" / "StatusItemController.swift"
SYSTEM_ICON = ROOT / "Core" / "SystemBatteryIcon.swift"
ENERGY_MODE = ROOT / "Core" / "EnergyMode.swift"
POPOVER = ROOT / "Popover" / "PopoverController.swift"


class PopoverControlsContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.content = CONTENT.read_text(encoding="utf-8")
        cls.slider = SLIDER.read_text(encoding="utf-8")
        cls.status = STATUS.read_text(encoding="utf-8")
        cls.system_icon = SYSTEM_ICON.read_text(encoding="utf-8")
        cls.energy_mode = ENERGY_MODE.read_text(encoding="utf-8")
        cls.popover = POPOVER.read_text(encoding="utf-8")

    def test_mode_picker_is_a_draggable_glass_knob(self):
        # A segmented control was correct but inert. The knob follows the
        # pointer one-to-one and springs to the nearest detent on release.
        self.assertIn("ModeSliderView(modes:", self.content)
        self.assertNotIn("NSSegmentedControl(", self.content)
        self.assertIn('NSClassFromString("NSGlassEffectView")', self.slider)
        self.assertIn("override func mouseDragged", self.slider)
        self.assertIn("CASpringAnimation", self.slider)

    def test_outside_clicks_dismiss_the_popover(self):
        # `.transient` only reacts to events this process sees. Wattson is an
        # accessory app that never activates, so a click on the desktop or in
        # another app never reaches it and the popover stayed open.
        self.assertIn("addGlobalMonitorForEvents", self.popover)
        self.assertIn("removeMonitor", self.popover)
        self.assertIn("performClose", self.popover)

    def test_knob_shadow_has_an_explicit_path(self):
        # Without one, Core Animation derives the shadow from the layer's alpha
        # channel every frame; with Liquid Glass on top, dragging crawled.
        self.assertIn("shadowPath", self.slider)

    def test_dragging_only_relabels_on_a_detent_change(self):
        drag = self.slider.split("override func mouseDragged", 1)[1].split("\n    override", 1)[0]
        self.assertIn("nearest != highlighted", drag)

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
        # The query wakes the helper through launchd, so it must not run on the
        # 1 Hz refresh or when the popover is closing.
        primary = self.status.split("if !popover.isOpen", 1)[1].split("}", 1)[0]
        self.assertIn("refreshSystemBatteryIconState", primary)
        refresh = self.status.split("private func refreshPresentation()", 1)[1]
        self.assertNotIn("SystemBatteryIconController.isHidden", refresh)

    def test_system_battery_controller_uses_the_privileged_helper(self):
        self.assertIn('"getSystemBatteryIconHidden"', self.system_icon)
        self.assertIn('"setSystemBatteryIconHidden"', self.system_icon)
        self.assertNotIn("Process()", self.system_icon)

    def test_slider_hit_tests_as_one_control(self):
        # The track covers the whole bounds, so AppKit hit-tested a plain
        # NSView and asked *it* whether it takes the first mouse. It says no,
        # which spent the first click after the popover opened on making the
        # window key. Dragging still worked because the event bubbled up the
        # responder chain, which is what hid this.
        self.assertIn("override func hitTest(_ point: NSPoint) -> NSView?", self.slider)
        self.assertIn("override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }", self.slider)

    def test_a_click_selects_the_detent_it_landed_on(self):
        # mouseUp used to read the knob's position. A click never moves the
        # knob, so it always resolved to the mode already selected and the
        # control only responded to drags.
        self.assertIn("if movedWhileDragging", self.slider)
        self.assertIn("nearestDetentIndex(toward: pressX)", self.slider)
        self.assertIn("private static let dragSlop", self.slider)

    def test_a_click_cannot_select_an_unsupported_mode(self):
        # Both the drag and the click path go through the same filter, so
        # High Power stays unreachable on hardware without it.
        chooser = self.slider.split("private func nearestIndex(toward x: CGFloat)", 1)[1]
        self.assertIn("modes.indices.filter { enabled[$0] }", chooser)
        mouse_up = self.slider.split("override func mouseUp", 1)[1].split("\n    private func", 1)[0]
        self.assertIn("guard enabled[pressedIndex] else", mouse_up)


if __name__ == "__main__":
    unittest.main()
