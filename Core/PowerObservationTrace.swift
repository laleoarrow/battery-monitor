import Foundation

// MARK: - Trace schema

enum TraceTermination:
    String,
    Codable,
    Equatable,
    Sendable
{
    case completed
    case interrupted
    case sizeLimit
    case fatalError
}

struct PowerObservationTraceHeader:
    Codable,
    Equatable,
    Sendable
{
    let captureTool: String
    let captureToolVersion: Int
    let scenario: String
    let requestedIntervalMilliseconds: Int
    let requestedDurationSeconds: Int
    let startedContinuousNanoseconds: UInt64
    let macModel: String
    let architecture: String
    let operatingSystemVersion: String
    let operatingSystemBuild: String
}

struct PowerObservationTraceFooter:
    Codable,
    Equatable,
    Sendable
{
    let termination: TraceTermination
    let samplesWritten: UInt64
    let bytesWritten: UInt64
    let endedContinuousNanoseconds: UInt64
    let terminationSignal: Int32?
    let fatalErrorCode: String?
}

enum KnownPowerObservationTraceRecordType:
    String,
    Codable,
    Equatable,
    Sendable
{
    case header
    case sample
    case footer
}

enum PowerObservationTraceRecordError:
    Error,
    Equatable
{
    case invalidSchemaVersion(Int)
    case unknownRecordType(String)
    case invalidPayloadCombination(
        recordType: String
    )
}

struct PowerObservationTraceRecord:
    Codable,
    Equatable,
    Sendable
{
    let schemaVersion: Int
    let recordType: String
    let header: PowerObservationTraceHeader?
    let sample: RawPowerObservation?
    let footer: PowerObservationTraceFooter?

    init(
        header: PowerObservationTraceHeader
    ) {
        schemaVersion = 1
        recordType =
            KnownPowerObservationTraceRecordType
                .header.rawValue
        self.header = header
        sample = nil
        footer = nil
    }

    init(sample: RawPowerObservation) {
        schemaVersion = 1
        recordType =
            KnownPowerObservationTraceRecordType
                .sample.rawValue
        header = nil
        self.sample = sample
        footer = nil
    }

    init(
        footer: PowerObservationTraceFooter
    ) {
        schemaVersion = 1
        recordType =
            KnownPowerObservationTraceRecordType
                .footer.rawValue
        header = nil
        sample = nil
        self.footer = footer
    }

    private enum CodingKeys:
        String,
        CodingKey
    {
        case schemaVersion
        case recordType
        case header
        case sample
        case footer
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )
        let schemaVersion = try container.decode(
            Int.self,
            forKey: .schemaVersion
        )
        guard schemaVersion == 1 else {
            throw PowerObservationTraceRecordError
                .invalidSchemaVersion(
                    schemaVersion
                )
        }
        let recordType = try container.decode(
            String.self,
            forKey: .recordType
        )
        let header = try container.decodeRequiredNullable(
            PowerObservationTraceHeader.self,
            forKey: .header
        )
        let sample = try container.decodeRequiredNullable(
            RawPowerObservation.self,
            forKey: .sample
        )
        let footer = try container.decodeRequiredNullable(
            PowerObservationTraceFooter.self,
            forKey: .footer
        )

        let valid: Bool
        switch recordType {
        case KnownPowerObservationTraceRecordType
            .header.rawValue:
            valid =
                header != nil
                && sample == nil
                && footer == nil
        case KnownPowerObservationTraceRecordType
            .sample.rawValue:
            valid =
                header == nil
                && sample != nil
                && footer == nil
        case KnownPowerObservationTraceRecordType
            .footer.rawValue:
            valid =
                header == nil
                && sample == nil
                && footer != nil
        default:
            throw PowerObservationTraceRecordError
                .unknownRecordType(
                    recordType
                )
        }
        guard valid else {
            throw PowerObservationTraceRecordError
                .invalidPayloadCombination(
                    recordType: recordType
                )
        }

        self.schemaVersion = schemaVersion
        self.recordType = recordType
        self.header = header
        self.sample = sample
        self.footer = footer
    }

    func encode(
        to encoder: Encoder
    ) throws {
        var container = encoder.container(
            keyedBy: CodingKeys.self
        )
        try container.encode(
            schemaVersion,
            forKey: .schemaVersion
        )
        try container.encode(
            recordType,
            forKey: .recordType
        )
        try container.encodeRequiredNullable(
            header,
            forKey: .header
        )
        try container.encodeRequiredNullable(
            sample,
            forKey: .sample
        )
        try container.encodeRequiredNullable(
            footer,
            forKey: .footer
        )
    }
}

