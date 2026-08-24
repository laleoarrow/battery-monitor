import Foundation
import CoreFoundation

// MARK: - Protocol v5 request

struct PowerObservationV5Request: Codable, Equatable, Sendable {
    static let protocolVersion = 5
    static let operation = "getPowerObservation"

    let wattsonProtocol: Int
    let op: String
    let clientSequence: UInt64

    init(clientSequence: UInt64) {
        wattsonProtocol = Self.protocolVersion
        op = Self.operation
        self.clientSequence = clientSequence
    }

    private enum CodingKeys: String, CodingKey {
        case wattsonProtocol = "_wattsonProtocol"
        case op
        case clientSequence
    }
}

// MARK: - Protocol v5 wire model

enum PowerObservationV5ConnectionStatus: String, Codable, Equatable, Sendable {
    case opened
    case serviceUnavailable
    case openFailed
    case layoutMismatch
}

enum PowerObservationV5KeyStatus: String, Codable, Equatable, Sendable {
    case present
    case connectionUnavailable
    case keyUnavailable
    case keyInfoFailed
    case valueReadFailed
    case unsupportedType
    case invalidValue
}

struct PowerObservationV5Connection: Equatable, Sendable {
    let status: PowerObservationV5ConnectionStatus
    let startedContinuousNanoseconds: UInt64
    let endedContinuousNanoseconds: UInt64
    let ioReturn: Int32?
    let validationIssue: String?

    var capture: MonotonicInterval? {
        try? MonotonicInterval(
            startedContinuousNanoseconds: startedContinuousNanoseconds,
            endedContinuousNanoseconds: endedContinuousNanoseconds
        )
    }
}

struct PowerObservationV5Key: Equatable, Sendable {
    let key: String
    let source: ObservationSource
    let status: PowerObservationV5KeyStatus
    let startedContinuousNanoseconds: UInt64
    let endedContinuousNanoseconds: UInt64
    let dataTypeFourCC: String?
    let rawBytesHex: String?
    let decodedWatts: Double?
    let ioReturn: Int32?
    let validationIssue: String?

    var capture: MonotonicInterval? {
        try? MonotonicInterval(
            startedContinuousNanoseconds: startedContinuousNanoseconds,
            endedContinuousNanoseconds: endedContinuousNanoseconds
        )
    }
}

struct PowerObservationV5Response: Equatable, Sendable {
    static let protocolVersion = 5
    static let clockName = "CLOCK_MONOTONIC_RAW"
    static let requiredKeyOrder = ["PDTR", "PSTR", "PPBR"]

    let wattsonProtocol: Int
    let ok: Bool
    let partial: Bool
    let clientSequence: UInt64
    let clock: String
    let error: String?
    let connection: PowerObservationV5Connection
    let keys: [PowerObservationV5Key]

    func key(_ name: String) -> PowerObservationV5Key? {
        keys.first { $0.key == name }
    }

    func asSMCObservation() throws -> SMCObservation {
        let mappedConnectionStatus: SMCConnectionStatus
        switch connection.status {
        case .opened:
            mappedConnectionStatus = .opened
        case .serviceUnavailable:
            mappedConnectionStatus = .serviceUnavailable
        case .openFailed, .layoutMismatch:
            mappedConnectionStatus = .openFailed
        }

        let interval = try MonotonicInterval(
            startedContinuousNanoseconds: connection.startedContinuousNanoseconds,
            endedContinuousNanoseconds: connection.endedContinuousNanoseconds
        )

        let mappedKeys = try keys.map { key in
            let source: ObservationSource
            switch key.key {
            case "PDTR": source = .smcPDTR
            case "PSTR": source = .smcPSTR
            case "PPBR": source = .smcPPBR
            default:
                throw PowerObservationV5ValidationError.invalidKeyOrder(keys.map(\.key))
            }

            let mappedStatus: SMCKeyStatus
            switch key.status {
            case .present:
                mappedStatus = .present
            case .connectionUnavailable, .keyUnavailable:
                mappedStatus = .keyUnavailable
            case .keyInfoFailed:
                mappedStatus = .keyInfoFailed
            case .valueReadFailed:
                mappedStatus = .valueReadFailed
            case .unsupportedType:
                mappedStatus = .unsupportedType
            case .invalidValue:
                mappedStatus = .invalidValue
            }

            return SMCKeyObservation(
                key: key.key,
                source: source,
                status: mappedStatus,
                capture: try MonotonicInterval(
                    startedContinuousNanoseconds: key.startedContinuousNanoseconds,
                    endedContinuousNanoseconds: key.endedContinuousNanoseconds
                ),
                dataTypeFourCC: key.dataTypeFourCC,
                rawBytesHex: key.rawBytesHex,
                decodedWatts: key.decodedWatts,
                ioReturn: key.ioReturn,
                validationIssue: key.validationIssue
            )
        }

        return try SMCObservation(
            connectionStatus: mappedConnectionStatus,
            connectionCapture: interval,
            keys: mappedKeys
        )
    }
}

