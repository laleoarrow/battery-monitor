import Foundation

// MARK: - Open string identifiers

struct ObservationSource: RawRepresentable, Codable, Hashable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(_ rawValue: String) {
        self.init(rawValue: rawValue)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension ObservationSource {
    static let appleSmartBatteryRegistry =
        ObservationSource("appleSmartBattery.registry")
    static let appleSmartBatteryPowerTelemetry =
        ObservationSource("appleSmartBattery.powerTelemetry")
    static let appleSmartBatteryAdapterDetails =
        ObservationSource("appleSmartBattery.adapterDetails")
    static let appleSmartBatteryPowerOutWatts =
        ObservationSource("appleSmartBattery.powerOutDetails.watts")
    static let appleSmartBatteryPowerOutPDPower =
        ObservationSource("appleSmartBattery.powerOutDetails.pdPower")

    static let smcPDTR = ObservationSource("smc.PDTR")
    static let smcPSTR = ObservationSource("smc.PSTR")
    static let smcPPBR = ObservationSource("smc.PPBR")

    static let derivedBatteryVI =
        ObservationSource("derived.batteryVoltageTimesCurrent")
    static let derivedSystemInputVI =
        ObservationSource("derived.systemVoltageTimesCurrent")
    static let derivedAggregate =
        ObservationSource("derived.aggregate")
    static let fixtureAnnotation =
        ObservationSource("fixture.annotation")

    static let legacyHelperV4 =
        ObservationSource("helper.v4.legacy")
    static let helperV5 =
        ObservationSource("helper.v5")
}

struct PowerSemantic: RawRepresentable, Codable, Hashable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(_ rawValue: String) {
        self.init(rawValue: rawValue)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension PowerSemantic {
    static let adapterInput = PowerSemantic("adapterInput")
    static let systemInput = PowerSemantic("systemInput")
    static let systemLoad = PowerSemantic("systemLoad")
    static let platformConsumption =
        PowerSemantic("platformConsumption")
    static let pstrPlatformConsumptionRaw =
        PowerSemantic("pstrPlatformConsumptionRaw")
    static let batteryFlowIntoBatteryPositive =
        PowerSemantic("batteryFlowIntoBatteryPositive")
    static let firmwareBatteryPowerUnresolvedSign =
        PowerSemantic("firmwareBatteryPowerUnresolvedSign")
    static let batteryDischargeMagnitude =
        PowerSemantic("batteryDischargeMagnitude")
    static let deviceOutput = PowerSemantic("deviceOutput")
    static let deviceOutputMeasuredTotal =
        PowerSemantic("deviceOutputMeasuredTotal")
    static let adapterCapability =
        PowerSemantic("adapterCapability")
    static let batteryVoltageTimesCurrent =
        PowerSemantic("batteryVoltageTimesCurrent")
    static let systemVoltageTimesCurrent =
        PowerSemantic("systemVoltageTimesCurrent")
    static let unknown = PowerSemantic("unknown")

    // Decode-only compatibility value. Schema-v1 emitters must not use it.
    static let externalDeviceOutputLegacy =
        PowerSemantic("externalDeviceOutput")
}

// MARK: - Primitive schema

enum ObservationKind: String, Codable, Equatable, Sendable {
    case raw
    case hint
    case capability
    case measured
    case derived
}

enum ObservationUnit: String, Codable, Equatable, Sendable {
    case none
    case unknown
    case boolean
    case count
    case registryNative
    case millivolts
    case milliamps
    case milliwatts
    case watts
    case nanoseconds
    case milliseconds
}

enum ObservationPresence: String, Codable, Equatable, Sendable {
    case present
    case missing
    case invalid
}

enum MonotonicIntervalError: Error, Equatable {
    case endPrecedesStart(started: UInt64, ended: UInt64)
}

struct MonotonicInterval: Codable, Equatable, Sendable {
    let startedContinuousNanoseconds: UInt64
    let endedContinuousNanoseconds: UInt64

    init(
        startedContinuousNanoseconds: UInt64,
        endedContinuousNanoseconds: UInt64
    ) throws {
        guard endedContinuousNanoseconds
                >= startedContinuousNanoseconds
        else {
            throw MonotonicIntervalError.endPrecedesStart(
                started: startedContinuousNanoseconds,
                ended: endedContinuousNanoseconds
            )
        }
        self.startedContinuousNanoseconds =
            startedContinuousNanoseconds
        self.endedContinuousNanoseconds =
            endedContinuousNanoseconds
    }

    var durationNanoseconds: UInt64 {
        endedContinuousNanoseconds
            - startedContinuousNanoseconds
    }

    var durationMilliseconds: Double {
        Double(durationNanoseconds) / 1_000_000
    }

    var midpointContinuousNanoseconds: UInt64 {
        startedContinuousNanoseconds
            + durationNanoseconds / 2
    }

