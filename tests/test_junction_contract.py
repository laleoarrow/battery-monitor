import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Popover" / "PowerFlowLayer.swift"


class JunctionContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = SOURCE.read_text(encoding="utf-8")

    def test_shared_pipe_edges_are_tangent(self):
        # Two pipes leaving one node must share an edge, so a split reads as one
        # stream dividing rather than two separate sockets.
        for upper, lower in [(12.4, 9.3), (18.0, 4.0), (6.0, 6.0)]:
            upper_bottom = (-lower / 2) + upper / 2
            lower_top = (upper / 2) - lower / 2
            self.assertAlmostEqual(upper_bottom, lower_top)
        self.assertIn("cy - lowerThickness / 2", self.source)
        self.assertIn("cy + upperThickness / 2", self.source)

    def test_trough_is_butt_capped_and_pulse_is_round_capped(self):
        # Butt keeps the seam flush under the node; round gives each travelling
        # pulse its capsule shape.
        self.assertIn("trough.lineCap = .butt", self.source)
        self.assertIn("pulse.lineCap = .round", self.source)

    def test_pipe_ends_are_tucked_under_the_node_boxes(self):
        # 40 + 18 - 4 and 288 - 18 + 4: four points inside each 36pt box.
        self.assertIn("startX: CGFloat = 53", self.source)
        self.assertIn("endX: CGFloat = 275", self.source)

    def test_run_is_faded_at_both_ends(self):
        self.assertIn("container.mask", self.source)
        self.assertIn("fade.locations", self.source)

    def test_geometry_is_recomputed_once_bounds_are_real(self):
        # Anything derived from bounds is nonsense when `update` lands before
        # the first layout pass — the mask collapses and the pipes vanish.
        layout_body = self.source.split("override func layout()", 1)[1].split("private func layoutMode", 1)[0]
        self.assertIn("update(snapshot: latest, animated: false)", layout_body)


if __name__ == "__main__":
    unittest.main()
