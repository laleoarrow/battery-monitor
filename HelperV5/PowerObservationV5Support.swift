import Foundation
import CoreFoundation

#if canImport(IOKit) && os(macOS)
import Darwin
import IOKit
#endif


// MARK: - Strict protocol-v5 request boundary

public struct HelperV5RequestPayload: Codable, Equatable, Sendable {
    public static let protocolVersion = 5
    public static let operation = "getPowerObservation"

    public let wattsonProtocol: Int
    public let op: String
    public let clientSequence: UInt64

    public init(clientSequence: UInt64) {
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

public enum HelperV5RequestDecodeOutcome: Equatable, Sendable {
    case request(HelperV5RequestPayload)
    case notV5
    case malformed
}

public struct HelperV5RequestDecoder {
    public static let maximumRequestBytes = 512
    private static let requiredKeys: Set<String> = [
        "_wattsonProtocol", "op", "clientSequence",
    ]

    public init() {}

    public func decode(frame: Data) -> HelperV5RequestDecodeOutcome {
        guard !frame.isEmpty, frame.count <= Self.maximumRequestBytes,
              let json = try? JSONSerialization.jsonObject(with: frame),
              let object = json as? [String: Any] else {
            return .malformed
        }
        guard object.keys.contains("_wattsonProtocol") else { return .notV5 }
        guard let protocolVersion = helperV5StrictInteger(
            object["_wattsonProtocol"]
        ) else { return .malformed }
        guard protocolVersion == HelperV5RequestPayload.protocolVersion else {
            return .notV5
        }
        guard Set(object.keys) == Self.requiredKeys,
              object["op"] as? String == HelperV5RequestPayload.operation,
              let sequence = helperV5StrictUInt64(object["clientSequence"]) else {
            return .malformed
        }
        return .request(HelperV5RequestPayload(clientSequence: sequence))
    }
}

public enum HelperV5RequestHandlingResult: Equatable, Sendable {
    case response(Data)
    case notV5
    case malformed
}

public final class HelperV5PowerObservationService {
    private let reader: HelperPowerObservationV5Reader
    private let requestDecoder: HelperV5RequestDecoder

    public init(
        reader: HelperPowerObservationV5Reader,
        requestDecoder: HelperV5RequestDecoder = HelperV5RequestDecoder()
    ) {
        self.reader = reader
        self.requestDecoder = requestDecoder
    }

    public func handle(frame: Data) -> HelperV5RequestHandlingResult {
        switch requestDecoder.decode(frame: frame) {
        case let .request(request):
            guard let line = reader.read(
                clientSequence: request.clientSequence
            ).encodedLine() else { return .malformed }
            return .response(line)
        case .notV5:
            return .notV5
        case .malformed:
            return .malformed
        }
    }
}

public enum HelperV5FixedSMCKey: String, CaseIterable, Sendable {
    case PDTR
    case PSTR
    case PPBR

    public var source: String { "smc.\(rawValue)" }
}

public enum HelperV5ConnectionStatus: String, Codable, Equatable, Sendable {
    case opened
    case serviceUnavailable
    case openFailed
    case layoutMismatch
}

public enum HelperV5KeyStatus: String, Codable, Equatable, Sendable {
    case present
    case connectionUnavailable
    case keyUnavailable
    case keyInfoFailed
    case valueReadFailed
    case unsupportedType
    case invalidValue
}

public struct HelperV5ConnectionOpenResult: Equatable, Sendable {
    public let status: HelperV5ConnectionStatus
    public let ioReturn: Int32?
    public let validationIssue: String?

    public init(
        status: HelperV5ConnectionStatus,
        ioReturn: Int32?,
        validationIssue: String?
    ) {
        self.status = status
        self.ioReturn = ioReturn
        self.validationIssue = validationIssue
    }
}

public struct HelperV5RawKeyResult: Equatable, Sendable {
    public let status: HelperV5KeyStatus
    public let dataTypeFourCC: String?
    public let rawBytes: [UInt8]?
    public let decodedWatts: Double?
    public let ioReturn: Int32?
    public let validationIssue: String?

    public init(
        status: HelperV5KeyStatus,
        dataTypeFourCC: String?,
        rawBytes: [UInt8]?,
        decodedWatts: Double?,
        ioReturn: Int32?,
        validationIssue: String?
    ) {
        self.status = status
        self.dataTypeFourCC = dataTypeFourCC
        self.rawBytes = rawBytes
        self.decodedWatts = decodedWatts
        self.ioReturn = ioReturn
        self.validationIssue = validationIssue
    }
}

public protocol HelperV5ContinuousClock: Sendable {
    func nowContinuousNanoseconds() -> UInt64
}

public protocol HelperV5SMCBackend: AnyObject {
    func open() -> HelperV5ConnectionOpenResult
    func read(_ key: HelperV5FixedSMCKey) -> HelperV5RawKeyResult
    func close()
}

public struct HelperV5ConnectionPayload: Codable, Equatable, Sendable {
    public let status: HelperV5ConnectionStatus
    public let startedNs: UInt64
    public let endedNs: UInt64
    public let ioReturn: Int32?
    public let validationIssue: String?

    public init(
        status: HelperV5ConnectionStatus,
        startedNs: UInt64,
        endedNs: UInt64,
        ioReturn: Int32?,
        validationIssue: String?
    ) {
        self.status = status
        self.startedNs = startedNs
        self.endedNs = endedNs
        self.ioReturn = ioReturn
        self.validationIssue = validationIssue
    }

    private enum CodingKeys: String, CodingKey {
        case status, startedNs, endedNs, ioReturn, validationIssue
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(status, forKey: .status)
        try container.encode(startedNs, forKey: .startedNs)
        try container.encode(endedNs, forKey: .endedNs)
        try container.encodeRequiredNullable(ioReturn, forKey: .ioReturn)
        try container.encodeRequiredNullable(validationIssue, forKey: .validationIssue)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            status: try container.decode(HelperV5ConnectionStatus.self, forKey: .status),
            startedNs: try container.decode(UInt64.self, forKey: .startedNs),
            endedNs: try container.decode(UInt64.self, forKey: .endedNs),
            ioReturn: try container.decodeRequiredNullable(Int32.self, forKey: .ioReturn),
            validationIssue: try container.decodeRequiredNullable(String.self, forKey: .validationIssue)
        )
    }
}

public struct HelperV5KeyPayload: Codable, Equatable, Sendable {
    public let key: String
    public let source: String
    public let status: HelperV5KeyStatus
    public let startedNs: UInt64
    public let endedNs: UInt64
    public let dataType: String?
    public let rawBytesHex: String?
    public let watts: Double?
    public let ioReturn: Int32?
    public let validationIssue: String?

