import XCTest
@testable import Wattson

final class PowerInputFallbackTests: XCTestCase {
    func testBatteryOnlyUsesInstantDischargeWhenTotalsAndAverageAreMissing() throws {
        var properties = batteryProperties()
        properties["InstantAmperage"] = -1_000
        properties["PowerOutDetails"] = [["PortIndex": 1, "Watts": 7_000]]

        let snapshot = try XCTUnwrap(BatterySampler.resolvedSnapshot(
            from: properties, lowPowerMode: false
        ))

        XCTAssertEqual(snapshot.adapterW, 0)
        XCTAssertEqual(snapshot.batteryW, -12, accuracy: 0.001)
        XCTAssertEqual(snapshot.systemW, 12, accuracy: 0.001)
        XCTAssertEqual(snapshot.coherentDeviceOutputW, 7)
        XCTAssertEqual(snapshot.state, .onBattery)
        XCTAssertEqual(snapshot.conservationError, 0, accuracy: 0.001)
    }

    func testBatteryOnlyInstantFallbackPreservesTelemetryPriority() {
        for (systemLoad, batteryPower, expected): (Int?, Int?, Double) in [
            (20_000, 9_000, 20),
            (nil, 9_000, 9),
            (0, 9_000, 0),
        ] {
            let power = BatterySampler.resolvedPower(
                plugged: false, chargingHint: false,
                systemPowerIn: nil, systemLoad: systemLoad,
                batteryPower: batteryPower, fallbackBatteryW: -6,
                instantBatteryW: -12
            )
            XCTAssertEqual(power.adapterW, 0)
            XCTAssertEqual(power.batteryW, -expected, accuracy: 0.001)
            XCTAssertEqual(power.systemW, expected, accuracy: 0.001)
        }
    }

    func testBatteryOnlyInstantFallbackUsesNonpositiveFiniteBoundedValues() {
        let cases: [(Double?, Double)] = [
            (-12, 12), (0, 0), (12, 6), (nil, 6),
            (.nan, 6), (.infinity, 6), (-.infinity, 6),
            (-1_001, 6), (1_001, 6),
        ]
        for (instant, expected) in cases {
            let power = BatterySampler.resolvedPower(
                plugged: false, chargingHint: true,
                systemPowerIn: nil, systemLoad: nil,
                batteryPower: nil, fallbackBatteryW: -6,
                instantBatteryW: instant
            )
            XCTAssertEqual(power.adapterW, 0)
            XCTAssertEqual(power.batteryW, -expected, accuracy: 0.001)
            XCTAssertEqual(power.systemW, expected, accuracy: 0.001)
        }
    }

    func testBatteryOnlyAverageFallbackDoesNotTurnChargeIntoDischarge() throws {
        let cases: [(instant: Int?, average: Int, expected: Double)] = [
            (1_000, 500, 0),
            (nil, 1_000, 0),
            (1_000, -500, 6),
            (nil, -1_000, 12),
            (-1, 1_000, 0),
        ]
        for item in cases {
            var properties = batteryProperties()
            properties["InstantAmperage"] = item.instant
            properties["Amperage"] = item.average
            let snapshot = try XCTUnwrap(BatterySampler.resolvedSnapshot(
                from: properties, lowPowerMode: false
            ))
            XCTAssertEqual(snapshot.adapterW, 0)
            XCTAssertEqual(snapshot.batteryW, -item.expected, accuracy: 0.001)
            XCTAssertEqual(snapshot.systemW, item.expected, accuracy: 0.001)
            XCTAssertEqual(snapshot.state, .onBattery)
            XCTAssertEqual(snapshot.conservationError, 0, accuracy: 0.001)
        }
    }

    func testDeviceOutputDoesNotInventIdentityForAnUnnumberedPort() {
        let details: [[String: Any]] = [
            ["PortIndex": 2, "Watts": 7_000],
            ["Watts": 2_000],
        ]
        XCTAssertEqual(BatterySampler.resolvedDeviceOutputW(details), 9)
        XCTAssertEqual(BatterySampler.resolvedDeviceOutputW(
            Array(details.reversed())
        ), 9)
        XCTAssertEqual(BatterySampler.resolvedDeviceOutputW([
            ["Watts": 7_000], ["Watts": 2_000],
        ]), 9)
    }

