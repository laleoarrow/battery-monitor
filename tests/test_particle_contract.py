import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
FLOW = ROOT / "Popover" / "PowerFlowLayer.swift"
STYLE = ROOT / "Popover" / "PopoverStyle.swift"


class ParticleContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.flow = FLOW.read_text(encoding="utf-8")
        cls.style = STYLE.read_text(encoding="utf-8")

    def test_particles_are_core_animation_driven(self):
        # Set once, then run in the render server. No per-frame timer.
        self.assertIn('CAKeyframeAnimation(keyPath: "position")', self.flow)
        self.assertNotIn("CVDisplayLink", self.flow)
        self.assertNotIn("Timer.scheduledTimer", self.flow)

    def test_particles_exist_at_every_power_level(self):
        # Not a high-power easter egg: the count floor is 2.
        self.assertIn("2 + VisualEncoding.t(total) * 6", self.flow)

    def test_cross_section_offsets_are_deterministic_and_nonzero(self):
        # All of them on the centreline reads as a conveyor belt, not a current.
        self.assertIn("thickness * 0.36", self.flow)
        self.assertIn("rng.nextUnit() * 2 - 1", self.flow)
        self.assertIn("seed: UInt64", self.flow)
        self.assertIn("struct SeededRNG", self.style)

    def test_particles_are_seated_on_the_curve_without_animation(self):
        # Relying on the keyframe animation alone leaves every dot stacked at
        # the layer origin whenever animations are off.
        self.assertIn("geometry.point(at:", self.flow)
        self.assertIn("dot.position = CGPoint", self.flow)

    def test_high_power_strengthens_particles_only(self):
        self.assertIn("VisualEncoding.over", self.flow)
        self.assertIn("saturationParticle", self.flow)
        self.assertIn("0xDBEAFF", self.style)
        # Tried and rejected: at 360pt wide these outweigh the pipe itself.
        for excluded in ("halo", "filament", "bolt.fill", "lightning"):
            self.assertNotIn(excluded, self.flow)


if __name__ == "__main__":
    unittest.main()