    public init(
        key: String,
        source: String,
        status: HelperV5KeyStatus,
        startedNs: UInt64,
        endedNs: UInt64,
        dataType: String?,
        rawBytesHex: String?,
        watts: Double?,
        ioReturn: Int32?,
        validationIssue: String?
    ) {
        self.key = key
        self.source = source
        self.status = status
        self.startedNs = startedNs
        self.endedNs = endedNs
        self.dataType = dataType
        self.rawBytesHex = rawBytesHex
        self.watts = watts
        self.ioReturn = ioReturn
        self.validationIssue = validationIssue
    }

    private enum CodingKeys: String, CodingKey {
        case key, source, status, startedNs, endedNs, dataType, rawBytesHex
        case watts, ioReturn, validationIssue
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(key, forKey: .key)
        try container.encode(source, forKey: .source)
        try container.encode(status, forKey: .status)
        try container.encode(startedNs, forKey: .startedNs)
        try container.encode(endedNs, forKey: .endedNs)
        try container.encodeRequiredNullable(dataType, forKey: .dataType)
        try container.encodeRequiredNullable(rawBytesHex, forKey: .rawBytesHex)
        try container.encodeRequiredNullable(watts, forKey: .watts)
        try container.encodeRequiredNullable(ioReturn, forKey: .ioReturn)
        try container.encodeRequiredNullable(validationIssue, forKey: .validationIssue)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            key: try container.decode(String.self, forKey: .key),
            source: try container.decode(String.self, forKey: .source),
            status: try container.decode(HelperV5KeyStatus.self, forKey: .status),
            startedNs: try container.decode(UInt64.self, forKey: .startedNs),
            endedNs: try container.decode(UInt64.self, forKey: .endedNs),
            dataType: try container.decodeRequiredNullable(String.self, forKey: .dataType),
            rawBytesHex: try container.decodeRequiredNullable(String.self, forKey: .rawBytesHex),
            watts: try container.decodeRequiredNullable(Double.self, forKey: .watts),
            ioReturn: try container.decodeRequiredNullable(Int32.self, forKey: .ioReturn),
            validationIssue: try container.decodeRequiredNullable(String.self, forKey: .validationIssue)
        )
    }
}

