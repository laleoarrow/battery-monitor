import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SNAPSHOT_SOURCE = ROOT / "Core" / "PowerSnapshot.swift"


class PowerModelContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = SNAPSHOT_SOURCE.read_text(encoding="utf-8")

    def test_uses_signed_battery_power_not_separate_charge_discharge(self):
        self.assertIn("var batteryW: Double", self.source)
        self.assertNotIn("dischargeW", self.source)
        self.assertNotIn("chargeW", self.source)

    def test_declares_four_power_states(self):
        for case in ("charging", "pluggedIdle", "onBattery", "mixedSupply"):
            self.assertIn(f"case {case}", self.source)

    def test_epsilon_is_three_tenths_watt(self):
        self.assertIn("static let epsilon: Double = 0.3", self.source)

    def test_total_input_sums_adapter_and_battery_output(self):
        self.assertIn("adapterW + max(-batteryW, 0)", self.source)

    def test_conservation_error_is_exposed_for_assertions(self):
        self.assertIn("var conservationError: Double", self.source)

    def test_plugged_does_not_force_battery_power_to_zero(self):
        # The old model hardcoded discharge to 0 while plugged, which made
        # mixed supply unrepresentable. That shape must never come back.
        self.assertNotIn("plugged ? 0", self.source)


if __name__ == "__main__":
    unittest.main()
