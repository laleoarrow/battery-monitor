import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Popover" / "PowerFlowLayer.swift"


class ParticleContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = SOURCE.read_text(encoding="utf-8")

    def test_particles_are_core_animation_driven(self):
        self.assertIn("CAEmitterLayer", self.source)
        self.assertIn("CAKeyframeAnimation(keyPath: \"position\")", self.source)

    def test_cross_section_offsets_are_deterministic_and_nonzero(self):
        self.assertIn("particleSeed: UInt64", self.source)
        self.assertIn("thickness * 0.36", self.source)
        self.assertIn("rng.nextUnit() * 2 - 1", self.source)

    def test_high_power_strengthens_particles_only(self):
        self.assertIn("VisualEncoding.over", self.source)
        self.assertIn("0xDBEAFF", self.source)
        for excluded in ("ambientGlow", "electricArc", "lightningGlyph"):
            self.assertNotIn(excluded, self.source)


if __name__ == "__main__":
    unittest.main()
