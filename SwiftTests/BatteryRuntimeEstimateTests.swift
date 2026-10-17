import XCTest
@testable import Wattson

final class BatteryRuntimeEstimateTests: XCTestCase {
    func testSelectsInternalBatteryInsteadOfUPS() {
        for charging in [false, true] {
            var ups = powerSource(charging: charging, minutes: 999)
            ups["Type"] = "UPS"
            let internalBattery = powerSource(charging: charging, minutes: 125)
            XCTAssertEqual(BatteryRuntimeEstimate.estimate(from: [ups, internalBattery]),
                           charging ? .charging(125) : .remaining(125))
            XCTAssertNil(BatteryRuntimeEstimate.estimate(from: [ups]))
        }
    }

    func testRequiresPresentInternalBatteryAndKnownPowerDirection() {
        let invalidFields: [(String, Any?)] = [
            ("Type", nil), ("Type", "UPS"),
            ("Is Present", nil), ("Is Present", false), ("Is Present", "true"),
            ("Power Source State", nil), ("Power Source State", "Unknown"),
            ("Is Charging", nil), ("Is Charging", "false"), ("Is Charging", 2),
        ]
        for charging in [false, true] {
            for (key, value) in invalidFields {
                var source = powerSource(charging: charging, minutes: 125)
                source[key] = value
                XCTAssertNil(BatteryRuntimeEstimate.estimate(from: [source]),
                             "\(key)=\(String(describing: value))")
            }
        }
        XCTAssertNil(BatteryRuntimeEstimate.estimate(from: []))
    }

    func testRejectsContradictoryChargingStates() {
        var source = powerSource(charging: false, minutes: 125)
        source["Is Charging"] = true
        XCTAssertNil(BatteryRuntimeEstimate.estimate(from: [source]))
        source = powerSource(charging: true, minutes: 125)
        source["Is Charged"] = true
        XCTAssertNil(BatteryRuntimeEstimate.estimate(from: [source]))
        source = powerSource(charging: false, minutes: 125)
        source["Is Charged"] = true
        XCTAssertEqual(BatteryRuntimeEstimate.estimate(from: [source]), .remaining(nil))
        source["Time to Empty"] = -1
        XCTAssertEqual(BatteryRuntimeEstimate.estimate(from: [source]), .remaining(nil))
    }

    func testUsesOnlyTheEstimateForTheCurrentDirection() {
        var battery = powerSource(charging: false, minutes: 125)
        battery["Time to Full Charge"] = 999
        XCTAssertEqual(BatteryRuntimeEstimate.estimate(from: [battery]), .remaining(125))
        var charging = powerSource(charging: true, minutes: 42)
        charging["Time to Empty"] = 999
        XCTAssertEqual(BatteryRuntimeEstimate.estimate(from: [charging]), .charging(42))
    }

    func testUnknownNegativeMissingAndMalformedMinutesPreserveKnownDirection() {
        let invalid: [Any?] = [
            nil, -1, -2, -10, true, 1.0, 1.5, "120", Double.nan, Double.infinity,
            NSNumber(value: UInt64.max), NSNumber(value: Int64(Int32.max) + 1),
        ]
        for charging in [false, true] {
            for value in invalid {
                XCTAssertEqual(BatteryRuntimeEstimate.estimate(from: [
                    powerSource(charging: charging, minutes: value),
                ]), charging ? .charging(nil) : .remaining(nil),
                "minutes=\(String(describing: value))")
            }
        }
    }

    func testZeroAndLargestSupportedMinutesAreValidInEitherDirection() {
        for minutes in [0, Int(Int32.max)] {
            XCTAssertEqual(BatteryRuntimeEstimate.estimate(from: [
                powerSource(charging: false, minutes: minutes),
            ]), .remaining(minutes))
            XCTAssertEqual(BatteryRuntimeEstimate.estimate(from: [
                powerSource(charging: true, minutes: minutes),
            ]), .charging(minutes))
        }
    }

    func testExternalPowerUsesChargedFlagInsteadOfPercentOrStaleMinutes() {
        var source = powerSource(charging: true, minutes: 125)
        source["Is Charging"] = false
        source["Current Capacity"] = 100
        source["Max Capacity"] = 100
        source["Time to Empty"] = 999
        for charged: Any? in [nil, false, "true"] {
            source["Is Charged"] = charged
            XCTAssertEqual(BatteryRuntimeEstimate.estimate(from: [source]), .notCharging)
        }
        source["Is Charged"] = true
        source["Current Capacity"] = 99
        XCTAssertEqual(BatteryRuntimeEstimate.estimate(from: [source]), .full)
    }

