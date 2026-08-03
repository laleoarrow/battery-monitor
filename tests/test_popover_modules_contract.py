import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
CONTENT = ROOT / "Popover" / "PopoverContentView.swift"
STYLE = ROOT / "Popover" / "PopoverStyle.swift"
ENCODING = ROOT / "Core" / "VisualEncoding.swift"
FLOW = ROOT / "Popover" / "PowerFlowLayer.swift"
RING = ROOT / "Popover" / "RingGaugeLayer.swift"
LANES = ROOT / "Popover" / "LaneLayer.swift"
HISTORY = ROOT / "Popover" / "HistoryLayer.swift"
POPOVER = ROOT / "Popover" / "PopoverController.swift"
STATUS = ROOT / "MenuBar" / "StatusItemController.swift"


class PopoverModulesContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.content = CONTENT.read_text(encoding="utf-8")
        cls.style = STYLE.read_text(encoding="utf-8")
        cls.encoding = ENCODING.read_text(encoding="utf-8")
        cls.flow = FLOW.read_text(encoding="utf-8")
        cls.ring = RING.read_text(encoding="utf-8")
        cls.lanes = LANES.read_text(encoding="utf-8")
        cls.history = HISTORY.read_text(encoding="utf-8")
        cls.popover = POPOVER.read_text(encoding="utf-8")
        cls.status = STATUS.read_text(encoding="utf-8")

    def test_content_contains_all_four_modules_in_fixed_order(self):
        order = [self.content.index(name) for name in ("flowView", "ringView", "laneView", "historyView")]
        self.assertEqual(order, sorted(order))

    def test_one_surface_divided_by_hairlines_not_four_cards(self):
        # Four bordered cards stack four sets of edges and paddings.
        self.assertIn("class PopoverSection", self.style)
        self.assertIn("separator", self.style)
        self.assertIn("PopoverStyle.surface", self.content)

    def test_sections_carry_no_titles(self):
        # A ring labelled "ring gauge" costs height and says nothing.
        for view in (self.ring, self.lanes):
            self.assertNotIn('"环形仪表"', view)
            self.assertNotIn('"功率泳道"', view)

    def test_numbers_use_monospaced_digits(self):
        # Tabular digits keep the readout from twitching at 1 Hz.
        self.assertIn("monospacedDigitSystemFont", self.style)

    def test_header_uses_a_compact_single_row_layout(self):
        header = self.content.split("final class PopoverHeaderView", 1)[1].split(
            "final class PopoverFooterView", 1
        )[0]
        height = float(re.search(r"preferredHeight: CGFloat = (\d+)", header).group(1))
        self.assertEqual(height, 52)
        self.assertNotIn("private let equation", header)
        self.assertNotIn("equation.frame", header)

    def test_header_only_surfaces_conservation_breaks_in_the_state(self):
        header = self.content.split("final class PopoverHeaderView", 1)[1].split(
            "final class PopoverFooterView", 1
        )[0]
        self.assertIn("abs(snapshot.conservationError) > 2", header)
        self.assertIn('String(format: "数据异常 · 偏差 %+.1f W"', header)
        self.assertIn('state.stringValue = "读取失败 · 上次数据"', header)

    def test_ring_centre_shows_charge_not_watts(self):
        # The header already owns the wattage.
        self.assertIn('percentUnit = NSTextField(labelWithString: "%")', self.ring)
        self.assertIn('percentLabel.stringValue = "\\(snapshot.percent)"', self.ring)

    def test_non_particle_motion_uses_one_power_driven_period(self):
        self.assertIn("motionPeriod: CFTimeInterval = 2.4", self.encoding)
        for module in (self.flow, self.ring, self.lanes):
            self.assertIn("VisualEncoding.motionPeriod", module)
            self.assertIn("VisualEncoding.multiplier", module)

    def test_particles_keep_their_independent_timing(self):
        particles = self.flow.split("func rebuildParticles", 1)[1].split(
            "final class PowerFlowView", 1
        )[0]
        self.assertIn("let duration = 2.4 * spread", particles)
        self.assertIn("let multiplier = CGFloat(2.4 / period)", particles)
        self.assertNotIn("VisualEncoding.motionPeriod", particles)
        self.assertIn("let particlePeriod = 2.4 / Double(motionMultiplier)", self.flow)
        self.assertIn("period: particlePeriod", self.flow)
        self.assertIn("startFlow(multiplier: motionMultiplier", self.flow)

    def test_lane_length_is_proportional_to_its_own_wattage(self):
        # Normalising against a fixed ceiling renders 108 W and 32 W at nearly
        # the same length, which states something false about the data.
        self.assertIn("max(systemWatts, batteryWatts, 0.1)", self.lanes)
        self.assertIn("fraction * Self.trackWidth", self.lanes)
        self.assertIn("motion.duration = VisualEncoding.motionPeriod", self.lanes)

    def test_lane_track_width_is_constant_not_read_from_bounds(self):
        # `update` can land before the first layout pass, and reading a
        # still-zero track width there collapses every bar to nothing.
        self.assertIn("trackWidth: CGFloat { PopoverStyle.contentWidth", self.lanes)
        self.assertNotIn("lane.track.bounds.width", self.lanes)

    def test_lane_sweep_crosses_the_entire_fill(self):
        # The pulse sits at 20% of a gradient that is twice the fill width.
        # Moving that layer by only one width leaves the pulse around the
        # middle; two widths carries it fully off the right edge before repeat.
        self.assertIn("motion.byValue = width * 2", self.lanes)

    def test_battery_lane_and_stat_follow_state_semantics(self):
        for label in ("充入电池", "电池输出", "电池补差"):
            self.assertIn(label, self.style)
        self.assertIn("batteryFlowLabel", self.lanes)
        self.assertIn("batteryFlowLabel", self.ring)

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
        self.assertIn("removeAllAnimations()", self.content)

    def test_history_is_only_recorded_by_the_history_clock(self):
        self.assertIn("sampleNow(recordHistory: true)", self.status)
        self.assertIn("sampleNow(recordHistory: false)", self.status)
        self.assertIn("if recordHistory", self.status)

    def test_status_controller_pushes_live_data_into_the_popover(self):
        self.assertIn("popover.update(", self.status)
        for field in ("snapshot:", "history:", "peak:", "degraded:"):
            self.assertIn(field, self.status)


if __name__ == "__main__":
    unittest.main()