    private enum CodingKeys: String, CodingKey {
        case startedContinuousNanoseconds
        case endedContinuousNanoseconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )
        let started = try container.decode(
            UInt64.self,
            forKey: .startedContinuousNanoseconds
        )
        let ended = try container.decode(
            UInt64.self,
            forKey: .endedContinuousNanoseconds
        )
        guard ended >= started else {
            throw DecodingError.dataCorruptedError(
                forKey: .endedContinuousNanoseconds,
                in: container,
                debugDescription:
                    "endedContinuousNanoseconds must be >= startedContinuousNanoseconds"
            )
        }
        startedContinuousNanoseconds = started
        endedContinuousNanoseconds = ended
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(
            keyedBy: CodingKeys.self
        )
        try container.encode(
            startedContinuousNanoseconds,
            forKey: .startedContinuousNanoseconds
        )
        try container.encode(
            endedContinuousNanoseconds,
            forKey: .endedContinuousNanoseconds
        )
    }
}

enum FreshnessAssessment:
    String,
    Codable,
    Equatable,
    Sendable
{
    case unknown
    case changed
    case unchanged
    case stale
}

enum FreshnessBasis:
    String,
    Codable,
    Equatable,
    Sendable
{
    case none
    case derivedUpdateToken
    case fixtureAnnotation
    case sourceReported
}

enum ObservationValidationError: Error, Equatable {
    case emptyIdentifier
    case presentValueMissing(identifier: String)
    case nonPresentValueProvided(identifier: String)
    case invalidIssueMissing(identifier: String)
    case rawPayloadConflict(identifier: String)
    case rawUnitMissing(identifier: String)
    case rawUnitWithoutPayload(identifier: String)
    case missingReadingHasPayload(identifier: String)
    case invalidReadingHasWatts(identifier: String)
    case nonFiniteNumber(identifier: String)
    case invalidFreshness(String)
}

struct FreshnessEvidence:
    Codable,
    Equatable,
    Sendable
{
    let evaluatedAtContinuousNanoseconds: UInt64
    let ageMilliseconds: Double?
    let updateToken: String?
    let unchangedSinceContinuousNanoseconds: UInt64?
    let unchangedForMilliseconds: Double?
    let assessment: FreshnessAssessment
    let basis: FreshnessBasis

    init(
        evaluatedAtContinuousNanoseconds: UInt64,
        ageMilliseconds: Double?,
        updateToken: String?,
        unchangedSinceContinuousNanoseconds: UInt64?,
        unchangedForMilliseconds: Double?,
        assessment: FreshnessAssessment,
        basis: FreshnessBasis
    ) throws {
        if let ageMilliseconds,
           (!ageMilliseconds.isFinite
            || ageMilliseconds < 0) {
            throw ObservationValidationError.invalidFreshness(
                "ageMilliseconds must be finite and non-negative"
            )
        }
        if let unchangedSinceContinuousNanoseconds,
           unchangedSinceContinuousNanoseconds
             > evaluatedAtContinuousNanoseconds {
            throw ObservationValidationError.invalidFreshness(
                "unchangedSinceContinuousNanoseconds cannot be after evaluation"
            )
        }
        if let unchangedForMilliseconds,
           (!unchangedForMilliseconds.isFinite
            || unchangedForMilliseconds < 0) {
            throw ObservationValidationError.invalidFreshness(
                "unchangedForMilliseconds must be finite and non-negative"
            )
        }
        if assessment == .stale,
           basis != .fixtureAnnotation,
           basis != .sourceReported {
            throw ObservationValidationError.invalidFreshness(
                "stale requires fixtureAnnotation or sourceReported"
            )
        }
        self.evaluatedAtContinuousNanoseconds =
            evaluatedAtContinuousNanoseconds
        self.ageMilliseconds = ageMilliseconds
        self.updateToken = updateToken
        self.unchangedSinceContinuousNanoseconds =
            unchangedSinceContinuousNanoseconds
        self.unchangedForMilliseconds =
            unchangedForMilliseconds
        self.assessment = assessment
        self.basis = basis
    }

    static func unknown(
        at nanoseconds: UInt64
    ) -> FreshnessEvidence {
        try! FreshnessEvidence(
            evaluatedAtContinuousNanoseconds: nanoseconds,
            ageMilliseconds: nil,
            updateToken: nil,
            unchangedSinceContinuousNanoseconds: nil,
            unchangedForMilliseconds: nil,
            assessment: .unknown,
            basis: .none
        )
    }
}

struct Observed<Value>:
    Codable,
    Equatable,
    Sendable
where Value: Codable & Equatable & Sendable {
    let identifier: String
    let source: ObservationSource
    let kind: ObservationKind
    let unit: ObservationUnit
    let presence: ObservationPresence
    let value: Value?
    let capture: MonotonicInterval
    let freshness: FreshnessEvidence
    let validationIssue: String?

    init(
        identifier: String,
        source: ObservationSource,
        kind: ObservationKind,
        unit: ObservationUnit,
        presence: ObservationPresence,
        value: Value?,
        capture: MonotonicInterval,
        freshness: FreshnessEvidence,
        validationIssue: String?
    ) throws {
        guard !identifier.isEmpty else {
            throw ObservationValidationError.emptyIdentifier
        }
        switch presence {
        case .present:
            guard value != nil else {
                throw ObservationValidationError
                    .presentValueMissing(
                        identifier: identifier
                    )
            }
        case .missing:
            guard value == nil else {
                throw ObservationValidationError
                    .nonPresentValueProvided(
                        identifier: identifier
                    )
            }
            guard freshness.ageMilliseconds == nil else {
                throw ObservationValidationError
                    .invalidFreshness(
                        "missing values cannot have ageMilliseconds"
                    )
            }
        case .invalid:
            guard value == nil else {
                throw ObservationValidationError
                    .nonPresentValueProvided(
                        identifier: identifier
                    )
            }
            guard let validationIssue,
                  !validationIssue.isEmpty else {
                throw ObservationValidationError
                    .invalidIssueMissing(
                        identifier: identifier
                    )
            }
        }

        self.identifier = identifier
        self.source = source
        self.kind = kind
        self.unit = unit
        self.presence = presence
        self.value = value
        self.capture = capture
        self.freshness = freshness
        self.validationIssue = validationIssue
    }

    static func canonicalFixtureMissing(
        identifier: String,
        source: ObservationSource,
        kind: ObservationKind,
        unit: ObservationUnit,
        capture: MonotonicInterval
    ) -> Observed<Value> {
        try! Observed(
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
            validationIssue: "fixture missing"
        )
    }
}

struct PowerReading:
    Codable,
    Equatable,
    Sendable
{
    let identifier: String
    let source: ObservationSource
    let kind: ObservationKind
    let semantic: PowerSemantic
    let presence: ObservationPresence
    let rawInteger: Int64?
    let rawFloatingPoint: Double?
    let rawUnit: ObservationUnit?
    let watts: Double?
    let capture: MonotonicInterval
    let freshness: FreshnessEvidence
    let validationIssue: String?

    init(
        identifier: String,
        source: ObservationSource,
        kind: ObservationKind,
        semantic: PowerSemantic,
        presence: ObservationPresence,
        rawInteger: Int64?,
        rawFloatingPoint: Double?,
        rawUnit: ObservationUnit?,
        watts: Double?,
        capture: MonotonicInterval,
        freshness: FreshnessEvidence,
        validationIssue: String?
    ) throws {
        guard !identifier.isEmpty else {
            throw ObservationValidationError.emptyIdentifier
        }
        guard rawInteger == nil
                || rawFloatingPoint == nil else {
            throw ObservationValidationError
                .rawPayloadConflict(
                    identifier: identifier
                )
        }

        let hasRaw =
            rawInteger != nil || rawFloatingPoint != nil

        if hasRaw && rawUnit == nil {
            throw ObservationValidationError
                .rawUnitMissing(
                    identifier: identifier
                )
        }
        if !hasRaw && rawUnit != nil {
            throw ObservationValidationError
                .rawUnitWithoutPayload(
                    identifier: identifier
                )
        }
        if let rawFloatingPoint,
           !rawFloatingPoint.isFinite {
            throw ObservationValidationError
                .nonFiniteNumber(
                    identifier: identifier
                )
        }
        if let watts, !watts.isFinite {
            throw ObservationValidationError
                .nonFiniteNumber(
                    identifier: identifier
                )
        }

        switch presence {
        case .present:
            guard hasRaw || watts != nil else {
                throw ObservationValidationError
                    .presentValueMissing(
                        identifier: identifier
                    )
            }
        case .missing:
            guard !hasRaw,
                  rawUnit == nil,
                  watts == nil else {
                throw ObservationValidationError
                    .missingReadingHasPayload(
                        identifier: identifier
                    )
            }
            guard freshness.ageMilliseconds == nil else {
                throw ObservationValidationError
                    .invalidFreshness(
                        "missing readings cannot have ageMilliseconds"
                    )
            }
        case .invalid:
            guard watts == nil else {
                throw ObservationValidationError
                    .invalidReadingHasWatts(
                        identifier: identifier
                    )
            }
            guard let validationIssue,
                  !validationIssue.isEmpty else {
                throw ObservationValidationError
                    .invalidIssueMissing(
                        identifier: identifier
                    )
            }
        }

        self.identifier = identifier
        self.source = source
        self.kind = kind
        self.semantic = semantic
        self.presence = presence
        self.rawInteger = rawInteger
        self.rawFloatingPoint = rawFloatingPoint
        self.rawUnit = rawUnit
        self.watts = watts
        self.capture = capture
        self.freshness = freshness
        self.validationIssue = validationIssue
    }

    static func canonicalFixtureMissing(
        identifier: String,
        source: ObservationSource,
        kind: ObservationKind,
        semantic: PowerSemantic,
        capture: MonotonicInterval
    ) -> PowerReading {
        try! PowerReading(
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
            validationIssue: "fixture missing"
        )
    }
}

// MARK: - AppleSmartBattery schema

struct BatteryPowerTelemetryObservation:
    Codable,
    Equatable,
    Sendable
{
    let presence: ObservationPresence
    let capture: MonotonicInterval
    let systemPowerIn: PowerReading
    let systemLoad: PowerReading
    let batteryPower: PowerReading
    let systemVoltageInNative: Observed<Int64>
    let systemCurrentInNative: Observed<Int64>
    let updateToken: String?
    let freshness: FreshnessEvidence

    static func canonicalFixtureMissing(
        capture: MonotonicInterval
    ) -> Self {
        Self(
            presence: .missing,
            capture: capture,
            systemPowerIn: .canonicalFixtureMissing(
                identifier:
                    "battery.powerTelemetry.systemPowerIn",
                source:
                    .appleSmartBatteryPowerTelemetry,
                kind: .measured,
                semantic: .systemInput,
                capture: capture
            ),
            systemLoad: .canonicalFixtureMissing(
                identifier:
                    "battery.powerTelemetry.systemLoad",
                source:
                    .appleSmartBatteryPowerTelemetry,
                kind: .measured,
                semantic: .systemLoad,
                capture: capture
            ),
            batteryPower: .canonicalFixtureMissing(
                identifier:
                    "battery.powerTelemetry.batteryPower",
                source:
                    .appleSmartBatteryPowerTelemetry,
                kind: .measured,
                semantic:
                    .firmwareBatteryPowerUnresolvedSign,
                capture: capture
            ),
            systemVoltageInNative:
                .canonicalFixtureMissing(
                    identifier:
                        "battery.powerTelemetry.systemVoltageIn",
                    source:
                        .appleSmartBatteryPowerTelemetry,
                    kind: .raw,
                    unit: .registryNative,
                    capture: capture
                ),
            systemCurrentInNative:
                .canonicalFixtureMissing(
                    identifier:
                        "battery.powerTelemetry.systemCurrentIn",
                    source:
                        .appleSmartBatteryPowerTelemetry,
                    kind: .raw,
                    unit: .registryNative,
                    capture: capture
                ),
            updateToken: nil,
            freshness: .unknown(
                at: capture.endedContinuousNanoseconds
            )
        )
    }
}

struct AdapterCapabilityObservation:
    Codable,
    Equatable,
    Sendable
{
    let presence: ObservationPresence
    let capture: MonotonicInterval
    let ratedWatts: PowerReading
    let adapterVoltageNative: Observed<Int64>
    let adapterCurrentNative: Observed<Int64>

    static func canonicalFixtureMissing(
        capture: MonotonicInterval
    ) -> Self {
        Self(
            presence: .missing,
            capture: capture,
            ratedWatts: .canonicalFixtureMissing(
                identifier:
                    "battery.adapterCapability.ratedWatts",
                source:
                    .appleSmartBatteryAdapterDetails,
                kind: .capability,
                semantic: .adapterCapability,
                capture: capture
            ),
            adapterVoltageNative:
                .canonicalFixtureMissing(
                    identifier:
                        "battery.adapterCapability.adapterVoltage",
                    source:
                        .appleSmartBatteryAdapterDetails,
                    kind: .capability,
                    unit: .registryNative,
                    capture: capture
                ),
            adapterCurrentNative:
                .canonicalFixtureMissing(
                    identifier:
                        "battery.adapterCapability.adapterCurrent",
                    source:
                        .appleSmartBatteryAdapterDetails,
                    kind: .capability,
                    unit: .registryNative,
                    capture: capture
                )
        )
    }
}

enum AggregateCompleteness:
    String,
    Codable,
    Equatable,
    Sendable
{
    case complete
    case partial
    case unknown
}

struct DeviceOutputPortObservation:
    Codable,
    Equatable,
    Sendable
{
    let arrayIndex: Int
    let portIndex: Int?
    let locationIdentifierWasPresent: Bool
    let measuredWatts: PowerReading
    let pdPowerRaw: PowerReading
}

struct DeviceOutputObservation:
    Codable,
    Equatable,
    Sendable
{
    let fieldPresence: ObservationPresence
    let capture: MonotonicInterval
    let ports: [DeviceOutputPortObservation]
    let measuredTotalWatts: PowerReading
    let completeness: AggregateCompleteness

    static func canonicalFixtureMissing(
        capture: MonotonicInterval
    ) -> Self {
        Self(
            fieldPresence: .missing,
            capture: capture,
            ports: [],
            measuredTotalWatts:
                .canonicalFixtureMissing(
                    identifier:
                        "battery.deviceOutput.measuredTotalWatts",
                    source: .derivedAggregate,
                    kind: .derived,
                    semantic:
                        .deviceOutputMeasuredTotal,
                    capture: capture
                ),
            completeness: .unknown
        )
    }
}

struct AppleSmartBatteryObservation:
    Codable,
    Equatable,
    Sendable
{
    let servicePresence: ObservationPresence
    let capture: MonotonicInterval
    let currentCapacity: Observed<Int64>
    let maxCapacity: Observed<Int64>
    let externalConnected: Observed<Bool>
    let isCharging: Observed<Bool>
    let voltageMillivolts: Observed<Int64>
    let instantAmperageMilliamps: Observed<Int64>
    let averageAmperageMilliamps: Observed<Int64>
    let powerTelemetry:
        BatteryPowerTelemetryObservation
    let adapterCapability:
        AdapterCapabilityObservation
    let deviceOutput: DeviceOutputObservation

    static func canonicalFixtureMissing(
        capture: MonotonicInterval
    ) -> Self {
        Self(
            servicePresence: .missing,
            capture: capture,
            currentCapacity:
                .canonicalFixtureMissing(
                    identifier:
                        "battery.currentCapacity",
                    source:
                        .appleSmartBatteryRegistry,
                    kind: .raw,
                    unit: .registryNative,
                    capture: capture
                ),
            maxCapacity:
                .canonicalFixtureMissing(
                    identifier:
                        "battery.maxCapacity",
                    source:
                        .appleSmartBatteryRegistry,
                    kind: .raw,
                    unit: .registryNative,
                    capture: capture
                ),
            externalConnected:
                .canonicalFixtureMissing(
                    identifier:
                        "battery.externalConnected",
                    source:
                        .appleSmartBatteryRegistry,
                    kind: .hint,
                    unit: .boolean,
                    capture: capture
                ),
            isCharging:
                .canonicalFixtureMissing(
                    identifier:
                        "battery.isCharging",
                    source:
                        .appleSmartBatteryRegistry,
                    kind: .hint,
                    unit: .boolean,
                    capture: capture
                ),
            voltageMillivolts:
                .canonicalFixtureMissing(
                    identifier:
                        "battery.voltageMillivolts",
                    source:
                        .appleSmartBatteryRegistry,
                    kind: .measured,
                    unit: .millivolts,
                    capture: capture
                ),
            instantAmperageMilliamps:
                .canonicalFixtureMissing(
                    identifier:
                        "battery.instantAmperageMilliamps",
                    source:
                        .appleSmartBatteryRegistry,
                    kind: .measured,
                    unit: .milliamps,
                    capture: capture
                ),
            averageAmperageMilliamps:
                .canonicalFixtureMissing(
                    identifier:
                        "battery.averageAmperageMilliamps",
                    source:
                        .appleSmartBatteryRegistry,
                    kind: .measured,
                    unit: .milliamps,
                    capture: capture
                ),
            powerTelemetry:
                .canonicalFixtureMissing(
                    capture: capture
                ),
            adapterCapability:
                .canonicalFixtureMissing(
                    capture: capture
                ),
            deviceOutput:
                .canonicalFixtureMissing(
                    capture: capture
                )
        )
    }
}

// MARK: - SMC schema

enum SMCConnectionStatus:
    String,
    Codable,
    Equatable,
    Sendable
{
    case opened
    case serviceUnavailable
    case openFailed
}

enum SMCKeyStatus:
    String,
    Codable,
    Equatable,
    Sendable
{
    case present
    case keyUnavailable
    case keyInfoFailed
    case valueReadFailed
    case unsupportedType
    case invalidValue
}

struct SMCKeyObservation:
    Codable,
    Equatable,
    Sendable
{
    let key: String
    let source: ObservationSource
    let status: SMCKeyStatus
    let capture: MonotonicInterval
    let dataTypeFourCC: String?
    let rawBytesHex: String?
    let decodedWatts: Double?
    let ioReturn: Int32?
    let validationIssue: String?

    static func canonicalFixtureMissing(
        key: String,
        source: ObservationSource,
        capture: MonotonicInterval
    ) -> Self {
        Self(
            key: key,
            source: source,
            status: .keyUnavailable,
            capture: capture,
            dataTypeFourCC: nil,
            rawBytesHex: nil,
            decodedWatts: nil,
            ioReturn: nil,
            validationIssue: "fixture missing"
        )
    }
}

enum SMCObservationError: Error, Equatable {
    case invalidKeyOrder([String])
    case invalidSource(
        key: String,
        source: ObservationSource
    )
}

struct SMCObservation:
    Codable,
    Equatable,
    Sendable
{
    static let requiredKeyOrder = [
        "PDTR",
        "PSTR",
        "PPBR",
    ]

    let connectionStatus: SMCConnectionStatus
    let connectionCapture: MonotonicInterval
    let keys: [SMCKeyObservation]

    init(
        connectionStatus: SMCConnectionStatus,
        connectionCapture: MonotonicInterval,
        keys: [SMCKeyObservation]
    ) throws {
        let order = keys.map(\.key)
        guard order == Self.requiredKeyOrder else {
            throw SMCObservationError
                .invalidKeyOrder(order)
        }
        let expectedSources:
            [String: ObservationSource] = [
                "PDTR": .smcPDTR,
                "PSTR": .smcPSTR,
                "PPBR": .smcPPBR,
            ]
        for key in keys {
            guard expectedSources[key.key]
                    == key.source else {
                throw SMCObservationError
                    .invalidSource(
                        key: key.key,
                        source: key.source
                    )
            }
        }
        self.connectionStatus = connectionStatus
        self.connectionCapture = connectionCapture
        self.keys = keys
    }

    static func canonicalFixtureMissing(
        capture: MonotonicInterval
    ) -> Self {
        try! Self(
            connectionStatus: .serviceUnavailable,
            connectionCapture: capture,
            keys: [
                .canonicalFixtureMissing(
                    key: "PDTR",
                    source: .smcPDTR,
                    capture: capture
                ),
                .canonicalFixtureMissing(
                    key: "PSTR",
                    source: .smcPSTR,
                    capture: capture
                ),
                .canonicalFixtureMissing(
                    key: "PPBR",
                    source: .smcPPBR,
                    capture: capture
                ),
            ]
        )
    }

    func key(
        _ name: String
    ) -> SMCKeyObservation? {
        keys.first { $0.key == name }
    }
}

// MARK: - Derived evidence

struct ObservationTimingEvidence:
    Codable,
    Equatable,
    Sendable
{
    let observationStartedContinuousNanoseconds:
        UInt64
    let observationEndedContinuousNanoseconds:
        UInt64
    let totalCaptureDurationMilliseconds: Double
    let smcKeySkewMilliseconds: Double?
    let batteryMidpointMinusSMCMidpointMilliseconds:
        Double?
    let absoluteBatterySMCSkewMilliseconds: Double?
}

struct ModuloAnchor:
    Codable,
    Equatable,
    Sendable
{
    let identifier: String
    let source: ObservationSource
    let watts: Double
    let capture: MonotonicInterval
}

struct ModuloCandidate:
    Codable,
    Equatable,
    Sendable
{
    let multiple: Int
    let candidateWatts: Double
    let deltaToAnchorsWatts: [Double]
}

enum ModuloEvidenceStatus:
    String,
    Codable,
    Equatable,
    Sendable
{
    case insufficientData
    case candidatesGenerated
}

struct PSTRModuloEvidence:
    Codable,
    Equatable,
    Sendable
{
    static let requiredModulusWatts = 65.536
    static let candidateMultiples = [0, 1, 2, 3]

    let status: ModuloEvidenceStatus
    let rawPSTRWatts: Double?
    let modulusWatts: Double
    let anchors: [ModuloAnchor]
    let candidates: [ModuloCandidate]
    let validationIssue: String?

    init(
        rawPSTRWatts: Double?,
        anchors: [ModuloAnchor],
        modulusWatts: Double =
            Self.requiredModulusWatts,
        validationIssue: String? = nil
    ) {
        self.rawPSTRWatts = rawPSTRWatts
        self.modulusWatts = modulusWatts
        self.anchors = anchors

        guard modulusWatts.isFinite,
              modulusWatts
                == Self.requiredModulusWatts else {
            status = .insufficientData
            candidates = []
            self.validationIssue =
                validationIssue
                ?? "invalid PSTR modulus"
            return
        }
        guard let rawPSTRWatts else {
            status = .insufficientData
            candidates = []
            self.validationIssue =
                validationIssue
                ?? "raw PSTR unavailable"
            return
        }
        guard rawPSTRWatts.isFinite,
              rawPSTRWatts >= 0 else {
            status = .insufficientData
            candidates = []
            self.validationIssue =
                validationIssue
                ?? "raw PSTR is invalid"
            return
        }
        guard anchors.allSatisfy({
            $0.watts.isFinite && $0.watts >= 0
        }) else {
            status = .insufficientData
            candidates = []
            self.validationIssue =
                validationIssue
                ?? "one or more PSTR anchors are invalid"
            return
        }

        status = .candidatesGenerated
        candidates = Self.candidateMultiples.map {
            multiple in
            let candidate =
                rawPSTRWatts
                + Double(multiple) * modulusWatts
            return ModuloCandidate(
                multiple: multiple,
                candidateWatts: candidate,
                deltaToAnchorsWatts: anchors.map {
                    candidate - $0.watts
                }
            )
        }
        self.validationIssue = validationIssue
    }
}

struct PowerBalanceEvidence:
    Codable,
    Equatable,
    Sendable
{
    let identifier: String
    let adapterSource: ObservationSource?
    let systemSource: ObservationSource?
    let batterySource: ObservationSource?
    let externalSource: ObservationSource?
    let residualWatts: Double?
    let maximumInputSkewMilliseconds: Double?
}

struct RawPowerEvidence:
    Codable,
    Equatable,
    Sendable
{
    let batteryVoltageTimesCurrent: PowerReading
    let systemVoltageTimesCurrent: PowerReading
    let timing: ObservationTimingEvidence
    let pstrModulo: PSTRModuloEvidence
    let balances: [PowerBalanceEvidence]

    static func canonicalFixtureMissing(
        capture: MonotonicInterval
    ) -> Self {
        Self(
            batteryVoltageTimesCurrent:
                .canonicalFixtureMissing(
                    identifier:
                        "evidence.batteryVoltageTimesCurrent",
                    source: .derivedBatteryVI,
                    kind: .derived,
                    semantic:
                        .batteryVoltageTimesCurrent,
                    capture: capture
                ),
            systemVoltageTimesCurrent:
                .canonicalFixtureMissing(
                    identifier:
                        "evidence.systemVoltageTimesCurrent",
                    source:
                        .derivedSystemInputVI,
                    kind: .derived,
                    semantic:
                        .systemVoltageTimesCurrent,
                    capture: capture
                ),
            timing: ObservationTimingEvidence(
                observationStartedContinuousNanoseconds:
                    capture.startedContinuousNanoseconds,
                observationEndedContinuousNanoseconds:
                    capture.endedContinuousNanoseconds,
                totalCaptureDurationMilliseconds:
                    capture.durationMilliseconds,
                smcKeySkewMilliseconds: nil,
                batteryMidpointMinusSMCMidpointMilliseconds:
                    nil,
                absoluteBatterySMCSkewMilliseconds:
                    nil
            ),
            pstrModulo: PSTRModuloEvidence(
                rawPSTRWatts: nil,
                anchors: []
            ),
            balances: []
        )
    }
}

struct RawPowerObservation:
    Codable,
    Equatable,
    Sendable
{
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let sequence: UInt64
    let scenario: String?
    let finalizedAtContinuousNanoseconds: UInt64
    let battery: AppleSmartBatteryObservation
    let smc: SMCObservation
    let evidence: RawPowerEvidence

    init(
        schemaVersion: Int =
            Self.currentSchemaVersion,
        sequence: UInt64,
        scenario: String?,
        finalizedAtContinuousNanoseconds: UInt64,
        battery: AppleSmartBatteryObservation,
        smc: SMCObservation,
        evidence: RawPowerEvidence
    ) throws {
        guard schemaVersion
                == Self.currentSchemaVersion else {
            throw PowerObservationTraceRecordError
                .invalidSchemaVersion(
                    schemaVersion
                )
        }
        self.schemaVersion = schemaVersion
        self.sequence = sequence
        self.scenario = scenario
        self.finalizedAtContinuousNanoseconds =
            finalizedAtContinuousNanoseconds
        self.battery = battery
        self.smc = smc
        self.evidence = evidence
        try validateContract()
    }

    static func canonicalFixture(
        sequence: UInt64,
        scenario: String? = nil,
        baseNanoseconds: UInt64 = 0
    ) -> Self {
        let capture = try! MonotonicInterval(
            startedContinuousNanoseconds:
                baseNanoseconds,
            endedContinuousNanoseconds:
                baseNanoseconds
        )
        return try! Self(
            sequence: sequence,
            scenario: scenario,
            finalizedAtContinuousNanoseconds:
                baseNanoseconds,
            battery:
                .canonicalFixtureMissing(
                    capture: capture
                ),
            smc:
                .canonicalFixtureMissing(
                    capture: capture
                ),
            evidence:
                .canonicalFixtureMissing(
                    capture: capture
                )
        )
    }
}


// MARK: - Strict required-nullable Codable support

extension KeyedDecodingContainer {
    func decodeRequiredNullable<T: Decodable>(
        _ type: T.Type,
        forKey key: Key
    ) throws -> T? {
        guard contains(key) else {
            throw DecodingError.keyNotFound(
                key,
                DecodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "Required key is missing"
                )
            )
        }
        if try decodeNil(forKey: key) {
            return nil
        }
        return try decode(T.self, forKey: key)
    }
}