public struct HelperV5ResponsePayload: Codable, Equatable, Sendable {
    public static let maximumResponseBytes = 4_096

    public let wattsonProtocol: Int
    public let ok: Bool
    public let partial: Bool
    public let clientSequence: UInt64
    public let clock: String
    public let error: String?
    public let connection: HelperV5ConnectionPayload
    public let keys: [HelperV5KeyPayload]

    public init(
        wattsonProtocol: Int = 5,
        ok: Bool,
        partial: Bool,
        clientSequence: UInt64,
        clock: String = "CLOCK_MONOTONIC_RAW",
        error: String?,
        connection: HelperV5ConnectionPayload,
        keys: [HelperV5KeyPayload]
    ) {
        self.wattsonProtocol = wattsonProtocol
        self.ok = ok
        self.partial = partial
        self.clientSequence = clientSequence
        self.clock = clock
        self.error = error
        self.connection = connection
        self.keys = keys
    }

    private enum CodingKeys: String, CodingKey {
        case wattsonProtocol = "_wattsonProtocol"
        case ok, partial, clientSequence, clock, error, connection, keys
    }

    public func encode(to encoder: Encoder) throws {
        guard isValidForEncoding else {
            throw EncodingError.invalidValue(
                self,
                EncodingError.Context(
                    codingPath: encoder.codingPath,
                    debugDescription: "invalid protocol-v5 response"
                )
            )
        }
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

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            wattsonProtocol: try container.decode(Int.self, forKey: .wattsonProtocol),
            ok: try container.decode(Bool.self, forKey: .ok),
            partial: try container.decode(Bool.self, forKey: .partial),
            clientSequence: try container.decode(UInt64.self, forKey: .clientSequence),
            clock: try container.decode(String.self, forKey: .clock),
            error: try container.decodeRequiredNullable(String.self, forKey: .error),
            connection: try container.decode(HelperV5ConnectionPayload.self, forKey: .connection),
            keys: try container.decode([HelperV5KeyPayload].self, forKey: .keys)
        )
        guard isValidForEncoding else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "invalid protocol-v5 response"
                )
            )
        }
    }

    public func encodedLine() -> Data? {
        guard isValidForEncoding else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard var data = try? encoder.encode(self) else { return nil }
        guard data.count < Self.maximumResponseBytes else { return nil }
        data.append(UInt8(ascii: "\n"))
        return data
    }

    private var isValidForEncoding: Bool {
        guard wattsonProtocol == 5,
              clock == "CLOCK_MONOTONIC_RAW",
              connection.endedNs >= connection.startedNs,
              keys.map(\.key) == HelperV5FixedSMCKey.allCases.map(\.rawValue),
              keys.map(\.source) == HelperV5FixedSMCKey.allCases.map(\.source),
              keys.allSatisfy({ key in
                  key.endedNs >= key.startedNs
                      && key.startedNs >= connection.startedNs
                      && key.endedNs <= connection.endedNs
                      && Self.validShape(of: key)
              }) else {
            return false
        }

        let connectionOpened = connection.status == .opened
        guard ok == connectionOpened,
              partial == (!connectionOpened || keys.contains { $0.status != .present }) else {
            return false
        }
        if connectionOpened {
            return error == nil
                && connection.ioReturn == nil
                && connection.validationIssue == nil
                && keys.allSatisfy { $0.status != .connectionUnavailable }
        }

        let issue = Self.connectionIssue(for: connection.status)
        return error == issue
            && connection.validationIssue == issue
            && keys.allSatisfy { $0.status == .connectionUnavailable }
    }

    private static func validShape(of key: HelperV5KeyPayload) -> Bool {
        let issue = keyIssue(for: key.status)
        if let rawBytesHex = key.rawBytesHex,
           !isUppercaseEvenHex(rawBytesHex) {
            return false
        }
        switch key.status {
        case .present:
            guard let dataType = key.dataType,
                  dataType.utf8.count == 4,
                  key.rawBytesHex != nil,
                  let watts = key.watts,
                  watts.isFinite,
                  key.ioReturn == nil,
                  key.validationIssue == nil else {
                return false
            }
            return key.key != HelperV5FixedSMCKey.PPBR.rawValue || watts >= 0
        case .connectionUnavailable, .keyInfoFailed:
            return key.dataType == nil
                && key.rawBytesHex == nil
                && key.watts == nil
                && key.validationIssue == issue
        case .keyUnavailable:
            return (key.dataType == nil || key.dataType?.utf8.count == 4)
                && key.rawBytesHex == nil
                && key.watts == nil
                && key.validationIssue == issue
        case .valueReadFailed:
            return key.dataType?.utf8.count == 4
                && key.rawBytesHex == nil
                && key.watts == nil
                && key.validationIssue == issue
        case .unsupportedType, .invalidValue:
            return key.dataType?.utf8.count == 4
                && key.rawBytesHex != nil
                && key.watts == nil
                && key.validationIssue == issue
        }
    }

    fileprivate static func connectionIssue(
        for status: HelperV5ConnectionStatus
    ) -> String? {
        switch status {
        case .opened: nil
        case .serviceUnavailable: "service unavailable"
        case .openFailed: "open failed"
        case .layoutMismatch: "layout mismatch"
        }
    }

    fileprivate static func keyIssue(for status: HelperV5KeyStatus) -> String? {
        switch status {
        case .present: nil
        case .connectionUnavailable: "connection unavailable"
        case .keyUnavailable: "key unavailable"
        case .keyInfoFailed: "key info failed"
        case .valueReadFailed: "value read failed"
        case .unsupportedType: "unsupported type"
        case .invalidValue: "invalid value"
        }
    }

    private static func isUppercaseEvenHex(_ value: String) -> Bool {
        guard !value.isEmpty,
              value.utf8.count <= 64,
              value.utf8.count.isMultiple(of: 2) else {
            return false
        }
        return value.utf8.allSatisfy {
            (48...57).contains($0) || (65...70).contains($0)
        }
    }
}

