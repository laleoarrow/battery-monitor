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
        XCTAssertNil(BatteryRuntimeEstimate.estimate(from: [source]))
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
            XCTAssertEqual(reader.readRuntimeSample().visibleSnapshot?.batteryTimeEstimate, estimate)
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
