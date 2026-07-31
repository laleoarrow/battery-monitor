import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
HISTORY_SOURCE = ROOT / "Core" / "PowerHistory.swift"


class PowerHistoryContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = HISTORY_SOURCE.read_text(encoding="utf-8")

    def test_capacity_is_sixty_samples(self):
        self.assertIn("capacity: Int = 60", self.source)

    def test_is_a_ring_buffer_not_an_unbounded_array(self):
        self.assertIn("%", self.source)
        self.assertIn("writeIndex", self.source)

    def test_exposes_samples_in_chronological_order(self):
        self.assertIn("var samples: [Double]", self.source)

    def test_exposes_peak_for_the_chart_scale(self):
        self.assertIn("var peak: Double", self.source)


if __name__ == "__main__":
    unittest.main()
