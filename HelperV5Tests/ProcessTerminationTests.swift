import Darwin
import Foundation
import XCTest
@testable import WattsonHelperV5Support

final class HelperProcessTerminationTests: XCTestCase {
    private func identity(pid: Int32 = 42, startedAt: UInt64 = UInt64.max, effectiveUID: uid_t = 501,
                          realUID: uid_t = 501, version: UInt32 = 7) -> HelperProcessIdentity {
        var token = audit_token_t()
        token.val = (501, effectiveUID, 20, realUID, 20, UInt32(bitPattern: pid), 0, version)
        return HelperProcessIdentity(pid: pid, startedAt: startedAt, auditToken: withUnsafeBytes(of: token) { Data($0) })
    }

    private func request(_ identity: HelperProcessIdentity) -> [String: Any] {
        ["_wattsonProtocol": 4, "op": "forceQuitProcess", "pid": identity.pid,
         "startedAt": String(identity.startedAt), "auditToken": identity.auditToken.base64EncodedString()]
    }

    private final class Backend: HelperProcessTerminationBackend {
        var signalIsAvailable = true
        var consoleUser: uid_t? = 501
        var realUser: uid_t = 501
        var effectiveUser: uid_t = 501
        var current: Result<HelperProcessIdentity, HelperProcessReadFailure>
        var signalCode: Int32? = 0
        var sends = 0
        var afterRead: (() -> Void)?
        init(identity: HelperProcessIdentity) { current = .success(identity) }
        func identity(for pid: Int32) -> Result<HelperProcessIdentity, HelperProcessReadFailure> {
            afterRead?()
            return current
        }
        func sendKill(to identity: HelperProcessIdentity) -> Int32? { sends += 1; return signalCode }
    }

    func testRequestRejectsAnythingExceptCanonicalFixedIdentityFields() {
        let valid = request(identity())
        XCTAssertEqual(HelperProcessIdentity.decodeRequest(valid), identity())
        for key in valid.keys {
            var missing = valid; missing[key] = nil
            XCTAssertNil(HelperProcessIdentity.decodeRequest(missing))
        }
        for key in ["uid", "signal", "path", "command", "arguments", "value"] {
            var extra = valid; extra[key] = 9
            XCTAssertNil(HelperProcessIdentity.decodeRequest(extra))
        }
        for (field, value) in [
            ("_wattsonProtocol", true as Any), ("_wattsonProtocol", 4.5), ("_wattsonProtocol", 5),
            ("op", "kill"), ("pid", true), ("pid", 1), ("pid", 42.5), ("pid", Int64(Int32.max) + 1),
            ("startedAt", "01"), ("startedAt", "+1"), ("startedAt", "0"), ("startedAt", " 1"),
            ("startedAt", UInt64.max), ("startedAt", "18446744073709551616"),
            ("auditToken", identity(pid: 43).auditToken.base64EncodedString()),
            ("auditToken", Data(repeating: 0, count: 31).base64EncodedString()),
            ("auditToken", identity().auditToken.base64EncodedString() + "\n"),
        ] {
            var invalid = valid; invalid[field] = value
            XCTAssertNil(HelperProcessIdentity.decodeRequest(invalid), "\(field): \(value)")
        }
    }

    func testRootOtherUserAndChangedSessionNeverReachSignal() {
        let original = identity()
        for (real, effective, console, expected) in [(uid_t(0), uid_t(0), uid_t(501), uid_t(501)),
                                                    (501, 0, 501, 501), (502, 501, 501, 501),
                                                    (501, 501, 502, 501), (501, 501, 501, 0)] {
            let backend = Backend(identity: original)
            backend.realUser = real; backend.effectiveUser = effective; backend.consoleUser = console
            XCTAssertEqual(HelperProcessTermination.forceQuit(original, expectedUID: expected, backend: backend), .notPermitted)
            XCTAssertEqual(backend.sends, 0)
        }
        for other in [identity(effectiveUID: 0), identity(realUID: 0), identity(effectiveUID: 502), identity(realUID: 502),
                      identity(pid: 1), identity(startedAt: 0)] {
            let backend = Backend(identity: other)
            XCTAssertEqual(HelperProcessTermination.forceQuit(other, expectedUID: 501, backend: backend), .notPermitted)
            XCTAssertEqual(backend.sends, 0)
        }
        let switched = Backend(identity: original)
        switched.afterRead = { switched.consoleUser = 502 }
        XCTAssertEqual(HelperProcessTermination.forceQuit(original, expectedUID: 501, backend: switched), .notPermitted)
        XCTAssertEqual(switched.sends, 0)
    }

