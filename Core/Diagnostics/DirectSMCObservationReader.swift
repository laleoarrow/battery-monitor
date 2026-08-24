#if DEBUG

import Foundation

#if canImport(IOKit) && os(macOS)
import IOKit
import Darwin
#endif

enum DirectSMCConnectionOpenResult {
    case opened(any DirectSMCConnectionReading)
    case serviceUnavailable
    case openFailed(ioReturn: Int32?)
}

protocol DirectSMCConnectionOpening {
    func openConnection() -> DirectSMCConnectionOpenResult
}

protocol DirectSMCConnectionReading: AnyObject {
    func readKey(_ key: String) -> DirectSMCRawKeyResult
    func close()
}

struct DirectSMCRawKeyResult: Equatable, Sendable {
    let status: SMCKeyStatus
    let dataTypeFourCC: String?
    let rawBytes: [UInt8]?
    let decodedWatts: Double?
    let ioReturn: Int32?
    let validationIssue: String?

    static func unavailable(
        issue: String,
        ioReturn: Int32? = nil
    ) -> Self {
        Self(
            status: .keyUnavailable,
            dataTypeFourCC: nil,
            rawBytes: nil,
            decodedWatts: nil,
            ioReturn: ioReturn,
            validationIssue: issue
        )
    }
}

enum DirectSMCValueDecoder {
    private static let supportedTypes = ["flt ", "sp78", "sp96"]

    static func decodeWatts(
        dataTypeFourCC: String,
        rawBytes: [UInt8]
    ) -> Double? {
        let value: Double?
        switch dataTypeFourCC {
        case "flt " where rawBytes.count == 4:
            let bits = UInt32(rawBytes[0])
                | UInt32(rawBytes[1]) << 8
                | UInt32(rawBytes[2]) << 16
                | UInt32(rawBytes[3]) << 24
            value = Double(Float(bitPattern: bits))
        case "sp78" where rawBytes.count == 2:
            value = signedFixedPoint(
                rawBytes,
                fractionalBits: 8
            )
        case "sp96" where rawBytes.count == 2:
            value = signedFixedPoint(
                rawBytes,
                fractionalBits: 6
            )
        default:
            value = nil
        }
        guard let value, value.isFinite else { return nil }
        return value
    }

    static func supports(_ dataTypeFourCC: String) -> Bool {
        supportedTypes.contains(dataTypeFourCC)
    }

    private static func signedFixedPoint(
        _ bytes: [UInt8],
        fractionalBits: Int
    ) -> Double? {
        guard bytes.count == 2 else { return nil }
        let bits = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
        return Double(Int16(bitPattern: bits))
            / Double(1 << fractionalBits)
    }
}

