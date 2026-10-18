import Darwin
import Foundation

public struct HelperEnergyProcess: Equatable, Sendable {
    public let pid: Int32
    public let name: String
    public let energyImpact: Double
    public let cpuPercent: Double
    public let idleWakeupsPerSecond: Double
    public let terminationIdentity: HelperProcessIdentity?

    public init(pid: Int32, name: String, energyImpact: Double, cpuPercent: Double, idleWakeupsPerSecond: Double,
                terminationIdentity: HelperProcessIdentity? = nil) {
        self.pid = pid
        self.name = name
        self.energyImpact = energyImpact
        self.cpuPercent = cpuPercent
        self.idleWakeupsPerSecond = idleWakeupsPerSecond
        self.terminationIdentity = terminationIdentity
    }
}

public struct HelperProcessCounters: Equatable, Sendable {
    public let startedAt: UInt64
    // proc_pid_rusage exposes CPU time in Mach absolute ticks on both
    // architectures; the timebase is 1:1 on Intel and commonly 125:3 on ARM.
    public let userMachTime: UInt64
    public let systemMachTime: UInt64
    public let idleWakeups: UInt64

    public init(startedAt: UInt64, userMachTime: UInt64, systemMachTime: UInt64, idleWakeups: UInt64) {
        self.startedAt = startedAt
        self.userMachTime = userMachTime
        self.systemMachTime = systemMachTime
        self.idleWakeups = idleWakeups
    }
}

/// Stats reads Apple's top POWER score. Computing its CPU-time + 500 us per
/// platform-idle-wakeup formula directly avoids top's memory-map traversal.
/// This relative score is neither watts nor Activity Monitor's private metric.
public enum HelperTopProcesses {
    public static let maximumProcesses = 10
    public static let maximumResponseBytes = 4_096
    // Effective UID/GID changes affect every thread in this helper. The FIFO
    // user-file operations share this lock with each short native snapshot;
    // the one-second sampling wait never holds it.
    public static let credentialLock = NSLock()
    private static let maximumSamplingNanoseconds: UInt64 = 5_000_000_000

    public static func rank(
        before: [Int32: HelperProcessCounters],
        after: [Int32: HelperProcessCounters],
        elapsedNanoseconds: UInt64,
        timebaseNumerator: UInt32 = 1,
        timebaseDenominator: UInt32 = 1
    ) -> [HelperEnergyProcess]? {
        guard elapsedNanoseconds > 0, elapsedNanoseconds <= maximumSamplingNanoseconds,
              timebaseNumerator > 0, timebaseDenominator > 0 else { return nil }
        let nanosecondsPerTick = Double(timebaseNumerator) / Double(timebaseDenominator)
        // Keep only numeric candidates so the full process walk neither sorts
        // every result nor allocates fallback names for discarded processes.
        var candidates: [(pid: Int32, energyImpact: Double, cpuPercent: Double, idleWakeupsPerSecond: Double)] = []
        candidates.reserveCapacity(maximumProcesses)
        for (pid, current) in after {
            guard pid > 0, let previous = before[pid],
                  previous.startedAt == current.startedAt,
                  current.userMachTime >= previous.userMachTime,
                  current.systemMachTime >= previous.systemMachTime,
                  current.idleWakeups >= previous.idleWakeups else { continue }
            // Convert each delta before addition/multiplication so malformed or
            // wrapped counters cannot overflow an integer in the root helper.
            let cpu = (Double(current.userMachTime - previous.userMachTime)
                + Double(current.systemMachTime - previous.systemMachTime)) * nanosecondsPerTick
            let cpuPercent = cpu / Double(elapsedNanoseconds) * 100
            let wakeupsPerSecond = Double(current.idleWakeups - previous.idleWakeups)
                * 1_000_000_000 / Double(elapsedNanoseconds)
            let score = cpuPercent + 0.05 * wakeupsPerSecond
            guard score.isFinite, score >= 0 else { continue }
            let index = candidates.firstIndex {
                score == $0.energyImpact ? pid < $0.pid : score > $0.energyImpact
            } ?? candidates.endIndex
            guard index < maximumProcesses else { continue }
            if candidates.count == maximumProcesses { candidates.removeLast() }
            candidates.insert((pid, score, cpuPercent, wakeupsPerSecond), at: index)
        }
        return candidates.map {
            HelperEnergyProcess(pid: $0.pid, name: "Process \($0.pid)", energyImpact: $0.energyImpact,
                                cpuPercent: $0.cpuPercent, idleWakeupsPerSecond: $0.idleWakeupsPerSecond)
        }
    }

