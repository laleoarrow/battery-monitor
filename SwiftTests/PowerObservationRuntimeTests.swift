import Foundation
import XCTest
@testable import Wattson

final class PowerObservationRuntimeTests: XCTestCase {
    func testNilPolicyNeverMakesRuntimeResolutionVisible() throws {
        let reader = RuntimeBatteryReader(
            observation: missingBattery(),
            snapshot: snapshot(adapter: 20, battery: 5, system: 15)
        )
        let recorder = RuntimeShadowRecorder()
        let runtime = PowerObservationRuntimeController(
            batteryReader: reader,
            helperObservation: { sequence in
                .v5(self.response(sequence: sequence, pdtr: 70, pstr: 40))
            },
            clock: RuntimeClock(values: [100, 200]).next,
            shadowRecorder: recorder
        )

        let result = runtime.sample(event: .normal)

        XCTAssertEqual(result.sequence, 1)
        guard case .policyUnavailable = result.resolution.pstrBand else {
            return XCTFail("production runtime must not configure a PSTR policy")
        }
        XCTAssertFalse(result.resolution.userVisibleEligible)
        XCTAssertTrue(try XCTUnwrap(result.shadowComparison)
            .userVisibleValuesUnchanged)
        XCTAssertEqual(recorder.comparisons.count, 1)
    }

    func testV5DirectValuesOnlyEnterLegacyResolvedLivePowerFormula() throws {
        let runtime = makeRuntime(
            snapshot: snapshot(adapter: 20, battery: 5, system: 15),
            helperResult: { sequence in
                .v5(self.response(sequence: sequence, pdtr: 70, pstr: 40))
            }
        )

        let result = runtime.sample(event: .normal)

        XCTAssertEqual(result.visibleSnapshot?.systemW, 40)
        XCTAssertEqual(result.visibleSnapshot?.batteryW, 5)
        XCTAssertEqual(result.visibleSnapshot?.adapterW, 45)
        XCTAssertEqual(result.resolution.adapter?.watts, 70)
        XCTAssertNotEqual(
            result.visibleSnapshot?.adapterW,
            result.resolution.adapter?.watts
        )
    }

    func testLegacyV4FallbackStillUsesLegacyResolvedLivePowerFormula() {
        let runtime = makeRuntime(
            snapshot: snapshot(adapter: 20, battery: 5, system: 15),
            helperResult: { _ in
                .legacyV4(HelperClient.LivePower(adapterW: 60, systemW: nil))
            }
        )

        let result = runtime.sample(event: .normal)

        XCTAssertEqual(result.visibleSnapshot?.adapterW, 60)
        XCTAssertEqual(result.visibleSnapshot?.batteryW, 5)
        XCTAssertEqual(result.visibleSnapshot?.systemW, 55)
    }

    func testPartialV5PreservesLegacyPSTRFirstFallbackSemantics() {
        let pstrRuntime = makeRuntime(
            snapshot: snapshot(adapter: 20, battery: 5, system: 15),
            helperResult: { sequence in
                .v5(self.response(sequence: sequence, pdtr: nil, pstr: 40))
            }
        )
        let pstrResult = pstrRuntime.sample(event: .normal)
        XCTAssertEqual(pstrResult.visibleSnapshot?.systemW, 40)
        XCTAssertEqual(pstrResult.visibleSnapshot?.batteryW, 5)
        XCTAssertEqual(pstrResult.visibleSnapshot?.adapterW, 45)

        let pdtrRuntime = makeRuntime(
            snapshot: snapshot(adapter: 20, battery: 5, system: 15),
            helperResult: { sequence in
                .v5(self.response(sequence: sequence, pdtr: 60, pstr: nil))
            }
        )
        let pdtrResult = pdtrRuntime.sample(event: .normal)
        XCTAssertEqual(pdtrResult.visibleSnapshot?.adapterW, 60)
        XCTAssertEqual(pdtrResult.visibleSnapshot?.batteryW, 5)
        XCTAssertEqual(pdtrResult.visibleSnapshot?.systemW, 55)
    }

