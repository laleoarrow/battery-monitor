import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SAMPLER_SOURCE = ROOT / "Core" / "BatterySampler.swift"


class SamplerContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = SAMPLER_SOURCE.read_text(encoding="utf-8")

    def test_reads_iokit_directly(self):
        self.assertIn('IOServiceMatching("AppleSmartBattery")', self.source)
        self.assertIn("IORegistryEntryCreateCFProperties", self.source)

    def test_never_forks_ioreg(self):
        # One process spawn per second was the single largest cost in the old
        # implementation.
        self.assertNotIn("Process()", self.source)
        self.assertNotIn("ioreg", self.source)

    def test_sign_extends_twos_complement_fields(self):
        # Negative amperage surfaces as a large unsigned value.
        self.assertIn("Int64(Int32.max)", self.source)
        self.assertIn("Int64(UInt32.max)", self.source)

    def test_battery_power_keeps_its_sign(self):
        self.assertIn('telemetry["BatteryPower"]', self.source)
        self.assertNotIn("plugged ? 0", self.source)

    def test_returns_snapshot_type_from_core(self):
        self.assertIn("-> PowerSnapshot?", self.source)


if __name__ == "__main__":
    unittest.main()
