import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
ENCODING_SOURCE = ROOT / "Core" / "VisualEncoding.swift"


def constant(source, name):
    match = re.search(rf"static let {name}: CGFloat = ([\d.]+)", source)
    assert match is not None, f"{name} not found"
    return float(match.group(1))


class SizeInvariantContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = ENCODING_SOURCE.read_text(encoding="utf-8")

    def test_two_max_pipes_exactly_fill_a_node(self):
        # A node takes at most two pipes, so this makes overflow impossible
        # rather than merely unlikely.
        thick_max = constant(self.source, "thickMin") + constant(self.source, "thickSpan")
        self.assertEqual(2 * thick_max, constant(self.source, "nodeSize"))

    def test_saturation_point_is_one_hundred_watts(self):
        self.assertEqual(constant(self.source, "wRef"), 100.0)

    def test_curve_is_compressive(self):
        exponent = constant(self.source, "exponent")
        self.assertLess(exponent, 1.0)
        self.assertEqual(exponent, 0.65)

    def test_speed_ratio_caps_at_three_point_four(self):
        self.assertEqual(constant(self.source, "speedRatio"), 3.4)

    def test_thickness_uses_per_pipe_watts_and_multiplier_uses_total(self):
        self.assertIn("func thickness(_ watts: Double)", self.source)
        self.assertIn("func multiplier(_ totalInputW: Double)", self.source)


if __name__ == "__main__":
    unittest.main()