public final class HelperPowerObservationV5Reader {
    private let backend: any HelperV5SMCBackend
    private let clock: any HelperV5ContinuousClock

    public init(
        backend: any HelperV5SMCBackend,
        clock: any HelperV5ContinuousClock
    ) {
        self.backend = backend
        self.clock = clock
    }

    public func read(clientSequence: UInt64) -> HelperV5ResponsePayload {
        let connectionStarted = clock.nowContinuousNanoseconds()
        let opened = backend.open()

        guard opened.status == .opened else {
            backend.close()
            let ended = max(connectionStarted, clock.nowContinuousNanoseconds())
            let issue = HelperV5ResponsePayload.connectionIssue(
                for: opened.status
            )!
            let keys = HelperV5FixedSMCKey.allCases.map { key in
                HelperV5KeyPayload(
                    key: key.rawValue,
                    source: key.source,
                    status: .connectionUnavailable,
                    startedNs: ended,
                    endedNs: ended,
                    dataType: nil,
                    rawBytesHex: nil,
                    watts: nil,
                    ioReturn: opened.ioReturn,
                    validationIssue: HelperV5ResponsePayload.keyIssue(
                        for: .connectionUnavailable
                    )
                )
            }
            return HelperV5ResponsePayload(
                ok: false,
                partial: true,
                clientSequence: clientSequence,
                error: issue,
                connection: HelperV5ConnectionPayload(
                    status: opened.status,
                    startedNs: connectionStarted,
                    endedNs: ended,
                    ioReturn: opened.ioReturn,
                    validationIssue: issue
                ),
                keys: keys
            )
        }

        var payloads: [HelperV5KeyPayload] = []
        for key in HelperV5FixedSMCKey.allCases {
            let started = clock.nowContinuousNanoseconds()
            let result = Self.normalized(backend.read(key), for: key)
            let ended = max(started, clock.nowContinuousNanoseconds())
            payloads.append(HelperV5KeyPayload(
                key: key.rawValue,
                source: key.source,
                status: result.status,
                startedNs: started,
                endedNs: ended,
                dataType: result.dataTypeFourCC,
                rawBytesHex: result.rawBytes.map(Self.hex),
                watts: result.decodedWatts,
                ioReturn: result.ioReturn,
                validationIssue: HelperV5ResponsePayload.keyIssue(
                    for: result.status
                )
            ))
        }
        backend.close()
        let connectionEnded = max(connectionStarted, clock.nowContinuousNanoseconds())
        return HelperV5ResponsePayload(
            ok: true,
            partial: payloads.contains { $0.status != .present },
            clientSequence: clientSequence,
            error: nil,
            connection: HelperV5ConnectionPayload(
                status: .opened,
                startedNs: connectionStarted,
                endedNs: connectionEnded,
                ioReturn: opened.ioReturn,
                validationIssue: nil
            ),
            keys: payloads
        )
    }

