import Foundation
import IOKit
import os

enum BatterySampler {
    static func sample() -> PowerSnapshot? {
        guard let props = batteryProperties() else { return nil }

        var snapshot = PowerSnapshot()
        snapshot.percent = intValue(props["CurrentCapacity"])
        snapshot.plugged = boolValue(props["ExternalConnected"])
        snapshot.cycleCount = intValue(props["CycleCount"])
        snapshot.temperatureC = Double(intValue(props["Temperature"])) / 100.0

        let voltage = intValue(props["Voltage"])
        let amperage = intValue(props["Amperage"])
        let telemetry = intMap(props["PowerTelemetryData"])

        // Signed. Positive flows into the battery, negative flows out.
        if let raw = telemetry["BatteryPower"] {
            snapshot.batteryW = Double(raw) / 1000.0
        } else {
            snapshot.batteryW = Double(voltage * amperage) / 1_000_000.0
        }

        if let load = telemetry["SystemLoad"] {
            snapshot.systemW = max(Double(load) / 1000.0, 0)
        } else {
            snapshot.systemW = abs(Double(voltage * amperage) / 1_000_000.0)
        }

        // The adapter covers whatever the battery is not supplying.
        if snapshot.plugged {
            if let systemIn = telemetry["SystemPowerIn"] {
                snapshot.adapterW = max(Double(systemIn) / 1000.0, 0)
            } else {
                snapshot.adapterW = max(snapshot.systemW + snapshot.batteryW, 0)
            }
        } else {
            snapshot.adapterW = 0
        }

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

    private static func batteryProperties() -> [String: Any]? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }
        var propsRef: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let props = propsRef?.takeRetainedValue() as? [String: Any] else {
            return nil
        }
        return props
    }

    // Values are raw two's-complement bit patterns, so negative currents
    // surface as huge unsigned numbers. Battery values never legitimately
    // exceed Int32.max, so anything in the 32-bit wraparound range is negative.
    private static func intValue(_ raw: Any?) -> Int {
        guard let number = raw as? NSNumber else { return 0 }
        var value = number.int64Value
        if value > Int64(Int32.max), value <= Int64(UInt32.max) {
            value -= Int64(UInt32.max) + 1
        }
        return Int(value)
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