    func testFailedHelperFetchPreservesBatterySnapshot() {
        let original = snapshot(adapter: 20, battery: -3, system: 23)
        let runtime = makeRuntime(
            snapshot: original,
            helperResult: { _ in .failed(.legacyV4Unavailable) }
        )

        let result = runtime.sample(event: .normal)

        XCTAssertEqual(result.visibleSnapshot?.adapterW, original.adapterW)
        XCTAssertEqual(result.visibleSnapshot?.batteryW, original.batteryW)
        XCTAssertEqual(result.visibleSnapshot?.systemW, original.systemW)
        XCTAssertEqual(result.visibleSnapshot?.percent, original.percent)
    }

    func testSequenceIsMonotonicAndEventsResetReaderFreshness() {
        let reader = RuntimeBatteryReader(
            observation: missingBattery(),
            snapshot: snapshot(adapter: 0, battery: -10, system: 10)
        )
        let runtime = PowerObservationRuntimeController(
            batteryReader: reader,
            helperObservation: { _ in .failed(.legacyV4Unavailable) },
            clock: RuntimeClock(values: [10, 20, 30, 40, 50, 60]).next,
            shadowRecorder: RuntimeShadowRecorder()
        )

        XCTAssertEqual(runtime.sample(event: .normal).sequence, 1)
        XCTAssertEqual(runtime.sample(event: .powerSourceTransition).sequence, 2)
        XCTAssertEqual(runtime.sample(event: .sleepWake).sequence, 3)
        XCTAssertEqual(reader.resetCount, 2)
    }

    func testRuntimeCarriesSignedBatteryVoltageTimesCurrentInShadowOnly() throws {
        let battery = try batteryWithSignedVI(
            voltage: 12_000,
            instantCurrent: -1_000,
            averageCurrent: nil
        )
        let runtime = PowerObservationRuntimeController(
            batteryReader: RuntimeBatteryReader(
                observation: battery,
                snapshot: snapshot(adapter: 20, battery: -3, system: 23)
            ),
            helperObservation: { sequence in
                .v5(self.response(sequence: sequence, pdtr: 20, pstr: 23))
            },
            clock: RuntimeClock(values: [100]).next,
            shadowRecorder: RuntimeShadowRecorder()
        )

        let result = runtime.sample(event: .normal)

        XCTAssertEqual(result.resolution.battery?.signedWatts, -12)
        XCTAssertEqual(
            result.resolution.battery?.source,
            .batteryVoltageTimesCurrent
        )
        XCTAssertEqual(result.visibleSnapshot?.batteryW, -3)
        XCTAssertFalse(result.resolution.userVisibleEligible)

        let averageOnlyBattery = try batteryWithSignedVI(
            voltage: 12_000,
            instantCurrent: nil,
            averageCurrent: -500
        )
        let averageOnlyRuntime = PowerObservationRuntimeController(
            batteryReader: RuntimeBatteryReader(
                observation: averageOnlyBattery,
                snapshot: snapshot(adapter: 20, battery: -3, system: 23)
            ),
            helperObservation: { sequence in
                .v5(self.response(
                    sequence: sequence,
                    pdtr: 20,
                    pstr: 23
                ))
            },
            clock: RuntimeClock(values: [200]).next,
            shadowRecorder: RuntimeShadowRecorder()
        )

        let averageOnlyResult = averageOnlyRuntime.sample(event: .normal)

        XCTAssertEqual(
            averageOnlyResult.resolution.battery?.signedWatts,
            -6
        )
        XCTAssertEqual(averageOnlyResult.visibleSnapshot?.batteryW, -3)
        XCTAssertFalse(
            averageOnlyResult.resolution.userVisibleEligible
        )
    }

    func testEventMergingRetainsStrongestFreshFollowUp() {
        XCTAssertEqual(
            PowerObservationRuntimeEvent.normal
                .merging(.powerSourceTransition)
                .merging(.sleepWake),
            .sleepWake
        )
        XCTAssertEqual(
            PowerObservationRuntimeEvent.sleepWake
                .merging(.powerSourceTransition),
            .sleepWake
        )
    }

