import CoreFoundation
import Foundation

#if canImport(IOKit) && os(macOS)
import IOKit
import Darwin
#endif

struct AppleSmartBatteryPowerRawSnapshot {
    let servicePresent: Bool
    let properties: [String: Any]
}

protocol AppleSmartBatteryPowerRawSnapshotReading {
    func readAllowlistedProperties(
        _ keys: [String]
    ) -> AppleSmartBatteryPowerRawSnapshot
}

struct AppleSmartBatteryPowerSample {
    let visibleSnapshot: PowerSnapshot?
    let observation: AppleSmartBatteryObservation
}

protocol AppleSmartBatteryPowerObservationReading: AnyObject {
    func readRuntimeSample() -> AppleSmartBatteryPowerSample
    func resetFreshness()
}

final class AppleSmartBatteryPowerObservationReader:
    AppleSmartBatteryPowerObservationReading
{
    static let propertyAllowlist = [
        "ExternalConnected",
        "IsCharging",
        "Voltage",
        "InstantAmperage",
        "Amperage",
        "PowerTelemetryData",
        "PowerOutDetails",
    ]
    static let runtimePropertyAllowlist = propertyAllowlist + [
        "CurrentCapacity", "MaxCapacity", "CycleCount",
        "Temperature", "VirtualTemperature",
    ]

    private static let telemetryAllowlist = [
        "SystemPowerIn",
        "SystemLoad",
        "BatteryPower",
        "SystemVoltageIn",
        "SystemCurrentIn",
    ]
    private static let powerOutAllowlist = [
        "Watts",
        "PDPowermW",
        "PortIndex",
    ]
    private static let defaultTrackingGapNanoseconds: UInt64 = 5_000_000_000

    private let backend: any AppleSmartBatteryPowerRawSnapshotReading
    private let clock: () -> UInt64
    private let lowPowerMode: () -> Bool
    private let maximumTrackingGapNanoseconds: UInt64
    private let trackerLock = NSLock()
    private var previousTelemetryToken: String?
    private var previousEvaluationNanoseconds: UInt64?
    private var unchangedSinceNanoseconds: UInt64?

    init(
        backend: any AppleSmartBatteryPowerRawSnapshotReading =
            SystemAppleSmartBatteryPowerRawSnapshotReader(),
        clock: @escaping () -> UInt64 =
            AppleSmartBatteryPowerObservationReader.monotonicNow,
        maximumTrackingGapNanoseconds: UInt64 =
            AppleSmartBatteryPowerObservationReader
                .defaultTrackingGapNanoseconds,
        lowPowerMode: @escaping () -> Bool = {
            ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    ) {
        self.backend = backend
        self.clock = clock
        self.maximumTrackingGapNanoseconds = maximumTrackingGapNanoseconds
        self.lowPowerMode = lowPowerMode
    }

    func readObservation() -> AppleSmartBatteryObservation {
        let (raw, capture) = readRaw(keys: Self.propertyAllowlist)
        return observation(from: raw, capture: capture)
    }

    func readRuntimeSample() -> AppleSmartBatteryPowerSample {
        // Both consumers see the same acquired field values. Individual
        // registry properties still have no firmware-level atomicity guarantee.
        let (raw, capture) = readRaw(keys: Self.runtimePropertyAllowlist)
        let snapshot: PowerSnapshot?
        if case let .snapshot(value) = BatterySampler.sampleResult(
            from: raw.servicePresent ? raw.properties : nil,
            lowPowerMode: lowPowerMode()
        ) {
            snapshot = value
        } else {
            snapshot = nil
        }
        return AppleSmartBatteryPowerSample(
            visibleSnapshot: snapshot,
            observation: observation(from: raw, capture: capture)
        )
    }

    private func readRaw(
        keys: [String]
    ) -> (AppleSmartBatteryPowerRawSnapshot, MonotonicInterval) {
        let started = clock()
        let raw = backend.readAllowlistedProperties(keys)
        let ended = max(started, clock())
        let capture = try! MonotonicInterval(
            startedContinuousNanoseconds: started,
            endedContinuousNanoseconds: ended
        )
        return (raw, capture)
    }

    private func observation(
        from raw: AppleSmartBatteryPowerRawSnapshot,
        capture: MonotonicInterval
    ) -> AppleSmartBatteryObservation {
        guard raw.servicePresent else {
            resetFreshness()
            return .canonicalFixtureMissing(capture: capture)
        }

        do {
            let missing = AppleSmartBatteryObservation
                .canonicalFixtureMissing(capture: capture)
            return AppleSmartBatteryObservation(
                servicePresence: .present,
                capture: capture,
                currentCapacity: missing.currentCapacity,
                maxCapacity: missing.maxCapacity,
                externalConnected: try booleanObservation(
                    raw.properties,
                    key: "ExternalConnected",
                    identifier: "battery.externalConnected",
                    capture: capture
                ),
                isCharging: try booleanObservation(
                    raw.properties,
                    key: "IsCharging",
                    identifier: "battery.isCharging",
                    capture: capture
                ),
                voltageMillivolts: try integerObservation(
                    raw.properties,
                    key: "Voltage",
                    identifier: "battery.voltageMillivolts",
                    kind: .measured,
                    unit: .millivolts,
                    capture: capture
                ),
                instantAmperageMilliamps: try integerObservation(
                    raw.properties,
                    key: "InstantAmperage",
                    identifier: "battery.instantAmperageMilliamps",
                    kind: .measured,
                    unit: .milliamps,
                    reinterpretUInt32AsSigned: true,
                    capture: capture
                ),
                averageAmperageMilliamps: try integerObservation(
                    raw.properties,
                    key: "Amperage",
                    identifier: "battery.averageAmperageMilliamps",
                    kind: .measured,
                    unit: .milliamps,
                    reinterpretUInt32AsSigned: true,
                    capture: capture
                ),
                powerTelemetry: try powerTelemetry(
                    raw.properties,
                    capture: capture
                ),
                adapterCapability: missing.adapterCapability,
                deviceOutput: try deviceOutput(
                    raw.properties,
                    capture: capture
                )
            )
        } catch {
            resetFreshness()
            let missing = AppleSmartBatteryObservation
                .canonicalFixtureMissing(capture: capture)
            return AppleSmartBatteryObservation(
                servicePresence: .invalid,
                capture: capture,
                currentCapacity: missing.currentCapacity,
                maxCapacity: missing.maxCapacity,
                externalConnected: missing.externalConnected,
                isCharging: missing.isCharging,
                voltageMillivolts: missing.voltageMillivolts,
                instantAmperageMilliamps:
                    missing.instantAmperageMilliamps,
                averageAmperageMilliamps:
                    missing.averageAmperageMilliamps,
                powerTelemetry: missing.powerTelemetry,
                adapterCapability: missing.adapterCapability,
                deviceOutput: missing.deviceOutput
            )
        }
    }

    func resetFreshness() {
        trackerLock.lock()
        previousTelemetryToken = nil
        previousEvaluationNanoseconds = nil
        unchangedSinceNanoseconds = nil
        trackerLock.unlock()
    }

    private func powerTelemetry(
        _ properties: [String: Any],
        capture: MonotonicInterval
    ) throws -> BatteryPowerTelemetryObservation {
        guard properties.keys.contains("PowerTelemetryData") else {
            resetFreshness()
            return .canonicalFixtureMissing(capture: capture)
        }
        guard let dictionary = projectedDictionary(
            properties["PowerTelemetryData"],
            allowlist: Self.telemetryAllowlist
        ) else {
            resetFreshness()
            return BatteryPowerTelemetryObservation(
                presence: .invalid,
                capture: capture,
                systemPowerIn: try invalidPowerReading(
                    "battery.powerTelemetry.systemPowerIn",
                    source: .appleSmartBatteryPowerTelemetry,
                    kind: .measured,
                    semantic: .systemInput,
                    capture: capture,
                    issue: "PowerTelemetryData is not a dictionary"
                ),
                systemLoad: try invalidPowerReading(
                    "battery.powerTelemetry.systemLoad",
                    source: .appleSmartBatteryPowerTelemetry,
                    kind: .measured,
                    semantic: .systemLoad,
                    capture: capture,
                    issue: "PowerTelemetryData is not a dictionary"
                ),
                batteryPower: try invalidPowerReading(
                    "battery.powerTelemetry.batteryPower",
                    source: .appleSmartBatteryPowerTelemetry,
                    kind: .measured,
                    semantic: .firmwareBatteryPowerUnresolvedSign,
                    capture: capture,
                    issue: "PowerTelemetryData is not a dictionary"
                ),
                systemVoltageInNative: try invalidIntegerObservation(
                    "battery.powerTelemetry.systemVoltageIn",
                    source: .appleSmartBatteryPowerTelemetry,
                    kind: .raw,
                    unit: .registryNative,
                    capture: capture,
                    issue: "PowerTelemetryData is not a dictionary"
                ),
                systemCurrentInNative: try invalidIntegerObservation(
                    "battery.powerTelemetry.systemCurrentIn",
                    source: .appleSmartBatteryPowerTelemetry,
                    kind: .raw,
                    unit: .registryNative,
                    capture: capture,
                    issue: "PowerTelemetryData is not a dictionary"
                ),
                updateToken: nil,
                freshness: .unknown(
                    at: capture.endedContinuousNanoseconds
                )
            )
        }

        let systemPowerIn = try telemetryPowerReading(
            dictionary,
            key: "SystemPowerIn",
            identifier: "battery.powerTelemetry.systemPowerIn",
            semantic: .systemInput,
            capture: capture
        )
        let systemLoad = try telemetryPowerReading(
            dictionary,
            key: "SystemLoad",
            identifier: "battery.powerTelemetry.systemLoad",
            semantic: .systemLoad,
            capture: capture
        )
        let batteryPower = try telemetryPowerReading(
            dictionary,
            key: "BatteryPower",
            identifier: "battery.powerTelemetry.batteryPower",
            semantic: .firmwareBatteryPowerUnresolvedSign,
            capture: capture
        )
        let systemVoltage = try integerObservation(
            dictionary,
            key: "SystemVoltageIn",
            identifier: "battery.powerTelemetry.systemVoltageIn",
            source: .appleSmartBatteryPowerTelemetry,
            kind: .raw,
            unit: .registryNative,
            capture: capture
        )
        let systemCurrent = try integerObservation(
            dictionary,
            key: "SystemCurrentIn",
            identifier: "battery.powerTelemetry.systemCurrentIn",
            source: .appleSmartBatteryPowerTelemetry,
            kind: .raw,
            unit: .registryNative,
            capture: capture
        )
        let token = telemetryToken(
            power: [systemPowerIn, systemLoad, batteryPower],
            integers: [systemVoltage, systemCurrent]
        )
        let freshness = try freshness(
            token: token,
            at: capture.endedContinuousNanoseconds
        )
        return BatteryPowerTelemetryObservation(
            presence: .present,
            capture: capture,
            systemPowerIn: systemPowerIn,
            systemLoad: systemLoad,
            batteryPower: batteryPower,
            systemVoltageInNative: systemVoltage,
            systemCurrentInNative: systemCurrent,
            updateToken: token,
            freshness: freshness
        )
    }

    private func deviceOutput(
        _ properties: [String: Any],
        capture: MonotonicInterval
    ) throws -> DeviceOutputObservation {
        guard properties.keys.contains("PowerOutDetails") else {
            return .canonicalFixtureMissing(capture: capture)
        }
        // Bound per-sample work before bridging or traversing port entries.
        // Invalid data is not evidence of a real zero-watt output.
        guard let rawPorts = properties["PowerOutDetails"] as? NSArray,
              rawPorts.count <= 64 else {
            return DeviceOutputObservation(
                fieldPresence: .invalid,
                capture: capture,
                ports: [],
                measuredTotalWatts: try invalidPowerReading(
                    "battery.deviceOutput.measuredTotalWatts",
                    source: .derivedAggregate,
                    kind: .derived,
                    semantic: .deviceOutputMeasuredTotal,
                    capture: capture,
                    issue: "PowerOutDetails must contain at most 64 ports"
                ),
                completeness: .unknown
            )
        }

        var ports: [DeviceOutputPortObservation] = []
        for (index, rawPort) in rawPorts.enumerated() {
            guard let port = projectedDictionary(
                rawPort,
                allowlist: Self.powerOutAllowlist
            ) else {
                ports.append(DeviceOutputPortObservation(
                    arrayIndex: index,
                    portIndex: nil,
                    locationIdentifierWasPresent: false,
                    measuredWatts: try invalidPowerReading(
                        "battery.deviceOutput.ports[\(index)].measuredWatts",
                        source: .appleSmartBatteryPowerOutWatts,
                        kind: .measured,
                        semantic: .deviceOutput,
                        capture: capture,
                        issue: "PowerOutDetails entry is not a dictionary"
                    ),
                    pdPowerRaw: try invalidPowerReading(
                        "battery.deviceOutput.ports[\(index)].pdPowerRaw",
                        source: .appleSmartBatteryPowerOutPDPower,
                        kind: .raw,
                        semantic: .unknown,
                        capture: capture,
                        issue: "PowerOutDetails entry is not a dictionary"
                    )
                ))
                continue
            }
            let parsedPort = parsedInteger(port["PortIndex"])
            let portIndex = parsedPort.value.flatMap { value in
                value >= 0 && value <= Int64(Int.max) ? Int(value) : nil
            }
            let measured = try integerPowerReading(
                parsedInteger(port["Watts"]),
                identifier:
                    "battery.deviceOutput.ports[\(index)].measuredWatts",
                source: .appleSmartBatteryPowerOutWatts,
                kind: .measured,
                semantic: .deviceOutput,
                rawUnit: .milliwatts,
                divisor: 1_000,
                requireNonNegative: true,
                capture: capture
            )
            let pdPower = try rawPowerReading(
                parsedInteger(port["PDPowermW"]),
                identifier:
                    "battery.deviceOutput.ports[\(index)].pdPowerRaw",
                source: .appleSmartBatteryPowerOutPDPower,
                capture: capture
            )
            ports.append(DeviceOutputPortObservation(
                arrayIndex: index,
                portIndex: portIndex,
                locationIdentifierWasPresent: false,
                measuredWatts: measured,
                pdPowerRaw: pdPower
            ))
        }

        let measuredPorts = ports.filter {
            $0.measuredWatts.presence == .present
        }
        let total: PowerReading
        let completeness: AggregateCompleteness
        if ports.isEmpty {
            total = try PowerReading(
                identifier: "battery.deviceOutput.measuredTotalWatts",
                source: .derivedAggregate,
                kind: .derived,
                semantic: .deviceOutputMeasuredTotal,
                presence: .present,
                rawInteger: nil,
                rawFloatingPoint: nil,
                rawUnit: nil,
                watts: 0,
                capture: capture,
                freshness: .unknown(
                    at: capture.endedContinuousNanoseconds
                ),
                validationIssue: nil
            )
            completeness = .complete
        } else if measuredPorts.isEmpty {
            total = .canonicalFixtureMissing(
                identifier: "battery.deviceOutput.measuredTotalWatts",
                source: .derivedAggregate,
                kind: .derived,
                semantic: .deviceOutputMeasuredTotal,
                capture: capture
            )
            completeness = .unknown
        } else {
            let watts = measuredPorts.reduce(0) {
                $0 + ($1.measuredWatts.watts ?? 0)
            }
            total = try PowerReading(
                identifier: "battery.deviceOutput.measuredTotalWatts",
                source: .derivedAggregate,
                kind: .derived,
                semantic: .deviceOutputMeasuredTotal,
                presence: .present,
                rawInteger: nil,
                rawFloatingPoint: nil,
                rawUnit: nil,
                watts: watts,
                capture: capture,
                freshness: .unknown(
                    at: capture.endedContinuousNanoseconds
                ),
                validationIssue: nil
            )
            completeness = measuredPorts.count == ports.count
                ? .complete : .partial
        }
        return DeviceOutputObservation(
            fieldPresence: .present,
            capture: capture,
            ports: ports,
            measuredTotalWatts: total,
            completeness: completeness
        )
    }

    private func integerObservation(
        _ properties: [String: Any],
        key: String,
        identifier: String,
        source: ObservationSource = .appleSmartBatteryRegistry,
        kind: ObservationKind,
        unit: ObservationUnit,
        reinterpretUInt32AsSigned: Bool = false,
        capture: MonotonicInterval
    ) throws -> Observed<Int64> {
        let parsed = parsedInteger(
            properties[key],
            reinterpretUInt32AsSigned: reinterpretUInt32AsSigned
        )
        switch parsed.presence {
        case .present:
            return try Observed(
                identifier: identifier,
                source: source,
                kind: kind,
                unit: unit,
                presence: .present,
                value: parsed.value,
                capture: capture,
                freshness: .unknown(
                    at: capture.endedContinuousNanoseconds
                ),
                validationIssue: nil
            )
        case .missing:
            return .canonicalFixtureMissing(
                identifier: identifier,
                source: source,
                kind: kind,
                unit: unit,
                capture: capture
            )
        case .invalid:
            return try invalidIntegerObservation(
                identifier,
                source: source,
                kind: kind,
                unit: unit,
                capture: capture,
                issue: parsed.issue ?? "invalid integer"
            )
        }
    }

    private func booleanObservation(
        _ properties: [String: Any],
        key: String,
        identifier: String,
        capture: MonotonicInterval
    ) throws -> Observed<Bool> {
        let parsed = parsedBoolean(properties[key])
        if parsed.presence == .missing {
            return .canonicalFixtureMissing(
                identifier: identifier,
                source: .appleSmartBatteryRegistry,
                kind: .hint,
                unit: .boolean,
                capture: capture
            )
        }
        return try Observed(
            identifier: identifier,
            source: .appleSmartBatteryRegistry,
            kind: .hint,
            unit: .boolean,
            presence: parsed.presence,
            value: parsed.value,
            capture: capture,
            freshness: .unknown(
                at: capture.endedContinuousNanoseconds
            ),
            validationIssue: parsed.presence == .invalid
                ? parsed.issue : nil
        )
    }

    private func telemetryPowerReading(
        _ dictionary: [String: Any],
        key: String,
        identifier: String,
        semantic: PowerSemantic,
        capture: MonotonicInterval
    ) throws -> PowerReading {
        try integerPowerReading(
            parsedInteger(dictionary[key]),
            identifier: identifier,
            source: .appleSmartBatteryPowerTelemetry,
            kind: .measured,
            semantic: semantic,
            rawUnit: .milliwatts,
            divisor: 1_000,
            requireNonNegative: false,
            capture: capture
        )
    }

    private func integerPowerReading(
        _ parsed: ParsedPowerObservationInteger,
        identifier: String,
        source: ObservationSource,
        kind: ObservationKind,
        semantic: PowerSemantic,
        rawUnit: ObservationUnit,
        divisor: Double,
        requireNonNegative: Bool,
        capture: MonotonicInterval
    ) throws -> PowerReading {
        switch parsed.presence {
        case .present:
            guard let value = parsed.value,
                  !requireNonNegative || value >= 0 else {
                return try invalidPowerReading(
                    identifier,
                    source: source,
                    kind: kind,
                    semantic: semantic,
                    capture: capture,
                    issue: "negative value is invalid"
                )
            }
            return try PowerReading(
                identifier: identifier,
                source: source,
                kind: kind,
                semantic: semantic,
                presence: .present,
                rawInteger: value,
                rawFloatingPoint: nil,
                rawUnit: rawUnit,
                watts: Double(value) / divisor,
                capture: capture,
                freshness: .unknown(
                    at: capture.endedContinuousNanoseconds
                ),
                validationIssue: nil
            )
        case .missing:
            return .canonicalFixtureMissing(
                identifier: identifier,
                source: source,
                kind: kind,
                semantic: semantic,
                capture: capture
            )
        case .invalid:
            return try invalidPowerReading(
                identifier,
                source: source,
                kind: kind,
                semantic: semantic,
                capture: capture,
                issue: parsed.issue ?? "invalid integer"
            )
        }
    }

    private func rawPowerReading(
        _ parsed: ParsedPowerObservationInteger,
        identifier: String,
        source: ObservationSource,
        capture: MonotonicInterval
    ) throws -> PowerReading {
        switch parsed.presence {
        case .present:
            return try PowerReading(
                identifier: identifier,
                source: source,
                kind: .raw,
                semantic: .unknown,
                presence: .present,
                rawInteger: parsed.value,
                rawFloatingPoint: nil,
                rawUnit: .milliwatts,
                watts: nil,
                capture: capture,
                freshness: .unknown(
                    at: capture.endedContinuousNanoseconds
                ),
                validationIssue: nil
            )
        case .missing:
            return .canonicalFixtureMissing(
                identifier: identifier,
                source: source,
                kind: .raw,
                semantic: .unknown,
                capture: capture
            )
        case .invalid:
            return try invalidPowerReading(
                identifier,
                source: source,
                kind: .raw,
                semantic: .unknown,
                capture: capture,
                issue: parsed.issue ?? "invalid integer"
            )
        }
    }

    private func invalidIntegerObservation(
        _ identifier: String,
        source: ObservationSource,
        kind: ObservationKind,
        unit: ObservationUnit,
        capture: MonotonicInterval,
        issue: String
    ) throws -> Observed<Int64> {
        try Observed(
            identifier: identifier,
            source: source,
            kind: kind,
            unit: unit,
            presence: .invalid,
            value: nil,
            capture: capture,
            freshness: .unknown(
                at: capture.endedContinuousNanoseconds
            ),
            validationIssue: issue
        )
    }

    private func invalidPowerReading(
        _ identifier: String,
        source: ObservationSource,
        kind: ObservationKind,
        semantic: PowerSemantic,
        capture: MonotonicInterval,
        issue: String
    ) throws -> PowerReading {
        try PowerReading(
            identifier: identifier,
            source: source,
            kind: kind,
            semantic: semantic,
            presence: .invalid,
            rawInteger: nil,
            rawFloatingPoint: nil,
            rawUnit: nil,
            watts: nil,
            capture: capture,
            freshness: .unknown(
                at: capture.endedContinuousNanoseconds
            ),
            validationIssue: issue
        )
    }

    private func telemetryToken(
        power: [PowerReading],
        integers: [Observed<Int64>]
    ) -> String {
        var canonical = power.map {
            "\($0.identifier):\($0.presence.rawValue):\($0.rawInteger.map(String.init) ?? "-")"
        }
        canonical.append(contentsOf: integers.map {
            "\($0.identifier):\($0.presence.rawValue):\($0.value.map(String.init) ?? "-")"
        })
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in canonical.joined(separator: "|").utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }

    private func freshness(
        token: String,
        at nanoseconds: UInt64
    ) throws -> FreshnessEvidence {
        trackerLock.lock()
        defer { trackerLock.unlock() }

        if let previousEvaluationNanoseconds,
           nanoseconds < previousEvaluationNanoseconds
            || nanoseconds - previousEvaluationNanoseconds
                > maximumTrackingGapNanoseconds {
            previousTelemetryToken = nil
            unchangedSinceNanoseconds = nil
        }
        previousEvaluationNanoseconds = nanoseconds

        if previousTelemetryToken != token {
            previousTelemetryToken = token
            unchangedSinceNanoseconds = nanoseconds
            return try FreshnessEvidence(
                evaluatedAtContinuousNanoseconds: nanoseconds,
                ageMilliseconds: nil,
                updateToken: token,
                unchangedSinceContinuousNanoseconds: nanoseconds,
                unchangedForMilliseconds: 0,
                assessment: .changed,
                basis: .derivedUpdateToken
            )
        }

        let since = unchangedSinceNanoseconds ?? nanoseconds
        unchangedSinceNanoseconds = since
        return try FreshnessEvidence(
            evaluatedAtContinuousNanoseconds: nanoseconds,
            ageMilliseconds: nil,
            updateToken: token,
            unchangedSinceContinuousNanoseconds: since,
            unchangedForMilliseconds:
                Double(nanoseconds - since) / 1_000_000,
            assessment: .unchanged,
            basis: .derivedUpdateToken
        )
    }

    private static func monotonicNow() -> UInt64 {
#if canImport(IOKit) && os(macOS)
        clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)
#else
        DispatchTime.now().uptimeNanoseconds
#endif
    }
}

