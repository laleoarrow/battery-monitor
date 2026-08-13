import Foundation
import IOKit
import os

enum BatterySampler {
    enum SampleResult {
        case absent
        case temporarilyUnavailable
        case snapshot(PowerSnapshot)
    }

    private static let maxBatteryCapacityUnits = 100_000
    private static let maxBatteryCycleCount = 100_000
    private static let maxBatteryVoltageMillivolts = 50_000
    private static let maxBatteryPowerWatts = 1_000.0
    private static let maxTelemetryMilliwatts = 1_000_000

    static func sample() -> PowerSnapshot? {
        guard case let .snapshot(snapshot) = sampleResult() else { return nil }
        return snapshot
    }

    static func sampleResult() -> SampleResult {
        let result = sampleResult(
            from: batteryProperties(),
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
        guard case let .snapshot(snapshot) = result else { return result }

        // A conservation break means a field was parsed wrong. Say so loudly
        // rather than rendering a plausible lie.
        if abs(snapshot.conservationError) > 2.0 {
            os_log("conservation broken by %{public}.2f W — adapter=%{public}.2f battery=%{public}.2f system=%{public}.2f",
                   log: OSLog(subsystem: "com.leoarrow.wattson", category: "sampler"),
                   type: .error,
                   snapshot.conservationError, snapshot.adapterW, snapshot.batteryW, snapshot.systemW)
        }

        return .snapshot(snapshot)
    }

    static func sampleResult(
        from props: [String: Any]?,
        lowPowerMode: Bool
    ) -> SampleResult {
        guard let props else { return .absent }
        guard let snapshot = resolvedSnapshot(
            from: props,
            lowPowerMode: lowPowerMode
        ) else { return .temporarilyUnavailable }
        return .snapshot(snapshot)
    }

    static func resolvedSnapshot(
        from props: [String: Any],
        lowPowerMode: Bool
    ) -> PowerSnapshot? {
        guard let percent = resolvedBatteryPercent(
                  currentCapacity: props["CurrentCapacity"],
                  maxCapacity: props["MaxCapacity"]
              ),
              let plugged = optionalBoolValue(props["ExternalConnected"]) else {
            return nil
        }

        var snapshot = PowerSnapshot()
        snapshot.percent = percent
        snapshot.plugged = plugged
        let batteryIsCharging = optionalBoolValue(props["IsCharging"]) ?? false
        snapshot.cycleCount = resolvedCycleCount(props["CycleCount"])
        snapshot.temperatureC = resolvedTemperatureC(
            temperatureRaw: optionalIntValue(props["Temperature"]),
            virtualTemperatureRaw: optionalIntValue(props["VirtualTemperature"])
        )

        let voltage = validBatteryVoltage(optionalIntValue(props["Voltage"]))
        let instantAmperage = optionalIntValue(props["InstantAmperage"])
        let amperage = optionalIntValue(props["Amperage"])
        let telemetry = parsedPowerTelemetry(props["PowerTelemetryData"])
        let instantBatteryW = resolvedInstantBatteryW(
            voltage: voltage,
            instantAmperage: instantAmperage,
            amperage: amperage
        )
        let fallbackBatteryW = resolvedFallbackBatteryW(
            voltage: voltage,
            amperage: amperage
        )

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
            fallbackBatteryW: fallbackBatteryW,
            instantBatteryW: instantBatteryW
        )
        snapshot.adapterW = power.adapterW
        snapshot.batteryW = power.batteryW
        snapshot.systemW = power.systemW

        snapshot.lowPowerMode = lowPowerMode
        return snapshot
    }

    /// Apple silicon publishes CurrentCapacity/MaxCapacity as a percentage pair,
    /// while Intel firmware publishes the same fields in mAh. Normalize the
    /// ratio from the pair. `CurrentCapacity` alone has no reliable unit: an
    /// Intel battery near empty can legitimately publish a two-digit mAh value,
    /// so treating a missing maximum as a percentage would invent a plausible
    /// but incorrect reading.
    static func resolvedBatteryPercent(
        currentCapacity rawCurrent: Any?,
        maxCapacity rawMaximum: Any?
    ) -> Int? {
        guard let current = optionalIntValue(rawCurrent),
              (0...maxBatteryCapacityUnits).contains(current) else { return nil }

        guard let maximum = optionalIntValue(rawMaximum),
              (1...maxBatteryCapacityUnits).contains(maximum) else { return nil }

        let percent = (Double(current) * 100.0 / Double(maximum)).rounded()
        guard percent.isFinite else { return nil }
        return Int(min(max(percent, 0), 100))
    }