enum PowerObservationTraceDecodeEvent:
    Equatable,
    Sendable
{
    case record(
        lineNumber: Int,
        record: PowerObservationTraceRecord
    )
    case skippedUnknownRecordType(
        lineNumber: Int,
        schemaVersion: Int,
        recordType: String
    )
    case unsupportedSchema(
        lineNumber: Int,
        schemaVersion: Int
    )
    case malformed(
        lineNumber: Int,
        message: String
    )
    case ignoredUnterminatedFinalFragment(
        lineNumber: Int,
        byteCount: Int
    )
}

struct PowerObservationTraceDecodingSummary:
    Equatable,
    Sendable
{
    let events: [
        PowerObservationTraceDecodeEvent
    ]

    var records: [
        PowerObservationTraceRecord
    ] {
        events.compactMap { event in
            guard case let .record(
                _,
                record
            ) = event else {
                return nil
            }
            return record
        }
    }

    var samples: [
        RawPowerObservation
    ] {
        records.compactMap(\.sample)
    }
}

struct PowerObservationTraceDecoder {
    static let supportedSchemaVersion = 1

    private struct EnvelopeProbe:
        Decodable
    {
        let schemaVersion: Int
        let recordType: String
    }

    func decodeJSONL(
        _ data: Data
    ) -> PowerObservationTraceDecodingSummary {
        var events:
            [PowerObservationTraceDecodeEvent] = []
        var lineStart = data.startIndex
        var lineNumber = 1

        for index in data.indices
        where data[index] == 0x0A {
            let line = Data(
                data[lineStart..<index]
            )
            events.append(
                decodeTerminatedLine(
                    line,
                    lineNumber: lineNumber
                )
            )
            lineStart = data.index(
                after: index
            )
            lineNumber += 1
        }

        if lineStart < data.endIndex {
            events.append(
                .ignoredUnterminatedFinalFragment(
                    lineNumber: lineNumber,
                    byteCount: data.distance(
                        from: lineStart,
                        to: data.endIndex
                    )
                )
            )
        }

        return PowerObservationTraceDecodingSummary(
            events: events
        )
    }

    func decodeTerminatedLine(
        _ line: Data,
        lineNumber: Int
    ) -> PowerObservationTraceDecodeEvent {
        let decoder = JSONDecoder()
        let probe: EnvelopeProbe

        do {
            probe = try decoder.decode(
                EnvelopeProbe.self,
                from: line
            )
        } catch {
            return .malformed(
                lineNumber: lineNumber,
                message: String(
                    describing: error
                )
            )
        }

        if probe.schemaVersion
            > Self.supportedSchemaVersion {
            return .unsupportedSchema(
                lineNumber: lineNumber,
                schemaVersion:
                    probe.schemaVersion
            )
        }

        if probe.schemaVersion <= 0 {
            return .malformed(
                lineNumber: lineNumber,
                message:
                    "schemaVersion must be positive"
            )
        }

        guard KnownPowerObservationTraceRecordType(
            rawValue: probe.recordType
        ) != nil else {
            return .skippedUnknownRecordType(
                lineNumber: lineNumber,
                schemaVersion:
                    probe.schemaVersion,
                recordType:
                    probe.recordType
            )
        }

        do {
            let record = try decoder.decode(
                PowerObservationTraceRecord.self,
                from: line
            )
            return .record(
                lineNumber: lineNumber,
                record: record
            )
        } catch {
            return .malformed(
                lineNumber: lineNumber,
                message: String(
                    describing: error
                )
            )
        }
    }
}

// MARK: - Replay

struct ObservationPresenceKey:
    Hashable,
    Equatable,
    Sendable
{
    let fieldPath: String
    let source: ObservationSource
}

struct ObservationPresenceEntry:
    Equatable,
    Sendable
{
    let key: ObservationPresenceKey
    let presence: ObservationPresence
}

struct SourceAvailabilityTransition:
    Codable,
    Equatable,
    Sendable
{
    let atSequence: UInt64
    let fieldPath: String
    let source: ObservationSource
    let previousPresence:
        ObservationPresence
    let currentPresence:
        ObservationPresence
}

struct ReplayedPowerObservation:
    Equatable,
    Sendable
{
    let observation: RawPowerObservation
    let transitions:
        [SourceAvailabilityTransition]
}