    func testReaderUsesFixedAllowlistAndResetsFreshnessAfterGap() throws {
        let backend = RuntimeBatteryBackend(properties: telemetryProperties())
        let clock = RuntimeClock(values: [0, 10, 20, 30, 200, 210])
        let reader = AppleSmartBatteryPowerObservationReader(
            backend: backend,
            clock: clock.next,
            maximumTrackingGapNanoseconds: 100
        )

        let first = reader.readObservation()
        let second = reader.readObservation()
        let afterGap = reader.readObservation()

        XCTAssertEqual(backend.requestedKeys, [
            AppleSmartBatteryPowerObservationReader.propertyAllowlist,
            AppleSmartBatteryPowerObservationReader.propertyAllowlist,
            AppleSmartBatteryPowerObservationReader.propertyAllowlist,
        ])
        XCTAssertEqual(first.powerTelemetry.freshness.assessment, .changed)
        XCTAssertEqual(second.powerTelemetry.freshness.assessment, .unchanged)
        XCTAssertEqual(afterGap.powerTelemetry.freshness.assessment, .changed)
        XCTAssertEqual(first.externalConnected.value, true)
        XCTAssertEqual(first.isCharging.value, true)
        XCTAssertEqual(first.voltageMillivolts.value, 12_000)
        XCTAssertEqual(first.instantAmperageMilliamps.value, 1_000)
        XCTAssertEqual(first.averageAmperageMilliamps.value, 900)

        var signedProperties = telemetryProperties()
        signedProperties["InstantAmperage"] = NSNumber(
            value: UInt64.max
        )
        let signedReader = AppleSmartBatteryPowerObservationReader(
            backend: RuntimeBatteryBackend(properties: signedProperties),
            clock: RuntimeClock(values: [300, 310]).next
        )
        XCTAssertEqual(
            signedReader.readObservation()
                .instantAmperageMilliamps.value,
            -1
        )
        for forbidden in [
            "LocationID", "Serial", "SerialNumber", "UUID",
            "DeviceName", "ProductName", "VendorName", "IORegistryPath",
        ] {
            XCTAssertFalse(
                AppleSmartBatteryPowerObservationReader.propertyAllowlist
                    .contains(forbidden)
            )
        }
    }

    func testReaderResetMakesAnUnchangedTokenFreshAgain() {
        let backend = RuntimeBatteryBackend(properties: telemetryProperties())
        let clock = RuntimeClock(values: [0, 10, 20, 30, 40, 50])
        let reader = AppleSmartBatteryPowerObservationReader(
            backend: backend,
            clock: clock.next,
            maximumTrackingGapNanoseconds: 1_000
        )

        XCTAssertEqual(
            reader.readObservation().powerTelemetry.freshness.assessment,
            .changed
        )
        XCTAssertEqual(
            reader.readObservation().powerTelemetry.freshness.assessment,
            .unchanged
        )
        reader.resetFreshness()
        XCTAssertEqual(
            reader.readObservation().powerTelemetry.freshness.assessment,
            .changed
        )
    }

