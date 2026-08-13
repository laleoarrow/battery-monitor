import Darwin
import Foundation
import IOKit
import os

private let log = OSLog(subsystem: "com.leoarrow.wattson.helper", category: "ipc")
// launchd's default same-job spawn throttle is 10 seconds. Staying alive past
// that window prevents a 5–10 second reconnect from waiting behind throttling,
// while the app's 1/2 Hz sampling naturally keeps an active helper warm.
private let idleTimeout: TimeInterval = 12
private let childTimeout: TimeInterval = 1.5
private let controlCenterDomain = "com.apple.controlcenter" as CFString
private let controlCenterBatteryKey = "Battery" as CFString
private let loginAgentLabel = "com.leoarrow.wattson.login"
private let wattsonBundleIdentifier = "com.leoarrow.wattson"
private let helperSocketPath = "/var/run/wattson-helper.sock"
private let helperExecutablePath = "/Library/PrivilegedHelperTools/com.leoarrow.wattson.helper"

// AppleSMC's read-only user-client protocol uses this frozen 80-byte structure.
// Wattson deliberately exposes only the two fixed whole-machine power keys below;
// no socket input can select an SMC key or reach an SMC write command.
private typealias SMCBytes = (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
)

private struct SMCVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

private struct SMCPLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

private struct SMCKeyInfoData {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
}

private struct SMCKeyData {
    var key: UInt32 = 0
    var version = SMCVersion()
    var pLimitData = SMCPLimitData()
    var keyInfo = SMCKeyInfoData()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes = (
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0
    )
}

private struct FixedSMCPower {
    let adapterW: Double?
    let systemW: Double?
}

private let smcFloatType: UInt32 = 0x666c_7420 // "flt "
private let smcSP78Type: UInt32 = 0x7370_3738 // "sp78"
private let smcSP96Type: UInt32 = 0x7370_3936 // "sp96"

/// Pure decoding boundary for the fixed SMC power keys. SMC `flt ` is stored
/// little-endian, while signed fixed-point types use network/big-endian order.
private func decodeSMCWatts(dataType: UInt32, bytes: [UInt8]) -> Double? {
    let watts: Double?
    switch dataType {
    case smcFloatType where bytes.count == 4:
        let bits = UInt32(bytes[0])
            | (UInt32(bytes[1]) << 8)
            | (UInt32(bytes[2]) << 16)
            | (UInt32(bytes[3]) << 24)
        watts = Double(Float(bitPattern: bits))
    case smcSP78Type where bytes.count == 2:
        watts = decodeSMCSignedFixedPoint(bytes, fractionalBits: 8)
    case smcSP96Type where bytes.count == 2:
        watts = decodeSMCSignedFixedPoint(bytes, fractionalBits: 6)
    default:
        watts = nil
    }

    guard let watts, watts.isFinite, (0 ... 1_000).contains(watts) else { return nil }
    return watts
}

private func decodeSMCSignedFixedPoint(
    _ bytes: [UInt8],
    fractionalBits: Int
) -> Double? {
    guard bytes.count == 2, (0 ... 15).contains(fractionalBits) else { return nil }
    let bits = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
    return Double(Int16(bitPattern: bits)) / Double(1 << fractionalBits)
}

private enum FixedSMCPowerReader {
    // These constants are the entire SMC capability granted to the app:
    // PDTR = adapter/DC-in power, PSTR = total system power.
    private static let adapterKey: UInt32 = 0x5044_5452
    private static let systemKey: UInt32 = 0x5053_5452
    private static let userClientSelector: UInt32 = 2
    private static let readBytesCommand: UInt8 = 5
    private static let readKeyInfoCommand: UInt8 = 9

    static func read() -> FixedSMCPower {
        guard MemoryLayout<SMCKeyData>.size == 80 else {
            return FixedSMCPower(adapterW: nil, systemW: nil)
        }

        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSMC")
        )
        guard service != 0 else {
            return FixedSMCPower(adapterW: nil, systemW: nil)
        }
        defer { IOObjectRelease(service) }

        var connection: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == kIOReturnSuccess else {
            return FixedSMCPower(adapterW: nil, systemW: nil)
        }
        defer { IOServiceClose(connection) }

        // PSTR is the live value used by the app whenever it exists. PDTR is a
        // compatibility fallback for hardware without PSTR; avoiding its key
        // info + value calls halves normal-path AppleSMC traffic. Reopening the
        // service/client for every request is intentional so sleep/wake never
        // leaves a cached, invalid connection behind.
        let systemW = readWatts(systemKey, connection: connection)
        return FixedSMCPower(
            adapterW: systemW == nil ? readWatts(adapterKey, connection: connection) : nil,
            systemW: systemW
        )
    }

    private static func readWatts(_ key: UInt32, connection: io_connect_t) -> Double? {
        var infoRequest = SMCKeyData()
        infoRequest.key = key
        infoRequest.data8 = readKeyInfoCommand
        guard let infoReply = call(infoRequest, connection: connection) else { return nil }

        let size = Int(infoReply.keyInfo.dataSize)
        guard size > 0, size <= 32 else { return nil }

        var valueRequest = SMCKeyData()
        valueRequest.key = key
        valueRequest.keyInfo.dataSize = infoReply.keyInfo.dataSize
        valueRequest.data8 = readBytesCommand
        guard let valueReply = call(valueRequest, connection: connection) else { return nil }

        let bytes = withUnsafeBytes(of: valueReply.bytes) { Array($0.prefix(size)) }
        return decodeSMCWatts(dataType: infoReply.keyInfo.dataType, bytes: bytes)
    }

    private static func call(_ request: SMCKeyData, connection: io_connect_t) -> SMCKeyData? {
        var request = request
        var reply = SMCKeyData()
        var replySize = MemoryLayout<SMCKeyData>.size
        let result = IOConnectCallStructMethod(
            connection,
            userClientSelector,
            &request,
            MemoryLayout<SMCKeyData>.size,
            &reply,
            &replySize
        )
        guard result == kIOReturnSuccess,
              replySize == MemoryLayout<SMCKeyData>.size,
              reply.result == 0 else { return nil }
        return reply
    }
}

