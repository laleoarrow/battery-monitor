import Foundation
import IOKit
import os

enum BatterySampler {
    static func sample() -> PowerSnapshot? {
        guard let props = batteryProperties() else { return nil }

        var snapshot = PowerSnapshot()
        snapshot.percent = intValue(props["CurrentCapacity"])
        snapshot.plugged = boolValue(props["ExternalConnected"])
        let batteryIsCharging = boolValue(props["IsCharging"])
        snapshot.cycleCount = intValue(props["CycleCount"])
        snapshot.temperatureC = resolvedTemperatureC(
            temperatureRaw: optionalIntValue(props["Temperature"]),
            virtualTemperatureRaw: optionalIntValue(props["VirtualTemperature"])
        )

        let voltage = intValue(props["Voltage"])
        let amperage = intValue(props["Amperage"])
        let telemetry = intMap(props["PowerTelemetryData"])

        // `IsCharging` can remain true while an undersized adapter is being
        // supplemented by the battery. Firmware has also emitted both raw sign
        // conventions for BatteryPower/SystemLoad. When the source and sink
        // totals exist, resolve all three values together so every degraded
        // field combination still obeys the Core conservation model.
        let power = resolvedPower(
            plugged: snapshot.plugged,
            chargingHint: batteryIsCharging,
            systemPowerIn: telemetry["SystemPowerIn"],
            systemLoad: telemetry["SystemLoad"],
            batteryPower: telemetry["BatteryPower"],
            fallbackBatteryW: Double(voltage * amperage) / 1_000_000.0
        )
        snapshot.adapterW = power.adapterW
        snapshot.batteryW = power.batteryW
        snapshot.systemW = power.systemW

        snapshot.lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

        // A conservation break means a field was parsed wrong. Say so loudly
        // rather than rendering a plausible lie.
        if abs(snapshot.conservationError) > 2.0 {
            os_log("conservation broken by %{public}.2f W — adapter=%{public}.2f battery=%{public}.2f system=%{public}.2f",
                   log: OSLog(subsystem: "com.leoarrow.wattson", category: "sampler"),
                   type: .error,
                   snapshot.conservationError, snapshot.adapterW, snapshot.batteryW, snapshot.systemW)
        }

        return snapshot
    }

    static func resolvedPower(
        plugged: Bool,
        chargingHint: Bool,
        systemPowerIn: Int?,
        systemLoad: Int?,
        batteryPower: Int?,
        fallbackBatteryW: Double
    ) -> (adapterW: Double, batteryW: Double, systemW: Double) {
        // SystemPowerIn is a source and has no observed sign drift. A negative
        // value is invalid/missing, not a real zero-watt adapter sample.
        let adapter = systemPowerIn.flatMap { raw in
            raw >= 0 ? Double(raw) / 1000.0 : nil
        }
        let system = systemLoad.map(normalizedSystemLoad)
        let batteryMagnitude = batteryPower.map { abs(Double($0)) / 1000.0 }
            ?? abs(fallbackBatteryW)

        if !plugged {
            let systemW = system ?? batteryMagnitude
            return (0, systemW > 0 ? -systemW : 0, systemW)
        }

        if let adapter, let system {
            // This is the only direction source robust to stale IsCharging and
            // BatteryPower sign flips. Keeping the exact difference also keeps
            // conservation exact; PowerSnapshot.state owns the ±0.3 W deadband.
            return (adapter, adapter - system, system)
        }

        if let adapter {
            let batteryW = chargingHint
                ? min(batteryMagnitude, adapter)
                : -batteryMagnitude
            return (adapter, batteryW, adapter - batteryW)
        }

        if let system {
            let batteryW = chargingHint
                ? batteryMagnitude
                : -min(batteryMagnitude, system)
            return (system + batteryW, batteryW, system)
        }

        // Older firmware can omit all three telemetry totals. Preserve a
        // conservative, internally consistent estimate from V×A rather than
        // making the app disappear at startup; the charging flag is only a
        // hint in this last-resort path.
        if chargingHint {
            return (batteryMagnitude, batteryMagnitude, 0)
        }
        return (0, batteryMagnitude > 0 ? -batteryMagnitude : 0, batteryMagnitude)
    }

    static func normalizedSystemLoad(_ raw: Int) -> Double {
        abs(Double(raw)) / 1000.0
    }