private struct ParsedPowerObservationInteger {
    let presence: ObservationPresence
    let value: Int64?
    let issue: String?
}

private struct ParsedPowerObservationBoolean {
    let presence: ObservationPresence
    let value: Bool?
    let issue: String?
}

private func parsedInteger(
    _ raw: Any?,
    reinterpretUInt32AsSigned: Bool = false
) -> ParsedPowerObservationInteger {
    guard let raw else {
        return .init(presence: .missing, value: nil, issue: "key missing")
    }
    guard let number = raw as? NSNumber,
          CFGetTypeID(number) != CFBooleanGetTypeID(),
          !["f", "d"].contains(String(cString: number.objCType)) else {
        return .init(
            presence: .invalid,
            value: nil,
            issue: "value is not an integer number"
        )
    }
    let type = String(cString: number.objCType)
    let unsignedTypes: Set<String> = ["C", "S", "I", "L", "Q"]
    let exact: Int64
    if unsignedTypes.contains(type) {
        let unsigned = number.uint64Value
        if reinterpretUInt32AsSigned,
           unsigned > UInt64(Int64.max) {
            exact = Int64(bitPattern: unsigned)
        } else if unsigned <= UInt64(Int64.max) {
            exact = Int64(unsigned)
        } else {
            return .init(
                presence: .invalid,
                value: nil,
                issue: "unsigned integer exceeds Int64.max"
            )
        }
    } else {
        exact = number.int64Value
    }
    let value: Int64
    if reinterpretUInt32AsSigned,
       exact > Int64(Int32.max),
       exact <= Int64(UInt32.max) {
        value = Int64(Int32(bitPattern: UInt32(exact)))
    } else {
        value = exact
    }
    return .init(presence: .present, value: value, issue: nil)
}