private func fixedPowerReply() -> String {
    let power = FixedSMCPowerReader.read()
    guard power.adapterW != nil || power.systemW != nil else {
        return #"{"ok":false,"error":"power sensors unavailable"}"#
    }

    var object: [String: Any] = ["ok": true]
    if let adapterW = power.adapterW { object["adapterW"] = adapterW }
    if let systemW = power.systemW { object["systemW"] = systemW }
    guard let data = try? JSONSerialization.data(withJSONObject: object),
          let reply = String(data: data, encoding: .utf8) else {
        return #"{"ok":false,"error":"power encoding failed"}"#
    }
    return reply
}

// MARK: - Socket Framing

private let maximumSocketMessageBytes = 512
private let maximumPendingSocketClients = 32
private let maximumAcceptsPerPollCycle = 8
private let socketRequestStartTimeoutNanoseconds: UInt64 = 2_000_000_000
private let wattsonProtocolVersion = 4

/// Unlike process uptime, this clock advances while the Mac sleeps. Request
/// and fixed-child deadlines use it so neither stale mutations nor commands
/// can become fresh again after wake or a wall-clock adjustment.
private func socketRequestContinuousNowNanoseconds() -> UInt64 {
    clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)
}

/// Darwin's default SIGPIPE disposition terminates the process when a peer
/// closes before a reply. A stale/timed-out client must fail only its request.
private func configureNoSigPipe(_ fd: Int32) -> Bool {
    var enabled: Int32 = 1
    return setsockopt(
        fd,
        SOL_SOCKET,
        SO_NOSIGPIPE,
        &enabled,
        socklen_t(MemoryLayout<Int32>.size)
    ) == 0
}

private func configureNonBlocking(_ fd: Int32) -> Bool {
    let flags = fcntl(fd, F_GETFL)
    return flags >= 0 && fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0
}

private func configureCloseOnExec(_ fd: Int32) -> Bool {
    let flags = fcntl(fd, F_GETFD)
    return flags >= 0 && fcntl(fd, F_SETFD, flags | FD_CLOEXEC) == 0
}

private func writeAll(_ data: Data, to fd: Int32) -> Bool {
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

private func writeExpiredRequestReply(to fd: Int32) {
    let data = Data(#"{"ok":false,"error":"request expired"}"#.utf8)
    data.withUnsafeBytes { rawBuffer in
        guard let baseAddress = rawBuffer.baseAddress else { return }
        _ = send(fd, baseAddress, rawBuffer.count, MSG_DONTWAIT)
    }
}

/// Check terminal poll state first so buffered bytes cannot hide a hangup, then
/// peek only when readable. Neither operation consumes protocol or response bytes.
private func readySocketPeerIsConnected(_ fd: Int32) -> Bool {
    while true {
        var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        let pollResult = Darwin.poll(&descriptor, 1, 0)
        if pollResult < 0 {
            if errno == EINTR { continue }
            return false
        }
        let terminalEvents = Int16(POLLERR | POLLHUP | POLLNVAL)
        if descriptor.revents & terminalEvents != 0 { return false }
        if pollResult == 0 || descriptor.revents & Int16(POLLIN) == 0 { return true }

        var byte: UInt8 = 0
        let count = recv(fd, &byte, 1, MSG_PEEK | MSG_DONTWAIT)
        if count > 0 { return true }
        if count == 0 { return false }
        if errno == EINTR { continue }
        return errno == EAGAIN || errno == EWOULDBLOCK
    }
}

private func strictJSONBool(_ raw: Any?) -> Bool? {
    guard let number = raw as? NSNumber,
          CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
    return number.boolValue
}

private func validProtocolVersion(in object: [String: Any]) -> Bool {
    guard let raw = object["_wattsonProtocol"] else { return true }
    guard let number = raw as? NSNumber,
          CFGetTypeID(number) != CFBooleanGetTypeID() else { return false }
    return number.intValue == wattsonProtocolVersion
        && number.doubleValue == Double(wattsonProtocolVersion)
}

private enum SocketFrameParseResult {
    case incomplete
    case complete([String: Any])
    case malformed
}

/// Protocol v4 waits for a newline boundary, making trailing bytes deterministic.
/// A complete unversioned object is still accepted for an older installed app.
private func parseSocketFrame(_ data: Data) -> SocketFrameParseResult {
    if let newline = data.firstIndex(of: UInt8(ascii: "\n")) {
        let frame = Data(data[..<newline])
        guard let object = try? JSONSerialization.jsonObject(with: frame) as? [String: Any],
              validProtocolVersion(in: object) else { return .malformed }
        return .complete(object)
    }

    if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        if object["_wattsonProtocol"] != nil { return .incomplete }
        return .complete(object)
    }
    return .incomplete
}

private func readJSONObject(from fd: Int32) -> [String: Any]? {
    let deadline = socketRequestContinuousNowNanoseconds()
        + socketRequestStartTimeoutNanoseconds
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 256)
    while data.count < maximumSocketMessageBytes {
        let now = socketRequestContinuousNowNanoseconds()
        guard now < deadline else { return nil }
        let remainingNanoseconds = deadline - now
        let timeoutMilliseconds = Int32(min(
            UInt64(Int32.max),
            (remainingNanoseconds + 999_999) / 1_000_000
        ))
        var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        let pollResult = Darwin.poll(&descriptor, 1, timeoutMilliseconds)
        if pollResult == 0 { return nil }
        if pollResult < 0 {
            if errno == EINTR { continue }
            return nil
        }

        let remainingBytes = maximumSocketMessageBytes - data.count
        let count = recv(fd, &buffer, min(buffer.count, remainingBytes), MSG_DONTWAIT)
        if count > 0 {
            data.append(contentsOf: buffer.prefix(count))
            switch parseSocketFrame(data) {
            case let .complete(object):
                return object
            case .malformed:
                return nil
            case .incomplete:
                continue
            }
        } else if count == 0 {
            return nil
        } else if errno == EINTR {
            continue
        } else if errno == EAGAIN || errno == EWOULDBLOCK {
            continue
        } else {
            return nil
        }
    }
    return nil
}

