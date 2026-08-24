import Foundation
import CoreFoundation

#if os(macOS)
import Darwin
#endif

enum PowerObservationFrameExchange: Equatable, Sendable {
    case frame(Data)
    case incompleteFrame(Data)
    case noResponse
}

protocol PowerObservationFrameTransport: Sendable {
    func exchange(
        request: Data,
        maximumResponseBytes: Int,
        timeoutSeconds: Int
    ) -> PowerObservationFrameExchange
}

enum PowerObservationFetchFailure: Equatable, Sendable {
    case invalidRequestEncoding
    case invalidV5(PowerObservationV5DecodeFailure)
    case truncatedV5Frame
    case legacyV4Unavailable
    case legacyV4Malformed
}

enum HelperPowerObservationFetchResult: Equatable, Sendable {
    case v5(PowerObservationV5Response)
    case legacyV4(HelperClient.LivePower)
    case failed(PowerObservationFetchFailure)

    var usesLegacyFallback: Bool {
        if case .legacyV4 = self { return true }
        return false
    }
}

struct PowerObservationV5Client: Sendable {
    static let v4MaximumResponseBytes = 512

    let transport: any PowerObservationFrameTransport
    let timeoutSeconds: Int

    init(
        transport: any PowerObservationFrameTransport,
        timeoutSeconds: Int = 2
    ) {
        self.transport = transport
        self.timeoutSeconds = timeoutSeconds
    }

    func fetch(clientSequence: UInt64) -> HelperPowerObservationFetchResult {
        guard let v5Request = encodeLine(PowerObservationV5Request(
            clientSequence: clientSequence
        )) else {
            return .failed(.invalidRequestEncoding)
        }

        switch transport.exchange(
            request: v5Request,
            maximumResponseBytes: PowerObservationV5Decoder.maximumFrameBytes,
            timeoutSeconds: timeoutSeconds
        ) {
        case .noResponse:
            return fetchLegacyV4()
        case .incompleteFrame:
            // Once a v5 request has received any response bytes, timeout,
            // EOF, or the frame bound is a truncated claimed-v5 response.
            // Retrying v4 would mix two independent acquisitions.
            return .failed(.truncatedV5Frame)
        case let .frame(frame):
            // The transport strips the newline. The 4096-byte wire bound
            // includes that newline, so a complete body must be smaller.
            guard frame.count < PowerObservationV5Decoder.maximumFrameBytes else {
                return .failed(.invalidV5(.frameTooLarge))
            }
            switch PowerObservationV5Decoder().decode(
                frame: frame,
                expectedClientSequence: clientSequence
            ) {
            case let .response(response):
                // A valid v5 response, including an explicit failure or a
                // partial three-key observation, is authoritative for this
                // request. Never splice it with a v4 fallback.
                return .v5(response)
            case .legacyOrUnsupportedProtocol:
                return fetchLegacyV4()
            case let .malformed(failure):
                // Receiving bytes that claim protocol v5 but fail strict
                // validation is not evidence that the helper is old. Mixing a
                // second response would hide truncation or corruption.
                return .failed(.invalidV5(failure))
            }
        }
    }

    private func fetchLegacyV4() -> HelperPowerObservationFetchResult {
        let requestObject: [String: Any] = [
            "_wattsonProtocol": 4,
            "op": "getPower",
        ]
        guard JSONSerialization.isValidJSONObject(requestObject),
              var request = try? JSONSerialization.data(
                  withJSONObject: requestObject,
                  options: [.sortedKeys]
              ) else {
            return .failed(.invalidRequestEncoding)
        }
        request.append(UInt8(ascii: "\n"))

        switch transport.exchange(
            request: request,
            maximumResponseBytes: Self.v4MaximumResponseBytes,
            timeoutSeconds: timeoutSeconds
        ) {
        case .noResponse:
            return .failed(.legacyV4Unavailable)
        case .incompleteFrame:
            return .failed(.legacyV4Malformed)
        case let .frame(frame):
            guard let livePower = LegacyPowerV4Decoder().decode(frame: frame) else {
                return .failed(.legacyV4Malformed)
            }
            return .legacyV4(livePower)
        }
    }

    private func encodeLine<T: Encodable>(_ value: T) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard var data = try? encoder.encode(value) else { return nil }
        data.append(UInt8(ascii: "\n"))
        return data
    }
}