    private static func normalized(
        _ result: HelperV5RawKeyResult,
        for key: HelperV5FixedSMCKey
    ) -> HelperV5RawKeyResult {
        func metadataIsFourCC(_ value: String?) -> Bool {
            value == nil || value!.utf8.count == 4
        }
        switch result.status {
        case .present:
            guard let dataType = result.dataTypeFourCC,
                  dataType.utf8.count == 4,
                  let rawBytes = result.rawBytes,
                  !rawBytes.isEmpty,
                  rawBytes.count <= 32,
                  let watts = result.decodedWatts,
                  watts.isFinite,
                  key != .PPBR || watts >= 0,
                  result.ioReturn == nil,
                  result.validationIssue == nil else {
                if let rawBytes = result.rawBytes,
                   !rawBytes.isEmpty,
                   rawBytes.count <= 32,
                   result.dataTypeFourCC?.utf8.count == 4 {
                    return HelperV5RawKeyResult(
                        status: .invalidValue,
                        dataTypeFourCC: result.dataTypeFourCC,
                        rawBytes: rawBytes,
                        decodedWatts: nil,
                        ioReturn: result.ioReturn,
                        validationIssue: "SMC backend returned an invalid present value"
                    )
                }
                return HelperV5RawKeyResult(
                    status: .keyInfoFailed,
                    dataTypeFourCC: nil,
                    rawBytes: nil,
                    decodedWatts: nil,
                    ioReturn: result.ioReturn,
                    validationIssue: "SMC backend returned an invalid present shape"
                )
            }
            return result
        case .connectionUnavailable:
            return HelperV5RawKeyResult(
                status: .keyInfoFailed,
                dataTypeFourCC: nil,
                rawBytes: nil,
                decodedWatts: nil,
                ioReturn: result.ioReturn,
                validationIssue: "connection lost while reading key"
            )
        case .keyInfoFailed:
            guard result.dataTypeFourCC == nil,
                  result.rawBytes == nil,
                  result.decodedWatts == nil,
                  result.validationIssue?.isEmpty == false else {
                return HelperV5RawKeyResult(
                    status: .keyInfoFailed,
                    dataTypeFourCC: nil,
                    rawBytes: nil,
                    decodedWatts: nil,
                    ioReturn: result.ioReturn,
                    validationIssue: "SMC backend returned an invalid unavailable shape"
                )
            }
            return result
        case .keyUnavailable:
            guard metadataIsFourCC(result.dataTypeFourCC),
                  result.rawBytes == nil,
                  result.decodedWatts == nil,
                  result.validationIssue?.isEmpty == false else {
                return HelperV5RawKeyResult(
                    status: .keyInfoFailed,
                    dataTypeFourCC: nil,
                    rawBytes: nil,
                    decodedWatts: nil,
                    ioReturn: result.ioReturn,
                    validationIssue: "SMC backend returned an invalid key-unavailable shape"
                )
            }
            return result
        case .valueReadFailed:
            guard result.dataTypeFourCC?.utf8.count == 4,
                  result.rawBytes == nil,
                  result.decodedWatts == nil,
                  result.validationIssue?.isEmpty == false else {
                return HelperV5RawKeyResult(
                    status: .keyInfoFailed,
                    dataTypeFourCC: nil,
                    rawBytes: nil,
                    decodedWatts: nil,
                    ioReturn: result.ioReturn,
                    validationIssue: "SMC backend returned an invalid value-read shape"
                )
            }
            return result
        case .unsupportedType, .invalidValue:
            guard result.decodedWatts == nil,
                  result.dataTypeFourCC?.utf8.count == 4,
                  let rawBytes = result.rawBytes,
                  !rawBytes.isEmpty,
                  rawBytes.count <= 32,
                  result.validationIssue?.isEmpty == false else {
                return HelperV5RawKeyResult(
                    status: .keyInfoFailed,
                    dataTypeFourCC: nil,
                    rawBytes: nil,
                    decodedWatts: nil,
                    ioReturn: result.ioReturn,
                    validationIssue: "SMC backend returned an invalid decoded-failure shape"
                )
            }
            return result
        }
    }

