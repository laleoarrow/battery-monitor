import XCTest
@testable import Wattson

final class BatteryRuntimeEstimateTests: XCTestCase {
    func testSelectsInternalBatteryInsteadOfUPS() {
        var ups = powerSource(minutes: 999)
        ups["Type"] = "UPS"
        XCTAssertEqual(BatteryRuntimeEstimate.minutes(from: [ups, powerSource(minutes: 125)]), 125)
        XCTAssertNil(BatteryRuntimeEstimate.minutes(from: [ups]))
    }

    func testRequiresPresentDischargingInternalBattery() {
        let invalidFields: [(String, Any?)] = [
            ("Type", nil), ("Type", "UPS"),
            ("Is Present", nil), ("Is Present", false), ("Is Present", "true"),
            ("Power Source State", nil), ("Power Source State", "AC Power"),
            ("Is Charging", nil), ("Is Charging", true), ("Is Charging", "false"),
        ]
        for (key, value) in invalidFields {
            var source = powerSource(minutes: 125)
            source[key] = value
            XCTAssertNil(BatteryRuntimeEstimate.minutes(from: [source]), "\(key)=\(String(describing: value))")
        }
        XCTAssertNil(BatteryRuntimeEstimate.minutes(from: []))
    }

    func testRejectsUnknownNegativeMissingAndMalformedMinutes() {
        let invalid: [Any?] = [
            nil, -1, -2, -10, true, 1.0, 1.5, "120",
            NSNumber(value: UInt64.max), NSNumber(value: Int64(Int32.max) + 1),
        ]
        for value in invalid {
            XCTAssertNil(BatteryRuntimeEstimate.minutes(from: [powerSource(minutes: value)]),
                         "minutes=\(String(describing: value))")
        }
    }

    func testZeroMinutesIsAValidNearEmptyEstimate() {
        XCTAssertEqual(BatteryRuntimeEstimate.minutes(from: [powerSource(minutes: 0)]), 0)
    }

    func testEstimateIsAppliedOnlyWhileOnBattery() {
        var reads = 0
        let readMinutes: () -> Int? = { reads += 1; return 125 }
        for snapshot in [
            PowerSnapshot(percent: 80, plugged: true, batteryW: 12),
            PowerSnapshot(percent: 100, plugged: true, batteryW: 0),
            PowerSnapshot(percent: 80, plugged: true, batteryW: -12),
        ] {
            XCTAssertNil(BatteryRuntimeEstimate.applying(to: snapshot, readMinutes: readMinutes)
                .estimatedRuntimeMinutes)
        }
        XCTAssertEqual(reads, 0)
        XCTAssertEqual(BatteryRuntimeEstimate.applying(
            to: PowerSnapshot(percent: 80, batteryW: -12), readMinutes: readMinutes
        ).estimatedRuntimeMinutes, 125)
        XCTAssertEqual(reads, 1)
    }

    func testUnavailableOrInvalidFreshEstimateClearsPreviousValue() {
        let previous = PowerSnapshot(percent: 80, estimatedRuntimeMinutes: 125)
        let invalid: [Int?] = [nil, -1, -2, Int(Int32.max) + 1]
        for value in invalid {
            XCTAssertNil(BatteryRuntimeEstimate.applying(to: previous, readMinutes: { value })
                .estimatedRuntimeMinutes)
        }
        var plugged = previous
        plugged.plugged = true
        XCTAssertNil(BatteryRuntimeEstimate.applying(to: plugged, readMinutes: { 125 })
            .estimatedRuntimeMinutes)
    }

    func testLowBatteryAndLowPowerDoNotInventAnEstimateMultiplier() {
        let snapshot = PowerSnapshot(percent: 5, batteryW: -8, lowPowerMode: true)
        XCTAssertEqual(BatteryRuntimeEstimate.applying(to: snapshot, readMinutes: { 17 })
            .estimatedRuntimeMinutes, 17)
    }

    func testPurePropertiesSamplingDoesNotPopulateAnExternalEstimate() {
        guard case let .snapshot(snapshot) = BatterySampler.sampleResult(
            from: batteryProperties(), lowPowerMode: false
        ) else { return XCTFail("Expected valid battery properties") }
        XCTAssertNil(snapshot.estimatedRuntimeMinutes)
    }

    func testRuntimeReaderReadsOncePerSampleAndReplacesUnknownEstimate() {
        let backend = RuntimeEstimateBatteryBackend(properties: batteryProperties())
        var reads = 0
        let reader = AppleSmartBatteryPowerObservationReader(
            backend: backend, lowPowerMode: { false },
            runtimeEstimateMinutes: { reads += 1; return reads == 1 ? 125 : nil }
        )
        XCTAssertEqual(reader.readRuntimeSample().visibleSnapshot?.estimatedRuntimeMinutes, 125)
        XCTAssertNil(reader.readRuntimeSample().visibleSnapshot?.estimatedRuntimeMinutes)
        XCTAssertEqual(reads, 2)
        XCTAssertEqual(backend.reads, 2)
    }

    func testRuntimeReaderSkipsEstimateOnExternalPowerAndUnavailableBattery() {
        let backend = RuntimeEstimateBatteryBackend(properties: batteryProperties())
        var reads = 0
        let reader = AppleSmartBatteryPowerObservationReader(
            backend: backend, lowPowerMode: { false },
            runtimeEstimateMinutes: { reads += 1; return 125 }
        )
        for (charging, current) in [(true, 1_000), (false, 0), (false, -1_000)] {
            backend.properties["ExternalConnected"] = true
            backend.properties["IsCharging"] = charging
            backend.properties["InstantAmperage"] = current
            XCTAssertNil(reader.readRuntimeSample().visibleSnapshot?.estimatedRuntimeMinutes)
        }
        backend.properties = [:]
        XCTAssertNil(reader.readRuntimeSample().visibleSnapshot)
        backend.servicePresent = false
        XCTAssertNil(reader.readRuntimeSample().visibleSnapshot)
        XCTAssertEqual(reads, 0)
    }

    private func powerSource(minutes: Any?) -> [String: Any] {
        var source: [String: Any] = [
            "Type": "InternalBattery", "Is Present": true,
            "Power Source State": "Battery Power", "Is Charging": false,
        ]
        source["Time to Empty"] = minutes
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