// MARK: - Strict decoder

enum PowerObservationV5DecodeOutcome: Equatable, Sendable {
    case response(PowerObservationV5Response)
    case legacyOrUnsupportedProtocol
    case malformed(PowerObservationV5DecodeFailure)
}

enum PowerObservationV5DecodeFailure: String, Equatable, Sendable {
    case emptyFrame
    case frameTooLarge
    case invalidJSON
    case nonObject
    case unknownTopLevelField
    case missingTopLevelField
    case invalidProtocol
    case invalidOperationResponse
    case sequenceMismatch
    case invalidConnection
    case invalidKeys
    case invalidKey
    case semanticMismatch
}

enum PowerObservationV5ValidationError: Error, Equatable {
    case invalidProtocol(Int)
    case invalidClock(String)
    case invalidSequence(expected: UInt64, actual: UInt64)
    case invalidConnection(String)
    case invalidKeyOrder([String])
    case invalidKey(String)
    case invalidPartial
    case invalidOK
    case invalidError
}

struct PowerObservationV5Decoder {
    static let maximumFrameBytes = 4_096

    private static let topLevelKeys: Set<String> = [
        "_wattsonProtocol", "ok", "partial", "clientSequence", "clock",
        "error", "connection", "keys",
    ]
    private static let connectionKeys: Set<String> = [
        "status", "startedNs", "endedNs", "ioReturn", "validationIssue",
    ]
    private static let keyKeys: Set<String> = [
        "key", "source", "status", "startedNs", "endedNs", "dataType",
        "rawBytesHex", "watts", "ioReturn", "validationIssue",
    ]

    func decode(
        frame: Data,
        expectedClientSequence: UInt64
    ) -> PowerObservationV5DecodeOutcome {
        guard !frame.isEmpty else { return .malformed(.emptyFrame) }
        guard frame.count < Self.maximumFrameBytes else {
            return .malformed(.frameTooLarge)
        }
        guard let json = try? JSONSerialization.jsonObject(with: frame) else {
            return .malformed(.invalidJSON)
        }
        guard let object = json as? [String: Any] else {
            return .malformed(.nonObject)
        }

        guard object.keys.contains("_wattsonProtocol") else {
            // An old helper can close the connection, return no frame, or return
            // an unversioned rejection. The client may perform one v4 retry.
            return .legacyOrUnsupportedProtocol
        }
        guard let rawProtocol = strictInteger(object["_wattsonProtocol"]) else {
            // A protocol field is a claim about framing. A malformed claim is
            // never evidence that the helper is old and must not trigger v4.
            return .malformed(.invalidProtocol)
        }
        guard rawProtocol == PowerObservationV5Response.protocolVersion else {
            return .legacyOrUnsupportedProtocol
        }
        guard Set(object.keys) == Self.topLevelKeys else {
            return Set(object.keys).isSuperset(of: Self.topLevelKeys)
                ? .malformed(.unknownTopLevelField)
                : .malformed(.missingTopLevelField)
        }

        do {
            let response = try decodeValidatedObject(
                object,
                expectedClientSequence: expectedClientSequence
            )
            return .response(response)
        } catch let error as PowerObservationV5ValidationError {
            switch error {
            case .invalidProtocol:
                return .malformed(.invalidProtocol)
            case .invalidClock:
                return .malformed(.invalidOperationResponse)
            case .invalidSequence:
                return .malformed(.sequenceMismatch)
            case .invalidConnection:
                return .malformed(.invalidConnection)
            case .invalidKeyOrder:
                return .malformed(.invalidKeys)
            case .invalidKey:
                return .malformed(.invalidKey)
            case .invalidPartial, .invalidOK, .invalidError:
                return .malformed(.semanticMismatch)
            }
        } catch {
            return .malformed(.invalidJSON)
        }
    }