    func testDeviceOutputStillRejectsExplicitDuplicateAndInvalidPortNumbers() {
        let duplicate: [[String: Any]] = [
            ["PortIndex": 2, "Watts": 7_000],
            ["Watts": 2_000],
            ["PortIndex": 2, "Watts": 1_000],
        ]
        XCTAssertNil(BatterySampler.resolvedDeviceOutputW(duplicate))
        XCTAssertNil(BatterySampler.resolvedDeviceOutputW(
            Array(duplicate.reversed())
        ))
        for invalid: Any in [0, 65, -1, true, 1.5, "2"] {
            XCTAssertNil(BatterySampler.resolvedDeviceOutputW([
                ["PortIndex": invalid, "Watts": 7_000],
            ]))
        }
    }

    func testPartialDeviceOutputPreservesMeasuredSumWithoutAnExactBreakdown() throws {
        for measured in [0, 7_000] {
            let details: [[String: Any]] = [
                ["PortIndex": 1, "Watts": measured],
                ["PortIndex": 2, "PDPowermW": 15_000],
            ]
            var properties = batteryProperties()
            properties["PowerTelemetryData"] = ["SystemLoad": 20_000]
            properties["PowerOutDetails"] = details

            let snapshot = try XCTUnwrap(BatterySampler.resolvedSnapshot(
                from: properties, lowPowerMode: false
            ))
            let expected = Double(measured) / 1_000
            XCTAssertEqual(BatterySampler.resolvedDeviceOutputW(details), expected)
            XCTAssertEqual(snapshot.deviceOutputW, expected)
            XCTAssertFalse(snapshot.deviceOutputIsComplete)
            XCTAssertNil(snapshot.coherentDeviceOutputW)
            XCTAssertEqual(snapshot.systemW, 20)
            XCTAssertEqual(snapshot.conservationError, 0, accuracy: 0.001)
        }
    }

    func testCompleteDeviceOutputRemainsAvailableForAnExactBreakdown() throws {
        for measured in [0, 7_000] {
            var properties = batteryProperties()
            properties["PowerTelemetryData"] = ["SystemLoad": 20_000]
            properties["PowerOutDetails"] = [
                ["PortIndex": 1, "Watts": measured],
                ["PortIndex": 2, "Watts": 0],
            ]
            let snapshot = try XCTUnwrap(BatterySampler.resolvedSnapshot(
                from: properties, lowPowerMode: false
            ))
            let expected = Double(measured) / 1_000
            XCTAssertEqual(snapshot.deviceOutputW, expected)
            XCTAssertTrue(snapshot.deviceOutputIsComplete)
            XCTAssertEqual(snapshot.coherentDeviceOutputW, expected)
        }
    }

    func testLivePowerMergeDoesNotPromotePartialDeviceOutputToComplete() throws {
        var properties = batteryProperties()
        properties["PowerTelemetryData"] = ["SystemLoad": 20_000]
        properties["PowerOutDetails"] = [
            ["PortIndex": 1, "Watts": 7_000],
            ["PortIndex": 2, "PDPowermW": 15_000],
        ]
        let snapshot = try XCTUnwrap(BatterySampler.resolvedSnapshot(
            from: properties, lowPowerMode: false
        ))
        let fresh = BatterySampler.resolvedLivePower(
            snapshot: snapshot, adapterW: nil, systemW: 25
        )
        XCTAssertEqual(fresh.deviceOutputW, 7)
        XCTAssertFalse(fresh.deviceOutputIsComplete)
        XCTAssertNil(fresh.coherentDeviceOutputW)
        XCTAssertEqual(fresh.systemW, 25)
        XCTAssertEqual(fresh.conservationError, 0, accuracy: 0.001)
    }

    func testMissingOrInvalidDeviceOutputDoesNotBecomeACompleteZero() throws {
        let details: [Any?] = [
            nil, [Any](), [["PDPowermW": 15_000]], [["Watts": "invalid"]],
        ]
        for raw in details {
            var properties = batteryProperties()
            properties["PowerTelemetryData"] = ["SystemLoad": 20_000]
            properties["PowerOutDetails"] = raw
            let snapshot = try XCTUnwrap(BatterySampler.resolvedSnapshot(
                from: properties, lowPowerMode: false
            ))
            XCTAssertNil(snapshot.deviceOutputW)
            XCTAssertFalse(snapshot.deviceOutputIsComplete)
            XCTAssertNil(snapshot.coherentDeviceOutputW)
        }
    }

    private func batteryProperties() -> [String: Any] {
        [
            "CurrentCapacity": 60,
            "MaxCapacity": 100,
            "ExternalConnected": false,
            "Voltage": 12_000,
        ]
    }
}
