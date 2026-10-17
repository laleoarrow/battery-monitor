import Foundation
import XCTest
@testable import WattsonHelperV5Support

final class HelperTopProcessesTests: XCTestCase {
    private func counters(start: UInt64 = 1, user: UInt64 = 0, system: UInt64 = 0, wakeups: UInt64 = 0) -> HelperProcessCounters {
        HelperProcessCounters(startedAt: start, userMachTime: user, systemMachTime: system, idleWakeups: wakeups)
    }

    func testCPUAndIdleWakeupScoreMatchesAppleTopFormula() throws {
        let processes = try XCTUnwrap(HelperTopProcesses.rank(
            before: [42: counters(user: 10, system: 20, wakeups: 5)],
            after: [42: counters(user: 500_000_010, system: 250_000_020, wakeups: 25)],
            elapsedNanoseconds: 1_000_000_000
        ))
        XCTAssertEqual(processes.map(\.pid), [42])
        XCTAssertEqual(processes[0].energyImpact, 76, accuracy: 0.000_001)
        XCTAssertEqual(processes[0].cpuPercent, 75, accuracy: 0.000_001)
        XCTAssertEqual(processes[0].idleWakeupsPerSecond, 20, accuracy: 0.000_001)
    }

    func testUsesMeasuredIntervalAndAllowsMulticoreScores() throws {
        let processes = try XCTUnwrap(HelperTopProcesses.rank(
            before: [42: counters()],
            after: [42: counters(user: 4_000_000_000)],
            elapsedNanoseconds: 2_000_000_000
        ))
        XCTAssertEqual(processes[0].energyImpact, 200)
        XCTAssertEqual(processes[0].cpuPercent, 200)
        XCTAssertEqual(processes[0].idleWakeupsPerSecond, 0)
    }

    func testConvertsAppleSiliconMachTicksBeforeAddingNanosecondWakeupTax() throws {
        let processes = try XCTUnwrap(HelperTopProcesses.rank(
            before: [42: counters()],
            after: [42: counters(user: 24_000_000, wakeups: 20)],
            elapsedNanoseconds: 1_000_000_000,
            timebaseNumerator: 125,
            timebaseDenominator: 3
        ))
        XCTAssertEqual(processes[0].energyImpact, 101, accuracy: 0.000_001)
        XCTAssertEqual(processes[0].cpuPercent, 100, accuracy: 0.000_001)
        XCTAssertEqual(processes[0].idleWakeupsPerSecond, 20, accuracy: 0.000_001)
        XCTAssertNil(HelperTopProcesses.rank(before: [:], after: [:], elapsedNanoseconds: 1, timebaseDenominator: 0))
    }

    func testWakeupRateUsesTheMeasuredInterval() throws {
        let processes = try XCTUnwrap(HelperTopProcesses.rank(
            before: [42: counters(wakeups: 4)],
            after: [42: counters(wakeups: 104)],
            elapsedNanoseconds: 2_000_000_000
        ))
        XCTAssertEqual(processes[0].cpuPercent, 0)
        XCTAssertEqual(processes[0].idleWakeupsPerSecond, 50)
        XCTAssertEqual(processes[0].energyImpact, 2.5)
    }

    func testIgnoresNewExitedReusedAndRegressedProcesses() throws {
        let processes = try XCTUnwrap(HelperTopProcesses.rank(
            before: [1: counters(start: 1), 2: counters(user: 50), 3: counters(wakeups: 10), 4: counters(), 5: counters(system: 50)],
            after: [0: counters(), 1: counters(start: 2), 2: counters(user: 49), 3: counters(wakeups: 9), 5: counters(system: 49), 6: counters()],
            elapsedNanoseconds: 1_000_000_000
        ))
        XCTAssertTrue(processes.isEmpty)
        XCTAssertNil(HelperTopProcesses.rank(before: [:], after: [:], elapsedNanoseconds: 0))
        XCTAssertNil(HelperTopProcesses.rank(before: [:], after: [:], elapsedNanoseconds: 5_000_000_001))
    }

    func testSortsTiesAndCapsAtTenWithoutOverflow() throws {
        let before = Dictionary(uniqueKeysWithValues: (1...12).map { (Int32($0), counters()) })
        let after = Dictionary(uniqueKeysWithValues: (1...12).map { (Int32($0), counters(user: UInt64.max, system: UInt64.max, wakeups: UInt64.max)) })
        let processes = try XCTUnwrap(HelperTopProcesses.rank(before: before, after: after, elapsedNanoseconds: 1_000_000_000))
        XCTAssertEqual(processes.map(\.pid), Array(1...10).map(Int32.init))
        XCTAssertTrue(processes.allSatisfy { $0.energyImpact.isFinite && $0.energyImpact > 0 })
    }