private struct LegacyPowerV4Decoder {
    func decode(frame: Data) -> HelperClient.LivePower? {
        guard frame.count <= PowerObservationV5Client.v4MaximumResponseBytes,
              let json = try? JSONSerialization.jsonObject(with: frame),
              let object = json as? [String: Any],
              legacyStrictBool(object["ok"]) == true else {
            return nil
        }
        let allowed: Set<String> = ["ok", "adapterW", "systemW"]
        guard Set(object.keys).isSubset(of: allowed) else { return nil }

        var invalid = false
        func watts(_ name: String) -> Double? {
            guard object.keys.contains(name) else { return nil }
            guard let number = object[name] as? NSNumber,
                  CFGetTypeID(number) != CFBooleanGetTypeID() else {
                invalid = true
                return nil
            }
            let value = number.doubleValue
            guard value.isFinite, (0...1_000).contains(value) else {
                invalid = true
                return nil
            }
            return value
        }

        let adapter = watts("adapterW")
        let system = watts("systemW")
        guard !invalid, adapter != nil || system != nil else { return nil }
        return HelperClient.LivePower(adapterW: adapter, systemW: system)
    }
}

private func legacyStrictBool(_ raw: Any?) -> Bool? {
    guard let number = raw as? NSNumber,
          CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
    return number.boolValue
}

#if os(macOS)

struct UnixSocketPowerObservationTransport: PowerObservationFrameTransport {
    let socketPath: String

    init(socketPath: String = HelperClient.socketPath) {
        self.socketPath = socketPath
    }

    func exchange(
        request: Data,
        maximumResponseBytes: Int,
        timeoutSeconds: Int
    ) -> PowerObservationFrameExchange {
        guard maximumResponseBytes > 0,
              (1...15).contains(timeoutSeconds) else { return .noResponse }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return .noResponse }
        defer { close(fd) }

        var noSigPipe: Int32 = 1
        guard setsockopt(
            fd,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            &noSigPipe,
            socklen_t(MemoryLayout<Int32>.size)
        ) == 0 else { return .noResponse }

        var timeout = timeval(tv_sec: timeoutSeconds, tv_usec: 0)
        let timeoutSize = socklen_t(MemoryLayout<timeval>.size)
        guard setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, timeoutSize) == 0,
              setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, timeoutSize) == 0 else {
            return .noResponse
        }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            return .noResponse
        }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: pathBytes)
        }
        let addressSize = socklen_t(MemoryLayout<sockaddr_un>.size)
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, addressSize)
            }
        }
        guard connected == 0, writeAll(request, to: fd) else { return .noResponse }

        let deadline = DispatchTime.now() + .seconds(timeoutSeconds)
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: min(512, maximumResponseBytes))
        while data.count < maximumResponseBytes {
            let now = DispatchTime.now().uptimeNanoseconds
            guard now < deadline.uptimeNanoseconds else {
                return incompleteOrNoResponse(data)
            }
            let remaining = deadline.uptimeNanoseconds - now
            let milliseconds = Int32(min(
                UInt64(Int32.max),
                (remaining + 999_999) / 1_000_000
            ))
            var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let pollResult = Darwin.poll(&descriptor, 1, milliseconds)
            if pollResult < 0 {
                if errno == EINTR { continue }
                return incompleteOrNoResponse(data)
            }
            guard pollResult > 0 else { return incompleteOrNoResponse(data) }
            let remainingBytes = maximumResponseBytes - data.count
            let count = recv(fd, &buffer, min(buffer.count, remainingBytes), MSG_DONTWAIT)
            if count > 0 {
                data.append(contentsOf: buffer.prefix(count))
                if let newline = data.firstIndex(of: UInt8(ascii: "\n")) {
                    return .frame(Data(data[..<newline]))
                }
            } else if count == 0 {
                return incompleteOrNoResponse(data)
            } else if errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK {
                continue
            } else {
                return incompleteOrNoResponse(data)
            }
        }
        // A frame that exactly fills the bound without a newline is truncated.
        return .incompleteFrame(data)
    }

    private func incompleteOrNoResponse(
        _ data: Data
    ) -> PowerObservationFrameExchange {
        data.isEmpty ? .noResponse : .incompleteFrame(data)
    }

    private func writeAll(_ data: Data, to fd: Int32) -> Bool {
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return data.isEmpty }
            var offset = 0
            while offset < raw.count {
                let count = write(fd, base.advanced(by: offset), raw.count - offset)
                if count > 0 {
                    offset += count
                } else if count < 0, errno == EINTR {
                    continue
                } else {
                    return false
                }
            }
            return true
        }
    }
}

extension HelperClient {
    static func powerObservation(
        clientSequence: UInt64,
        timeoutSeconds: Int = 2
    ) -> HelperPowerObservationFetchResult {
        PowerObservationV5Client(
            transport: UnixSocketPowerObservationTransport(),
            timeoutSeconds: timeoutSeconds
        ).fetch(clientSequence: clientSequence)
    }
}

#endif
