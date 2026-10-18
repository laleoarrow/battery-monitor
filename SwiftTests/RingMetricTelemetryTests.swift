import Foundation
import XCTest
@testable import Wattson

final class RingMetricTelemetryTests: XCTestCase {
    func testFixtureKeepsMeasuredBatteryAndAdapterUnitsSeparate() throws {
        let snapshot = try sample(fixture())

        XCTAssertEqual(snapshot.batteryVoltageV, 12.81)
        XCTAssertEqual(snapshot.batteryCurrentMA, 607)
        XCTAssertEqual(snapshot.adapterVoltageV, 19.32)
        XCTAssertEqual(snapshot.adapterCurrentMA, 2_363)
        XCTAssertEqual(snapshot.maxCapacityMAh, 6_975)
        XCTAssertEqual(snapshot.designCapacityMAh, 8_579)
        XCTAssertEqual(
            try XCTUnwrap(snapshot.batteryHealthPercent),
            6_975.0 / 8_579 * 100, accuracy: 0.0001
        )
    }

    func testBatteryCurrentPrefersInstantAndFallsBackToAverage() throws {
        let cases: [(Any?, Any?, Int?)] = [
            (607, 500, 607), (nil, -500, -500),
            (-1, -500, -500), (100_001, -500, -500),
            (true, -500, -500), (607.5, -500, -500),
            (0, -500, 0), (nil, nil, nil),
        ]
        for (instant, average, expected) in cases {
            var properties = fixture()
            properties["InstantAmperage"] = instant
            properties["Amperage"] = average
            XCTAssertEqual(try sample(properties).batteryCurrentMA, expected)
        }
    }

    func testBatteryDischargeCurrentRetainsSignedFirmwareValues() throws {
        for current: Any in [
            -607,
            NSNumber(value: UInt32(bitPattern: -607)),
            NSNumber(value: UInt64(bitPattern: -607)),
        ] {
            var properties = fixture()
            properties["ExternalConnected"] = false
            properties["IsCharging"] = false
            properties["InstantAmperage"] = current
            let snapshot = try sample(properties)
            XCTAssertEqual(snapshot.batteryCurrentMA, -607)
            XCTAssertNil(snapshot.adapterVoltageV)
            XCTAssertNil(snapshot.adapterCurrentMA)
        }
    }

    func testMissingOptionalMetricsStayUnavailable() throws {
        let snapshot = try sample([
            "CurrentCapacity": 70, "MaxCapacity": 100,
            "ExternalConnected": true,
        ])
        XCTAssertNil(snapshot.batteryVoltageV)
        XCTAssertNil(snapshot.batteryCurrentMA)
        XCTAssertNil(snapshot.adapterVoltageV)
        XCTAssertNil(snapshot.adapterCurrentMA)
        XCTAssertNil(snapshot.maxCapacityMAh)
        XCTAssertNil(snapshot.designCapacityMAh)
        XCTAssertNil(snapshot.batteryHealthPercent)
    }

    func testInvalidBatteryVoltageAndCurrentDegradeIndependently() throws {
        for invalid: Any in [true, 12_810.5, "12810", NSNull(), 0, -1, 50_001] {
            var properties = fixture()
            properties["Voltage"] = invalid
            let snapshot = try sample(properties)
            XCTAssertNil(snapshot.batteryVoltageV)
            XCTAssertEqual(snapshot.batteryCurrentMA, 607)
            XCTAssertEqual(snapshot.adapterVoltageV, 19.32)
        }
        for invalid: Any in [true, 607.5, "607", NSNull(), -1, -100_001, 100_001] {
            var properties = fixture()
            properties["InstantAmperage"] = invalid
            properties["Amperage"] = nil
            let snapshot = try sample(properties)
            XCTAssertNil(snapshot.batteryCurrentMA)
            XCTAssertEqual(snapshot.batteryVoltageV, 12.81)
        }
    }

    func testAdapterZeroReadingsArePreservedWhileConnected() throws {
        var properties = fixture()
        properties["PowerTelemetryData"] = [
            "SystemVoltageIn": 0, "SystemCurrentIn": 0,
        ]
        let snapshot = try sample(properties)
        XCTAssertEqual(snapshot.adapterVoltageV, 0)
        XCTAssertEqual(snapshot.adapterCurrentMA, 0)
    }

    func testAdapterDoesNotSubstituteNegotiatedCapabilityForMeasurements() throws {
        var properties = fixture()
        properties["PowerTelemetryData"] = ["SystemPowerIn": 45_643]
        let snapshot = try sample(properties)
        XCTAssertNil(snapshot.adapterVoltageV)
        XCTAssertNil(snapshot.adapterCurrentMA)
        XCTAssertEqual(snapshot.batteryVoltageV, 12.81)
        XCTAssertEqual(snapshot.batteryCurrentMA, 607)
    }

    func testAdapterRejectsInvalidNumbersAndBooleansIndependently() throws {
        for invalid: Any in [true, 19_320.5, "19320", NSNull(), -1, 50_001] {
            var properties = fixture()
            properties["PowerTelemetryData"] = [
                "SystemVoltageIn": invalid, "SystemCurrentIn": 2_363,
            ]
            let snapshot = try sample(properties)
            XCTAssertNil(snapshot.adapterVoltageV)
            XCTAssertEqual(snapshot.adapterCurrentMA, 2_363)
        }
        for invalid: Any in [true, 2_363.5, "2363", NSNull(), -1, 100_001] {
            var properties = fixture()
            properties["PowerTelemetryData"] = [
                "SystemVoltageIn": 19_320, "SystemCurrentIn": invalid,
            ]
            let snapshot = try sample(properties)
            XCTAssertEqual(snapshot.adapterVoltageV, 19.32)
            XCTAssertNil(snapshot.adapterCurrentMA)
        }
    }

