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
        # One untinted system glass track carries a neutral moving selection
        # capsule, avoiding a foggy glass-on-glass stack.
        self.assertIn("ModeSliderView(modes:", self.content)
        self.assertNotIn("NSSegmentedControl(", self.content)
        self.assertIn("NSGlassEffectView(frame:", self.slider)
        self.assertNotIn("NSGlassEffectContainerView(frame:", self.slider)
        self.assertIn("let base = NSGlassEffectView", self.slider)
        self.assertIn("style: .regular", self.slider)
        self.assertIn("tint: nil, content: trackContent", self.slider)
        self.assertIn("case nativeSelection(NSView)", self.slider)
        self.assertIn("weight: .regular", self.slider)
        self.assertIn("weight: .semibold", self.slider)
        self.assertIn("func setLifted(_ lifted: Bool)", self.slider)
        self.assertIn("trackContent.addSubview(field)", self.slider)
        self.assertIn("override func mouseDragged", self.slider)
        self.assertIn("private var settleCompletionWorkItem: DispatchWorkItem?", self.slider)
        self.assertIn("self.knobHost.frame = frame", self.slider)

    def test_native_glass_is_not_covered_by_an_opaque_imitation(self):
        self.assertNotIn("alpha: 0.95", self.slider)
        self.assertNotIn("alpha: 0.55", self.slider)
        self.assertIn("guard !usesNativeGlass else { return }", self.slider)
        self.assertIn("tint: PopoverStyle.stateColor(latestSnapshot.state)", self.content)

    def test_mode_change_is_completed_asynchronously(self):
        self.assertIn("@escaping (EnergyMode?) -> Void", self.slider)
        self.assertIn("pendingSelectionIndex", self.slider)
        self.assertIn("EnergyModeController.set(mode)", self.status)
        self.assertIn("completion(landedMode)", self.status)

    def test_custom_slider_has_keyboard_and_voiceover_semantics(self):
        self.assertIn("override var acceptsFirstResponder", self.slider)
        self.assertIn("override func keyDown", self.slider)
        self.assertIn("accessibilityPerformIncrement", self.slider)
        self.assertIn("accessibilityPerformDecrement", self.slider)
        self.assertIn("setAccessibilityRole(.slider)", self.slider)
        self.assertIn("setAccessibilityElement(false)", self.slider)

    def test_mouse_click_does_not_leave_a_blue_keyboard_focus_ring(self):
        mouse_down = self.slider.split("override func mouseDown", 1)[1].split(
            "\n    override func mouseDragged", 1
        )[0]
        self.assertNotIn("makeFirstResponder", mouse_down)
        self.assertIn("focusRingType = .none", self.slider)
        self.assertNotIn("override func drawFocusRingMask", self.slider)
        # Keyboard and VoiceOver semantics remain even without the redundant
        # full-capsule accent outline.
        self.assertIn("override var acceptsFirstResponder", self.slider)

    def test_legacy_material_tracks_reduce_transparency_without_double_text(self):
        self.assertIn("accessibilityDisplayShouldReduceTransparency", self.slider)
        self.assertIn("NSWorkspace.shared.notificationCenter", self.slider)
        blend = self.slider.split("private func applyLabelBlend", 1)[1].split(
            "\n    /// During the brief settle", 1
        )[0]
        self.assertIn("Float(1 - weight)", blend)
        self.assertNotIn("self.usesNativeGlass", blend)

    def test_lifted_capsule_reserves_space_before_the_settings_button(self):
        self.assertIn("bounds.width - 46", self.content)
        self.assertIn("bounds.width - 22", self.content)

    def test_settings_menu_reports_the_running_bundle_version(self):
        menu = self.content.split("private func showModuleMenu", 1)[1].split(
            "@objc private func quitApp", 1
        )[0]
        self.assertIn('forInfoDictionaryKey: "CFBundleShortVersionString"', menu)
        self.assertIn('title: "Wattson Version \\(version)"', menu)
        self.assertIn("versionItem.isEnabled = false", menu)

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

    def test_glass_configuration_uses_typed_api_not_kvc(self):
        # KVC turns a missing glass property into an Objective-C exception that
        # Swift cannot recover from. The public macOS 26 API is compile-checked.
        self.assertIn("case nativeSelection(NSView)", self.slider)
        self.assertIn("case plain(NSView)", self.slider)
        self.assertIn("trackGlass as? NSGlassEffectView", self.slider)
        self.assertIn("knob?.applyTint(", self.slider)
        self.assertNotIn("setValue", self.slider)

    def test_legacy_knob_path_is_reachable_for_testing(self):
        # On a macOS 26 machine the fallback is otherwise dead code that would
        # only ever run on someone else's Mac.
        self.assertIn("WATTSON_FORCE_LEGACY_KNOB", self.slider)

    def test_release_runner_can_force_both_reduce_motion_paths(self):
        self.assertIn('case "1": return true', self.slider)
        self.assertIn('case "0": return false', self.slider)

    def test_knob_has_a_fallback_below_macos_26(self):
        # Liquid Glass is macOS 26 only; older systems get a plain translucent
        # pill rather than a hand-rolled imitation.
        self.assertIn("#available(macOS 26.0, *)", self.slider)
        self.assertIn("} else {", self.slider)

    def test_three_modes_are_always_visible_in_requested_order(self):
        self.assertIn("[.auto, .low, .high]", self.content)
        for title in ('"Auto"', '"Low Power"', '"High Power"'):
            self.assertIn(title, self.energy_mode)

    def test_unsupported_high_power_is_disabled_not_removed(self):
        # The detent stays visible but cannot be snapped to, so the control
        # never silently loses a position.
        self.assertIn("EnergyModeController.supportsHighPower", self.content)
        self.assertIn("enabledModes:", self.content)
        self.assertIn("candidates = modes.indices.filter { enabled[$0] }", self.slider)

    def test_system_battery_checkbox_is_in_the_footer(self):
        self.assertIn('checkboxWithTitle: "Hide System Battery Icon"', self.content)
        self.assertIn("onSystemBatteryIconToggle", self.content)

    def test_system_battery_state_is_queried_only_when_opening(self):
        # The query wakes the helper through launchd, so it must not run on the
        # 1 Hz refresh or when the popover is closing.
        primary = self.status.split("case .primary:", 1)[1].split("case .secondary:", 1)[0]
        self.assertIn("let opening = !popover.isOpen", primary)
        self.assertIn("if opening", primary)
        self.assertIn("refreshSystemBatteryIconState", primary)
        refresh = self.status.split("private func refreshPresentation()", 1)[1]
        self.assertNotIn("SystemBatteryIconController.isHidden", refresh)

    def test_opening_is_not_blocked_by_the_system_battery_query(self):
        # A cold launchd helper, or a wedged socket, may take up to the client
        # timeout. The popover must already be on screen before that work starts.
        primary = self.status.split("case .primary:", 1)[1].split("case .secondary:", 1)[0]
        self.assertLess(primary.index("popover.toggle"),
                        primary.index("refreshSystemBatteryIconState"))
        self.assertIn("SystemBatteryIconController.refreshHidden", self.status)
        self.assertIn("DispatchQueue", self.system_icon)
        self.assertIn("DispatchQueue.main.async", self.system_icon)

    def test_stale_system_battery_reads_cannot_overwrite_a_newer_choice(self):
        self.assertIn("systemBatteryIconRefreshGeneration", self.status)
        self.assertIn("guard generation == self.systemBatteryIconRefreshGeneration", self.status)

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

    def test_knob_only_grows_after_drag_threshold_and_fits_one_detent_at_rest(self):
        self.assertIn("let width = segmentWidth", self.slider)
        self.assertNotIn("segmentWidth * 1.18", self.slider)
        mouse_down = self.slider.split("override func mouseDown", 1)[1].split(
            "\n    override func mouseDragged", 1
        )[0]
        self.assertNotIn("showPressedState", mouse_down)
        self.assertNotIn("setLifted(true)", mouse_down)
        mouse_dragged = self.slider.split("override func mouseDragged", 1)[1].split(
            "\n    override func mouseUp", 1
        )[0]
        threshold = mouse_dragged.split("if !movedWhileDragging", 1)[1]
        self.assertIn("setLifted(true)", threshold)
        self.assertIn("moveKnob(centreX:", mouse_dragged)
        move = self.slider.split("private func moveKnob", 1)[1].split(
            "\n    /// The dragged capsule", 1
        )[0]
        self.assertIn("setKnobGeometry", move)

    def test_clicks_flow_magnetically_and_drag_releases_spring(self):
        self.assertIn("case magnetic", self.slider)
        self.assertIn("case spring", self.slider)
        self.assertIn("let overshoot", self.slider)
        self.assertIn("startSettleMotion(kind: .magnetic", self.slider)
        self.assertIn("private func magneticScale", self.slider)
        self.assertIn("startSettleMotion(kind: .spring", self.slider)
        self.assertIn("private func springProgress", self.slider)
        self.assertIn("let duration: CFTimeInterval = 0.24", self.slider)
        self.assertIn('CAKeyframeAnimation(keyPath: "position")', self.slider)
        self.assertIn('CAKeyframeAnimation(keyPath: "transform")', self.slider)
        self.assertNotIn("Timer(timeInterval:", self.slider)
        self.assertIn("movedWhileDragging ? .spring : .magnetic", self.slider)

        magnetic = self.slider.split("private func magneticMotion", 1)[1].split(
            "\n    /// Click motion", 1
        )[0]
        self.assertNotIn("halfWindow", magnetic)
        self.assertNotIn("phases.removeAll", magnetic)
        self.assertIn("centreOverrides.append((crossing, detent))", magnetic)

    def test_label_brightness_tracks_capsule_distance_without_relayout(self):
        self.assertIn("private var activeLabels: [NSTextField]", self.slider)
        weights = self.slider.split("private func labelBlendWeights", 1)[1].split(
            "\n    private func applyLabelBlend", 1
        )[0]
        self.assertIn("1 - distance / max(segmentWidth, 1)", weights)
        self.assertIn("let crossing = phase(forLinearProgress: progress)", self.slider)
        self.assertIn("centreOverrides.append((crossing, detent))", self.slider)
        blend = self.slider.split("private func applyLabelBlend", 1)[1].split(
            "\n    /// During the brief settle", 1
        )[0]
        self.assertIn("layer?.opacity", blend)
        drag = self.slider.split("private func moveKnob", 1)[1].split(
            "\n    /// The dragged capsule", 1
        )[0]
        self.assertIn("setKnobGeometry", drag)
        self.assertNotIn("textColor", drag)
        frame_update = self.slider.split("private func setKnobFrame", 1)[1].split(
            "\n    private func setKnobGeometry", 1
        )[0]
        self.assertIn("applyLabelBlend(at: frame.midX)", frame_update)
        driver = self.slider.split("private func startSettleMotion", 1)[1].split(
            "\n    private func stopSettleMotion", 1
        )[0]
        self.assertIn("let labelWeights = frames.map", driver)
        self.assertIn("active.values = labelWeights.map", driver)
        self.assertIn("base.values = labelWeights.map", driver)
        self.assertIn('layer.add(group, forKey: "wattson.settle.geometry")', driver)
        transaction_start = driver.rindex("CATransaction.begin()")
        model_write = driver.rindex("setKnobFrame(target)")
        animation_add = driver.index('layer.add(group, forKey: "wattson.settle.geometry")')
        transaction_commit = driver.rindex("CATransaction.commit()")
        self.assertLess(transaction_start, model_write)
        self.assertLess(model_write, animation_add)
        self.assertLess(animation_add, transaction_commit)
        self.assertLess(frame_update.index("self.knobHost.frame = frame"),
                        frame_update.index("applyLabelBlend(at: frame.midX)"))

    def test_settle_runs_on_the_compositor_and_can_be_interrupted_visually(self):
        settle = self.slider.split("private func settle", 1)[1].split(
            "\n    private func magneticDuration", 1
        )[0]
        self.assertIn("startSettleMotion", settle)
        self.assertIn("let start = visibleKnobFrame()", settle)
        self.assertNotIn("Timer", settle)
        driver = self.slider.split("private func startSettleMotion", 1)[1].split(
            "\n    private func stopSettleMotion", 1
        )[0]
        self.assertIn("CAAnimationGroup()", driver)
        self.assertIn("settleGeneration == generation", driver)
        interrupt = self.slider.split("private func interruptSettleAtVisibleGeometry", 1)[1].split(
            "\n    private func moveKnob", 1
        )[0]
        self.assertLess(interrupt.index("visibleKnobFrame()"),
                        interrupt.index("stopSettleMotion()"))
        self.assertNotIn("removeAllAnimations", interrupt)
        visible = self.slider.split("private func visibleKnobFrame", 1)[1].split(
            "\n    private func setKnobFrame", 1
        )[0]
        self.assertIn("layer?.presentation()", visible)
        self.assertIn("presentation.transform.m11", visible)
        layout = self.slider.split("override func layout()", 1)[1].split(
            "\n    // MARK: - State", 1
        )[0]
        self.assertIn("if !dragging, activeSettleMotion == nil", layout)

    def test_display_option_refresh_cannot_lift_a_click_below_drag_slop(self):
        refresh = self.slider.split("private func refreshDisplayOptions", 1)[1].split(
            "\n    /// GitHub Mobile", 1
        )[0]
        self.assertIn("setLifted(movedWhileDragging)", refresh)
        self.assertNotIn("setLifted(dragging)", refresh)

        update = self.slider.split("func update(selected:", 1)[1].split(
            "\n    /// Clicks flow", 1
        )[0]
        self.assertIn("setLifted(movedWhileDragging)", update)

    def test_native_track_and_selector_follow_github_mobile_hierarchy(self):
        self.assertIn("configureGlass(base, style: .regular", self.slider)
        self.assertIn("tint: nil, content: trackContent", self.slider)
        self.assertIn("selector.layer?.backgroundColor = NSColor.white.withAlphaComponent", self.slider)
        self.assertIn("selector.layer?.borderWidth = 0", self.slider)
        self.assertNotIn("configureGlass(selector", self.slider)
        self.assertNotIn("case glass(NSView)", self.slider)
        track_tint = self.slider.split("private func applyTrackTint", 1)[1].split(
            "\n    /// Core Animation", 1
        )[0]
        self.assertIn("guard !usesNativeGlass else { return }", track_tint)
        self.assertNotIn("glass.tintColor", track_tint)
        self.assertIn("PopoverStyle.wellBorder.withAlphaComponent", track_tint)
        self.assertNotIn("WATTSON_FORCE_OPTICAL_LENS", self.slider)
        self.assertNotIn("backdropFilters", self.slider)
        fallback = self.slider.split("private func installFallbackChromeIfNeeded", 1)[1].split(
            "\n    private func refreshDisplayOptions", 1
        )[0]
        self.assertIn("masksToBounds = !usesNativeGlass", fallback)

    def test_footer_panel_tint_tracks_all_power_states_instead_of_fixed_blue(self):
        update_footer = self.content.split("private func updateFooter", 1)[1].split(
            "\n    private func", 1
        )[0]
        self.assertIn("PopoverStyle.stateColor(latestSnapshot.state)", update_footer)
        footer = self.content.split("final class PopoverFooterView", 1)[1].split(
            "final class PopoverContentViewController", 1
        )[0]
        self.assertNotIn("tint: PopoverStyle.blue", footer)

    def test_a_click_cannot_select_an_unsupported_mode(self):
        # Both the drag and the click path go through the same filter, so
        # High Power stays unreachable on hardware without it.
        chooser = self.slider.split("private func nearestIndex(toward x: CGFloat)", 1)[1]
        self.assertIn("modes.indices.filter { enabled[$0] }", chooser)
        mouse_up = self.slider.split("override func mouseUp", 1)[1].split("\n    private func", 1)[0]
        self.assertIn("guard enabled[pressedIndex] else", mouse_up)


if __name__ == "__main__":
    unittest.main()