/// Convert the next absolute inbox deadline into poll's relative millisecond
/// timeout. An incomplete reader owns the deadline while it is pending; without
/// one, the listener can sleep until the helper's absolute idle deadline.
private func socketPollTimeoutMilliseconds(
    requestContinuousNow: UInt64,
    nextReadContinuousDeadline: UInt64?,
    idleUptimeNow: UInt64,
    idleUptimeDeadline: UInt64
) -> Int32 {
    let now: UInt64
    let deadline: UInt64
    if let nextReadContinuousDeadline {
        now = requestContinuousNow
        deadline = nextReadContinuousDeadline
    } else {
        now = idleUptimeNow
        deadline = idleUptimeDeadline
    }
    guard deadline > now else { return 0 }

    let remaining = deadline - now
    let wholeMilliseconds = remaining / 1_000_000
    let roundedMilliseconds = wholeMilliseconds + (remaining % 1_000_000 == 0 ? 0 : 1)
    return Int32(min(UInt64(Int32.max), roundedMilliseconds))
}

private struct SocketRequest {
    let fd: Int32
    let peerUID: uid_t
    let continuousDeadline: UInt64
    let object: [String: Any]
}

private enum ReadySocketRequestResult {
    case none
    case expired
    case abandoned
    case request(SocketRequest)
}

private struct ReadingSocketClient {
    let fd: Int32
    let peerUID: uid_t
    let acceptedAtContinuousTime: UInt64
    let continuousDeadline: UInt64
    var data = Data()
}

/// A single-threaded framing inbox. It admits at most 32 reading + ready
/// clients. At capacity, a newly authenticated client evicts the oldest incomplete
/// reader; ready requests are never evicted and remain FIFO.
private struct SocketRequestInbox {
    private let requestContinuousNow: () -> UInt64
    private var reading: [ReadingSocketClient] = []
    private var ready: [SocketRequest] = []

    init(
        requestContinuousNow: @escaping () -> UInt64 = socketRequestContinuousNowNanoseconds
    ) {
        self.requestContinuousNow = requestContinuousNow
    }

    var count: Int { reading.count + ready.count }
    var hasPending: Bool { count > 0 }
    var nextReadContinuousDeadline: UInt64? {
        reading.map(\.continuousDeadline).min()
    }

    mutating func takeNextReady() -> ReadySocketRequestResult {
        guard !ready.isEmpty else { return .none }
        let request = ready.removeFirst()
        guard requestContinuousNow() < request.continuousDeadline else {
            writeExpiredRequestReply(to: request.fd)
            close(request.fd)
            return .expired
        }
        guard readySocketPeerIsConnected(request.fd) else {
            close(request.fd)
            return .abandoned
        }
        return .request(request)
    }

    /// Returns activity, or nil for a fatal listener/poll error.
    mutating func poll(listener: Int32, timeoutMilliseconds: Int32) -> Bool? {
        var activity = expireReaders(at: requestContinuousNow())
        var descriptors = [pollfd(fd: listener, events: Int16(POLLIN), revents: 0)]
        descriptors.append(contentsOf: reading.map {
            pollfd(fd: $0.fd, events: Int16(POLLIN), revents: 0)
        })

        let result = descriptors.withUnsafeMutableBufferPointer { buffer in
            Darwin.poll(buffer.baseAddress, nfds_t(buffer.count), timeoutMilliseconds)
        }
        if result < 0 {
            return errno == EINTR ? activity : nil
        }

        let terminalEvents = Int16(POLLERR | POLLHUP | POLLNVAL)

        // An operation may have occupied the serial executor past a reader's
        // absolute deadline. Expire again after poll and before consuming bytes.
        activity = expireReaders(at: requestContinuousNow()) || activity

        // Service existing readers first. Accepting can evict one and immediately
        // reuse its descriptor number, so reading the poll snapshot afterward
        // could otherwise consume bytes from the wrong connection.
        for descriptor in descriptors.dropFirst() where descriptor.revents != 0 {
            activity = true
            if descriptor.revents & terminalEvents != 0 {
                if let index = reading.firstIndex(where: { $0.fd == descriptor.fd }) {
                    rejectReading(at: index)
                }
                continue
            }
            if descriptor.revents & Int16(POLLIN) != 0 {
                receiveAvailableBytes(from: descriptor.fd)
            }
        }

        let listenerEvents = descriptors[0].revents
        if listenerEvents & terminalEvents != 0 { return nil }
        if listenerEvents & Int16(POLLIN) != 0 {
            guard let accepted = acceptAvailableClients(from: listener) else { return nil }
            activity = activity || accepted
        }
        return activity
    }

    mutating func closeAll() {
        reading.forEach { close($0.fd) }
        ready.forEach { close($0.fd) }
        reading.removeAll()
        ready.removeAll()
    }