    func testApplyingReadsOnceAndReplacesEachPreviousDirection() {
        var snapshot = PowerSnapshot(percent: 80, batteryW: -12, batteryTimeEstimate: .remaining(125))
        var reads = 0
        for (plugged, watts, estimate): (Bool, Double, BatteryTimeEstimate) in [
            (true, 12, .charging(42)), (true, 0, .full), (true, 0, .notCharging),
            (false, -12, .remaining(125)), (false, -12, .remaining(nil)),
            (true, 12, .charging(nil)),
        ] {
            snapshot.plugged = plugged
            snapshot.batteryW = watts
            snapshot = BatteryRuntimeEstimate.applying(to: snapshot, readEstimate: {
                reads += 1
                return estimate
            })
            XCTAssertEqual(snapshot.batteryTimeEstimate, estimate)
            XCTAssertEqual(snapshot.plugged, plugged)
            XCTAssertEqual(snapshot.batteryW, watts)
        }
        XCTAssertEqual(reads, 6)
    }

    func testReverseDirectionRaceClearsPreviousEstimate() {
        let onBattery = PowerSnapshot(batteryTimeEstimate: .remaining(125))
        for estimate: BatteryTimeEstimate in [.charging(42), .charging(nil), .full, .notCharging] {
            XCTAssertNil(BatteryRuntimeEstimate.applying(to: onBattery, readEstimate: { estimate })
                .batteryTimeEstimate)
        }
        for watts in [-12.0, 0, 12] {
            let external = PowerSnapshot(plugged: true, batteryW: watts, batteryTimeEstimate: .charging(42))
            XCTAssertNil(BatteryRuntimeEstimate.applying(to: external, readEstimate: { .remaining(125) })
                .batteryTimeEstimate)
        }
    }

    func testUnknownFreshStateClearsAnyPreviousEstimate() {
        for previous: BatteryTimeEstimate in [.remaining(125), .charging(42), .full, .notCharging] {
            let snapshot = PowerSnapshot(batteryTimeEstimate: previous)
            XCTAssertNil(BatteryRuntimeEstimate.applying(to: snapshot, readEstimate: { nil })
                .batteryTimeEstimate)
        }
    }

    func testInvalidInjectedMinutesClearNumberWithoutLosingKnownDirection() {
        for minutes: Int? in [nil, -1, -2, Int(Int32.max) + 1] {
            let battery = PowerSnapshot(batteryTimeEstimate: .remaining(125))
            XCTAssertEqual(BatteryRuntimeEstimate.applying(to: battery, readEstimate: { .remaining(minutes) })
                .batteryTimeEstimate, .remaining(nil))
            let external = PowerSnapshot(plugged: true, batteryTimeEstimate: .charging(42))
            XCTAssertEqual(BatteryRuntimeEstimate.applying(to: external, readEstimate: { .charging(minutes) })
                .batteryTimeEstimate, .charging(nil))
        }
    }

    func testNearFullChargingBelowPowerEpsilonRetainsIOPSEstimate() {
        let snapshot = PowerSnapshot(percent: 100, plugged: true, adapterW: 12.1,
                                     batteryW: 0.1, systemW: 12, batteryTimeEstimate: .full)
        XCTAssertEqual(snapshot.state, .pluggedIdle)
        let updated = BatteryRuntimeEstimate.applying(to: snapshot, readEstimate: { .charging(8) })
        XCTAssertEqual(updated.batteryTimeEstimate, .charging(8))
        XCTAssertEqual(updated.batteryW, 0.1)
        XCTAssertEqual(updated.adapterW, 12.1)
        XCTAssertEqual(updated.systemW, 12)
        XCTAssertEqual(updated.percent, 100)
    }

    func testMixedSupplyNeverShowsAChargeETAOrFullState() {
        let snapshot = PowerSnapshot(percent: 100, plugged: true, batteryW: -12)
        for estimate: BatteryTimeEstimate in [.charging(42), .charging(nil), .full, .notCharging] {
            XCTAssertEqual(BatteryRuntimeEstimate.applying(to: snapshot, readEstimate: { estimate })
                .batteryTimeEstimate, .notCharging)
        }
        XCTAssertNil(BatteryRuntimeEstimate.applying(to: snapshot, readEstimate: { .remaining(125) })
            .batteryTimeEstimate)
    }

