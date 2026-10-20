import XCTest
@testable import Wattson

final class SystemBatteryHealthTests: XCTestCase {
    private func report(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "SPPowerDataType": [[
                "_name": "spbattery_information",
                "sppower_battery_health_info": [
                    "sppower_battery_health_maximum_capacity": value,
                ],
            ]],
        ])
    }

    func testUsesSystemMaximumCapacityInsteadOfRawCapacityRatio() throws {
        let data = Data("""
        {"SPPowerDataType":[{"_name":"spbattery_information",
        "sppower_battery_health_info":{"sppower_battery_health_maximum_capacity":"84%"},
        "AppleRawMaxCapacity":4000,"DesignCapacity":5000}]}
        """.utf8)
        XCTAssertEqual(SystemBatteryHealth.percent(from: data), 84)
    }

    func testAcceptsWholeSystemPercentIncludingBounds() throws {
        for value in [0, 1, 84, 100] {
            XCTAssertEqual(SystemBatteryHealth.percent(from: try report("\(value)%")), Double(value))
        }
    }

    func testRejectsInvalidOrWronglyTypedPercent() throws {
        let values: [Any] = [
            "", "%", "84", "84.5%", "-1%", "101%", "NaN%", "inf%", " 84%", "84 %",
            "８４%", "84%%", 84, true, NSNull(), ["value": "84%"],
        ]
        for value in values {
            XCTAssertNil(SystemBatteryHealth.percent(from: try report(value)), "\(value)")
        }
    }

    func testRejectsMissingHealthAndWrongReportShapes() {
        for text in [
            "not json", "[]", "null", "{}", "{\"SPPowerDataType\":{}}",
            "{\"SPPowerDataType\":[{\"_name\":\"spbattery_information\"}]}",
            "{\"SPPowerDataType\":[{\"_name\":\"spbattery_information\",\"sppower_battery_health_info\":[]}]}",
            """
            {"OtherReport":[{"_name":"spbattery_information",
            "sppower_battery_health_info":{"sppower_battery_health_maximum_capacity":"84%"}}]}
            """,
            """
            {"SPPowerDataType":[{"_name":"spac_charger_information",
            "sppower_battery_health_info":{"sppower_battery_health_maximum_capacity":"84%"}}]}
            """,
        ] {
            XCTAssertNil(SystemBatteryHealth.percent(from: Data(text.utf8)), text)
        }
    }

    func testInitialReadIsNonblockingAndRepeatedSamplesCoalesce() {
        var reads = 0
        var completion: ((Double?) -> Void)?
        let health = SystemBatteryHealth(now: { 0 }, read: {
            reads += 1
            completion = $0
        })
        for _ in 0..<100 { XCTAssertNil(health.currentPercent()) }
        XCTAssertEqual(reads, 1)
        completion?(84)
        XCTAssertEqual(health.currentPercent(), 84)
        XCTAssertEqual(reads, 1)
    }

    func testConcurrentSamplesScheduleOnlyOneReader() {
        let lock = NSLock()
        var reads = 0
        var completion: ((Double?) -> Void)?
        let health = SystemBatteryHealth(now: { 0 }, read: {
            lock.lock()
            reads += 1
            completion = $0
            lock.unlock()
        })
        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            XCTAssertNil(health.currentPercent())
        }
        XCTAssertEqual(reads, 1)
        completion?(84)
        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            XCTAssertEqual(health.currentPercent(), 84)
        }
        XCTAssertEqual(reads, 1)
    }

    func testRefreshUsesCompletionTimeAndKeepsPriorReadingDuringBoundedRead() {
        var time: TimeInterval = 0
        var completions: [(Double?) -> Void] = []
        let health = SystemBatteryHealth(now: { time }, read: { completions.append($0) })
        XCTAssertNil(health.currentPercent())
        time = 5
        completions[0](84)
        time = 904.999
        XCTAssertEqual(health.currentPercent(), 84)
        XCTAssertEqual(completions.count, 1)
        time = 905
        XCTAssertEqual(health.currentPercent(), 84)
        XCTAssertEqual(completions.count, 2)
        XCTAssertEqual(health.currentPercent(), 84)
        XCTAssertEqual(completions.count, 2)
        completions[1](83)
        XCTAssertEqual(health.currentPercent(), 83)
    }

    func testFailedRefreshClearsCachedValueAndRetriesAfterOneMinute() {
        var time: TimeInterval = 0
        var completions: [(Double?) -> Void] = []
        let health = SystemBatteryHealth(now: { time }, read: { completions.append($0) })
        XCTAssertNil(health.currentPercent())
        completions[0](84)
        time = 900
        XCTAssertEqual(health.currentPercent(), 84)
        completions[1](nil)
        XCTAssertNil(health.currentPercent())
        time = 959.999
        XCTAssertNil(health.currentPercent())
        XCTAssertEqual(completions.count, 2)
        time = 960
        XCTAssertNil(health.currentPercent())
        XCTAssertEqual(completions.count, 3)
        completions[2](83)
        XCTAssertEqual(health.currentPercent(), 83)
    }

    func testInitialFailureHasBoundedRetryAndInvalidResultsRemainUnavailable() {
        var time: TimeInterval = 0
        var completions: [(Double?) -> Void] = []
        let health = SystemBatteryHealth(now: { time }, read: { completions.append($0) })
        for invalid in [Double?.none, .some(.nan), .some(.infinity), .some(-1), .some(101)] {
            XCTAssertNil(health.currentPercent())
            let count = completions.count
            completions[count - 1](invalid)
            time += 59
            XCTAssertNil(health.currentPercent())
            XCTAssertEqual(completions.count, count)
            time += 1
        }
    }

    func testStaleDuplicateCompletionCannotReplaceNewerResultOrFinishItsRead() {
        var time: TimeInterval = 0
        var completions: [(Double?) -> Void] = []
        let health = SystemBatteryHealth(now: { time }, read: { completions.append($0) })
        XCTAssertNil(health.currentPercent())
        completions[0](84)
        time = 900
        XCTAssertEqual(health.currentPercent(), 84)
        completions[0](20)
        XCTAssertEqual(health.currentPercent(), 84)
        XCTAssertEqual(completions.count, 2)
        completions[1](83)
        completions[0](20)
        XCTAssertEqual(health.currentPercent(), 83)
    }

    func testClockReversalRefreshesRatherThanExtendingCacheLifetime() {
        var time: TimeInterval = 100
        var completions: [(Double?) -> Void] = []
        let health = SystemBatteryHealth(now: { time }, read: { completions.append($0) })
        XCTAssertNil(health.currentPercent())
        completions[0](84)
        time = 99
        XCTAssertEqual(health.currentPercent(), 84)
        XCTAssertEqual(completions.count, 2)
    }
}