extension KeyedEncodingContainer {
    mutating func encodeRequiredNullable<T: Encodable>(
        _ value: T?,
        forKey key: Key
    ) throws {
        if let value {
            try encode(value, forKey: key)
        } else {
            try encodeNil(forKey: key)
        }
    }
}

private func observationDataCorrupted(
    _ decoder: Decoder,
    _ description: String
) -> DecodingError {
    DecodingError.dataCorrupted(
        DecodingError.Context(
            codingPath: decoder.codingPath,
            debugDescription: description
        )
    )
}

private func valuesApproximatelyEqual(
    _ lhs: Double,
    _ rhs: Double,
    tolerance: Double = 0.000_000_001
) -> Bool {
    abs(lhs - rhs) <= tolerance
}

extension FreshnessEvidence {
    private enum CodingKeys: String, CodingKey {
        case evaluatedAtContinuousNanoseconds
        case ageMilliseconds
        case updateToken
        case unchangedSinceContinuousNanoseconds
        case unchangedForMilliseconds
        case assessment
        case basis
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                evaluatedAtContinuousNanoseconds: try container.decode(
                    UInt64.self,
                    forKey: .evaluatedAtContinuousNanoseconds
                ),
                ageMilliseconds: try container.decodeRequiredNullable(
                    Double.self,
                    forKey: .ageMilliseconds
                ),
                updateToken: try container.decodeRequiredNullable(
                    String.self,
                    forKey: .updateToken
                ),
                unchangedSinceContinuousNanoseconds: try container.decodeRequiredNullable(
                    UInt64.self,
                    forKey: .unchangedSinceContinuousNanoseconds
                ),
                unchangedForMilliseconds: try container.decodeRequiredNullable(
                    Double.self,
                    forKey: .unchangedForMilliseconds
                ),
                assessment: try container.decode(
                    FreshnessAssessment.self,
                    forKey: .assessment
                ),
                basis: try container.decode(
                    FreshnessBasis.self,
                    forKey: .basis
                )
            )
        } catch let error as DecodingError {
            throw error
        } catch {
            throw observationDataCorrupted(decoder, String(describing: error))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(
            evaluatedAtContinuousNanoseconds,
            forKey: .evaluatedAtContinuousNanoseconds
        )
        try container.encodeRequiredNullable(
            ageMilliseconds,
            forKey: .ageMilliseconds
        )
        try container.encodeRequiredNullable(
            updateToken,
            forKey: .updateToken
        )
        try container.encodeRequiredNullable(
            unchangedSinceContinuousNanoseconds,
            forKey: .unchangedSinceContinuousNanoseconds
        )
        try container.encodeRequiredNullable(
            unchangedForMilliseconds,
            forKey: .unchangedForMilliseconds
        )
        try container.encode(assessment, forKey: .assessment)
        try container.encode(basis, forKey: .basis)
    }
}