    public static func sample(peerUID: uid_t? = nil) -> [HelperEnergyProcess]? {
        let deadline = now() + maximumSamplingNanoseconds
        var timebase = mach_timebase_info_data_t()
        guard mach_timebase_info(&timebase) == KERN_SUCCESS else { return nil }
        guard let first = snapshot(deadline: deadline) else { return nil }
        Thread.sleep(forTimeInterval: 1)
        guard let second = snapshot(deadline: deadline), second.time > first.time,
              now() < deadline,
              let ranked = rank(
                  before: first.processes,
                  after: second.processes,
                  elapsedNanoseconds: second.time - first.time,
                  timebaseNumerator: timebase.numer,
                  timebaseDenominator: timebase.denom
              ) else { return nil }
        // Resolve only the ten visible candidates; the full process walk
        // records counters only. Only visible candidates request task name
        // ports; termination identities are offered only to their console user.
        credentialLock.lock()
        defer { credentialLock.unlock() }
        guard now() < deadline else { return nil }
        let termination = SystemHelperProcessTerminationBackend()
        let processes: [HelperEnergyProcess] = ranked.compactMap {
            let name = processName($0.pid)
            guard now() < deadline,
                  let current = processCounters($0.pid),
                  current.startedAt == second.processes[$0.pid]?.startedAt else { return nil }
            let identity: HelperProcessIdentity?
            if let uid = peerUID, uid != 0, termination.consoleUser == uid, termination.signalIsAvailable,
               case let .success(candidate) = termination.identity(for: $0.pid),
               candidate.startedAt == current.startedAt, candidate.belongsToConsoleUser(uid) {
                identity = candidate
            } else {
                identity = nil
            }
            return HelperEnergyProcess(
                pid: $0.pid,
                name: name,
                energyImpact: $0.energyImpact,
                cpuPercent: $0.cpuPercent,
                idleWakeupsPerSecond: $0.idleWakeupsPerSecond,
                terminationIdentity: identity
            )
        }
        return now() < deadline ? processes : nil
    }

    public static func responseLine(processes: [HelperEnergyProcess]) -> Data? {
        guard processes.count <= maximumProcesses else { return nil }
        let object: [String: Any] = [
            "ok": true,
            "processes": processes.map { process -> [String: Any] in
                var row: [String: Any] = ["pid": process.pid, "name": process.name, "energyImpact": process.energyImpact,
                                         "cpuPercent": process.cpuPercent, "idleWakeupsPerSecond": process.idleWakeupsPerSecond]
                if let identity = process.terminationIdentity {
                    row["terminationIdentity"] = ["startedAt": String(identity.startedAt),
                                                   "auditToken": identity.auditToken.base64EncodedString()]
                }
                return row
            },
        ]
        guard var data = try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes]),
              data.count < maximumResponseBytes else { return nil }
        data.append(UInt8(ascii: "\n"))
        return data
    }

    private static func now() -> UInt64 {
        clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)
    }

    private static func snapshot(deadline: UInt64) -> (time: UInt64, processes: [Int32: HelperProcessCounters])? {
        credentialLock.lock()
        defer { credentialLock.unlock() }
        let started = now()
        let estimate = proc_listallpids(nil, 0)
        guard started < deadline, estimate > 0, estimate <= 131_072 else { return nil }
        var pids = [pid_t](repeating: 0, count: Int(estimate) + 256)
        let count = pids.withUnsafeMutableBytes {
            proc_listallpids($0.baseAddress, Int32($0.count))
        }
        guard count > 0, count < pids.count else { return nil }
        var counters: [Int32: HelperProcessCounters] = [:]
        counters.reserveCapacity(Int(count))
        for pid in pids.prefix(Int(count)) where pid > 0 {
            guard now() < deadline else { return nil }
            // Races with process exit, unavailable system processes and
            // platform permission failures exclude only that process.
            counters[pid] = processCounters(pid)
        }
        let ended = now()
        guard ended < deadline, !counters.isEmpty else { return nil }
        return (started + (ended - started) / 2, counters)
    }

    private static func processCounters(_ pid: Int32) -> HelperProcessCounters? {
        var usage = rusage_info_v0()
        let result = withUnsafeMutablePointer(to: &usage) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V0, $0)
            }
        }
        guard result == 0, usage.ri_proc_exit_abstime == 0 else { return nil }
        return HelperProcessCounters(
            startedAt: usage.ri_proc_start_abstime,
            userMachTime: usage.ri_user_time,
            systemMachTime: usage.ri_system_time,
            idleWakeups: usage.ri_pkg_idle_wkups
        )
    }

    private static func processName(_ pid: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        let count = proc_name(pid, &buffer, UInt32(buffer.count))
        guard count > 0 else { return "Process \(pid)" }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        let raw = String(decoding: bytes, as: UTF8.self)
        return sanitizedName(raw, pid: pid)
    }

    static func sanitizedName(_ raw: String, pid: Int32) -> String {
        // Joiners are part of legitimate graphemes (for example family emoji
        // and shaped scripts). Replace other control-bearing characters whole.
        let controls = CharacterSet.controlCharacters.subtracting(
            CharacterSet(charactersIn: "\u{200C}\u{200D}")
        )
        let cleaned = String(raw.map { character -> Character in
            character.unicodeScalars.contains(where: controls.contains) ? " " : character
        }).trimmingCharacters(in: .whitespacesAndNewlines)
        var name = ""
        var bytes = 0
        for character in cleaned.prefix(64) {
            let characterBytes = String(character).utf8.count
            guard bytes + characterBytes <= 96 else { break }
            name.append(character)
            bytes += characterBytes
        }
        while name.last?.isWhitespace == true { name.removeLast() }
        return name.isEmpty ? "Process \(pid)" : name
    }
}