    private mutating func acceptAvailableClients(from listener: Int32) -> Bool? {
        var acceptedAny = false
        for _ in 0..<maximumAcceptsPerPollCycle {
            let fd = accept(listener, nil, nil)
            if fd < 0 {
                if errno == EINTR { continue }
                if errno == EAGAIN || errno == EWOULDBLOCK { return acceptedAny }
                return nil
            }
            acceptedAny = true
            let acceptedAtContinuousTime = requestContinuousNow()

            var sendTimeout = timeval(tv_sec: 2, tv_usec: 0)
            let timeoutSize = socklen_t(MemoryLayout<timeval>.size)
            guard configureNoSigPipe(fd),
                  configureCloseOnExec(fd),
                  setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &sendTimeout, timeoutSize) == 0 else {
                close(fd)
                continue
            }

            var peerUID: uid_t = 0
            var peerGID: gid_t = 0
            guard getpeereid(fd, &peerUID, &peerGID) == 0,
                  peerUID == consoleUID() else {
                close(fd)
                continue
            }

            if count == maximumPendingSocketClients {
                guard !reading.isEmpty else {
                    close(fd)
                    continue
                }
                // The first reader is the oldest incomplete authenticated client.
                close(reading.removeFirst().fd)
            }
            reading.append(ReadingSocketClient(
                fd: fd,
                peerUID: peerUID,
                acceptedAtContinuousTime: acceptedAtContinuousTime,
                continuousDeadline: acceptedAtContinuousTime
                    + socketRequestStartTimeoutNanoseconds
            ))
        }
        return acceptedAny
    }

    private mutating func receiveAvailableBytes(from fd: Int32) {
        guard var index = reading.firstIndex(where: { $0.fd == fd }) else { return }
        var buffer = [UInt8](repeating: 0, count: 256)

        while reading[index].data.count < maximumSocketMessageBytes {
            let remaining = maximumSocketMessageBytes - reading[index].data.count
            let byteCount = recv(fd, &buffer, min(buffer.count, remaining), MSG_DONTWAIT)
            if byteCount > 0 {
                reading[index].data.append(contentsOf: buffer.prefix(byteCount))
                switch parseSocketFrame(reading[index].data) {
                case let .complete(object):
                    let client = reading.remove(at: index)
                    ready.append(SocketRequest(
                        fd: client.fd,
                        peerUID: client.peerUID,
                        continuousDeadline: client.continuousDeadline,
                        object: object
                    ))
                    return
                case .malformed:
                    rejectReading(at: index)
                    return
                case .incomplete:
                    if reading[index].data.count == maximumSocketMessageBytes {
                        rejectReading(at: index)
                        return
                    }
                }
            } else if byteCount == 0 {
                rejectReading(at: index)
                return
            } else if errno == EINTR {
                continue
            } else if errno == EAGAIN || errno == EWOULDBLOCK {
                return
            } else {
                rejectReading(at: index)
                return
            }
            guard let currentIndex = reading.firstIndex(where: { $0.fd == fd }) else { return }
            index = currentIndex
        }
    }

    private mutating func rejectReading(at index: Int) {
        let fd = reading.remove(at: index).fd
        _ = writeAll(Data(#"{"ok":false,"error":"malformed"}"#.utf8), to: fd)
        close(fd)
    }

    private mutating func expireReaders(at continuousNow: UInt64) -> Bool {
        var expiredAny = false
        for index in reading.indices.reversed()
            where reading[index].continuousDeadline <= continuousNow {
            rejectReading(at: index)
            expiredAny = true
        }
        return expiredAny
    }
}

// MARK: - Console User

/// The console owner is the only UID allowed to talk to us.
private func consoleUID() -> uid_t? {
    var info = stat()
    guard stat("/dev/console", &info) == 0 else { return nil }
    return info.st_uid
}

private enum Mode: String {
    case low, auto, high
}

private enum BatteryPreferenceWorkerOperation: String {
    case read = "--battery-preference-read"
    case hide = "--battery-preference-hide"
    case show = "--battery-preference-show"
}

private func runExitCode(_ args: [String]) -> Int32? {
    var pid: pid_t = 0
    var argv: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) }
    argv.append(nil)
    defer { argv.forEach { free($0) } }

    guard posix_spawn(&pid, args[0], nil, nil, &argv, environ) == 0 else { return nil }
    var status: Int32 = 0
    let deadline = socketRequestContinuousNowNanoseconds()
        + UInt64(childTimeout * 1_000_000_000)
    while true {
        let result = waitpid(pid, &status, WNOHANG)
        if result == pid {
            guard (status & 0x7f) == 0 else { return nil }
            return (status >> 8) & 0xff
        }
        if result < 0, errno != EINTR { return nil }
        if socketRequestContinuousNowNanoseconds() >= deadline {
            _ = kill(pid, SIGKILL)
            _ = waitpid(pid, &status, 0)
            return nil
        }
        usleep(10_000)
    }
}

private func run(_ args: [String]) -> Bool {
    runExitCode(args) == 0
}

private let maximumCommandOutputBytes = 65_536

private func stopOutputProcess(_ process: Process) {
    guard process.isRunning else { return }
    process.terminate()
    let terminationDeadline = DispatchTime.now() + .milliseconds(100)
    while process.isRunning,
          DispatchTime.now().uptimeNanoseconds < terminationDeadline.uptimeNanoseconds {
        usleep(5_000)
    }
    if process.isRunning {
        _ = kill(process.processIdentifier, SIGKILL)
    }
}

/// Fixed-command output capture with one monotonic deadline for execution and
/// reads. Draining a nonblocking pipe prevents a chatty child from deadlocking,
/// enforces the size cap while bytes arrive, and does not wait for a descendant
/// that merely inherited stdout after the direct child has exited.
private func runOutput(_ args: [String]) -> String? {
    guard !args.isEmpty else { return nil }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: args[0])
    process.arguments = Array(args.dropFirst())
    process.environment = [
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        "LANG": "C",
        "LC_ALL": "C",
    ]
    let pipe = Pipe()
    let outputReadHandle = pipe.fileHandleForReading
    let outputWriteHandle = pipe.fileHandleForWriting
    defer {
        try? outputReadHandle.close()
        try? outputWriteHandle.close()
    }
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    let outputFD = outputReadHandle.fileDescriptor
    let originalFlags = fcntl(outputFD, F_GETFL)
    guard originalFlags >= 0,
          fcntl(outputFD, F_SETFL, originalFlags | O_NONBLOCK) == 0 else { return nil }
    defer { _ = fcntl(outputFD, F_SETFL, originalFlags) }
    guard (try? process.run()) != nil else { return nil }

    let deadline = DispatchTime.now().uptimeNanoseconds
        + UInt64(childTimeout * 1_000_000_000)
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4_096)
    var observedChildExit = false

    while true {
        var madeProgress = false
        while true {
            let count = read(outputFD, &buffer, buffer.count)
            if count > 0 {
                guard data.count + count <= maximumCommandOutputBytes else {
                    stopOutputProcess(process)
                    return nil
                }
                data.append(contentsOf: buffer.prefix(count))
                madeProgress = true
            } else if count == 0 || (count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
                break
            } else if count < 0, errno == EINTR {
                continue
            } else {
                stopOutputProcess(process)
                return nil
            }
        }

        // Once the direct child is known to have exited, drain once more. It
        // may have written between the preceding EAGAIN and isRunning turning
        // false. Do not wait for EOF: a descendant may still own the write end.
        if observedChildExit { break }
        if !process.isRunning {
            observedChildExit = true
            continue
        }
        guard DispatchTime.now().uptimeNanoseconds < deadline else {
            stopOutputProcess(process)
            return nil
        }
        if !madeProgress {
            usleep(5_000)
        }
    }

    guard process.terminationStatus == 0 else { return nil }
    return String(data: data, encoding: .utf8)
}