extension Observed {
    private enum CodingKeys: String, CodingKey {
        case identifier
        case source
        case kind
        case unit
        case presence
        case value
        case capture
        case freshness
        case validationIssue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                identifier: try container.decode(String.self, forKey: .identifier),
                source: try container.decode(ObservationSource.self, forKey: .source),
                kind: try container.decode(ObservationKind.self, forKey: .kind),
                unit: try container.decode(ObservationUnit.self, forKey: .unit),
                presence: try container.decode(ObservationPresence.self, forKey: .presence),
                value: try container.decodeRequiredNullable(Value.self, forKey: .value),
                capture: try container.decode(MonotonicInterval.self, forKey: .capture),
                freshness: try container.decode(FreshnessEvidence.self, forKey: .freshness),
                validationIssue: try container.decodeRequiredNullable(
                    String.self,
                    forKey: .validationIssue
                )
            )
        } catch let error as DecodingError {
            throw error
        } catch {
            throw observationDataCorrupted(decoder, String(describing: error))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(identifier, forKey: .identifier)
        try container.encode(source, forKey: .source)
        try container.encode(kind, forKey: .kind)
        try container.encode(unit, forKey: .unit)
        try container.encode(presence, forKey: .presence)
        try container.encodeRequiredNullable(value, forKey: .value)
        try container.encode(capture, forKey: .capture)
        try container.encode(freshness, forKey: .freshness)
        try container.encodeRequiredNullable(
            validationIssue,
            forKey: .validationIssue
        )
    }
}

extension PowerReading {
    private enum CodingKeys: String, CodingKey {
        case identifier
        case source
        case kind
        case semantic
        case presence
        case rawInteger
        case rawFloatingPoint
        case rawUnit
        case watts
        case capture
        case freshness
        case validationIssue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                identifier: try container.decode(String.self, forKey: .identifier),
                source: try container.decode(ObservationSource.self, forKey: .source),
                kind: try container.decode(ObservationKind.self, forKey: .kind),
                semantic: try container.decode(PowerSemantic.self, forKey: .semantic),
                presence: try container.decode(ObservationPresence.self, forKey: .presence),
                rawInteger: try container.decodeRequiredNullable(Int64.self, forKey: .rawInteger),
                rawFloatingPoint: try container.decodeRequiredNullable(
                    Double.self,
                    forKey: .rawFloatingPoint
                ),
                rawUnit: try container.decodeRequiredNullable(
                    ObservationUnit.self,
                    forKey: .rawUnit
                ),
                watts: try container.decodeRequiredNullable(Double.self, forKey: .watts),
                capture: try container.decode(MonotonicInterval.self, forKey: .capture),
                freshness: try container.decode(FreshnessEvidence.self, forKey: .freshness),
                validationIssue: try container.decodeRequiredNullable(
                    String.self,
                    forKey: .validationIssue
                )
            )
        } catch let error as DecodingError {
            throw error
        } catch {
            throw observationDataCorrupted(decoder, String(describing: error))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(identifier, forKey: .identifier)
        try container.encode(source, forKey: .source)
        try container.encode(kind, forKey: .kind)
        try container.encode(semantic, forKey: .semantic)
        try container.encode(presence, forKey: .presence)
        try container.encodeRequiredNullable(rawInteger, forKey: .rawInteger)
        try container.encodeRequiredNullable(
            rawFloatingPoint,
            forKey: .rawFloatingPoint
        )
        try container.encodeRequiredNullable(rawUnit, forKey: .rawUnit)
        try container.encodeRequiredNullable(watts, forKey: .watts)
        try container.encode(capture, forKey: .capture)
        try container.encode(freshness, forKey: .freshness)
        try container.encodeRequiredNullable(
            validationIssue,
            forKey: .validationIssue
        )
    }
}

private enum NestedObservationValidationError: Error, Equatable {
    case invalidFieldContract(String)
    case invalidMissingContainer(String)
    case invalidDeviceOutput(String)
    case invalidSMCKey(String)
    case invalidTiming(String)
    case invalidModulo(String)
    case invalidBalance(String)
    case invalidEvidence(String)
    case invalidRawObservation(String)
}

private func requireObservedContract<Value>(
    _ observed: Observed<Value>,
    identifier: String,
    source: ObservationSource,
    kind: ObservationKind,
    unit: ObservationUnit
) throws {
    guard observed.identifier == identifier,
          observed.source == source,
          observed.kind == kind,
          observed.unit == unit else {
        throw NestedObservationValidationError.invalidFieldContract(identifier)
    }
}

private func requirePowerContract(
    _ reading: PowerReading,
    identifier: String,
    source: ObservationSource,
    kind: ObservationKind,
    semantic: PowerSemantic
) throws {
    guard reading.identifier == identifier,
          reading.source == source,
          reading.kind == kind,
          reading.semantic == semantic else {
        throw NestedObservationValidationError.invalidFieldContract(identifier)
    }
}

private func requireIntegerMilliwattReading(
    _ reading: PowerReading,
    nonNegative: Bool = false
) throws {
    guard reading.presence == .present else {
        return
    }
    guard let rawInteger = reading.rawInteger,
          reading.rawFloatingPoint == nil,
          reading.rawUnit == .milliwatts,
          let watts = reading.watts,
          watts == Double(rawInteger) / 1_000,
          !nonNegative || rawInteger >= 0 else {
        throw NestedObservationValidationError.invalidFieldContract(
            "\(reading.identifier) must preserve integer milliwatts and normalize only by dividing by 1000"
        )
    }
}

private func requireIntegerWattReading(
    _ reading: PowerReading,
    nonNegative: Bool = false
) throws {
    guard reading.presence == .present else {
        return
    }
    guard let rawInteger = reading.rawInteger,
          reading.rawFloatingPoint == nil,
          reading.rawUnit == .watts,
          let watts = reading.watts,
          watts == Double(rawInteger),
          !nonNegative || rawInteger >= 0 else {
        throw NestedObservationValidationError.invalidFieldContract(
            "\(reading.identifier) must preserve integer watts without conversion"
        )
    }
}

private func requireDerivedReading(
    _ reading: PowerReading,
    nonNegative: Bool = false
) throws {
    guard reading.presence == .present else {
        return
    }
    guard reading.rawInteger == nil,
          reading.rawFloatingPoint == nil,
          reading.rawUnit == nil,
          let watts = reading.watts,
          !nonNegative || watts >= 0 else {
        throw NestedObservationValidationError.invalidFieldContract(
            "\(reading.identifier) must contain only derived watts"
        )
    }
}

private func requireMissingObservedShape<Value>(
    _ observed: Observed<Value>,
    capture: MonotonicInterval
) throws {
    guard observed.presence == .missing,
          observed.capture == capture,
          observed.freshness == .unknown(
              at: capture.endedContinuousNanoseconds
          ) else {
        throw NestedObservationValidationError.invalidMissingContainer(
            observed.identifier
        )
    }
}

private func requireMissingPowerShape(
    _ reading: PowerReading,
    capture: MonotonicInterval
) throws {
    guard reading.presence == .missing,
          reading.capture == capture,
          reading.freshness == .unknown(
              at: capture.endedContinuousNanoseconds
          ) else {
        throw NestedObservationValidationError.invalidMissingContainer(
            reading.identifier
        )
    }
}

private func maximumMidpointSkewMilliseconds(
    _ captures: [MonotonicInterval]
) -> Double? {
    guard captures.count >= 2 else {
        return nil
    }
    let midpoints = captures.map(
        \.midpointContinuousNanoseconds
    )
    guard let minimum = midpoints.min(),
          let maximum = midpoints.max() else {
        return nil
    }
    return Double(maximum - minimum) / 1_000_000
}

private func signedMidpointDifferenceMilliseconds(
    _ lhs: MonotonicInterval,
    _ rhs: MonotonicInterval
) -> Double {
    let lhsMidpoint = lhs.midpointContinuousNanoseconds
    let rhsMidpoint = rhs.midpointContinuousNanoseconds
    if lhsMidpoint >= rhsMidpoint {
        return Double(lhsMidpoint - rhsMidpoint)
            / 1_000_000
    }
    return -Double(rhsMidpoint - lhsMidpoint)
        / 1_000_000
}

