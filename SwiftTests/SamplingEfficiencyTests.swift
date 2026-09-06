import XCTest
@testable import Wattson

final class SamplingEfficiencyTests: XCTestCase {
    func testPeriodicTickCannotCancelAnOpeningFreshFollowUp() {
        var cadence = SamplingCadence(now: 0)
        var requests = SampleRequestCoalescer()
        // A hidden acquisition was already in flight before the user opened.
        XCTAssertTrue(requests.request(recordHistory: false, requiresFreshFollowUp: false))
        cadence.displayIsActive = true
        let openingGeneration = cadence.displayGeneration

        // Run the periodic callback before the deferred opening callback. It
        // coalesces into the old acquisition and rearms its next timer, but it
        // cannot satisfy the opening event's fresh-follow-up requirement.
        let history = cadence.takeHistoryRequest(at: 2)
        XCTAssertFalse(requests.request(recordHistory: history, requiresFreshFollowUp: false))
        XCTAssertEqual(cadence.nextDelay(at: 2), 1)
        XCTAssertTrue(cadence.isCurrentOpening(openingGeneration))
        if cadence.isCurrentOpening(openingGeneration) {
            XCTAssertFalse(requests.request(recordHistory: cadence.takeHistoryRequest(at: 2),
                                            requiresFreshFollowUp: true))
        }
        let old = requests.complete()
        XCTAssertTrue(old.publishCurrent)
        XCTAssertTrue(old.recordHistory)
        XCTAssertTrue(old.requiresFreshFollowUp)
        XCTAssertTrue(requests.request(recordHistory: false, requiresFreshFollowUp: false))
        XCTAssertFalse(requests.complete().requiresFreshFollowUp)
    }

    func testCloseAndReopenRejectsOnlyTheOldOpeningCallback() {
        var cadence = SamplingCadence(now: 0)
        var requests = SampleRequestCoalescer()
        XCTAssertTrue(requests.request(recordHistory: false, requiresFreshFollowUp: false))
        cadence.displayIsActive = true
        let firstOpening = cadence.displayGeneration
        cadence.displayIsActive = false
        XCTAssertFalse(cadence.isCurrentOpening(firstOpening))
        cadence.displayIsActive = true
        let secondOpening = cadence.displayGeneration
        XCTAssertNotEqual(firstOpening, secondOpening)
        XCTAssertFalse(cadence.isCurrentOpening(firstOpening))
        XCTAssertTrue(cadence.isCurrentOpening(secondOpening))

        var deliveredOpeningCallbacks = 0
        for generation in [firstOpening, secondOpening] {
            if cadence.isCurrentOpening(generation) {
                deliveredOpeningCallbacks += 1
                XCTAssertFalse(requests.request(recordHistory: false, requiresFreshFollowUp: true))
            }
        }
        XCTAssertEqual(deliveredOpeningCallbacks, 1)
        XCTAssertTrue(requests.complete().requiresFreshFollowUp)
        cadence.displayIsActive = true
        XCTAssertEqual(cadence.displayGeneration, secondOpening)
        _ = cadence.takeHistoryRequest(at: 2)
        cadence.resetHistory(at: 10)
        XCTAssertEqual(cadence.displayGeneration, secondOpening)
    }

    func testHiddenSamplingUsesFiveReadsAndHistoryRequestsInTenSeconds() {
        var cadence = SamplingCadence(now: 0)
        var now = 0.0
        var historyRequests = 0
        XCTAssertEqual(cadence.tolerance, 0.2)
        for _ in 0..<5 {
            XCTAssertEqual(cadence.nextDelay(at: now), 2)
            now += cadence.nextDelay(at: now)
            if cadence.takeHistoryRequest(at: now) { historyRequests += 1 }
        }
        XCTAssertEqual(now, 10)
        XCTAssertEqual(historyRequests, 5)
    }