enum PowerObservationReplayError:
    Error,
    Equatable
{
    case nonMonotonicSequence(
        previous: UInt64,
        current: UInt64
    )
}

struct PowerObservationReplay {
    private var previousPresence:
        [ObservationPresenceKey:
         ObservationPresence] = [:]

    private(set) var lastSequence: UInt64?

    init() {}

    mutating func consume(
        _ observation: RawPowerObservation
    ) throws -> ReplayedPowerObservation {
        if let lastSequence,
           observation.sequence <= lastSequence {
            throw PowerObservationReplayError
                .nonMonotonicSequence(
                    previous: lastSequence,
                    current:
                        observation.sequence
                )
        }

        let entries =
            observation.replayPresenceEntries()
        var transitions:
            [SourceAvailabilityTransition] = []

        for entry in entries {
            if let previous =
                previousPresence[entry.key],
               previous != entry.presence {
                transitions.append(
                    SourceAvailabilityTransition(
                        atSequence:
                            observation.sequence,
                        fieldPath:
                            entry.key.fieldPath,
                        source:
                            entry.key.source,
                        previousPresence:
                            previous,
                        currentPresence:
                            entry.presence
                    )
                )
            }
            previousPresence[entry.key] =
                entry.presence
        }

        transitions.sort {
            if $0.fieldPath != $1.fieldPath {
                return $0.fieldPath
                    < $1.fieldPath
            }
            return $0.source.rawValue
                < $1.source.rawValue
        }

        lastSequence = observation.sequence

        return ReplayedPowerObservation(
            observation: observation,
            transitions: transitions
        )
    }
}

extension RawPowerObservation {
    func replayPresenceEntries()
        -> [ObservationPresenceEntry]
    {
        func entry(
            _ fieldPath: String,
            _ source: ObservationSource,
            _ presence: ObservationPresence
        ) -> ObservationPresenceEntry {
            ObservationPresenceEntry(
                key: ObservationPresenceKey(
                    fieldPath: fieldPath,
                    source: source
                ),
                presence: presence
            )
        }

        var result:
            [ObservationPresenceEntry] = [
                entry(
                    "battery.service",
                    .appleSmartBatteryRegistry,
                    battery.servicePresence
                ),
                entry(
                    "battery.currentCapacity",
                    battery.currentCapacity.source,
                    battery.currentCapacity.presence
                ),
                entry(
                    "battery.maxCapacity",
                    battery.maxCapacity.source,
                    battery.maxCapacity.presence
                ),
                entry(
                    "battery.externalConnected",
                    battery.externalConnected.source,
                    battery.externalConnected.presence
                ),
                entry(
                    "battery.isCharging",
                    battery.isCharging.source,
                    battery.isCharging.presence
                ),
                entry(
                    "battery.voltageMillivolts",
                    battery.voltageMillivolts.source,
                    battery.voltageMillivolts.presence
                ),
                entry(
                    "battery.instantAmperageMilliamps",
                    battery.instantAmperageMilliamps.source,
                    battery.instantAmperageMilliamps.presence
                ),
                entry(
                    "battery.averageAmperageMilliamps",
                    battery.averageAmperageMilliamps.source,
                    battery.averageAmperageMilliamps.presence
                ),
                entry(
                    "battery.powerTelemetry.systemPowerIn",
                    battery.powerTelemetry.systemPowerIn.source,
                    battery.powerTelemetry.systemPowerIn.presence
                ),
                entry(
                    "battery.powerTelemetry.systemLoad",
                    battery.powerTelemetry.systemLoad.source,
                    battery.powerTelemetry.systemLoad.presence
                ),
                entry(
                    "battery.powerTelemetry.batteryPower",
                    battery.powerTelemetry.batteryPower.source,
                    battery.powerTelemetry.batteryPower.presence
                ),
                entry(
                    "battery.powerTelemetry.systemVoltageIn",
                    battery.powerTelemetry.systemVoltageInNative.source,
                    battery.powerTelemetry.systemVoltageInNative.presence
                ),
                entry(
                    "battery.powerTelemetry.systemCurrentIn",
                    battery.powerTelemetry.systemCurrentInNative.source,
                    battery.powerTelemetry.systemCurrentInNative.presence
                ),
                entry(
                    "battery.adapterCapability.ratedWatts",
                    battery.adapterCapability.ratedWatts.source,
                    battery.adapterCapability.ratedWatts.presence
                ),
                entry(
                    "battery.adapterCapability.adapterVoltage",
                    battery.adapterCapability.adapterVoltageNative.source,
                    battery.adapterCapability.adapterVoltageNative.presence
                ),
                entry(
                    "battery.adapterCapability.adapterCurrent",
                    battery.adapterCapability.adapterCurrentNative.source,
                    battery.adapterCapability.adapterCurrentNative.presence
                ),
                entry(
                    "battery.deviceOutput.field",
                    .appleSmartBatteryRegistry,
                    battery.deviceOutput.fieldPresence
                ),
                entry(
                    "battery.deviceOutput.measuredTotalWatts",
                    battery.deviceOutput.measuredTotalWatts.source,
                    battery.deviceOutput.measuredTotalWatts.presence
                ),
                entry(
                    "evidence.batteryVoltageTimesCurrent",
                    evidence.batteryVoltageTimesCurrent.source,
                    evidence.batteryVoltageTimesCurrent.presence
                ),
                entry(
                    "evidence.systemVoltageTimesCurrent",
                    evidence.systemVoltageTimesCurrent.source,
                    evidence.systemVoltageTimesCurrent.presence
                ),
            ]

        for keyName
        in SMCObservation.requiredKeyOrder {
            if let key = smc.key(keyName) {
                let presence:
                    ObservationPresence =
                    key.status == .present
                    ? .present
                    : .missing
                result.append(
                    entry(
                        "smc.\(keyName)",
                        key.source,
                        presence
                    )
                )
            }
        }

        return result
    }
}