    func testLowBatteryAndLowPowerDoNotInventAnEstimateMultiplier() {
        let snapshot = PowerSnapshot(percent: 5, batteryW: -8, lowPowerMode: true)
        XCTAssertEqual(BatteryRuntimeEstimate.applying(to: snapshot, readEstimate: { .remaining(17) })
            .batteryTimeEstimate, .remaining(17))
    }

    func testPurePropertiesSamplingDoesNotPopulateAnExternalEstimate() {
        guard case let .snapshot(snapshot) = BatterySampler.sampleResult(
            from: batteryProperties(), lowPowerMode: false
        ) else { return XCTFail("Expected valid battery properties") }
        XCTAssertNil(snapshot.batteryTimeEstimate)
    }

    func testRuntimeReaderReadsOncePerValidSampleIncludingExternalPower() {
        let backend = RuntimeEstimateBatteryBackend(properties: batteryProperties())
        var reads = 0
        var freshEstimate: BatteryTimeEstimate? = .remaining(125)
        let reader = AppleSmartBatteryPowerObservationReader(
            backend: backend, lowPowerMode: { false },
            batteryTimeEstimate: { reads += 1; return freshEstimate }
        )
        for (plugged, charging, current, estimate): (Bool, Bool, Int, BatteryTimeEstimate?) in [
            (false, false, -1_000, .remaining(125)),
            (true, true, 1_000, .charging(42)),
            (true, true, 10, .charging(8)),
            (true, false, 0, .full),
            (true, false, 0, .notCharging),
            (true, true, 1_000, .charging(nil)),
            (false, false, -1_000, nil),
        ] {
            backend.properties["ExternalConnected"] = plugged
            backend.properties["IsCharging"] = charging
            backend.properties["InstantAmperage"] = current
            freshEstimate = estimate
            XCTAssertEqual(reader.readRuntimeSample().visibleSnapshot?.batteryTimeEstimate,
                           estimate ?? .remaining(nil))
        }
        XCTAssertEqual(reads, 7)
        XCTAssertEqual(backend.reads, 7)
    }

    func testRuntimeReaderSkipsEstimateWhenBatterySnapshotIsUnavailable() {
        let backend = RuntimeEstimateBatteryBackend(properties: [:])
        var reads = 0
        let reader = AppleSmartBatteryPowerObservationReader(
            backend: backend, lowPowerMode: { false },
            batteryTimeEstimate: { reads += 1; return .remaining(125) }
        )
        XCTAssertNil(reader.readRuntimeSample().visibleSnapshot)
        backend.properties = batteryProperties()
        backend.servicePresent = false
        XCTAssertNil(reader.readRuntimeSample().visibleSnapshot)
        XCTAssertEqual(reads, 0)
    }

    private func powerSource(charging: Bool, minutes: Any?) -> [String: Any] {
        var source: [String: Any] = [
            "Type": "InternalBattery", "Is Present": true,
            "Power Source State": charging ? "AC Power" : "Battery Power",
            "Is Charging": charging,
        ]
        source[charging ? "Time to Full Charge" : "Time to Empty"] = minutes
        return source
    }

    private func batteryProperties() -> [String: Any] {
        ["CurrentCapacity": 80, "MaxCapacity": 100,
         "ExternalConnected": false, "IsCharging": false,
         "Voltage": 12_000, "InstantAmperage": -1_000]
    }
}

private final class RuntimeEstimateBatteryBackend: AppleSmartBatteryPowerRawSnapshotReading {
    var properties: [String: Any]
    var servicePresent = true
    private(set) var reads = 0

    init(properties: [String: Any]) { self.properties = properties }

    func readAllowlistedProperties(_ keys: [String]) -> AppleSmartBatteryPowerRawSnapshot {
        reads += 1
        return AppleSmartBatteryPowerRawSnapshot(
            servicePresent: servicePresent,
            properties: properties.filter { keys.contains($0.key) }
        )
    }
}

final class BatteryTimeFallbackTests: XCTestCase {
    private let second: UInt64 = 1_000_000_000

