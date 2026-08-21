import Foundation
import XCTest
@testable import Wattson

final class RawPowerObservationTests: XCTestCase {
    private let traceDecoder = PowerObservationTraceDecoder()

    private func fixtureData(_ name: String) throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(
                forResource: name,
                withExtension: nil,
                subdirectory: "Fixtures/PowerObservations"
            ),
            "missing fixture \(name)"
        )
        return try Data(contentsOf: url)
    }

    private func summary(_ name: String) throws -> PowerObservationTraceDecodingSummary {
        traceDecoder.decodeJSONL(try fixtureData(name))
    }

    private func jsonObject<T: Encodable>(
        _ value: T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(value)
        )
        return try XCTUnwrap(
            object as? [String: Any],
            file: file,
            line: line
        )
    }

    private func jsonData(
        _ object: [String: Any]
    ) throws -> Data {
        try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys]
        )
    }

    private func settingJSONValue(
        _ value: Any,
        at path: [String],
        in object: [String: Any],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> [String: Any] {
        let key = try XCTUnwrap(
            path.first,
            "JSON mutation path must not be empty",
            file: file,
            line: line
        )
        var result = object
        if path.count == 1 {
            result[key] = value
            return result
        }
        let nested = try XCTUnwrap(
            result[key] as? [String: Any],
            "missing JSON object at \(key)",
            file: file,
            line: line
        )
        result[key] = try settingJSONValue(
            value,
            at: Array(path.dropFirst()),
            in: nested,
            file: file,
            line: line
        )
        return result
    }

    private func assertRawObservationDecodeFails(
        _ object: [String: Any],
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                RawPowerObservation.self,
                from: jsonData(object)
            ),
            message,
            file: file,
            line: line
        )
    }

    private func assertRequiredNullableKey<T: Codable>(
        _ key: String,
        in value: T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        var object = try jsonObject(value, file: file, line: line)
        XCTAssertTrue(
            object.keys.contains(key),
            "required nullable key \(key) was not encoded",
            file: file,
            line: line
        )
        XCTAssertTrue(
            object[key] is NSNull,
            "required nullable key \(key) was not explicit null",
            file: file,
            line: line
        )
        object.removeValue(forKey: key)
        XCTAssertThrowsError(
            try JSONDecoder().decode(T.self, from: jsonData(object)),
            "missing required nullable key \(key) decoded successfully",
            file: file,
            line: line
        )
    }

    private func assertRequiredNullableKeys<T: Codable>(
        _ keys: [String],
        in value: T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        for key in keys {
            try assertRequiredNullableKey(
                key,
                in: value,
                file: file,
                line: line
            )
        }
    }

    private func assertEncodedKeys<T: Encodable>(
        _ value: T,
        _ expected: Set<String>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        assertKeys(
            try jsonObject(value, file: file, line: line),
            expected,
            file: file,
            line: line
        )
    }

    private func assertKeys(
        _ object: [String: Any],
        _ expected: Set<String>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            Set(object.keys),
            expected,
            file: file,
            line: line
        )
    }

    private func assertMalformed(
        _ event: PowerObservationTraceDecodeEvent,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .malformed = event else {
            XCTFail(
                "expected malformed event, got \(event)",
                file: file,
                line: line
            )
            return
        }
    }

    private func sample(
        _ name: String,
        sequence: UInt64 = 0
    ) throws -> RawPowerObservation {
        let decoded = try summary(name)
        XCTAssertFalse(
            decoded.events.contains { event in
                if case .malformed = event { return true }
                return false
            },
            "fixture \(name) contains an unexpected malformed record"
        )
        return try XCTUnwrap(
            decoded.samples.first { $0.sequence == sequence }
        )
    }


    private func assertEqual(
        _ actual: Double?,
        _ expected: Double,
        accuracy: Double = 0.000_001,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertEqual(
            try XCTUnwrap(actual, file: file, line: line),
            expected,
            accuracy: accuracy,
            file: file,
            line: line
        )
    }

    private func canonicalHeader(_ scenario: String) -> PowerObservationTraceHeader {
        PowerObservationTraceHeader(
            captureTool: "WattsonPowerObservationFixture",
            captureToolVersion: 1,
            scenario: scenario,
            requestedIntervalMilliseconds: 250,
            requestedDurationSeconds: 1,
            startedContinuousNanoseconds: 0,
            macModel: "FixtureMac",
            architecture: "arm64",
            operatingSystemVersion: "26.5.2",
            operatingSystemBuild: "25F84"
        )
    }

    private func interval(
        _ start: UInt64 = 0,
        _ end: UInt64? = nil
    ) throws -> MonotonicInterval {
        try MonotonicInterval(
            startedContinuousNanoseconds: start,
            endedContinuousNanoseconds: end ?? start
        )
    }

    private func unknownFreshness(_ time: UInt64 = 0) -> FreshnessEvidence {
        .unknown(at: time)
    }

    private func powerReading(
        identifier: String,
        source: ObservationSource,
        kind: ObservationKind,
        semantic: PowerSemantic,
        rawInteger: Int64? = nil,
        rawUnit: ObservationUnit? = nil,
        watts: Double? = nil,
        capture: MonotonicInterval
    ) throws -> PowerReading {
        try PowerReading(
            identifier: identifier,
            source: source,
            kind: kind,
            semantic: semantic,
            presence: .present,
            rawInteger: rawInteger,
            rawFloatingPoint: nil,
            rawUnit: rawUnit,
            watts: watts,
            capture: capture,
            freshness: unknownFreshness(capture.endedContinuousNanoseconds),
            validationIssue: nil
        )
    }

    private func presentSMCKey(
        _ key: String,
        source: ObservationSource,
        watts: Double,
        capture: MonotonicInterval
    ) -> SMCKeyObservation {
        SMCKeyObservation(
            key: key,
            source: source,
            status: .present,
            capture: capture,
            dataTypeFourCC: "flt ",
            rawBytesHex: "00000000",
            decodedWatts: watts,
            ioReturn: 0,
            validationIssue: nil
        )
    }

    func testCompleteIOKitTupleAndRawPSTRAreBothPreserved() throws {
        let observation = try sample("complete-iokit-lower-pstr-v1.jsonl")
        let telemetry = observation.battery.powerTelemetry

        XCTAssertEqual(telemetry.systemPowerIn.rawInteger, 117_388)
        XCTAssertEqual(telemetry.systemPowerIn.rawUnit, .milliwatts)
        XCTAssertNil(telemetry.systemPowerIn.rawFloatingPoint)
        try assertEqual(telemetry.systemPowerIn.watts, 117.388)
        XCTAssertEqual(telemetry.systemLoad.rawInteger, 101_850)
        XCTAssertEqual(telemetry.systemLoad.rawUnit, .milliwatts)
        XCTAssertNil(telemetry.systemLoad.rawFloatingPoint)
        try assertEqual(telemetry.systemLoad.watts, 101.850)
        XCTAssertEqual(telemetry.batteryPower.rawInteger, 15_538)
        XCTAssertEqual(telemetry.batteryPower.rawUnit, .milliwatts)
        XCTAssertNil(telemetry.batteryPower.rawFloatingPoint)
        try assertEqual(telemetry.batteryPower.watts, 15.538)
        let pstr = try XCTUnwrap(observation.smc.key("PSTR"))
        XCTAssertEqual(pstr.status, .present)
        XCTAssertEqual(pstr.source, .smcPSTR)
        XCTAssertEqual(pstr.dataTypeFourCC, "flt ")
        XCTAssertEqual(pstr.ioReturn, 0)
        let rawBytes = try XCTUnwrap(pstr.rawBytesHex)
        XCTAssertFalse(rawBytes.isEmpty)
        XCTAssertTrue(rawBytes.count.isMultiple(of: 2))
        XCTAssertTrue(
            rawBytes.allSatisfy {
                $0.isNumber || ("A"..."F").contains(String($0))
            }
        )
        try assertEqual(pstr.decodedWatts, 40)

        for reading in [
            telemetry.systemPowerIn,
            telemetry.systemLoad,
            telemetry.batteryPower,
        ] {
            XCTAssertEqual(
                try XCTUnwrap(reading.watts),
                Double(try XCTUnwrap(reading.rawInteger)) / 1_000,
                accuracy: 0.000_001
            )
        }

        let encoded = try JSONEncoder().encode(observation)
        let roundTrip = try JSONDecoder().decode(RawPowerObservation.self, from: encoded)
        XCTAssertEqual(roundTrip, observation)

        let text = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        XCTAssertFalse(text.contains("53.9"))
        XCTAssertFalse(text.contains("fused"))
        XCTAssertFalse(text.contains("corrected"))
        XCTAssertFalse(text.contains("selected"))

        let object = try jsonObject(observation)
        let wrongUnit = try settingJSONValue(
            "watts",
            at: [
                "battery",
                "powerTelemetry",
                "systemPowerIn",
                "rawUnit",
            ],
            in: object
        )
        try assertRawObservationDecodeFails(
            wrongUnit,
            "SystemPowerIn must retain its milliwatt raw unit"
        )

        let wrongConversion = try settingJSONValue(
            117.0,
            at: [
                "battery",
                "powerTelemetry",
                "systemPowerIn",
                "watts",
            ],
            in: object
        )
        try assertRawObservationDecodeFails(
            wrongConversion,
            "SystemPowerIn watts must equal raw milliwatts divided by 1000"
        )

        let invalidProgrammaticReading = try PowerReading(
            identifier: "battery.powerTelemetry.systemPowerIn",
            source: .appleSmartBatteryPowerTelemetry,
            kind: .measured,
            semantic: .systemInput,
            presence: .present,
            rawInteger: 117_388,
            rawFloatingPoint: nil,
            rawUnit: .watts,
            watts: 117.388,
            capture: telemetry.systemPowerIn.capture,
            freshness: telemetry.systemPowerIn.freshness,
            validationIssue: nil
        )
        let invalidProgrammaticTelemetry = BatteryPowerTelemetryObservation(
            presence: telemetry.presence,
            capture: telemetry.capture,
            systemPowerIn: invalidProgrammaticReading,
            systemLoad: telemetry.systemLoad,
            batteryPower: telemetry.batteryPower,
            systemVoltageInNative: telemetry.systemVoltageInNative,
            systemCurrentInNative: telemetry.systemCurrentInNative,
            updateToken: telemetry.updateToken,
            freshness: telemetry.freshness
        )
        let battery = observation.battery
        let invalidProgrammaticBattery = AppleSmartBatteryObservation(
            servicePresence: battery.servicePresence,
            capture: battery.capture,
            currentCapacity: battery.currentCapacity,
            maxCapacity: battery.maxCapacity,
            externalConnected: battery.externalConnected,
            isCharging: battery.isCharging,
            voltageMillivolts: battery.voltageMillivolts,
            instantAmperageMilliamps: battery.instantAmperageMilliamps,
            averageAmperageMilliamps: battery.averageAmperageMilliamps,
            powerTelemetry: invalidProgrammaticTelemetry,
            adapterCapability: battery.adapterCapability,
            deviceOutput: battery.deviceOutput
        )
        XCTAssertThrowsError(
            try RawPowerObservation(
                sequence: observation.sequence,
                scenario: observation.scenario,
                finalizedAtContinuousNanoseconds:
                    observation.finalizedAtContinuousNanoseconds,
                battery: invalidProgrammaticBattery,
                smc: observation.smc,
                evidence: observation.evidence
            ),
            "programmatic construction must enforce the same fixed-field PowerReading contract as decoding"
        )
    }

    func testPSTRModuloEvidenceGeneratesFourCandidatesWithoutSelectingOne() throws {
        let observation = try sample("pstr-modulo-65536-v1.jsonl")
        let modulo = observation.evidence.pstrModulo

        XCTAssertEqual(modulo.status, .candidatesGenerated)
        try assertEqual(modulo.rawPSTRWatts, 36.440)
        XCTAssertEqual(modulo.modulusWatts, 65.536, accuracy: 0)
        XCTAssertEqual(modulo.candidates.map(\.multiple), [0, 1, 2, 3])
        let expected = [36.440, 101.976, 167.512, 233.048]
        for (actual, expectedValue) in zip(modulo.candidates.map(\.candidateWatts), expected) {
            XCTAssertEqual(actual, expectedValue, accuracy: 0.000_001)
        }
        XCTAssertEqual(
            modulo.candidates.map { $0.deltaToAnchorsWatts[0] },
            [-65.536, 0, 65.536, 131.072]
        )
        try assertEqual(
            observation.smc.key("PSTR")?.decodedWatts,
            try XCTUnwrap(modulo.rawPSTRWatts)
        )

        let text = try XCTUnwrap(
            String(data: JSONEncoder().encode(modulo), encoding: .utf8)
        )
        for forbidden in [
            "selectedMultiple",
            "correctedPSTR",
            "unwrappedPSTR",
            "preferredCandidate",
            "resolvedPSTR",
        ] {
            XCTAssertFalse(text.contains(forbidden), forbidden)
        }

        let original = try jsonObject(observation)
        var wrongCandidate = original
        var evidence = try XCTUnwrap(
            wrongCandidate["evidence"] as? [String: Any]
        )
        var moduloObject = try XCTUnwrap(
            evidence["pstrModulo"] as? [String: Any]
        )
        var candidates = try XCTUnwrap(
            moduloObject["candidates"] as? [[String: Any]]
        )
        candidates[0]["candidateWatts"] = 36.441
        moduloObject["candidates"] = candidates
        evidence["pstrModulo"] = moduloObject
        wrongCandidate["evidence"] = evidence
        try assertRawObservationDecodeFails(
            wrongCandidate,
            "serialized PSTR candidates must be recomputed and validated"
        )

        var wrongDelta = original
        evidence = try XCTUnwrap(
            wrongDelta["evidence"] as? [String: Any]
        )
        moduloObject = try XCTUnwrap(
            evidence["pstrModulo"] as? [String: Any]
        )
        candidates = try XCTUnwrap(
            moduloObject["candidates"] as? [[String: Any]]
        )
        candidates[1]["deltaToAnchorsWatts"] = [0.001]
        moduloObject["candidates"] = candidates
        evidence["pstrModulo"] = moduloObject
        wrongDelta["evidence"] = evidence
        try assertRawObservationDecodeFails(
            wrongDelta,
            "serialized PSTR anchor deltas must be signed formula results"
        )

        var wrongModulus = try settingJSONValue(
            64.0,
            at: ["evidence", "pstrModulo", "modulusWatts"],
            in: original
        )
        wrongModulus = try settingJSONValue(
            "insufficientData",
            at: ["evidence", "pstrModulo", "status"],
            in: wrongModulus
        )
        wrongModulus = try settingJSONValue(
            [],
            at: ["evidence", "pstrModulo", "candidates"],
            in: wrongModulus
        )
        wrongModulus = try settingJSONValue(
            "invalid PSTR modulus",
            at: ["evidence", "pstrModulo", "validationIssue"],
            in: wrongModulus
        )
        try assertRawObservationDecodeFails(
            wrongModulus,
            "schema v1 must reject any modulus other than exactly 65.536"
        )

        var crossMismatch = original
        var smc = try XCTUnwrap(
            crossMismatch["smc"] as? [String: Any]
        )
        var keys = try XCTUnwrap(
            smc["keys"] as? [[String: Any]]
        )
        XCTAssertEqual(keys[1]["key"] as? String, "PSTR")
        keys[1]["decodedWatts"] = 40.0
        smc["keys"] = keys
        crossMismatch["smc"] = smc
        try assertRawObservationDecodeFails(
            crossMismatch,
            "direct smc.PSTR and PSTR modulo raw evidence must not disagree"
        )
    }

    func testAsynchronousIntervalsPreserveSignedAndAbsoluteSkewAndNonzeroResidual() throws {
        let observation = try sample("asynchronous-rails-v1.jsonl")
        let timing = observation.evidence.timing
        let balance = try XCTUnwrap(
            observation.evidence.balances.first { $0.identifier == "smc.direct" }
        )

        try assertEqual(timing.smcKeySkewMilliseconds, 750)
        try assertEqual(
            timing.batteryMidpointMinusSMCMidpointMilliseconds,
            -250
        )
        try assertEqual(timing.absoluteBatterySMCSkewMilliseconds, 250)
        try assertEqual(balance.residualWatts, 10)
        try assertEqual(observation.smc.key("PDTR")?.decodedWatts, 80)
        try assertEqual(observation.smc.key("PSTR")?.decodedWatts, 60)
        try assertEqual(
            observation.evidence.batteryVoltageTimesCurrent.watts,
            10
        )

        let oneKeyObservations = [
            try sample("complete-iokit-lower-pstr-v1.jsonl"),
            try sample("pstr-modulo-65536-v1.jsonl"),
            try sample("presence-transitions-v1.jsonl", sequence: 0),
            try sample("presence-transitions-v1.jsonl", sequence: 1),
            try sample("presence-transitions-v1.jsonl", sequence: 3),
        ]
        for oneKey in oneKeyObservations {
            XCTAssertEqual(
                oneKey.smc.keys.filter { $0.status == .present }.count,
                1
            )
            XCTAssertNil(
                oneKey.evidence.timing.smcKeySkewMilliseconds,
                "fewer than two present SMC keys must not synthesize key skew"
            )
            try assertEqual(
                oneKey.evidence.timing
                    .batteryMidpointMinusSMCMidpointMilliseconds,
                0
            )
            try assertEqual(
                oneKey.evidence.timing.absoluteBatterySMCSkewMilliseconds,
                0
            )
        }

        let object = try jsonObject(observation)
        let wrongSMCKeySkew = try settingJSONValue(
            749.0,
            at: ["evidence", "timing", "smcKeySkewMilliseconds"],
            in: object
        )
        try assertRawObservationDecodeFails(
            wrongSMCKeySkew,
            "SMC key skew must be derived from present key capture midpoints"
        )

        var wrongBatterySMCSkew = try settingJSONValue(
            -249.0,
            at: [
                "evidence",
                "timing",
                "batteryMidpointMinusSMCMidpointMilliseconds",
            ],
            in: object
        )
        wrongBatterySMCSkew = try settingJSONValue(
            249.0,
            at: [
                "evidence",
                "timing",
                "absoluteBatterySMCSkewMilliseconds",
            ],
            in: wrongBatterySMCSkew
        )
        try assertRawObservationDecodeFails(
            wrongBatterySMCSkew,
            "battery-SMC skew must be derived from the capture intervals"
        )

        var wrongBalance = object
        var evidenceObject = try XCTUnwrap(
            wrongBalance["evidence"] as? [String: Any]
        )
        var balances = try XCTUnwrap(
            evidenceObject["balances"] as? [[String: Any]]
        )
        balances[0]["residualWatts"] = 11.0
        evidenceObject["balances"] = balances
        wrongBalance["evidence"] = evidenceObject
        try assertRawObservationDecodeFails(
            wrongBalance,
            "smc.direct residual must be recomputed from PDTR, PSTR, and signed battery VI"
        )
    }

    func testMissingPowerOutDetailsIsUnknownRatherThanZero() throws {
        let output = try sample(
            "power-out-presence-matrix-v1.jsonl",
            sequence: 0
        ).battery.deviceOutput
        XCTAssertEqual(output.fieldPresence, .missing)
        XCTAssertTrue(output.ports.isEmpty)
        XCTAssertEqual(output.measuredTotalWatts.presence, .missing)
        XCTAssertNil(output.measuredTotalWatts.watts)
        XCTAssertEqual(output.completeness, .unknown)

    }

    func testInvalidPowerOutDetailsIsUnknownRatherThanZero() throws {
        let output = try sample(
            "power-out-presence-matrix-v1.jsonl",
            sequence: 1
        ).battery.deviceOutput
        XCTAssertEqual(output.fieldPresence, .invalid)
        XCTAssertTrue(output.ports.isEmpty)
        XCTAssertEqual(output.measuredTotalWatts.presence, .invalid)
        XCTAssertNil(output.measuredTotalWatts.watts)
        XCTAssertEqual(output.completeness, .unknown)
    }

    func testExplicitEmptyPowerOutDetailsIsMeasuredZero() throws {
        let output = try sample(
            "power-out-presence-matrix-v1.jsonl",
            sequence: 2
        ).battery.deviceOutput
        XCTAssertEqual(output.fieldPresence, .present)
        XCTAssertTrue(output.ports.isEmpty)
        XCTAssertEqual(output.measuredTotalWatts.presence, .present)
        try assertEqual(output.measuredTotalWatts.watts, 0)
        XCTAssertEqual(output.completeness, .complete)
    }

    func testExplicitZeroWattsIsMeasuredZero() throws {
        let output = try sample(
            "power-out-presence-matrix-v1.jsonl",
            sequence: 3
        ).battery.deviceOutput
        let port = try XCTUnwrap(output.ports.first)
        XCTAssertEqual(port.measuredWatts.presence, .present)
        XCTAssertEqual(port.measuredWatts.rawInteger, 0)
        XCTAssertEqual(port.measuredWatts.rawUnit, .milliwatts)
        try assertEqual(port.measuredWatts.watts, 0)
        try assertEqual(output.measuredTotalWatts.watts, 0)
        XCTAssertEqual(output.completeness, .complete)
    }

    func testOnlyPDPowerRemainsRawAndIsNotMeasuredFallback() throws {
        let output = try sample(
            "power-out-presence-matrix-v1.jsonl",
            sequence: 4
        ).battery.deviceOutput
        let port = try XCTUnwrap(output.ports.first)
        XCTAssertEqual(port.measuredWatts.presence, .missing)
        XCTAssertEqual(port.pdPowerRaw.presence, .present)
        XCTAssertEqual(port.pdPowerRaw.kind, .raw)
        XCTAssertEqual(port.pdPowerRaw.semantic, .unknown)
        XCTAssertEqual(port.pdPowerRaw.rawInteger, 7_300)
        XCTAssertEqual(port.pdPowerRaw.rawUnit, .milliwatts)
        XCTAssertNil(port.pdPowerRaw.watts)
        XCTAssertEqual(output.measuredTotalWatts.presence, .missing)
        XCTAssertNil(output.measuredTotalWatts.watts)
        XCTAssertEqual(output.completeness, .unknown)

        let negativeRaw = try PowerReading(
            identifier: port.pdPowerRaw.identifier,
            source: port.pdPowerRaw.source,
            kind: .raw,
            semantic: .unknown,
            presence: .present,
            rawInteger: -7_300,
            rawFloatingPoint: nil,
            rawUnit: .milliwatts,
            watts: nil,
            capture: port.pdPowerRaw.capture,
            freshness: port.pdPowerRaw.freshness,
            validationIssue: nil
        )
        let negativePort = DeviceOutputPortObservation(
            arrayIndex: port.arrayIndex,
            portIndex: port.portIndex,
            locationIdentifierWasPresent:
                port.locationIdentifierWasPresent,
            measuredWatts: port.measuredWatts,
            pdPowerRaw: negativeRaw
        )
        let negativeOutput = DeviceOutputObservation(
            fieldPresence: .present,
            capture: output.capture,
            ports: [negativePort],
            measuredTotalWatts: output.measuredTotalWatts,
            completeness: .unknown
        )
        let negativeRoundTrip = try JSONDecoder().decode(
            DeviceOutputObservation.self,
            from: JSONEncoder().encode(negativeOutput)
        )
        XCTAssertEqual(
            negativeRoundTrip.ports[0].pdPowerRaw.rawInteger,
            -7_300,
            "raw PDPowermW must preserve its sign"
        )
        XCTAssertNil(negativeRoundTrip.ports[0].pdPowerRaw.watts)
    }

    func testMixedPowerOutEntriesProducePartialMeasuredTotal() throws {
        let observation = try sample(
            "power-out-presence-matrix-v1.jsonl",
            sequence: 5
        )
        let output = observation.battery.deviceOutput
        XCTAssertEqual(output.ports.count, 2)
        try assertEqual(output.ports[0].measuredWatts.watts, 5)
        XCTAssertEqual(output.ports[1].measuredWatts.presence, .invalid)
        XCTAssertEqual(output.ports[1].pdPowerRaw.rawInteger, 3_000)
        XCTAssertNil(output.ports[1].pdPowerRaw.watts)
        XCTAssertTrue(output.ports[1].locationIdentifierWasPresent)
        try assertEqual(output.measuredTotalWatts.watts, 5)
        XCTAssertEqual(output.completeness, .partial)

        var object = try jsonObject(observation)
        var battery = try XCTUnwrap(
            object["battery"] as? [String: Any]
        )
        var outputObject = try XCTUnwrap(
            battery["deviceOutput"] as? [String: Any]
        )
        var ports = try XCTUnwrap(
            outputObject["ports"] as? [[String: Any]]
        )
        var measured = try XCTUnwrap(
            ports[0]["measuredWatts"] as? [String: Any]
        )
        measured["watts"] = 6.0
        ports[0]["measuredWatts"] = measured
        outputObject["ports"] = ports
        var aggregate = try XCTUnwrap(
            outputObject["measuredTotalWatts"] as? [String: Any]
        )
        aggregate["watts"] = 6.0
        outputObject["measuredTotalWatts"] = aggregate
        battery["deviceOutput"] = outputObject
        object["battery"] = battery
        try assertRawObservationDecodeFails(
            object,
            "port Watts must preserve the exact milliwatt-to-watt conversion even when the aggregate matches"
        )
    }

    func testAdapterRatedWattsRemainCapabilityRatherThanMeasuredInput() throws {
        let observation = try sample("adapter-capability-only-v1.jsonl")
        let rated = observation.battery.adapterCapability.ratedWatts
        XCTAssertEqual(rated.presence, .present)
        XCTAssertEqual(rated.kind, .capability)
        XCTAssertEqual(rated.semantic, .adapterCapability)
        try assertEqual(rated.watts, 140)
        XCTAssertEqual(observation.smc.key("PDTR")?.status, .keyUnavailable)
        XCTAssertEqual(
            observation.battery.powerTelemetry.systemPowerIn.presence,
            .missing
        )
        XCTAssertFalse(
            observation.smc.keys.contains {
                $0.status == .present && $0.decodedWatts == 140
            }
        )

        XCTAssertEqual(rated.rawInteger, 140)
        XCTAssertEqual(rated.rawUnit, .watts)
        let wrongUnit = try settingJSONValue(
            "milliwatts",
            at: [
                "battery",
                "adapterCapability",
                "ratedWatts",
                "rawUnit",
            ],
            in: jsonObject(observation)
        )
        try assertRawObservationDecodeFails(
            wrongUnit,
            "AdapterDetails.Watts is a watt-denominated capability, never a milliwatt input measurement"
        )
    }

    func testPresentMissingInvalidAndPresentZeroRoundTripDistinctly() throws {
        let capture = try interval()
        let presentTwelve = try Observed<Int64>(
            identifier: "fixture.value",
            source: .fixtureAnnotation,
            kind: .raw,
            unit: .count,
            presence: .present,
            value: 12,
            capture: capture,
            freshness: unknownFreshness(),
            validationIssue: nil
        )
        let presentZero = try Observed<Int64>(
            identifier: "fixture.value",
            source: .fixtureAnnotation,
            kind: .raw,
            unit: .count,
            presence: .present,
            value: 0,
            capture: capture,
            freshness: unknownFreshness(),
            validationIssue: nil
        )
        let missing = try Observed<Int64>(
            identifier: "fixture.value",
            source: .fixtureAnnotation,
            kind: .raw,
            unit: .count,
            presence: .missing,
            value: nil,
            capture: capture,
            freshness: unknownFreshness(),
            validationIssue: "fixture missing"
        )
        let invalid = try Observed<Int64>(
            identifier: "fixture.value",
            source: .fixtureAnnotation,
            kind: .raw,
            unit: .count,
            presence: .invalid,
            value: nil,
            capture: capture,
            freshness: unknownFreshness(),
            validationIssue: "fixture invalid"
        )

        let values = [presentTwelve, presentZero, missing, invalid]
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let encoded = try values.map(encoder.encode)
        XCTAssertEqual(Set(encoded).count, 4)

        for (original, data) in zip(values, encoded) {
            let decoded = try decoder.decode(Observed<Int64>.self, from: data)
            XCTAssertEqual(decoded, original)
            let object = try XCTUnwrap(
                JSONSerialization.jsonObject(with: data) as? [String: Any]
            )
            XCTAssertNotNil(object["value"])
            XCTAssertNotNil(object["validationIssue"])
        }

        XCTAssertThrowsError(
            try FreshnessEvidence(
                evaluatedAtContinuousNanoseconds: 10,
                ageMilliseconds: -1,
                updateToken: nil,
                unchangedSinceContinuousNanoseconds: nil,
                unchangedForMilliseconds: nil,
                assessment: .unknown,
                basis: .none
            )
        )
        XCTAssertThrowsError(
            try FreshnessEvidence(
                evaluatedAtContinuousNanoseconds: 10,
                ageMilliseconds: nil,
                updateToken: nil,
                unchangedSinceContinuousNanoseconds: 11,
                unchangedForMilliseconds: nil,
                assessment: .unchanged,
                basis: .derivedUpdateToken
            )
        )
        XCTAssertThrowsError(
            try FreshnessEvidence(
                evaluatedAtContinuousNanoseconds: 10,
                ageMilliseconds: nil,
                updateToken: nil,
                unchangedSinceContinuousNanoseconds: nil,
                unchangedForMilliseconds: -0.1,
                assessment: .unchanged,
                basis: .derivedUpdateToken
            )
        )
        XCTAssertThrowsError(
            try FreshnessEvidence(
                evaluatedAtContinuousNanoseconds: 10,
                ageMilliseconds: nil,
                updateToken: nil,
                unchangedSinceContinuousNanoseconds: nil,
                unchangedForMilliseconds: nil,
                assessment: .stale,
                basis: .none
            )
        )
        XCTAssertThrowsError(
            try FreshnessEvidence(
                evaluatedAtContinuousNanoseconds: 10,
                ageMilliseconds: .nan,
                updateToken: nil,
                unchangedSinceContinuousNanoseconds: nil,
                unchangedForMilliseconds: nil,
                assessment: .unknown,
                basis: .none
            )
        )

        var freshnessJSON = try jsonObject(unknownFreshness(10))
        freshnessJSON["ageMilliseconds"] = -1.0
        XCTAssertThrowsError(
            try decoder.decode(
                FreshnessEvidence.self,
                from: jsonData(freshnessJSON)
            )
        )
        freshnessJSON = try jsonObject(unknownFreshness(10))
        freshnessJSON["unchangedSinceContinuousNanoseconds"] = 11
        XCTAssertThrowsError(
            try decoder.decode(
                FreshnessEvidence.self,
                from: jsonData(freshnessJSON)
            )
        )
        freshnessJSON = try jsonObject(unknownFreshness(10))
        freshnessJSON["assessment"] = "stale"
        XCTAssertThrowsError(
            try decoder.decode(
                FreshnessEvidence.self,
                from: jsonData(freshnessJSON)
            )
        )

        XCTAssertThrowsError(
            try Observed<Int64>(
                identifier: "fixture.invalidObserved",
                source: .fixtureAnnotation,
                kind: .raw,
                unit: .count,
                presence: .present,
                value: nil,
                capture: capture,
                freshness: unknownFreshness(),
                validationIssue: nil
            )
        )
        XCTAssertThrowsError(
            try Observed<Int64>(
                identifier: "fixture.invalidObserved",
                source: .fixtureAnnotation,
                kind: .raw,
                unit: .count,
                presence: .missing,
                value: 1,
                capture: capture,
                freshness: unknownFreshness(),
                validationIssue: "fixture missing"
            )
        )
        XCTAssertThrowsError(
            try Observed<Int64>(
                identifier: "fixture.invalidObserved",
                source: .fixtureAnnotation,
                kind: .raw,
                unit: .count,
                presence: .invalid,
                value: 1,
                capture: capture,
                freshness: unknownFreshness(),
                validationIssue: "invalid"
            )
        )
        XCTAssertThrowsError(
            try Observed<Int64>(
                identifier: "fixture.invalidObserved",
                source: .fixtureAnnotation,
                kind: .raw,
                unit: .count,
                presence: .invalid,
                value: nil,
                capture: capture,
                freshness: unknownFreshness(),
                validationIssue: nil
            )
        )
        var observedJSON = try jsonObject(presentZero)
        observedJSON["presence"] = "missing"
        XCTAssertThrowsError(
            try decoder.decode(
                Observed<Int64>.self,
                from: jsonData(observedJSON)
            )
        )
        observedJSON = try jsonObject(invalid)
        observedJSON["validationIssue"] = NSNull()
        XCTAssertThrowsError(
            try decoder.decode(
                Observed<Int64>.self,
                from: jsonData(observedJSON)
            )
        )

        func makePower(
            presence: ObservationPresence,
            rawInteger: Int64?,
            rawFloatingPoint: Double?,
            rawUnit: ObservationUnit?,
            watts: Double?,
            issue: String?
        ) throws -> PowerReading {
            try PowerReading(
                identifier: "fixture.invalidPower",
                source: .fixtureAnnotation,
                kind: .measured,
                semantic: .unknown,
                presence: presence,
                rawInteger: rawInteger,
                rawFloatingPoint: rawFloatingPoint,
                rawUnit: rawUnit,
                watts: watts,
                capture: capture,
                freshness: unknownFreshness(),
                validationIssue: issue
            )
        }
        XCTAssertThrowsError(
            try makePower(
                presence: .present,
                rawInteger: 1,
                rawFloatingPoint: 1,
                rawUnit: .milliwatts,
                watts: 0.001,
                issue: nil
            )
        )
        XCTAssertThrowsError(
            try makePower(
                presence: .present,
                rawInteger: 1,
                rawFloatingPoint: nil,
                rawUnit: nil,
                watts: 0.001,
                issue: nil
            )
        )
        XCTAssertThrowsError(
            try makePower(
                presence: .present,
                rawInteger: nil,
                rawFloatingPoint: nil,
                rawUnit: .watts,
                watts: 1,
                issue: nil
            )
        )
        XCTAssertThrowsError(
            try makePower(
                presence: .present,
                rawInteger: nil,
                rawFloatingPoint: nil,
                rawUnit: nil,
                watts: nil,
                issue: nil
            )
        )
        XCTAssertThrowsError(
            try makePower(
                presence: .missing,
                rawInteger: 1,
                rawFloatingPoint: nil,
                rawUnit: .milliwatts,
                watts: nil,
                issue: "missing"
            )
        )
        XCTAssertThrowsError(
            try makePower(
                presence: .invalid,
                rawInteger: 1,
                rawFloatingPoint: nil,
                rawUnit: .milliwatts,
                watts: 0.001,
                issue: "invalid"
            )
        )
        XCTAssertThrowsError(
            try makePower(
                presence: .invalid,
                rawInteger: 1,
                rawFloatingPoint: nil,
                rawUnit: .milliwatts,
                watts: nil,
                issue: nil
            )
        )
        XCTAssertThrowsError(
            try makePower(
                presence: .present,
                rawInteger: nil,
                rawFloatingPoint: .infinity,
                rawUnit: .watts,
                watts: nil,
                issue: nil
            )
        )
        XCTAssertThrowsError(
            try makePower(
                presence: .present,
                rawInteger: nil,
                rawFloatingPoint: nil,
                rawUnit: nil,
                watts: .nan,
                issue: nil
            )
        )

        let exactInteger = try Observed<Int64>(
            identifier: "fixture.exactInteger",
            source: .fixtureAnnotation,
            kind: .raw,
            unit: .registryNative,
            presence: .present,
            value: 9_007_199_254_740_993,
            capture: capture,
            freshness: unknownFreshness(),
            validationIssue: nil
        )
        XCTAssertEqual(
            try decoder.decode(
                Observed<Int64>.self,
                from: encoder.encode(exactInteger)
            ).value,
            9_007_199_254_740_993
        )
        let signedPower = try PowerReading(
            identifier: "fixture.signedPower",
            source: .fixtureAnnotation,
            kind: .measured,
            semantic: PowerSemantic("future.signed"),
            presence: .present,
            rawInteger: -15_538,
            rawFloatingPoint: nil,
            rawUnit: .milliwatts,
            watts: -15.538,
            capture: capture,
            freshness: unknownFreshness(),
            validationIssue: nil
        )
        XCTAssertEqual(
            try decoder.decode(
                PowerReading.self,
                from: encoder.encode(signedPower)
            ),
            signedPower,
            "raw evidence must preserve signed values rather than applying abs"
        )

        let canonical = RawPowerObservation.canonicalFixture(
            sequence: 0,
            scenario: nil
        )
        var invalidMissingTelemetry = try jsonObject(
            canonical.battery.powerTelemetry
        )
        var invalidMissingFreshness = try XCTUnwrap(
            invalidMissingTelemetry["freshness"] as? [String: Any]
        )
        invalidMissingFreshness["assessment"] = "changed"
        invalidMissingFreshness["basis"] = "derivedUpdateToken"
        invalidMissingTelemetry["freshness"] = invalidMissingFreshness
        XCTAssertThrowsError(
            try decoder.decode(
                BatteryPowerTelemetryObservation.self,
                from: jsonData(invalidMissingTelemetry)
            ),
            "missing PowerTelemetryData must retain canonical unknown freshness"
        )

        let canonicalTelemetry = canonical.battery.powerTelemetry
        var telemetryChildFreshness = try jsonObject(canonicalTelemetry)
        var systemPowerIn = try XCTUnwrap(
            telemetryChildFreshness["systemPowerIn"] as? [String: Any]
        )
        var childFreshness = try XCTUnwrap(
            systemPowerIn["freshness"] as? [String: Any]
        )
        childFreshness["assessment"] = "changed"
        childFreshness["basis"] = "derivedUpdateToken"
        systemPowerIn["freshness"] = childFreshness
        telemetryChildFreshness["systemPowerIn"] = systemPowerIn
        XCTAssertThrowsError(
            try decoder.decode(
                BatteryPowerTelemetryObservation.self,
                from: jsonData(telemetryChildFreshness)
            ),
            "canonical-missing telemetry child must retain unknown freshness"
        )
        var telemetryChildCapture = try jsonObject(canonicalTelemetry)
        systemPowerIn = try XCTUnwrap(
            telemetryChildCapture["systemPowerIn"] as? [String: Any]
        )
        systemPowerIn["capture"] = [
            "startedContinuousNanoseconds": 1,
            "endedContinuousNanoseconds": 1,
        ]
        telemetryChildCapture["systemPowerIn"] = systemPowerIn
        XCTAssertThrowsError(
            try decoder.decode(
                BatteryPowerTelemetryObservation.self,
                from: jsonData(telemetryChildCapture)
            ),
            "canonical-missing telemetry child capture must equal its container capture"
        )

        let canonicalAdapter = canonical.battery.adapterCapability
        var adapterChildFreshness = try jsonObject(canonicalAdapter)
        var ratedWatts = try XCTUnwrap(
            adapterChildFreshness["ratedWatts"] as? [String: Any]
        )
        childFreshness = try XCTUnwrap(
            ratedWatts["freshness"] as? [String: Any]
        )
        childFreshness["assessment"] = "changed"
        childFreshness["basis"] = "derivedUpdateToken"
        ratedWatts["freshness"] = childFreshness
        adapterChildFreshness["ratedWatts"] = ratedWatts
        XCTAssertThrowsError(
            try decoder.decode(
                AdapterCapabilityObservation.self,
                from: jsonData(adapterChildFreshness)
            ),
            "canonical-missing adapter child must retain unknown freshness"
        )
        var adapterChildCapture = try jsonObject(canonicalAdapter)
        ratedWatts = try XCTUnwrap(
            adapterChildCapture["ratedWatts"] as? [String: Any]
        )
        ratedWatts["capture"] = [
            "startedContinuousNanoseconds": 1,
            "endedContinuousNanoseconds": 1,
        ]
        adapterChildCapture["ratedWatts"] = ratedWatts
        XCTAssertThrowsError(
            try decoder.decode(
                AdapterCapabilityObservation.self,
                from: jsonData(adapterChildCapture)
            ),
            "canonical-missing adapter child capture must equal its container capture"
        )

        let canonicalDevice = canonical.battery.deviceOutput
        var deviceChildFreshness = try jsonObject(canonicalDevice)
        var aggregateChild = try XCTUnwrap(
            deviceChildFreshness["measuredTotalWatts"] as? [String: Any]
        )
        childFreshness = try XCTUnwrap(
            aggregateChild["freshness"] as? [String: Any]
        )
        childFreshness["assessment"] = "changed"
        childFreshness["basis"] = "derivedUpdateToken"
        aggregateChild["freshness"] = childFreshness
        deviceChildFreshness["measuredTotalWatts"] = aggregateChild
        XCTAssertThrowsError(
            try decoder.decode(
                DeviceOutputObservation.self,
                from: jsonData(deviceChildFreshness)
            ),
            "canonical-missing Device Output aggregate must retain unknown freshness"
        )
        var deviceChildCapture = try jsonObject(canonicalDevice)
        aggregateChild = try XCTUnwrap(
            deviceChildCapture["measuredTotalWatts"] as? [String: Any]
        )
        aggregateChild["capture"] = [
            "startedContinuousNanoseconds": 1,
            "endedContinuousNanoseconds": 1,
        ]
        deviceChildCapture["measuredTotalWatts"] = aggregateChild
        XCTAssertThrowsError(
            try decoder.decode(
                DeviceOutputObservation.self,
                from: jsonData(deviceChildCapture)
            ),
            "canonical-missing Device Output aggregate capture must equal its container capture"
        )
        let portSource = try XCTUnwrap(
            try sample(
                "power-out-presence-matrix-v1.jsonl",
                sequence: 4
            ).battery.deviceOutput.ports.first
        )
        let nullablePort = DeviceOutputPortObservation(
            arrayIndex: portSource.arrayIndex,
            portIndex: nil,
            locationIdentifierWasPresent:
                portSource.locationIdentifierWasPresent,
            measuredWatts: portSource.measuredWatts,
            pdPowerRaw: portSource.pdPowerRaw
        )
        let nullableBalance = PowerBalanceEvidence(
            identifier: "smc.direct",
            adapterSource: nil,
            systemSource: nil,
            batterySource: nil,
            externalSource: nil,
            residualWatts: nil,
            maximumInputSkewMilliseconds: nil
        )
        let derivedOnlyPower = try PowerReading(
            identifier: "fixture.derivedOnly",
            source: .fixtureAnnotation,
            kind: .derived,
            semantic: PowerSemantic("future.derivedOnly"),
            presence: .present,
            rawInteger: nil,
            rawFloatingPoint: nil,
            rawUnit: nil,
            watts: 1,
            capture: capture,
            freshness: unknownFreshness(),
            validationIssue: nil
        )
        let footer = PowerObservationTraceFooter(
            termination: .completed,
            samplesWritten: 1,
            bytesWritten: 0,
            endedContinuousNanoseconds: 0,
            terminationSignal: nil,
            fatalErrorCode: nil
        )
        let header = canonicalHeader("key-tree")
        let sampleRecord = PowerObservationTraceRecord(sample: canonical)
        let headerRecord = PowerObservationTraceRecord(header: header)
        let footerRecord = PowerObservationTraceRecord(footer: footer)
        let presentPSTR = try XCTUnwrap(
            try sample("complete-iokit-lower-pstr-v1.jsonl")
                .smc.key("PSTR")
        )
        let validModulo = PSTRModuloEvidence(
            rawPSTRWatts: 0,
            anchors: []
        )
        let pstrFixture = try sample("pstr-modulo-65536-v1.jsonl")
        let moduloWithAnchor = pstrFixture.evidence.pstrModulo
        let anchor = try XCTUnwrap(moduloWithAnchor.anchors.first)
        let candidate = try XCTUnwrap(moduloWithAnchor.candidates.first)

        try assertRequiredNullableKeys(
            [
                "ageMilliseconds",
                "updateToken",
                "unchangedSinceContinuousNanoseconds",
                "unchangedForMilliseconds",
            ],
            in: canonical.battery.powerTelemetry.freshness
        )
        try assertRequiredNullableKeys(["value"], in: missing)
        try assertRequiredNullableKeys(
            ["validationIssue"],
            in: presentTwelve
        )
        try assertRequiredNullableKeys(
            [
                "rawInteger",
                "rawFloatingPoint",
                "rawUnit",
                "validationIssue",
            ],
            in: derivedOnlyPower
        )
        try assertRequiredNullableKeys(
            ["watts"],
            in: canonical.evidence.batteryVoltageTimesCurrent
        )
        try assertRequiredNullableKeys(
            ["updateToken"],
            in: canonical.battery.powerTelemetry
        )
        try assertRequiredNullableKeys(["portIndex"], in: nullablePort)
        try assertRequiredNullableKeys(
            [
                "dataTypeFourCC",
                "rawBytesHex",
                "decodedWatts",
                "ioReturn",
            ],
            in: canonical.smc.keys[0]
        )
        try assertRequiredNullableKeys(
            ["validationIssue"],
            in: presentPSTR
        )
        try assertRequiredNullableKeys(
            [
                "smcKeySkewMilliseconds",
                "batteryMidpointMinusSMCMidpointMilliseconds",
                "absoluteBatterySMCSkewMilliseconds",
            ],
            in: canonical.evidence.timing
        )
        try assertRequiredNullableKeys(
            ["rawPSTRWatts"],
            in: canonical.evidence.pstrModulo
        )
        try assertRequiredNullableKeys(
            ["validationIssue"],
            in: validModulo
        )
        try assertRequiredNullableKeys(
            [
                "adapterSource",
                "systemSource",
                "batterySource",
                "externalSource",
                "residualWatts",
                "maximumInputSkewMilliseconds",
            ],
            in: nullableBalance
        )
        try assertRequiredNullableKeys(["scenario"], in: canonical)
        try assertRequiredNullableKeys(
            ["terminationSignal", "fatalErrorCode"],
            in: footer
        )
        try assertRequiredNullableKeys(
            ["header", "footer"],
            in: sampleRecord
        )
        try assertRequiredNullableKeys(
            ["sample", "footer"],
            in: headerRecord
        )
        try assertRequiredNullableKeys(
            ["header", "sample"],
            in: footerRecord
        )

        let recordObject = try jsonObject(sampleRecord)
        assertKeys(
            recordObject,
            ["schemaVersion", "recordType", "header", "sample", "footer"]
        )
        let sampleObject = try XCTUnwrap(
            recordObject["sample"] as? [String: Any]
        )
        assertKeys(
            sampleObject,
            [
                "schemaVersion",
                "sequence",
                "scenario",
                "finalizedAtContinuousNanoseconds",
                "battery",
                "smc",
                "evidence",
            ]
        )
        let batteryObject = try XCTUnwrap(
            sampleObject["battery"] as? [String: Any]
        )
        assertKeys(
            batteryObject,
            [
                "servicePresence",
                "capture",
                "currentCapacity",
                "maxCapacity",
                "externalConnected",
                "isCharging",
                "voltageMillivolts",
                "instantAmperageMilliamps",
                "averageAmperageMilliamps",
                "powerTelemetry",
                "adapterCapability",
                "deviceOutput",
            ]
        )
        let observedObject = try XCTUnwrap(
            batteryObject["currentCapacity"] as? [String: Any]
        )
        assertKeys(
            observedObject,
            [
                "identifier",
                "source",
                "kind",
                "unit",
                "presence",
                "value",
                "capture",
                "freshness",
                "validationIssue",
            ]
        )
        let evidenceObject = try XCTUnwrap(
            sampleObject["evidence"] as? [String: Any]
        )
        assertKeys(
            evidenceObject,
            [
                "batteryVoltageTimesCurrent",
                "systemVoltageTimesCurrent",
                "timing",
                "pstrModulo",
                "balances",
            ]
        )

        try assertEncodedKeys(
            header,
            [
                "captureTool",
                "captureToolVersion",
                "scenario",
                "requestedIntervalMilliseconds",
                "requestedDurationSeconds",
                "startedContinuousNanoseconds",
                "macModel",
                "architecture",
                "operatingSystemVersion",
                "operatingSystemBuild",
            ]
        )
        try assertEncodedKeys(
            footer,
            [
                "termination",
                "samplesWritten",
                "bytesWritten",
                "endedContinuousNanoseconds",
                "terminationSignal",
                "fatalErrorCode",
            ]
        )
        try assertEncodedKeys(
            canonical.battery.powerTelemetry.freshness,
            [
                "evaluatedAtContinuousNanoseconds",
                "ageMilliseconds",
                "updateToken",
                "unchangedSinceContinuousNanoseconds",
                "unchangedForMilliseconds",
                "assessment",
                "basis",
            ]
        )
        try assertEncodedKeys(
            canonical.battery.currentCapacity,
            [
                "identifier",
                "source",
                "kind",
                "unit",
                "presence",
                "value",
                "capture",
                "freshness",
                "validationIssue",
            ]
        )
        try assertEncodedKeys(
            derivedOnlyPower,
            [
                "identifier",
                "source",
                "kind",
                "semantic",
                "presence",
                "rawInteger",
                "rawFloatingPoint",
                "rawUnit",
                "watts",
                "capture",
                "freshness",
                "validationIssue",
            ]
        )
        try assertEncodedKeys(
            canonical.battery.powerTelemetry,
            [
                "presence",
                "capture",
                "systemPowerIn",
                "systemLoad",
                "batteryPower",
                "systemVoltageInNative",
                "systemCurrentInNative",
                "updateToken",
                "freshness",
            ]
        )
        try assertEncodedKeys(
            canonical.battery.adapterCapability,
            [
                "presence",
                "capture",
                "ratedWatts",
                "adapterVoltageNative",
                "adapterCurrentNative",
            ]
        )
        try assertEncodedKeys(
            canonical.battery.deviceOutput,
            [
                "fieldPresence",
                "capture",
                "ports",
                "measuredTotalWatts",
                "completeness",
            ]
        )
        try assertEncodedKeys(
            nullablePort,
            [
                "arrayIndex",
                "portIndex",
                "locationIdentifierWasPresent",
                "measuredWatts",
                "pdPowerRaw",
            ]
        )
        try assertEncodedKeys(
            canonical.smc,
            ["connectionStatus", "connectionCapture", "keys"]
        )
        try assertEncodedKeys(
            canonical.smc.keys[0],
            [
                "key",
                "source",
                "status",
                "capture",
                "dataTypeFourCC",
                "rawBytesHex",
                "decodedWatts",
                "ioReturn",
                "validationIssue",
            ]
        )
        try assertEncodedKeys(
            canonical.evidence.timing,
            [
                "observationStartedContinuousNanoseconds",
                "observationEndedContinuousNanoseconds",
                "totalCaptureDurationMilliseconds",
                "smcKeySkewMilliseconds",
                "batteryMidpointMinusSMCMidpointMilliseconds",
                "absoluteBatterySMCSkewMilliseconds",
            ]
        )
        try assertEncodedKeys(
            moduloWithAnchor,
            [
                "status",
                "rawPSTRWatts",
                "modulusWatts",
                "anchors",
                "candidates",
                "validationIssue",
            ]
        )
        try assertEncodedKeys(
            anchor,
            ["identifier", "source", "watts", "capture"]
        )
        try assertEncodedKeys(
            candidate,
            ["multiple", "candidateWatts", "deltaToAnchorsWatts"]
        )
        try assertEncodedKeys(
            nullableBalance,
            [
                "identifier",
                "adapterSource",
                "systemSource",
                "batterySource",
                "externalSource",
                "residualWatts",
                "maximumInputSkewMilliseconds",
            ]
        )
        try assertEncodedKeys(
            canonical.evidence,
            [
                "batteryVoltageTimesCurrent",
                "systemVoltageTimesCurrent",
                "timing",
                "pstrModulo",
                "balances",
            ]
        )
        try assertEncodedKeys(
            capture,
            ["startedContinuousNanoseconds", "endedContinuousNanoseconds"]
        )
    }

    func testBalanceEvidenceNeverMutatesDirectReadings() throws {
        let capture = try interval()
        let pdtr = presentSMCKey("PDTR", source: .smcPDTR, watts: 100, capture: capture)
        let pstr = presentSMCKey("PSTR", source: .smcPSTR, watts: 40, capture: capture)
        let ppbr = SMCKeyObservation.canonicalFixtureMissing(
            key: "PPBR",
            source: .smcPPBR,
            capture: capture
        )
        let smc = try SMCObservation(
            connectionStatus: .opened,
            connectionCapture: capture,
            keys: [pdtr, pstr, ppbr]
        )
        let batteryVI = try powerReading(
            identifier: "evidence.batteryVoltageTimesCurrent",
            source: .derivedBatteryVI,
            kind: .derived,
            semantic: .batteryVoltageTimesCurrent,
            watts: 15,
            capture: capture
        )
        let balance = PowerBalanceEvidence(
            identifier: "smc.direct",
            adapterSource: .smcPDTR,
            systemSource: .smcPSTR,
            batterySource: .derivedBatteryVI,
            externalSource: nil,
            residualWatts: 45,
            maximumInputSkewMilliseconds: 0
        )
        let canonical = RawPowerEvidence.canonicalFixtureMissing(capture: capture)
        let evidence = RawPowerEvidence(
            batteryVoltageTimesCurrent: batteryVI,
            systemVoltageTimesCurrent: canonical.systemVoltageTimesCurrent,
            timing: ObservationTimingEvidence(
                observationStartedContinuousNanoseconds: 0,
                observationEndedContinuousNanoseconds: 0,
                totalCaptureDurationMilliseconds: 0,
                smcKeySkewMilliseconds: 0,
                batteryMidpointMinusSMCMidpointMilliseconds: nil,
                absoluteBatterySMCSkewMilliseconds: nil
            ),
            pstrModulo: PSTRModuloEvidence(rawPSTRWatts: 40, anchors: []),
            balances: [balance]
        )
        let observation = try RawPowerObservation(
            sequence: 0,
            scenario: "balance-preservation",
            finalizedAtContinuousNanoseconds: 0,
            battery: .canonicalFixtureMissing(capture: capture),
            smc: smc,
            evidence: evidence
        )
        let roundTrip = try JSONDecoder().decode(
            RawPowerObservation.self,
            from: JSONEncoder().encode(observation)
        )

        try assertEqual(roundTrip.smc.key("PDTR")?.decodedWatts, 100)
        try assertEqual(roundTrip.smc.key("PSTR")?.decodedWatts, 40)
        try assertEqual(roundTrip.evidence.batteryVoltageTimesCurrent.watts, 15)
        try assertEqual(roundTrip.evidence.balances[0].residualWatts, 45)

        let pdtrObject = try jsonObject(pdtr)
        for key in ["dataTypeFourCC", "rawBytesHex", "decodedWatts"] {
            var invalidPresent = pdtrObject
            invalidPresent[key] = NSNull()
            XCTAssertThrowsError(
                try JSONDecoder().decode(
                    SMCKeyObservation.self,
                    from: jsonData(invalidPresent)
                ),
                "present SMC key must reject missing \(key)"
            )
        }
        var invalidHex = pdtrObject
        invalidHex["rawBytesHex"] = "aa"
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                SMCKeyObservation.self,
                from: jsonData(invalidHex)
            )
        )
        var failedWithWatts = try jsonObject(ppbr)
        failedWithWatts["decodedWatts"] = 1.0
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                SMCKeyObservation.self,
                from: jsonData(failedWithWatts)
            )
        )

        let invalidProgrammaticPDTR = SMCKeyObservation(
            key: "PDTR",
            source: .smcPDTR,
            status: .present,
            capture: capture,
            dataTypeFourCC: nil,
            rawBytesHex: nil,
            decodedWatts: nil,
            ioReturn: 0,
            validationIssue: nil
        )
        let invalidProgrammaticSMC = try SMCObservation(
            connectionStatus: .opened,
            connectionCapture: capture,
            keys: [invalidProgrammaticPDTR, pstr, ppbr]
        )
        XCTAssertThrowsError(
            try RawPowerObservation(
                sequence: 1,
                scenario: "invalid-programmatic-smc",
                finalizedAtContinuousNanoseconds: 0,
                battery: .canonicalFixtureMissing(capture: capture),
                smc: invalidProgrammaticSMC,
                evidence: evidence
            ),
            "RawPowerObservation initializer must recursively reject invalid SMC key state"
        )

        let negativePPBR = SMCKeyObservation(
            key: "PPBR",
            source: .smcPPBR,
            status: .present,
            capture: capture,
            dataTypeFourCC: "flt ",
            rawBytesHex: "BF800000",
            decodedWatts: -1,
            ioReturn: 0,
            validationIssue: nil
        )
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                SMCKeyObservation.self,
                from: JSONEncoder().encode(negativePPBR)
            ),
            "present PPBR is a discharge magnitude and must reject negative decoded watts"
        )
    }

    func testUnknownObservationSourceRoundTripsVerbatim() throws {
        let observation = try sample("unknown-fields-and-source-v1.jsonl")
        let source = observation.evidence.batteryVoltageTimesCurrent.source
        XCTAssertEqual(source.rawValue, "smc.FUTURE")

        let data = try JSONEncoder().encode(observation)
        let roundTrip = try JSONDecoder().decode(RawPowerObservation.self, from: data)
        XCTAssertEqual(
            roundTrip.evidence.batteryVoltageTimesCurrent.source.rawValue,
            "smc.FUTURE"
        )

        var object = try jsonObject(observation)
        object = try settingJSONValue(
            "future.semantic.v2",
            at: [
                "evidence",
                "batteryVoltageTimesCurrent",
                "semantic",
            ],
            in: object
        )
        let semanticRoundTrip = try JSONDecoder().decode(
            RawPowerObservation.self,
            from: jsonData(object)
        )
        XCTAssertEqual(
            semanticRoundTrip.evidence.batteryVoltageTimesCurrent
                .semantic.rawValue,
            "future.semantic.v2"
        )
        let semanticReencoded = try JSONDecoder().decode(
            RawPowerObservation.self,
            from: JSONEncoder().encode(semanticRoundTrip)
        )
        XCTAssertEqual(
            semanticReencoded.evidence.batteryVoltageTimesCurrent
                .semantic.rawValue,
            "future.semantic.v2"
        )
    }

    func testTraceDecoderIgnoresUnknownJSONFields() throws {
        let decoded = try summary("unknown-fields-and-source-v1.jsonl")
        XCTAssertEqual(decoded.samples.count, 1)
        XCTAssertFalse(decoded.events.contains { event in
            if case .malformed = event { return true }
            return false
        })
    }

    func testTraceDecoderSkipsUnknownRecordTypeAndContinues() throws {
        let decoded = try summary("unknown-record-type-v1.jsonl")
        XCTAssertEqual(decoded.records.count, 3)
        XCTAssertEqual(decoded.samples.count, 1)
        XCTAssertTrue(decoded.events.contains { event in
            guard case let .skippedUnknownRecordType(
                lineNumber,
                schemaVersion,
                recordType
            ) = event else { return false }
            return lineNumber == 2
                && schemaVersion == 1
                && recordType == "calibration"
        })

        let canonical = RawPowerObservation.canonicalFixture(
            sequence: 0,
            scenario: "payload-validation"
        )
        let record = PowerObservationTraceRecord(sample: canonical)
        let original = try jsonObject(record)

        var missingSample = original
        missingSample["sample"] = NSNull()
        assertMalformed(
            traceDecoder.decodeTerminatedLine(
                try jsonData(missingSample),
                lineNumber: 10
            )
        )

        var sampleWithHeader = original
        sampleWithHeader["header"] = try jsonObject(
            canonicalHeader("payload-validation")
        )
        assertMalformed(
            traceDecoder.decodeTerminatedLine(
                try jsonData(sampleWithHeader),
                lineNumber: 11
            )
        )

        for payloadKey in ["header", "sample", "footer"] {
            var missingRequiredPayloadKey = original
            missingRequiredPayloadKey.removeValue(forKey: payloadKey)
            assertMalformed(
                traceDecoder.decodeTerminatedLine(
                    try jsonData(missingRequiredPayloadKey),
                    lineNumber: 12
                )
            )
        }
    }

    func testTraceDecoderReportsUnsupportedFutureSchema() throws {
        let decoded = try summary("future-schema-v99.jsonl")
        XCTAssertEqual(decoded.records.count, 0)
        XCTAssertEqual(
            decoded.events,
            [.unsupportedSchema(lineNumber: 1, schemaVersion: 99)]
        )

        for invalidSchema in [0, -1] {
            let data = Data(
                "{\"recordType\":\"sample\",\"schemaVersion\":\(invalidSchema)}\n".utf8
            )
            let invalid = traceDecoder.decodeJSONL(data)
            XCTAssertEqual(invalid.events.count, 1)
            assertMalformed(try XCTUnwrap(invalid.events.first))
        }

        let canonical = RawPowerObservation.canonicalFixture(
            sequence: 0,
            scenario: "direct-schema-validation"
        )
        for invalidSchema in [0, 2] {
            var object = try jsonObject(canonical)
            object["schemaVersion"] = invalidSchema
            XCTAssertThrowsError(
                try JSONDecoder().decode(
                    RawPowerObservation.self,
                    from: jsonData(object)
                ),
                "direct RawPowerObservation decode accepted schema \(invalidSchema)"
            )
        }
    }

    func testTraceDecoderIgnoresOnlyUnterminatedFinalFragment() throws {
        let decoded = try summary("truncated-final-fragment-v1.jsonl.partial")
        XCTAssertEqual(decoded.records.count, 2)
        XCTAssertEqual(decoded.samples.count, 1)
        XCTAssertNil(decoded.records.last?.footer)
        XCTAssertTrue(decoded.events.contains { event in
            guard case let .ignoredUnterminatedFinalFragment(
                lineNumber,
                byteCount
            ) = event else { return false }
            return lineNumber == 3 && byteCount > 0
        })
        XCTAssertFalse(decoded.events.contains { event in
            if case .malformed(lineNumber: 3, message: _) = event { return true }
            return false
        })

        let completeButUnterminated = try JSONEncoder().encode(
            PowerObservationTraceRecord(
                sample: .canonicalFixture(
                    sequence: 9,
                    scenario: "parseable-no-lf"
                )
            )
        )
        let parseableDecoded = traceDecoder.decodeJSONL(
            completeButUnterminated
        )
        XCTAssertTrue(parseableDecoded.records.isEmpty)
        XCTAssertEqual(
            parseableDecoded.events,
            [
                .ignoredUnterminatedFinalFragment(
                    lineNumber: 1,
                    byteCount: completeButUnterminated.count
                ),
            ]
        )
    }

    func testMalformedMiddleRecordDoesNotDiscardPriorOrLaterRecords() throws {
        let decoded = try summary("malformed-middle-record-v1.jsonl")
        XCTAssertEqual(decoded.samples.map(\.sequence), [0, 1])
        XCTAssertEqual(decoded.records.count, 4)
        XCTAssertNotNil(decoded.records.last?.footer)
        XCTAssertTrue(decoded.events.contains { event in
            if case .malformed(lineNumber: 3, message: _) = event { return true }
            return false
        })
    }

    func testReplayPreservesStaleAnnotationAndReportsPresenceTransitions() throws {
        let observations = try summary("presence-transitions-v1.jsonl").samples
        XCTAssertEqual(observations.count, 4)
        XCTAssertEqual(
            observations[1].battery.powerTelemetry.freshness.assessment,
            .stale
        )
        XCTAssertEqual(
            observations[1].battery.powerTelemetry.freshness.basis,
            .fixtureAnnotation
        )
        try assertEqual(
            observations[1].battery.powerTelemetry.freshness.unchangedForMilliseconds,
            30_000
        )

        var replay = PowerObservationReplay()
        let frames = try observations.map { try replay.consume($0) }
        XCTAssertTrue(frames[0].transitions.isEmpty)
        XCTAssertTrue(frames[1].transitions.isEmpty)
        XCTAssertEqual(frames[2].transitions.count, 1)
        XCTAssertEqual(frames[2].transitions[0].fieldPath, "smc.PSTR")
        XCTAssertEqual(frames[2].transitions[0].previousPresence, .present)
        XCTAssertEqual(frames[2].transitions[0].currentPresence, .missing)
        XCTAssertEqual(frames[3].transitions.count, 1)
        XCTAssertEqual(frames[3].transitions[0].fieldPath, "smc.PSTR")
        XCTAssertEqual(frames[3].transitions[0].previousPresence, .missing)
        XCTAssertEqual(frames[3].transitions[0].currentPresence, .present)

        let expectedPaths: Set<String> = [
            "battery.service",
            "battery.currentCapacity",
            "battery.maxCapacity",
            "battery.externalConnected",
            "battery.isCharging",
            "battery.voltageMillivolts",
            "battery.instantAmperageMilliamps",
            "battery.averageAmperageMilliamps",
            "battery.powerTelemetry.systemPowerIn",
            "battery.powerTelemetry.systemLoad",
            "battery.powerTelemetry.batteryPower",
            "battery.powerTelemetry.systemVoltageIn",
            "battery.powerTelemetry.systemCurrentIn",
            "battery.adapterCapability.ratedWatts",
            "battery.adapterCapability.adapterVoltage",
            "battery.adapterCapability.adapterCurrent",
            "battery.deviceOutput.field",
            "battery.deviceOutput.measuredTotalWatts",
            "smc.PDTR",
            "smc.PSTR",
            "smc.PPBR",
            "evidence.batteryVoltageTimesCurrent",
            "evidence.systemVoltageTimesCurrent",
        ]
        let entries = observations[0].replayPresenceEntries()
        XCTAssertEqual(Set(entries.map { $0.key.fieldPath }), expectedPaths)
        XCTAssertEqual(entries.count, expectedPaths.count)
        XCTAssertFalse(
            entries.contains { $0.key.fieldPath.contains("ports[") },
            "dynamic port entries must not become replay availability keys"
        )

        let matrix = try summary(
            "power-out-presence-matrix-v1.jsonl"
        ).samples
        var outputReplay = PowerObservationReplay()
        _ = try outputReplay.consume(
            try XCTUnwrap(matrix.first { $0.sequence == 0 })
        )
        let multiple = try outputReplay.consume(
            try XCTUnwrap(matrix.first { $0.sequence == 2 })
        )
        XCTAssertEqual(
            multiple.transitions.map(\.fieldPath),
            [
                "battery.deviceOutput.field",
                "battery.deviceOutput.measuredTotalWatts",
            ],
            "multiple transitions must be sorted by stable field path"
        )
        let dynamicPortOnly = try outputReplay.consume(
            try XCTUnwrap(matrix.first { $0.sequence == 3 })
        )
        XCTAssertTrue(
            dynamicPortOnly.transitions.isEmpty,
            "adding a dynamic port while aggregate presence remains present must not emit availability transitions"
        )
    }

    func testReplayRejectsNonMonotonicSequence() throws {
        let capture = try interval()
        let observation = RawPowerObservation.canonicalFixture(
            sequence: 5,
            scenario: "replay"
        )
        var replay = PowerObservationReplay()
        _ = try replay.consume(observation)
        XCTAssertThrowsError(try replay.consume(observation)) { error in
            XCTAssertEqual(
                error as? PowerObservationReplayError,
                .nonMonotonicSequence(previous: 5, current: 5)
            )
        }
        let descending = RawPowerObservation.canonicalFixture(
            sequence: 4,
            scenario: "replay"
        )
        XCTAssertThrowsError(try replay.consume(descending)) { error in
            XCTAssertEqual(
                error as? PowerObservationReplayError,
                .nonMonotonicSequence(previous: 5, current: 4)
            )
        }
        XCTAssertEqual(replay.lastSequence, 5)
        _ = capture
    }

    func testMonotonicIntervalRejectsEndBeforeStart() {
        XCTAssertThrowsError(
            try MonotonicInterval(
                startedContinuousNanoseconds: 10,
                endedContinuousNanoseconds: 9
            )
        ) { error in
            XCTAssertEqual(
                error as? MonotonicIntervalError,
                .endPrecedesStart(started: 10, ended: 9)
            )
        }

        let invalid = Data(
            #"{"endedContinuousNanoseconds":9,"startedContinuousNanoseconds":10}"#.utf8
        )
        XCTAssertThrowsError(
            try JSONDecoder().decode(MonotonicInterval.self, from: invalid)
        )
    }

    func testMonotonicIntervalDerivedValuesAreNotEncoded() throws {
        let value = try interval(10, 20)
        XCTAssertEqual(value.durationNanoseconds, 10)
        XCTAssertEqual(value.durationMilliseconds, 0.000_01, accuracy: 0.000_000_001)
        XCTAssertEqual(value.midpointContinuousNanoseconds, 15)

        let data = try JSONEncoder().encode(value)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(
            Set(object.keys),
            ["startedContinuousNanoseconds", "endedContinuousNanoseconds"]
        )
    }
}
