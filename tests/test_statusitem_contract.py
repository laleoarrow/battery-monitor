import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
STATUS_SOURCE = ROOT / "MenuBar" / "StatusItemController.swift"
APP_DELEGATE_SOURCE = ROOT / "MenuBar" / "AppDelegate.swift"
POPOVER_SOURCE = ROOT / "Popover" / "PopoverController.swift"
STYLE_SOURCE = ROOT / "Popover" / "PopoverStyle.swift"
ANIMATION_HARNESS = ROOT / "tests" / "animation_stress" / "main.swift"
ANIMATION_RUNNER = ROOT / "scripts" / "verify_animation_stress.sh"
INTERACTION_HARNESS = ROOT / "tests" / "interaction" / "main.swift"


class StatusItemContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = STATUS_SOURCE.read_text(encoding="utf-8")
        cls.app_delegate = APP_DELEGATE_SOURCE.read_text(encoding="utf-8")
        cls.popover = POPOVER_SOURCE.read_text(encoding="utf-8")
        cls.style = STYLE_SOURCE.read_text(encoding="utf-8")
        cls.animation_harness = ANIMATION_HARNESS.read_text(encoding="utf-8")
        cls.animation_runner = ANIMATION_RUNNER.read_text(encoding="utf-8")
        cls.interaction_harness = INTERACTION_HARNESS.read_text(encoding="utf-8")

    def test_listens_for_both_mouse_buttons(self):
        self.assertIn("leftMouseUp", self.source)
        self.assertIn("rightMouseUp", self.source)
        self.assertIn("sendAction(on:", self.source)

    def test_press_state_is_actually_wired_not_just_declared(self):
        # BatteryIcon supports reverting to template while pressed, but that
        # branch is dead unless something sets the flag on a down event.
        self.assertIn("leftMouseDown", self.source)
        self.assertIn("rightMouseDown", self.source)
        self.assertIn("pressed = true", self.source)
        self.assertIn("pressed = false", self.source)

    def test_left_opens_popover_and_right_toggles_mode(self):
        self.assertIn("popover.toggle", self.source)
        # Right-click stays a two-state toggle even though three modes exist.
        self.assertIn("rightClickModes.next(current: EnergyModeController.current)", self.source)
        self.assertIn("base == .low ? .auto : .low", self.source)
        self.assertIn("applyEnergyMode", self.source)

    def test_right_click_write_is_async_and_restores_press_state_immediately(self):
        secondary = self.source.split("case .secondary:", 1)[1].split("\n            }", 1)[0]
        self.assertIn("pressed = false", secondary)
        self.assertIn("refreshStatusItem()", secondary)
        self.assertIn("applyEnergyMode(request.mode)", secondary)
        self.assertIn("rightClickModes.finish(generation: request.generation)", secondary)

    def test_click_acts_without_depending_on_currentEvent(self):
        # A trackpad tap is short enough that AppKit may deliver only one half
        # of the pair, and NSApp.currentEvent can already be nil by the time the
        # action runs. Requiring it silently dropped taps while a held press
        # worked.
        handler = self.source.split("@objc private func handleClick()", 1)[1].split("\n    private func", 1)[0]
        self.assertNotIn("guard let event = NSApp.currentEvent", handler)
        self.assertIn("clickRouter.intents(for: event?.type", handler)

    def test_click_feedback_does_not_redraw_the_whole_popover(self):
        # The down event delivers both `.press` and `.primary`; rebuilding all
        # five modules for each intent delayed the first visible frame.
        handler = self.source.split("@objc private func handleClick()", 1)[1].split("\n    private func", 1)[0]
        self.assertIn("refreshStatusItem()", handler)
        self.assertNotIn("refreshPresentation()", handler)

    def test_closed_popover_updates_are_cached_until_the_next_open(self):
        # The 2 s history clock continues while the popover is closed. Those
        # samples must stay current without rebuilding every hidden AppKit
        # module; the newest cached presentation is applied before show().
        update = self.popover.split("func update(snapshot:", 1)[1].split(
            "func setModeSelectHandler", 1
        )[0]
        self.assertIn("latestPresentation =", update)
        self.assertIn("guard wantsOpen || popover.isShown else { return }", update)
        opening = self.popover.split("private func open(relativeTo", 1)[1].split(
            "private func close()", 1
        )[0]
        self.assertIn("applyLatestPresentation()", opening)
        self.assertLess(opening.index("applyLatestPresentation()"),
                        opening.index("popover.show"))

    def test_identical_status_icon_visuals_reuse_the_existing_image(self):
        refresh = self.source.split("private func refreshStatusItem()", 1)[1]
        self.assertIn("BatteryIcon.renderKey", refresh)
        self.assertIn("renderedStatusIconKey", refresh)
        self.assertIn("if key != renderedStatusIconKey", refresh)

    def test_first_live_sample_is_deferred_until_after_the_opening_event(self):
        clock = self.source.split("private func startDisplayClock()", 1)[1].split(
            "private func stopDisplayClock()", 1
        )[0]
        self.assertIn("DispatchQueue.main.async", clock)

    def test_both_halves_of_a_click_do_not_act_twice(self):
        # Pairing is tracked as click-cycle state, not a time window. A window
        # let a press held past its length act twice, so the popover opened and
        # immediately closed. See tests/interaction for the executed proof.
        router = (ROOT / "MenuBar" / "ClickRouter.swift").read_text(encoding="utf-8")
        self.assertIn("pressAlreadyActed", router)
        self.assertNotIn("coalescingWindow", router)
        self.assertNotIn("now: TimeInterval", router)

    def test_popover_toggle_keys_on_intent_not_on_appkit_animation_state(self):
        # `popover.isShown` stays true for the whole close animation, so
        # branching on it swallowed a click that reopened the popover mid-fade.
        popover = (ROOT / "Popover" / "PopoverController.swift").read_text(encoding="utf-8")
        toggle = popover.split("func toggle(relativeTo", 1)[1].split("\n    private func close", 1)[0]
        self.assertNotIn("popover.isShown", toggle.split("private func open", 1)[0])
        self.assertIn("wantsOpen ? close() : open(relativeTo: button)", toggle)

    def test_a_superseded_close_does_not_tear_down_the_popover_that_replaced_it(self):
        # AppKit pairs one close with each show; counting them is exact, while
        # the state at that instant is not — isShown is briefly false in the
        # ~7ms between the old popover leaving and the new one landing.
        popover = (ROOT / "Popover" / "PopoverController.swift").read_text(encoding="utf-8")
        self.assertIn("showsRequested += 1", popover)
        self.assertIn("closesObserved += 1", popover)
        self.assertIn("guard closesObserved >= showsRequested else { return }", popover)
        # The teardown must still reset the intent, or an AppKit-initiated
        # dismissal would leave the next click reading as "close".
        teardown = popover.split("guard closesObserved >= showsRequested else { return }", 1)[1]
        self.assertIn("wantsOpen = false", teardown)

    def test_right_click_has_a_visible_confirmation(self):
        # Right-click as a direct action is undiscoverable, so it must confirm.
        self.assertIn("confirmToggle", self.source)

    def test_right_click_confirmation_honors_reduce_motion(self):
        confirmation = self.source.split("private func confirmToggle", 1)[1].split(
            "// MARK: - Clocks", 1
        )[0]
        self.assertIn("accessibilityDisplayShouldReduceMotion", confirmation)

    def test_tooltip_documents_the_right_click(self):
        self.assertIn("toolTip", self.source)
        self.assertIn("right-click", self.source)

    def test_status_item_strongly_owns_one_lazy_settings_controller(self):
        self.assertEqual(
            self.source.count("lazy var settingsWindowController = SettingsWindowController()"),
            1,
        )
        self.assertIn("popover.setSettingsHandler", self.source)
        self.assertIn("self?.presentSettingsWindow()", self.source)

    def test_quick_menu_and_command_comma_share_one_settings_target(self):
        self.assertEqual(self.source.count("@objc private func showSettings()"), 1)
        target = self.source.split("@objc private func showSettings()", 1)[1].split(
            "\n    private func", 1
        )[0]
        for operation in (
            "stopDisplayClock()",
            "popover.handleOutsideClick()",
            "DispatchQueue.main.async",
            "presentSettingsWindow()",
        ):
            self.assertIn(operation, target)
        self.assertLess(target.index("stopDisplayClock()"),
                        target.index("popover.handleOutsideClick()"))
        self.assertLess(target.index("popover.handleOutsideClick()"),
                        target.index("DispatchQueue.main.async"))
        presenter = self.source.split("private func presentSettingsWindow()", 1)[1].split(
            "\n    @objc private func", 1
        )[0]
        self.assertIn("stopDisplayClock()", presenter)
        self.assertIn("settingsWindowController.show()", presenter)
        self.assertLess(presenter.index("stopDisplayClock()"),
                        presenter.index("settingsWindowController.show()"))
        menu = self.source.split("private func installMainMenuIfNeeded()", 1)[1].split(
            "@objc private func showSettings()", 1
        )[0]
        self.assertIn('title: "Settings…"', menu)
        self.assertIn("#selector(showSettings)", menu)
        self.assertIn('keyEquivalent: ","', menu)
        self.assertIn("keyEquivalentModifierMask = [.command]", menu)
        self.assertIn('title: "Quit Wattson"', menu)
        self.assertIn("guard NSApp.mainMenu == nil", menu)

    def test_settings_command_does_not_mutate_activation_policy(self):
        settings_code = self.source.split("private func installMainMenuIfNeeded()", 1)[1]
        settings_code += self.app_delegate
        self.assertNotIn("setActivationPolicy", settings_code)

    def test_system_battery_state_has_one_authoritative_cache(self):
        self.assertNotIn("systemBatteryIconHidden: Bool?", self.source)
        self.assertNotIn("systemBatteryIconRefreshGeneration", self.source)
        self.assertIn("SystemBatteryIconController.cachedHidden", self.source)
        self.assertIn("SystemBatteryIconController.didChange", self.source)
        self.assertIn("systemBatteryIconObserver", self.source)

    def test_system_battery_observer_updates_popover_and_is_removed(self):
        observer = self.source.split("SystemBatteryIconController.didChange", 1)[1].split(
            "wakeObserver =", 1
        )[0]
        self.assertIn("queue: .main", observer)
        self.assertIn("updateSystemBatteryIconPresentation()", observer)
        teardown = self.source.split("deinit", 1)[1].split("// MARK: - Clicks", 1)[0]
        self.assertIn("systemBatteryIconObserver", teardown)
        self.assertIn("removeObserver(systemBatteryIconObserver)", teardown)

    def test_opening_refresh_publishes_through_the_core_controller(self):
        refresh = self.source.split("private func refreshSystemBatteryIconState()", 1)[1].split(
            "private func applySystemBatteryIconHidden", 1
        )[0]
        self.assertIn("SystemBatteryIconController.refreshHidden", refresh)
        self.assertIn("updateSystemBatteryIconPresentation()", refresh)
        self.assertNotIn("generation", refresh)

    def test_icon_updates_are_event_driven_not_polled(self):
        self.assertIn("IOPSNotificationCreateRunLoopSource", self.source)

    def test_wake_requests_an_immediate_fresh_sample(self):
        self.assertIn("NSWorkspace.didWakeNotification", self.source)
        wake = self.source.split("NSWorkspace.didWakeNotification", 1)[1].split(
            "startEventDrivenUpdates()", 1
        )[0]
        self.assertIn("history.reset()", wake)
        self.assertIn("refreshPresentation()", wake)
        self.assertIn("requiresFreshFollowUp: true", wake)
        self.assertIn("supersedesCurrent: true", wake)
        self.assertIn("event: .sleepWake", wake)

    def test_history_clock_is_two_seconds_and_display_clock_is_one(self):
        self.assertIn("historyInterval: TimeInterval = 2", self.source)
        self.assertIn("displayInterval: TimeInterval = 1", self.source)

    def test_sampling_timers_have_coalescing_tolerance(self):
        self.assertIn("historyTolerance: TimeInterval = 0.2", self.source)
        self.assertIn("displayTolerance: TimeInterval = 0.1", self.source)
        self.assertIn("timer.tolerance = Self.historyTolerance", self.source)
        self.assertIn("timer.tolerance = Self.displayTolerance", self.source)

    def test_periodic_ticks_coalesce_but_events_keep_one_fresh_follow_up(self):
        self.assertIn("struct SampleRequestCoalescer", self.source)
        self.assertIn("freshFollowUpRequested", self.source)
        self.assertNotIn("private var resampleRequested", self.source)
        event_updates = self.source.split("private func startEventDrivenUpdates", 1)[1].split(
            "private func startHistoryClock", 1
        )[0]
        self.assertIn("requiresFreshFollowUp: true", event_updates)
        self.assertNotIn("supersedesCurrent: true", event_updates)
        self.assertIn("event: .powerSourceTransition", event_updates)
        history_clock = self.source.split("private func startHistoryClock", 1)[1].split(
            "private func startDisplayClock", 1
        )[0]
        display_clock = self.source.split("private func startDisplayClock", 1)[1].split(
            "private func stopDisplayClock", 1
        )[0]
        self.assertNotIn("requiresFreshFollowUp: true", history_clock)
        self.assertNotIn("supersedesCurrent: true", history_clock)
        repeating_display = display_clock.split("DispatchQueue.main.async", 1)[0]
        self.assertNotIn("requiresFreshFollowUp: true", repeating_display)
        self.assertNotIn("supersedesCurrent: true", repeating_display)
        deferred_open = display_clock.split("DispatchQueue.main.async", 1)[1]
        self.assertIn("requiresFreshFollowUp: true", deferred_open)
        self.assertNotIn("supersedesCurrent: true", deferred_open)
        finish = self.source.split("private func finishSample", 1)[1].split(
            "private func refreshPresentation", 1
        )[0]
        self.assertIn("if completedRequest.publishCurrent", finish)
        follow_up = "if completedRequest.requiresFreshFollowUp"
        self.assertIn(follow_up, finish)
        self.assertLess(
            finish.index("startupAvailability.finish"), finish.index(follow_up)
        )
        self.assertIn(
            "completedRequest.recordHistory && !completedRequest.publishCurrent",
            finish,
        )

    def test_sampling_lifecycle_is_idempotent_and_cleans_up_sources(self):
        self.assertIn("guard !started else { return true }", self.source)
        self.assertIn("deinit", self.source)
        self.assertIn("historyTimer?.invalidate()", self.source)
        self.assertIn("displayTimer?.invalidate()", self.source)
        self.assertIn("CFRunLoopSourceInvalidate", self.source)
        self.assertIn("removeObserver", self.source)

    def test_sampling_sources_continue_during_menu_tracking(self):
        self.assertIn("CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)", self.source)
        self.assertEqual(self.source.count("RunLoop.main.add(timer, forMode: .common)"), 2)

    def test_unchanged_status_button_chrome_is_not_reassigned(self):
        refresh = self.source.split("private func refreshStatusItem()", 1)[1]
        self.assertIn("renderedStatusButtonPresentation", refresh)
        self.assertIn("presentation.showsPercentage != rendered?.showsPercentage", refresh)
        self.assertIn("presentation.title != rendered?.title", refresh)
        self.assertIn("presentation.alpha != rendered?.alpha", refresh)

    def test_icon_style_participates_in_the_cached_status_image_key(self):
        refresh = self.source.split("private func refreshStatusItem()", 1)[1]
        self.assertIn("let iconStyle = Settings.menuBarIconStyle", refresh)
        self.assertEqual(refresh.count("style: iconStyle"), 2)
        self.assertIn("if key != renderedStatusIconKey", refresh)

    def test_fresh_smc_power_is_read_off_main_then_applied_before_presentation(self):
        sampling = self.source.split("fileprivate func sampleNow", 1)[1].split(
            "private func finishSample", 1
        )[0]
        finish = self.source.split("private func finishSample", 1)[1].split(
            "private func refreshPresentation", 1
        )[0]
        self.assertIn("samplingQueue.async", sampling)
        self.assertLess(
            sampling.index("pendingPowerObservationEvent.merging(event)"),
            sampling.index("guard sampleRequests.request"),
        )
        self.assertLess(
            sampling.index(") else { return }"),
            sampling.index("pendingPowerObservationEvent = .normal"),
        )
        self.assertIn("powerObservationRuntime.sample", sampling)
        self.assertIn("result.visibleSnapshot", finish)
        self.assertNotIn("result.resolution", finish)
        self.assertNotIn("userVisibleEligible", finish)

    def test_display_clock_stops_when_the_popover_closes(self):
        self.assertIn("displayTimer?.invalidate()", self.source)

    def test_popover_is_transient_and_hangs_below_the_item(self):
        self.assertIn(".transient", self.popover)
        self.assertIn(".maxY", self.popover)

    def test_entrance_animation_configures_the_native_motion_on_each_open(self):
        opening = self.popover.split("private func open(relativeTo", 1)[1].split(
            "private func close()", 1
        )[0]
        self.assertIn("popover.animates = !reduceMotion", opening)

    def test_reopening_during_dismissal_does_not_replay_from_low_opacity(self):
        opening = self.popover.split("private func open(relativeTo", 1)[1].split(
            "private func close()", 1
        )[0]
        self.assertIn("let reopeningDuringDismissal = popover.isShown", opening)
        self.assertIn("if !reopeningDuringDismissal", opening)

    def test_entrance_animation_honors_reduce_motion(self):
        opening = self.popover.split("private func open(relativeTo", 1)[1].split(
            "private func close()", 1
        )[0]
        self.assertIn("let reduceMotion = Self.reducesMotion", opening)
        self.assertIn("NSWorkspace.shared.accessibilityDisplayShouldReduceMotion", self.popover)
        self.assertIn("playEntranceAnimation", opening)
        self.assertIn('CABasicAnimation(keyPath: "opacity")', self.popover)
        self.assertIn('CABasicAnimation(keyPath: "transform")', self.popover)
        self.assertIn("reduceMotion", self.popover)
        self.assertIn("reducedMotionAnimationsAreSafe", self.interaction_harness)
        self.assertIn('fade.keyPath == "opacity"', self.interaction_harness)
        self.assertIn('descriptions.count == 1', self.interaction_harness)
        self.assertIn('root:wattson.popover.entrance', self.interaction_harness)
        self.assertIn('runningModuleAnimationCountForTest == 0', self.interaction_harness)
        self.assertIn('runningInfiniteAnimationCountForTest == 0', self.interaction_harness)
        self.assertIn('group.repeatCount == 0', self.interaction_harness)
        self.assertIn('减少动态效果允许经验证的短暂透明度淡入', self.interaction_harness)
        self.assertIn('root/rogue:opacity', self.interaction_harness)

    def test_entrance_animation_uses_one_replaceable_key(self):
        normalized = self.popover.replace("Self.", "")
        self.assertIn("entranceAnimationKey", normalized)
        self.assertIn("forKey: entranceAnimationKey", normalized)
        self.assertIn("removeAnimation(forKey: entranceAnimationKey)", normalized)

    def test_debug_seam_exposes_entrance_animation_without_showing_a_window(self):
        for declaration in (
            "func playEntranceAnimationForTest(reduceMotion: Bool)",
            "func stopEntranceAnimationForTest()",
            "var entranceAnimationCountForTest: Int",
            "var entranceAnimationForTest: CAAnimation?",
        ):
            self.assertIn(declaration, self.popover)

        self.assertIn("PopoverController()", self.animation_harness)
        for forbidden in ("NSApplication.shared", "NSWindow(", "NSPanel(", ".show("):
            self.assertNotIn(forbidden, self.animation_harness)

    def test_animation_stress_replaces_twenty_thousand_times_then_removes(self):
        self.assertIn("20_000", self.animation_harness)
        self.assertIn("iteration.isMultiple(of: 2)", self.animation_harness)
        self.assertIn("entranceAnimationCountForTest == 1", self.animation_harness)
        self.assertIn("stopEntranceAnimationForTest()", self.animation_harness)
        self.assertIn("entranceAnimationCountForTest == 0", self.animation_harness)
        self.assertIn("elapsed", self.animation_harness)

    def test_animation_stress_runner_is_isolated_and_low_priority(self):
        self.assertIn("mktemp -d", self.animation_runner)
        self.assertGreaterEqual(
            self.animation_runner.count("/usr/sbin/taskpolicy -b /usr/bin/nice -n 15"), 2
        )
        self.assertIn('${1:-20000}', self.animation_runner)
        for forbidden in ("install.sh", "pkill", "killall", "/usr/bin/open"):
            self.assertNotIn(forbidden, self.animation_runner)

    def test_popover_is_360_wide(self):
        self.assertIn("static let width: CGFloat = 360", self.style)
        self.assertIn("width: PopoverStyle.width", self.popover)


if __name__ == "__main__":
    unittest.main()