private func runPmset(_ mode: Mode) -> Bool {
    // Constant argument vectors, one per mode. No caller-supplied value is
    // ever placed here — the request only selects which constant to run.
    // Apple's tri-state `powermode` accepts 0/1 on Low-Power-only hardware;
    // `lowpowermode` is the display alias used by `pmset -g live` there.
    switch mode {
    case .low:  return run(["/usr/bin/pmset", "-a", "powermode", "1"])
    case .auto: return run(["/usr/bin/pmset", "-a", "powermode", "0"])
    case .high: return run(["/usr/bin/pmset", "-a", "powermode", "2"])
    }
}

/// The power mode actually in force, for whichever source is supplying power.
///
/// The preference file looks like the obvious source and is the wrong one:
/// powerd writes it lazily and coalesces, so it lags the real setting by a
/// whole transition. Measured on this machine, it held `LowPowerMode = 2`
/// while pmset reported powermode 0, and held 0 right after a switch to high.
/// Reading it is what made High Power look like it never applied — it applied
/// every time, and the readback lost it. `pmset -g live` was correct and
/// immediate across seven consecutive transitions.
private func livePowerMode() -> Mode? {
    guard let text = runOutput(["/usr/bin/pmset", "-g", "live"]) else { return nil }
    return mode(fromLiveOutput: text)
}

private func mode(fromLiveOutput text: String) -> Mode? {
    for line in text.split(separator: "\n") {
        let fields = line.split(whereSeparator: { $0.isWhitespace })
        guard let key = fields.first?.lowercased(),
              let value = fields.last.flatMap({ Int($0) }) else { continue }
        switch (key, value) {
        case ("powermode", 0), ("lowpowermode", 0): return .auto
        case ("powermode", 1), ("lowpowermode", 1): return .low
        case ("powermode", 2): return .high
        case ("powermode", _), ("lowpowermode", _): return nil
        default: continue
        }
    }
    return nil
}

/// The app is sandboxed, so the helper asks pmset for capabilities of the
/// current hardware. Parsing is pure: stale preference files and their
/// directory-enumeration order cannot influence the answer.
private func supportsHighPower(
    current: Mode,
    capabilitiesOutput: String?
) -> Bool {
    if current == .high { return true }
    guard let capabilitiesOutput else { return false }
    return capabilitiesOutput.split(whereSeparator: { $0.isWhitespace }).contains {
        $0.lowercased() == "highpowermode"
    }
}

/// Being in high power right now is proof on its own. Otherwise use only the
/// fixed read-only command that reports capabilities for this hardware.
private func supportsHighPower(current: Mode) -> Bool {
    if current == .high { return true }
    let output = runOutput(["/usr/bin/pmset", "-g", "cap"])
    return supportsHighPower(current: current, capabilitiesOutput: output)
}

private func modeReply(_ mode: Mode) -> String {
    let supportsHigh = supportsHighPower(current: mode)
    return #"{"ok":true,"mode":"\#(mode.rawValue)","supportsHigh":\#(supportsHigh),"modeVerified":true}"#
}

/// The installer runs this client mode as root while its rollback backup still
/// exists. It proves the newly bootstrapped service can authenticate the console
/// user and answer over its socket without requiring battery hardware to expose
/// a power-mode value.
private func helperHealthProbeOnce() -> Bool {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return false }
    defer { close(fd) }

    guard configureNoSigPipe(fd) else { return false }
    var timeout = timeval(tv_sec: 2, tv_usec: 0)
    let timeoutSize = socklen_t(MemoryLayout<timeval>.size)
    guard setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, timeoutSize) == 0,
          setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, timeoutSize) == 0 else {
        return false
    }

    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let pathBytes = Array(helperSocketPath.utf8)
    guard pathBytes.count < MemoryLayout.size(ofValue: address.sun_path) else { return false }
    withUnsafeMutableBytes(of: &address.sun_path) { raw in
        raw.copyBytes(from: pathBytes)
    }

    let addressSize = socklen_t(MemoryLayout<sockaddr_un>.size)
    let connected = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            connect(fd, $0, addressSize)
        }
    }
    guard connected == 0 else { return false }

    let request = Data(#"{"op":"health"}"#.utf8)
    guard writeAll(request, to: fd),
          let response = readJSONObject(from: fd) else { return false }
    return strictJSONBool(response["ok"]) == true
        && strictJSONBool(response["health"]) == true
}

private func newlyInstalledHelperIsHealthy() -> Bool {
    let deadline = socketRequestContinuousNowNanoseconds() + 8_000_000_000
    repeat {
        if helperHealthProbeOnce() { return true }
        usleep(100_000)
    } while socketRequestContinuousNowNanoseconds() < deadline
    return false
}

private func dropPrivileges(to uid: uid_t) -> Bool {
    guard geteuid() == 0, uid != 0,
          let account = getpwuid(uid),
          let name = account.pointee.pw_name else { return false }
    let userName = String(cString: name)
    let gid = account.pointee.pw_gid
    return userName.withCString { initgroups($0, Int32(bitPattern: gid)) == 0 }
        && setgid(gid) == 0
        && setuid(uid) == 0
}

private func dropHealthProbePrivilegesToConsoleUser() -> Bool {
    guard let uid = consoleUID() else { return false }
    return dropPrivileges(to: uid)
}

private struct UserAccount {
    let uid: uid_t
    let gid: gid_t
    let name: String
    let home: String

    var appPath: String {
        "/Applications/Wattson.app"
    }

    var legacyAppPath: String {
        URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent("Applications/Wattson.app")
            .path
    }

    var agentDirectory: String {
        URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent("Library/LaunchAgents")
            .path
    }