    private func properties(charging: Bool = false) -> [String: Any] {
        ["ExternalConnected": charging, "IsCharging": charging, "FullyCharged": false,
         "CurrentCapacity": 80, "MaxCapacity": 100,
         "AppleRawCurrentCapacity": 6_000, "AppleRawMaxCapacity": 8_000,
         "Amperage": charging ? 2_000 : -2_000,
         "InstantAmperage": charging ? 2_000 : -2_000, "Voltage": 12_000]
    }

    private func sample(
        _ tracker: inout BatteryTimeFallback, _ props: [String: Any],
        at seconds: UInt64, system: BatteryTimeEstimate? = nil,
        snapshot: PowerSnapshot? = nil
    ) -> PowerSnapshot {
        let plugged = BatterySampler.optionalBoolValue(props["ExternalConnected"]) ?? false
        return tracker.applying(
            to: snapshot ?? PowerSnapshot(plugged: plugged, batteryW: plugged ? 24 : -24),
            properties: props, systemEstimate: system, atNanoseconds: seconds * second
        )
    }

    private func settled(
        _ tracker: inout BatteryTimeFallback, _ props: [String: Any],
        system: BatteryTimeEstimate? = nil, through end: UInt64 = 60
    ) -> PowerSnapshot {
        var result = PowerSnapshot()
        for time in 0...end { result = sample(&tracker, props, at: time, system: system) }
        return result
    }

    func testSystemIsImmediateAndWinsOverBothFallbacks() {
        var tracker = BatteryTimeFallback()
        var props = properties()
        props["AvgTimeToEmpty"] = 19
        let result = sample(&tracker, props, at: 0, system: .remaining(125))
        XCTAssertEqual(result.batteryTimeEstimate, .remaining(125))
        XCTAssertEqual(result.batteryTimeEstimateSource, .system)
        XCTAssertEqual(settled(&tracker, props, system: .remaining(125)).batteryTimeEstimate, .remaining(125))
        let fallback = sample(&tracker, props, at: 61, system: .remaining(nil))
        XCTAssertEqual(fallback.batteryTimeEstimate, .remaining(19))
        XCTAssertEqual(fallback.batteryTimeEstimateSource, .batteryGauge)
    }

    func testGaugeRequiresSixtySecondsAndKeepsDirectionAndZero() {
        for charging in [false, true] {
            for minutes in [0, 19, 65_534] {
                var tracker = BatteryTimeFallback()
                var props = properties(charging: charging)
                props[charging ? "AvgTimeToFull" : "AvgTimeToEmpty"] = minutes
                let pending = settled(&tracker, props, through: 59)
                XCTAssertEqual(pending.batteryTimeEstimate, charging ? .charging(nil) : .remaining(nil))
                let result = sample(&tracker, props, at: 60)
                XCTAssertEqual(result.batteryTimeEstimate, charging ? .charging(minutes) : .remaining(minutes))
                XCTAssertEqual(result.batteryTimeEstimateSource, .batteryGauge)
            }
        }
    }

    func testMalformedOrSentinelGaugeTimesEndWaitingWithoutInventingChargeFormula() {
        for value: Any in [-1, 65_535, 65_536, true, 19.0, "19", NSNumber(value: UInt64.max)] {
            var tracker = BatteryTimeFallback()
            var props = properties(charging: true)
            props["AvgTimeToFull"] = value
            XCTAssertNil(settled(&tracker, props, system: .charging(nil)).batteryTimeEstimate)
        }
    }

    func testGaugeRejectsExplicitOppositeOrMalformedCurrentButAcceptsMissingCurrent() {
        for charging in [false, true] {
            for bad: Any in [charging ? -100 : 100, "0", true, 0.0, -1, 100_001] {
                var tracker = BatteryTimeFallback()
                var props = properties(charging: charging)
                props[charging ? "AvgTimeToFull" : "AvgTimeToEmpty"] = 19
                props["Amperage"] = bad
                XCTAssertNil(settled(&tracker, props).batteryTimeEstimate)
            }
            var tracker = BatteryTimeFallback()
            var props = properties(charging: charging)
            props["Amperage"] = nil
            props["InstantAmperage"] = nil
            props[charging ? "AvgTimeToFull" : "AvgTimeToEmpty"] = 19
            XCTAssertEqual(settled(&tracker, props).batteryTimeEstimate, charging ? .charging(19) : .remaining(19))
        }
    }