    func testBoundedRankingMatchesFullSortAcrossGeneratedFixtures() {
        for count in [0, 1, 10, 11, 1_000] {
            var before: [Int32: HelperProcessCounters] = [:]
            var after: [Int32: HelperProcessCounters] = [:]
            var seed: UInt64 = 0xCAFE_BABE
            for index in 0..<count {
                seed = seed &* 6_364_136_223_846_793_005 &+ 1
                let pid = Int32(index + 1)
                let band = seed % 31 // Repeated bands exercise ties across the top-ten boundary.
                let previous = counters(start: seed, user: seed % 1_000, system: seed % 100, wakeups: seed % 10)
                before[pid] = previous
                after[pid] = counters(start: previous.startedAt,
                                      user: previous.userMachTime + band * 1_000_000,
                                      system: previous.systemMachTime + band * 500_000,
                                      wakeups: previous.idleWakeups + band * 3)
            }
            for (numerator, denominator) in [(UInt32(1), UInt32(1)), (125, 3)] {
                for elapsed: UInt64 in [1, 1_000_000_000, 5_000_000_000] {
                    let expected = fullSortRank(before: before, after: after, elapsedNanoseconds: elapsed,
                                                timebaseNumerator: numerator, timebaseDenominator: denominator)
                    XCTAssertEqual(HelperTopProcesses.rank(before: before, after: after, elapsedNanoseconds: elapsed,
                                                           timebaseNumerator: numerator, timebaseDenominator: denominator),
                                   expected, "count=\(count), interval=\(elapsed), timebase=\(numerator)/\(denominator)")
                    let reordered = Dictionary(uniqueKeysWithValues: after.sorted { $0.key > $1.key })
                    XCTAssertEqual(HelperTopProcesses.rank(before: before, after: reordered, elapsedNanoseconds: elapsed,
                                                           timebaseNumerator: numerator, timebaseDenominator: denominator), expected)
                }
            }
        }
    }

    func testBoundedRankingMatchesFullSortForInvalidCountersAndPIDReuse() throws {
        var before = Dictionary(uniqueKeysWithValues: (-1...30).map { (Int32($0), counters(user: 100, system: 100, wakeups: 100)) })
        var after = Dictionary(uniqueKeysWithValues: (-1...30).map { (Int32($0), counters(user: 1_000_000_100, system: 100, wakeups: 110)) })
        after[1] = counters(start: 2, user: UInt64.max, system: UInt64.max, wakeups: UInt64.max)
        after[2] = counters(user: 99, system: UInt64.max, wakeups: UInt64.max)
        after[3] = counters(user: UInt64.max, system: 99, wakeups: UInt64.max)
        after[4] = counters(user: UInt64.max, system: UInt64.max, wakeups: 99)
        before[5] = nil // A process appeared between snapshots.
        after[6] = nil // A process exited between snapshots.
        before[7] = counters()
        after[7] = counters(user: UInt64.max, system: UInt64.max, wakeups: UInt64.max)
        before[8] = counters(user: UInt64.max - 100, system: UInt64.max - 100, wakeups: UInt64.max - 100)
        after[8] = counters(user: UInt64.max, system: UInt64.max, wakeups: UInt64.max)
        after[9] = before[9] // A valid zero score still participates in ranking.

        let expected = fullSortRank(before: before, after: after, elapsedNanoseconds: 1_000_000_000)
        let result = try XCTUnwrap(HelperTopProcesses.rank(before: before, after: after, elapsedNanoseconds: 1_000_000_000))
        XCTAssertEqual(result, expected)
        XCTAssertEqual(result.first?.pid, 7)
        XCTAssertTrue(Set(result.map(\.pid)).isDisjoint(with: Set(Int32(-1)...Int32(6))))
    }

    func testBoundedRankingMatchesFullSortAtIntervalAndTimebaseLimits() {
        let before: [Int32: HelperProcessCounters] = [42: counters()]
        let after: [Int32: HelperProcessCounters] = [42: counters(user: UInt64.max, system: UInt64.max, wakeups: UInt64.max)]
        let cases: [(UInt64, UInt32, UInt32)] = [
            (0, 1, 1), (5_000_000_001, 1, 1), (UInt64.max, 1, 1),
            (1, 0, 1), (1, 1, 0), (1, UInt32.max, 1),
            (5_000_000_000, 1, UInt32.max), (5_000_000_000, UInt32.max, UInt32.max),
        ]
        for (elapsed, numerator, denominator) in cases {
            XCTAssertEqual(HelperTopProcesses.rank(before: before, after: after, elapsedNanoseconds: elapsed,
                                                   timebaseNumerator: numerator, timebaseDenominator: denominator),
                           fullSortRank(before: before, after: after, elapsedNanoseconds: elapsed,
                                        timebaseNumerator: numerator, timebaseDenominator: denominator))
        }
    }

