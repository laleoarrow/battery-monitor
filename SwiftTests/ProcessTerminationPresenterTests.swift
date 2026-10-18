import Darwin
import Foundation
import XCTest
@testable import Wattson

final class ProcessTerminationPresenterTests: XCTestCase {
    private final class Harness {
        var confirmations: [(EnergyProcess, (Bool) -> Void)] = []
        var terminations: [(ProcessIdentity, (ProcessTerminationResult) -> Void)] = []
        var failures: [(EnergyProcess, ProcessTerminationResult)] = []
        var onFailure: (() -> Void)?

        lazy var presenter = ProcessTerminationPresenter(dependencies: .init(
            confirm: { [unowned self] in confirmations.append(($0, $1)) },
            terminate: { [unowned self] in terminations.append(($0, $1)) },
            showFailure: { [unowned self] in
                failures.append(($0, $1))
                onFailure?()
            }
        ))
    }

    private func process(pid: Int32 = 42, start: UInt64 = 100) -> EnergyProcess {
        var token = audit_token_t()
        token.val = (501, 501, 20, 501, 20, UInt32(bitPattern: pid), 0, 7)
        let identity = ProcessIdentity(pid: pid, startedAt: start, auditToken: withUnsafeBytes(of: token) { Data($0) })
        return EnergyProcess(pid: pid, name: "Renderer", energyImpact: 42, cpuPercent: 42, idleWakeupsPerSecond: 0,
                             terminationIdentity: identity)
    }

    func testCancelNeverReachesTerminationAndAllowsAnotherSelection() {
        let h = Harness()
        h.presenter.request(process())
        XCTAssertTrue(h.presenter.isBusy)
        XCTAssertEqual(h.confirmations.count, 1)
        h.confirmations[0].1(false)
        XCTAssertTrue(h.terminations.isEmpty)
        XCTAssertFalse(h.presenter.isBusy)
        h.presenter.request(process(pid: 43))
        XCTAssertEqual(h.confirmations.count, 2)
    }

    func testConfirmationCapturesIdentityAndCoalescesRepeatedRequests() {
        let h = Harness()
        let original = process()
        h.presenter.request(original)
        h.presenter.request(process(pid: 43))
        XCTAssertEqual(h.confirmations.count, 1)
        h.confirmations[0].1(true)
        h.presenter.request(process(start: 101))
        h.confirmations[0].1(true)
        XCTAssertEqual(h.terminations.count, 1)
        XCTAssertEqual(h.terminations[0].0, original.terminationIdentity)
        h.terminations[0].1(.signalSent)
        XCTAssertFalse(h.presenter.isBusy)
        XCTAssertTrue(h.failures.isEmpty)
    }

    func testOldCallbacksCannotAffectANewerRequest() {
        let h = Harness()
        h.presenter.request(process())
        h.confirmations[0].1(false)
        h.presenter.request(process(pid: 43))
        h.confirmations[0].1(true)
        XCTAssertTrue(h.terminations.isEmpty)
        h.confirmations[1].1(true)
        h.terminations[0].1(.signalSent)
        h.presenter.request(process(pid: 44))
        h.terminations[0].1(.failed)
        XCTAssertTrue(h.presenter.isBusy)
        XCTAssertTrue(h.failures.isEmpty)
        XCTAssertEqual(h.confirmations.count, 3)
    }

    func testResultsSettleAndFailuresHoldBusyUntilFeedbackReturns() {
        let h = Harness()
        let results: [ProcessTerminationResult] = [
            .signalSent, .alreadyExited, .identityChanged, .notPermitted, .unavailable, .failed,
        ]
        for result in results {
            let failuresBefore = h.failures.count
            h.presenter.request(process())
            h.confirmations.last!.1(true)
            h.onFailure = {
                XCTAssertTrue(h.presenter.isBusy)
                h.presenter.request(self.process(pid: 43))
            }
            let confirmationsBefore = h.confirmations.count
            h.terminations.last!.1(result)
            XCTAssertFalse(h.presenter.isBusy)
            XCTAssertEqual(h.confirmations.count, confirmationsBefore)
            if result == .signalSent || result == .alreadyExited {
                XCTAssertEqual(h.failures.count, failuresBefore)
            } else {
                XCTAssertEqual(h.failures.last?.0, process())
                XCTAssertEqual(h.failures.last?.1, result)
                XCTAssertFalse(ProcessTerminationPresenter.failureMessage(for: result).isEmpty)
            }
        }
    }

    func testMissingInvalidOrMismatchedIdentityNeverPromptsOrSignals() {
        let h = Harness()
        let valid = process()
        let missing = EnergyProcess(pid: 42, name: "Legacy", energyImpact: 10, cpuPercent: 10, idleWakeupsPerSecond: 0)
        let mismatched = EnergyProcess(pid: 43, name: "Other", energyImpact: 10, cpuPercent: 10, idleWakeupsPerSecond: 0,
                                       terminationIdentity: valid.terminationIdentity)
        let invalid = EnergyProcess(pid: 42, name: "Malformed", energyImpact: 10, cpuPercent: 10, idleWakeupsPerSecond: 0,
                                    terminationIdentity: ProcessIdentity(pid: 42, startedAt: 1, auditToken: Data()))
        for row in [missing, mismatched, invalid] { h.presenter.request(row) }
        XCTAssertFalse(h.presenter.isBusy)
        XCTAssertTrue(h.confirmations.isEmpty)
        XCTAssertTrue(h.terminations.isEmpty)
    }
}