    func testUnpluggingDiscardsStaleAdapterTelemetry() throws {
        var properties = fixture()
        properties["ExternalConnected"] = false
        let snapshot = try sample(properties)
        XCTAssertNil(snapshot.adapterVoltageV)
        XCTAssertNil(snapshot.adapterCurrentMA)

        var stale = snapshot
        stale.adapterVoltageV = 19.32
        stale.adapterCurrentMA = 2_363
        for systemW: Double? in [nil, 15] {
            let merged = BatterySampler.resolvedLivePower(
                snapshot: stale, adapterW: 45, systemW: systemW
            )
            XCTAssertNil(merged.adapterVoltageV)
            XCTAssertNil(merged.adapterCurrentMA)
        }
    }

    func testHealthUsesPhysicalRawCapacityInsteadOfAppleSiliconPercentage() throws {
        var properties = fixture()
        properties["MaxCapacity"] = 100
        XCTAssertEqual(try sample(properties).maxCapacityMAh, 6_975)

        properties["AppleRawMaxCapacity"] = nil
        let snapshot = try sample(properties)
        XCTAssertNil(snapshot.maxCapacityMAh)
        XCTAssertNil(snapshot.batteryHealthPercent)
        XCTAssertEqual(snapshot.designCapacityMAh, 8_579)

        // Even an ordinary capacity that looks like mAh is not an explicit raw
        // measurement and cannot silently replace the missing raw maximum.
        properties["MaxCapacity"] = 6_975
        XCTAssertNil(try sample(properties).batteryHealthPercent)
    }

    func testHealthRequiresBothValidPhysicalCapacityMeasurements() throws {
        for key in ["AppleRawMaxCapacity", "DesignCapacity"] {
            for invalid: Any in [true, 6_975.5, "6975", NSNull(), -1, 0, 100_001] {
                var properties = fixture()
                properties[key] = invalid
                let snapshot = try sample(properties)
                XCTAssertNil(snapshot.batteryHealthPercent)
                if key == "AppleRawMaxCapacity" {
                    XCTAssertNil(snapshot.maxCapacityMAh)
                    XCTAssertEqual(snapshot.designCapacityMAh, 8_579)
                } else {
                    XCTAssertNil(snapshot.designCapacityMAh)
                    XCTAssertEqual(snapshot.maxCapacityMAh, 6_975)
                }
            }
            var properties = fixture()
            properties[key] = nil
            XCTAssertNil(try sample(properties).batteryHealthPercent)
        }
    }

    func testRuntimeAllowlistCarriesCapacityAndMeasuredInputThroughFusion() throws {
        let backend = RingMetricBatteryBackend(properties: fixture())
        let reader = AppleSmartBatteryPowerObservationReader(
            backend: backend, clock: { 100 }, lowPowerMode: { false },
            batteryTimeEstimate: { nil }
        )
        let runtime = PowerObservationRuntimeController(
            batteryReader: reader,
            helperObservation: { _ in
                .legacyV4(HelperClient.LivePower(adapterW: 60, systemW: 40))
            },
            clock: { 100 },
            shadowRecorder: PrivacySafePowerObservationShadowRecorder()
        )

        let snapshot = try XCTUnwrap(runtime.sample(event: .normal).visibleSnapshot)
        XCTAssertTrue(backend.requestedKeys.contains("DesignCapacity"))
        XCTAssertEqual(snapshot.systemW, 40)
        XCTAssertEqual(snapshot.batteryVoltageV, 12.81)
        XCTAssertEqual(snapshot.batteryCurrentMA, 607)
        XCTAssertEqual(snapshot.adapterVoltageV, 19.32)
        XCTAssertEqual(snapshot.adapterCurrentMA, 2_363)
        XCTAssertEqual(snapshot.maxCapacityMAh, 6_975)
        XCTAssertEqual(snapshot.designCapacityMAh, 8_579)
        XCTAssertNotNil(snapshot.batteryHealthPercent)
    }

    private func sample(_ properties: [String: Any]) throws -> PowerSnapshot {
        let snapshot: PowerSnapshot?
        if case let .snapshot(value) = BatterySampler.sampleResult(
            from: properties, lowPowerMode: false
        ) {
            snapshot = value
        } else {
            snapshot = nil
        }
        return try XCTUnwrap(snapshot)
    }

    private func fixture() -> [String: Any] {
        [
            "CurrentCapacity": 70, "MaxCapacity": 100,
            "ExternalConnected": true, "IsCharging": true,
            "Voltage": 12_810, "InstantAmperage": 607, "Amperage": 500,
            "AppleRawMaxCapacity": 6_975, "DesignCapacity": 8_579,
            "PowerTelemetryData": [
                "SystemPowerIn": 45_643, "SystemLoad": 37_867,
                "BatteryPower": 7_776, "SystemVoltageIn": 19_320,
                "SystemCurrentIn": 2_363,
            ],
            "AdapterDetails": [
                "AdapterVoltage": 20_000, "Current": 4_900, "Watts": 98,
            ],
        ]
    }
}

private final class RingMetricBatteryBackend: AppleSmartBatteryPowerRawSnapshotReading {
    let properties: [String: Any]
    private(set) var requestedKeys: [String] = []

    init(properties: [String: Any]) {
        self.properties = properties
    }

    func readAllowlistedProperties(_ keys: [String]) -> AppleSmartBatteryPowerRawSnapshot {
        requestedKeys = keys
        return AppleSmartBatteryPowerRawSnapshot(
            servicePresent: true,
            properties: properties.filter { keys.contains($0.key) }
        )
    }
}