    private func decodeValidatedObject(
        _ object: [String: Any],
        expectedClientSequence: UInt64
    ) throws -> PowerObservationV5Response {
        guard strictInteger(object["_wattsonProtocol"])
                == PowerObservationV5Response.protocolVersion else {
            throw PowerObservationV5ValidationError.invalidProtocol(
                strictInteger(object["_wattsonProtocol"]) ?? -1
            )
        }
        guard let ok = strictBool(object["ok"]),
              let partial = strictBool(object["partial"]),
              let clientSequence = strictUInt64(object["clientSequence"]),
              let clock = object["clock"] as? String,
              let connectionObject = object["connection"] as? [String: Any],
              let keyObjects = object["keys"] as? [[String: Any]] else {
            throw PowerObservationV5ValidationError.invalidConnection(
                "top-level field type mismatch"
            )
        }
        guard clientSequence == expectedClientSequence else {
            throw PowerObservationV5ValidationError.invalidSequence(
                expected: expectedClientSequence,
                actual: clientSequence
            )
        }
        guard clock == PowerObservationV5Response.clockName else {
            throw PowerObservationV5ValidationError.invalidClock(clock)
        }
        let error = try requiredNullableString(object, key: "error")
        let connection = try decodeConnection(connectionObject)
        let keys = try keyObjects.map(decodeKey)
        guard keys.map(\.key) == PowerObservationV5Response.requiredKeyOrder else {
            throw PowerObservationV5ValidationError.invalidKeyOrder(keys.map(\.key))
        }
        let expectedSources: [ObservationSource] = [.smcPDTR, .smcPSTR, .smcPPBR]
        guard zip(keys, expectedSources).allSatisfy({ $0.0.source == $0.1 }) else {
            throw PowerObservationV5ValidationError.invalidKey("source mismatch")
        }

        let connectionOpened = connection.status == .opened
        guard ok == connectionOpened else {
            throw PowerObservationV5ValidationError.invalidOK
        }
        let expectedPartial = !connectionOpened || keys.contains { $0.status != .present }
        guard partial == expectedPartial else {
            throw PowerObservationV5ValidationError.invalidPartial
        }
        if connectionOpened {
            guard keys.allSatisfy({ $0.status != .connectionUnavailable }) else {
                throw PowerObservationV5ValidationError.invalidKey(
                    "opened connection cannot publish connectionUnavailable keys"
                )
            }
        } else {
            guard keys.allSatisfy({ $0.status == .connectionUnavailable }) else {
                throw PowerObservationV5ValidationError.invalidKey(
                    "failed connection must publish three connectionUnavailable keys"
                )
            }
        }
        guard keys.allSatisfy({
            $0.startedContinuousNanoseconds >= connection.startedContinuousNanoseconds
                && $0.endedContinuousNanoseconds <= connection.endedContinuousNanoseconds
        }) else {
            throw PowerObservationV5ValidationError.invalidKey(
                "key capture must be contained by the connection capture"
            )
        }
        if ok {
            guard error == nil else { throw PowerObservationV5ValidationError.invalidError }
        } else {
            guard let error, !error.isEmpty else {
                throw PowerObservationV5ValidationError.invalidError
            }
        }

        return PowerObservationV5Response(
            wattsonProtocol: PowerObservationV5Response.protocolVersion,
            ok: ok,
            partial: partial,
            clientSequence: clientSequence,
            clock: clock,
            error: error,
            connection: connection,
            keys: keys
        )
    }

