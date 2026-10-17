import Darwin
import Foundation

// Compile this file with HelperV5/TopProcesses.swift using -O. The caller owns
// its project-local scratch binary and bounded process lifecycle. No app,
// preferences, helper connection or native process sampling is used here.
@main
private enum RankBenchmark {
    typealias Snapshot = [Int32: HelperProcessCounters]

    @inline(never)
    static func fullSort(before: Snapshot, after: Snapshot) -> [HelperEnergyProcess] {
        let processes: [HelperEnergyProcess] = after.compactMap { pid, current in
            guard pid > 0, let previous = before[pid], previous.startedAt == current.startedAt,
                  current.userMachTime >= previous.userMachTime,
                  current.systemMachTime >= previous.systemMachTime,
                  current.idleWakeups >= previous.idleWakeups else { return nil }
            let cpu = Double(current.userMachTime - previous.userMachTime)
                + Double(current.systemMachTime - previous.systemMachTime)
            let cpuPercent = cpu / 1_000_000_000 * 100
            let wakeupsPerSecond = Double(current.idleWakeups - previous.idleWakeups) * 1_000_000_000 / 1_000_000_000
            let score = cpuPercent + 0.05 * wakeupsPerSecond
            guard score.isFinite, score >= 0 else { return nil }
            return HelperEnergyProcess(pid: pid, name: "Process \(pid)", energyImpact: score,
                                       cpuPercent: cpuPercent, idleWakeupsPerSecond: wakeupsPerSecond)
        }
        return Array(processes.sorted {
            $0.energyImpact == $1.energyImpact ? $0.pid < $1.pid : $0.energyImpact > $1.energyImpact
        }.prefix(HelperTopProcesses.maximumProcesses))
    }

    @inline(never)
    static func bounded(before: Snapshot, after: Snapshot) -> [HelperEnergyProcess] {
        HelperTopProcesses.rank(before: before, after: after, elapsedNanoseconds: 1_000_000_000)!
    }

    static func fixtures(count: Int) -> (Snapshot, Snapshot) {
        var before: Snapshot = [:]
        var after: Snapshot = [:]
        var seed: UInt64 = 0xCAFE_BABE
        for index in 0..<count {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1
            let pid = Int32(index + 1)
            let band = seed % 31
            let previous = HelperProcessCounters(startedAt: seed, userMachTime: seed % 1_000,
                                                 systemMachTime: seed % 100, idleWakeups: seed % 10)
            before[pid] = previous
            after[pid] = HelperProcessCounters(startedAt: previous.startedAt,
                                              userMachTime: previous.userMachTime + band * 1_000_000,
                                              systemMachTime: previous.systemMachTime + band * 500_000,
                                              idleWakeups: previous.idleWakeups + band * 3)
        }
        return (before, after)
    }

    static func main() throws {
        let iterations = CommandLine.arguments.dropFirst().first.flatMap(Int.init) ?? 100
        precondition((100...10_000).contains(iterations))
        var sink: Double = 0
        for count in [10, 100, 1_000, 10_000] {
            let (before, after) = fixtures(count: count)
            precondition(fullSort(before: before, after: after) == bounded(before: before, after: after))
            for _ in 0..<20 {
                sink += fullSort(before: before, after: after).first?.energyImpact ?? 0
                sink += bounded(before: before, after: after).first?.energyImpact ?? 0
            }
            for round in 1...3 {
                // Same dictionary instances and ABBA order reduce order effects.
                for variant in ["full-sort", "bounded", "bounded", "full-sort"] {
                    let start = clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)
                    for _ in 0..<iterations {
                        let result = variant == "full-sort" ? fullSort(before: before, after: after)
                            : bounded(before: before, after: after)
                        sink += result.reduce(0) { $0 + $1.energyImpact + Double($1.pid) }
                    }
                    let elapsed = clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW) - start
                    let record: [String: Any] = ["case": "process-rank", "processes": count, "round": round,
                                                 "variant": variant, "iterations": iterations,
                                                 "ns_per_iteration": Double(elapsed) / Double(iterations)]
                    print(String(decoding: try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]), as: UTF8.self))
                }
            }
        }
        print("checksum=\(sink)")
    }
}
