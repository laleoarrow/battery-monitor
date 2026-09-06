import XCTest
@testable import Wattson

final class PowerHistoryFreshnessTests: XCTestCase {
    func testSlowSamplingDoesNotKeepReadingsOlderThanTwoMinutes() {
        var now: TimeInterval = 0
        let history = PowerHistory(clock: { now })
        for index in 0..<60 {
            now = Double(index * 4)
            history.append(Double(index))
        }

        XCTAssertEqual(history.samples, Array(30..<60).map(Double.init))
        XCTAssertEqual(history.peak, 59)
    }

    func testSamplingFailureExpiresCachedValuesAndPeakWithoutNewAppend() {
        var now: TimeInterval = 0
        let history = PowerHistory(clock: { now })
        history.append(90)
        now = 10
        history.append(20)
        XCTAssertEqual(history.presentation.peak, 90)
        XCTAssertEqual(history.presentationMaterializationCountForTest, 1)

        now = 119
        XCTAssertEqual(history.presentation.peak, 90)
        XCTAssertEqual(history.presentationMaterializationCountForTest, 1)
        now = 120
        XCTAssertEqual(history.presentation.samples, [20])
        XCTAssertEqual(history.presentation.peak, 20)
        XCTAssertEqual(history.presentationMaterializationCountForTest, 2)
        now = 130
        XCTAssertTrue(history.presentation.samples.isEmpty)
        XCTAssertEqual(history.presentation.peak, 0)
        XCTAssertEqual(history.presentationMaterializationCountForTest, 3)
    }

    func testWrappedBufferRetainsOrderAcrossExpirationAndRecovery() {
        var now: TimeInterval = 0
        let history = PowerHistory(clock: { now })
        for index in 0..<75 {
            now = Double(index)
            history.append(Double(index))
        }
        XCTAssertEqual(history.samples, Array(15..<75).map(Double.init))

        now = 160
        XCTAssertEqual(history.samples, Array(41..<75).map(Double.init))
        history.append(100)
        XCTAssertEqual(history.samples, Array(41..<75).map(Double.init) + [100])

        now = 400
        history.append(5)
        XCTAssertEqual(history.samples, [5])
        XCTAssertEqual(history.peak, 5)
        history.reset()
        history.append(7)
        XCTAssertEqual(history.samples, [7])
    }

    func testPartiallyExpiredRingCanRefillAndContinueWrapping() {
        var now: TimeInterval = 0
        let history = PowerHistory(clock: { now })
        for index in 0..<75 {
            now = Double(index)
            history.append(Double(index))
        }
        now = 160
        XCTAssertEqual(history.samples, Array(41..<75).map(Double.init))
        for index in 100..<180 {
            now += 1
            history.append(Double(index))
        }
        XCTAssertEqual(history.samples, Array(120..<180).map(Double.init))
        XCTAssertEqual(history.peak, 179)
    }
}
