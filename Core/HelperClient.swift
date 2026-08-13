import Darwin
import Foundation

enum HelperClient {
    private static let maximumMessageBytes = 512
    private static let wattsonProtocolVersion = 4

    struct LivePower: Equatable {
        let adapterW: Double?
        let systemW: Double?
    }

    static let socketPath = "/var/run/wattson-helper.sock"

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: socketPath)
    }

    static func send(
        _ request: [String: Any],
        timeoutSeconds: Int = 2
    ) -> [String: Any]? {
        guard (1...15).contains(timeoutSeconds) else { return nil }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        // The client is synchronous, but UI callers dispatch it to their serial
        // worker queues. The timeout bounds helper failure without ever holding
        // AppKit's event loop.
        guard configureNoSigPipe(fd) else { return nil }
        var timeout = timeval(tv_sec: timeoutSeconds, tv_usec: 0)
        let timeoutSize = socklen_t(MemoryLayout<timeval>.size)
        guard setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, timeoutSize) == 0,
              setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, timeoutSize) == 0 else {
            return nil
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { return nil }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: pathBytes)
        }

        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let connected = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, size) }
        }
        guard connected == 0 else { return nil }

        var framedRequest = request
        framedRequest["_wattsonProtocol"] = wattsonProtocolVersion
        guard var payload = try? JSONSerialization.data(withJSONObject: framedRequest) else {
            return nil
        }
        payload.append(UInt8(ascii: "\n"))
        guard payload.count <= maximumMessageBytes else { return nil }
        guard writeAll(payload, to: fd) else { return nil }

        return readJSONObject(
            from: fd,
            maximumBytes: maximumMessageBytes,
            timeoutSeconds: timeoutSeconds
        )
    }

    /// Darwin sends SIGPIPE by default when a peer closes before a write. IPC
    /// failure must fail only this request, never terminate Wattson.
    static func configureNoSigPipe(_ fd: Int32) -> Bool {
        var enabled: Int32 = 1
        return setsockopt(
            fd,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            &enabled,
            socklen_t(MemoryLayout<Int32>.size)
        ) == 0
    }

    /// SOCK_STREAM may complete a write partially even for these small fixed
    /// messages. Retry only the interrupted/remaining bytes; socket timeouts
    /// still provide the request deadline.
    static func writeAll(_ data: Data, to fd: Int32) -> Bool {
        data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return data.isEmpty }
            var offset = 0
            while offset < rawBuffer.count {
                let count = write(
                    fd,
                    baseAddress.advanced(by: offset),
                    rawBuffer.count - offset
                )
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

    /// Protocol v4 is newline framed. EOF remains a compatibility boundary for
    /// an older helper response during an in-place upgrade.
    static func readJSONObject(
        from fd: Int32,
        maximumBytes: Int = maximumMessageBytes,
        timeoutSeconds: Int = 2
    ) -> [String: Any]? {
        guard maximumBytes > 0, (1...15).contains(timeoutSeconds) else { return nil }
        let deadline = DispatchTime.now() + .seconds(timeoutSeconds)
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: min(256, maximumBytes))
        while data.count < maximumBytes {
            let now = DispatchTime.now().uptimeNanoseconds
            guard now < deadline.uptimeNanoseconds else { return nil }
            let remainingNanoseconds = deadline.uptimeNanoseconds - now
            let timeoutMilliseconds = Int32(min(
                UInt64(Int32.max),
                (remainingNanoseconds + 999_999) / 1_000_000
            ))
            var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let pollResult = Darwin.poll(&descriptor, 1, timeoutMilliseconds)
            if pollResult < 0 {
                if errno == EINTR { continue }
                return nil
            }
            guard pollResult > 0 else { return nil }
            let readableEvents = Int16(POLLIN | POLLHUP)
            guard descriptor.revents & readableEvents != 0 else { return nil }

            let remaining = maximumBytes - data.count
            let count = recv(fd, &buffer, min(buffer.count, remaining), MSG_DONTWAIT)
            if count > 0 {
                data.append(contentsOf: buffer.prefix(count))
                if let newline = data.firstIndex(of: UInt8(ascii: "\n")) {
                    let frame = Data(data[..<newline])
                    return try? JSONSerialization.jsonObject(with: frame) as? [String: Any]
                }
            } else if count == 0 {
                return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            } else if errno == EINTR {
                continue
            } else if errno == EAGAIN || errno == EWOULDBLOCK {
                if descriptor.revents & Int16(POLLHUP) != 0 {
                    return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                }
                continue
            } else {
                return nil
            }
        }
        return nil
    }

    static func isHealthy() -> Bool {
        strictJSONBool(send(["op": "health"])?["health"]) == true
    }

    static func livePower() -> LivePower? {
        guard let response = send(["op": "getPower"]),
              strictJSONBool(response["ok"]) == true else {
            return nil
        }

        var invalidField = false
        func watts(_ name: String) -> Double? {
            guard let raw = response[name] else { return nil }
            guard let value = validatedWatts(raw) else {
                invalidField = true
                return nil
            }
            return value
        }

        let adapterW = watts("adapterW")
        let systemW = watts("systemW")
        guard !invalidField, adapterW != nil || systemW != nil else { return nil }
        return LivePower(adapterW: adapterW, systemW: systemW)
    }

    /// Swift bridges small NSNumber values (including 1) through `Bool` in an
    /// `is Bool` check. Core Foundation type identity distinguishes a real JSON
    /// boolean from a numeric one-watt sample without rejecting either 0 or 1.
    static func validatedWatts(_ raw: Any) -> Double? {
        guard let number = raw as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let value = number.doubleValue
        guard value.isFinite, (0 ... 1_000).contains(value) else { return nil }
        return value
    }

    static func strictJSONBool(_ raw: Any?) -> Bool? {
        guard let number = raw as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }
}