extension BatteryPowerTelemetryObservation {
    private enum CodingKeys: String, CodingKey {
        case presence
        case capture
        case systemPowerIn
        case systemLoad
        case batteryPower
        case systemVoltageInNative
        case systemCurrentInNative
        case updateToken
        case freshness
    }

    fileprivate func validateContract() throws {
        try requirePowerContract(
            systemPowerIn,
            identifier: "battery.powerTelemetry.systemPowerIn",
            source: .appleSmartBatteryPowerTelemetry,
            kind: .measured,
            semantic: .systemInput
        )
        try requirePowerContract(
            systemLoad,
            identifier: "battery.powerTelemetry.systemLoad",
            source: .appleSmartBatteryPowerTelemetry,
            kind: .measured,
            semantic: .systemLoad
        )
        try requirePowerContract(
            batteryPower,
            identifier: "battery.powerTelemetry.batteryPower",
            source: .appleSmartBatteryPowerTelemetry,
            kind: .measured,
            semantic: .firmwareBatteryPowerUnresolvedSign
        )
        try requireObservedContract(
            systemVoltageInNative,
            identifier: "battery.powerTelemetry.systemVoltageIn",
            source: .appleSmartBatteryPowerTelemetry,
            kind: .raw,
            unit: .registryNative
        )
        try requireObservedContract(
            systemCurrentInNative,
            identifier: "battery.powerTelemetry.systemCurrentIn",
            source: .appleSmartBatteryPowerTelemetry,
            kind: .raw,
            unit: .registryNative
        )
        try requireIntegerMilliwattReading(systemPowerIn)
        try requireIntegerMilliwattReading(systemLoad)
        try requireIntegerMilliwattReading(batteryPower)
        if presence == .missing {
            guard systemPowerIn.presence == .missing,
                  systemLoad.presence == .missing,
                  batteryPower.presence == .missing,
                  systemVoltageInNative.presence == .missing,
                  systemCurrentInNative.presence == .missing,
                  updateToken == nil,
                  freshness == .unknown(
                      at: capture.endedContinuousNanoseconds
                  ) else {
                throw NestedObservationValidationError.invalidMissingContainer(
                    "battery.powerTelemetry"
                )
            }
            try requireMissingPowerShape(
                systemPowerIn,
                capture: capture
            )
            try requireMissingPowerShape(
                systemLoad,
                capture: capture
            )
            try requireMissingPowerShape(
                batteryPower,
                capture: capture
            )
            try requireMissingObservedShape(
                systemVoltageInNative,
                capture: capture
            )
            try requireMissingObservedShape(
                systemCurrentInNative,
                capture: capture
            )
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            presence: try container.decode(ObservationPresence.self, forKey: .presence),
            capture: try container.decode(MonotonicInterval.self, forKey: .capture),
            systemPowerIn: try container.decode(PowerReading.self, forKey: .systemPowerIn),
            systemLoad: try container.decode(PowerReading.self, forKey: .systemLoad),
            batteryPower: try container.decode(PowerReading.self, forKey: .batteryPower),
            systemVoltageInNative: try container.decode(
                Observed<Int64>.self,
                forKey: .systemVoltageInNative
            ),
            systemCurrentInNative: try container.decode(
                Observed<Int64>.self,
                forKey: .systemCurrentInNative
            ),
            updateToken: try container.decodeRequiredNullable(String.self, forKey: .updateToken),
            freshness: try container.decode(FreshnessEvidence.self, forKey: .freshness)
        )
        do {
            try validateContract()
        } catch {
            throw observationDataCorrupted(decoder, String(describing: error))
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
        try container.encode(presence, forKey: .presence)
        try container.encode(capture, forKey: .capture)
        try container.encode(systemPowerIn, forKey: .systemPowerIn)
        try container.encode(systemLoad, forKey: .systemLoad)
        try container.encode(batteryPower, forKey: .batteryPower)
        try container.encode(systemVoltageInNative, forKey: .systemVoltageInNative)
        try container.encode(systemCurrentInNative, forKey: .systemCurrentInNative)
        try container.encodeRequiredNullable(updateToken, forKey: .updateToken)
        try container.encode(freshness, forKey: .freshness)
    }
}

extension AdapterCapabilityObservation {
    private enum CodingKeys: String, CodingKey {
        case presence
        case capture
        case ratedWatts
        case adapterVoltageNative
        case adapterCurrentNative
    }

    fileprivate func validateContract() throws {
        try requirePowerContract(
            ratedWatts,
            identifier: "battery.adapterCapability.ratedWatts",
            source: .appleSmartBatteryAdapterDetails,
            kind: .capability,
            semantic: .adapterCapability
        )
        try requireObservedContract(
            adapterVoltageNative,
            identifier: "battery.adapterCapability.adapterVoltage",
            source: .appleSmartBatteryAdapterDetails,
            kind: .capability,
            unit: .registryNative
        )
        try requireObservedContract(
            adapterCurrentNative,
            identifier: "battery.adapterCapability.adapterCurrent",
            source: .appleSmartBatteryAdapterDetails,
            kind: .capability,
            unit: .registryNative
        )
        try requireIntegerWattReading(
            ratedWatts,
            nonNegative: true
        )
        if presence == .missing {
            guard ratedWatts.presence == .missing,
                  adapterVoltageNative.presence == .missing,
                  adapterCurrentNative.presence == .missing else {
                throw NestedObservationValidationError.invalidMissingContainer(
                    "battery.adapterCapability"
                )
            }
            try requireMissingPowerShape(
                ratedWatts,
                capture: capture
            )
            try requireMissingObservedShape(
                adapterVoltageNative,
                capture: capture
            )
            try requireMissingObservedShape(
                adapterCurrentNative,
                capture: capture
            )
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            presence: try container.decode(ObservationPresence.self, forKey: .presence),
            capture: try container.decode(MonotonicInterval.self, forKey: .capture),
            ratedWatts: try container.decode(PowerReading.self, forKey: .ratedWatts),
            adapterVoltageNative: try container.decode(
                Observed<Int64>.self,
                forKey: .adapterVoltageNative
            ),
            adapterCurrentNative: try container.decode(
                Observed<Int64>.self,
                forKey: .adapterCurrentNative
            )
        )
        do {
            try validateContract()
        } catch {
            throw observationDataCorrupted(decoder, String(describing: error))
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
        try container.encode(presence, forKey: .presence)
        try container.encode(capture, forKey: .capture)
        try container.encode(ratedWatts, forKey: .ratedWatts)
        try container.encode(adapterVoltageNative, forKey: .adapterVoltageNative)
        try container.encode(adapterCurrentNative, forKey: .adapterCurrentNative)
    }
}

extension DeviceOutputPortObservation {
    private enum CodingKeys: String, CodingKey {
        case arrayIndex
        case portIndex
        case locationIdentifierWasPresent
        case measuredWatts
        case pdPowerRaw
    }

    fileprivate func validateContract() throws {
        guard arrayIndex >= 0 else {
            throw NestedObservationValidationError.invalidDeviceOutput(
                "arrayIndex must be non-negative"
            )
        }
        if let portIndex, portIndex < 0 {
            throw NestedObservationValidationError.invalidDeviceOutput(
                "portIndex must be non-negative when present"
            )
        }
        try requirePowerContract(
            measuredWatts,
            identifier: "battery.deviceOutput.ports[\(arrayIndex)].measuredWatts",
            source: .appleSmartBatteryPowerOutWatts,
            kind: .measured,
            semantic: .deviceOutput
        )
        try requirePowerContract(
            pdPowerRaw,
            identifier: "battery.deviceOutput.ports[\(arrayIndex)].pdPowerRaw",
            source: .appleSmartBatteryPowerOutPDPower,
            kind: .raw,
            semantic: .unknown
        )
        if measuredWatts.presence == .present {
            try requireIntegerMilliwattReading(
                measuredWatts,
                nonNegative: true
            )
        }
        if pdPowerRaw.presence == .present {
            guard pdPowerRaw.rawInteger != nil,
                  pdPowerRaw.rawFloatingPoint == nil,
                  pdPowerRaw.rawUnit == .milliwatts,
                  pdPowerRaw.watts == nil else {
                throw NestedObservationValidationError.invalidDeviceOutput(
                    "PDPowermW must remain raw and unnormalized"
                )
            }
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            arrayIndex: try container.decode(Int.self, forKey: .arrayIndex),
            portIndex: try container.decodeRequiredNullable(Int.self, forKey: .portIndex),
            locationIdentifierWasPresent: try container.decode(
                Bool.self,
                forKey: .locationIdentifierWasPresent
            ),
            measuredWatts: try container.decode(PowerReading.self, forKey: .measuredWatts),
            pdPowerRaw: try container.decode(PowerReading.self, forKey: .pdPowerRaw)
        )
        do {
            try validateContract()
        } catch {
            throw observationDataCorrupted(decoder, String(describing: error))
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
        try container.encode(arrayIndex, forKey: .arrayIndex)
        try container.encodeRequiredNullable(portIndex, forKey: .portIndex)
        try container.encode(
            locationIdentifierWasPresent,
            forKey: .locationIdentifierWasPresent
        )
        try container.encode(measuredWatts, forKey: .measuredWatts)
        try container.encode(pdPowerRaw, forKey: .pdPowerRaw)
    }
}

extension DeviceOutputObservation {
    private enum CodingKeys: String, CodingKey {
        case fieldPresence
        case capture
        case ports
        case measuredTotalWatts
        case completeness
    }

