import XCTest
@testable import Wattson

final class PowerObservationFusionReplayTests: XCTestCase {
    func testReplayGeneratesCandidatesWithoutSelectingWhenPolicyIsNil() throws {
        let observation = try fixtureObservation(pstr: 36.44, systemLoad: 101.976)
        var replay = PowerObservationFusionReplay()
        let output = replay.consume(
            PowerFusionReplayInput(observation: observation),
            policy: nil
        )
        guard case let .policyUnavailable(raw, candidates) = output.pstrDecision else {
            return XCTFail("nil policy must keep replay shadow-only")
        }
        XCTAssertEqual(raw, 36.44)
        XCTAssertEqual(candidates, [36.44, 101.976, 167.512, 233.048])
        XCTAssertFalse(output.resolution.userVisibleEligible)
    }

    func testReplayCarriesLegacyComparisonWithoutChangingVisibleValues() throws {
        let observation = try fixtureObservation(pstr: 40, systemLoad: 45)
        var replay = PowerObservationFusionReplay()
        let output = replay.consume(
            PowerFusionReplayInput(
                observation: observation,
                legacyVisible: LegacyVisiblePower(adapterW: 60, batteryW: 15, systemW: 45)
            ),
            policy: nil
        )
        XCTAssertEqual(output.shadowComparison?.adapter.legacyWatts, 60)
        XCTAssertEqual(output.shadowComparison?.system.legacyWatts, 45)
        XCTAssertEqual(output.shadowComparison?.userVisibleValuesUnchanged, true)
    }

    func testReplayResetClearsBandPersistence() throws {
        let observation = try fixtureObservation(pstr: 36.44, systemLoad: 101.976)
        let policy = PSTRBandPolicy(
            maximumAnchorSkewMilliseconds: 10,
            maximumUnchangedAnchorMilliseconds: nil,
            maximumBestCandidateErrorWatts: 0.01,
            minimumRunnerUpMarginWatts: 10,
            requiredConsecutiveSamples: 2,
            maximumPersistenceGapMilliseconds: 1_000
        )
        var replay = PowerObservationFusionReplay()
        let first = replay.consume(PowerFusionReplayInput(observation: observation), policy: policy)
        guard case .pending = first.pstrDecision else { return XCTFail("first sample should be pending") }
        replay.reset()
        let second = replay.consume(PowerFusionReplayInput(observation: observation), policy: policy)
        guard case let .pending(_, _, _, count, _) = second.pstrDecision else {
            return XCTFail("reset must clear persistence")
        }
        XCTAssertEqual(count, 1)
    }

