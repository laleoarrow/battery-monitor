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
            self.assertNotIn('"Ring Gauge"', view)
            self.assertNotIn('"Power Lanes"', view)

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
        self.assertIn('String(format: "Data Issue · Imbalance %+.1f W"', header)
        self.assertIn('state.stringValue = "Read Failed · Last Reading"', header)

    def test_ring_centre_shows_charge_not_watts(self):
        # The header already owns the wattage.
        self.assertIn('percentUnit = NSTextField(labelWithString: "%")', self.ring)
        self.assertIn('percentLabel.stringValue = "\\(snapshot.percent)"', self.ring)

    def test_ring_reuses_cycle_count_slot_for_measured_device_output(self):
        self.assertIn("for _ in 0..<4", self.ring)
        self.assertIn("if let deviceOutputW = snapshot.coherentDeviceOutputW", self.ring)
        self.assertIn('captions[3].stringValue = "Device Output"', self.ring)
        self.assertIn("values[3].stringValue = PopoverStyle.watts(deviceOutputW)", self.ring)
        self.assertIn('captions[3].stringValue = "Cycle Count"', self.ring)
        self.assertIn('values[3].setAccessibilityLabel("Cycle Count")', self.ring)
        self.assertIn("captions[3].cell?.setAccessibilityElement(false)", self.ring)
        self.assertIn("values[3].setAccessibilityElement(true)", self.ring)
        self.assertNotIn("captions[4]", self.ring)
        self.assertNotIn("values[4]", self.ring)

    def test_ring_height_remains_fixed_at_138_points(self):
        plot_height = float(
            re.search(r"plotHeight: CGFloat = (\d+)", self.ring).group(1)
        )
        section_padding = float(
            re.search(r"sectionPadding: CGFloat = (\d+)", self.style).group(1)
        )
        self.assertIn(
            "preferredHeight: CGFloat = plotHeight + PopoverStyle.sectionPadding * 2",
            self.ring,
        )
        self.assertEqual(plot_height + section_padding * 2, 138)

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
        for label in ("To Battery", "Battery Output", "Battery Assist"):
            self.assertIn(label, self.style)
        self.assertIn("batteryFlowLabel", self.lanes)
        self.assertIn("batteryFlowLabel", self.ring)

    def test_mixed_supply_lanes_and_history_keep_the_blue_instrument_color(self):
        self.assertIn("snapshot.state == .mixedSupply", self.lanes)
        self.assertIn("? PopoverStyle.blue", self.lanes)
        history_update = self.content.split("let historyColor", 1)[1].split(
            "updateFooter()", 1
        )[0]
        self.assertIn("snapshot.state == .mixedSupply", history_update)
        self.assertIn("? PopoverStyle.blue", history_update)

    def test_history_draws_the_two_minute_samples_without_animation(self):
        self.assertIn("samples: [Double]", self.history)
        self.assertIn("CATransaction.setDisableActions(true)", self.history)

    def test_history_skips_rebuilding_an_identical_path_and_color(self):
        self.assertIn("lastSamples", self.history)
        self.assertIn("lastPeak", self.history)
        self.assertIn("lastColor", self.history)
        self.assertIn("samples == lastSamples", self.history)
        self.assertIn("lastColor.isEqual(color)", self.history)

    def test_module_visibility_uses_the_shared_typed_settings_store(self):
        self.assertIn("typealias PopoverModule = Settings.Module", self.content)
        self.assertIn("Settings.isModuleVisible", self.content)
        self.assertIn("Settings.setModule", self.content)
        self.assertNotIn("UserDefaults.standard", self.content)

    def test_transient_close_stops_all_animations_and_the_display_clock(self):
        self.assertIn("NSPopoverDelegate", self.popover)
        self.assertIn("func popoverDidClose", self.popover)
        self.assertIn("setAnimationsEnabled(false)", self.popover)
        self.assertIn("stopDisplayClock()", self.status)
        self.assertIn("removeAllAnimations()", self.content)

    def test_reduce_motion_stops_content_motion_and_tracks_runtime_changes(self):
        opening = self.popover.split("private func open(relativeTo", 1)[1].split(
            "private func applyLatestPresentation", 1
        )[0]
        self.assertIn("let reduceMotion = Self.reducesMotion", opening)
        self.assertIn("content.setAnimationsEnabled(!reduceMotion)", opening)
        self.assertIn(
            "NSWorkspace.accessibilityDisplayOptionsDidChangeNotification",
            self.popover,
        )
        refresh = self.popover.split("private func refreshDisplayOptions()", 1)[1].split(
            "private func applyLatestPresentation", 1
        )[0]
        self.assertIn("guard wantsOpen else { return }", refresh)
        self.assertIn("content.setAnimationsEnabled(!reduceMotion)", refresh)
        self.assertIn("if reduceMotion { stopEntranceAnimation() }", refresh)

    def test_full_battery_breathing_stops_and_stays_stopped_when_hidden(self):
        idle = self.flow.split("case .pluggedIdle:", 1)[1].split(
            "case .onBattery:", 1
        )[0]
        self.assertIn("setBreathing(animationsEnabled", idle)
        disabling = self.flow.split("func setAnimationsEnabled(_ enabled: Bool)", 1)[1]
        self.assertIn("stopBreathing", disabling)

    def test_ring_paths_are_rebuilt_by_layout_not_telemetry(self):
        layout = self.ring.split("override func layout()", 1)[1].split(
            "private func rebuildPaths", 1
        )[0]
        update = self.ring.split("func update(snapshot:", 1)[1].split(
            "private func applyRotation", 1
        )[0]
        self.assertIn("rebuildPaths()", layout)
        self.assertNotIn("rebuildPaths()", update)

    def test_history_intent_is_carried_through_sample_availability(self):
        self.assertIn("sampleNow(recordHistory: true)", self.status)
        self.assertIn("sampleNow(recordHistory: false)", self.status)
        self.assertIn("recordHistory: completedRequest.recordHistory", self.status)
        self.assertIn("if availabilityPlan.shouldRecordHistory", self.status)

    def test_status_controller_pushes_live_data_into_the_popover(self):
        self.assertIn("popover.update(", self.status)
        for field in ("snapshot:", "history:", "peak:", "degraded:"):
            self.assertIn(field, self.status)


if __name__ == "__main__":
    unittest.main()
