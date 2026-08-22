#if DEBUG

import Foundation
import CoreFoundation

#if canImport(IOKit) && os(macOS)
import IOKit
#endif

struct AppleSmartBatteryRawSnapshot {
    let servicePresent: Bool
    let properties: [String: Any]
}

protocol AppleSmartBatteryRawSnapshotReading {
    func readAllowlistedProperties(
        _ keys: [String]
    ) -> AppleSmartBatteryRawSnapshot
}

struct TelemetryFreezeTracker {
    private var previousToken: String?
    private var unchangedSinceContinuousNanoseconds: UInt64?

    mutating func observe(
        updateToken: String?,
        evaluatedAtContinuousNanoseconds: UInt64
    ) throws -> FreshnessEvidence {
        guard let updateToken else {
            previousToken = nil
            unchangedSinceContinuousNanoseconds = nil
            return .unknown(at: evaluatedAtContinuousNanoseconds)
        }

        if previousToken != updateToken {
            previousToken = updateToken
            unchangedSinceContinuousNanoseconds =
                evaluatedAtContinuousNanoseconds
            return try FreshnessEvidence(
                evaluatedAtContinuousNanoseconds:
                    evaluatedAtContinuousNanoseconds,
                ageMilliseconds: nil,
                updateToken: updateToken,
                unchangedSinceContinuousNanoseconds:
                    evaluatedAtContinuousNanoseconds,
                unchangedForMilliseconds: 0,
                assessment: .changed,
                basis: .derivedUpdateToken
            )
        }

        let since = unchangedSinceContinuousNanoseconds
            ?? evaluatedAtContinuousNanoseconds
        unchangedSinceContinuousNanoseconds = since
        let elapsed: Double
        if evaluatedAtContinuousNanoseconds >= since {
            elapsed = Double(
                evaluatedAtContinuousNanoseconds - since
            ) / 1_000_000
        } else {
            elapsed = 0
        }
        return try FreshnessEvidence(
            evaluatedAtContinuousNanoseconds:
                evaluatedAtContinuousNanoseconds,
            ageMilliseconds: nil,
            updateToken: updateToken,
            unchangedSinceContinuousNanoseconds: since,
            unchangedForMilliseconds: elapsed,
            assessment: .unchanged,
            basis: .derivedUpdateToken
        )
    }
}