    var agentPath: String {
        URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent("Library/LaunchAgents/\(loginAgentLabel).plist")
            .path
    }
}

/// Account data comes from the authenticated peer UID, never from JSON.
private func userAccount(for uid: uid_t) -> UserAccount? {
    guard uid != 0,
          let record = getpwuid(uid),
          let rawName = record.pointee.pw_name,
          let rawHome = record.pointee.pw_dir else { return nil }
    let name = String(cString: rawName)
    let home = String(cString: rawHome)
    guard !name.isEmpty, home.hasPrefix("/") else { return nil }
    return UserAccount(uid: uid, gid: record.pointee.pw_gid, name: name, home: home)
}

private func currentSupplementaryGroups() -> [gid_t]? {
    let count = getgroups(0, nil)
    guard count >= 0 else { return nil }
    guard count > 0 else { return [] }
    var groups = [gid_t](repeating: 0, count: Int(count))
    let readCount = groups.withUnsafeMutableBufferPointer {
        getgroups(count, $0.baseAddress)
    }
    return readCount == count ? groups : nil
}

private func restoreSupplementaryGroups(_ groups: [gid_t]) -> Bool {
    if groups.isEmpty { return setgroups(0, nil) == 0 }
    return groups.withUnsafeBufferPointer {
        setgroups(Int32($0.count), $0.baseAddress)
    } == 0
}

/// User-controlled home-directory paths are never touched with root file
/// privileges. The helper is single-threaded, so changing effective IDs cannot
/// leak into another request. `defer` also covers every early failure path.
private func withUserPrivileges(_ account: UserAccount, body: () -> Bool) -> Bool {
    let originalUID = geteuid()
    let originalGID = getegid()
    guard originalUID == 0, originalGID == 0,
          let originalGroups = currentSupplementaryGroups() else { return false }

    defer {
        guard seteuid(0) == 0,
              restoreSupplementaryGroups(originalGroups),
              setegid(0) == 0 else {
            os_log("could not restore helper privileges", log: log, type: .fault)
            exit(1)
        }
    }

    let groupsReady = account.name.withCString {
        initgroups($0, Int32(bitPattern: account.gid)) == 0
    }
    guard groupsReady,
          setegid(account.gid) == 0,
          seteuid(account.uid) == 0 else { return false }
    return body()
}

private func loginAgentPlist(
    for account: UserAccount,
    appPath: String? = nil
) -> [String: Any] {
    [
        "Label": loginAgentLabel,
        "ProgramArguments": ["/usr/bin/open", "-gj", appPath ?? account.appPath],
        "RunAtLoad": true,
        "LimitLoadToSessionType": "Aqua",
        "ProcessType": "Interactive",
        "AssociatedBundleIdentifiers": [wattsonBundleIdentifier],
    ]
}

private func loginAgentMatches(_ appPath: String, for account: UserAccount) -> Bool {
    withUserPrivileges(account) {
        var info = stat()
        guard lstat(account.agentPath, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFREG,
              info.st_uid == account.uid,
              info.st_gid == account.gid,
              (info.st_mode & 0o777) == 0o644,
              info.st_size > 0,
              info.st_size <= 65_536,
              let data = try? Data(contentsOf: URL(fileURLWithPath: account.agentPath)),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil)
                  as? [String: Any] else { return false }

        let expected = loginAgentPlist(for: account, appPath: appPath)
        guard plist.count == expected.count else { return false }
        return plist["Label"] as? String == loginAgentLabel
            && plist["ProgramArguments"] as? [String] == ["/usr/bin/open", "-gj", appPath]
            && plist["RunAtLoad"] as? Bool == true
            && plist["LimitLoadToSessionType"] as? String == "Aqua"
            && plist["ProcessType"] as? String == "Interactive"
            && plist["AssociatedBundleIdentifiers"] as? [String] == [wattsonBundleIdentifier]
    }
}

private func loginAgentIsCanonical(for account: UserAccount) -> Bool {
    loginAgentMatches(account.appPath, for: account)
}

private func loginAgentIsLegacyCanonical(for account: UserAccount) -> Bool {
    loginAgentMatches(account.legacyAppPath, for: account)
}

private func writeLoginAgent(for account: UserAccount) -> Bool {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: account.appPath, isDirectory: &isDirectory),
          isDirectory.boolValue,
          let data = try? PropertyListSerialization.data(
              fromPropertyList: loginAgentPlist(for: account),
              format: .xml,
              options: 0
          ) else { return false }

    let wrote = withUserPrivileges(account) {
        do {
            try FileManager.default.createDirectory(
                atPath: account.agentDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o755]
            )
            try data.write(to: URL(fileURLWithPath: account.agentPath), options: .atomic)
            return chmod(account.agentPath, 0o644) == 0
        } catch {
            return false
        }
    }
    return wrote && loginAgentIsCanonical(for: account)
}

private func removeLoginAgent(for account: UserAccount) -> Bool {
    withUserPrivileges(account) {
        var info = stat()
        guard lstat(account.agentPath, &info) == 0 else { return errno == ENOENT }
        guard (info.st_mode & S_IFMT) != S_IFDIR else { return false }
        return unlink(account.agentPath) == 0
    }
}

private func loginAgentTarget(for account: UserAccount) -> String {
    "gui/\(account.uid)/\(loginAgentLabel)"
}

private func loginAgentIsLoaded(for account: UserAccount) -> Bool {
    run(["/bin/launchctl", "print", loginAgentTarget(for: account)])
}

private func launchAtLoginEnabled(for uid: uid_t) -> Bool? {
    guard uid == consoleUID(), let account = userAccount(for: uid) else { return nil }
    guard loginAgentIsLoaded(for: account) else { return false }
    if loginAgentIsCanonical(for: account) { return true }

    // v2 stored the app in ~/Applications. Migrate only its exact, user-owned
    // LaunchAgent contract after the v3 app has landed at /Applications.
    guard loginAgentIsLegacyCanonical(for: account) else { return false }
    return setLaunchAtLoginEnabled(true, for: uid)
}