final class DirectSMCObservationReader:
    DirectSMCObservationReading
{
    static let fixedKeyOrder = ["PDTR", "PSTR", "PPBR"]

    private let backend: any DirectSMCConnectionOpening
    private let clock: any ContinuousNanosecondClockReading

    init(
        backend: any DirectSMCConnectionOpening =
            SystemDirectSMCConnectionOpener(),
        clock: any ContinuousNanosecondClockReading =
            SystemContinuousNanosecondClock()
    ) {
        self.backend = backend
        self.clock = clock
    }

    func readObservation() throws -> SMCObservation {
        let connectionStarted = clock.nowContinuousNanoseconds()
        switch backend.openConnection() {
        case .serviceUnavailable:
            let ended = max(
                connectionStarted,
                clock.nowContinuousNanoseconds()
            )
            let capture = try MonotonicInterval(
                startedContinuousNanoseconds: connectionStarted,
                endedContinuousNanoseconds: ended
            )
            return try SMCObservation(
                connectionStatus: .serviceUnavailable,
                connectionCapture: capture,
                keys: Self.fixedKeyOrder.map {
                    unavailableKey(
                        $0,
                        capture: capture,
                        issue: "AppleSMC service unavailable",
                        ioReturn: nil
                    )
                }
            )

        case let .openFailed(ioReturn):
            let ended = max(
                connectionStarted,
                clock.nowContinuousNanoseconds()
            )
            let capture = try MonotonicInterval(
                startedContinuousNanoseconds: connectionStarted,
                endedContinuousNanoseconds: ended
            )
            return try SMCObservation(
                connectionStatus: .openFailed,
                connectionCapture: capture,
                keys: Self.fixedKeyOrder.map {
                    unavailableKey(
                        $0,
                        capture: capture,
                        issue: "AppleSMC connection open failed",
                        ioReturn: ioReturn
                    )
                }
            )

        case let .opened(connection):
            defer { connection.close() }
            var observations: [SMCKeyObservation] = []
            observations.reserveCapacity(Self.fixedKeyOrder.count)
            for key in Self.fixedKeyOrder {
                let started = clock.nowContinuousNanoseconds()
                let result = connection.readKey(key)
                let ended = max(
                    started,
                    clock.nowContinuousNanoseconds()
                )
                let capture = try MonotonicInterval(
                    startedContinuousNanoseconds: started,
                    endedContinuousNanoseconds: ended
                )
                observations.append(
                    SMCKeyObservation(
                        key: key,
                        source: source(for: key),
                        status: result.status,
                        capture: capture,
                        dataTypeFourCC: result.dataTypeFourCC,
                        rawBytesHex: result.rawBytes.map(hexString),
                        decodedWatts: result.decodedWatts,
                        ioReturn: result.ioReturn,
                        validationIssue: result.validationIssue
                    )
                )
            }
            let connectionEnded = max(
                connectionStarted,
                clock.nowContinuousNanoseconds()
            )
            return try SMCObservation(
                connectionStatus: .opened,
                connectionCapture: try MonotonicInterval(
                    startedContinuousNanoseconds: connectionStarted,
                    endedContinuousNanoseconds: connectionEnded
                ),
                keys: observations
            )
        }
    }

    private func unavailableKey(
        _ key: String,
        capture: MonotonicInterval,
        issue: String,
        ioReturn: Int32?
    ) -> SMCKeyObservation {
        SMCKeyObservation(
            key: key,
            source: source(for: key),
            status: .keyUnavailable,
            capture: capture,
            dataTypeFourCC: nil,
            rawBytesHex: nil,
            decodedWatts: nil,
            ioReturn: ioReturn,
            validationIssue: issue
        )
    }

    private func source(for key: String) -> ObservationSource {
        switch key {
        case "PDTR": return .smcPDTR
        case "PSTR": return .smcPSTR
        case "PPBR": return .smcPPBR
        default: preconditionFailure("unexpected fixed SMC key")
        }
    }

    private func hexString(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02X", $0) }.joined()
    }
}

#if canImport(IOKit) && os(macOS)

private typealias DirectSMCBytes = (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
)

private struct DirectSMCVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

private struct DirectSMCPLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

private struct DirectSMCKeyInfoData {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
}

private struct DirectSMCKeyData {
    var key: UInt32 = 0
    var version = DirectSMCVersion()
    var pLimitData = DirectSMCPLimitData()
    var keyInfo = DirectSMCKeyInfoData()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: DirectSMCBytes = (
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0
    )
}

struct SystemDirectSMCConnectionOpener:
    DirectSMCConnectionOpening
{
    func openConnection() -> DirectSMCConnectionOpenResult {
        guard MemoryLayout<DirectSMCKeyData>.size == 80 else {
            return .openFailed(ioReturn: nil)
        }
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSMC")
        )
        guard service != IO_OBJECT_NULL else {
            return .serviceUnavailable
        }
        defer { IOObjectRelease(service) }

        var connection: io_connect_t = 0
        let result = IOServiceOpen(
            service,
            mach_task_self_,
            0,
            &connection
        )
        guard result == kIOReturnSuccess else {
            return .openFailed(ioReturn: Int32(result))
        }
        return .opened(
            SystemDirectSMCConnection(connection: connection)
        )
    }
}