    private static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02X", $0) }.joined()
    }
}

public struct SystemHelperV5ContinuousClock: HelperV5ContinuousClock {
    public init() {}

    public func nowContinuousNanoseconds() -> UInt64 {
        #if os(macOS)
        return clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)
        #else
        return DispatchTime.now().uptimeNanoseconds
        #endif
    }
}

#if canImport(IOKit) && os(macOS)

private typealias HelperV5SMCBytes = (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
)
private struct HelperV5SMCVersion {
    var major: UInt8 = 0; var minor: UInt8 = 0; var build: UInt8 = 0
    var reserved: UInt8 = 0; var release: UInt16 = 0
}
private struct HelperV5SMCPLimitData {
    var version: UInt16 = 0; var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0; var gpuPLimit: UInt32 = 0; var memPLimit: UInt32 = 0
}
private struct HelperV5SMCKeyInfoData {
    var dataSize: UInt32 = 0; var dataType: UInt32 = 0; var dataAttributes: UInt8 = 0
}
private struct HelperV5SMCKeyData {
    var key: UInt32 = 0
    var version = HelperV5SMCVersion()
    var pLimitData = HelperV5SMCPLimitData()
    var keyInfo = HelperV5SMCKeyInfoData()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: HelperV5SMCBytes = (
        0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,
        0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0
    )
}

public final class SystemHelperV5SMCBackend: HelperV5SMCBackend {
    private static let selector: UInt32 = 2
    private static let readBytesCommand: UInt8 = 5
    private static let readKeyInfoCommand: UInt8 = 9
    private static let floatType: UInt32 = 0x666c_7420
    private static let sp78Type: UInt32 = 0x7370_3738
    private static let sp96Type: UInt32 = 0x7370_3936

    private var connection: io_connect_t = 0

    public init() {}

