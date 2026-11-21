import Foundation
import XCTest
@testable import Wattson

final class USBDeviceConnectionTests: XCTestCase {
    func testExternalPortHintExcludesInternalUnknownAndMalformedValues() {
        for type in [0, 5] {
            XCTAssertTrue(USBDeviceConnectionReader.isExternalPortType(NSNumber(value: type)))
        }
        let rejected: [Any?] = [
            nil, NSNumber(value: true), NSNumber(value: false),
            -1, 1, 2, 3, 4, 6, 255, Double.nan, Double.infinity,
            "0", "5", Data([0]), Data([5]), ["USBPortType": 5],
        ]
        for raw in rejected {
            XCTAssertFalse(USBDeviceConnectionReader.isExternalPortType(raw), "\(String(describing: raw))")
        }
    }

    func testFractionalPortTypesAreNotTruncatedToExternalPorts() {
        for value in [-0.5, 0.5, Double.leastNonzeroMagnitude,
                      5.0.nextDown, 5.0.nextUp, 5.5] {
            XCTAssertFalse(
                USBDeviceConnectionReader.isExternalPortType(NSNumber(value: value)),
                "Fractional port type \(value) must not become 0 or 5"
            )
        }
        for value in [0.0, 5.0] {
            XCTAssertTrue(USBDeviceConnectionReader.isExternalPortType(NSNumber(value: value)))
        }
    }

    func testConnectionAppearsBeforeDelayedPowerAndChangesWithoutCaching() throws {
        let backend = USBConnectionBatteryBackend()
        let reader = makeReader(backend)
        let baseline = try XCTUnwrap(reader.readRuntimeSample().visibleSnapshot)
        XCTAssertFalse(baseline.hasConnectedUSBDevice)
        XCTAssertNil(baseline.deviceOutputW)

        backend.connected = true
        for _ in 0..<53 {
            let pending = reader.readRuntimeSample()
            XCTAssertTrue(try XCTUnwrap(pending.visibleSnapshot).hasConnectedUSBDevice)
            XCTAssertNil(pending.visibleSnapshot?.deviceOutputW)
            XCTAssertNil(pending.visibleSnapshot?.coherentDeviceOutputW)
            XCTAssertEqual(pending.visibleSnapshot?.systemW, 24)
            XCTAssertEqual(pending.observation.deviceOutput.fieldPresence, .missing)
        }

        backend.properties["PowerOutDetails"] = [["PortIndex": 1, "Watts": 7_000]]
        let measured = try XCTUnwrap(reader.readRuntimeSample().visibleSnapshot)
        XCTAssertTrue(measured.hasConnectedUSBDevice)
        XCTAssertEqual(measured.coherentDeviceOutputW, 7)

        // Enumeration cannot negate an independent measured power-only load.
        backend.connected = false
        let powerOnly = try XCTUnwrap(reader.readRuntimeSample().visibleSnapshot)
        XCTAssertFalse(powerOnly.hasConnectedUSBDevice)
        XCTAssertEqual(powerOnly.coherentDeviceOutputW, 7)

        backend.properties.removeValue(forKey: "PowerOutDetails")
        let removed = try XCTUnwrap(reader.readRuntimeSample().visibleSnapshot)
        XCTAssertFalse(removed.hasConnectedUSBDevice)
        XCTAssertNil(removed.deviceOutputW)
        XCTAssertEqual(backend.connectionReadCount, 57)
    }

    func testConnectedZeroAndPartialOutputNeverInventMeasuredPower() throws {
        let backend = USBConnectionBatteryBackend()
        backend.connected = true
        let reader = makeReader(backend)
        backend.properties["PowerOutDetails"] = [["PortIndex": 1, "Watts": 0]]
        let zero = try XCTUnwrap(reader.readRuntimeSample().visibleSnapshot)
        XCTAssertTrue(zero.hasConnectedUSBDevice)
        XCTAssertEqual(zero.deviceOutputW, 0)
        XCTAssertEqual(zero.coherentDeviceOutputW, 0)

        backend.properties["PowerOutDetails"] = [
            ["PortIndex": 1, "Watts": 7_000], ["PortIndex": 2],
        ]
        let partial = try XCTUnwrap(reader.readRuntimeSample().visibleSnapshot)
        XCTAssertTrue(partial.hasConnectedUSBDevice)
        XCTAssertEqual(partial.deviceOutputW, 7)
        XCTAssertFalse(partial.deviceOutputIsComplete)
        XCTAssertNil(partial.coherentDeviceOutputW)
    }

    func testHelperMergeRetainsConnectionHintWithoutInventingUSBWatts() throws {
        let backend = USBConnectionBatteryBackend()
        backend.connected = true
        let original = try XCTUnwrap(makeReader(backend).readRuntimeSample().visibleSnapshot)
        let merged = BatterySampler.resolvedLivePower(
            snapshot: original, adapterW: nil, systemW: 30
        )
        XCTAssertTrue(merged.hasConnectedUSBDevice)
        XCTAssertEqual(merged.systemW, 30)
        XCTAssertNil(merged.deviceOutputW)
        XCTAssertNil(merged.coherentDeviceOutputW)
    }

    func testUnavailableBatteryDoesNotAcquireUnusableConnectionHint() {
        let backend = USBConnectionBatteryBackend()
        backend.properties.removeValue(forKey: "CurrentCapacity")
        XCTAssertNil(makeReader(backend).readRuntimeSample().visibleSnapshot)
        XCTAssertEqual(backend.connectionReadCount, 0)
    }

    func testFixtureBackendDefaultsToNoHostUSBQuery() {
        XCTAssertFalse(USBConnectionDefaultBackend().hasExternalUSBDevice())
    }

    private func makeReader(
        _ backend: USBConnectionBatteryBackend
    ) -> AppleSmartBatteryPowerObservationReader {
        AppleSmartBatteryPowerObservationReader(
            systemBatteryReading: { .init() },
            batteryHealthPercent: { nil },
            backend: backend,
            clock: { 1 },
            lowPowerMode: { false }
        )
    }
}

private final class USBConnectionBatteryBackend: AppleSmartBatteryPowerRawSnapshotReading {
    var connected = false
    var connectionReadCount = 0
    var properties: [String: Any] = [
        "CurrentCapacity": 80, "MaxCapacity": 100,
        "ExternalConnected": false, "Voltage": 12_000,
        "InstantAmperage": -2_000, "Amperage": -2_000,
    ]

    func readAllowlistedProperties(_ keys: [String]) -> AppleSmartBatteryPowerRawSnapshot {
        .init(servicePresent: true, properties: properties.filter { keys.contains($0.key) })
    }

    func hasExternalUSBDevice() -> Bool {
        connectionReadCount += 1
        return connected
    }
}

private struct USBConnectionDefaultBackend: AppleSmartBatteryPowerRawSnapshotReading {
    func readAllowlistedProperties(_ keys: [String]) -> AppleSmartBatteryPowerRawSnapshot {
        .init(servicePresent: false, properties: [:])
    }
}