    func testObservedDischargeUsesRawMahAndSmoothedNegativeMa() {
        for (capacity, current, minutes) in [(6_000, -2_000, 180), (6_000, -4_000, 90), (3_000, -2_000, 90)] {
            var tracker = BatteryTimeFallback()
            var props = properties()
            props["AppleRawCurrentCapacity"] = capacity
            props["Amperage"] = current
            props["InstantAmperage"] = current
            let result = settled(&tracker, props)
            XCTAssertEqual(result.batteryTimeEstimate, .remaining(minutes))
            XCTAssertEqual(result.batteryTimeEstimateSource, .observedDischarge)
        }
    }

    func testSingleCurrentSpikeDoesNotHalveRemainingTime() {
        var tracker = BatteryTimeFallback()
        var props = properties()
        XCTAssertEqual(settled(&tracker, props).batteryTimeEstimate, .remaining(180))
        props["Amperage"] = -4_000
        props["InstantAmperage"] = -4_000
        XCTAssertEqual(sample(&tracker, props, at: 61).batteryTimeEstimate, .remaining(175))
        var result = PowerSnapshot()
        for time: UInt64 in 62...361 { result = sample(&tracker, props, at: time) }
        XCTAssertEqual(result.batteryTimeEstimate, .remaining(90))
    }

    func testLowPowerDoesNotMultiplyTheEstimateAndShortValuesUseMinuteResolution() {
        var tracker = BatteryTimeFallback()
        var props = properties()
        props["AppleRawCurrentCapacity"] = 100
        _ = settled(&tracker, props)
        let snapshot = PowerSnapshot(percent: 2, batteryW: -24, lowPowerMode: true)
        XCTAssertEqual(sample(&tracker, props, at: 61, snapshot: snapshot).batteryTimeEstimate, .remaining(3))
        props["AppleRawCurrentCapacity"] = 1
        XCTAssertEqual(sample(&tracker, props, at: 62, snapshot: snapshot).batteryTimeEstimate, .remaining(1))
    }

    func testPercentageCapacityAndInvalidRawPairsCannotEnterFormula() {
        for invalid: [String: Any] in [
            ["AppleRawCurrentCapacity": NSNull()], ["AppleRawMaxCapacity": NSNull()],
            ["AppleRawCurrentCapacity": 8_001], ["AppleRawMaxCapacity": 100_001],
            ["AppleRawCurrentCapacity": -1], ["AppleRawCurrentCapacity": true],
            ["AppleRawMaxCapacity": 0], ["AppleRawCurrentCapacity": 6_000.0],
        ] {
            var tracker = BatteryTimeFallback()
            var props = properties()
            props.merge(invalid) { _, new in new }
            XCTAssertNil(settled(&tracker, props).batteryTimeEstimate)
        }
    }

    func testInvalidOrContradictoryCurrentCannotEnterFormulaAndWaitIsBounded() {
        for value: Any in [0, -1, -10, 2_000, -100_001, true, -2_000.0, "-2000"] {
            var tracker = BatteryTimeFallback()
            var props = properties()
            props["Amperage"] = value
            XCTAssertNil(settled(&tracker, props).batteryTimeEstimate)
            XCTAssertNil(sample(&tracker, props, at: 61).batteryTimeEstimate)
        }
        var tracker = BatteryTimeFallback()
        var props = properties()
        props["InstantAmperage"] = 2000
        XCTAssertNil(settled(&tracker, props).batteryTimeEstimate)
    }

    func testUnsignedTwosComplementAndMissingAverageCurrentAreSupported() {
        for average: Any? in [NSNumber(value: UInt32(bitPattern: -2_000)), NSNumber(value: UInt64(bitPattern: -2_000)), nil] {
            var tracker = BatteryTimeFallback()
            var props = properties()
            props["Amperage"] = average
            XCTAssertEqual(settled(&tracker, props).batteryTimeEstimate, .remaining(180))
        }
    }