final class AppleSmartBatteryObservationReader:
    AppleSmartBatteryObservationReading
{
    static let topLevelPropertyAllowlist = [
        "CurrentCapacity",
        "MaxCapacity",
        "ExternalConnected",
        "IsCharging",
        "Voltage",
        "InstantAmperage",
        "Amperage",
        "PowerTelemetryData",
        "AdapterDetails",
        "PowerOutDetails",
    ]

    static let telemetryPropertyAllowlist = [
        "SystemPowerIn",
        "SystemLoad",
        "BatteryPower",
        "SystemVoltageIn",
        "SystemCurrentIn",
    ]

    static let adapterPropertyAllowlist = [
        "Watts",
        "AdapterVoltage",
        "Current",
    ]

    static let powerOutPropertyAllowlist = [
        "Watts",
        "PDPowermW",
        "PortIndex",
    ]

    private let backend: any AppleSmartBatteryRawSnapshotReading
    private let clock: any ContinuousNanosecondClockReading
    private let trackerLock = NSLock()
    private var telemetryFreezeTracker = TelemetryFreezeTracker()

    init(
        backend: any AppleSmartBatteryRawSnapshotReading =
            SystemAppleSmartBatteryRawSnapshotReader(),
        clock: any ContinuousNanosecondClockReading =
            SystemContinuousNanosecondClock()
    ) {
        self.backend = backend
        self.clock = clock
    }

    func readObservation() throws -> AppleSmartBatteryObservation {
        let started = clock.nowContinuousNanoseconds()
        let raw = backend.readAllowlistedProperties(
            Self.topLevelPropertyAllowlist
        )
        let ended = max(
            started,
            clock.nowContinuousNanoseconds()
        )
        let capture = try MonotonicInterval(
            startedContinuousNanoseconds: started,
            endedContinuousNanoseconds: ended
        )

        guard raw.servicePresent else {
            _ = try telemetryFreshness(
                updateToken: nil,
                evaluatedAtContinuousNanoseconds:
                    capture.endedContinuousNanoseconds
            )
            return .canonicalFixtureMissing(capture: capture)
        }

        let currentCapacity = try observedInteger(
            properties: raw.properties,
            key: "CurrentCapacity",
            identifier: "battery.currentCapacity",
            kind: .raw,
            unit: .registryNative,
            capture: capture
        )
        let maxCapacity = try observedInteger(
            properties: raw.properties,
            key: "MaxCapacity",
            identifier: "battery.maxCapacity",
            kind: .raw,
            unit: .registryNative,
            capture: capture
        )
        let externalConnected = try observedBoolean(
            properties: raw.properties,
            key: "ExternalConnected",
            identifier: "battery.externalConnected",
            capture: capture
        )
        let isCharging = try observedBoolean(
            properties: raw.properties,
            key: "IsCharging",
            identifier: "battery.isCharging",
            capture: capture
        )
        let voltage = try observedInteger(
            properties: raw.properties,
            key: "Voltage",
            identifier: "battery.voltageMillivolts",
            kind: .measured,
            unit: .millivolts,
            capture: capture
        )
        let instantAmperage = try observedInteger(
            properties: raw.properties,
            key: "InstantAmperage",
            identifier: "battery.instantAmperageMilliamps",
            kind: .measured,
            unit: .milliamps,
            reinterpretUnsignedUInt32AsSigned: true,
            capture: capture
        )
        let averageAmperage = try observedInteger(
            properties: raw.properties,
            key: "Amperage",
            identifier: "battery.averageAmperageMilliamps",
            kind: .measured,
            unit: .milliamps,
            reinterpretUnsignedUInt32AsSigned: true,
            capture: capture
        )

        return AppleSmartBatteryObservation(
            servicePresence: .present,
            capture: capture,
            currentCapacity: currentCapacity,
            maxCapacity: maxCapacity,
            externalConnected: externalConnected,
            isCharging: isCharging,
            voltageMillivolts: voltage,
            instantAmperageMilliamps: instantAmperage,
            averageAmperageMilliamps: averageAmperage,
            powerTelemetry: try makePowerTelemetry(
                properties: raw.properties,
                capture: capture
            ),
            adapterCapability: try makeAdapterCapability(
                properties: raw.properties,
                capture: capture
            ),
            deviceOutput: try makeDeviceOutput(
                properties: raw.properties,
                capture: capture
            )
        )
    }

    private func makePowerTelemetry(
        properties: [String: Any],
        capture: MonotonicInterval
    ) throws -> BatteryPowerTelemetryObservation {
        guard properties.keys.contains("PowerTelemetryData") else {
            _ = try telemetryFreshness(
                updateToken: nil,
                evaluatedAtContinuousNanoseconds:
                    capture.endedContinuousNanoseconds
            )
            return .canonicalFixtureMissing(capture: capture)
        }
        guard let dictionary = allowlistedDictionaryValue(
            properties["PowerTelemetryData"],
            allowedKeys: Self.telemetryPropertyAllowlist
        )?.values else {
            let freshness = try telemetryFreshness(
                updateToken: nil,
                evaluatedAtContinuousNanoseconds:
                    capture.endedContinuousNanoseconds
            )
            return BatteryPowerTelemetryObservation(
                presence: .invalid,
                capture: capture,
                systemPowerIn: try invalidPowerReading(
                    identifier:
                        "battery.powerTelemetry.systemPowerIn",
                    source: .appleSmartBatteryPowerTelemetry,
                    kind: .measured,
                    semantic: .systemInput,
                    capture: capture,
                    issue: "PowerTelemetryData is not a dictionary"
                ),
                systemLoad: try invalidPowerReading(
                    identifier:
                        "battery.powerTelemetry.systemLoad",
                    source: .appleSmartBatteryPowerTelemetry,
                    kind: .measured,
                    semantic: .systemLoad,
                    capture: capture,
                    issue: "PowerTelemetryData is not a dictionary"
                ),
                batteryPower: try invalidPowerReading(
                    identifier:
                        "battery.powerTelemetry.batteryPower",
                    source: .appleSmartBatteryPowerTelemetry,
                    kind: .measured,
                    semantic:
                        .firmwareBatteryPowerUnresolvedSign,
                    capture: capture,
                    issue: "PowerTelemetryData is not a dictionary"
                ),
                systemVoltageInNative: try invalidObservedInteger(
                    identifier:
                        "battery.powerTelemetry.systemVoltageIn",
                    source: .appleSmartBatteryPowerTelemetry,
                    kind: .raw,
                    unit: .registryNative,
                    capture: capture,
                    issue: "PowerTelemetryData is not a dictionary"
                ),
                systemCurrentInNative: try invalidObservedInteger(
                    identifier:
                        "battery.powerTelemetry.systemCurrentIn",
                    source: .appleSmartBatteryPowerTelemetry,
                    kind: .raw,
                    unit: .registryNative,
                    capture: capture,
                    issue: "PowerTelemetryData is not a dictionary"
                ),
                updateToken: nil,
                freshness: freshness
            )
        }

        let systemPowerIn = try telemetryPowerReading(
            dictionary: dictionary,
            key: "SystemPowerIn",
            identifier: "battery.powerTelemetry.systemPowerIn",
            semantic: .systemInput,
            capture: capture
        )
        let systemLoad = try telemetryPowerReading(
            dictionary: dictionary,
            key: "SystemLoad",
            identifier: "battery.powerTelemetry.systemLoad",
            semantic: .systemLoad,
            capture: capture
        )
        let batteryPower = try telemetryPowerReading(
            dictionary: dictionary,
            key: "BatteryPower",
            identifier: "battery.powerTelemetry.batteryPower",
            semantic: .firmwareBatteryPowerUnresolvedSign,
            capture: capture
        )
        let systemVoltage = try observedInteger(
            properties: dictionary,
            key: "SystemVoltageIn",
            identifier:
                "battery.powerTelemetry.systemVoltageIn",
            source: .appleSmartBatteryPowerTelemetry,
            kind: .raw,
            unit: .registryNative,
            capture: capture
        )
        let systemCurrent = try observedInteger(
            properties: dictionary,
            key: "SystemCurrentIn",
            identifier:
                "battery.powerTelemetry.systemCurrentIn",
            source: .appleSmartBatteryPowerTelemetry,
            kind: .raw,
            unit: .registryNative,
            capture: capture
        )

        let token = telemetryUpdateToken([
            systemPowerIn,
            systemLoad,
            batteryPower,
        ], observed: [systemVoltage, systemCurrent])
        let freshness = try telemetryFreshness(
            updateToken: token,
            evaluatedAtContinuousNanoseconds:
                capture.endedContinuousNanoseconds
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

    private func makeAdapterCapability(
        properties: [String: Any],
        capture: MonotonicInterval
    ) throws -> AdapterCapabilityObservation {
        guard properties.keys.contains("AdapterDetails") else {
            return .canonicalFixtureMissing(capture: capture)
        }
        guard let dictionary = allowlistedDictionaryValue(
            properties["AdapterDetails"],
            allowedKeys: Self.adapterPropertyAllowlist
        )?.values else {
            return AdapterCapabilityObservation(
                presence: .invalid,
                capture: capture,
                ratedWatts: try invalidPowerReading(
                    identifier:
                        "battery.adapterCapability.ratedWatts",
                    source: .appleSmartBatteryAdapterDetails,
                    kind: .capability,
                    semantic: .adapterCapability,
                    capture: capture,
                    issue: "AdapterDetails is not a dictionary"
                ),
                adapterVoltageNative: try invalidObservedInteger(
                    identifier:
                        "battery.adapterCapability.adapterVoltage",
                    source: .appleSmartBatteryAdapterDetails,
                    kind: .capability,
                    unit: .registryNative,
                    capture: capture,
                    issue: "AdapterDetails is not a dictionary"
                ),
                adapterCurrentNative: try invalidObservedInteger(
                    identifier:
                        "battery.adapterCapability.adapterCurrent",
                    source: .appleSmartBatteryAdapterDetails,
                    kind: .capability,
                    unit: .registryNative,
                    capture: capture,
                    issue: "AdapterDetails is not a dictionary"
                )
            )
        }

        let ratedWatts = try adapterRatedWatts(
            dictionary: dictionary,
            capture: capture
        )
        let voltage = try observedInteger(
            properties: dictionary,
            key: "AdapterVoltage",
            identifier:
                "battery.adapterCapability.adapterVoltage",
            source: .appleSmartBatteryAdapterDetails,
            kind: .capability,
            unit: .registryNative,
            capture: capture
        )
        let current = try observedInteger(
            properties: dictionary,
            key: "Current",
            identifier:
                "battery.adapterCapability.adapterCurrent",
            source: .appleSmartBatteryAdapterDetails,
            kind: .capability,
            unit: .registryNative,
            capture: capture
        )

        return AdapterCapabilityObservation(
            presence: .present,
            capture: capture,
            ratedWatts: ratedWatts,
            adapterVoltageNative: voltage,
            adapterCurrentNative: current
        )
    }

    private func makeDeviceOutput(
        properties: [String: Any],
        capture: MonotonicInterval
    ) throws -> DeviceOutputObservation {
        guard properties.keys.contains("PowerOutDetails") else {
            return .canonicalFixtureMissing(capture: capture)
        }
        guard let rawEntries = arrayValue(
            properties["PowerOutDetails"]
        ) else {
            return DeviceOutputObservation(
                fieldPresence: .invalid,
                capture: capture,
                ports: [],
                measuredTotalWatts: try invalidPowerReading(
                    identifier:
                        "battery.deviceOutput.measuredTotalWatts",
                    source: .derivedAggregate,
                    kind: .derived,
                    semantic: .deviceOutputMeasuredTotal,
                    capture: capture,
                    issue: "PowerOutDetails is not an array"
                ),
                completeness: .unknown
            )
        }

        var ports: [DeviceOutputPortObservation] = []
        ports.reserveCapacity(rawEntries.count)
        for (arrayIndex, rawEntry) in rawEntries.enumerated() {
            guard let projected = allowlistedDictionaryValue(
                rawEntry,
                allowedKeys: Self.powerOutPropertyAllowlist,
                detectLocationIdentifier: true
            ) else {
                ports.append(
                    DeviceOutputPortObservation(
                        arrayIndex: arrayIndex,
                        portIndex: nil,
                        locationIdentifierWasPresent: false,
                        measuredWatts: try invalidPowerReading(
                            identifier:
                                "battery.deviceOutput.ports[\(arrayIndex)].measuredWatts",
                            source:
                                .appleSmartBatteryPowerOutWatts,
                            kind: .measured,
                            semantic: .deviceOutput,
                            capture: capture,
                            issue: "PowerOutDetails entry is not a dictionary"
                        ),
                        pdPowerRaw: try invalidPowerReading(
                            identifier:
                                "battery.deviceOutput.ports[\(arrayIndex)].pdPowerRaw",
                            source:
                                .appleSmartBatteryPowerOutPDPower,
                            kind: .raw,
                            semantic: .unknown,
                            capture: capture,
                            issue: "PowerOutDetails entry is not a dictionary"
                        )
                    )
                )
                continue
            }
            let entry = projected.values

            let portIndex = integerField(
                entry,
                key: "PortIndex"
            ).value.flatMap { value -> Int? in
                guard value >= 0,
                      value <= Int64(Int.max) else { return nil }
                return Int(value)
            }
            ports.append(
                DeviceOutputPortObservation(
                    arrayIndex: arrayIndex,
                    portIndex: portIndex,
                    locationIdentifierWasPresent:
                        projected.locationIdentifierWasPresent,
                    measuredWatts: try portMeasuredWatts(
                        entry: entry,
                        arrayIndex: arrayIndex,
                        capture: capture
                    ),
                    pdPowerRaw: try portPDPowerRaw(
                        entry: entry,
                        arrayIndex: arrayIndex,
                        capture: capture
                    )
                )
            )
        }

        let measuredPorts = ports.filter {
            $0.measuredWatts.presence == .present
        }
        let total: PowerReading
        let completeness: AggregateCompleteness
        if ports.isEmpty {
            total = try derivedDeviceOutputTotal(
                watts: 0,
                presence: .present,
                capture: capture,
                issue: nil
            )
            completeness = .complete
        } else if measuredPorts.isEmpty {
            total = try PowerReading(
                identifier:
                    "battery.deviceOutput.measuredTotalWatts",
                source: .derivedAggregate,
                kind: .derived,
                semantic: .deviceOutputMeasuredTotal,
                presence: .missing,
                rawInteger: nil,
                rawFloatingPoint: nil,
                rawUnit: nil,
                watts: nil,
                capture: capture,
                freshness: .unknown(
                    at: capture.endedContinuousNanoseconds
                ),
                validationIssue: "no measured Watts entries"
            )
            completeness = .unknown
        } else {
            let sum = measuredPorts.reduce(0.0) {
                $0 + ($1.measuredWatts.watts ?? 0)
            }
            total = try derivedDeviceOutputTotal(
                watts: sum,
                presence: .present,
                capture: capture,
                issue: nil
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

    private func observedInteger(
        properties: [String: Any],
        key: String,
        identifier: String,
        source: ObservationSource =
            .appleSmartBatteryRegistry,
        kind: ObservationKind,
        unit: ObservationUnit,
        reinterpretUnsignedUInt32AsSigned: Bool = false,
        capture: MonotonicInterval
    ) throws -> Observed<Int64> {
        let field = integerField(
            properties,
            key: key,
            reinterpretUnsignedUInt32AsSigned:
                reinterpretUnsignedUInt32AsSigned
        )
        switch field.presence {
        case .present:
            return try Observed(
                identifier: identifier,
                source: source,
                kind: kind,
                unit: unit,
                presence: .present,
                value: field.value,
                capture: capture,
                freshness: .unknown(
                    at: capture.endedContinuousNanoseconds
                ),
                validationIssue: nil
            )
        case .missing:
            return try Observed(
                identifier: identifier,
                source: source,
                kind: kind,
                unit: unit,
                presence: .missing,
                value: nil,
                capture: capture,
                freshness: .unknown(
                    at: capture.endedContinuousNanoseconds
                ),
                validationIssue: "key missing"
            )
        case .invalid:
            return try invalidObservedInteger(
                identifier: identifier,
                source: source,
                kind: kind,
                unit: unit,
                capture: capture,
                issue: field.issue ?? "invalid integer"
            )
        }
    }

    private func observedBoolean(
        properties: [String: Any],
        key: String,
        identifier: String,
        capture: MonotonicInterval
    ) throws -> Observed<Bool> {
        let field = booleanField(properties, key: key)
        return try Observed(
            identifier: identifier,
            source: .appleSmartBatteryRegistry,
            kind: .hint,
            unit: .boolean,
            presence: field.presence,
            value: field.value,
            capture: capture,
            freshness: .unknown(
                at: capture.endedContinuousNanoseconds
            ),
            validationIssue: field.presence == .invalid
                ? field.issue : field.presence == .missing
                    ? "key missing" : nil
        )
    }

    private func telemetryPowerReading(
        dictionary: [String: Any],
        key: String,
        identifier: String,
        semantic: PowerSemantic,
        reinterpretUnsignedUInt32AsSigned: Bool = false,
        capture: MonotonicInterval
    ) throws -> PowerReading {
        let field = integerField(
            dictionary,
            key: key,
            reinterpretUnsignedUInt32AsSigned:
                reinterpretUnsignedUInt32AsSigned
        )
        return try integerPowerReading(
            field: field,
            identifier: identifier,
            source: .appleSmartBatteryPowerTelemetry,
            kind: .measured,
            semantic: semantic,
            rawUnit: .milliwatts,
            normalizeToWatts: true,
            requireNonNegative: false,
            capture: capture
        )
    }

    private func adapterRatedWatts(
        dictionary: [String: Any],
        capture: MonotonicInterval
    ) throws -> PowerReading {
        try integerPowerReading(
            field: integerField(dictionary, key: "Watts"),
            identifier: "battery.adapterCapability.ratedWatts",
            source: .appleSmartBatteryAdapterDetails,
            kind: .capability,
            semantic: .adapterCapability,
            rawUnit: .watts,
            normalizeToWatts: false,
            requireNonNegative: true,
            capture: capture
        )
    }

    private func portMeasuredWatts(
        entry: [String: Any],
        arrayIndex: Int,
        capture: MonotonicInterval
    ) throws -> PowerReading {
        try integerPowerReading(
            field: integerField(entry, key: "Watts"),
            identifier:
                "battery.deviceOutput.ports[\(arrayIndex)].measuredWatts",
            source: .appleSmartBatteryPowerOutWatts,
            kind: .measured,
            semantic: .deviceOutput,
            rawUnit: .milliwatts,
            normalizeToWatts: true,
            requireNonNegative: true,
            capture: capture
        )
    }

    private func portPDPowerRaw(
        entry: [String: Any],
        arrayIndex: Int,
        capture: MonotonicInterval
    ) throws -> PowerReading {
        let field = integerField(entry, key: "PDPowermW")
        switch field.presence {
        case .present:
            return try PowerReading(
                identifier:
                    "battery.deviceOutput.ports[\(arrayIndex)].pdPowerRaw",
                source: .appleSmartBatteryPowerOutPDPower,
                kind: .raw,
                semantic: .unknown,
                presence: .present,
                rawInteger: field.value,
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
            return try PowerReading(
                identifier:
                    "battery.deviceOutput.ports[\(arrayIndex)].pdPowerRaw",
                source: .appleSmartBatteryPowerOutPDPower,
                kind: .raw,
                semantic: .unknown,
                presence: .missing,
                rawInteger: nil,
                rawFloatingPoint: nil,
                rawUnit: nil,
                watts: nil,
                capture: capture,
                freshness: .unknown(
                    at: capture.endedContinuousNanoseconds
                ),
                validationIssue: "key missing"
            )
        case .invalid:
            return try PowerReading(
                identifier:
                    "battery.deviceOutput.ports[\(arrayIndex)].pdPowerRaw",
                source: .appleSmartBatteryPowerOutPDPower,
                kind: .raw,
                semantic: .unknown,
                presence: .invalid,
                rawInteger: nil,
                rawFloatingPoint: nil,
                rawUnit: nil,
                watts: nil,
                capture: capture,
                freshness: .unknown(
                    at: capture.endedContinuousNanoseconds
                ),
                validationIssue: field.issue ?? "invalid PDPowermW"
            )
        }
    }

    private func integerPowerReading(
        field: ParsedIntegerField,
        identifier: String,
        source: ObservationSource,
        kind: ObservationKind,
        semantic: PowerSemantic,
        rawUnit: ObservationUnit,
        normalizeToWatts: Bool,
        requireNonNegative: Bool,
        capture: MonotonicInterval
    ) throws -> PowerReading {
        switch field.presence {
        case .present:
            guard let value = field.value else {
                return try invalidPowerReading(
                    identifier: identifier,
                    source: source,
                    kind: kind,
                    semantic: semantic,
                    capture: capture,
                    issue: "integer parser returned no value"
                )
            }
            guard !requireNonNegative || value >= 0 else {
                return try PowerReading(
                    identifier: identifier,
                    source: source,
                    kind: kind,
                    semantic: semantic,
                    presence: .invalid,
                    rawInteger: value,
                    rawFloatingPoint: nil,
                    rawUnit: rawUnit,
                    watts: nil,
                    capture: capture,
                    freshness: .unknown(
                        at: capture.endedContinuousNanoseconds
                    ),
                    validationIssue: "negative value is invalid"
                )
            }
            let watts = normalizeToWatts
                ? Double(value) / 1_000
                : Double(value)
            return try PowerReading(
                identifier: identifier,
                source: source,
                kind: kind,
                semantic: semantic,
                presence: .present,
                rawInteger: value,
                rawFloatingPoint: nil,
                rawUnit: rawUnit,
                watts: watts,
                capture: capture,
                freshness: .unknown(
                    at: capture.endedContinuousNanoseconds
                ),
                validationIssue: nil
            )
        case .missing:
            return try PowerReading(
                identifier: identifier,
                source: source,
                kind: kind,
                semantic: semantic,
                presence: .missing,
                rawInteger: nil,
                rawFloatingPoint: nil,
                rawUnit: nil,
                watts: nil,
                capture: capture,
                freshness: .unknown(
                    at: capture.endedContinuousNanoseconds
                ),
                validationIssue: "key missing"
            )
        case .invalid:
            return try invalidPowerReading(
                identifier: identifier,
                source: source,
                kind: kind,
                semantic: semantic,
                capture: capture,
                issue: field.issue ?? "invalid integer"
            )
        }
    }

    private func derivedDeviceOutputTotal(
        watts: Double?,
        presence: ObservationPresence,
        capture: MonotonicInterval,
        issue: String?
    ) throws -> PowerReading {
        try PowerReading(
            identifier:
                "battery.deviceOutput.measuredTotalWatts",
            source: .derivedAggregate,
            kind: .derived,
            semantic: .deviceOutputMeasuredTotal,
            presence: presence,
            rawInteger: nil,
            rawFloatingPoint: nil,
            rawUnit: nil,
            watts: watts,
            capture: capture,
            freshness: .unknown(
                at: capture.endedContinuousNanoseconds
            ),
            validationIssue: issue
        )
    }

    private func invalidObservedInteger(
        identifier: String,
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
        identifier: String,
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

    private func telemetryUpdateToken(
        _ readings: [PowerReading],
        observed: [Observed<Int64>]
    ) -> String {
        var components: [String] = []
        components.reserveCapacity(readings.count + observed.count)
        for reading in readings {
            components.append(canonicalComponent(
                identifier: reading.identifier,
                presence: reading.presence,
                rawInteger: reading.rawInteger
            ))
        }
        for value in observed {
            components.append(canonicalComponent(
                identifier: value.identifier,
                presence: value.presence,
                rawInteger: value.value
            ))
        }
        return PowerObservationSHA256.hexDigest(
            Data(components.joined(separator: "|").utf8)
        )
    }

    private func telemetryFreshness(
        updateToken: String?,
        evaluatedAtContinuousNanoseconds: UInt64
    ) throws -> FreshnessEvidence {
        trackerLock.lock()
        defer { trackerLock.unlock() }
        return try telemetryFreezeTracker.observe(
            updateToken: updateToken,
            evaluatedAtContinuousNanoseconds:
                evaluatedAtContinuousNanoseconds
        )
    }

    private func canonicalComponent(
        identifier: String,
        presence: ObservationPresence,
        rawInteger: Int64?
    ) -> String {
        switch presence {
        case .present:
            return "\(identifier)=present:\(rawInteger ?? 0)"
        case .missing:
            return "\(identifier)=missing"
        case .invalid:
            return "\(identifier)=invalid"
        }
    }
}

private struct ParsedIntegerField {
    let presence: ObservationPresence
    let value: Int64?
    let issue: String?
}

private struct ParsedBooleanField {
    let presence: ObservationPresence
    let value: Bool?
    let issue: String?
}

private struct AllowlistedDictionaryValue {
    let values: [String: Any]
    let locationIdentifierWasPresent: Bool
}

private func allowlistedDictionaryValue(
    _ raw: Any?,
    allowedKeys: [String],
    detectLocationIdentifier: Bool = false
) -> AllowlistedDictionaryValue? {
    let locationKey = "Location" + "ID"
    var values: [String: Any] = [:]
    let locationIdentifierWasPresent: Bool

    if let dictionary = raw as? NSDictionary {
        for key in allowedKeys {
            if let value = dictionary.object(forKey: key) {
                values[key] = value
            }
        }
        locationIdentifierWasPresent = detectLocationIdentifier
            && dictionaryContainsKey(dictionary, key: locationKey)
    } else {
        return nil
    }

    return AllowlistedDictionaryValue(
        values: values,
        locationIdentifierWasPresent:
            locationIdentifierWasPresent
    )
}

private func dictionaryContainsKey(
    _ dictionary: NSDictionary,
    key: String
) -> Bool {
    let cfKey = key as CFString
    return CFDictionaryContainsKey(
        dictionary as CFDictionary,
        Unmanaged.passUnretained(cfKey).toOpaque()
    )
}

private func arrayValue(_ raw: Any?) -> [Any]? {
    if let array = raw as? [Any] { return array }
    if let array = raw as? NSArray { return array.map { $0 } }
    return nil
}

private func numberIsFloatingPoint(_ number: NSNumber) -> Bool {
    let type = String(cString: number.objCType)
    return type == "f" || type == "d"
}

private func integerField(
    _ properties: [String: Any],
    key: String,
    reinterpretUnsignedUInt32AsSigned: Bool = false
) -> ParsedIntegerField {
    guard properties.keys.contains(key) else {
        return ParsedIntegerField(
            presence: .missing,
            value: nil,
            issue: "key missing"
        )
    }
    guard let number = properties[key] as? NSNumber,
          CFGetTypeID(number) != CFBooleanGetTypeID(),
          !numberIsFloatingPoint(number) else {
        return ParsedIntegerField(
            presence: .invalid,
            value: nil,
            issue: "value is not an integer number"
        )
    }
    let type = String(cString: number.objCType)
    let unsignedTypes: Set<String> = ["C", "S", "I", "L", "Q"]
    let exactValue: Int64
    if unsignedTypes.contains(type) {
        let unsignedValue = number.uint64Value
        if reinterpretUnsignedUInt32AsSigned,
           unsignedValue > UInt64(Int64.max) {
            exactValue = Int64(bitPattern: unsignedValue)
        } else if unsignedValue <= UInt64(Int64.max) {
            exactValue = Int64(unsignedValue)
        } else {
            return ParsedIntegerField(
                presence: .invalid,
                value: nil,
                issue: "unsigned integer exceeds Int64.max"
            )
        }
    } else {
        exactValue = number.int64Value
    }
    let value: Int64
    if reinterpretUnsignedUInt32AsSigned,
       exactValue > Int64(Int32.max),
       exactValue <= Int64(UInt32.max) {
        value = Int64(Int32(bitPattern: UInt32(exactValue)))
    } else {
        value = exactValue
    }
    return ParsedIntegerField(
        presence: .present,
        value: value,
        issue: nil
    )
}

private func booleanField(
    _ properties: [String: Any],
    key: String
) -> ParsedBooleanField {
    guard properties.keys.contains(key) else {
        return ParsedBooleanField(
            presence: .missing,
            value: nil,
            issue: "key missing"
        )
    }
    guard let number = properties[key] as? NSNumber else {
        return ParsedBooleanField(
            presence: .invalid,
            value: nil,
            issue: "value is not a boolean"
        )
    }
    if CFGetTypeID(number) == CFBooleanGetTypeID() {
        return ParsedBooleanField(
            presence: .present,
            value: number.boolValue,
            issue: nil
        )
    }
    guard !numberIsFloatingPoint(number) else {
        return ParsedBooleanField(
            presence: .invalid,
            value: nil,
            issue: "value is not a boolean"
        )
    }
    let value = number.int64Value
    guard value == 0 || value == 1 else {
        return ParsedBooleanField(
            presence: .invalid,
            value: nil,
            issue: "integer boolean must be 0 or 1"
        )
    }
    return ParsedBooleanField(
        presence: .present,
        value: value == 1,
        issue: nil
    )
}

struct SystemAppleSmartBatteryRawSnapshotReader:
    AppleSmartBatteryRawSnapshotReading
{
    func readAllowlistedProperties(
        _ keys: [String]
    ) -> AppleSmartBatteryRawSnapshot {
#if canImport(IOKit) && os(macOS)
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSmartBattery")
        )
        guard service != IO_OBJECT_NULL else {
            return AppleSmartBatteryRawSnapshot(
                servicePresent: false,
                properties: [:]
            )
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
        return AppleSmartBatteryRawSnapshot(
            servicePresent: true,
            properties: properties
        )
#else
        return AppleSmartBatteryRawSnapshot(
            servicePresent: false,
            properties: [:]
        )
#endif
    }
}

private enum PowerObservationSHA256 {
    private static let initialHash: [UInt32] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
        0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
    ]

    private static let roundConstants: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
        0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
        0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
        0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
        0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
        0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
        0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
        0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
        0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ]

    static func hexDigest(_ data: Data) -> String {
        var message = [UInt8](data)
        let bitLength = UInt64(message.count) * 8
        message.append(0x80)
        while message.count % 64 != 56 { message.append(0) }
        for shift in stride(from: 56, through: 0, by: -8) {
            message.append(UInt8((bitLength >> UInt64(shift)) & 0xff))
        }

        var hash = initialHash
        for offset in stride(from: 0, to: message.count, by: 64) {
            var words = [UInt32](repeating: 0, count: 64)
            for index in 0..<16 {
                let base = offset + index * 4
                words[index] = UInt32(message[base]) << 24
                    | UInt32(message[base + 1]) << 16
                    | UInt32(message[base + 2]) << 8
                    | UInt32(message[base + 3])
            }
            for index in 16..<64 {
                let s0 = rotateRight(words[index - 15], by: 7)
                    ^ rotateRight(words[index - 15], by: 18)
                    ^ (words[index - 15] >> 3)
                let s1 = rotateRight(words[index - 2], by: 17)
                    ^ rotateRight(words[index - 2], by: 19)
                    ^ (words[index - 2] >> 10)
                words[index] = words[index - 16]
                    &+ s0 &+ words[index - 7] &+ s1
            }

            var a = hash[0]
            var b = hash[1]
            var c = hash[2]
            var d = hash[3]
            var e = hash[4]
            var f = hash[5]
            var g = hash[6]
            var h = hash[7]

            for index in 0..<64 {
                let bigS1 = rotateRight(e, by: 6)
                    ^ rotateRight(e, by: 11)
                    ^ rotateRight(e, by: 25)
                let choice = (e & f) ^ ((~e) & g)
                let temporary1 = h &+ bigS1 &+ choice
                    &+ roundConstants[index] &+ words[index]
                let bigS0 = rotateRight(a, by: 2)
                    ^ rotateRight(a, by: 13)
                    ^ rotateRight(a, by: 22)
                let majority = (a & b) ^ (a & c) ^ (b & c)
                let temporary2 = bigS0 &+ majority

                h = g
                g = f
                f = e
                e = d &+ temporary1
                d = c
                c = b
                b = a
                a = temporary1 &+ temporary2
            }

            hash[0] &+= a
            hash[1] &+= b
            hash[2] &+= c
            hash[3] &+= d
            hash[4] &+= e
            hash[5] &+= f
            hash[6] &+= g
            hash[7] &+= h
        }
        return hash.map { String(format: "%08x", $0) }.joined()
    }

    private static func rotateRight(
        _ value: UInt32,
        by amount: UInt32
    ) -> UInt32 {
        (value >> amount) | (value << (32 - amount))
    }
}

#endif