    private func decodeConnection(
        _ object: [String: Any]
    ) throws -> PowerObservationV5Connection {
        guard Set(object.keys) == Self.connectionKeys,
              let rawStatus = object["status"] as? String,
              let status = PowerObservationV5ConnectionStatus(rawValue: rawStatus),
              let started = strictUInt64(object["startedNs"]),
              let ended = strictUInt64(object["endedNs"]),
              ended >= started else {
            throw PowerObservationV5ValidationError.invalidConnection(
                "invalid connection object"
            )
        }
        let ioReturn = try requiredNullableInt32(object, key: "ioReturn")
        let issue = try requiredNullableString(object, key: "validationIssue")
        switch status {
        case .opened:
            guard issue == nil, ioReturn == nil else {
                throw PowerObservationV5ValidationError.invalidConnection(
                    "opened connection cannot carry an issue or failure code"
                )
            }
        case .serviceUnavailable, .openFailed, .layoutMismatch:
            guard let issue, !issue.isEmpty else {
                throw PowerObservationV5ValidationError.invalidConnection(
                    "failed connection requires an issue"
                )
            }
        }
        return PowerObservationV5Connection(
            status: status,
            startedContinuousNanoseconds: started,
            endedContinuousNanoseconds: ended,
            ioReturn: ioReturn,
            validationIssue: issue
        )
    }

    private func decodeKey(
        _ object: [String: Any]
    ) throws -> PowerObservationV5Key {
        guard Set(object.keys) == Self.keyKeys,
              let key = object["key"] as? String,
              let sourceRaw = object["source"] as? String,
              let rawStatus = object["status"] as? String,
              let status = PowerObservationV5KeyStatus(rawValue: rawStatus),
              let started = strictUInt64(object["startedNs"]),
              let ended = strictUInt64(object["endedNs"]),
              ended >= started else {
            throw PowerObservationV5ValidationError.invalidKey("field type mismatch")
        }
        let source = ObservationSource(sourceRaw)
        let dataType = try requiredNullableString(object, key: "dataType")
        let rawBytes = try requiredNullableString(object, key: "rawBytesHex")
        let watts = try requiredNullableFiniteDouble(object, key: "watts")
        let ioReturn = try requiredNullableInt32(object, key: "ioReturn")
        let issue = try requiredNullableString(object, key: "validationIssue")

        if let rawBytes, !Self.isUppercaseEvenHex(rawBytes) {
            throw PowerObservationV5ValidationError.invalidKey("invalid raw bytes")
        }
        switch status {
        case .present:
            guard let dataType, dataType.utf8.count == 4,
                  rawBytes != nil,
                  let watts,
                  ioReturn == nil,
                  issue == nil else {
                throw PowerObservationV5ValidationError.invalidKey(
                    "present key shape is invalid"
                )
            }
            if key == "PPBR", watts < 0 {
                throw PowerObservationV5ValidationError.invalidKey(
                    "PPBR must remain a non-negative discharge magnitude"
                )
            }
        case .connectionUnavailable, .keyInfoFailed:
            guard dataType == nil, rawBytes == nil, watts == nil,
                  issue?.isEmpty == false else {
                throw PowerObservationV5ValidationError.invalidKey(
                    "unavailable key shape is invalid"
                )
            }
        case .keyUnavailable:
            guard dataType == nil || dataType?.utf8.count == 4,
                  rawBytes == nil, watts == nil,
                  issue?.isEmpty == false else {
                throw PowerObservationV5ValidationError.invalidKey(
                    "key-unavailable shape is invalid"
                )
            }
        case .valueReadFailed:
            guard dataType?.utf8.count == 4, rawBytes == nil, watts == nil,
                  issue?.isEmpty == false else {
                throw PowerObservationV5ValidationError.invalidKey(
                    "value-read failure shape is invalid"
                )
            }
        case .unsupportedType, .invalidValue:
            guard dataType?.utf8.count == 4, rawBytes != nil, watts == nil,
                  issue?.isEmpty == false else {
                throw PowerObservationV5ValidationError.invalidKey(
                    "decoded failure shape is invalid"
                )
            }
        }

        return PowerObservationV5Key(
            key: key,
            source: source,
            status: status,
            startedContinuousNanoseconds: started,
            endedContinuousNanoseconds: ended,
            dataTypeFourCC: dataType,
            rawBytesHex: rawBytes,
            decodedWatts: watts,
            ioReturn: ioReturn,
            validationIssue: issue
        )
    }

