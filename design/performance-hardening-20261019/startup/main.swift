import Darwin
import Foundation

// One measured production acquisition per process. No AppKit, helper request,
// preferences, app registration, or battery values are emitted by this probe.
func processCPUNanoseconds() -> UInt64 {
    var usage = rusage()
    guard getrusage(RUSAGE_SELF, &usage) == 0 else { return 0 }
    let seconds = usage.ru_utime.tv_sec + usage.ru_stime.tv_sec
    let microseconds = usage.ru_utime.tv_usec + usage.ru_stime.tv_usec
    return UInt64(seconds) * 1_000_000_000 + UInt64(microseconds) * 1_000
}

let onMainThread = Thread.isMainThread
let cpuBefore = processCPUNanoseconds()
let started = clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)
let result = BatterySampler.sampleResult()
let ended = clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)
let cpuAfter = processCPUNanoseconds()
let outcome: String
switch result {
case .absent: outcome = "absent"
case .temporarilyUnavailable: outcome = "temporarilyUnavailable"
case .snapshot: outcome = "snapshot"
}
let output: [String: Any] = [
    "pid": ProcessInfo.processInfo.processIdentifier,
    "mainThread": onMainThread,
    "firstSamplerCall": true,
    "elapsedNanoseconds": ended - started,
    "processCPUNanoseconds": cpuAfter - cpuBefore,
    "outcome": outcome,
]
let data = try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])
FileHandle.standardOutput.write(data + Data([10]))