private func setLaunchAtLoginEnabled(_ enabled: Bool, for uid: uid_t) -> Bool? {
    // Recheck the console owner immediately before mutation in case fast-user
    // switching happened after the socket was authenticated.
    guard uid == consoleUID(), let account = userAccount(for: uid) else { return nil }
    let target = loginAgentTarget(for: account)

    if enabled {
        if loginAgentIsCanonical(for: account) && loginAgentIsLoaded(for: account) { return true }
        _ = run(["/bin/launchctl", "bootout", target])
        guard writeLoginAgent(for: account),
              run(["/bin/launchctl", "enable", target]),
              run(["/bin/launchctl", "bootstrap", "gui/\(account.uid)", account.agentPath]),
              loginAgentIsLoaded(for: account) else {
            _ = run(["/bin/launchctl", "bootout", target])
            _ = removeLoginAgent(for: account)
            return nil
        }
        return true
    }

    // Remove the persistent file first. Even if launchctl reports a transient
    // failure, the app cannot return at the next login.
    guard removeLoginAgent(for: account) else { return nil }
    _ = run(["/bin/launchctl", "bootout", target])
    return loginAgentIsLoaded(for: account) ? nil : false
}

/// A native PKG does not launch the app after installation. Migrate an exact
/// loaded v2 LaunchAgent before postinstall removes the v2 user-local app, so
/// launch at login keeps working even if the user does not open v3 immediately.
private func migrateLegacyLoginAgentForInstaller() -> Bool {
    guard geteuid() == 0 else { return false }
    guard let uid = consoleUID(), uid != 0,
          let account = userAccount(for: uid) else { return true }
    guard loginAgentIsLegacyCanonical(for: account) else { return true }
    return setLaunchAtLoginEnabled(true, for: uid) == true
}

/// Control Center stores Battery as 18 when it is in both Control Center and
/// the menu bar, and 8 when it remains in Control Center only. Unknown values
/// are not guessed at, so a future macOS layout cannot be overwritten from a
/// misleading checkbox state.
private func currentUserSystemBatteryIconHidden() -> Bool? {
    guard CFPreferencesSynchronize(
        controlCenterDomain,
        kCFPreferencesCurrentUser,
        kCFPreferencesCurrentHost
    ) else { return nil }
    guard let raw = CFPreferencesCopyValue(
        controlCenterBatteryKey,
        controlCenterDomain,
        kCFPreferencesCurrentUser,
        kCFPreferencesCurrentHost
    ) as? NSNumber else { return nil }
    switch raw.intValue {
    case 8: return true
    case 18: return false
    default: return nil
    }
}

private func setCurrentUserSystemBatteryIconHidden(_ hidden: Bool) -> Bool {
    CFPreferencesSetValue(
        controlCenterBatteryKey,
        NSNumber(value: hidden ? 8 : 18),
        controlCenterDomain,
        kCFPreferencesCurrentUser,
        kCFPreferencesCurrentHost
    )
    return currentUserSystemBatteryIconHidden() == hidden
}

private func runBatteryPreferenceWorker(
    _ operation: BatteryPreferenceWorkerOperation,
    for uid: uid_t
) -> Int32? {
    guard uid == consoleUID(), userAccount(for: uid) != nil else { return nil }
    return runExitCode([
        "/bin/launchctl", "asuser", "\(uid)", helperExecutablePath,
        operation.rawValue, "\(uid)",
    ])
}

private func systemBatteryIconHidden(for uid: uid_t) -> Bool? {
    switch runBatteryPreferenceWorker(.read, for: uid) {
    case 8: return true
    case 18: return false
    default: return nil
    }
}

private func restartControlCenter(for uid: uid_t) -> Bool {
    // uid comes from /dev/console, never from the request. launchd immediately
    // relaunches this per-user agent; launchctl kickstart is rejected by SIP.
    guard let exitCode = runExitCode([
        "/usr/bin/pkill", "-TERM", "-U", "\(uid)", "-x", "ControlCenter",
    ]) else { return false }
    return exitCode == 0 || exitCode == 1
}

private func setSystemBatteryIconHidden(_ hidden: Bool, for uid: uid_t) -> Bool {
    let operation: BatteryPreferenceWorkerOperation = hidden ? .hide : .show
    guard runBatteryPreferenceWorker(operation, for: uid) == 0 else { return false }
    return restartControlCenter(for: uid)
}

private func runBatteryPreferenceWorkerIfRequested() {
    guard CommandLine.arguments.count >= 2,
          let operation = BatteryPreferenceWorkerOperation(
              rawValue: CommandLine.arguments[1]
          ) else { return }
    guard CommandLine.arguments.count == 3,
          let rawUID = UInt32(CommandLine.arguments[2]),
          rawUID != 0 else { exit(2) }
    let expectedUID = uid_t(rawUID)

    // `launchctl asuser` supplies the console user's bootstrap context but
    // intentionally keeps root credentials. Permanently drop those credentials
    // before touching CurrentUser preferences. The authenticated UID is carried
    // into this worker and checked again so a fast-user switch cannot retarget
    // the request to the newly active user's cfprefsd instance.
    guard expectedUID == consoleUID(),
          dropPrivileges(to: expectedUID) else { exit(2) }
    switch operation {
    case .read:
        guard let hidden = currentUserSystemBatteryIconHidden() else { exit(2) }
        exit(hidden ? 8 : 18)
    case .hide:
        exit(setCurrentUserSystemBatteryIconHidden(true) ? 0 : 2)
    case .show:
        exit(setCurrentUserSystemBatteryIconHidden(false) ? 0 : 2)
    }
}