    fileprivate func validateContract() throws {
        try requirePowerContract(
            measuredTotalWatts,
            identifier: "battery.deviceOutput.measuredTotalWatts",
            source: .derivedAggregate,
            kind: .derived,
            semantic: .deviceOutputMeasuredTotal
        )
        try requireDerivedReading(
            measuredTotalWatts,
            nonNegative: true
        )
        try ports.forEach { try $0.validateContract() }

        switch fieldPresence {
        case .missing:
            guard ports.isEmpty,
                  measuredTotalWatts.presence == .missing,
                  measuredTotalWatts.watts == nil,
                  completeness == .unknown else {
                throw NestedObservationValidationError.invalidDeviceOutput(
                    "missing PowerOutDetails must remain unknown"
                )
            }
            try requireMissingPowerShape(
                measuredTotalWatts,
                capture: capture
            )
        case .invalid:
            guard ports.isEmpty,
                  measuredTotalWatts.presence == .invalid,
                  measuredTotalWatts.watts == nil,
                  completeness == .unknown else {
                throw NestedObservationValidationError.invalidDeviceOutput(
                    "invalid PowerOutDetails must remain invalid and unknown"
                )
            }
        case .present:
            let measuredPorts = ports.filter {
                $0.measuredWatts.presence == .present
            }
            let sum = measuredPorts.reduce(0.0) {
                $0 + ($1.measuredWatts.watts ?? 0)
            }
            if ports.isEmpty {
                guard measuredTotalWatts.presence == .present,
                      measuredTotalWatts.watts.map({
                          valuesApproximatelyEqual($0, 0)
                      }) == true,
                      completeness == .complete else {
                    throw NestedObservationValidationError.invalidDeviceOutput(
                        "an explicit empty array is measured zero"
                    )
                }
            } else if measuredPorts.isEmpty {
                guard measuredTotalWatts.presence == .missing,
                      measuredTotalWatts.watts == nil,
                      completeness == .unknown else {
                    throw NestedObservationValidationError.invalidDeviceOutput(
                        "ports without measured Watts remain unknown"
                    )
                }
            } else {
                guard measuredTotalWatts.presence == .present,
                      measuredTotalWatts.watts.map({
                          valuesApproximatelyEqual($0, sum)
                      }) == true else {
                    throw NestedObservationValidationError.invalidDeviceOutput(
                        "aggregate must equal the sum of measured Watts only"
                    )
                }
                let expected: AggregateCompleteness =
                    measuredPorts.count == ports.count ? .complete : .partial
                guard completeness == expected else {
                    throw NestedObservationValidationError.invalidDeviceOutput(
                        "aggregate completeness does not match the sanitized entries"
                    )
                }
            }
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            fieldPresence: try container.decode(
                ObservationPresence.self,
                forKey: .fieldPresence
            ),
            capture: try container.decode(MonotonicInterval.self, forKey: .capture),
            ports: try container.decode([DeviceOutputPortObservation].self, forKey: .ports),
            measuredTotalWatts: try container.decode(
                PowerReading.self,
                forKey: .measuredTotalWatts
            ),
            completeness: try container.decode(
                AggregateCompleteness.self,
                forKey: .completeness
            )
        )
        do {
            try validateContract()
        } catch {
            throw observationDataCorrupted(decoder, String(describing: error))
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
        try container.encode(fieldPresence, forKey: .fieldPresence)
        try container.encode(capture, forKey: .capture)
        try container.encode(ports, forKey: .ports)
        try container.encode(measuredTotalWatts, forKey: .measuredTotalWatts)
        try container.encode(completeness, forKey: .completeness)
    }
}

extension AppleSmartBatteryObservation {
    private enum CodingKeys: String, CodingKey {
        case servicePresence
        case capture
        case currentCapacity
        case maxCapacity
        case externalConnected
        case isCharging
        case voltageMillivolts
        case instantAmperageMilliamps
        case averageAmperageMilliamps
        case powerTelemetry
        case adapterCapability
        case deviceOutput
    }

    fileprivate func validateContract() throws {
        try requireObservedContract(
            currentCapacity,
            identifier: "battery.currentCapacity",
            source: .appleSmartBatteryRegistry,
            kind: .raw,
            unit: .registryNative
        )
        try requireObservedContract(
            maxCapacity,
            identifier: "battery.maxCapacity",
            source: .appleSmartBatteryRegistry,
            kind: .raw,
            unit: .registryNative
        )
        try requireObservedContract(
            externalConnected,
            identifier: "battery.externalConnected",
            source: .appleSmartBatteryRegistry,
            kind: .hint,
            unit: .boolean
        )
        try requireObservedContract(
            isCharging,
            identifier: "battery.isCharging",
            source: .appleSmartBatteryRegistry,
            kind: .hint,
            unit: .boolean
        )
        try requireObservedContract(
            voltageMillivolts,
            identifier: "battery.voltageMillivolts",
            source: .appleSmartBatteryRegistry,
            kind: .measured,
            unit: .millivolts
        )
        try requireObservedContract(
            instantAmperageMilliamps,
            identifier: "battery.instantAmperageMilliamps",
            source: .appleSmartBatteryRegistry,
            kind: .measured,
            unit: .milliamps
        )
        try requireObservedContract(
            averageAmperageMilliamps,
            identifier: "battery.averageAmperageMilliamps",
            source: .appleSmartBatteryRegistry,
            kind: .measured,
            unit: .milliamps
        )
        try powerTelemetry.validateContract()
        try adapterCapability.validateContract()
        try deviceOutput.validateContract()
        if servicePresence == .missing {
            guard powerTelemetry.presence == .missing,
                  powerTelemetry.capture == capture,
                  adapterCapability.presence == .missing,
                  adapterCapability.capture == capture,
                  deviceOutput.fieldPresence == .missing,
                  deviceOutput.capture == capture else {
                throw NestedObservationValidationError.invalidMissingContainer(
                    "battery"
                )
            }
            try requireMissingObservedShape(
                currentCapacity,
                capture: capture
            )
            try requireMissingObservedShape(
                maxCapacity,
                capture: capture
            )
            try requireMissingObservedShape(
                externalConnected,
                capture: capture
            )
            try requireMissingObservedShape(
                isCharging,
                capture: capture
            )
            try requireMissingObservedShape(
                voltageMillivolts,
                capture: capture
            )
            try requireMissingObservedShape(
                instantAmperageMilliamps,
                capture: capture
            )
            try requireMissingObservedShape(
                averageAmperageMilliamps,
                capture: capture
            )
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            servicePresence: try container.decode(
                ObservationPresence.self,
                forKey: .servicePresence
            ),
            capture: try container.decode(MonotonicInterval.self, forKey: .capture),
            currentCapacity: try container.decode(Observed<Int64>.self, forKey: .currentCapacity),
            maxCapacity: try container.decode(Observed<Int64>.self, forKey: .maxCapacity),
            externalConnected: try container.decode(Observed<Bool>.self, forKey: .externalConnected),
            isCharging: try container.decode(Observed<Bool>.self, forKey: .isCharging),
            voltageMillivolts: try container.decode(Observed<Int64>.self, forKey: .voltageMillivolts),
            instantAmperageMilliamps: try container.decode(
                Observed<Int64>.self,
                forKey: .instantAmperageMilliamps
            ),
            averageAmperageMilliamps: try container.decode(
                Observed<Int64>.self,
                forKey: .averageAmperageMilliamps
            ),
            powerTelemetry: try container.decode(
                BatteryPowerTelemetryObservation.self,
                forKey: .powerTelemetry
            ),
            adapterCapability: try container.decode(
                AdapterCapabilityObservation.self,
                forKey: .adapterCapability
            ),
            deviceOutput: try container.decode(
                DeviceOutputObservation.self,
                forKey: .deviceOutput
            )
        )
        do {
            try validateContract()
        } catch {
            throw observationDataCorrupted(decoder, String(describing: error))
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
        try container.encode(servicePresence, forKey: .servicePresence)
        try container.encode(capture, forKey: .capture)
        try container.encode(currentCapacity, forKey: .currentCapacity)
        try container.encode(maxCapacity, forKey: .maxCapacity)
        try container.encode(externalConnected, forKey: .externalConnected)
        try container.encode(isCharging, forKey: .isCharging)
        try container.encode(voltageMillivolts, forKey: .voltageMillivolts)
        try container.encode(
            instantAmperageMilliamps,
            forKey: .instantAmperageMilliamps
        )
        try container.encode(
            averageAmperageMilliamps,
            forKey: .averageAmperageMilliamps
        )
        try container.encode(powerTelemetry, forKey: .powerTelemetry)
        try container.encode(adapterCapability, forKey: .adapterCapability)
        try container.encode(deviceOutput, forKey: .deviceOutput)
    }
}

private func validateUppercaseHex(_ value: String) -> Bool {
    guard !value.isEmpty,
          value.count.isMultiple(of: 2) else {
        return false
    }
    return value.unicodeScalars.allSatisfy { scalar in
        ("0"..."9").contains(Character(String(scalar)))
            || ("A"..."F").contains(Character(String(scalar)))
    }
}

extension SMCKeyObservation {
    private enum CodingKeys: String, CodingKey {
        case key
        case source
        case status
        case capture
        case dataTypeFourCC
        case rawBytesHex
        case decodedWatts
        case ioReturn
        case validationIssue
    }

    fileprivate func validateContract() throws {
        if let rawBytesHex, !validateUppercaseHex(rawBytesHex) {
            throw NestedObservationValidationError.invalidSMCKey(
                "rawBytesHex must use non-empty uppercase even-length hex"
            )
        }
        switch status {
        case .present:
            guard let dataTypeFourCC,
                  dataTypeFourCC.count == 4,
                  rawBytesHex != nil,
                  let decodedWatts,
                  decodedWatts.isFinite else {
                throw NestedObservationValidationError.invalidSMCKey(
                    "present keys require type, raw bytes, and finite decoded watts"
                )
            }
            if key == "PPBR", decodedWatts < 0 {
                throw NestedObservationValidationError.invalidSMCKey(
                    "PPBR must remain a non-negative discharge magnitude"
                )
            }
        case .keyUnavailable,
             .keyInfoFailed,
             .valueReadFailed,
             .unsupportedType,
             .invalidValue:
            guard decodedWatts == nil else {
                throw NestedObservationValidationError.invalidSMCKey(
                    "failed keys cannot contain decoded watts"
                )
            }
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            key: try container.decode(String.self, forKey: .key),
            source: try container.decode(ObservationSource.self, forKey: .source),
            status: try container.decode(SMCKeyStatus.self, forKey: .status),
            capture: try container.decode(MonotonicInterval.self, forKey: .capture),
            dataTypeFourCC: try container.decodeRequiredNullable(
                String.self,
                forKey: .dataTypeFourCC
            ),
            rawBytesHex: try container.decodeRequiredNullable(
                String.self,
                forKey: .rawBytesHex
            ),
            decodedWatts: try container.decodeRequiredNullable(
                Double.self,
                forKey: .decodedWatts
            ),
            ioReturn: try container.decodeRequiredNullable(Int32.self, forKey: .ioReturn),
            validationIssue: try container.decodeRequiredNullable(
                String.self,
                forKey: .validationIssue
            )
        )
        do {
            try validateContract()
        } catch {
            throw observationDataCorrupted(decoder, String(describing: error))
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
        try container.encode(key, forKey: .key)
        try container.encode(source, forKey: .source)
        try container.encode(status, forKey: .status)
        try container.encode(capture, forKey: .capture)
        try container.encodeRequiredNullable(dataTypeFourCC, forKey: .dataTypeFourCC)
        try container.encodeRequiredNullable(rawBytesHex, forKey: .rawBytesHex)
        try container.encodeRequiredNullable(decodedWatts, forKey: .decodedWatts)
        try container.encodeRequiredNullable(ioReturn, forKey: .ioReturn)
        try container.encodeRequiredNullable(
            validationIssue,
            forKey: .validationIssue
        )
    }
}

extension SMCObservation {
    private enum CodingKeys: String, CodingKey {
        case connectionStatus
        case connectionCapture
        case keys
    }