    private static func isUppercaseEvenHex(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count.isMultiple(of: 2) else { return false }
        return value.utf8.allSatisfy {
            (48...57).contains($0) || (65...70).contains($0)
        }
    }
}

// MARK: - Codable with required nullable keys

extension PowerObservationV5Connection: Codable {
    private enum CodingKeys: String, CodingKey {
        case status
        case startedContinuousNanoseconds = "startedNs"
        case endedContinuousNanoseconds = "endedNs"
        case ioReturn
        case validationIssue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            status: try container.decode(PowerObservationV5ConnectionStatus.self, forKey: .status),
            startedContinuousNanoseconds: try container.decode(UInt64.self, forKey: .startedContinuousNanoseconds),
            endedContinuousNanoseconds: try container.decode(UInt64.self, forKey: .endedContinuousNanoseconds),
            ioReturn: try container.decodeRequiredNullable(Int32.self, forKey: .ioReturn),
            validationIssue: try container.decodeRequiredNullable(String.self, forKey: .validationIssue)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(status, forKey: .status)
        try container.encode(startedContinuousNanoseconds, forKey: .startedContinuousNanoseconds)
        try container.encode(endedContinuousNanoseconds, forKey: .endedContinuousNanoseconds)
        try container.encodeRequiredNullable(ioReturn, forKey: .ioReturn)
        try container.encodeRequiredNullable(validationIssue, forKey: .validationIssue)
    }
}

extension PowerObservationV5Key: Codable {
    private enum CodingKeys: String, CodingKey {
        case key
        case source
        case status
        case startedContinuousNanoseconds = "startedNs"
        case endedContinuousNanoseconds = "endedNs"
        case dataTypeFourCC = "dataType"
        case rawBytesHex
        case decodedWatts = "watts"
        case ioReturn
        case validationIssue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            key: try container.decode(String.self, forKey: .key),
            source: try container.decode(ObservationSource.self, forKey: .source),
            status: try container.decode(PowerObservationV5KeyStatus.self, forKey: .status),
            startedContinuousNanoseconds: try container.decode(UInt64.self, forKey: .startedContinuousNanoseconds),
            endedContinuousNanoseconds: try container.decode(UInt64.self, forKey: .endedContinuousNanoseconds),
            dataTypeFourCC: try container.decodeRequiredNullable(String.self, forKey: .dataTypeFourCC),
            rawBytesHex: try container.decodeRequiredNullable(String.self, forKey: .rawBytesHex),
            decodedWatts: try container.decodeRequiredNullable(Double.self, forKey: .decodedWatts),
            ioReturn: try container.decodeRequiredNullable(Int32.self, forKey: .ioReturn),
            validationIssue: try container.decodeRequiredNullable(String.self, forKey: .validationIssue)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(key, forKey: .key)
        try container.encode(source, forKey: .source)
        try container.encode(status, forKey: .status)
        try container.encode(startedContinuousNanoseconds, forKey: .startedContinuousNanoseconds)
        try container.encode(endedContinuousNanoseconds, forKey: .endedContinuousNanoseconds)
        try container.encodeRequiredNullable(dataTypeFourCC, forKey: .dataTypeFourCC)
        try container.encodeRequiredNullable(rawBytesHex, forKey: .rawBytesHex)
        try container.encodeRequiredNullable(decodedWatts, forKey: .decodedWatts)
        try container.encodeRequiredNullable(ioReturn, forKey: .ioReturn)
        try container.encodeRequiredNullable(validationIssue, forKey: .validationIssue)
    }
}