    func testRuntimeReadsBatteryFieldsOnceForVisibleAndShadowAcrossPowerStates() throws {
        let backend = RuntimeBatteryBackend(properties: [:])
        let reader = AppleSmartBatteryPowerObservationReader(
            backend: backend,
            clock: RuntimeClock(values: Array(0..<20)).next,
            lowPowerMode: { true }
        )
        let runtime = PowerObservationRuntimeController(
            batteryReader: reader,
            helperObservation: { _ in .failed(.legacyV4Unavailable) },
            clock: { 100 },
            shadowRecorder: RuntimeShadowRecorder()
        )
        let cases: [(Bool, Int, Int, Int, PowerState)] = [
            (true, 1_000, 70, 7_000, .charging),
            (true, 0, 100, 0, .pluggedIdle),
            (false, -1_000, 70, 5_000, .onBattery),
            (true, -500, 70, 5_000, .mixedSupply),
            (false, -1_000, 5, 0, .onBattery),
        ]
        for (index, item) in cases.enumerated() {
            let (plugged, current, percent, output, state) = item
            var properties = telemetryProperties()
            properties["ExternalConnected"] = NSNumber(value: plugged)
            properties["InstantAmperage"] = NSNumber(value: current)
            properties["CurrentCapacity"] = NSNumber(value: percent)
            properties["CycleCount"] = NSNumber(value: 282)
            properties["Temperature"] = NSNumber(value: 3_400)
            properties["PowerOutDetails"] = [["Watts": output]]
            backend.properties = properties

            let result = runtime.sample(event: .powerSourceTransition)
            let visible = try XCTUnwrap(result.visibleSnapshot)
            XCTAssertEqual(backend.requestedKeys.count, index + 1)
            XCTAssertEqual(backend.requestedKeys.last,
                           AppleSmartBatteryPowerObservationReader.runtimePropertyAllowlist)
            XCTAssertEqual(visible.state, state)
            XCTAssertEqual(visible.percent, percent)
            XCTAssertEqual(visible.cycleCount, 282)
            XCTAssertTrue(visible.lowPowerMode)
            XCTAssertEqual(visible.deviceOutputW, Double(output) / 1_000)
            XCTAssertEqual(result.resolution.deviceOutputAuxiliary?.watts,
                           visible.deviceOutputW)
            XCTAssertEqual(result.resolution.battery?.signedWatts,
                           Double(current) * 12_000 / 1_000_000)
            XCTAssertFalse(result.resolution.userVisibleEligible)
        }
        let keys = try XCTUnwrap(backend.requestedKeys.first)
        XCTAssertEqual(keys.count, 12)
        XCTAssertEqual(Set(keys).count, keys.count)
    }

    func testSharedSampleDoesNotReuseBatteryOrUSBValuesAfterRemoval() throws {
        var properties = telemetryProperties()
        properties["PowerOutDetails"] = [["Watts": 7_000]]
        let backend = RuntimeBatteryBackend(properties: properties)
        let reader = AppleSmartBatteryPowerObservationReader(
            backend: backend,
            clock: RuntimeClock(values: Array(0..<10)).next,
            lowPowerMode: { false }
        )
        XCTAssertEqual(reader.readRuntimeSample().visibleSnapshot?.deviceOutputW, 7)
        backend.properties.removeValue(forKey: "PowerOutDetails")
        let removed = reader.readRuntimeSample()
        XCTAssertNil(removed.visibleSnapshot?.deviceOutputW)
        XCTAssertEqual(removed.observation.deviceOutput.fieldPresence, .missing)

        backend.properties.removeValue(forKey: "CurrentCapacity")
        let partial = reader.readRuntimeSample()
        XCTAssertNil(partial.visibleSnapshot)
        XCTAssertEqual(partial.observation.servicePresence, .present)
        XCTAssertEqual(partial.observation.voltageMillivolts.value, 12_000)

        backend.servicePresent = false
        let absent = reader.readRuntimeSample()
        XCTAssertNil(absent.visibleSnapshot)
        XCTAssertEqual(absent.observation.servicePresence, .missing)
    }

    func testSharedBatteryAcquisitionStillRunsConcurrentlyWithHelper() {
        let batteryStarted = DispatchSemaphore(value: 0)
        let helperStarted = DispatchSemaphore(value: 0)
        let backend = RuntimeBatteryBackend(properties: telemetryProperties())
        backend.onRead = {
            batteryStarted.signal()
            XCTAssertEqual(helperStarted.wait(timeout: .now() + 2), .success)
        }
        let runtime = PowerObservationRuntimeController(
            batteryReader: AppleSmartBatteryPowerObservationReader(
                backend: backend, lowPowerMode: { false }
            ),
            helperObservation: { _ in
                helperStarted.signal()
                XCTAssertEqual(batteryStarted.wait(timeout: .now() + 2), .success)
                return .failed(.legacyV4Unavailable)
            },
            clock: { 100 },
            shadowRecorder: RuntimeShadowRecorder()
        )
        XCTAssertNotNil(runtime.sample(event: .normal).visibleSnapshot)
        XCTAssertEqual(backend.requestedKeys.count, 1)
    }