    // Independent pre-optimization implementation: exact results, including all
    // numeric fields and fallback names, must survive bounded candidate selection.
    private func fullSortRank(
        before: [Int32: HelperProcessCounters], after: [Int32: HelperProcessCounters], elapsedNanoseconds: UInt64,
        timebaseNumerator: UInt32 = 1, timebaseDenominator: UInt32 = 1
    ) -> [HelperEnergyProcess]? {
        guard elapsedNanoseconds > 0, elapsedNanoseconds <= 5_000_000_000,
              timebaseNumerator > 0, timebaseDenominator > 0 else { return nil }
        let nanosecondsPerTick = Double(timebaseNumerator) / Double(timebaseDenominator)
        let processes: [HelperEnergyProcess] = after.compactMap { pid, current in
            guard pid > 0, let previous = before[pid], previous.startedAt == current.startedAt,
                  current.userMachTime >= previous.userMachTime,
                  current.systemMachTime >= previous.systemMachTime,
                  current.idleWakeups >= previous.idleWakeups else { return nil }
            let cpu = (Double(current.userMachTime - previous.userMachTime)
                + Double(current.systemMachTime - previous.systemMachTime)) * nanosecondsPerTick
            let cpuPercent = cpu / Double(elapsedNanoseconds) * 100
            let wakeupsPerSecond = Double(current.idleWakeups - previous.idleWakeups)
                * 1_000_000_000 / Double(elapsedNanoseconds)
            let score = cpuPercent + 0.05 * wakeupsPerSecond
            guard score.isFinite, score >= 0 else { return nil }
            return HelperEnergyProcess(pid: pid, name: "Process \(pid)", energyImpact: score,
                                       cpuPercent: cpuPercent, idleWakeupsPerSecond: wakeupsPerSecond)
        }
        return Array(processes.sorted {
            $0.energyImpact == $1.energyImpact ? $0.pid < $1.pid : $0.energyImpact > $1.energyImpact
        }.prefix(HelperTopProcesses.maximumProcesses))
    }

    func testResponseIncludesFramingAndAllowsEmptyList() throws {
        let processes = (1...10).map {
            HelperEnergyProcess(pid: Int32($0), name: String(repeating: "x", count: 64), energyImpact: 1.5, cpuPercent: 1, idleWakeupsPerSecond: 10)
        }
        let line = try XCTUnwrap(HelperTopProcesses.responseLine(processes: processes))
        XCTAssertEqual(line.last, UInt8(ascii: "\n"))
        XCTAssertLessThanOrEqual(line.count, HelperTopProcesses.maximumResponseBytes)
        let response = try XCTUnwrap(JSONSerialization.jsonObject(with: line) as? [String: Any])
        let rows = try XCTUnwrap(response["processes"] as? [[String: Any]])
        XCTAssertEqual(rows.first?["cpuPercent"] as? Double, 1)
        XCTAssertEqual(rows.first?["idleWakeupsPerSecond"] as? Double, 10)
        let empty = try XCTUnwrap(HelperTopProcesses.responseLine(processes: []))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: empty) as? [String: Any])
        XCTAssertEqual((object["processes"] as? [Any])?.count, 0)
        XCTAssertNil(HelperTopProcesses.responseLine(processes: processes + [processes[0]]))
    }

    func testNameLimitsPreserveWholeGraphemesAndFitTheResponseByteCap() throws {
        let family = "👨‍👩‍👧‍👦"
        let bounded = HelperTopProcesses.sanitizedName(String(repeating: family, count: 20), pid: 42)
        XCTAssertEqual(bounded, String(repeating: family, count: 3))
        XCTAssertLessThanOrEqual(bounded.utf8.count, 96)
        XCTAssertEqual(HelperTopProcesses.sanitizedName(String(repeating: "a", count: 100), pid: 42).count, 64)
        XCTAssertEqual(HelperTopProcesses.sanitizedName(" \n\t ", pid: 42), "Process 42")
        XCTAssertEqual(HelperTopProcesses.sanitizedName(String(repeating: "a", count: 63) + " more", pid: 42), String(repeating: "a", count: 63))

        let escapedName = String(repeating: "\"", count: 32) + String(repeating: "é", count: 32)
        XCTAssertEqual(escapedName.count, 64)
        XCTAssertEqual(escapedName.utf8.count, 96)
        let processes = (1...10).map {
            HelperEnergyProcess(pid: Int32.max - Int32($0), name: escapedName,
                                energyImpact: Double.greatestFiniteMagnitude,
                                cpuPercent: Double.greatestFiniteMagnitude,
                                idleWakeupsPerSecond: Double.greatestFiniteMagnitude)
        }
        let line = try XCTUnwrap(HelperTopProcesses.responseLine(processes: processes))
        XCTAssertLessThan(line.count, HelperTopProcesses.maximumResponseBytes)
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: line))
    }
}
