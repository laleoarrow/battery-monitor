import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Popover" / "PowerFlowLayer.swift"


class JunctionContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = SOURCE.read_text(encoding="utf-8")
        cls.scene = (ROOT / "Popover" / "PowerFlowScene.swift").read_text(encoding="utf-8")

    def test_shared_pipe_edges_are_tangent(self):
        # Two pipes leaving one node must share an edge, so a split reads as one
        # stream dividing rather than two separate sockets.
        for upper, lower in [(12.4, 9.3), (18.0, 4.0), (6.0, 6.0)]:
            upper_bottom = (-lower / 2) + upper / 2
            lower_top = (upper / 2) - lower / 2
            self.assertAlmostEqual(upper_bottom, lower_top)
        self.assertIn("var edge = center - widths.reduce(0, +) / 2", self.scene)
        self.assertIn("edge += width", self.scene)

    def test_trough_is_butt_capped_and_flow_is_round_capped(self):
        # Butt keeps the seam flush under the node; round gives the travelling
        # light its capsule ends.
        self.assertIn("trough.lineCap = .butt", self.source)
        self.assertIn("flowMask.lineCap = .round", self.source)

    def test_pipe_ends_are_tucked_under_the_node_boxes(self):
        # 40 + 18 - 5 and 288 - 18 + 5: five points inside each 36pt box.
        self.assertIn("point(nodes[index].x + 13, nodes[index].y)", self.scene)
        self.assertIn("point(nodes[nodeIndex].x - 13, nodes[nodeIndex].y)", self.scene)
        self.assertIn("PipeGeometry(start: point(53, startY)", self.scene)
        self.assertIn("end: point(275, endY)", self.scene)

    def test_mixed_ribbons_clip_join_seams_without_fading_node_ends(self):
        self.assertIn("self.clipMask.path = CGPath(rect: clip, transform: nil)", self.source)
        self.assertIn("self.container.mask = self.clipMask", self.source)
        self.assertIn("ribbon.closeSubpath()", self.source)
        self.assertIn("self.trough.fillColor = taper == nil ? nil", self.source)
        self.assertNotIn("CAGradientLayer()", self.source.split("private let clipMask", 1)[1].split("init()", 1)[0])

    def test_mixed_theme_exposes_its_common_coordinate_field(self):
        self.assertIn("centeredTheme", self.source)
        self.assertIn("centeredGradientPeakXForTest", self.source)
        self.assertIn("mixedGradientPeakXForTest", self.source)

    def test_light_sweeps_the_full_width_without_a_seam(self):
        # Twice the width, shifted by exactly one width, loops with no jump.
        self.assertIn("width: bounds.width * 2", self.source)
        self.assertIn("drift.byValue = width", self.source)

    def test_light_pattern_is_periodic_across_the_loop(self):
        # The gradient is shifted by exactly one view width, which is half its
        # own span, so the pattern must repeat with period 0.5. The first
        # version did not: alpha differed by 0.14 across the wrap and showed as
        # a seam once per cycle.
        import re
        block = self.source.split("gradient.locations = [", 1)[1].split("]", 1)[0]
        locations = [float(x) for x in re.findall(r"[\d.]+", block)]
        colours = self.source.split("let clear = color.withAlphaComponent(0).cgColor", 1)[1].split("self.gradient.colors = [", 1)[1].split("]", 1)[0]
        names = [n.strip() for n in colours.replace("\n", "").split(",") if n.strip()]
        alpha = {"clear": 0.0, "soft": 0.30, "core": 1.0}
        values = [alpha[n] for n in names]
        self.assertEqual(len(values), len(locations))

        def at(f):
            if f <= locations[0]:
                return values[0]
            for i in range(1, len(locations)):
                if f <= locations[i]:
                    span = locations[i] - locations[i - 1]
                    u = 0 if span == 0 else (f - locations[i - 1]) / span
                    return values[i - 1] + (values[i] - values[i - 1]) * u
            return values[-1]

        worst = max(abs(at(f / 1000) - at(f / 1000 + 0.5)) for f in range(501))
        self.assertLess(worst, 0.001, f"pattern is not periodic; worst gap {worst:.3f}")

    def test_geometry_is_recomputed_once_bounds_are_real(self):
        # Anything derived from bounds is nonsense when `update` lands before
        # the first layout pass — the mask collapses and the pipes vanish.
        layout_body = self.source.split("override func layout()", 1)[1].split("private func layoutMode", 1)[0]
        self.assertIn("update(snapshot: latest, animated: false)", layout_body)


if __name__ == "__main__":
    unittest.main()
