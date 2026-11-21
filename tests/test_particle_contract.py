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
        cls.fusion = (ROOT / "Popover" / "EnergyFlowParticleLayer.swift").read_text(encoding="utf-8")

    def test_resting_particles_are_core_animation_driven(self):
        # Resting motion remains in the render server. The structural morph
        # alone owns a short-lived geometry timer and cancels it on settlement.
        self.assertIn('CAKeyframeAnimation(keyPath: "position")', self.flow)
        for source in (self.flow, self.fusion):
            self.assertNotIn("CVDisplayLink", source)
            self.assertNotIn("Timer.scheduledTimer", source)
        self.assertIn('CAKeyframeAnimation(keyPath: "contents")', self.fusion)
        self.assertIn("transitionDuration: CFTimeInterval = 0.32", self.flow)
        self.assertIn("if progress >= 1", self.flow)
        cancel = self.flow.split("private func cancelMorph()", 1)[1].split("\n    }", 1)[0]
        self.assertIn("stopMorphTimer()", cancel)
        stop = self.flow.split("private func stopMorphTimer()", 1)[1].split("\n    }", 1)[0]
        self.assertIn("morphTimer?.invalidate(); morphTimer = nil", stop)

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
        for excluded in ("filament", "bolt.fill", "lightning"):
            self.assertNotIn(excluded, self.flow)


    def test_pool_guard_covers_everything_it_is_built_from(self):
        # Guarding on the count alone let particles keep whatever they were born
        # with: reopening the popover left them frozen, and a topology change
        # left them riding the previous curve.
        guard = self.flow.split("guard wanted != existingCount", 1)[1].split("else {", 1)[0]
        for term in ("particlesAreHot", "particlesAreAnimating", "particleTopology"):
            self.assertIn(term, guard)

    def test_pool_guard_holds_no_continuous_quantity(self):
        # Whatever the quantisation, a continuously drifting reading oscillates
        # across its own boundary and the pool churns at 1 Hz. Keying on
        # thickness rebuilt on 95% of samples; keying on the curve's
        # coordinates did the same, because tangency derives them from
        # thickness. Topology is discrete.
        guard = self.flow.split("guard wanted != existingCount", 1)[1].split("else {", 1)[0]
        for continuous in ("thickness", "geometry.start", "geometry.end"):
            self.assertNotIn(continuous, guard)

    def test_particle_count_has_hysteresis(self):
        # The count is a rounded function of a drifting reading, so it flips
        # back and forth at a boundary. One spark either way is invisible.
        self.assertIn("abs(requested - existingCount) >= 2", self.flow)

    def test_hot_style_has_hysteresis_at_the_saturation_boundary(self):
        # 99.9/100.1 W telemetry noise must not rebuild the entire pool and its
        # animations once per second.
        self.assertIn("particlesStayHotAbove", self.flow)
        self.assertIn("? snapshot.totalInputW >= Self.particlesStayHotAbove", self.flow)

    def test_stopping_flow_records_that_particles_stopped(self):
        # Stripping the animations without updating the bookkeeping made the
        # pool believe it was still animating, so the next rebuild was skipped.
        body = self.flow.split("func stopFlow(", 1)[1].split("\n    }", 1)[0]
        self.assertIn("removeAllAnimations", body)
        self.assertIn("particlesAreAnimating = false", body)


if __name__ == "__main__":
    unittest.main()