    fileprivate func validateContract() throws {
        guard keys.map(\.key) == Self.requiredKeyOrder else {
            throw SMCObservationError.invalidKeyOrder(
                keys.map(\.key)
            )
        }
        let expectedSources: [ObservationSource] = [
            .smcPDTR,
            .smcPSTR,
            .smcPPBR,
        ]
        for (key, source) in zip(keys, expectedSources) {
            guard key.source == source else {
                throw SMCObservationError.invalidSource(
                    key: key.key,
                    source: key.source
                )
            }
            try key.validateContract()
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                connectionStatus: try container.decode(
                    SMCConnectionStatus.self,
                    forKey: .connectionStatus
                ),
                connectionCapture: try container.decode(
                    MonotonicInterval.self,
                    forKey: .connectionCapture
                ),
                keys: try container.decode([SMCKeyObservation].self, forKey: .keys)
            )
        } catch let error as DecodingError {
            throw error
        } catch {
            throw observationDataCorrupted(decoder, String(describing: error))
        }
    }
}

extension ObservationTimingEvidence {
    private enum CodingKeys: String, CodingKey {
        case observationStartedContinuousNanoseconds
        case observationEndedContinuousNanoseconds
        case totalCaptureDurationMilliseconds
        case smcKeySkewMilliseconds
        case batteryMidpointMinusSMCMidpointMilliseconds
        case absoluteBatterySMCSkewMilliseconds
    }

    fileprivate func validateContract() throws {
        guard observationEndedContinuousNanoseconds
                >= observationStartedContinuousNanoseconds else {
            throw NestedObservationValidationError.invalidTiming(
                "observation end precedes start"
            )
        }
        let expectedDuration = Double(
            observationEndedContinuousNanoseconds
                - observationStartedContinuousNanoseconds
        ) / 1_000_000
        guard totalCaptureDurationMilliseconds.isFinite,
              totalCaptureDurationMilliseconds >= 0,
              valuesApproximatelyEqual(
                  totalCaptureDurationMilliseconds,
                  expectedDuration
              ) else {
            throw NestedObservationValidationError.invalidTiming(
                "total capture duration is inconsistent"
            )
        }
        if let smcKeySkewMilliseconds {
            guard smcKeySkewMilliseconds.isFinite,
                  smcKeySkewMilliseconds >= 0 else {
                throw NestedObservationValidationError.invalidTiming(
                    "SMC key skew must be finite and non-negative"
                )
            }
        }
        switch (
            batteryMidpointMinusSMCMidpointMilliseconds,
            absoluteBatterySMCSkewMilliseconds
        ) {
        case (nil, nil):
            break
        case let (signed?, absolute?):
            guard signed.isFinite,
                  absolute.isFinite,
                  absolute >= 0,
                  valuesApproximatelyEqual(absolute, abs(signed)) else {
                throw NestedObservationValidationError.invalidTiming(
                    "signed and absolute battery-SMC skew disagree"
                )
            }
        default:
            throw NestedObservationValidationError.invalidTiming(
                "signed and absolute battery-SMC skew must both be present or absent"
            )
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            observationStartedContinuousNanoseconds: try container.decode(
                UInt64.self,
                forKey: .observationStartedContinuousNanoseconds
            ),
            observationEndedContinuousNanoseconds: try container.decode(
                UInt64.self,
                forKey: .observationEndedContinuousNanoseconds
            ),
            totalCaptureDurationMilliseconds: try container.decode(
                Double.self,
                forKey: .totalCaptureDurationMilliseconds
            ),
            smcKeySkewMilliseconds: try container.decodeRequiredNullable(
                Double.self,
                forKey: .smcKeySkewMilliseconds
            ),
            batteryMidpointMinusSMCMidpointMilliseconds:
                try container.decodeRequiredNullable(
                    Double.self,
                    forKey: .batteryMidpointMinusSMCMidpointMilliseconds
                ),
            absoluteBatterySMCSkewMilliseconds:
                try container.decodeRequiredNullable(
                    Double.self,
                    forKey: .absoluteBatterySMCSkewMilliseconds
                )
        )
        do {
            try validateContract()
        } catch {
            throw observationDataCorrupted(decoder, String(describing: error))
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
        try container.encode(
            observationStartedContinuousNanoseconds,
            forKey: .observationStartedContinuousNanoseconds
        )
        try container.encode(
            observationEndedContinuousNanoseconds,
            forKey: .observationEndedContinuousNanoseconds
        )
        try container.encode(
            totalCaptureDurationMilliseconds,
            forKey: .totalCaptureDurationMilliseconds
        )
        try container.encodeRequiredNullable(
            smcKeySkewMilliseconds,
            forKey: .smcKeySkewMilliseconds
        )
        try container.encodeRequiredNullable(
            batteryMidpointMinusSMCMidpointMilliseconds,
            forKey: .batteryMidpointMinusSMCMidpointMilliseconds
        )
        try container.encodeRequiredNullable(
            absoluteBatterySMCSkewMilliseconds,
            forKey: .absoluteBatterySMCSkewMilliseconds
        )
    }
}

extension ModuloAnchor {
    private enum CodingKeys: String, CodingKey {
        case identifier
        case source
        case watts
        case capture
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let identifier = try container.decode(String.self, forKey: .identifier)
        let watts = try container.decode(Double.self, forKey: .watts)
        guard !identifier.isEmpty, watts.isFinite, watts >= 0 else {
            throw observationDataCorrupted(
                decoder,
                "PSTR anchor identifier and watts are invalid"
            )
        }
        self.init(
            identifier: identifier,
            source: try container.decode(ObservationSource.self, forKey: .source),
            watts: watts,
            capture: try container.decode(MonotonicInterval.self, forKey: .capture)
        )
    }
}

extension ModuloCandidate {
    private enum CodingKeys: String, CodingKey {
        case multiple
        case candidateWatts
        case deltaToAnchorsWatts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let candidateWatts = try container.decode(Double.self, forKey: .candidateWatts)
        let deltas = try container.decode([Double].self, forKey: .deltaToAnchorsWatts)
        guard candidateWatts.isFinite,
              deltas.allSatisfy(\.isFinite) else {
            throw observationDataCorrupted(
                decoder,
                "PSTR candidate contains a non-finite value"
            )
        }
        self.init(
            multiple: try container.decode(Int.self, forKey: .multiple),
            candidateWatts: candidateWatts,
            deltaToAnchorsWatts: deltas
        )
    }
}

extension PSTRModuloEvidence {
    private enum CodingKeys: String, CodingKey {
        case status
        case rawPSTRWatts
        case modulusWatts
        case anchors
        case candidates
        case validationIssue
    }

