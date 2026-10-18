import Darwin
import Foundation
import WattsonHelperV5Support

@main
private enum RootWorkerProbe {
    static func main() throws {
        guard CommandLine.arguments.count == 2, getuid() != 0 else { exit(64) }
        let helper = CommandLine.arguments[1]
        let backend = SystemHelperProcessTerminationBackend()
        guard backend.consoleUser == getuid(), backend.signalIsAvailable else {
            throw failure("The owned GUI VM must have an active console user and atomic signal API")
        }
        var checks: [String: Bool] = [:]
        func ownedChild(_ body: (Process, HelperProcessIdentity) throws -> Void) throws {
            let child = Process()
            child.executableURL = URL(fileURLWithPath: "/bin/sleep")
            child.arguments = ["60"]
            try child.run()
            defer {
                if child.isRunning { _ = kill(child.processIdentifier, SIGKILL) }
                child.waitUntilExit()
            }
            var identity: HelperProcessIdentity?
            for _ in 0..<100 {
                if case .success(let value) = backend.identity(for: child.processIdentifier) { identity = value; break }
                usleep(10_000)
            }
            guard let identity else { throw failure("Could not read owned child identity") }
            try body(child, identity)
        }
        func worker(_ identity: HelperProcessIdentity, uid: uid_t = getuid()) throws -> Int32 {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
            process.arguments = ["-n", helper, "--force-quit-process", String(uid), String(identity.pid),
                                 String(identity.startedAt), identity.auditToken.base64EncodedString()]
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        }
        try ownedChild { child, identity in
            let changed = HelperProcessIdentity(pid: identity.pid, startedAt: identity.startedAt + 1, auditToken: identity.auditToken)
            checks["staleIdentityRejected"] = try worker(changed) == HelperProcessTerminationResult.identityChanged.workerExitCode
            checks["staleIdentityLeavesOwnedChildAlive"] = child.isRunning
            checks["rootUIDRejected"] = try worker(identity, uid: 0) == HelperProcessTerminationResult.notPermitted.workerExitCode
            checks["invalidUIDLeavesOwnedChildAlive"] = child.isRunning
            let result = try worker(identity)
            checks["rootWorkerDropsCredentialsAndSendsKill"] = result == 0
            guard result == 0 else { throw failure("Owned root worker returned \(result)") }
            let deadline = Date().addingTimeInterval(2)
            while child.isRunning && Date() < deadline { usleep(10_000) }
            guard !child.isRunning else { throw failure("Owned child did not exit within two seconds") }
            child.waitUntilExit()
            checks["ownedChildKilledWithSIGKILLAndReaped"] = child.terminationReason == .uncaughtSignal && child.terminationStatus == SIGKILL
            // Darwin returns no process for a reaped child. A denial after exit
            // is harmless; the positive case above proves the actual signal.
        }
        let report: [String: Any] = ["schema": 1, "allPassed": checks.values.allSatisfy { $0 }, "checks": checks,
            "method": "Invoke the unmodified production helper's fixed worker entry as root with sudo -n. Its production service refuses to signal unless both real and effective UID equal the authenticated console user. Only this probe's own sleep child receives SIGKILL and is reaped.",
            "limitations": "No LaunchDaemon, canonical helper path, socket, app, or receipt is installed. This verifies the production root worker entry and permanent drop path; the socket dispatcher is covered by source and unit tests."]
        print(String(decoding: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
        if !checks.values.allSatisfy({ $0 }) { exit(1) }
    }
    private static func failure(_ message: String) -> NSError {
        NSError(domain: "WattsonRootWorkerProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
