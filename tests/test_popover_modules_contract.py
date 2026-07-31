import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
POPOVER = ROOT / "Popover" / "PopoverController.swift"
CONTENT = ROOT / "Popover" / "PopoverContentView.swift"
RING = ROOT / "Popover" / "RingGaugeLayer.swift"
LANES = ROOT / "Popover" / "LaneLayer.swift"
HISTORY = ROOT / "Popover" / "HistoryLayer.swift"
STATUS = ROOT / "MenuBar" / "StatusItemController.swift"


class PopoverModulesContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.popover = POPOVER.read_text(encoding="utf-8")
        cls.content = CONTENT.read_text(encoding="utf-8")
        cls.ring = RING.read_text(encoding="utf-8")
        cls.lanes = LANES.read_text(encoding="utf-8")
        cls.history = HISTORY.read_text(encoding="utf-8")
        cls.status = STATUS.read_text(encoding="utf-8")

    def test_content_contains_all_four_modules_in_fixed_order(self):
        order = [
            self.content.index("powerFlowView"),
            self.content.index("ringGaugeView"),
            self.content.index("laneView"),
            self.content.index("historyView"),
        ]
        self.assertEqual(order, sorted(order))

    def test_numbers_use_monospaced_digits_and_conservation_is_visible(self):
        self.assertIn("monospacedDigitSystemFont", self.content)
        self.assertIn("conservationError", self.content)
        self.assertIn("abs(snapshot.conservationError) > 2", self.content)

    def test_ring_and_lanes_follow_state_semantics(self):
        self.assertIn('"%"', self.ring)
        self.assertIn("rotation.duration = 5.0", self.ring)
        self.assertIn("setAnimationSpeed(rotatingArc", self.ring)
        self.assertIn("rotatingArc.anchorPoint", self.ring)
        self.assertIn("rotatingArc.position = center", self.ring)
        for label in ("充入电池", "电池输出", "电池补差"):
            self.assertIn(label, self.lanes + self.ring)
        self.assertIn("snapshot.state == .mixedSupply ? .systemBlue : color", self.ring)
        self.assertIn("snapshot.state == .mixedSupply ? .systemBlue : color", self.lanes)
        self.assertIn("motion.duration = 2.4", self.lanes)
        self.assertIn("setAnimationSpeed(sweep", self.lanes)

    def test_history_draws_the_two_minute_samples_without_animation(self):
        self.assertIn("samples: [Double]", self.history)
        self.assertIn("CATransaction.setDisableActions(true)", self.history)

    def test_module_visibility_defaults_on_and_is_persisted(self):
        self.assertIn("UserDefaults.standard", self.content)
        self.assertIn("register(defaults:", self.content)

    def test_transient_close_stops_all_animations_and_the_display_clock(self):
        self.assertIn("NSPopoverDelegate", self.popover)
        self.assertIn("func popoverDidClose", self.popover)
        self.assertIn("setAnimationsEnabled(false)", self.popover)
        self.assertIn("stopDisplayClock()", self.status)
        self.assertIn("removeAllAnimations()", self.content + self.ring + self.lanes)

    def test_history_is_only_recorded_by_the_history_clock(self):
        self.assertIn("sampleNow(recordHistory: true)", self.status)
        self.assertIn("sampleNow(recordHistory: false)", self.status)
        self.assertIn("if recordHistory", self.status)

    def test_status_controller_pushes_live_data_into_the_popover(self):
        self.assertIn("popover.update(", self.status)
        for field in ("snapshot:", "history:", "degraded:"):
            self.assertIn(field, self.status)


if __name__ == "__main__":
    unittest.main()