extension PowerObservationV5Response: Codable {
    private enum CodingKeys: String, CodingKey {
        case wattsonProtocol = "_wattsonProtocol"
        case ok
        case partial
        case clientSequence
        case clock
        case error
        case connection
        case keys
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            wattsonProtocol: try container.decode(Int.self, forKey: .wattsonProtocol),
            ok: try container.decode(Bool.self, forKey: .ok),
            partial: try container.decode(Bool.self, forKey: .partial),
            clientSequence: try container.decode(UInt64.self, forKey: .clientSequence),
            clock: try container.decode(String.self, forKey: .clock),
            error: try container.decodeRequiredNullable(String.self, forKey: .error),
            connection: try container.decode(PowerObservationV5Connection.self, forKey: .connection),
            keys: try container.decode([PowerObservationV5Key].self, forKey: .keys)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(wattsonProtocol, forKey: .wattsonProtocol)
        try container.encode(ok, forKey: .ok)
        try container.encode(partial, forKey: .partial)
        try container.encode(clientSequence, forKey: .clientSequence)
        try container.encode(clock, forKey: .clock)
        try container.encodeRequiredNullable(error, forKey: .error)
        try container.encode(connection, forKey: .connection)
        try container.encode(keys, forKey: .keys)
    }
}

// MARK: - Strict JSON scalar helpers

private func strictBool(_ raw: Any?) -> Bool? {
    guard let number = raw as? NSNumber,
          CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
    return number.boolValue
}

private func strictInteger(_ raw: Any?) -> Int? {
    guard let number = raw as? NSNumber,
          CFGetTypeID(number) != CFBooleanGetTypeID(),
          jsonNumberIsIntegral(number) else { return nil }
    let value = number.int64Value
    guard value >= Int64(Int.min), value <= Int64(Int.max) else { return nil }
    return Int(value)
}

private func strictUInt64(_ raw: Any?) -> UInt64? {
    guard let number = raw as? NSNumber,
          CFGetTypeID(number) != CFBooleanGetTypeID(),
          jsonNumberIsIntegral(number) else { return nil }
    let text = number.stringValue
    guard !text.hasPrefix("-"), let value = UInt64(text) else { return nil }
    return value
}

private func jsonNumberIsIntegral(_ number: NSNumber) -> Bool {
    let type = String(cString: number.objCType)
    guard type != "f", type != "d" else { return false }
    let value = number.doubleValue
    return value.isFinite && value.rounded(.towardZero) == value
}

private func requiredNullableString(
    _ object: [String: Any],
    key: String
) throws -> String? {
    guard object.keys.contains(key) else {
        throw PowerObservationV5ValidationError.invalidKey("missing \(key)")
    }
    if object[key] is NSNull { return nil }
    guard let value = object[key] as? String else {
        throw PowerObservationV5ValidationError.invalidKey("invalid \(key)")
    }
    return value
}

private func requiredNullableInt32(
    _ object: [String: Any],
    key: String
) throws -> Int32? {
    guard object.keys.contains(key) else {
        throw PowerObservationV5ValidationError.invalidKey("missing \(key)")
    }
    if object[key] is NSNull { return nil }
    guard let value = strictInteger(object[key]),
          value >= Int(Int32.min), value <= Int(Int32.max) else {
        throw PowerObservationV5ValidationError.invalidKey("invalid \(key)")
    }
    return Int32(value)
}

private func requiredNullableFiniteDouble(
    _ object: [String: Any],
    key: String
) throws -> Double? {
    guard object.keys.contains(key) else {
        throw PowerObservationV5ValidationError.invalidKey("missing \(key)")
    }
    if object[key] is NSNull { return nil }
    guard let number = object[key] as? NSNumber,
          CFGetTypeID(number) != CFBooleanGetTypeID() else {
        throw PowerObservationV5ValidationError.invalidKey("invalid \(key)")
    }
    let value = number.doubleValue
    guard value.isFinite else {
        throw PowerObservationV5ValidationError.invalidKey("non-finite \(key)")
    }
    return value
}
