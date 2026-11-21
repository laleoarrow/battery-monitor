import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Popover" / "PowerFlowLayer.swift"


class TopologyContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = SOURCE.read_text(encoding="utf-8")
        cls.scene = (ROOT / "Popover" / "PowerFlowScene.swift").read_text(encoding="utf-8")

    def test_has_existing_and_usb_aware_layouts(self):
        for layout in ("adapterLed", "batteryLed", "batteryOutputSplit",
                       "adapterOutputSplit", "mixedOutputSplit"):
            self.assertIn("case " + layout, self.source)

    def test_device_split_accepts_connection_hint_but_power_requires_measurement(self):
        split_gate = self.scene.split("static func make(snapshot:", 1)[1].split(
            "let nodes:", 1)[0]
        self.assertIn("snapshot.coherentDeviceOutputW", split_gate)
        self.assertIn("$0 > 0", split_gate)
        self.assertIn("measuredOutput != nil || snapshot.hasConnectedUSBDevice", split_gate)
        self.assertIn("let loads = snapshot.batteryW < -PowerSnapshot.epsilon", self.scene)
        self.assertIn("? [snapshot.systemW - output, 0, output] : [0, 0, 0]", self.scene)
        self.assertNotIn("$0 > PowerSnapshot.epsilon", split_gate)

    def test_usb_is_a_peer_node_without_an_inline_duplicate(self):
        self.assertIn("private let deviceNode = FlowNodeView()", self.source)
        self.assertIn("[adapterNode, batteryNode, systemNode, deviceNode]", self.source)
        self.assertNotIn("pluggedDeviceOutputReadout", self.source)
        self.assertNotIn("deviceOutputReadoutSlotHeight", self.source)
        self.assertIn("static let plotHeight: CGFloat = 224", self.source)
        self.assertIn("static let preferredHeight: CGFloat = plotHeight", self.source)
        self.assertIn("node.setCompact(scene.nodeCompact[index])", self.source)

    def test_each_condition_has_one_theme(self):
        palette = self.source.split("private func conditionColor", 1)[1].split(
            "private func watts", 1)[0]
        self.assertIn("snapshot.plugged, snapshot.adapterW > 0", palette)
        self.assertIn("PopoverStyle.neutral", palette)
        self.assertIn("PopoverStyle.green : PopoverStyle.blue", palette)
        self.assertNotIn("PopoverStyle.amber", self.source)

    def test_device_output_uses_the_shared_vector_icon(self):
        artwork = (ROOT / "Popover" / "PowerIconView.swift").read_text()
        self.assertIn('symbol == "device.output.port"', artwork)
        self.assertIn('return DeviceOutputIcon.image(', artwork)
        self.assertIn('symbol: "device.output.port"', self.source)
        self.assertNotIn("deviceOutputPortTemplateImage", self.source)
        self.assertNotIn("base64Encoded:", self.source)

    def test_layout_keeps_explicit_peer_positions_and_fixed_node_ends(self):
        self.assertIn("private func applyPositions(_ scene: PowerFlowScene)", self.source)
        self.assertIn("nodes = [point(40, 90), point(288, 129), point(288, 51)", self.scene)
        self.assertIn("nodes = [point(40, 51), point(40, 129), point(288, 90)", self.scene)
        self.assertIn("path.move(to: start)", self.source)
        self.assertIn("path.addCurve(to: end, control1: control1, control2: control2)", self.source)
        self.assertIn("jointWidth", self.source)
        self.assertIn("twoInTwoOut ? 0.68 : 1", self.scene)
        self.assertIn("layout == .mixedOutputSplit ? 146 : 53", self.scene)
        self.assertIn("layout == .mixedOutputSplit ? 182 : jointX", self.scene)

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

    def test_all_nodes_share_one_symbol_scale_and_visual_weight(self):
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
        self.assertIn("private let icon = PowerIconImageView()", self.source)
        self.assertIn("icon.configurePowerIcon", self.source)
        self.assertIn("side: 32, inset: 4", self.source)
        self.assertIn("PowerIconImageView.image(for: symbol)", self.source)
        artwork = (ROOT / "Popover" / "PowerIconView.swift").read_text()
        for symbol in ("cpu", "powerplug", "powerplug.slash", "battery.100.bolt"):
            self.assertIn('case "' + symbol + '":', artwork)
        self.assertIn("PopoverStyle.neutral.usingColorSpace(.sRGB)", artwork)
        self.assertIn("accent.usingColorSpace(.sRGB)", artwork)


if __name__ == "__main__":
    unittest.main()