// MARK: - Strict trace payload Codable

private enum TraceFooterValidationError: Error, Equatable {
    case invalidCompletedPayload
    case invalidInterruptedPayload
    case invalidSizeLimitPayload
    case invalidFatalPayload
}

extension PowerObservationTraceFooter {
    private enum CodingKeys: String, CodingKey {
        case termination
        case samplesWritten
        case bytesWritten
        case endedContinuousNanoseconds
        case terminationSignal
        case fatalErrorCode
    }

    private static let allowedFatalErrorCodes: Set<String> = [
        "battery-reader-failed",
        "smc-reader-failed",
        "collector-failed",
        "encoding-failed",
    ]

    fileprivate func validateContract() throws {
        switch termination {
        case .completed:
            guard terminationSignal == nil,
                  fatalErrorCode == nil else {
                throw TraceFooterValidationError.invalidCompletedPayload
            }
        case .interrupted:
            guard terminationSignal != nil,
                  fatalErrorCode == nil else {
                throw TraceFooterValidationError.invalidInterruptedPayload
            }
        case .sizeLimit:
            guard terminationSignal == nil,
                  fatalErrorCode == nil else {
                throw TraceFooterValidationError.invalidSizeLimitPayload
            }
        case .fatalError:
            guard terminationSignal == nil,
                  let fatalErrorCode,
                  Self.allowedFatalErrorCodes.contains(fatalErrorCode) else {
                throw TraceFooterValidationError.invalidFatalPayload
            }
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            termination: try container.decode(TraceTermination.self, forKey: .termination),
            samplesWritten: try container.decode(UInt64.self, forKey: .samplesWritten),
            bytesWritten: try container.decode(UInt64.self, forKey: .bytesWritten),
            endedContinuousNanoseconds: try container.decode(
                UInt64.self,
                forKey: .endedContinuousNanoseconds
            ),
            terminationSignal: try container.decodeRequiredNullable(
                Int32.self,
                forKey: .terminationSignal
            ),
            fatalErrorCode: try container.decodeRequiredNullable(
                String.self,
                forKey: .fatalErrorCode
            )
        )
        do {
            try validateContract()
        } catch {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: String(describing: error)
                )
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        do {
            try validateContract()
        } catch {
            throw EncodingError.invalidValue(
                self,
                EncodingError.Context(
                    codingPath: encoder.codingPath,
                    debugDescription: String(describing: error)
                )
            )
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(termination, forKey: .termination)
        try container.encode(samplesWritten, forKey: .samplesWritten)
        try container.encode(bytesWritten, forKey: .bytesWritten)
        try container.encode(
            endedContinuousNanoseconds,
            forKey: .endedContinuousNanoseconds
        )
        try container.encodeRequiredNullable(
            terminationSignal,
            forKey: .terminationSignal
        )
        try container.encodeRequiredNullable(
            fatalErrorCode,
            forKey: .fatalErrorCode
        )
    }
}