    func testEveryOpeningPhaseSharesHistoryReadsInsteadOfAddingASecondClock() {
        for phase in [0.1, 0.5, 0.9, 1.9] {
            var cadence = SamplingCadence(now: 0)
            cadence.displayIsActive = true
            XCTAssertEqual(cadence.tolerance, 0.1)
            // Opening remains one immediate read, separate from periodic work.
            XCTAssertFalse(cadence.takeHistoryRequest(at: phase))
            var now = phase
            var sampleTimes: [TimeInterval] = []
            var historyTimes: [TimeInterval] = []
            for _ in 0..<10 {
                let delay = cadence.nextDelay(at: now)
                XCTAssertGreaterThan(delay, 0)
                XCTAssertLessThanOrEqual(delay, 1)
                now += delay
                sampleTimes.append(now)
                if cadence.takeHistoryRequest(at: now) { historyTimes.append(now) }
            }
            XCTAssertEqual(historyTimes, [2, 4, 6, 8, 10], "phase=\(phase)")
            XCTAssertEqual(sampleTimes.filter { $0 <= phase + 2 }.count, 2)
            // The previous clocks at [phase+1, phase+2] and [2] requested
            // three independent acquisitions when each read completed quickly.
            let previousFirstTwoSeconds = [phase + 1, phase + 2, 2]
            XCTAssertEqual(Set(previousFirstTwoSeconds).count, 3)
            XCTAssertLessThanOrEqual(sampleTimes.last!, phase + 10)
        }
    }

    func testRepeatedVisibilityChangesNeverPostponeHistory() {
        var cadence = SamplingCadence(now: 0)
        for index in 1...19 {
            let now = Double(index) / 10
            cadence.displayIsActive = true
            XCTAssertFalse(cadence.takeHistoryRequest(at: now))
            XCTAssertLessThanOrEqual(cadence.nextDelay(at: now), 1)
            cadence.displayIsActive = false
            XCTAssertEqual(cadence.nextDelay(at: now), 2 - now, accuracy: 0.000_001)
        }
        XCTAssertTrue(cadence.takeHistoryRequest(at: 2))
        XCTAssertEqual(cadence.nextDelay(at: 2), 2)
        cadence.displayIsActive = true
        XCTAssertEqual(cadence.nextDelay(at: 2), 1)
    }

    func testOpeningAtAnOverdueDeadlineRecordsOnceWithoutCatchUp() {
        var cadence = SamplingCadence(now: 0)
        cadence.displayIsActive = true
        XCTAssertEqual(cadence.nextDelay(at: 9), 0)
        XCTAssertTrue(cadence.takeHistoryRequest(at: 9))
        XCTAssertFalse(cadence.takeHistoryRequest(at: 9))
        XCTAssertEqual(cadence.nextDelay(at: 9), 1)
        XCTAssertFalse(cadence.takeHistoryRequest(at: 10))
        XCTAssertTrue(cadence.takeHistoryRequest(at: 11))
    }

    func testTimerToleranceDoesNotDeferTheNextHistorySampleToAThirdTick() {
        var cadence = SamplingCadence(now: 0)
        cadence.displayIsActive = true
        XCTAssertFalse(cadence.takeHistoryRequest(at: 1.1))
        XCTAssertEqual(cadence.nextDelay(at: 1.1), 0.9, accuracy: 0.000_001)
        XCTAssertTrue(cadence.takeHistoryRequest(at: 2.15))
        XCTAssertFalse(cadence.takeHistoryRequest(at: 3.2))
        XCTAssertEqual(cadence.nextDelay(at: 3.2), 0.95, accuracy: 0.000_001)
        XCTAssertTrue(cadence.takeHistoryRequest(at: 4.15))
    }