private final class SystemDirectSMCConnection:
    DirectSMCConnectionReading
{
    private static let userClientSelector: UInt32 = 2
    private static let readBytesCommand: UInt8 = 5
    private static let readKeyInfoCommand: UInt8 = 9
    private var connection: io_connect_t
    private var isClosed = false

    init(connection: io_connect_t) {
        self.connection = connection
    }

    deinit { close() }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        IOServiceClose(connection)
        connection = 0
    }

    func readKey(_ key: String) -> DirectSMCRawKeyResult {
        guard !isClosed,
              let packedKey = fourCC(key) else {
            return .unavailable(issue: "invalid or closed SMC connection")
        }

        var infoRequest = DirectSMCKeyData()
        infoRequest.key = packedKey
        infoRequest.data8 = Self.readKeyInfoCommand
        let infoCall = call(infoRequest)
        guard infoCall.ioReturn == kIOReturnSuccess,
              let infoReply = infoCall.reply else {
            return DirectSMCRawKeyResult(
                status: .keyInfoFailed,
                dataTypeFourCC: nil,
                rawBytes: nil,
                decodedWatts: nil,
                ioReturn: Int32(infoCall.ioReturn),
                validationIssue: "SMC key-info read failed"
            )
        }

        let size = Int(infoReply.keyInfo.dataSize)
        guard size > 0, size <= 32 else {
            return DirectSMCRawKeyResult(
                status: .invalidValue,
                dataTypeFourCC: fourCCString(
                    infoReply.keyInfo.dataType
                ),
                rawBytes: nil,
                decodedWatts: nil,
                ioReturn: nil,
                validationIssue: "SMC key size is invalid"
            )
        }

        var valueRequest = DirectSMCKeyData()
        valueRequest.key = packedKey
        valueRequest.keyInfo.dataSize =
            infoReply.keyInfo.dataSize
        valueRequest.data8 = Self.readBytesCommand
        let valueCall = call(valueRequest)
        guard valueCall.ioReturn == kIOReturnSuccess,
              let valueReply = valueCall.reply else {
            return DirectSMCRawKeyResult(
                status: .valueReadFailed,
                dataTypeFourCC: fourCCString(
                    infoReply.keyInfo.dataType
                ),
                rawBytes: nil,
                decodedWatts: nil,
                ioReturn: Int32(valueCall.ioReturn),
                validationIssue: "SMC value read failed"
            )
        }

        let bytes = withUnsafeBytes(of: valueReply.bytes) {
            Array($0.prefix(size))
        }
        let type = fourCCString(infoReply.keyInfo.dataType)
        guard let decoded = DirectSMCValueDecoder.decodeWatts(
            dataTypeFourCC: type,
            rawBytes: bytes
        ) else {
            let supported = DirectSMCValueDecoder.supports(type)
            return DirectSMCRawKeyResult(
                status: supported ? .invalidValue : .unsupportedType,
                dataTypeFourCC: type,
                rawBytes: bytes,
                decodedWatts: nil,
                ioReturn: nil,
                validationIssue: supported
                    ? "SMC watts are invalid"
                    : "SMC data type is unsupported"
            )
        }
        if key == "PPBR", decoded < 0 {
            return DirectSMCRawKeyResult(
                status: .invalidValue,
                dataTypeFourCC: type,
                rawBytes: bytes,
                decodedWatts: nil,
                ioReturn: nil,
                validationIssue:
                    "PPBR is not a non-negative discharge magnitude"
            )
        }
        return DirectSMCRawKeyResult(
            status: .present,
            dataTypeFourCC: type,
            rawBytes: bytes,
            decodedWatts: decoded,
            ioReturn: nil,
            validationIssue: nil
        )
    }

    private func call(
        _ request: DirectSMCKeyData
    ) -> (ioReturn: kern_return_t, reply: DirectSMCKeyData?) {
        var request = request
        var reply = DirectSMCKeyData()
        var replySize = MemoryLayout<DirectSMCKeyData>.size
        let result = IOConnectCallStructMethod(
            connection,
            Self.userClientSelector,
            &request,
            MemoryLayout<DirectSMCKeyData>.size,
            &reply,
            &replySize
        )
        guard result == kIOReturnSuccess,
              replySize == MemoryLayout<DirectSMCKeyData>.size,
              reply.result == 0 else {
            return (result, nil)
        }
        return (result, reply)
    }

    private func fourCC(_ key: String) -> UInt32? {
        let bytes = Array(key.utf8)
        guard bytes.count == 4 else { return nil }
        return bytes.reduce(UInt32(0)) {
            ($0 << 8) | UInt32($1)
        }
    }

    private func fourCCString(_ value: UInt32) -> String {
        let bytes: [UInt8] = [
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff),
        ]
        return String(bytes: bytes, encoding: .ascii) ?? "????"
    }
}

#else

struct SystemDirectSMCConnectionOpener:
    DirectSMCConnectionOpening
{
    func openConnection() -> DirectSMCConnectionOpenResult {
        .serviceUnavailable
    }
}

#endif

#endif
