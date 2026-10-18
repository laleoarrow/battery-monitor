#!/usr/bin/env python3
"""Read-only production-code probe; owns its compiler, binary, pipe and worker."""

import hashlib
import json
import pathlib
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tests"))
from local_runtime import TemporaryDirectory, run


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


helper = ROOT / "Helper/wattson-helper.swift"
source = helper.read_text()
function = "private func socketPollTimeoutMilliseconds" + source.split(
    "private func socketPollTimeoutMilliseconds", 1
)[1].split("private struct SocketRequest", 1)[0]
baseline = pathlib.Path(__file__).with_name("baseline-timeout.swift").read_text().replace(
    "socketPollTimeoutMilliseconds", "baselineSocketPollTimeoutMilliseconds"
)
assert "idleUptimeDeadline: lastActivityUptime + idleTimeoutNanoseconds" in source
assert "!inbox.hasPending, !topProcessesWorker.hasPending" in source
assert "backgroundWorkPending: topProcessesWorker.hasPending" in source

probe = r'''
import Darwin
import Foundation
/* CURRENT_FUNCTION */
/* BASELINE_FUNCTION */
var pipes = [Int32](repeating: 0, count: 2)
guard pipe(&pipes) == 0 else { fatalError("owned pipe failed") }
defer { close(pipes[0]); close(pipes[1]) }
let workerStarted = DispatchSemaphore(value: 0)
let workerFinished = DispatchSemaphore(value: 0)
let sampleStart = DispatchTime.now().uptimeNanoseconds
HelperTopProcesses.credentialLock.lock()
DispatchQueue.global(qos: .utility).async {
    workerStarted.signal()
    _ = HelperTopProcesses.sample()
    workerFinished.signal()
}
guard workerStarted.wait(timeout: .now() + 2) == .success else {
    HelperTopProcesses.credentialLock.unlock()
    fatalError("owned worker did not start")
}
Thread.sleep(forTimeInterval: 12.2)
let heldNanoseconds = DispatchTime.now().uptimeNanoseconds - sampleStart
let pendingBeyondIdle = workerFinished.wait(timeout: .now()) == .timedOut
let expiredIdleDeadline = sampleStart + 12_000_000_000
guard pendingBeyondIdle else {
    HelperTopProcesses.credentialLock.unlock()
    fatalError("sample unexpectedly settled while credential lock held")
}
var measurements: [[String: Any]] = []
for round in 0..<3 {
    for useBaseline in [true, false] {
        let start = DispatchTime.now().uptimeNanoseconds
        let cpuStart = clock()
        var calls = 0
        var originalTimeout: Int32 = -1
        while DispatchTime.now().uptimeNanoseconds - start < 250_000_000 {
            let now = DispatchTime.now().uptimeNanoseconds
            let timeout = useBaseline
                ? baselineSocketPollTimeoutMilliseconds(
                    requestContinuousNow: now, nextReadContinuousDeadline: nil,
                    idleUptimeNow: now, idleUptimeDeadline: expiredIdleDeadline
                )
                : socketPollTimeoutMilliseconds(
                    requestContinuousNow: now, nextReadContinuousDeadline: nil,
                    idleUptimeNow: now, idleUptimeDeadline: expiredIdleDeadline,
                    backgroundWorkPending: true
                )
            originalTimeout = timeout
            var descriptor = pollfd(fd: pipes[0], events: Int16(POLLIN), revents: 0)
            guard Darwin.poll(&descriptor, 1, Int32(timeout)) >= 0 else {
                HelperTopProcesses.credentialLock.unlock()
                fatalError("owned poll failed")
            }
            calls += 1
        }
        measurements.append([
            "round": round,
            "case": useBaseline ? "baseline-production-timeout" : "fixed-production-timeout",
            "productionTimeoutMilliseconds": originalTimeout,
            "pollCalls": calls,
            "wallMilliseconds": Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000,
            "cpuMilliseconds": Double(clock() - cpuStart) / Double(CLOCKS_PER_SEC) * 1_000,
        ])
    }
}
HelperTopProcesses.credentialLock.unlock()
let settledAfterRelease = workerFinished.wait(timeout: .now() + 2) == .success
guard settledAfterRelease else { fatalError("owned sample did not settle after release") }
let now = DispatchTime.now().uptimeNanoseconds
let readerPriority = socketPollTimeoutMilliseconds(
    requestContinuousNow: now, nextReadContinuousDeadline: now + 2_000_000,
    idleUptimeNow: now, idleUptimeDeadline: expiredIdleDeadline,
    backgroundWorkPending: true
)
let result: [String: Any] = [
    "credentialLockHeldMilliseconds": Double(heldNanoseconds) / 1_000_000,
    "realProductionSamplePendingBeyondTwelveSeconds": pendingBeyondIdle,
    "workerSettledAfterLockRelease": settledAfterRelease,
    "readerDeadlinePriorityMilliseconds": readerPriority,
    "measurements": measurements,
]
let encoded = try! JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
print(String(decoding: encoded, as: UTF8.self))
'''.replace("/* CURRENT_FUNCTION */", function).replace("/* BASELINE_FUNCTION */", baseline)

started = time.monotonic()
with TemporaryDirectory(prefix="helper-poll-boundary-") as temporary:
    directory = pathlib.Path(temporary)
    main = directory / "main.swift"
    binary = directory / "helper-poll-probe"
    main.write_text(probe)
    compiled = run([
        "/usr/bin/swiftc", "-O", str(main),
        str(ROOT / "HelperV5/TopProcesses.swift"),
        str(ROOT / "HelperV5/ProcessTermination.swift"), "-o", str(binary),
    ], capture_output=True, text=True, timeout=90)
    assert compiled.returncode == 0, compiled.stderr
    executed = run([str(binary)], capture_output=True, text=True, timeout=30)
    assert executed.returncode == 0, executed.stderr
    result = json.loads(executed.stdout)

result.update({
    "sourceFilesSHA256": {str(path.relative_to(ROOT)): sha256(path) for path in [
        helper, ROOT / "HelperV5/TopProcesses.swift", ROOT / "HelperV5/ProcessTermination.swift",
    ]},
    "scope": "Actual HelperTopProcesses.sample blocked on its actual credential lock; exact production timeout function and real Darwin.poll on an owned empty pipe. No installed helper, socket, app, preferences, credentials, process signal or UI touched.",
    "baselineTimeoutSHA256": sha256(pathlib.Path(__file__).with_name("baseline-timeout.swift")),
    "limitations": "The long lock is deliberately injected. This establishes a rare blocked-worker boundary, not ordinary-sampling CPU usage or whole-app performance. Both baseline and fixed waits are extracted from their exact production functions.",
    "temporaryLifecycle": "tests/local_runtime.py TemporaryDirectory and bounded run own compiler/binary process groups; pipe and worker settle before normal exit; temporary directory removed.",
    "elapsedSeconds": time.monotonic() - started,
})
output = pathlib.Path(__file__).with_name("fixed-reproduction.json")
output.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n")
print(json.dumps(result, indent=2, ensure_ascii=False))