private func handle(_ request: SocketRequest) {
    let fd = request.fd
    let peerUID = request.peerUID
    defer { close(fd) }

    guard socketRequestContinuousNowNanoseconds() < request.continuousDeadline else {
        writeExpiredRequestReply(to: fd)
        return
    }

    // A request may have waited behind another fixed operation. Recheck the
    // console owner immediately before executing it so fast-user switching
    // cannot apply an authenticated former user's request to the new session.
    guard peerUID == consoleUID() else {
        os_log("rejected connection from uid %{public}d", log: log, type: .error, Int(peerUID))
        return
    }

    let object = request.object
    guard let op = object["op"] as? String else {
        _ = writeAll(Data(#"{"ok":false,"error":"malformed"}"#.utf8), to: fd)
        return
    }

    var reply = #"{"ok":false,"error":"rejected"}"#

    switch op {
    case "health":
        reply = #"{"ok":true,"health":true}"#
    case "getPower":
        reply = fixedPowerReply()
    case "getMode":
        if let mode = livePowerMode() {
            reply = modeReply(mode)
        } else {
            reply = #"{"ok":false,"error":"mode readback failed"}"#
        }
    case "setMode":
        if let raw = object["value"] as? String, let mode = Mode(rawValue: raw) {
            if runPmset(mode), let landed = livePowerMode() {
                reply = modeReply(landed)
            } else {
                reply = #"{"ok":false,"error":"pmset or readback failed"}"#
            }
        } else {
            os_log("rejected setMode with unknown value", log: log, type: .error)
        }
    case "getSystemBatteryIconHidden":
        if let hidden = systemBatteryIconHidden(for: peerUID) {
            reply = hidden ? #"{"ok":true,"hidden":true}"#
                           : #"{"ok":true,"hidden":false}"#
        } else {
            reply = #"{"ok":false,"error":"unknown battery preference"}"#
        }
    case "setSystemBatteryIconHidden":
        if let hidden = strictJSONBool(object["hidden"]) {
            let ok = setSystemBatteryIconHidden(hidden, for: peerUID)
            if ok {
                reply = hidden ? #"{"ok":true,"hidden":true}"#
                               : #"{"ok":true,"hidden":false}"#
            } else {
                reply = #"{"ok":false,"error":"control center update failed"}"#
            }
        } else {
            os_log("rejected battery visibility with a non-boolean value", log: log, type: .error)
        }
    case "getLaunchAtLoginEnabled":
        if let enabled = launchAtLoginEnabled(for: peerUID) {
            reply = enabled ? #"{"ok":true,"enabled":true}"#
                            : #"{"ok":true,"enabled":false}"#
        } else {
            reply = #"{"ok":false,"error":"login item readback failed"}"#
        }
    case "setLaunchAtLoginEnabled":
        if let enabled = strictJSONBool(object["enabled"]),
           let landed = setLaunchAtLoginEnabled(enabled, for: peerUID) {
            reply = landed ? #"{"ok":true,"enabled":true}"#
                           : #"{"ok":true,"enabled":false}"#
        } else {
            os_log("login item update failed or received a non-boolean value", log: log, type: .error)
            reply = #"{"ok":false,"error":"login item update failed"}"#
        }
    default:
        os_log("rejected unknown op", log: log, type: .error)
    }

    _ = writeAll(Data((reply + "\n").utf8), to: fd)
}

@main
private enum WattsonHelperMain {
    static func main() {
        runBatteryPreferenceWorkerIfRequested()

        if CommandLine.arguments.count == 2,
           CommandLine.arguments[1] == "--migrate-legacy-login-item" {
            exit(migrateLegacyLoginAgentForInstaller() ? 0 : 1)
        }

        if CommandLine.arguments.count == 2,
           CommandLine.arguments[1] == "--health-probe" {
            if !dropHealthProbePrivilegesToConsoleUser() { exit(1) }
            exit(newlyInstalledHelperIsHealthy() ? 0 : 1)
        }

        // Socket activation: launchd already opened and bound the listener.
        // The parameter is a pointer to a non-optional pointer, so this starts as a
        // throwaway allocation that launch_activate_socket overwrites with its own
        // malloc'd array. On success the caller owns that array and must free it.
        var fds = UnsafeMutablePointer<Int32>.allocate(capacity: 1)
        var fdCount: size_t = 0
        guard launch_activate_socket("Listener", &fds, &fdCount) == 0, fdCount > 0 else {
            os_log("no launchd socket", log: log, type: .fault)
            exit(1)
        }
        let listener = fds[0]
        free(fds)

        guard configureNonBlocking(listener), configureCloseOnExec(listener) else {
            os_log("could not configure listener", log: log, type: .fault)
            close(listener)
            return
        }

        let idleTimeoutNanoseconds = UInt64(idleTimeout * 1_000_000_000)
        var lastActivityUptime = DispatchTime.now().uptimeNanoseconds
        var inbox = SocketRequestInbox()
        defer {
            inbox.closeAll()
            close(listener)
        }

        while true {
            var activity = false
            var pollFailed = false

            // A command-line LaunchDaemon has no AppKit run-loop pool. Drain
            // Foundation Data/JSON temporaries after each framing or execution
            // pass so a helper kept warm by 2 s sampling remains memory-flat.
            autoreleasepool {
                switch inbox.takeNextReady() {
                case let .request(request):
                    // Exactly one FIFO request executes per pass. No operation
                    // overlaps credential-changing work from another request.
                    handle(request)
                    activity = true
                    return
                case .expired:
                    activity = true
                    return
                case .abandoned:
                    activity = true
                    return
                case .none:
                    break
                }

                let requestContinuousNow = socketRequestContinuousNowNanoseconds()
                let idleUptimeNow = DispatchTime.now().uptimeNanoseconds
                let timeoutMilliseconds = socketPollTimeoutMilliseconds(
                    requestContinuousNow: requestContinuousNow,
                    nextReadContinuousDeadline: inbox.nextReadContinuousDeadline,
                    idleUptimeNow: idleUptimeNow,
                    idleUptimeDeadline: lastActivityUptime + idleTimeoutNanoseconds
                )
                guard let didActivity = inbox.poll(
                    listener: listener,
                    timeoutMilliseconds: timeoutMilliseconds
                ) else {
                    pollFailed = true
                    return
                }
                activity = didActivity
            }

            if pollFailed {
                os_log("socket inbox poll failed", log: log, type: .fault)
                return
            }
            let idleUptimeNow = DispatchTime.now().uptimeNanoseconds
            if activity { lastActivityUptime = idleUptimeNow }
            if !inbox.hasPending,
               idleUptimeNow >= lastActivityUptime,
               idleUptimeNow - lastActivityUptime >= idleTimeoutNanoseconds {
                return
            }
        }
    }
}
