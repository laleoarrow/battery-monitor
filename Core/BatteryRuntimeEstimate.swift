import Foundation
import IOKit.ps

enum BatteryRuntimeEstimate {
    /// Read the direction and its corresponding minutes from the same internal
    /// battery description. macOS uses -1 while calculating either estimate.
    static func estimate(from descriptions: [[String: Any]]) -> BatteryTimeEstimate? {
        guard let battery = descriptions.first(where: {
            $0[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
                && BatterySampler.optionalBoolValue($0[kIOPSIsPresentKey]) == true
        }),
              let state = battery[kIOPSPowerSourceStateKey] as? String,
              let charging = BatterySampler.optionalBoolValue(battery[kIOPSIsChargingKey])
        else { return nil }

        let charged = BatterySampler.optionalBoolValue(battery[kIOPSIsChargedKey]) == true
        switch state {
        case kIOPSBatteryPowerValue:
            guard !charging && !charged else { return nil }
            return .remaining(validMinutes(battery[kIOPSTimeToEmptyKey]))
        case kIOPSACPowerValue:
            guard !(charging && charged) else { return nil }
            if charging { return .charging(validMinutes(battery[kIOPSTimeToFullChargeKey])) }
            return charged ? .full : .notCharging
        default:
            return nil
        }
    }

    static func systemEstimate() -> BatteryTimeEstimate? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        let descriptions = sources.compactMap { source in
            IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any]
        }
        return estimate(from: descriptions)
    }

    static func applying(
        to snapshot: PowerSnapshot,
        readEstimate: () -> BatteryTimeEstimate? = BatteryRuntimeEstimate.systemEstimate
    ) -> PowerSnapshot {
        var fresh = snapshot
        fresh.batteryTimeEstimate = nil
        guard let estimate = readEstimate() else { return fresh }
        switch estimate {
        case let .remaining(minutes):
            guard !snapshot.plugged else { return fresh }
            fresh.batteryTimeEstimate = .remaining(validMinutes(minutes))
        case let .charging(minutes):
            guard snapshot.plugged else { return fresh }
            fresh.batteryTimeEstimate = snapshot.state == .mixedSupply
                ? .notCharging : .charging(validMinutes(minutes))
        case .full, .notCharging:
            guard snapshot.plugged else { return fresh }
            fresh.batteryTimeEstimate = snapshot.state == .mixedSupply ? .notCharging : estimate
        }
        return fresh
    }

    private static func validMinutes(_ value: Any?) -> Int? {
        guard let minutes = BatterySampler.optionalIntValue(value),
              (0...Int(Int32.max)).contains(minutes) else { return nil }
        return minutes
    }
}