    public func open() -> HelperV5ConnectionOpenResult {
        guard MemoryLayout<HelperV5SMCKeyData>.size == 80 else {
            return HelperV5ConnectionOpenResult(
                status: .layoutMismatch,
                ioReturn: nil,
                validationIssue: "SMC ABI layout mismatch"
            )
        }
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSMC")
        )
        guard service != 0 else {
            return HelperV5ConnectionOpenResult(
                status: .serviceUnavailable,
                ioReturn: nil,
                validationIssue: "AppleSMC service unavailable"
            )
        }
        defer { IOObjectRelease(service) }
        var opened: io_connect_t = 0
        let result = IOServiceOpen(service, mach_task_self_, 0, &opened)
        guard result == kIOReturnSuccess else {
            return HelperV5ConnectionOpenResult(
                status: .openFailed,
                ioReturn: Int32(result),
                validationIssue: "AppleSMC open failed"
            )
        }
        connection = opened
        return HelperV5ConnectionOpenResult(status: .opened, ioReturn: nil, validationIssue: nil)
    }

    public func read(_ key: HelperV5FixedSMCKey) -> HelperV5RawKeyResult {
        guard connection != 0 else {
            return HelperV5RawKeyResult(
                status: .connectionUnavailable,
                dataTypeFourCC: nil,
                rawBytes: nil,
                decodedWatts: nil,
                ioReturn: nil,
                validationIssue: "AppleSMC connection unavailable"
            )
        }
        guard let keyCode = Self.fourCC(key.rawValue) else {
            return HelperV5RawKeyResult(
                status: .keyUnavailable,
                dataTypeFourCC: nil,
                rawBytes: nil,
                decodedWatts: nil,
                ioReturn: nil,
                validationIssue: "fixed key encoding failed"
            )
        }

        var info = HelperV5SMCKeyData()
        info.key = keyCode
        info.data8 = Self.readKeyInfoCommand
        let infoCall = call(info)
        guard infoCall.ioReturn == kIOReturnSuccess, let infoReply = infoCall.reply else {
            return HelperV5RawKeyResult(
                status: .keyInfoFailed,
                dataTypeFourCC: nil,
                rawBytes: nil,
                decodedWatts: nil,
                ioReturn: Int32(infoCall.ioReturn),
                validationIssue: "SMC key info failed"
            )
        }
        let size = Int(infoReply.keyInfo.dataSize)
        guard size > 0, size <= 32 else {
            return HelperV5RawKeyResult(
                status: .keyUnavailable,
                dataTypeFourCC: Self.fourCCString(infoReply.keyInfo.dataType),
                rawBytes: nil,
                decodedWatts: nil,
                ioReturn: nil,
                validationIssue: "SMC key size unavailable"
            )
        }

        var request = HelperV5SMCKeyData()
        request.key = keyCode
        request.keyInfo.dataSize = infoReply.keyInfo.dataSize
        request.data8 = Self.readBytesCommand
        let valueCall = call(request)
        guard valueCall.ioReturn == kIOReturnSuccess, let valueReply = valueCall.reply else {
            return HelperV5RawKeyResult(
                status: .valueReadFailed,
                dataTypeFourCC: Self.fourCCString(infoReply.keyInfo.dataType),
                rawBytes: nil,
                decodedWatts: nil,
                ioReturn: Int32(valueCall.ioReturn),
                validationIssue: "SMC value read failed"
            )
        }
        let bytes = withUnsafeBytes(of: valueReply.bytes) { Array($0.prefix(size)) }
        let dataType = infoReply.keyInfo.dataType
        guard Self.supportedType(dataType, byteCount: bytes.count) else {
            return HelperV5RawKeyResult(
                status: .unsupportedType,
                dataTypeFourCC: Self.fourCCString(dataType),
                rawBytes: bytes,
                decodedWatts: nil,
                ioReturn: nil,
                validationIssue: "SMC data type unsupported"
            )
        }
        guard let watts = Self.decodeWatts(dataType: dataType, bytes: bytes),
              key != .PPBR || watts >= 0 else {
            return HelperV5RawKeyResult(
                status: .invalidValue,
                dataTypeFourCC: Self.fourCCString(dataType),
                rawBytes: bytes,
                decodedWatts: nil,
                ioReturn: nil,
                validationIssue: key == .PPBR
                    ? "PPBR discharge magnitude is negative"
                    : "SMC watts invalid"
            )
        }
        return HelperV5RawKeyResult(
            status: .present,
            dataTypeFourCC: Self.fourCCString(dataType),
            rawBytes: bytes,
            decodedWatts: watts,
            ioReturn: nil,
            validationIssue: nil
        )
    }

    public func close() {
        if connection != 0 {
            IOServiceClose(connection)
            connection = 0
        }
    }

    private func call(_ request: HelperV5SMCKeyData) -> (ioReturn: kern_return_t, reply: HelperV5SMCKeyData?) {
        var request = request
        var reply = HelperV5SMCKeyData()
        var replySize = MemoryLayout<HelperV5SMCKeyData>.size
        let result = IOConnectCallStructMethod(
            connection,
            Self.selector,
            &request,
            MemoryLayout<HelperV5SMCKeyData>.size,
            &reply,
            &replySize
        )
        guard result == kIOReturnSuccess,
              replySize == MemoryLayout<HelperV5SMCKeyData>.size,
              reply.result == 0 else {
            return (result, nil)
        }
        return (result, reply)
    }

    private static func supportedType(_ type: UInt32, byteCount: Int) -> Bool {
        (type == floatType && byteCount == 4)
            || ((type == sp78Type || type == sp96Type) && byteCount == 2)
    }

    private static func decodeWatts(dataType: UInt32, bytes: [UInt8]) -> Double? {
        switch dataType {
        case floatType where bytes.count == 4:
            let bits = UInt32(bytes[0])
                | UInt32(bytes[1]) << 8
                | UInt32(bytes[2]) << 16
                | UInt32(bytes[3]) << 24
            let value = Double(Float(bitPattern: bits))
            return value.isFinite ? value : nil
        case sp78Type where bytes.count == 2:
            let bits = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
            return Double(Int16(bitPattern: bits)) / 256
        case sp96Type where bytes.count == 2:
            let bits = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
            return Double(Int16(bitPattern: bits)) / 64
        default:
            return nil
        }
    }

    private static func fourCC(_ value: String) -> UInt32? {
        let bytes = Array(value.utf8)
        guard bytes.count == 4 else { return nil }
        return bytes.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private static func fourCCString(_ value: UInt32) -> String {
        let bytes: [UInt8] = [
            UInt8((value >> 24) & 0xff), UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff), UInt8(value & 0xff),
        ]
        return String(bytes: bytes, encoding: .ascii) ?? "????"
    }
}

