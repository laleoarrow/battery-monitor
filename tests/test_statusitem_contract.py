import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
STATUS_SOURCE = ROOT / "MenuBar" / "StatusItemController.swift"
POPOVER_SOURCE = ROOT / "Popover" / "PopoverController.swift"
STYLE_SOURCE = ROOT / "Popover" / "PopoverStyle.swift"
ANIMATION_HARNESS = ROOT / "tests" / "animation_stress" / "main.swift"
ANIMATION_RUNNER = ROOT / "scripts" / "verify_animation_stress.sh"


class StatusItemContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = STATUS_SOURCE.read_text(encoding="utf-8")
        cls.popover = POPOVER_SOURCE.read_text(encoding="utf-8")
        cls.style = STYLE_SOURCE.read_text(encoding="utf-8")
        cls.animation_harness = ANIMATION_HARNESS.read_text(encoding="utf-8")
        cls.animation_runner = ANIMATION_RUNNER.read_text(encoding="utf-8")

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

    def test_tooltip_documents_the_right_click(self):
        self.assertIn("toolTip", self.source)
        self.assertIn("右键", self.source)

    def test_icon_updates_are_event_driven_not_polled(self):
        self.assertIn("IOPSNotificationCreateRunLoopSource", self.source)

    def test_history_clock_is_two_seconds_and_display_clock_is_one(self):
        self.assertIn("historyInterval: TimeInterval = 2", self.source)
        self.assertIn("displayInterval: TimeInterval = 1", self.source)

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
        self.assertIn("NSWorkspace.shared.accessibilityDisplayShouldReduceMotion", opening)
        self.assertIn("playEntranceAnimation", opening)
        self.assertIn('CABasicAnimation(keyPath: "opacity")', self.popover)
        self.assertIn('CABasicAnimation(keyPath: "transform")', self.popover)
        self.assertIn("reduceMotion", self.popover)

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
