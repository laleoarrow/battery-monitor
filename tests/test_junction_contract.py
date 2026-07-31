import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Popover" / "PowerFlowLayer.swift"


class JunctionContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = SOURCE.read_text(encoding="utf-8")

    def test_shared_pipe_edges_are_tangent(self):
        for upper, lower in ((4.0, 4.0), (9.3, 12.4), (18.0, 18.0)):
            cy = 72.0
            upper_center = cy - lower / 2
            lower_center = cy + upper / 2
            self.assertAlmostEqual(
                upper_center + upper / 2,
                lower_center - lower / 2,
            )
        self.assertIn("cy - lowerThickness / 2", self.source)
        self.assertIn("cy + upperThickness / 2", self.source)

    def test_track_is_butt_capped_and_pulse_is_round_capped(self):
        self.assertIn("track.lineCap = .butt", self.source)
        self.assertIn("pulse.lineCap = .round", self.source)
        self.assertIn("pulse.mask = mask", self.source)


if __name__ == "__main__":
    unittest.main()