#else

public final class SystemHelperV5SMCBackend: HelperV5SMCBackend {
    public init() {}
    public func open() -> HelperV5ConnectionOpenResult {
        HelperV5ConnectionOpenResult(
            status: .serviceUnavailable,
            ioReturn: nil,
            validationIssue: "AppleSMC is unavailable on this platform"
        )
    }
    public func read(_ key: HelperV5FixedSMCKey) -> HelperV5RawKeyResult {
        HelperV5RawKeyResult(
            status: .connectionUnavailable,
            dataTypeFourCC: nil,
            rawBytes: nil,
            decodedWatts: nil,
            ioReturn: nil,
            validationIssue: "AppleSMC is unavailable on this platform"
        )
    }
    public func close() {}
}

#endif

private func helperV5StrictInteger(_ raw: Any?) -> Int? {
    guard let number = raw as? NSNumber,
          CFGetTypeID(number) != CFBooleanGetTypeID(),
          helperV5JSONNumberIsIntegral(number) else { return nil }
    let value = number.int64Value
    guard value >= Int64(Int.min), value <= Int64(Int.max) else { return nil }
    return Int(value)
}

private func helperV5StrictUInt64(_ raw: Any?) -> UInt64? {
    guard let number = raw as? NSNumber,
          CFGetTypeID(number) != CFBooleanGetTypeID(),
          helperV5JSONNumberIsIntegral(number) else { return nil }
    let text = number.stringValue
    guard !text.hasPrefix("-"), let value = UInt64(text) else { return nil }
    return value
}

private func helperV5JSONNumberIsIntegral(_ number: NSNumber) -> Bool {
    let type = String(cString: number.objCType)
    guard type != "f", type != "d" else { return false }
    let value = number.doubleValue
    return value.isFinite && value.rounded(.towardZero) == value
}

private extension KeyedDecodingContainer {
    func decodeRequiredNullable<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T? {
        guard contains(key) else {
            throw DecodingError.keyNotFound(
                key,
                DecodingError.Context(codingPath: codingPath, debugDescription: "Required key is missing")
            )
        }
        if try decodeNil(forKey: key) { return nil }
        return try decode(type, forKey: key)
    }
}

private extension KeyedEncodingContainer {
    mutating func encodeRequiredNullable<T: Encodable>(_ value: T?, forKey key: Key) throws {
        if let value { try encode(value, forKey: key) }
        else { try encodeNil(forKey: key) }
    }
}