    func testFailedAndSlowReadsKeepTheCadenceWithoutPeriodicFollowUps() {
        var cadence = SamplingCadence(now: 0)
        var requests = SampleRequestCoalescer()
        var availability = StartupAvailabilityReducer()
        _ = availability.start(.snapshot(PowerSnapshot(percent: 70)))
        cadence.displayIsActive = true
        XCTAssertTrue(requests.request(recordHistory: false, requiresFreshFollowUp: false))
        for now in [1.0, 2.0, 3.0, 4.0] {
            let history = cadence.takeHistoryRequest(at: now)
            XCTAssertFalse(requests.request(recordHistory: history, requiresFreshFollowUp: false))
        }
        let completed = requests.complete()
        XCTAssertTrue(completed.recordHistory)
        XCTAssertFalse(completed.requiresFreshFollowUp)
        let failed = availability.finish(nil, recordHistory: completed.recordHistory)
        XCTAssertFalse(failed.shouldRecordHistory)
        XCTAssertTrue(availability.isDegraded)
        XCTAssertEqual(cadence.nextDelay(at: 4), 1)
        XCTAssertFalse(cadence.takeHistoryRequest(at: 5))
        XCTAssertTrue(cadence.takeHistoryRequest(at: 6))
    }

    func testWakeRestartsCadenceFromItsImmediateHistoryRequest() {
        for shown in [false, true] {
            var cadence = SamplingCadence(now: 0)
            cadence.displayIsActive = shown
            cadence.resetHistory(at: 100)
            XCTAssertEqual(cadence.nextDelay(at: 100), shown ? 1 : 2)
            XCTAssertFalse(cadence.takeHistoryRequest(at: 100))
            XCTAssertTrue(cadence.takeHistoryRequest(at: 102))
            XCTAssertFalse(cadence.takeHistoryRequest(at: 102))
        }
    }

    func testWakeRetainsLastReadingButCannotPublishThePreSleepAcquisition() {
        var availability = StartupAvailabilityReducer()
        var requests = SampleRequestCoalescer()
        var visible = PowerSnapshot(percent: 70, plugged: true,
                                    adapterW: 40, batteryW: 10, systemW: 30)
        _ = availability.start(.snapshot(visible))
        XCTAssertTrue(requests.request(recordHistory: true, requiresFreshFollowUp: false))

        let wake = availability.finish(nil, recordHistory: false)
        XCTAssertNil(wake.snapshot)
        XCTAssertFalse(wake.shouldRecordHistory)
        XCTAssertTrue(availability.hasUsableSnapshot)
        XCTAssertTrue(availability.isDegraded)
        XCTAssertEqual(visible.percent, 70)
        XCTAssertFalse(requests.request(recordHistory: true, requiresFreshFollowUp: true,
                                        supersedesCurrent: true))

        let oldCompletion = requests.complete()
        XCTAssertFalse(oldCompletion.publishCurrent)
        XCTAssertTrue(oldCompletion.requiresFreshFollowUp)
        // Controller must not run availability.finish for the superseded result.
        XCTAssertTrue(availability.isDegraded)
        XCTAssertTrue(requests.request(recordHistory: oldCompletion.recordHistory,
                                       requiresFreshFollowUp: false))
        let freshCompletion = requests.complete()
        XCTAssertTrue(freshCompletion.publishCurrent)
        let fresh = availability.finish(
            PowerSnapshot(percent: 69, plugged: false, batteryW: -20, systemW: 20),
            recordHistory: freshCompletion.recordHistory
        )
        if let snapshot = fresh.snapshot { visible = snapshot }
        XCTAssertEqual(visible.percent, 69)
        XCTAssertFalse(availability.isDegraded)
        XCTAssertTrue(fresh.shouldRecordHistory)
    }

    func testWakePartialReadStaysDegradedUntilAUsableReadingReturns() {
        var availability = StartupAvailabilityReducer()
        _ = availability.start(.snapshot(PowerSnapshot(percent: 70)))
        _ = availability.finish(nil, recordHistory: false)
        for _ in 0..<3 {
            let plan = availability.finish(nil, recordHistory: true)
            XCTAssertNil(plan.snapshot)
            XCTAssertFalse(plan.shouldRecordHistory)
            XCTAssertTrue(availability.hasUsableSnapshot)
            XCTAssertTrue(availability.isDegraded)
        }
        _ = availability.finish(PowerSnapshot(percent: 69), recordHistory: true)
        XCTAssertFalse(availability.isDegraded)
    }
}