    func testExitReusedPIDExecOrCredentialChangeFailsClosed() {
        let original = identity()
        for current in [identity(startedAt: 2), identity(version: 8), identity(effectiveUID: 502), identity(realUID: 502)] {
            let backend = Backend(identity: current)
            XCTAssertEqual(HelperProcessTermination.forceQuit(original, expectedUID: 501, backend: backend), .identityChanged)
            XCTAssertEqual(backend.sends, 0)
        }
        let backend = Backend(identity: original)
        for (failure, expected) in [(HelperProcessReadFailure.alreadyExited, HelperProcessTerminationResult.alreadyExited),
                                    (.notPermitted, .notPermitted), (.unavailable, .unavailable)] {
            backend.current = .failure(failure)
            XCTAssertEqual(HelperProcessTermination.forceQuit(original, expectedUID: 501, backend: backend), expected)
            XCTAssertEqual(backend.sends, 0)
        }
        backend.signalIsAvailable = false
        XCTAssertEqual(HelperProcessTermination.forceQuit(original, expectedUID: 501, backend: backend), .unavailable)
        XCTAssertEqual(backend.sends, 0)
    }

    func testAtomicSignalErrnoAndWorkerExitCodesHaveAllowlistedResults() {
        for (code, expected) in [(Int32(0), HelperProcessTerminationResult.signalSent), (ESRCH, .alreadyExited),
                                 (EPERM, .notPermitted), (EACCES, .notPermitted), (ENOSYS, .unavailable),
                                 (ENOTSUP, .unavailable), (EINVAL, .failed), (-1, .failed)] {
            let backend = Backend(identity: identity()); backend.signalCode = code
            XCTAssertEqual(HelperProcessTermination.forceQuit(identity(), expectedUID: 501, backend: backend), expected)
            XCTAssertEqual(backend.sends, 1)
        }
        for result in [HelperProcessTerminationResult.signalSent, .alreadyExited, .identityChanged, .notPermitted, .unavailable, .failed] {
            XCTAssertEqual(HelperProcessTerminationResult(workerExitCode: result.workerExitCode), result)
            XCTAssertEqual(result.responseLine.last, UInt8(ascii: "\n"))
            let response = try! JSONSerialization.jsonObject(with: result.responseLine) as! [String: Any]
            XCTAssertEqual(response["result"] as? String, result.rawValue)
            XCTAssertEqual(response["ok"] as? Bool, [.signalSent, .alreadyExited].contains(result))
        }
        XCTAssertEqual(HelperProcessTerminationResult(workerExitCode: nil), .failed)
        XCTAssertEqual(HelperProcessTerminationResult(workerExitCode: 9), .failed)
    }

    func testPublicKernelTaskNameTokenUsesTheExpectedUIDAndPIDFields() throws {
        let backend = SystemHelperProcessTerminationBackend()
        let current: HelperProcessIdentity
        switch backend.identity(for: getpid()) {
        case .success(let identity): current = identity
        case .failure: throw XCTSkip("The kernel does not expose this task's public audit token")
        }
        XCTAssertEqual(current.pid, getpid())
        XCTAssertGreaterThan(current.startedAt, 0)
        let token = try XCTUnwrap(HelperProcessAuditToken(data: current.auditToken))
        XCTAssertEqual(token.pid, getpid())
        XCTAssertEqual(token.realUID, getuid())
        XCTAssertEqual(token.effectiveUID, geteuid())
        XCTAssertEqual(current.auditToken.count, 32)
    }

