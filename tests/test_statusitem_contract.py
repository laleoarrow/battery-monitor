import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
STATUS_SOURCE = ROOT / "MenuBar" / "StatusItemController.swift"
POPOVER_SOURCE = ROOT / "Popover" / "PopoverController.swift"
STYLE_SOURCE = ROOT / "Popover" / "PopoverStyle.swift"


class StatusItemContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = STATUS_SOURCE.read_text(encoding="utf-8")
        cls.popover = POPOVER_SOURCE.read_text(encoding="utf-8")
        cls.style = STYLE_SOURCE.read_text(encoding="utf-8")

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
        self.assertIn("EnergyModeController.current == .low ? .auto : .low", self.source)
        self.assertIn("applyEnergyMode", self.source)

    def test_click_acts_without_depending_on_currentEvent(self):
        # A trackpad tap is short enough that AppKit may deliver only one half
        # of the pair, and NSApp.currentEvent can already be nil by the time the
        # action runs. Requiring it silently dropped taps while a held press
        # worked.
        handler = self.source.split("@objc private func handleClick()", 1)[1].split("\n    private func", 1)[0]
        self.assertNotIn("guard let event = NSApp.currentEvent", handler)
        self.assertIn("clickCoalescingWindow", handler)

    def test_both_halves_of_a_click_do_not_act_twice(self):
        self.assertIn("clickCoalescingWindow: TimeInterval", self.source)
        self.assertIn("lastClickAt", self.source)

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

    def test_popover_is_360_wide(self):
        self.assertIn("static let width: CGFloat = 360", self.style)
        self.assertIn("width: PopoverStyle.width", self.popover)


if __name__ == "__main__":
    unittest.main()
