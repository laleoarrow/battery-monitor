import pathlib
import subprocess
import tempfile
import textwrap
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

    def test_iokit_source_and_sink_signs_are_normalized_to_the_core_model(self):
        # Firmware can expose the same physical sample with either raw sign,
        # and IsCharging can stay true during mixed supply. Source minus sink
        # is therefore the authoritative direction when both totals exist.
        self.assertIn('telemetry["BatteryPower"]', self.source)
        self.assertIn('boolValue(props["IsCharging"])', self.source)
        self.assertIn("let power = resolvedPower(", self.source)
        self.assertIn('systemPowerIn: telemetry["SystemPowerIn"]', self.source)
        self.assertIn('systemLoad: telemetry["SystemLoad"]', self.source)
        self.assertIn('batteryPower: telemetry["BatteryPower"]', self.source)
        self.assertIn("return (adapter, adapter - system, system)", self.source)
        self.assertIn("systemLoad.map(normalizedSystemLoad)", self.source)
        self.assertNotIn("plugged ? 0", self.source)

    def test_numeric_resolution_uses_conservation_before_unreliable_flags(self):
        harness = textwrap.dedent(
            """
            import Foundation

            func require(_ condition: @autoclosure () -> Bool, _ message: String) {
                if !condition() {
                    FileHandle.standardError.write(Data((message + "\\n").utf8))
                    exit(1)
                }
            }

            func resolved(_ raw: Int?, charging: Bool, plugged: Bool,
                          systemIn: Int?, load: Int?, fallback: Double = 0) -> PowerSnapshot {
                let values = BatterySampler.resolvedPower(
                    plugged: plugged,
                    chargingHint: charging,
                    systemPowerIn: systemIn,
                    systemLoad: load,
                    batteryPower: raw,
                    fallbackBatteryW: fallback
                )
                return PowerSnapshot(
                    plugged: plugged,
                    adapterW: values.adapterW,
                    batteryW: values.batteryW,
                    systemW: values.systemW
                )
            }

            func near(_ lhs: Double, _ rhs: Double) -> Bool { abs(lhs - rhs) < 0.000_001 }

            let liveMixed = resolved(-31_784, charging: true, plugged: true,
                                     systemIn: 85_695, load: 117_479)
            require(near(liveMixed.adapterW, 85.695)
                        && near(liveMixed.batteryW, -31.784)
                        && near(liveMixed.systemW, 117.479),
                    "live mixed tuple")
            require(liveMixed.state == .mixedSupply
                        && near(liveMixed.conservationError, 0),
                    "mixed supply overrides stale IsCharging")

            let charging = resolved(20_000, charging: false, plugged: true,
                                    systemIn: 50_000, load: 30_000)
            require(charging.batteryW == 20 && charging.state == .charging
                        && charging.conservationError == 0,
                    "charging follows source minus sink")

            let idle = resolved(-20_000, charging: true, plugged: true,
                                systemIn: 32_000, load: 32_000)
            require(idle.batteryW == 0 && idle.state == .pluggedIdle
                        && idle.conservationError == 0,
                    "equal source and sink is plugged idle")

            let batteryOnly = resolved(30_000, charging: true, plugged: false,
                                       systemIn: 99_000, load: -30_000)
            require(batteryOnly.adapterW == 0 && batteryOnly.batteryW == -30
                        && batteryOnly.systemW == 30 && batteryOnly.state == .onBattery
                        && batteryOnly.conservationError == 0,
                    "battery-only ignores stale source, flag, and raw signs")

            let adapterOnlyCharge = resolved(-20_000, charging: true, plugged: true,
                                             systemIn: 50_000, load: nil)
            require(adapterOnlyCharge.adapterW == 50 && adapterOnlyCharge.batteryW == 20
                        && adapterOnlyCharge.systemW == 30
                        && adapterOnlyCharge.conservationError == 0,
                    "adapter-only charging fallback")

            let adapterOnlyMixed = resolved(10_000, charging: false, plugged: true,
                                            systemIn: 50_000, load: nil)
            require(adapterOnlyMixed.adapterW == 50 && adapterOnlyMixed.batteryW == -10
                        && adapterOnlyMixed.systemW == 60
                        && adapterOnlyMixed.conservationError == 0,
                    "adapter-only mixed fallback")

            let loadOnlyCharge = resolved(-20_000, charging: true, plugged: true,
                                          systemIn: nil, load: 30_000)
            require(loadOnlyCharge.adapterW == 50 && loadOnlyCharge.batteryW == 20
                        && loadOnlyCharge.systemW == 30
                        && loadOnlyCharge.conservationError == 0,
                    "load-only charging fallback")

            let loadOnlyMixed = resolved(10_000, charging: false, plugged: true,
                                         systemIn: nil, load: 60_000)
            require(loadOnlyMixed.adapterW == 50 && loadOnlyMixed.batteryW == -10
                        && loadOnlyMixed.systemW == 60
                        && loadOnlyMixed.conservationError == 0,
                    "load-only mixed fallback")

            let legacyCharge = resolved(nil, charging: true, plugged: true,
                                        systemIn: nil, load: nil, fallback: 12)
            require(legacyCharge.adapterW == 12 && legacyCharge.batteryW == 12
                        && legacyCharge.systemW == 0
                        && legacyCharge.conservationError == 0,
                    "legacy V×A charging fallback stays conservative")

            let zero = resolved(0, charging: false, plugged: false,
                                systemIn: nil, load: nil)
            require(zero.batteryW.sign == .plus && zero.conservationError == 0,
                    "zero stays positive")
            require(BatterySampler.normalizedSystemLoad(30_000) == 30, "positive load")
            require(BatterySampler.normalizedSystemLoad(-30_000) == 30, "negative load")
            """
        )
        with tempfile.TemporaryDirectory() as temp:
            temp_path = pathlib.Path(temp)
            main = temp_path / "main.swift"
            binary = temp_path / "sampler-normalization"
            main.write_text(harness, encoding="utf-8")
            subprocess.run(
                [
                    "xcrun",
                    "swiftc",
                    str(ROOT / "Core" / "PowerSnapshot.swift"),
                    str(SAMPLER_SOURCE),
                    str(main),
                    "-framework",
                    "IOKit",
                    "-o",
                    str(binary),
                ],
                check=True,
                capture_output=True,
                text=True,
            )
            subprocess.run([str(binary)], check=True, capture_output=True, text=True)

    def test_returns_snapshot_type_from_core(self):
        self.assertIn("-> PowerSnapshot?", self.source)


if __name__ == "__main__":
    unittest.main()
