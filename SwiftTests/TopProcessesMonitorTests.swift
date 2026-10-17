import XCTest
@testable import Wattson

final class TopProcessesMonitorTests: XCTestCase {
    private let reading = TopProcessesState.ready([
        EnergyProcess(pid: 42, name: "Safari", energyImpact: 12.5, cpuPercent: 12.5, idleWakeupsPerSecond: 0),
    ])

    func testInactiveTicksDoNotReadAndActiveTicksCoalesceAtTenSeconds() {
        var time: TimeInterval = 10
        var reads = 0
        var completion: ((TopProcessesState) -> Void)?
        var updates: [TopProcessesState] = []
        let monitor = TopProcessesMonitor(now: { time }, read: {
            reads += 1
            completion = $0
        })
        monitor.onUpdate = { updates.append($0) }
        monitor.refreshIfNeeded()
        XCTAssertEqual(reads, 0)
        monitor.setActive(true)
        XCTAssertEqual(reads, 1)
        XCTAssertEqual(updates, [.loading])
        monitor.setActive(true)
        time = 30
        monitor.refreshIfNeeded()
        XCTAssertEqual(reads, 1)
        completion?(reading)
        XCTAssertEqual(updates, [.loading, reading])
        time = 39.9
        monitor.refreshIfNeeded()
        XCTAssertEqual(reads, 1)
        time = 40
        monitor.refreshIfNeeded()
        XCTAssertEqual(reads, 2)
    }

    func testClosingDiscardsLateResultsAndStopsAllFurtherReads() {
        var completion: ((TopProcessesState) -> Void)?
        var updates: [TopProcessesState] = []
        var reads = 0
        let monitor = TopProcessesMonitor(read: {
            reads += 1
            completion = $0
        })
        monitor.onUpdate = { updates.append($0) }
        monitor.setActive(true)
        monitor.setActive(false)
        completion?(reading)
        monitor.refreshIfNeeded()
        XCTAssertEqual(reads, 1)
        XCTAssertEqual(updates, [.loading, .loading])
    }

    func testRapidReopeningWaitsForOldReadAndPublishesOnlyFreshResult() {
        var completions: [(TopProcessesState) -> Void] = []
        var updates: [TopProcessesState] = []
        let monitor = TopProcessesMonitor(read: { completions.append($0) })
        monitor.onUpdate = { updates.append($0) }
        monitor.setActive(true)
        monitor.setActive(false)
        monitor.setActive(true)
        XCTAssertEqual(completions.count, 1)
        completions[0](reading)
        XCTAssertEqual(completions.count, 2)
        XCTAssertEqual(updates, [.loading, .loading, .loading])
        completions[1](.ready([]))
        XCTAssertEqual(updates.last, .ready([]))
    }

    func testUnavailableReadRetriesWithoutKeepingStaleRows() {
        var time: TimeInterval = 0
        var completions: [(TopProcessesState) -> Void] = []
        var updates: [TopProcessesState] = []
        let monitor = TopProcessesMonitor(now: { time }, read: { completions.append($0) })
        monitor.onUpdate = { updates.append($0) }
        monitor.setActive(true)
        completions[0](reading)
        time = 10
        monitor.refreshIfNeeded()
        completions[1](.unavailable)
        XCTAssertEqual(updates.last, .unavailable)
        time = 20
        monitor.refreshIfNeeded()
        XCTAssertEqual(completions.count, 3)
        completions[2](reading)
        XCTAssertEqual(updates.last, reading)
    }
}