private func parsedBoolean(_ raw: Any?) -> ParsedPowerObservationBoolean {
    guard let raw else {
        return .init(presence: .missing, value: nil, issue: "key missing")
    }
    guard let number = raw as? NSNumber else {
        return .init(
            presence: .invalid,
            value: nil,
            issue: "value is not a boolean"
        )
    }
    if CFGetTypeID(number) == CFBooleanGetTypeID() {
        return .init(presence: .present, value: number.boolValue, issue: nil)
    }
    guard !["f", "d"].contains(String(cString: number.objCType)) else {
        return .init(
            presence: .invalid,
            value: nil,
            issue: "value is not a boolean"
        )
    }
    let value = number.int64Value
    guard value == 0 || value == 1 else {
        return .init(
            presence: .invalid,
            value: nil,
            issue: "integer boolean must be 0 or 1"
        )
    }
    return .init(presence: .present, value: value == 1, issue: nil)
}

private func projectedDictionary(
    _ raw: Any?,
    allowlist: [String]
) -> [String: Any]? {
    guard let dictionary = raw as? NSDictionary else { return nil }
    var projected: [String: Any] = [:]
    for key in allowlist {
        if let value = dictionary.object(forKey: key) {
            projected[key] = value
        }
    }
    return projected
}

struct SystemAppleSmartBatteryPowerRawSnapshotReader:
    AppleSmartBatteryPowerRawSnapshotReading
{
    func readAllowlistedProperties(
        _ keys: [String]
    ) -> AppleSmartBatteryPowerRawSnapshot {
#if canImport(IOKit) && os(macOS)
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSmartBattery")
        )
        guard service != IO_OBJECT_NULL else {
            return .init(servicePresent: false, properties: [:])
        }
        defer { IOObjectRelease(service) }

        var properties: [String: Any] = [:]
        for key in keys {
            if let value = IORegistryEntryCreateCFProperty(
                service,
                key as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue() {
                properties[key] = value
            }
        }
        return .init(servicePresent: true, properties: properties)
#else
        return .init(servicePresent: false, properties: [:])
#endif
    }
}