    func testAtomicTerminationSignalsOnlyAnOwnedChildAndAlwaysReapsIt() throws {
        let backend = SystemHelperProcessTerminationBackend()
        guard getuid() != 0, backend.consoleUser == getuid(), backend.signalIsAvailable else {
            throw XCTSkip("Requires the console user and the public identity-bound signal API")
        }
        var arguments: [UnsafeMutablePointer<CChar>?] = [strdup("/bin/sleep"), strdup("30"), nil]
        defer { arguments.forEach { free($0) } }
        var pid: pid_t = 0
        XCTAssertEqual(posix_spawn(&pid, "/bin/sleep", nil, nil, &arguments, environ), 0)
        guard pid > 1 else { return XCTFail("Owned child did not start") }
        var reaped = false
        defer {
            if !reaped {
                var status: Int32 = 0
                var result: pid_t
                repeat { result = waitpid(pid, &status, WNOHANG) } while result < 0 && errno == EINTR
                if result == 0 {
                    _ = kill(pid, SIGKILL)
                    while waitpid(pid, &status, 0) < 0, errno == EINTR {}
                }
            }
        }
        // The child may not have completed exec immediately after spawn.
        var selected: HelperProcessIdentity?
        for _ in 0..<100 {
            if case .success(let identity) = backend.identity(for: pid), identity.belongsToConsoleUser(getuid()) {
                selected = identity
                break
            }
            usleep(1_000)
        }
        guard let selected else { throw XCTSkip("Owned child task name token is unavailable on this system") }
        // A stale incarnation must leave the currently owned child alive.
        let stale = HelperProcessIdentity(pid: pid, startedAt: selected.startedAt &+ 1, auditToken: selected.auditToken)
        XCTAssertEqual(HelperProcessTermination.forceQuit(stale, expectedUID: getuid(), backend: backend), .identityChanged)
        var status: Int32 = 0
        let beforeSignal = waitpid(pid, &status, WNOHANG)
        guard beforeSignal == 0 else {
            reaped = beforeSignal == pid || (beforeSignal < 0 && errno == ECHILD)
            return XCTFail("Owned child exited before the test signal")
        }
        XCTAssertEqual(HelperProcessTermination.forceQuit(selected, expectedUID: getuid(), backend: backend), .signalSent)
        let deadline = DispatchTime.now().uptimeNanoseconds + 2_000_000_000
        while DispatchTime.now().uptimeNanoseconds < deadline {
            let result = waitpid(pid, &status, WNOHANG)
            if result == pid {
                reaped = true
                break
            }
            if result < 0, errno != EINTR { break }
            usleep(1_000)
        }
        XCTAssertTrue(reaped, "Identity-bound signal must terminate the owned child")
        XCTAssertEqual(status & 0x7f, SIGKILL)
    }

    func testTenLongestNamesAndFullPrecisionIdentitiesFitUnchangedFrameBound() throws {
        let escapedName = String(repeating: "\"", count: 32) + String(repeating: "é", count: 32)
        let rows = (1...10).map { index in
            var token = audit_token_t()
            token.val = (UInt32.max, UInt32.max, UInt32.max, UInt32.max, UInt32.max,
                         UInt32(Int32.max - Int32(index)), UInt32.max, UInt32.max)
            let maximalIdentity = HelperProcessIdentity(pid: Int32.max - Int32(index), startedAt: UInt64.max,
                                                        auditToken: withUnsafeBytes(of: token) { Data($0) })
            return HelperEnergyProcess(pid: Int32.max - Int32(index), name: escapedName,
                                energyImpact: Double.greatestFiniteMagnitude, cpuPercent: Double.greatestFiniteMagnitude,
                                idleWakeupsPerSecond: Double.greatestFiniteMagnitude,
                                terminationIdentity: maximalIdentity)
        }
        let line = try XCTUnwrap(HelperTopProcesses.responseLine(processes: rows))
        XCTAssertLessThan(line.count, HelperTopProcesses.maximumResponseBytes)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: line) as? [String: Any])
        let processes = try XCTUnwrap(object["processes"] as? [[String: Any]])
        XCTAssertEqual(processes.count, 10)
        XCTAssertEqual((processes[0]["terminationIdentity"] as? [String: Any])?["startedAt"] as? String, String(UInt64.max))
    }
}