    func testMissingDataCanRecoverWithoutRestartingDirectionWait() {
        var tracker = BatteryTimeFallback()
        var props = properties(charging: true)
        XCTAssertNil(settled(&tracker, props, system: .charging(nil)).batteryTimeEstimate)
        props["AvgTimeToFull"] = 19
        XCTAssertEqual(sample(&tracker, props, at: 61, system: .charging(nil)).batteryTimeEstimate, .charging(19))
        props["AvgTimeToFull"] = nil
        XCTAssertNil(sample(&tracker, props, at: 62, system: .charging(nil)).batteryTimeEstimate)
    }

    func testInvalidCurrentDiscardsFormulaHistoryButNotBoundedWaiting() {
        var tracker = BatteryTimeFallback()
        var props = properties()
        _ = settled(&tracker, props)
        props["Amperage"] = 0
        XCTAssertNil(sample(&tracker, props, at: 61).batteryTimeEstimate)
        props["Amperage"] = -2_000
        for time: UInt64 in 62...121 {
            XCTAssertEqual(sample(&tracker, props, at: time).batteryTimeEstimate, .remaining(nil))
        }
        XCTAssertEqual(sample(&tracker, props, at: 122).batteryTimeEstimate, .remaining(180))
    }

    func testDirectionChangeClockRollbackGapAndResetRequireNewSettlingWindow() {
        for restart: UInt64 in [40, 71] {
            var tracker = BatteryTimeFallback()
            let props = properties()
            _ = settled(&tracker, props)
            XCTAssertEqual(sample(&tracker, props, at: restart).batteryTimeEstimate, .remaining(nil))
        }
        var tracker = BatteryTimeFallback()
        _ = settled(&tracker, properties())
        tracker.reset()
        XCTAssertEqual(sample(&tracker, properties(), at: 61).batteryTimeEstimate, .remaining(nil))
        var charging = properties(charging: true)
        charging["AvgTimeToFull"] = 19
        XCTAssertEqual(sample(&tracker, charging, at: 62).batteryTimeEstimate, .charging(nil))
    }

    func testOppositeIOPSDirectionCannotBeCombinedWithRawFallback() {
        for system: BatteryTimeEstimate in [.charging(nil), .charging(19), .full, .notCharging] {
            var tracker = BatteryTimeFallback()
            XCTAssertNil(settled(&tracker, properties(), system: system).batteryTimeEstimate)
        }
    }

    func testFullBatteryUnplugStartsCalculationThenUsesFreshDischarge() {
        var tracker = BatteryTimeFallback()
        var props = properties()
        props["ExternalConnected"] = true
        props["FullyCharged"] = true
        props["Amperage"] = 0
        props["InstantAmperage"] = 0
        let plugged = PowerSnapshot(percent: 100, plugged: true, systemW: 24)
        XCTAssertEqual(sample(&tracker, props, at: 0, system: .full, snapshot: plugged).batteryTimeEstimate, .full)

        props["ExternalConnected"] = false
        props["Amperage"] = -2_000
        props["InstantAmperage"] = -2_000
        let unplugged = PowerSnapshot(percent: 100, batteryW: -24, systemW: 24)
        // The two APIs can still disagree for the first sample after unplugging.
        let first = sample(&tracker, props, at: 1, system: .full, snapshot: unplugged)
        XCTAssertEqual(first.batteryTimeEstimate, .remaining(nil))
        XCTAssertNil(first.batteryTimeEstimateSource)
        for time: UInt64 in 2...60 {
            XCTAssertEqual(sample(&tracker, props, at: time, system: .remaining(nil), snapshot: unplugged)
                .batteryTimeEstimate, .remaining(nil))
        }
        let settled = sample(&tracker, props, at: 61, system: .remaining(nil), snapshot: unplugged)
        XCTAssertEqual(settled.batteryTimeEstimate, .remaining(180))
        XCTAssertEqual(settled.batteryTimeEstimateSource, .observedDischarge)
    }

    func testOppositeSystemDirectionWaitIsBoundedAndCanRecover() {
        for charging in [false, true] {
            var tracker = BatteryTimeFallback()
            var props = properties(charging: charging)
            props[charging ? "AvgTimeToFull" : "AvgTimeToEmpty"] = 19
            let stale: BatteryTimeEstimate = charging ? .remaining(125) : .charging(19)
            for time: UInt64 in 0...59 {
                let result = sample(&tracker, props, at: time, system: stale)
                XCTAssertEqual(result.batteryTimeEstimate, charging ? .charging(nil) : .remaining(nil))
                XCTAssertNil(result.batteryTimeEstimateSource)
            }
            for time: UInt64 in 60...120 {
                XCTAssertNil(sample(&tracker, props, at: time, system: stale).batteryTimeEstimate)
            }
            let fresh = sample(&tracker, props, at: 121, system: charging ? .charging(42) : .remaining(125))
            XCTAssertEqual(fresh.batteryTimeEstimate, charging ? .charging(42) : .remaining(125))
            XCTAssertEqual(fresh.batteryTimeEstimateSource, .system)
        }
    }