    func testReaderRejectsMalformedAndOversizedDeviceOutputWithoutInventingZero() {
        for details: Any in ["invalid", Array(repeating: ["Watts": 0], count: 65)] {
            var properties = telemetryProperties()
            properties["PowerOutDetails"] = details
            let reader = AppleSmartBatteryPowerObservationReader(
                backend: RuntimeBatteryBackend(properties: properties),
                clock: RuntimeClock(values: [0, 10]).next
            )
            let observation = reader.readObservation()
            XCTAssertEqual(observation.servicePresence, .present)
            XCTAssertEqual(observation.deviceOutput.fieldPresence, .invalid)
            XCTAssertEqual(observation.deviceOutput.measuredTotalWatts.presence, .invalid)
            XCTAssertNil(observation.deviceOutput.measuredTotalWatts.watts)
            XCTAssertTrue(observation.deviceOutput.ports.isEmpty)
        }
    }

    private func makeRuntime(
        snapshot: PowerSnapshot,
        helperResult: @escaping (UInt64) -> HelperPowerObservationFetchResult
    ) -> PowerObservationRuntimeController {
        PowerObservationRuntimeController(
            batteryReader: RuntimeBatteryReader(
                observation: missingBattery(), snapshot: snapshot
            ),
            helperObservation: helperResult,
            clock: RuntimeClock(values: [100, 200]).next,
            shadowRecorder: RuntimeShadowRecorder()
        )
    }

    private func snapshot(
        adapter: Double,
        battery: Double,
        system: Double
    ) -> PowerSnapshot {
        var value = PowerSnapshot()
        value.percent = 70
        value.plugged = adapter > 0
        value.adapterW = adapter
        value.batteryW = battery
        value.systemW = system
        return value
    }

    private func missingBattery() -> AppleSmartBatteryObservation {
        .canonicalFixtureMissing(capture: try! MonotonicInterval(
            startedContinuousNanoseconds: 0,
            endedContinuousNanoseconds: 0
        ))
    }

    private func batteryWithSignedVI(
        voltage: Int64,
        instantCurrent: Int64?,
        averageCurrent: Int64?
    ) throws -> AppleSmartBatteryObservation {
        let capture = try MonotonicInterval(
            startedContinuousNanoseconds: 10,
            endedContinuousNanoseconds: 20
        )
        let missing = AppleSmartBatteryObservation
            .canonicalFixtureMissing(capture: capture)
        return AppleSmartBatteryObservation(
            servicePresence: .present,
            capture: capture,
            currentCapacity: missing.currentCapacity,
            maxCapacity: missing.maxCapacity,
            externalConnected: missing.externalConnected,
            isCharging: missing.isCharging,
            voltageMillivolts: try Observed(
                identifier: "battery.voltageMillivolts",
                source: .appleSmartBatteryRegistry,
                kind: .measured,
                unit: .millivolts,
                presence: .present,
                value: voltage,
                capture: capture,
                freshness: .unknown(at: 20),
                validationIssue: nil
            ),
            instantAmperageMilliamps: try instantCurrent.map {
                try Observed(
                    identifier: "battery.instantAmperageMilliamps",
                    source: .appleSmartBatteryRegistry,
                    kind: .measured,
                    unit: .milliamps,
                    presence: .present,
                    value: $0,
                    capture: capture,
                    freshness: .unknown(at: 20),
                    validationIssue: nil
                )
            } ?? missing.instantAmperageMilliamps,
            averageAmperageMilliamps: try averageCurrent.map {
                try Observed(
                    identifier: "battery.averageAmperageMilliamps",
                    source: .appleSmartBatteryRegistry,
                    kind: .measured,
                    unit: .milliamps,
                    presence: .present,
                    value: $0,
                    capture: capture,
                    freshness: .unknown(at: 20),
                    validationIssue: nil
                )
            } ?? missing.averageAmperageMilliamps,
            powerTelemetry: missing.powerTelemetry,
            adapterCapability: missing.adapterCapability,
            deviceOutput: missing.deviceOutput
        )
    }

