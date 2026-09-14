import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
CONTENT = ROOT / "Popover" / "PopoverContentView.swift"
SLIDER = ROOT / "Popover" / "ModeSliderView.swift"
GLASS_MODE = ROOT / "Popover" / "NativeGlassModeControl.swift"
INTERACTIVE_GLASS_MODE = ROOT / "Popover" / "InteractiveGlassModeControl.swift"
STATUS = ROOT / "MenuBar" / "StatusItemController.swift"
SYSTEM_ICON = ROOT / "Core" / "SystemBatteryIcon.swift"
ENERGY_MODE = ROOT / "Core" / "EnergyMode.swift"
POPOVER = ROOT / "Popover" / "PopoverController.swift"
GLASS_PANEL = ROOT / "Popover" / "GlassPopoverPanel.swift"


class PopoverControlsContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.content = CONTENT.read_text(encoding="utf-8")
        cls.slider = SLIDER.read_text(encoding="utf-8")
        cls.glass_mode = GLASS_MODE.read_text(encoding="utf-8")
        cls.interactive_glass_mode = INTERACTIVE_GLASS_MODE.read_text(encoding="utf-8")
        cls.status = STATUS.read_text(encoding="utf-8")
        cls.system_icon = SYSTEM_ICON.read_text(encoding="utf-8")
        cls.energy_mode = ENERGY_MODE.read_text(encoding="utf-8")
        cls.popover = POPOVER.read_text(encoding="utf-8")
        cls.glass_panel = GLASS_PANEL.read_text(encoding="utf-8")

    def test_mode_picker_is_a_draggable_glass_knob(self):
        # macOS 26 batches a regular track and a clear moving optical lens in
        # the public glass container. Older systems use the sampled fallback.
        self.assertIn("ModeSliderView(modes:", self.content)
        self.assertNotIn("NSSegmentedControl(", self.content)
        self.assertIn("NSGlassEffectView(frame:", self.slider)
        self.assertIn("NSGlassEffectContainerView(frame:", self.slider)
        self.assertIn("let base = NSGlassEffectView", self.slider)
        self.assertIn("style: .regular", self.slider)
        self.assertIn("tint: nil, content: trackContent", self.slider)
        self.assertIn("configureGlass(selector, style: .clear", self.slider)
        self.assertIn("container.contentView = materialContent", self.slider)
        self.assertIn("materialContent.addSubview(knobHost)", self.slider)
        self.assertIn("case nativeSelection(NSView)", self.slider)
        self.assertIn("weight: .regular", self.slider)
        self.assertIn("weight: .semibold", self.slider)
        self.assertIn("func setLifted(_ lifted: Bool, reduceMotion: Bool)", self.slider)
        self.assertIn("trackContent.addSubview(field)", self.slider)
        self.assertIn("override func mouseDragged", self.slider)
        self.assertIn("private var settleCompletionWorkItem: DispatchWorkItem?", self.slider)
        self.assertIn("self.knobHost.frame = frame", self.slider)

    def test_native_glass_is_not_covered_by_an_opaque_imitation(self):
        self.assertNotIn("alpha: 0.95", self.slider)
        self.assertNotIn("alpha: 0.55", self.slider)
        self.assertIn("guard !usesNativeGlass else { return }", self.slider)
        self.assertIn("tint: PopoverStyle.stateColor(latestSnapshot.state)", self.content)

    def test_native_glass_has_no_custom_fill_or_white_rim(self):
        native = self.slider.split(
            "if !forceLegacyMaterials, #available(macOS 26.0, *)", 1
        )[1].split("} else {", 1)[0]
        self.assertIn("selector.layer?.backgroundColor = NSColor.clear.cgColor", native)
        self.assertIn("let content = NSView(frame: .zero)", native)
        self.assertNotIn("OpticalLensChromeView(frame:", native)
        self.assertNotIn("withAlphaComponent(0.035)", native)

    def test_native_glass_click_motion_updates_real_view_geometry_per_display(self):
        self.assertIn("let displayLink = window.displayLink(", self.slider)
        self.assertNotIn("NSScreen.main", self.slider.split(
            "private func startNativeGlassSettleMotion", 1
        )[1].split("nativeGlassDisplayLinkDidFire", 1)[0])
        self.assertIn("nativeGlassDisplayLinkDidFire", self.slider)
        driver = self.slider.split("private func startSettleMotion", 1)[1].split(
            "\n    private func stopSettleMotion", 1
        )[0]
        self.assertIn("if usesNativeGlass", driver)
        self.assertIn("startNativeGlassSettleMotion", driver)

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

    def test_optional_glass_menu_button_uses_system_style_and_restores_baseline(self):
        footer = self.content.split("final class PopoverFooterView", 1)[1].split(
            "\nprivate final class PopoverSurfaceView", 1
        )[0]
        refresh = footer.split("private func refreshDisplayOptions(reduceMotion:", 1)[1].split(
            "\n    @objc private func systemBatteryIconChanged", 1
        )[0]
        glass, classic = refresh.split("        } else {", 1)
        self.assertIn("if #available(macOS 26.0, *), Settings.usesLiquidGlass", glass)
        # Classic Reduce Motion retains its own native segmented appearance.
        self.assertNotIn("nativeModeControl.cell?.isBordered", footer)
        self.assertNotIn("nativeModeControl.borderShape =", footer)
        self.assertIn("settingsButton.bezelStyle = .glass", glass)
        self.assertIn("settingsButton.borderShape = .circle", glass)
        self.assertIn("settingsButton.isBordered = true", glass)
        self.assertIn("settingsButton.contentTintColor = nil", glass)
        self.assertIn("settingsButton.borderShape = .automatic", classic)
        self.assertIn("settingsButton.bezelStyle = .rounded", classic)
        self.assertIn("settingsButton.isBordered = false", classic)
        self.assertIn("settingsButton.contentTintColor = PopoverStyle.secondaryText", classic)
        self.assertIn("addSubview(settingsButton)", classic)
        self.assertIn("glassControls?.isHidden = true", classic)
        # The focused glass child and menu must retain keyboard continuity when
        # switching the appearance, including when Reduce Motion is enabled.
        self.assertNotIn("else { return }", refresh)
        self.assertIn("let useGlassControl = Settings.usesLiquidGlass", refresh)
        self.assertIn("let useNativeControl = reduceMotion && !useGlassControl", refresh)
        self.assertIn("isDescendant(of: previousControl)", refresh)
        self.assertIn("glassModeControl?.keyboardFocusView", refresh)
        for capture in ("let transferFocus =", "var restoreMenuFocus ="):
            self.assertLess(refresh.index(capture),
                            refresh.index("glassControlsContent.addSubview(settingsButton)"))
        self.assertIn("if transferFocus, previousControl !== nextControl {", refresh)
        self.assertIn("window?.makeFirstResponder(focusView)", refresh)
        self.assertIn("if restoreMenuFocus {", refresh)
        self.assertIn("requestMenuFocus()", refresh)
        self.assertIn("window?.makeFirstResponder(settingsButton)", refresh)

    def test_a2_uses_the_accepted_public_interactive_glass_with_one_label_copy(self):
        source = self.interactive_glass_mode
        self.assertIn("NSHostingView<InteractiveGlassModeView>", source)
        self.assertIn("GlassEffectContainer(spacing: 0)", source)
        self.assertIn(".glassEffect(controlGlass.interactive(), in: InteractiveModeCapsule", source)
        self.assertIn(".glassEffect(controlGlass.interactive(), in: Circle())", source)
        self.assertEqual(source.count("Text(model.modes[index].title)"), 1)
        self.assertIn(".contentShape(.focusEffect, Capsule())", source)
        self.assertIn(".contentShape(.focusEffect, Circle())", source)
        for forbidden in ("LinearGradient", "CAGradientLayer", "backdropFilters", "setValue(",
                          "cacheDisplay", "bitmapImageRepForCachingDisplay", "focusEffectDisabled"):
            self.assertNotIn(forbidden, source)

    def test_a2_transient_pointer_state_is_separate_from_owner_selection(self):
        source = self.interactive_glass_mode
        self.assertIn("@GestureState private var pointer: Pointer?", source)
        self.assertIn("DragGesture(minimumDistance: 4", source)
        self.assertIn(".updating($pointer)", source)
        self.assertIn("model.remember(state.drag)", source)
        self.assertRegex(source, r"\.onEnded \{ value in\s+_ = model\.finishDrag\(translationX:")
        self.assertIn("drag.generation == generation", source)
        self.assertIn("labelRect($0).contains(start) && enabledModes.contains(modes[$0])", source)
        self.assertIn("allowed: pressedIndex == selectedIndex", source)
        self.assertIn("translationX.isFinite", source)
        self.assertIn("lastDrag = nil", source)
        self.assertIn("modes.indices.filter { enabledModes.contains(modes[$0]) }", source)
        self.assertNotIn("@State private var selectedIndex", source)
        request = source.split("func request(_ index: Int)", 1)[1].split("func move(", 1)[0]
        self.assertIn("enabledModes.contains(modes[index])", request)
        self.assertIn("guard index != selectedIndex else { return true }", request)
        self.assertIn("onSelect(modes[index])", request)
        self.assertNotRegex(request, r"\bselectedIndex\s*=(?!=)")

    def test_a2_lifecycle_cancels_and_keeps_native_keyboard_accessibility(self):
        source = self.interactive_glass_mode
        for lifecycle in ("NSApplication.didResignActiveNotification", "NSWindow.didResignKeyNotification",
                          "override func viewDidHide()", "override func viewWillMove(toWindow",
                          "override func cancelOperation", ".onDisappear { model.cancel() }"):
            self.assertIn(lifecycle, source)
        self.assertIn("NotificationCenter.default.removeObserver(self)", source)
        self.assertIn(".disabled(!model.enabledModes.contains(model.modes[index]))", source)
        self.assertIn('.accessibilityLabel("Power Mode")', source)
        self.assertIn('.accessibilityLabel("Choose Modules")', source)
        self.assertIn('.accessibilityValue(index == model.selectedIndex ? "Selected" : "Not selected")', source)
        self.assertIn(".accessibilityAddTraits(index == model.selectedIndex ? .isSelected : [])", source)
        self.assertIn(".onMoveCommand", source)
        self.assertIn(".onKeyPress(.return)", source)
        self.assertIn(".onExitCommand", source)
        self.assertIn(".contains(convert(point, from: superview)) else { return nil }", source)

    def test_a2_optical_padding_does_not_change_the_classic_footer_geometry(self):
        footer = self.content.split("final class PopoverFooterView", 1)[1].split(
            "\nprivate final class PopoverSurfaceView", 1
        )[0]
        self.assertIn("interactiveGlassControl?.frame = NSRect(x: -12, y: 24, width: bounds.width + 24, height: 62)", footer)
        self.assertIn("static let opticalInset: CGFloat = 12", self.interactive_glass_mode)
        self.assertIn("bounds.insetBy(dx: Self.opticalInset, dy: Self.opticalInset)", self.interactive_glass_mode)
        self.assertIn("static let preferredHeight: CGFloat = 78", footer)
        self.assertIn("modeControl.frame = modeFrame", footer)
        self.assertIn("nativeModeControl.frame = modeFrame", footer)

    def test_footer_glass_operations_use_one_container_and_native_button_surfaces(self):
        footer = self.content.split("final class PopoverFooterView", 1)[1].split(
            "\nprivate final class PopoverSurfaceView", 1
        )[0]
        self.assertEqual(footer.count("NSGlassEffectContainerView(frame:"), 1)
        self.assertNotIn("NSGlassEffectView", footer)
        self.assertIn("if glassControls == nil {", footer)
        self.assertIn("container.spacing = 0", footer)
        self.assertIn("container.contentView = glassControlsContent", footer)
        self.assertIn("let control = NativeGlassModeControl(modes: modes)", footer)
        self.assertIn("glassControlsContent.addSubview(control)", footer)
        self.assertIn("glassControlsContent.addSubview(settingsButton)", footer)
        self.assertNotIn("container.addSubview", footer)
        self.assertIn("button.setButtonType(.pushOnPushOff)", self.glass_mode)
        self.assertIn("button.allowsMixedState = false", self.glass_mode)
        self.assertIn("button.isBordered = true", self.glass_mode)
        self.assertIn("button.bezelStyle = .glass", self.glass_mode)
        self.assertIn("button.borderShape = .capsule", self.glass_mode)
        self.assertIn("button.tintProminence = selected ? .primary : .none", self.glass_mode)
        # Each button owns its system material, without an extra glass well or
        # painted selection surface. Only native prominence marks selection.
        self.assertNotIn("NSGlassEffectView", self.glass_mode)
        self.assertNotIn("NSGlassEffectContainerView", self.glass_mode)
        for source in (footer, self.glass_mode):
            self.assertNotIn(".tintColor", source)
            self.assertNotIn("backgroundColor =", source)
            self.assertNotIn("setValue(", source)

    def test_footer_glass_geometry_preserves_classic_row_and_total_height(self):
        footer = self.content.split("final class PopoverFooterView", 1)[1].split(
            "\nprivate final class PopoverSurfaceView", 1
        )[0]
        layout = footer.split("override func layout()", 1)[1].split("\n    func update(", 1)[0]
        self.assertIn("static let preferredHeight: CGFloat = 78", footer)
        self.assertIn("systemBatteryIconButton.frame = NSRect(x: 0, y: 10, width: 168, height: 20)", layout)
        self.assertIn("hint.frame = NSRect(x: 168, y: 12, width: bounds.width - 168, height: 15)", layout)
        self.assertIn("x: 0, y: 36, width: bounds.width - 46", layout)
        self.assertIn("height: ModeSliderView.preferredHeight", layout)
        self.assertIn("modeControl.frame = modeFrame", layout)
        self.assertIn("nativeModeControl.frame = modeFrame", layout)
        glass, classic = layout.split("if Settings.usesLiquidGlass {", 1)[1].split("} else {", 1)
        self.assertIn("glassControls?.frame = NSRect(x: 0, y: 36, width: bounds.width, height: 38)", glass)
        self.assertIn("glassControlsContent.frame = glassControls?.bounds ?? .zero", glass)
        self.assertIn("glassModeControl?.frame = NSRect(x: 0, y: 0, width: modeFrame.width, height: 38)", glass)
        self.assertIn("settingsButton.frame = NSRect(x: bounds.width - 38, y: 0, width: 38, height: 38)", glass)
        self.assertIn("settingsButton.frame = NSRect(x: bounds.width - 22, y: 42, width: 22, height: 20)", classic)
        self.assertIn("static let preferredHeight: CGFloat = 38", self.glass_mode)
        self.assertIn("private static let buttonSpacing: CGFloat = 6", self.glass_mode)
        self.assertIn("bounds.width - CGFloat(buttons.count - 1) * Self.buttonSpacing", self.glass_mode)
        self.assertIn("/ CGFloat(buttons.count)", self.glass_mode)
        self.assertIn("CGFloat(index) * (width + Self.buttonSpacing)", self.glass_mode)
        self.assertIn("y: 0, width: width, height: bounds.height", self.glass_mode)

    def test_glass_interaction_isolates_preferences_before_constructing_views(self):
        interaction = (ROOT / "tests" / "interaction" / "main.swift").read_text()
        self.assertLess(interaction.index("Settings.configureForTest(defaults:"),
                        interaction.index("NSApplication.shared"))
        self.assertEqual(interaction.count("Settings.configureForTest(defaults:"), 1)

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

    def test_glass_background_is_a_replacement_public_host_not_a_nested_popover(self):
        self.assertIn("final class GlassPopoverPanel: NSPanel", self.glass_panel)
        self.assertIn("[.borderless, .nonactivatingPanel]", self.glass_panel)
        self.assertIn("isOpaque = false", self.glass_panel)
        self.assertIn("backgroundColor = .clear", self.glass_panel)
        self.assertIn("override var canBecomeKey: Bool { true }", self.glass_panel)
        self.assertIn("override var canBecomeMain: Bool { false }", self.glass_panel)
        self.assertEqual(self.glass_panel.count("NSGlassEffectView(frame:"), 1)
        self.assertIn("glass.style = style", self.glass_panel)
        self.assertNotIn("glass.contentView = content", self.glass_panel)
        self.assertIn("contentView!.addSubview(content)", self.glass_panel)
        self.assertIn("contentView!.addSubview(glass)", self.glass_panel)
        self.assertIn("style: Settings.liquidGlassStyle == .clear ? .clear : .regular", self.popover)
        self.assertIn("popover.show(relativeTo:", self.popover)
        self.assertIn("usingGlassPanel ? glassPanel?.isVisible == true : popover.isShown", self.popover)
        for forbidden in ("NSVisualEffectView", "CAGradientLayer", "backdropFilters", "setValue(",
                          "activate(ignoringOtherApps", "activate(options:"):
            self.assertNotIn(forbidden, self.glass_panel)

    def test_glass_local_click_routing_preserves_anchor_toggle_and_native_menus(self):
        route = self.popover.split("private func shouldDismissLocalClick(window:", 1)[1].split(
            "\n    private func handleEscape", 1
        )[0]
        self.assertIn("guard usingGlassPanel, wantsOpen else { return false }", route)
        self.assertIn("window === glassPanel { return false }", route)
        self.assertIn("frame.contains(screenPoint) { return false }", route)
        self.assertIn("!trackingMenus.isEmpty", route)
        self.assertIn("window == nil || window!.level >= .popUpMenu", route)
        watcher = self.popover.split("private func startWatchingForOutsideClicks()", 1)[1].split(
            "\n    private func shouldDismissLocalClick", 1
        )[0]
        self.assertIn("NSEvent.addLocalMonitorForEvents", watcher)
        self.assertIn("shouldDismissLocalClick(window: event.window, screenPoint: point) { self.close() }", watcher)
        self.assertIn("NSMenu.didBeginTrackingNotification", watcher)
        self.assertIn("NSMenu.didEndTrackingNotification", watcher)
        self.assertIn("guard usingGlassPanel else { return }", watcher)

    def test_escape_first_belongs_to_menu_then_drag_then_panel(self):
        escape = self.popover.split("private func handleEscape()", 1)[1].split("\n    ///", 1)[0]
        self.assertIn("guard trackingMenus.isEmpty else { return false }", escape)
        self.assertIn("if !content.cancelActiveModeDrag() { close() }", escape)
        key_route = self.popover.split("if event.type == .keyDown {", 1)[1].split("} else {", 1)[0]
        self.assertIn("event.keyCode == 53", key_route)
        self.assertIn("self.glassPanel?.ownsEscapeEvent(eventWindow: event.window, keyWindow: NSApp.keyWindow) == true", key_route)
        self.assertIn("self.handleEscape() { return nil }", key_route)
        self.assertLess(key_route.index("ownsEscapeEvent"), key_route.index("self.handleEscape()"))
        self.assertIn("override func cancelOperation(_ sender: Any?) { onEscape?() }", self.glass_panel)
        self.assertIn("func cancelActiveModeDrag() -> Bool { footer.cancelActiveModeDrag() }", self.content)

    def test_glass_close_and_deinit_release_all_scoped_event_observers(self):
        cleanup = self.popover.split("private func stopWatchingForOutsideClicks()", 1)[1].split(
            "\n}\n", 1
        )[0]
        for source in ("outsideClickMonitor = nil", "localEventMonitor = nil",
                       "localObservers.forEach(NotificationCenter.default.removeObserver)",
                       "localObservers.removeAll()", "workspaceObservers.removeAll()",
                       "workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)",
                       "observedAnchor?.postsFrameChangedNotifications = anchorPostedFrameChanges",
                       "trackingMenus.removeAll()", "$0.cancelTracking()"):
            self.assertIn(source, cleanup)
        close = self.popover.split("private func close()", 1)[1].split(
            "\n    private func closeBeforePresentingSettings", 1
        )[0]
        self.assertLess(close.index("stopWatchingForOutsideClicks()"), close.index("panel.orderOut(nil)"))
        self.assertIn("panel.onDismiss = nil", close)
        self.assertIn("panel.onEscape = nil", close)
        self.assertIn("panel.detachContent()", close)
        deinit = self.popover.split("deinit {", 1)[1].split(
            "\n    private func refreshLiquidGlassAppearance", 1
        )[0]
        self.assertIn("stopWatchingForOutsideClicks()", deinit)
        self.assertIn("glassPanel?.orderOut(nil)", deinit)

    def test_retiring_classic_host_resets_only_its_own_lifecycle_and_rejects_late_closes(self):
        retirement = self.popover.split("private func retireClassicHost()", 1)[1].split(
            "\n    private func resolvePlacement", 1
        )[0]
        self.assertLess(retirement.index("popover.delegate = nil"), retirement.index("popover.close()"))
        self.assertIn("popover.contentViewController = nil", retirement)
        self.assertIn("popover = NSPopover()", retirement)
        self.assertIn("showsRequested = 0", retirement)
        self.assertIn("closesObserved = 0", retirement)
        did_close = self.popover.split("func popoverDidClose", 1)[1].split("\n    ///", 1)[0]
        self.assertIn("closingPopover === popover else { return }", did_close)
        self.assertLess(did_close.index("closingPopover === popover"), did_close.index("closesObserved += 1"))
        self.assertIn("guard !usingGlassPanel else { return }", did_close)
        self.assertIn("guard closesObserved >= showsRequested else { return }", did_close)

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
        refresh = self.system_icon.split("static func refreshHidden", 1)[1].split(
            "static func setHidden", 1
        )[0]
        self.assertIn("operations.enqueueRead", refresh)
        self.assertIn("timeoutSeconds: 4", refresh)

    def test_system_battery_write_does_not_block_appkit(self):
        setter = self.system_icon.split("static func setHidden", 1)[1]
        self.assertIn("operations.enqueueMutation", setter)
        self.assertIn("timeoutSeconds: 6", setter)
        apply = self.status.split("private func applySystemBatteryIconHidden", 1)[1].split(
            "private func noBattery", 1
        )[0]
        self.assertIn("SystemBatteryIconController.setHidden(hidden)", apply)
        self.assertIn("completion(succeeded)", apply)

    def test_stale_system_battery_reads_cannot_overwrite_a_newer_choice(self):
        self.assertIn("latestSettledSequence", self.system_icon)
        self.assertIn("guard sequence >= latestSettledSequence", self.system_icon)
        self.assertIn("SystemBatteryIconController.didChange", self.status)
        self.assertIn("SystemBatteryIconController.cachedHidden", self.status)
        self.assertNotIn("systemBatteryIconRefreshGeneration", self.status)

    def test_system_battery_controller_uses_the_privileged_helper(self):
        self.assertIn('"getSystemBatteryIconHidden"', self.system_icon)
        self.assertIn('"setSystemBatteryIconHidden"', self.system_icon)
        self.assertNotIn("Process()", self.system_icon)

    def test_helper_backed_settings_share_one_serial_worker(self):
        self.assertIn("enum HelperSettingsOperationWorker", self.system_icon)
        self.assertIn(
            "worker: SerialOperationWorker = HelperSettingsOperationWorker.shared",
            self.system_icon,
        )
        self.assertIn("private func drainOne()", self.system_icon)

    def test_pending_settings_reads_can_be_cancelled_before_selection(self):
        cancellation = self.system_icon.split("func cancelPendingRead()", 1)[1].split(
            "func performMutation", 1
        )[0]
        self.assertIn("pendingRead = nil", cancellation)
        self.assertNotIn("pendingMutations", cancellation)

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

    def test_knob_keeps_one_detent_footprint_through_direct_drag(self):
        self.assertIn("let width = segmentWidth", self.slider)
        self.assertNotIn("segmentWidth * 1.18", self.slider)
        self.assertNotIn("pressedScale", self.slider)
        mouse_down = self.slider.split("override func mouseDown", 1)[1].split(
            "\n    override func mouseDragged", 1
        )[0]
        self.assertNotIn("showPressedState", mouse_down)
        self.assertNotIn("setLifted(true,", mouse_down)
        mouse_dragged = self.slider.split("override func mouseDragged", 1)[1].split(
            "\n    override func mouseUp", 1
        )[0]
        threshold = mouse_dragged.split("if !movedWhileDragging", 1)[1]
        self.assertIn("setLifted(true, reduceMotion: reducesMotion)", threshold)
        self.assertIn("moveKnob(centreX: centre)", mouse_dragged)
        self.assertNotIn("scaleX", mouse_dragged)
        self.assertNotIn("scaleY", mouse_dragged)
        move = self.slider.split("private func moveKnob", 1)[1].split(
            "\n    /// The dragged capsule", 1
        )[0]
        self.assertIn("setKnobGeometry", move)
        self.assertIn("width: base.width", move)
        self.assertIn("height: base.height", move)

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
        self.assertIn("let weights = labelBlendWeights(at: frame.midX)", frame_update)
        self.assertIn("self.applyLabelBlend(weights)", frame_update)
        driver = self.slider.split("private func startSettleMotion", 1)[1].split(
            "\n    private func stopSettleMotion", 1
        )[0]
        self.assertIn("let labelWeights = frames.map", driver)
        self.assertIn("active.values = labelWeights.map", driver)
        self.assertIn("base.values = labelWeights.map", driver)
        self.assertIn('layer.add(group, forKey: "wattson.settle.geometry")', driver)
        legacy = driver.split("let position = CAKeyframeAnimation", 1)[1].split(
            "\n        let workItem = DispatchWorkItem", 1
        )[0]
        transaction_start = legacy.index("CATransaction.begin()")
        model_write = legacy.index("setKnobFrame(target)")
        animation_add = legacy.index('layer.add(group, forKey: "wattson.settle.geometry")')
        transaction_commit = legacy.index("CATransaction.commit()")
        self.assertLess(transaction_start, model_write)
        self.assertLess(model_write, animation_add)
        self.assertLess(animation_add, transaction_commit)
        self.assertLess(frame_update.index("self.knobHost.frame = frame"),
                        frame_update.index("self.applyLabelBlend(weights)"))

    def test_each_slider_frame_commits_geometry_and_labels_in_one_transaction(self):
        frame_update = self.slider.split("private func setKnobFrame", 1)[1].split(
            "\n    private func setKnobGeometry", 1
        )[0]
        self.assertEqual(frame_update.count("PopoverStyle.setWithoutAnimation"), 1)
        transaction = frame_update.split(
            "PopoverStyle.setWithoutAnimation {", 1
        )[1].split("\n        }", 1)[0]
        self.assertIn("self.knobHost.frame = frame", transaction)
        self.assertIn("self.applyLabelBlend(weights)", transaction)
        self.assertNotIn("applyLabelBlend(at:", frame_update)

        raw_blend = self.slider.split(
            "private func applyLabelBlend(_ weights: [CGFloat])", 1
        )[1].split("\n    private func applyLabelBlend(at", 1)[0]
        self.assertIn("layer?.opacity", raw_blend)
        self.assertNotIn("PopoverStyle.setWithoutAnimation", raw_blend)

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
        self.assertIn("let anchorPoint = layer.anchorPoint", driver)
        self.assertIn("$0.minX + $0.width * anchorPoint.x", driver)
        self.assertIn("$0.minY + $0.height * anchorPoint.y", driver)
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
        self.assertIn("dragging && movedWhileDragging", refresh)
        self.assertIn("activeSettleMotion != nil", refresh)
        self.assertIn("if reduceMotion, activeSettleMotion != nil", refresh)
        self.assertIn("stopSettleMotion()", refresh)
        self.assertIn("setKnobFrame(knobFrame(at: selectedIndex))", refresh)
        self.assertIn("else if reduceMotion, dragging, movedWhileDragging", refresh)
        self.assertIn("setKnobGeometry(centreX: draggedCentre", refresh)

        update = self.slider.split("func update(selected:", 1)[1].split(
            "\n    /// Clicks flow", 1
        )[0]
        self.assertIn("dragging && movedWhileDragging", update)
        self.assertIn("activeSettleMotion != nil", update)

    def test_native_track_and_selector_follow_github_mobile_hierarchy(self):
        self.assertIn("configureGlass(base, style: .regular", self.slider)
        self.assertIn("tint: nil, content: trackContent", self.slider)
        self.assertIn("let container = NSGlassEffectContainerView", self.slider)
        self.assertIn("container.contentView = materialContent", self.slider)
        self.assertIn("configureGlass(selector, style: .clear", self.slider)
        self.assertIn("selector.layer?.backgroundColor = NSColor.clear.cgColor", self.slider)
        self.assertIn("selector.layer?.borderWidth = 0", self.slider)
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

    def test_legacy_lens_uses_a_bounded_real_track_capture_and_cheap_drag_crop(self):
        capture = self.slider.split("private func captureOpticalSnapshotIfNeeded", 1)[1].split(
            "\n    // MARK: - Geometry", 1
        )[0]
        self.assertIn("bitmapImageRepForCachingDisplay", capture)
        self.assertIn("cacheDisplay", capture)
        self.assertIn("fallbackLens.install(sample: image)", capture)
        self.assertIn("for label in self.labels { label.layer?.opacity = 0 }", capture)
        self.assertIn("opticalSnapshotDirty = false", capture)
        self.assertIn("override func viewDidChangeBackingProperties", self.slider)

        drag = self.slider.split("override func mouseDragged", 1)[1].split(
            "\n    override func mouseUp", 1
        )[0]
        self.assertNotIn("cacheDisplay", drag)
        self.assertNotIn("bitmapImageRepForCachingDisplay", drag)
        self.assertIn("moveKnob(centreX:", drag)

        sampling = self.slider.split("private func updateSamplingRect", 1)[1].split(
            "\n    override func layout", 1
        )[0]
        self.assertIn("sampleLayer.contentsRect = sampleRect", sampling)
        self.assertIn("magnification", sampling)

    def test_reduce_transparency_disables_refraction_and_uses_opaque_selector(self):
        material = self.slider.split("func applyMaterial", 1)[1].split(
            "\n    func update(hostFrameInTrack:", 1
        )[0]
        self.assertIn("sampleLayer.isHidden = !samplingEnabled", material)
        self.assertIn("opaqueModeSliderSelection", material)
        opaque = self.slider.split("private func opaqueModeSliderSelection", 1)[1].split(
            "\n}", 1
        )[0]
        self.assertIn("alpha: 1", opaque)
        self.assertIn("PopoverStyle.isDark", opaque)

        native = self.slider.split("private static func applyNativeSurface", 1)[1].split(
            "\n        func applyTint", 1
        )[0]
        self.assertIn("opaqueModeSliderSelection", native)
        self.assertIn("performAsCurrentDrawingAppearance", native)
        self.assertIn(": NSColor.clear", native)

    def test_fallback_refraction_is_scoped_to_lifted_direct_drag(self):
        fallback = self.slider.split("private final class LegacyOpticalLensView", 1)[1].split(
            "\n/// A horizontally locked mode bar", 1
        )[0]
        self.assertIn("lifted && !reduceTransparency && sampleImage != nil", fallback)
        self.assertIn("sampleLayer.isHidden = !samplingEnabled", fallback)
        self.assertIn("magnification = samplingEnabled ? 1.105 : 1", fallback)
        # Settle animations move the host on the render server. Keeping the
        # crop disabled then prevents a model-frame sample from drifting away
        # from the presentation-frame lens.
        self.assertIn("guard samplingEnabled else", fallback)

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