    private func fixtureObservation(
        pstr: Double,
        systemLoad: Double
    ) throws -> RawPowerObservation {
        let capture = try MonotonicInterval(
            startedContinuousNanoseconds: 100,
            endedContinuousNanoseconds: 110
        )
        let changed = try FreshnessEvidence(
            evaluatedAtContinuousNanoseconds: 110,
            ageMilliseconds: nil,
            updateToken: "token",
            unchangedSinceContinuousNanoseconds: 110,
            unchangedForMilliseconds: 0,
            assessment: .changed,
            basis: .derivedUpdateToken
        )
        let systemReading = try PowerReading(
            identifier: "battery.powerTelemetry.systemLoad",
            source: .appleSmartBatteryPowerTelemetry,
            kind: .measured,
            semantic: .systemLoad,
            presence: .present,
            rawInteger: Int64((systemLoad * 1_000).rounded()),
            rawFloatingPoint: nil,
            rawUnit: .milliwatts,
            watts: systemLoad,
            capture: capture,
            freshness: changed,
            validationIssue: nil
        )
        let telemetry = BatteryPowerTelemetryObservation(
            presence: .present,
            capture: capture,
            systemPowerIn: .canonicalFixtureMissing(
                identifier: "battery.powerTelemetry.systemPowerIn",
                source: .appleSmartBatteryPowerTelemetry,
                kind: .measured,
                semantic: .systemInput,
                capture: capture
            ),
            systemLoad: systemReading,
            batteryPower: .canonicalFixtureMissing(
                identifier: "battery.powerTelemetry.batteryPower",
                source: .appleSmartBatteryPowerTelemetry,
                kind: .measured,
                semantic: .firmwareBatteryPowerUnresolvedSign,
                capture: capture
            ),
            systemVoltageInNative: .canonicalFixtureMissing(
                identifier: "battery.powerTelemetry.systemVoltageIn",
                source: .appleSmartBatteryPowerTelemetry,
                kind: .raw,
                unit: .registryNative,
                capture: capture
            ),
            systemCurrentInNative: .canonicalFixtureMissing(
                identifier: "battery.powerTelemetry.systemCurrentIn",
                source: .appleSmartBatteryPowerTelemetry,
                kind: .raw,
                unit: .registryNative,
                capture: capture
            ),
            updateToken: "token",
            freshness: changed
        )
        var battery = AppleSmartBatteryObservation.canonicalFixtureMissing(capture: capture)
        battery = AppleSmartBatteryObservation(
            servicePresence: .present,
            capture: capture,
            currentCapacity: battery.currentCapacity,
            maxCapacity: battery.maxCapacity,
            externalConnected: battery.externalConnected,
            isCharging: battery.isCharging,
            voltageMillivolts: battery.voltageMillivolts,
            instantAmperageMilliamps: battery.instantAmperageMilliamps,
            averageAmperageMilliamps: battery.averageAmperageMilliamps,
            powerTelemetry: telemetry,
            adapterCapability: battery.adapterCapability,
            deviceOutput: battery.deviceOutput
        )
        let pstrKey = SMCKeyObservation(
            key: "PSTR",
            source: .smcPSTR,
            status: .present,
            capture: capture,
            dataTypeFourCC: "flt ",
            rawBytesHex: "00000000",
            decodedWatts: pstr,
            ioReturn: nil,
            validationIssue: nil
        )
        let smc = try SMCObservation(
            connectionStatus: .opened,
            connectionCapture: capture,
            keys: [
                .canonicalFixtureMissing(key: "PDTR", source: .smcPDTR, capture: capture),
                pstrKey,
                .canonicalFixtureMissing(key: "PPBR", source: .smcPPBR, capture: capture),
            ]
        )
        let anchors = [ModuloAnchor(
            identifier: systemReading.identifier,
            source: systemReading.source,
            watts: systemLoad,
            capture: capture
        )]
        let evidence = RawPowerEvidence(
            batteryVoltageTimesCurrent: .canonicalFixtureMissing(
                identifier: "evidence.batteryVoltageTimesCurrent",
                source: .derivedBatteryVI,
                kind: .derived,
                semantic: .batteryVoltageTimesCurrent,
                capture: capture
            ),
            systemVoltageTimesCurrent: .canonicalFixtureMissing(
                identifier: "evidence.systemVoltageTimesCurrent",
                source: .derivedSystemInputVI,
                kind: .derived,
                semantic: .systemVoltageTimesCurrent,
                capture: capture
            ),
            timing: ObservationTimingEvidence(
                observationStartedContinuousNanoseconds: 100,
                observationEndedContinuousNanoseconds: 110,
                totalCaptureDurationMilliseconds: 0.000_01,
                smcKeySkewMilliseconds: nil,
                batteryMidpointMinusSMCMidpointMilliseconds: 0,
                absoluteBatterySMCSkewMilliseconds: 0
            ),
            pstrModulo: PSTRModuloEvidence(rawPSTRWatts: pstr, anchors: anchors),
            balances: []
        )
        return try RawPowerObservation(
            sequence: 1,
            scenario: "replay",
            finalizedAtContinuousNanoseconds: 110,
            battery: battery,
            smc: smc,
            evidence: evidence
        )
    }
}