    private func telemetryProperties() -> [String: Any] {
        [
            "CurrentCapacity": NSNumber(value: 70),
            "MaxCapacity": NSNumber(value: 100),
            "ExternalConnected": NSNumber(value: true),
            "IsCharging": NSNumber(value: true),
            "Voltage": NSNumber(value: 12_000),
            "InstantAmperage": NSNumber(value: 1_000),
            "Amperage": NSNumber(value: 900),
            "PowerTelemetryData": [
                "SystemPowerIn": NSNumber(value: 50_000),
                "SystemLoad": NSNumber(value: 40_000),
                "BatteryPower": NSNumber(value: 10_000),
                "SystemVoltageIn": NSNumber(value: 20_000),
                "SystemCurrentIn": NSNumber(value: 2_000),
            ],
        ]
    }

    private func response(
        sequence: UInt64,
        pdtr: Double?,
        pstr: Double?
    ) -> PowerObservationV5Response {
        let connection = PowerObservationV5Connection(
            status: .opened,
            startedContinuousNanoseconds: 100,
            endedContinuousNanoseconds: 110,
            ioReturn: 0,
            validationIssue: nil
        )
        return PowerObservationV5Response(
            wattsonProtocol: 5,
            ok: true,
            partial: pdtr == nil || pstr == nil,
            clientSequence: sequence,
            clock: PowerObservationV5Response.clockName,
            error: nil,
            connection: connection,
            keys: [
                key("PDTR", source: .smcPDTR, watts: pdtr),
                key("PSTR", source: .smcPSTR, watts: pstr),
                key("PPBR", source: .smcPPBR, watts: 2),
            ]
        )
    }

    private func key(
        _ name: String,
        source: ObservationSource,
        watts: Double?
    ) -> PowerObservationV5Key {
        PowerObservationV5Key(
            key: name,
            source: source,
            status: watts == nil ? .keyUnavailable : .present,
            startedContinuousNanoseconds: 100,
            endedContinuousNanoseconds: 101,
            dataTypeFourCC: watts == nil ? nil : "flt ",
            rawBytesHex: watts == nil ? nil : "00000000",
            decodedWatts: watts,
            ioReturn: watts == nil ? -1 : 0,
            validationIssue: watts == nil ? "key unavailable" : nil
        )
    }
}

private final class RuntimeClock {
    private var values: [UInt64]
    private let lock = NSLock()

    init(values: [UInt64]) {
        self.values = values
    }

    func next() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return values.isEmpty ? 0 : values.removeFirst()
    }
}

private final class RuntimeBatteryReader:
    AppleSmartBatteryPowerObservationReading
{
    let observation: AppleSmartBatteryObservation
    let snapshot: PowerSnapshot?
    private(set) var resetCount = 0

    init(observation: AppleSmartBatteryObservation, snapshot: PowerSnapshot?) {
        self.observation = observation
        self.snapshot = snapshot
    }

    func readRuntimeSample() -> AppleSmartBatteryPowerSample {
        AppleSmartBatteryPowerSample(
            visibleSnapshot: snapshot, observation: observation
        )
    }

    func resetFreshness() {
        resetCount += 1
    }
}

private final class RuntimeBatteryBackend:
    AppleSmartBatteryPowerRawSnapshotReading
{
    var properties: [String: Any]
    var servicePresent = true
    var onRead: (() -> Void)?
    private(set) var requestedKeys: [[String]] = []

    init(properties: [String: Any]) {
        self.properties = properties
    }

    func readAllowlistedProperties(
        _ keys: [String]
    ) -> AppleSmartBatteryPowerRawSnapshot {
        requestedKeys.append(keys)
        onRead?()
        return AppleSmartBatteryPowerRawSnapshot(
            servicePresent: servicePresent,
            properties: properties.filter { keys.contains($0.key) }
        )
    }
}

private final class RuntimeShadowRecorder: PowerObservationShadowRecording {
    private(set) var comparisons: [PowerShadowComparison] = []

    func record(_ comparison: PowerShadowComparison) {
        comparisons.append(comparison)
    }
}