    static func resolvedInstantBatteryW(
        voltage: Int?,
        instantAmperage: Int?,
        amperage: Int?
    ) -> Double? {
        guard let voltage, voltage > 0 else { return nil }
        guard let current = validBatteryCurrent(instantAmperage)
                ?? validBatteryCurrent(amperage) else { return nil }
        let watts = Double(voltage) * Double(current) / 1_000_000.0
        guard watts.isFinite, abs(watts) <= maxBatteryPowerWatts else { return nil }
        return watts
    }

    static func resolvedFallbackBatteryW(
        voltage: Int?,
        amperage: Int?
    ) -> Double {
        resolvedInstantBatteryW(
            voltage: voltage,
            instantAmperage: nil,
            amperage: amperage
        ) ?? 0
    }

    private static func validBatteryCurrent(_ current: Int?) -> Int? {
        guard let current,
              current != -1,
              (-100_000...100_000).contains(current) else { return nil }
        return current
    }

    static func validBatteryVoltage(_ voltage: Int?) -> Int? {
        guard let voltage,
              (1...maxBatteryVoltageMillivolts).contains(voltage) else { return nil }
        return voltage
    }

    private static func validTelemetryMilliwatts(
        _ value: Int?,
        signed: Bool
    ) -> Int? {
        guard let value else { return nil }
        let validRange = signed
            ? -maxTelemetryMilliwatts...maxTelemetryMilliwatts
            : 0...maxTelemetryMilliwatts
        return validRange.contains(value) ? value : nil
    }

    static func parsedPowerTelemetry(_ raw: Any?) -> [String: Int] {
        guard let dict = raw as? [String: Any] else { return [:] }
        var values: [String: Int] = [:]
        if let source = validTelemetryMilliwatts(
            optionalIntValue(dict["SystemPowerIn"]), signed: false
        ) {
            values["SystemPowerIn"] = source
        }
        for key in ["SystemLoad", "BatteryPower"] {
            if let value = validTelemetryMilliwatts(
                optionalIntValue(dict[key]), signed: true
            ) {
                values[key] = value
            }
        }
        return values
    }

