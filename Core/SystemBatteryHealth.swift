import Darwin
import Foundation

/// The percentage macOS reports in System Information. Raw battery-controller
/// capacity ratios use a different baseline from the system's Maximum Capacity.
final class SystemBatteryHealth {
    static let shared = SystemBatteryHealth()

    private static let queue = DispatchQueue(
        label: "com.leoarrow.wattson.battery-health", qos: .utility
    )
    private let lock = NSLock()
    private let now: () -> TimeInterval
    private let read: (@escaping (Double?) -> Void) -> Void
    private var cachedPercent: Double?
    private var completedAt: TimeInterval?
    private var refreshInterval: TimeInterval = 0
    private var generation = 0
    private var inFlight: Int?

    init(
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        read: @escaping (@escaping (Double?) -> Void) -> Void = { completion in
            SystemBatteryHealth.queue.async { completion(readLivePercent()) }
        }
    ) {
        self.now = now
        self.read = read
    }

    /// Sampling never waits for system_profiler. A failed refresh clears the
    /// previous percentage; subsequent samples retry after one minute.
    func currentPercent() -> Double? {
        lock.lock()
        let time = now()
        let isFresh = completedAt.map { time >= $0 && time - $0 < refreshInterval } ?? false
        let request: Int?
        if inFlight == nil, !isFresh {
            generation += 1
            request = generation
            inFlight = request
        } else {
            request = nil
        }
        let percent = cachedPercent
        lock.unlock()

        if let request {
            read { [weak self] value in self?.complete(value, request: request) }
        }
        return percent
    }

    private func complete(_ value: Double?, request: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard inFlight == request else { return }
        cachedPercent = value.flatMap { $0.isFinite && (0...100).contains($0) ? $0 : nil }
        completedAt = now()
        refreshInterval = cachedPercent == nil ? 60 : 15 * 60
        inFlight = nil
    }

    static func percent(from data: Data) -> Double? {
        guard let report = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = report["SPPowerDataType"] as? [[String: Any]],
              let battery = entries.first(where: { $0["_name"] as? String == "spbattery_information" }),
              let health = battery["sppower_battery_health_info"] as? [String: Any],
              let text = health["sppower_battery_health_maximum_capacity"] as? String,
              text.hasSuffix("%") else { return nil }
        let digits = text.dropLast()
        guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }),
              let value = Double(digits), (0...100).contains(value) else { return nil }
        return value
    }

    /// Fixed, read-only command. This method is synchronous and belongs only on
    /// the utility worker (or an explicit diagnostic probe), never a UI callback.
    static func readLivePercent() -> Double? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPPowerDataType", "-json", "-timeout", "5"]
        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "C"
        environment["LANG"] = "C"
        process.environment = environment
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
        let deadline = DispatchTime.now().uptimeNanoseconds + 7_500_000_000
        guard (try? process.run()) != nil else { return nil }
        try? outputWriteHandle.close()
        defer {
            if process.isRunning {
                process.terminate()
                let terminationDeadline = DispatchTime.now().uptimeNanoseconds + 100_000_000
                while process.isRunning,
                      DispatchTime.now().uptimeNanoseconds < terminationDeadline {
                    usleep(5_000)
                }
                if process.isRunning { _ = kill(process.processIdentifier, SIGKILL) }
            }
            process.waitUntilExit()
        }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        var observedChildExit = false
        while true {
            while true {
                guard DispatchTime.now().uptimeNanoseconds < deadline else { return nil }
                let count = Darwin.read(outputFD, &buffer, buffer.count)
                if count > 0 {
                    guard data.count + count <= 262_144 else { return nil }
                    data.append(contentsOf: buffer.prefix(count))
                } else if count == 0 || (count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
                    break
                } else if count < 0, errno == EINTR {
                    continue
                } else {
                    return nil
                }
            }
            // Drain once more after observing exit, including bytes written
            // between the prior EAGAIN and the termination notification.
            if observedChildExit { break }
            if !process.isRunning {
                observedChildExit = true
                continue
            }
            usleep(5_000)
        }
        guard process.terminationStatus == 0 else { return nil }
        return percent(from: data)
    }
}
