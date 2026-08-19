import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Popover" / "PowerFlowLayer.swift"


class TopologyContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = SOURCE.read_text(encoding="utf-8")

    def test_has_two_layouts_and_all_four_power_states(self):
        self.assertIn("case adapterLed", self.source)
        self.assertIn("case batteryLed", self.source)
        for state in ("case .charging", "case .pluggedIdle", "case .onBattery", "case .mixedSupply"):
            self.assertIn(state, self.source)

    def test_mixed_supply_keeps_adapter_blue_and_battery_orange(self):
        # Orange carries information here: the charger cannot keep up and the
        # battery is draining while plugged in.
        mixed = self.source.split("case .mixedSupply:", 1)[1]
        self.assertIn("tint: PopoverStyle.blue", mixed)
        self.assertIn("tint: PopoverStyle.amber", mixed)

    def test_keeps_exactly_two_pipe_bundles_and_three_node_views(self):
        # Constant layer and view counts are what make every transition a pure
        # property interpolation instead of an add/remove.
        self.assertIn("(0..<2).map", self.source)
        self.assertIn("[adapterNode, batteryNode, systemNode]", self.source)

    def test_layout_positions_depend_only_on_layout(self):
        # Filling the gap left by a disconnected adapter puts the battery box
        # straight on top of the adapter's caption.
        self.assertIn("private func positions(for layout: FlowLayout)", self.source)
        self.assertIn("Self.adapterLedPositions", self.source)
        self.assertIn("Self.batteryLedPositions", self.source)

    def test_every_pipe_uses_the_same_cubic_shape(self):
        # Equal control-point counts are required for CAShapeLayer to
        # interpolate between topologies rather than snap.
        self.assertIn("path.move(to: start)", self.source)
        self.assertIn("path.addCurve(to: end, control1: control1, control2: control2)", self.source)
        self.assertEqual(self.source.count("PipeGeometry(start:"), 2)

    def test_plot_is_flipped(self):
        # Node and pipe coordinates are written with y growing downward. A
        # plain NSView mirrors the whole diagram vertically.
        self.assertIn("override var isFlipped: Bool { true }", self.source)
        self.assertIn("class FlippedPlot", self.source)

    def test_idle_battery_keeps_a_static_dashed_link(self):
        # The battery is still connected at full charge; drawing nothing would
        # claim otherwise.
        self.assertIn("idleConnection", self.source)
        self.assertIn("lineDashPattern = [3, 6]", self.source)

    def test_all_three_nodes_share_one_symbol_scale_and_visual_weight(self):
        # Adapter, System, and Battery are peers in the same 36-point wells.
        # A smaller unconfigured CPU symbol makes the three-node diagram look
        # like it mixes two unrelated icon families.
        self.assertIn(
            "NSImage.SymbolConfiguration(pointSize: 21, weight: .regular)",
            self.source,
        )
        self.assertIn("icon.frame = box.bounds", self.source)
        self.assertIn("icon.imageScaling = .scaleProportionallyDown", self.source)
        self.assertIn("withSymbolConfiguration(Self.powerIconConfiguration)", self.source)
        self.assertNotIn("usesEmphasizedPowerIcon", self.source)
        self.assertNotIn("? .scaleProportionallyDown", self.source)
        self.assertIn("restoredAdapterRotation", self.source)
        self.assertIn("rotatedAdapterImage(addsSlash:", self.source)
        self.assertIn("rotation: restoredAdapterRotation", self.source)
        self.assertIn("context.rotate(by: rotation)", self.source)
        self.assertIn("restoredChargingBatteryImage", self.source)
        self.assertIn("chargingBatteryImage()", self.source)
        self.assertIn("private static let restoredSystemImage = systemChipImage()", self.source)
        self.assertIn('case "cpu":', self.source)
        self.assertIn("return restoredSystemImage", self.source)
        self.assertIn("private static func systemChipImage()", self.source)
        self.assertIn("private static let nodeIconStrokeWidth: CGFloat = 1.6", self.source)
        self.assertIn("shell.lineWidth = nodeIconStrokeWidth", self.source)
        self.assertIn("chip.lineWidth = nodeIconStrokeWidth", self.source)


if __name__ == "__main__":
    unittest.main()
