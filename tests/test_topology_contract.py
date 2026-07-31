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
        for state in (".charging", ".pluggedIdle", ".onBattery", ".mixedSupply"):
            self.assertIn(state, self.source)

    def test_mixed_supply_keeps_adapter_blue_and_battery_orange(self):
        self.assertIn("adapterNode.setTint(.systemBlue)", self.source)
        self.assertIn("batteryNode.setTint(.systemOrange)", self.source)
        self.assertIn("systemNode.setTint(.labelColor)", self.source)

    def test_keeps_exactly_two_pipe_bundles_and_three_node_views(self):
        self.assertIn("(0..<2).map", self.source)
        self.assertIn("[adapterNode, batteryNode, systemNode]", self.source)

    def test_layout_positions_depend_only_on_layout(self):
        self.assertIn("private func positions(for layout: FlowLayout)", self.source)
        self.assertIn("switch layout", self.source)
        self.assertIn("Self.adapterLedPositions", self.source)
        self.assertIn("Self.batteryLedPositions", self.source)

    def test_every_pipe_path_uses_the_same_cubic_shape(self):
        self.assertIn("path.move(to: start)", self.source)
        self.assertIn(
            "path.addCurve(to: end, control1: control1, control2: control2)",
            self.source,
        )


if __name__ == "__main__":
    unittest.main()