    func testRegistryStateCanRecoverFullOrPausedButDoesNotUseRoundedPercent() {
        var tracker = BatteryTimeFallback()
        var props = properties(charging: true)
        props["AppleRawCurrentCapacity"] = 7_680
        props["AvgTimeToFull"] = 19
        let snapshot = PowerSnapshot(percent: 100, plugged: true, batteryW: 0.1)
        for time: UInt64 in 0...60 { _ = sample(&tracker, props, at: time, snapshot: snapshot) }
        XCTAssertEqual(sample(&tracker, props, at: 61, snapshot: snapshot).batteryTimeEstimate, .charging(19))
        props["IsCharging"] = false
        let paused = sample(&tracker, props, at: 62, snapshot: snapshot)
        XCTAssertEqual(paused.batteryTimeEstimate, .notCharging)
        XCTAssertEqual(paused.batteryTimeEstimateSource, .batteryGauge)
        props["FullyCharged"] = true
        XCTAssertEqual(sample(&tracker, props, at: 63, snapshot: snapshot).batteryTimeEstimate, .full)
        let mixed = PowerSnapshot(percent: 100, plugged: true, batteryW: -12)
        XCTAssertEqual(sample(&tracker, props, at: 64, snapshot: mixed).batteryTimeEstimate, .notCharging)
    }

    func testUnknownOrInconsistentRegistryStateIsImmediatelyUnavailable() {
        for patch: [String: Any] in [
            ["ExternalConnected": NSNull()], ["IsCharging": NSNull()],
            ["IsCharging": true],
        ] {
            var tracker = BatteryTimeFallback()
            var props = properties()
            props.merge(patch) { _, new in new }
            XCTAssertNil(sample(&tracker, props, at: 0).batteryTimeEstimate)
        }
    }

    func testReaderRetainsHistoryWithoutTelemetryAndNormalFreshnessResetButClearsOnFailureOrWake() {
        let backend = RuntimeEstimateBatteryBackend(properties: properties())
        var now: UInt64 = 0
        let reader = AppleSmartBatteryPowerObservationReader(
            backend: backend, clock: { now * self.second }, lowPowerMode: { false }, batteryTimeEstimate: { nil }
        )
        for time: UInt64 in 0...60 {
            now = time
            if time == 30 { reader.resetFreshness() }
            _ = reader.readRuntimeSample()
        }
        now = 61
        XCTAssertEqual(reader.readRuntimeSample().visibleSnapshot?.batteryTimeEstimate, .remaining(180))
        reader.resetBatteryTimeHistory()
        now = 62
        XCTAssertEqual(reader.readRuntimeSample().visibleSnapshot?.batteryTimeEstimate, .remaining(nil))
        for time: UInt64 in 63...122 { now = time; _ = reader.readRuntimeSample() }
        backend.servicePresent = false
        now = 123
        XCTAssertNil(reader.readRuntimeSample().visibleSnapshot)
        backend.servicePresent = true
        now = 124
        XCTAssertEqual(reader.readRuntimeSample().visibleSnapshot?.batteryTimeEstimate, .remaining(nil))
        for time: UInt64 in 125...184 { now = time; _ = reader.readRuntimeSample() }
        backend.properties["MaxCapacity"] = nil
        now = 185
        XCTAssertNil(reader.readRuntimeSample().visibleSnapshot)
        backend.properties["MaxCapacity"] = 100
        now = 186
        XCTAssertEqual(reader.readRuntimeSample().visibleSnapshot?.batteryTimeEstimate, .remaining(nil))
        XCTAssertTrue(AppleSmartBatteryPowerObservationReader.runtimePropertyAllowlist.contains("AppleRawMaxCapacity"))
        XCTAssertTrue(AppleSmartBatteryPowerObservationReader.runtimePropertyAllowlist.contains("AvgTimeToFull"))
    }
}