    fileprivate func validateContract() throws {
        guard modulusWatts == Self.requiredModulusWatts else {
            throw NestedObservationValidationError.invalidModulo(
                "modulusWatts must equal exactly 65.536"
            )
        }
        guard anchors.allSatisfy({
            !$0.identifier.isEmpty
                && $0.watts.isFinite
                && $0.watts >= 0
        }) else {
            throw NestedObservationValidationError.invalidModulo(
                "PSTR anchors must have identifiers and finite non-negative watts"
            )
        }

        guard let rawPSTRWatts,
              rawPSTRWatts.isFinite,
              rawPSTRWatts >= 0 else {
            guard status == .insufficientData,
                  candidates.isEmpty,
                  validationIssue?.isEmpty == false else {
                throw NestedObservationValidationError.invalidModulo(
                    "missing or invalid raw PSTR requires insufficientData, no candidates, and an issue"
                )
            }
            return
        }

        guard status == .candidatesGenerated,
              candidates.count == Self.candidateMultiples.count else {
            throw NestedObservationValidationError.invalidModulo(
                "valid raw PSTR requires exactly four generated candidates"
            )
        }
        for (candidate, multiple) in zip(
            candidates,
            Self.candidateMultiples
        ) {
            let expectedWatts =
                rawPSTRWatts
                + Double(multiple) * Self.requiredModulusWatts
            guard candidate.multiple == multiple,
                  candidate.candidateWatts == expectedWatts,
                  candidate.deltaToAnchorsWatts.count
                    == anchors.count else {
                throw NestedObservationValidationError.invalidModulo(
                    "PSTR candidate does not match its required multiple"
                )
            }
            for (delta, anchor) in zip(
                candidate.deltaToAnchorsWatts,
                anchors
            ) {
                guard delta == expectedWatts - anchor.watts else {
                    throw NestedObservationValidationError.invalidModulo(
                        "PSTR candidate delta does not match its anchor"
                    )
                }
            }
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let serializedStatus = try container.decode(
            ModuloEvidenceStatus.self,
            forKey: .status
        )
        let serializedRaw = try container.decodeRequiredNullable(
            Double.self,
            forKey: .rawPSTRWatts
        )
        let serializedModulus = try container.decode(Double.self, forKey: .modulusWatts)
        let serializedAnchors = try container.decode([ModuloAnchor].self, forKey: .anchors)
        let serializedCandidates = try container.decode(
            [ModuloCandidate].self,
            forKey: .candidates
        )
        let serializedIssue = try container.decodeRequiredNullable(
            String.self,
            forKey: .validationIssue
        )

        let expected = PSTRModuloEvidence(
            rawPSTRWatts: serializedRaw,
            anchors: serializedAnchors,
            modulusWatts: serializedModulus,
            validationIssue: serializedIssue
        )
        guard serializedStatus == expected.status,
              serializedCandidates == expected.candidates,
              serializedIssue == expected.validationIssue else {
            throw observationDataCorrupted(
                decoder,
                "serialized PSTR modulo evidence is inconsistent"
            )
        }
        self = expected
        do {
            try validateContract()
        } catch {
            throw observationDataCorrupted(
                decoder,
                String(describing: error)
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
        try container.encode(status, forKey: .status)
        try container.encodeRequiredNullable(rawPSTRWatts, forKey: .rawPSTRWatts)
        try container.encode(modulusWatts, forKey: .modulusWatts)
        try container.encode(anchors, forKey: .anchors)
        try container.encode(candidates, forKey: .candidates)
        try container.encodeRequiredNullable(
            validationIssue,
            forKey: .validationIssue
        )
    }
}

extension PowerBalanceEvidence {
    private enum CodingKeys: String, CodingKey {
        case identifier
        case adapterSource
        case systemSource
        case batterySource
        case externalSource
        case residualWatts
        case maximumInputSkewMilliseconds
    }

    fileprivate func validateContract() throws {
        guard identifier == "iokit.telemetry"
                || identifier == "smc.direct" else {
            throw NestedObservationValidationError.invalidBalance(
                "unsupported balance identifier"
            )
        }
        if let residualWatts, !residualWatts.isFinite {
            throw NestedObservationValidationError.invalidBalance(
                "residual must be finite"
            )
        }
        if let maximumInputSkewMilliseconds,
           (!maximumInputSkewMilliseconds.isFinite
            || maximumInputSkewMilliseconds < 0) {
            throw NestedObservationValidationError.invalidBalance(
                "maximum input skew must be finite and non-negative"
            )
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            identifier: try container.decode(String.self, forKey: .identifier),
            adapterSource: try container.decodeRequiredNullable(
                ObservationSource.self,
                forKey: .adapterSource
            ),
            systemSource: try container.decodeRequiredNullable(
                ObservationSource.self,
                forKey: .systemSource
            ),
            batterySource: try container.decodeRequiredNullable(
                ObservationSource.self,
                forKey: .batterySource
            ),
            externalSource: try container.decodeRequiredNullable(
                ObservationSource.self,
                forKey: .externalSource
            ),
            residualWatts: try container.decodeRequiredNullable(
                Double.self,
                forKey: .residualWatts
            ),
            maximumInputSkewMilliseconds: try container.decodeRequiredNullable(
                Double.self,
                forKey: .maximumInputSkewMilliseconds
            )
        )
        do {
            try validateContract()
        } catch {
            throw observationDataCorrupted(decoder, String(describing: error))
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
        try container.encode(identifier, forKey: .identifier)
        try container.encodeRequiredNullable(adapterSource, forKey: .adapterSource)
        try container.encodeRequiredNullable(systemSource, forKey: .systemSource)
        try container.encodeRequiredNullable(batterySource, forKey: .batterySource)
        try container.encodeRequiredNullable(externalSource, forKey: .externalSource)
        try container.encodeRequiredNullable(residualWatts, forKey: .residualWatts)
        try container.encodeRequiredNullable(
            maximumInputSkewMilliseconds,
            forKey: .maximumInputSkewMilliseconds
        )
    }
}

extension RawPowerEvidence {
    fileprivate func validateContract(
        battery: AppleSmartBatteryObservation,
        smc: SMCObservation
    ) throws {
        guard batteryVoltageTimesCurrent.identifier
                == "evidence.batteryVoltageTimesCurrent",
              batteryVoltageTimesCurrent.kind == .derived else {
            throw NestedObservationValidationError.invalidEvidence(
                "battery V×I evidence has an invalid fixed-field contract"
            )
        }
        guard systemVoltageTimesCurrent.identifier
                == "evidence.systemVoltageTimesCurrent",
              systemVoltageTimesCurrent.kind == .derived else {
            throw NestedObservationValidationError.invalidEvidence(
                "system V×I evidence has an invalid fixed-field contract"
            )
        }
        try requireDerivedReading(batteryVoltageTimesCurrent)
        try requireDerivedReading(systemVoltageTimesCurrent)
        try timing.validateContract()
        try pstrModulo.validateContract()

        guard timing.observationStartedContinuousNanoseconds
                <= battery.capture.startedContinuousNanoseconds,
              timing.observationStartedContinuousNanoseconds
                <= smc.connectionCapture.startedContinuousNanoseconds,
              timing.observationEndedContinuousNanoseconds
                >= battery.capture.endedContinuousNanoseconds,
              timing.observationEndedContinuousNanoseconds
                >= smc.connectionCapture.endedContinuousNanoseconds else {
            throw NestedObservationValidationError.invalidTiming(
                "observation bounds must contain both reader captures"
            )
        }

        let presentSMCCaptures = smc.keys.compactMap {
            $0.status == .present ? $0.capture : nil
        }
        let expectedSMCKeySkew =
            maximumMidpointSkewMilliseconds(
                presentSMCCaptures
            )
        guard timing.smcKeySkewMilliseconds
                == expectedSMCKeySkew else {
            throw NestedObservationValidationError.invalidTiming(
                "SMC key skew must be derived from present key midpoints"
            )
        }

        let expectedSignedBatterySMCSkew: Double?
        if battery.servicePresence == .present,
           smc.connectionStatus == .opened {
            expectedSignedBatterySMCSkew =
                signedMidpointDifferenceMilliseconds(
                    battery.capture,
                    smc.connectionCapture
                )
        } else {
            expectedSignedBatterySMCSkew = nil
        }
        guard timing.batteryMidpointMinusSMCMidpointMilliseconds
                == expectedSignedBatterySMCSkew,
              timing.absoluteBatterySMCSkewMilliseconds
                == expectedSignedBatterySMCSkew.map(abs) else {
            throw NestedObservationValidationError.invalidTiming(
                "battery-SMC skew must be derived from the source captures"
            )
        }

        guard let pstr = smc.key("PSTR") else {
            throw NestedObservationValidationError.invalidModulo(
                "PSTR key is required"
            )
        }
        if pstr.status == .present {
            guard pstr.decodedWatts == pstrModulo.rawPSTRWatts else {
                throw NestedObservationValidationError.invalidModulo(
                    "direct PSTR and modulo raw PSTR disagree"
                )
            }
        } else {
            guard pstrModulo.rawPSTRWatts == nil else {
                throw NestedObservationValidationError.invalidModulo(
                    "unavailable PSTR cannot publish modulo raw watts"
                )
            }
        }

        var identifiers = Set<String>()
        for balance in balances {
            guard identifiers.insert(balance.identifier).inserted else {
                throw NestedObservationValidationError.invalidBalance(
                    "duplicate balance identifier"
                )
            }
            try balance.validateContract()
            switch balance.identifier {
            case "iokit.telemetry":
                try validateIOKitBalance(
                    balance,
                    telemetry: battery.powerTelemetry
                )
            case "smc.direct":
                try validateSMCDirectBalance(
                    balance,
                    smc: smc,
                    batteryVI: batteryVoltageTimesCurrent
                )
            default:
                throw NestedObservationValidationError.invalidBalance(
                    "unsupported balance identifier"
                )
            }
        }
    }

    private func validateIOKitBalance(
        _ balance: PowerBalanceEvidence,
        telemetry: BatteryPowerTelemetryObservation
    ) throws {
        let adapter = telemetry.systemPowerIn
        let system = telemetry.systemLoad
        let battery = telemetry.batteryPower
        let adapterWatts = adapter.presence == .present
            ? adapter.watts : nil
        let systemWatts = system.presence == .present
            ? system.watts : nil
        let batteryWatts = battery.presence == .present
            ? battery.watts : nil
        let expectedAdapterSource = adapterWatts == nil
            ? nil : adapter.source
        let expectedSystemSource = systemWatts == nil
            ? nil : system.source
        let expectedBatterySource = batteryWatts == nil
            ? nil : battery.source

        guard balance.adapterSource
                == expectedAdapterSource,
              balance.systemSource
                == expectedSystemSource,
              balance.batterySource
                == expectedBatterySource,
              balance.externalSource == nil else {
            throw NestedObservationValidationError.invalidBalance(
                "iokit.telemetry sources do not match direct branches"
            )
        }

        if let adapterWatts,
           let systemWatts,
           let batteryWatts {
            let expectedResidual =
                adapterWatts - systemWatts - batteryWatts
            let expectedSkew =
                maximumMidpointSkewMilliseconds([
                    adapter.capture,
                    system.capture,
                    battery.capture,
                ])
            guard balance.residualWatts == expectedResidual,
                  balance.maximumInputSkewMilliseconds
                    == expectedSkew else {
                throw NestedObservationValidationError.invalidBalance(
                    "iokit.telemetry residual or skew is inconsistent"
                )
            }
        } else {
            guard balance.residualWatts == nil,
                  balance.maximumInputSkewMilliseconds == nil else {
                throw NestedObservationValidationError.invalidBalance(
                    "iokit.telemetry cannot derive evidence from a missing branch"
                )
            }
        }
    }

    private func validateSMCDirectBalance(
        _ balance: PowerBalanceEvidence,
        smc: SMCObservation,
        batteryVI: PowerReading
    ) throws {
        guard let adapter = smc.key("PDTR"),
              let system = smc.key("PSTR") else {
            throw NestedObservationValidationError.invalidBalance(
                "SMC fixed keys are required"
            )
        }
        let adapterWatts = adapter.status == .present
            ? adapter.decodedWatts : nil
        let systemWatts = system.status == .present
            ? system.decodedWatts : nil
        let batteryWatts = batteryVI.presence == .present
            ? batteryVI.watts : nil
        let expectedAdapterSource = adapterWatts == nil
            ? nil : adapter.source
        let expectedSystemSource = systemWatts == nil
            ? nil : system.source
        let expectedBatterySource = batteryWatts == nil
            ? nil : batteryVI.source

        guard balance.adapterSource
                == expectedAdapterSource,
              balance.systemSource
                == expectedSystemSource,
              balance.batterySource
                == expectedBatterySource,
              balance.externalSource == nil else {
            throw NestedObservationValidationError.invalidBalance(
                "smc.direct sources do not match direct branches"
            )
        }

        if let adapterWatts,
           let systemWatts,
           let batteryWatts {
            let expectedResidual =
                adapterWatts - systemWatts - batteryWatts
            let expectedSkew =
                maximumMidpointSkewMilliseconds([
                    adapter.capture,
                    system.capture,
                    batteryVI.capture,
                ])
            guard balance.residualWatts == expectedResidual,
                  balance.maximumInputSkewMilliseconds
                    == expectedSkew else {
                throw NestedObservationValidationError.invalidBalance(
                    "smc.direct residual or skew is inconsistent"
                )
            }
        } else {
            guard balance.residualWatts == nil,
                  balance.maximumInputSkewMilliseconds == nil else {
                throw NestedObservationValidationError.invalidBalance(
                    "smc.direct cannot derive evidence from a missing branch"
                )
            }
        }
    }
}

extension RawPowerObservation {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case sequence
        case scenario
        case finalizedAtContinuousNanoseconds
        case battery
        case smc
        case evidence
    }

    fileprivate func validateContract() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw PowerObservationTraceRecordError
                .invalidSchemaVersion(schemaVersion)
        }
        try battery.validateContract()
        try smc.validateContract()
        try evidence.validateContract(
            battery: battery,
            smc: smc
        )
        guard finalizedAtContinuousNanoseconds
                >= evidence.timing
                    .observationEndedContinuousNanoseconds else {
            throw NestedObservationValidationError.invalidRawObservation(
                "finalization must not precede the observation end"
            )
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                schemaVersion: try container.decode(Int.self, forKey: .schemaVersion),
                sequence: try container.decode(UInt64.self, forKey: .sequence),
                scenario: try container.decodeRequiredNullable(String.self, forKey: .scenario),
                finalizedAtContinuousNanoseconds: try container.decode(
                    UInt64.self,
                    forKey: .finalizedAtContinuousNanoseconds
                ),
                battery: try container.decode(
                    AppleSmartBatteryObservation.self,
                    forKey: .battery
                ),
                smc: try container.decode(SMCObservation.self, forKey: .smc),
                evidence: try container.decode(RawPowerEvidence.self, forKey: .evidence)
            )
        } catch let error as DecodingError {
            throw error
        } catch {
            throw observationDataCorrupted(decoder, String(describing: error))
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
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(sequence, forKey: .sequence)
        try container.encodeRequiredNullable(scenario, forKey: .scenario)
        try container.encode(
            finalizedAtContinuousNanoseconds,
            forKey: .finalizedAtContinuousNanoseconds
        )
        try container.encode(battery, forKey: .battery)
        try container.encode(smc, forKey: .smc)
        try container.encode(evidence, forKey: .evidence)
    }
}
