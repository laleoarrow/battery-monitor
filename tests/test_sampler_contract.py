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
        self.assertIn("IORegistryEntryCreateCFProperty", self.source)
        self.assertNotIn("IORegistryEntryCreateCFProperties", self.source)
        property_reader = self.source.split("private static func batteryProperties", 1)[1].split(
            "// Values are raw", 1
        )[0]
        self.assertIn('"PowerOutDetails"', property_reader)
        for key in (
            "CurrentCapacity",
            "MaxCapacity",
            "ExternalConnected",
            "IsCharging",
            "CycleCount",
            "Temperature",
            "VirtualTemperature",
            "Voltage",
            "InstantAmperage",
            "Amperage",
            "PowerTelemetryData",
        ):
            self.assertIn(f'"{key}"', self.source)
        self.assertIn("let snapshot = resolvedSnapshot(", self.source)
        self.assertIn("resolvedBatteryPercent(", self.source)
        self.assertIn(
            'let plugged = optionalBoolValue(props["ExternalConnected"])',
            self.source,
        )
        self.assertIn(
            'optionalIntValue(props["InstantAmperage"])', self.source
        )
        self.assertIn("validBatteryCurrent(instantAmperage)", self.source)
        self.assertIn("validBatteryCurrent(amperage)", self.source)
        self.assertIn("(-100_000...100_000).contains(current)", self.source)
        self.assertIn("let fallbackBatteryW = resolvedFallbackBatteryW(", self.source)
        self.assertIn("fallbackBatteryW: fallbackBatteryW", self.source)
        self.assertNotIn("Double(amperage ?? 0)", self.source)
        self.assertIn("adapter == nil || adapter == 0", self.source)
        self.assertNotIn(
            "systemPowerIn == nil || systemPowerIn == 0", self.source
        )

    def test_never_forks_registry_or_profiler_tools(self):
        # One process spawn per second was the single largest cost in the old
        # implementation.
        self.assertNotIn("Process()", self.source)
        self.assertNotIn("ioreg", self.source)
        self.assertNotIn("system_profiler", self.source)

    def test_power_out_details_uses_only_measured_watts(self):
        parser = self.source.split("static func resolvedDeviceOutputW", 1)[1].split(
            "static func resolvedPower", 1
        )[0]
        self.assertIn('entry["Watts"]', parser)
        for unmeasured in ("PDPowermW", "FilteredPower"):
            self.assertNotIn(f'entry["{unmeasured}"]', parser)
        self.assertNotIn('entry["Configured', parser)
        self.assertIn(
            'resolvedDeviceOutputW(props["PowerOutDetails"])', self.source
        )

    def test_sign_extends_twos_complement_fields(self):
        # Negative amperage surfaces as a large unsigned value.
        self.assertIn("optionalIntValue", self.source)
        self.assertIn("Int64(Int32.max)", self.source)
        self.assertIn("Int64(UInt32.max)", self.source)
        self.assertIn("CFBooleanGetTypeID()", self.source)

    def test_property_parser_rejects_cross_hardware_invalid_inputs(self):
        harness = textwrap.dedent(
            """
            import Foundation

            func require(_ condition: @autoclosure () -> Bool, _ message: String) {
                if !condition() {
                    FileHandle.standardError.write(Data((message + "\\n").utf8))
                    exit(1)
                }
            }

            func near(_ lhs: Double, _ rhs: Double) -> Bool {
                abs(lhs - rhs) < 0.000_001
            }

            func validProps() -> [String: Any] {
                [
                    "CurrentCapacity": NSNumber(value: 67),
                    "MaxCapacity": NSNumber(value: 100),
                    "ExternalConnected": kCFBooleanTrue as Any,
                    "IsCharging": kCFBooleanFalse as Any,
                    "CycleCount": NSNumber(value: 42),
                    "Voltage": NSNumber(value: 12_000),
                    "InstantAmperage": NSNumber(value: 1_000),
                    "Amperage": NSNumber(value: 1_000),
                    "PowerTelemetryData": [
                        "SystemPowerIn": NSNumber(value: 60_000),
                        "SystemLoad": NSNumber(value: 40_000),
                        "BatteryPower": NSNumber(value: 20_000),
                    ],
                ]
            }

            require(BatterySampler.optionalIntValue(NSNumber(value: 1)) == 1,
                    "numeric NSNumber(1) remains a valid integer")
            require(BatterySampler.optionalIntValue(kCFBooleanTrue as Any) == nil,
                    "CFBoolean true cannot masquerade as integer one")
            require(BatterySampler.optionalIntValue(kCFBooleanFalse as Any) == nil,
                    "CFBoolean false cannot masquerade as integer zero")
            require(BatterySampler.optionalIntValue("12") == nil,
                    "numeric strings are not IOKit integers")
            require(BatterySampler.optionalIntValue(NSNumber(value: 12.5)) == nil,
                    "fractional numbers are not IOKit integers")
            require(BatterySampler.optionalIntValue(NSNumber(value: UInt64.max)) == -1,
                    "UInt64 two's-complement sentinel remains signed")
            require(BatterySampler.optionalIntValue(
                        NSNumber(value: UInt64.max - 3_134)
                    ) == -3_135,
                    "live UInt64 two's-complement current remains signed")

            require(BatterySampler.optionalBoolValue(kCFBooleanTrue as Any) == true,
                    "CFBoolean true remains a valid flag")
            require(BatterySampler.optionalBoolValue(NSNumber(value: 1)) == true,
                    "numeric one remains a valid flag")
            require(BatterySampler.optionalBoolValue(NSNumber(value: 0)) == false,
                    "numeric zero remains a valid flag")
            for invalidFlag: Any in ["1", NSNumber(value: -1), NSNumber(value: 2),
                                     NSNumber(value: 0.5)] {
                require(BatterySampler.optionalBoolValue(invalidFlag) == nil,
                        "unrecognized flag is rejected")
            }

            let valid = BatterySampler.resolvedSnapshot(
                from: validProps(), lowPowerMode: true
            )
            require(valid != nil, "valid hardware dictionary produces a snapshot")
            require(valid!.percent == 67 && valid!.plugged && valid!.cycleCount == 42
                        && valid!.lowPowerMode,
                    "valid identity fields are preserved")
            require(near(valid!.adapterW, 60) && near(valid!.batteryW, 20)
                        && near(valid!.systemW, 40)
                        && near(valid!.conservationError, 0),
                    "valid coherent telemetry behavior is preserved")

            for raw: Any in [
                NSNumber(value: -1), NSNumber(value: Int32.min),
                NSNumber(value: UInt32.max), NSNumber(value: 100_001),
                NSNumber(value: Int.max), NSNumber(value: 1.5),
                kCFBooleanTrue as Any,
            ] {
                var props = validProps()
                props["CycleCount"] = raw
                require(BatterySampler.resolvedSnapshot(
                            from: props, lowPowerMode: false
                        )?.cycleCount == 0,
                        "wrapped or implausible cycle count degrades to zero")
            }

            var intelCapacity = validProps()
            intelCapacity["CurrentCapacity"] = NSNumber(value: 3_500)
            intelCapacity["MaxCapacity"] = NSNumber(value: 7_000)
            require(BatterySampler.resolvedSnapshot(
                        from: intelCapacity, lowPowerMode: false
                    )?.percent == 50,
                    "Intel mAh capacity pair resolves to a percentage")
            intelCapacity["CurrentCapacity"] = NSNumber(value: 7_100)
            require(BatterySampler.resolvedSnapshot(
                        from: intelCapacity, lowPowerMode: false
                    )?.percent == 100,
                    "Intel calibration overshoot clamps to full")

            var appleSiliconCapacity = validProps()
            appleSiliconCapacity["CurrentCapacity"] = NSNumber(value: 67)
            appleSiliconCapacity["MaxCapacity"] = NSNumber(value: 100)
            require(BatterySampler.resolvedSnapshot(
                        from: appleSiliconCapacity, lowPowerMode: false
                    )?.percent == 67,
                    "Apple-silicon percentage pair remains unchanged")

            var emptyCapacity = validProps()
            emptyCapacity["CurrentCapacity"] = NSNumber(value: 0)
            emptyCapacity["MaxCapacity"] = NSNumber(value: 7_000)
            require(BatterySampler.resolvedSnapshot(
                        from: emptyCapacity, lowPowerMode: false
                    )?.percent == 0,
                    "zero current capacity is a valid empty battery")

            var missingMaximum = validProps()
            missingMaximum.removeValue(forKey: "MaxCapacity")
            require(BatterySampler.resolvedSnapshot(
                        from: missingMaximum, lowPowerMode: false
                    ) == nil,
                    "missing maximum cannot identify percentage versus Intel mAh")
            missingMaximum["CurrentCapacity"] = NSNumber(value: 0)
            require(BatterySampler.resolvedSnapshot(
                        from: missingMaximum, lowPowerMode: false
                    ) == nil,
                    "zero without a maximum has no reliable unit")
            missingMaximum["CurrentCapacity"] = NSNumber(value: 3_500)
            require(BatterySampler.resolvedSnapshot(
                        from: missingMaximum, lowPowerMode: false
                    ) == nil,
                    "missing maximum cannot guess an Intel mAh percentage")

            let invalidMaximums: [Any] = [
                kCFBooleanTrue as Any,
                NSNumber(value: 0), NSNumber(value: -1),
                NSNumber(value: 12.5), NSNumber(value: Int.max), "100",
            ]
            for raw in invalidMaximums {
                var props = validProps()
                props["MaxCapacity"] = raw
                require(BatterySampler.resolvedSnapshot(
                            from: props, lowPowerMode: false
                        ) == nil,
                        "malformed or non-positive maximum rejects the sample")
            }

            let invalidCapacities: [Any] = [
                NSNumber(value: -1), NSNumber(value: 100_001),
                NSNumber(value: Int.min), NSNumber(value: Int.max),
                kCFBooleanTrue as Any, "67",
            ]
            for raw in invalidCapacities {
                var props = validProps()
                props["CurrentCapacity"] = raw
                require(BatterySampler.resolvedSnapshot(
                            from: props, lowPowerMode: false
                        ) == nil,
                        "invalid capacity rejects the complete sample")
            }
            var percentOvershoot = validProps()
            percentOvershoot["CurrentCapacity"] = NSNumber(value: 101)
            require(BatterySampler.resolvedSnapshot(
                        from: percentOvershoot, lowPowerMode: false
                    )?.percent == 100,
                    "percentage calibration overshoot clamps to full")

            let invalidConnections: [Any] = [
                NSNumber(value: -1), NSNumber(value: 2),
                NSNumber(value: Int.min), NSNumber(value: Int.max),
                NSNumber(value: 0.5), "true",
            ]
            for raw in invalidConnections {
                var props = validProps()
                props["ExternalConnected"] = raw
                require(BatterySampler.resolvedSnapshot(
                            from: props, lowPowerMode: false
                        ) == nil,
                        "unrecognized connection flag rejects the complete sample")
            }
            var missingConnection = validProps()
            missingConnection.removeValue(forKey: "ExternalConnected")
            require(BatterySampler.resolvedSnapshot(
                        from: missingConnection, lowPowerMode: false
                    ) == nil,
                    "missing connection state rejects the complete sample")

            let partial: [String: Any] = [
                "CurrentCapacity": NSNumber(value: 50),
                "MaxCapacity": NSNumber(value: 100),
                "ExternalConnected": NSNumber(value: 0),
            ]
            let partialSnapshot = BatterySampler.resolvedSnapshot(
                from: partial, lowPowerMode: false
            )
            require(partialSnapshot != nil && partialSnapshot!.percent == 50
                        && !partialSnapshot!.plugged
                        && partialSnapshot!.adapterW == 0
                        && partialSnapshot!.batteryW == 0
                        && partialSnapshot!.systemW == 0,
                    "missing optional IOKit fields degrade independently")

            let nonNumericTelemetry = BatterySampler.parsedPowerTelemetry([
                "SystemPowerIn": "60000",
                "SystemLoad": kCFBooleanTrue as Any,
                "BatteryPower": NSNumber(value: 20_000),
            ])
            require(nonNumericTelemetry["SystemPowerIn"] == nil
                        && nonNumericTelemetry["SystemLoad"] == nil
                        && nonNumericTelemetry["BatteryPower"] == 20_000,
                    "invalid telemetry fields are omitted instead of becoming zero")

            let telemetryBoundaries = BatterySampler.parsedPowerTelemetry([
                "SystemPowerIn": NSNumber(value: 1_000_000),
                "SystemLoad": NSNumber(value: -1_000_000),
                "BatteryPower": NSNumber(value: 1_000_000),
            ])
            require(telemetryBoundaries["SystemPowerIn"] == 1_000_000
                        && telemetryBoundaries["SystemLoad"] == -1_000_000
                        && telemetryBoundaries["BatteryPower"] == 1_000_000,
                    "telemetry limit boundaries remain valid")

            for raw in [-1, -1_000_001, Int.min, 1_000_001, Int.max] {
                let parsed = BatterySampler.parsedPowerTelemetry([
                    "SystemPowerIn": NSNumber(value: raw),
                ])
                require(parsed["SystemPowerIn"] == nil,
                        "negative source sentinel and source extremes are rejected")
            }
            for key in ["SystemLoad", "BatteryPower"] {
                for raw in [-1_000_001, Int.min, 1_000_001, Int.max] {
                    let parsed = BatterySampler.parsedPowerTelemetry([
                        key: NSNumber(value: raw),
                    ])
                    require(parsed[key] == nil,
                            "signed telemetry extremes are rejected")
                }
            }

            require(BatterySampler.validBatteryVoltage(1) == 1
                        && BatterySampler.validBatteryVoltage(50_000) == 50_000,
                    "voltage boundaries remain valid")
            for raw in [0, -1, 50_001, Int.max] {
                require(BatterySampler.validBatteryVoltage(raw) == nil,
                        "voltage sentinel and extremes are rejected")
            }
            for raw: Any in [NSNumber(value: 0), NSNumber(value: -1),
                             NSNumber(value: 50_001), NSNumber(value: Int.max),
                             kCFBooleanTrue as Any, "12000"] {
                var props = validProps()
                props.removeValue(forKey: "PowerTelemetryData")
                props["IsCharging"] = kCFBooleanTrue as Any
                props["Voltage"] = raw
                let snapshot = BatterySampler.resolvedSnapshot(
                    from: props, lowPowerMode: false
                )
                require(snapshot != nil && snapshot!.adapterW == 0
                            && snapshot!.batteryW == 0
                            && snapshot!.systemW == 0
                            && snapshot!.conservationError == 0,
                        "invalid voltage cannot produce an anomalous fallback wattage")
            }

            require(BatterySampler.resolvedInstantBatteryW(
                        voltage: 10_000,
                        instantAmperage: 100_000,
                        amperage: nil
                    ) == 1_000,
                    "positive 1000 W battery boundary remains valid")
            require(BatterySampler.resolvedInstantBatteryW(
                        voltage: 10_000,
                        instantAmperage: -100_000,
                        amperage: nil
                    ) == -1_000,
                    "negative 1000 W battery boundary remains valid")
            require(BatterySampler.resolvedInstantBatteryW(
                        voltage: 10_001,
                        instantAmperage: 100_000,
                        amperage: nil
                    ) == nil,
                    "combined battery power above 1000 W is rejected")
            require(BatterySampler.resolvedFallbackBatteryW(
                        voltage: 50_000,
                        amperage: 100_000
                    ) == 0,
                    "valid individual extremes cannot create a 5000 W fallback")

            var extremeFallbackProps = validProps()
            extremeFallbackProps.removeValue(forKey: "PowerTelemetryData")
            extremeFallbackProps["IsCharging"] = kCFBooleanTrue as Any
            extremeFallbackProps["Voltage"] = NSNumber(value: 50_000)
            extremeFallbackProps["InstantAmperage"] = NSNumber(value: 100_000)
            extremeFallbackProps["Amperage"] = NSNumber(value: 100_000)
            let extremeFallback = BatterySampler.resolvedSnapshot(
                from: extremeFallbackProps, lowPowerMode: false
            )
            require(extremeFallback != nil && extremeFallback!.adapterW == 0
                        && extremeFallback!.batteryW == 0
                        && extremeFallback!.systemW == 0
                        && extremeFallback!.conservationError == 0,
                    "complete sample rejects impossible combined fallback power")

            let extreme = BatterySampler.resolvedPower(
                plugged: true,
                chargingHint: true,
                systemPowerIn: Int.max,
                systemLoad: Int.min,
                batteryPower: Int.max,
                fallbackBatteryW: 0
            )
            require(extreme.adapterW == 0 && extreme.batteryW == 0
                        && extreme.systemW == 0,
                    "direct resolver also rejects extreme telemetry")
            """
        )
        with tempfile.TemporaryDirectory() as temp:
            temp_path = pathlib.Path(temp)
            main = temp_path / "main.swift"
            binary = temp_path / "sampler-property-validation"
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

    def test_temperature_units_and_fallback_are_explicit(self):
        self.assertIn("Double(raw) / 10.0 - 273.15", self.source)
        self.assertIn("Double(raw) / 100.0", self.source)
        self.assertIn("(-100.0...150.0).contains(celsius)", self.source)
        self.assertIn('optionalIntValue(props["VirtualTemperature"])', self.source)

    def test_live_smc_branch_preserves_coherent_battery_flow_and_conservation(self):
        self.assertIn("static func resolvedLivePower(", self.source)
        self.assertIn("abs(snapshot.batteryW) <= maxBatteryPowerWatts", self.source)
        self.assertIn("max(staleBatteryW, -liveSystem)", self.source)
        self.assertIn("maxBatteryPowerWatts - liveSystem", self.source)
        self.assertIn("fresh.adapterW = liveSystem + fresh.batteryW", self.source)
        self.assertIn("min(staleBatteryW, liveAdapter)", self.source)
        self.assertIn("liveAdapter - maxBatteryPowerWatts", self.source)
        self.assertNotIn("fresh.batteryW = adapterW - systemW", self.source)
        self.assertIn("else { return snapshot }", self.source)

    def test_iokit_source_and_sink_signs_are_normalized_to_the_core_model(self):
        # Firmware can expose the same physical sample with either raw sign,
        # and IsCharging can stay true during mixed supply. Source minus sink
        # is therefore the authoritative direction when both totals exist.
        self.assertIn('telemetry["BatteryPower"]', self.source)
        self.assertIn('optionalBoolValue(props["IsCharging"])', self.source)
        self.assertIn("parsedPowerTelemetry", self.source)
        self.assertIn("maxTelemetryMilliwatts = 1_000_000", self.source)
        self.assertIn("maxBatteryVoltageMillivolts = 50_000", self.source)
        self.assertIn("let power = resolvedPower(", self.source)
        self.assertIn('systemPowerIn: telemetry["SystemPowerIn"]', self.source)
        self.assertIn('systemLoad: telemetry["SystemLoad"]', self.source)
        self.assertIn('batteryPower: telemetry["BatteryPower"]', self.source)
        self.assertIn("return (adapter, adapter - system, system)", self.source)
        self.assertIn(").map(normalizedSystemLoad)", self.source)
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
                          systemIn: Int?, load: Int?, fallback: Double = 0,
                          instant: Double? = nil) -> PowerSnapshot {
                let values = BatterySampler.resolvedPower(
                    plugged: plugged,
                    chargingHint: charging,
                    systemPowerIn: systemIn,
                    systemLoad: load,
                    batteryPower: raw,
                    fallbackBatteryW: fallback,
                    instantBatteryW: instant
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

            let signedAdapterOnlyMixed = resolved(
                nil, charging: true, plugged: true,
                systemIn: 60_000, load: nil, fallback: 12, instant: -12
            )
            require(signedAdapterOnlyMixed.adapterW == 60
                        && signedAdapterOnlyMixed.batteryW == -12
                        && signedAdapterOnlyMixed.systemW == 72
                        && signedAdapterOnlyMixed.state == .mixedSupply
                        && signedAdapterOnlyMixed.conservationError == 0,
                    "adapter-only signed current overrides stale charging hint")

            let signedAdapterOnlyCharge = resolved(
                nil, charging: false, plugged: true,
                systemIn: 60_000, load: nil, fallback: 12, instant: 12
            )
            require(signedAdapterOnlyCharge.adapterW == 60
                        && signedAdapterOnlyCharge.batteryW == 12
                        && signedAdapterOnlyCharge.systemW == 48
                        && signedAdapterOnlyCharge.state == .charging
                        && signedAdapterOnlyCharge.conservationError == 0,
                    "adapter-only signed current overrides stale discharging hint")

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

            let transitionCharge = resolved(-9_000, charging: false, plugged: true,
                                             systemIn: 0, load: 40_000,
                                             fallback: -9, instant: 24)
            require(transitionCharge.adapterW == 64
                        && transitionCharge.batteryW == 24
                        && transitionCharge.systemW == 40
                        && transitionCharge.state == .charging
                        && transitionCharge.conservationError == 0,
                    "instant positive current wins while source telemetry is zero")

            let sourceSentinel = resolved(-9_000, charging: false, plugged: true,
                                          systemIn: -1, load: 40_000,
                                          fallback: -9, instant: 24)
            require(sourceSentinel.adapterW == 64
                        && sourceSentinel.batteryW == 24
                        && sourceSentinel.systemW == 40
                        && sourceSentinel.state == .charging
                        && sourceSentinel.conservationError == 0,
                    "normalized unavailable source includes negative sentinel")

            let transitionIdle = resolved(9_000, charging: true, plugged: true,
                                           systemIn: nil, load: 40_000,
                                           fallback: 9, instant: 0)
            require(transitionIdle.adapterW == 40
                        && transitionIdle.batteryW == 0
                        && transitionIdle.systemW == 40
                        && transitionIdle.state == .pluggedIdle
                        && transitionIdle.conservationError == 0,
                    "instant zero current produces plugged idle")

            let transitionMixed = resolved(9_000, charging: true, plugged: true,
                                            systemIn: 0, load: 40_000,
                                            fallback: 9, instant: -12)
            require(transitionMixed.adapterW == 28
                        && transitionMixed.batteryW == -12
                        && transitionMixed.systemW == 40
                        && transitionMixed.state == .mixedSupply
                        && transitionMixed.conservationError == 0,
                    "signed instant current overrides stale charging hint")

            let boundedMixed = resolved(9_000, charging: true, plugged: true,
                                        systemIn: nil, load: 40_000,
                                        fallback: 9, instant: -60)
            require(boundedMixed.adapterW == 0 && boundedMixed.batteryW == -40
                        && boundedMixed.systemW == 40
                        && boundedMixed.conservationError == 0,
                    "instant battery discharge cannot exceed system load")

            let noLoadCharge = resolved(-9_000, charging: false, plugged: true,
                                        systemIn: nil, load: nil,
                                        fallback: -9, instant: 24)
            require(noLoadCharge.adapterW == 24 && noLoadCharge.batteryW == 24
                        && noLoadCharge.systemW == 0
                        && noLoadCharge.state == .charging
                        && noLoadCharge.conservationError == 0,
                    "missing load retains instant charging direction")

            let noLoadIdle = resolved(9_000, charging: true, plugged: true,
                                      systemIn: nil, load: nil,
                                      fallback: 9, instant: 0)
            require(noLoadIdle.adapterW == 0 && noLoadIdle.batteryW == 0
                        && noLoadIdle.systemW == 0
                        && noLoadIdle.state == .pluggedIdle
                        && noLoadIdle.conservationError == 0,
                    "missing load retains instant idle direction")

            let noLoadMixed = resolved(9_000, charging: true, plugged: true,
                                       systemIn: nil, load: nil,
                                       fallback: 9, instant: -12)
            require(noLoadMixed.adapterW == 0 && noLoadMixed.batteryW == -12
                        && noLoadMixed.systemW == 12
                        && noLoadMixed.state == .mixedSupply
                        && noLoadMixed.conservationError == 0,
                    "missing load retains instant mixed direction")

            let zeroLoadCharge = resolved(-9_000, charging: false, plugged: true,
                                          systemIn: 0, load: 0,
                                          fallback: -9, instant: 24)
            require(zeroLoadCharge.adapterW == 24
                        && zeroLoadCharge.batteryW == 24
                        && zeroLoadCharge.systemW == 0
                        && zeroLoadCharge.state == .charging
                        && zeroLoadCharge.conservationError == 0,
                    "zero load retains instant charging direction")

            let zeroLoadMixed = resolved(9_000, charging: true, plugged: true,
                                         systemIn: 0, load: 0,
                                         fallback: 9, instant: -12)
            require(zeroLoadMixed.adapterW == 0 && zeroLoadMixed.batteryW == -12
                        && zeroLoadMixed.systemW == 12
                        && zeroLoadMixed.state == .mixedSupply
                        && zeroLoadMixed.conservationError == 0,
                    "zero load retains instant mixed direction")

            let unpluggedOldAC = resolved(9_000, charging: true, plugged: false,
                                          systemIn: 60_000, load: 40_000,
                                          fallback: 9, instant: 24)
            require(unpluggedOldAC.adapterW == 0 && unpluggedOldAC.batteryW == -40
                        && unpluggedOldAC.systemW == 40
                        && unpluggedOldAC.state == .onBattery
                        && unpluggedOldAC.conservationError == 0,
                    "unplug ignores old AC and instant charging telemetry")

            let coherentSource = resolved(9_000, charging: false, plugged: true,
                                          systemIn: 60_000, load: 40_000,
                                          fallback: 9, instant: -12)
            require(coherentSource.adapterW == 60 && coherentSource.batteryW == 20
                        && coherentSource.systemW == 40
                        && coherentSource.state == .charging
                        && coherentSource.conservationError == 0,
                    "positive source telemetry remains authoritative")

            for (snapshot, expectedBattery, expectedAdapter) in [
                (transitionCharge, 24.0, 69.0),
                (transitionIdle, 0.0, 45.0),
                (transitionMixed, -12.0, 33.0),
                (noLoadCharge, 24.0, 69.0),
                (noLoadIdle, 0.0, 45.0),
                (noLoadMixed, -12.0, 33.0),
                (zeroLoadCharge, 24.0, 69.0),
                (zeroLoadMixed, -12.0, 33.0),
            ] {
                let live = BatterySampler.resolvedLivePower(
                    snapshot: snapshot, adapterW: 1, systemW: 45
                )
                require(live.adapterW == expectedAdapter
                            && live.batteryW == expectedBattery
                            && live.systemW == 45
                            && live.conservationError == 0,
                        "live system refresh retains instant battery branch")
            }
            require(BatterySampler.resolvedLivePower(
                        snapshot: noLoadCharge, adapterW: 1, systemW: 45
                    ).state == .charging,
                    "live load keeps transition charging state")
            require(BatterySampler.resolvedLivePower(
                        snapshot: noLoadIdle, adapterW: 1, systemW: 45
                    ).state == .pluggedIdle,
                    "live load keeps transition idle state")
            require(BatterySampler.resolvedLivePower(
                        snapshot: noLoadMixed, adapterW: 1, systemW: 45
                    ).state == .mixedSupply,
                    "live load keeps transition mixed state")

            for invalidInstant in [
                -1, Int(Int32.min), Int(Int32.max), -100_001, 100_001,
                Int.min, Int.max,
            ] {
                let fallback = BatterySampler.resolvedInstantBatteryW(
                    voltage: 12_000,
                    instantAmperage: invalidInstant,
                    amperage: -2_000
                )
                require(fallback != nil && near(fallback!, -24),
                        "invalid instant current falls back to valid Amperage")
            }
            require(BatterySampler.resolvedInstantBatteryW(
                        voltage: 12_000,
                        instantAmperage: -1,
                        amperage: Int(Int32.max)
                    ) == nil,
                    "two invalid current candidates produce nil")
            require(BatterySampler.resolvedInstantBatteryW(
                        voltage: Int.max,
                        instantAmperage: 100_000,
                        amperage: nil
                    ) == nil,
                    "extreme voltage cannot create an anomalous battery wattage")

            for invalidAmperage in [
                -1, Int(Int32.min), Int(Int32.max), -100_001, 100_001,
                Int.min, Int.max,
            ] {
                let fallback = BatterySampler.resolvedFallbackBatteryW(
                    voltage: 12_000,
                    amperage: invalidAmperage
                )
                let instant = BatterySampler.resolvedInstantBatteryW(
                    voltage: 12_000,
                    instantAmperage: nil,
                    amperage: invalidAmperage
                )
                let snapshot = resolved(
                    nil, charging: true, plugged: true,
                    systemIn: nil, load: nil,
                    fallback: fallback, instant: instant
                )
                require(snapshot.adapterW == 0 && snapshot.batteryW == 0
                            && snapshot.systemW == 0
                            && snapshot.state == .pluggedIdle
                            && snapshot.conservationError == 0,
                        "missing telemetry rejects invalid fallback Amperage")
            }
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