    /// Refresh the whole-machine branch from SMC while retaining the battery
    /// branch from AppleSmartBattery. PDTR and PSTR are published on different
    /// hardware sample boundaries, so subtracting one from the other invents
    /// large charge/discharge spikes whenever system load changes. Rebuilding
    /// the third branch around the last coherent battery value stays live and
    /// preserves the conservation model without that false direction change.
    static func resolvedLivePower(
        snapshot: PowerSnapshot,
        adapterW: Double?,
        systemW: Double?
    ) -> PowerSnapshot {
        let liveAdapter = adapterW.flatMap { value in
            value.isFinite && value >= 0 ? value : nil
        }
        let liveSystem = systemW.flatMap { value in
            value.isFinite && value >= 0 ? value : nil
        }

        var fresh = snapshot
        if !snapshot.plugged {
            guard let liveSystem else { return snapshot }
            fresh.adapterW = 0
            fresh.systemW = liveSystem
            fresh.batteryW = liveSystem > 0 ? -liveSystem : 0
            return fresh
        }

        if let liveSystem {
            // A connected Mac can still draw from its battery. Clamp only the
            // impossible case where the stale discharge exceeds total load.
            fresh.systemW = liveSystem
            fresh.batteryW = max(snapshot.batteryW, -liveSystem)
            fresh.adapterW = liveSystem + fresh.batteryW
        } else if let liveAdapter {
            fresh.adapterW = liveAdapter
            fresh.batteryW = min(snapshot.batteryW, liveAdapter)
            fresh.systemW = liveAdapter - fresh.batteryW
        } else {
            return snapshot
        }
        return fresh
    }

    /// AppleSmartBattery's physical `Temperature` is deci-Kelvin, while
    /// `VirtualTemperature` is centi-Celsius on hardware that only publishes
    /// the synthesized sensor. Prefer the physical value, but do not turn a
    /// missing or firmware-sentinel reading into a plausible temperature.
    static func resolvedTemperatureC(
        temperatureRaw: Int?,
        virtualTemperatureRaw: Int?
    ) -> Double? {
        if let raw = temperatureRaw, raw != 0, raw != -1 {
            let celsius = Double(raw) / 10.0 - 273.15
            if (-100.0...150.0).contains(celsius) { return celsius }
        }

        if let raw = virtualTemperatureRaw, raw != -1 {
            let celsius = Double(raw) / 100.0
            if (-100.0...150.0).contains(celsius) { return celsius }
        }

        return nil
    }

    private static func batteryProperties() -> [String: Any]? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }

        // Reading the whole registry dictionary also materializes large,
        // unrelated firmware blobs. Fetching just the fields used below keeps
        // sampling responsive and lets one malformed optional field degrade
        // independently.
        let keys = [
            "CurrentCapacity", "ExternalConnected", "IsCharging", "CycleCount",
            "Temperature", "VirtualTemperature", "Voltage", "Amperage",
            "PowerTelemetryData",
        ]
        var props: [String: Any] = [:]
        for key in keys {
            if let value = IORegistryEntryCreateCFProperty(
                service, key as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue() {
                props[key] = value
            }
        }

        // Optional telemetry and temperature may degrade independently, but a
        // partial dictionary without identity/source state must not replace the
        // last good snapshot with a plausible-looking 0% battery-only sample.
        guard props["CurrentCapacity"] is NSNumber,
              props["ExternalConnected"] is NSNumber else { return nil }
        return props
    }

    // Values are raw two's-complement bit patterns, so negative currents
    // surface as huge unsigned numbers. Battery values never legitimately
    // exceed Int32.max, so anything in the 32-bit wraparound range is negative.
    private static func optionalIntValue(_ raw: Any?) -> Int? {
        guard let number = raw as? NSNumber else { return nil }
        var value = number.int64Value
        if value > Int64(Int32.max), value <= Int64(UInt32.max) {
            value -= Int64(UInt32.max) + 1
        }
        return Int(value)
    }

    private static func intValue(_ raw: Any?) -> Int {
        optionalIntValue(raw) ?? 0
    }

    private static func boolValue(_ raw: Any?) -> Bool {
        if let flag = raw as? Bool { return flag }
        return (raw as? NSNumber)?.boolValue ?? false
    }

    private static func intMap(_ raw: Any?) -> [String: Int] {
        guard let dict = raw as? [String: Any] else { return [:] }
        var values: [String: Int] = [:]
        for (key, value) in dict {
            values[key] = intValue(value)
        }
        return values
    }
}
