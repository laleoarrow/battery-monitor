import Foundation
import IOKit.ps

enum BatteryRuntimeEstimate {
    /// Time to Empty is a signed integer in minutes, valid only for a present
    /// battery running on its own power. macOS uses -1 while calculating.
    /// Select the internal battery so a UPS cannot supply its estimate.
    static func minutes(from descriptions: [[String: Any]]) -> Int? {
        guard let battery = descriptions.first(where: {
            $0[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
                && BatterySampler.optionalBoolValue($0[kIOPSIsPresentKey]) == true
                && $0[kIOPSPowerSourceStateKey] as? String == kIOPSBatteryPowerValue
                && BatterySampler.optionalBoolValue($0[kIOPSIsChargingKey]) == false
        }),
              let minutes = BatterySampler.optionalIntValue(battery[kIOPSTimeToEmptyKey]),
              (0...Int(Int32.max)).contains(minutes) else { return nil }
        return minutes
    }

    static func systemMinutes() -> Int? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        let descriptions = sources.compactMap { source in
            IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any]
        }
        return minutes(from: descriptions)
    }

    static func applying(
        to snapshot: PowerSnapshot,
        readMinutes: () -> Int? = BatteryRuntimeEstimate.systemMinutes
    ) -> PowerSnapshot {
        var fresh = snapshot
        fresh.estimatedRuntimeMinutes = nil
        guard snapshot.state == .onBattery,
              let minutes = readMinutes(),
              (0...Int(Int32.max)).contains(minutes) else { return fresh }
        fresh.estimatedRuntimeMinutes = minutes
        return fresh
    }
}
