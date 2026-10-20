import Darwin
import Foundation

// This CLI wraps only real, read-only production calls. It emits durations,
// counts and availability, never battery values, process names or process IDs.
private func now() -> UInt64 { clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW) }
private func cpu(_ who: Int32 = RUSAGE_SELF) -> UInt64 {
    var usage = rusage()
    precondition(getrusage(who, &usage) == 0)
    return UInt64(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) * 1_000_000_000
        + UInt64(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) * 1_000
}
private func emit(_ value: [String: Any]) {
    let data = try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    FileHandle.standardOutput.write(data + Data([10]))
}
private final class Measurements {
    private let lock = NSLock()
    private var rows: [[String: Any]] = []
    func measured<T>(_ stage: String, _ action: () -> T) -> T {
        let started = now()
        let result = action()
        let duration = now() - started
        lock.lock()
        rows.append(["stage": stage, "wallNanoseconds": duration])
        lock.unlock()
        return result
    }
    func drain() -> [[String: Any]] {
        lock.lock()
        defer { lock.unlock() }
        let result = rows
        rows.removeAll(keepingCapacity: true)
        return result
    }
}
private struct MeasuredRawReader: AppleSmartBatteryPowerRawSnapshotReading {
    let measurements: Measurements
    func readAllowlistedProperties(_ keys: [String]) -> AppleSmartBatteryPowerRawSnapshot {
        measurements.measured("registry_allowlisted_read") {
            SystemAppleSmartBatteryPowerRawSnapshotReader().readAllowlistedProperties(keys)
        }
    }
}
private final class MeasuredBatteryReader: AppleSmartBatteryPowerObservationReading {
    let measurements: Measurements
    let reader: AppleSmartBatteryPowerObservationReader
    init(measurements: Measurements, health: SystemBatteryHealth) {
        self.measurements = measurements
        reader = AppleSmartBatteryPowerObservationReader(
            systemBatteryReading: {
                measurements.measured("iops_system_read") { BatteryRuntimeEstimate.systemReading() }
            },
            batteryHealthPercent: {
                measurements.measured("health_cache_read") { health.currentPercent() }
            },
            backend: MeasuredRawReader(measurements: measurements)
        )
    }
    func readRuntimeSample() -> AppleSmartBatteryPowerSample {
        measurements.measured("battery_runtime_branch") { reader.readRuntimeSample() }
    }
    func resetFreshness() { reader.resetFreshness() }
    func resetBatteryTimeHistory() { reader.resetBatteryTimeHistory() }
}

private let arguments = Array(CommandLine.arguments.dropFirst())
precondition(arguments == ["--warmup"] || arguments == ["--measure"])
private let measurements = Measurements()
// Keep the production cache and fixed live reader. This wrapper counts reads;
// utility execution is equivalent to the production default's private queue.
private let healthQueue = DispatchQueue(label: "Wattson.Performance.Health", qos: .utility)
private let health = SystemBatteryHealth(read: { completion in
    healthQueue.async {
        completion(measurements.measured("health_live_profiler") {
            SystemBatteryHealth.readLivePercent()
        })
    }
})
private let coldStarted = now()
private let coldCPU = cpu()
private let coldChildrenCPU = cpu(RUSAGE_CHILDREN)
private let initialHealth = health.currentPercent()
private let firstReturn = now() - coldStarted
private let firstReturnCPU = cpu() - coldCPU
private var healthAvailable = initialHealth != nil
while !healthAvailable && now() - coldStarted < 8_500_000_000 {
    usleep(10_000)
    healthAvailable = health.currentPercent() != nil
}
healthQueue.sync {}
emit([
    "stage": "health_cold", "available": healthAvailable,
    "firstCallReturnedCachedValue": initialHealth != nil,
    "firstCallNanoseconds": firstReturn,
    "firstCallCPUNanoseconds": firstReturnCPU,
    "completionWallNanoseconds": now() - coldStarted,
    "selfCPUNanoseconds": cpu() - coldCPU,
    "directChildrenCPUNanoseconds": cpu(RUSAGE_CHILDREN) - coldChildrenCPU,
    "calls": measurements.drain(),
])

private let reader = MeasuredBatteryReader(measurements: measurements, health: health)
private let runtime = PowerObservationRuntimeController(
    batteryReader: reader,
    helperObservation: { sequence in
        measurements.measured("helper_v5_ipc") {
            HelperClient.powerObservation(clientSequence: sequence)
        }
    },
    clock: { now() },
    shadowRecorder: PrivacySafePowerObservationShadowRecorder()
)
private let samplingQueue = DispatchQueue(label: "Wattson.Performance.Sample", qos: .userInitiated)
private let iterations = arguments == ["--warmup"] ? 2 : 32
private let allStarted = now()
for index in 0..<iterations {
    let target = allStarted + UInt64(index) * 2_000_000_000
    if now() < target { usleep(useconds_t((target - now()) / 1_000)) }
    let completed = DispatchSemaphore(value: 0)
    samplingQueue.async {
        let started = now()
        let cpuStarted = cpu()
        let result = runtime.sample(event: .normal)
        let duration = now() - started
        let cpuDuration = cpu() - cpuStarted
        let helperOutcome: String
        switch result.helperResult {
        case .v5: helperOutcome = "v5"
        case .legacyV4: helperOutcome = "legacy_v4"
        case .failed: helperOutcome = "failed"
        }
        emit([
            "stage": "runtime_sample", "iteration": index + 1,
            "wallNanoseconds": duration, "selfCPUNanoseconds": cpuDuration,
            "snapshotAvailable": result.visibleSnapshot != nil,
            "helperOutcome": helperOutcome, "mainThread": Thread.isMainThread,
            "calls": measurements.drain(),
        ])
        completed.signal()
    }
    precondition(completed.wait(timeout: .now() + 8) == .success)
}

if arguments == ["--measure"] {
    // A genuine cached read; no mocked health percentage or clock is used.
    for batch in 1...10 {
        let started = now()
        let cpuStarted = cpu()
        for _ in 0..<10_000 { _ = health.currentPercent() }
        emit([
            "stage": "health_hot_batch", "batch": batch, "iterations": 10_000,
            "wallNanoseconds": now() - started,
            "selfCPUNanoseconds": cpu() - cpuStarted,
        ])
    }
    for index in 1...3 {
        let started = now()
        let cpuStarted = cpu()
        let result = HelperClient.topProcesses()
        let count: Int
        switch result {
        case let .ready(rows): count = rows.count
        case .loading, .unavailable: count = -1
        }
        emit([
            "stage": "top_processes_read", "iteration": index,
            "wallNanoseconds": now() - started,
            "selfCPUNanoseconds": cpu() - cpuStarted,
            "returnedRowCount": count,
        ])
        if index < 3 { usleep(2_000_000) }
    }
    emit(["stage": "end", "remainingHealthLiveReads": measurements.drain()])
}