    static func resolvedPower(
        plugged: Bool,
        chargingHint: Bool,
        systemPowerIn: Int?,
        systemLoad: Int?,
        batteryPower: Int?,
        fallbackBatteryW: Double,
        instantBatteryW: Double? = nil
    ) -> (adapterW: Double, batteryW: Double, systemW: Double) {
        // SystemPowerIn is a source and has no observed sign drift. A negative
        // value is invalid/missing, not a real zero-watt adapter sample.
        let adapter = validTelemetryMilliwatts(
            systemPowerIn, signed: false
        ).map { Double($0) / 1000.0 }
        let system = validTelemetryMilliwatts(
            systemLoad, signed: true
        ).map(normalizedSystemLoad)
        let fallbackMagnitude = fallbackBatteryW.isFinite
            && abs(fallbackBatteryW) <= maxBatteryPowerWatts
            ? abs(fallbackBatteryW)
            : 0
        let batteryMagnitude = validTelemetryMilliwatts(
            batteryPower, signed: true
        ).map { abs(Double($0)) / 1000.0 }
            ?? fallbackMagnitude

        if !plugged {
            let systemW = system ?? batteryMagnitude
            return (0, systemW > 0 ? -systemW : 0, systemW)
        }

        // AppleSmartBattery can report ExternalConnected immediately while
        // SystemPowerIn remains missing/zero for roughly one telemetry cycle.
        // In that narrow transition, signed V×I supplies the battery branch.
        // A missing/zero load gets the smallest conservative placeholder until
        // the same sampling pass merges live PSTR and rebuilds the adapter.
        if (adapter == nil || adapter == 0),
           let instantBatteryW,
           instantBatteryW.isFinite,
           abs(instantBatteryW) <= maxBatteryPowerWatts {
            let transitionSystemW = system.flatMap { $0 > 0 ? $0 : nil }
                ?? max(-instantBatteryW, 0)
            let batteryW = min(
                max(instantBatteryW, -transitionSystemW),
                maxBatteryPowerWatts - transitionSystemW
            )
            return (transitionSystemW + batteryW, batteryW, transitionSystemW)
        }

        if let adapter, let system {
            // This is the only direction source robust to stale IsCharging and
            // BatteryPower sign flips. Keeping the exact difference also keeps
            // conservation exact; PowerSnapshot.state owns the ±0.3 W deadband.
            return (adapter, adapter - system, system)
        }

        if let adapter {
            let batteryW: Double
            if let instantBatteryW,
               instantBatteryW.isFinite,
               abs(instantBatteryW) <= maxBatteryPowerWatts {
                // With a fresh source total but no load total, signed V×I is
                // the only direction-bearing observation. Clamp it only far
                // enough to keep the reconstructed system branch physical.
                batteryW = min(
                    max(instantBatteryW, adapter - maxBatteryPowerWatts),
                    adapter
                )
            } else {
                batteryW = chargingHint
                    ? min(batteryMagnitude, adapter)
                    : max(-batteryMagnitude, adapter - maxBatteryPowerWatts)
            }
            return (adapter, batteryW, adapter - batteryW)
        }

        if let system {
            let batteryW = chargingHint
                ? min(batteryMagnitude, maxBatteryPowerWatts - system)
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
            value.isFinite && (0...maxBatteryPowerWatts).contains(value) ? value : nil
        }
        let liveSystem = systemW.flatMap { value in
            value.isFinite && (0...maxBatteryPowerWatts).contains(value) ? value : nil
        }

        // `HelperClient` applies the same bounds, but keep this pure merge safe
        // when it is reused by tests or a future sensor backend. A corrupt stale
        // battery branch must not turn one valid live branch into NaN or an
        // impossible multi-kilowatt reconstructed total.
        let staleBatteryW = snapshot.batteryW.isFinite
            && abs(snapshot.batteryW) <= maxBatteryPowerWatts
            ? snapshot.batteryW
            : 0

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
            // impossible cases where the stale discharge exceeds total load or
            // a stale charge would reconstruct an adapter above the sensor cap.
            fresh.systemW = liveSystem
            fresh.batteryW = min(
                max(staleBatteryW, -liveSystem),
                maxBatteryPowerWatts - liveSystem
            )
            fresh.adapterW = liveSystem + fresh.batteryW
        } else if let liveAdapter {
            fresh.adapterW = liveAdapter
            fresh.batteryW = max(
                min(staleBatteryW, liveAdapter),
                liveAdapter - maxBatteryPowerWatts
            )
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
            "CurrentCapacity", "MaxCapacity", "ExternalConnected", "IsCharging", "CycleCount",
            "Temperature", "VirtualTemperature", "Voltage", "InstantAmperage",
            "Amperage", "PowerTelemetryData",
        ]
        var props: [String: Any] = [:]
        for key in keys {
            if let value = IORegistryEntryCreateCFProperty(
                service, key as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue() {
                props[key] = value
            }
        }

        return props
    }

    // Values are raw two's-complement bit patterns, so negative currents
    // surface as huge unsigned numbers. Battery values never legitimately
    // exceed Int32.max, so anything in the 32-bit wraparound range is negative.
    static func optionalIntValue(_ raw: Any?) -> Int? {
        guard let number = raw as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              !CFNumberIsFloatType(number) else { return nil }
        // IOKit may publish a negative battery value as either UInt32 or
        // UInt64 two's-complement. NSNumber.int64Value preserves the latter;
        // normalize the former explicitly before applying field-level bounds.
        var value = number.int64Value
        if value > Int64(Int32.max), value <= Int64(UInt32.max) {
            value -= Int64(UInt32.max) + 1
        }
        return Int(value)
    }

    static func optionalBoolValue(_ raw: Any?) -> Bool? {
        guard let number = raw as? NSNumber else { return nil }
        if CFGetTypeID(number) == CFBooleanGetTypeID() {
            return number.boolValue
        }
        guard let value = optionalIntValue(number), value == 0 || value == 1 else {
            return nil
        }
        return value == 1
    }

    static func resolvedCycleCount(_ raw: Any?) -> Int {
        guard let value = optionalIntValue(raw),
              (0...maxBatteryCycleCount).contains(value) else { return 0 }
        return value
    }

}
