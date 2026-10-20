import Foundation
import IOKit.ps

struct SystemBatteryReading {
    var percent: Int? = nil
    var timeEstimate: BatteryTimeEstimate? = nil

    var chargingState: BatteryChargingState? {
        switch timeEstimate {
        case .charging: return .charging
        case .full: return .full
        case .notCharging: return .notCharging
        default: return nil
        }
    }
}

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
            guard !charging else { return nil }
            // The charged flag can lag a power-source change. Wait for a
            // coherent description rather than trusting its old minute value.
            if charged { return .remaining(nil) }
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
        systemReading().timeEstimate
    }

    /// One public IOPS snapshot supplies the user-visible charge level and
    /// charging state. Firmware capacity ratios are only a fallback.
    static func systemReading() -> SystemBatteryReading {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return .init() }
        let descriptions = sources.compactMap { source in
            IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any]
        }
        return reading(from: descriptions)
    }

    static func reading(from descriptions: [[String: Any]]) -> SystemBatteryReading {
        let battery = descriptions.first {
            $0[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
                && BatterySampler.optionalBoolValue($0[kIOPSIsPresentKey]) == true
        }
        return SystemBatteryReading(
            percent: BatterySampler.resolvedBatteryPercent(
                currentCapacity: battery?[kIOPSCurrentCapacityKey],
                maxCapacity: battery?[kIOPSMaxCapacityKey]
            ),
            timeEstimate: estimate(from: descriptions)
        )
    }

    static func applying(
        to snapshot: PowerSnapshot,
        readEstimate: () -> BatteryTimeEstimate? = BatteryRuntimeEstimate.systemEstimate
    ) -> PowerSnapshot {
        var fresh = snapshot
        fresh.batteryTimeEstimate = nil
        fresh.batteryTimeEstimateSource = nil
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
        fresh.batteryTimeEstimateSource = .system
        return fresh
    }

    private static func validMinutes(_ value: Any?) -> Int? {
        guard let minutes = BatterySampler.optionalIntValue(value),
              (0...Int(Int32.max)).contains(minutes) else { return nil }
        return minutes
    }
}

/// Bounded fallback for firmware that does not publish an IOPS time estimate.
/// A minute of continuous, same-direction samples avoids using transition data.
struct BatteryTimeFallback {
    private enum Direction { case remaining, charging, full, notCharging }
    private static let settlingNanoseconds: UInt64 = 60_000_000_000
    private static let maximumGapNanoseconds: UInt64 = 10_000_000_000
    private var direction: Direction?
    private var directionSince: UInt64?
    private var previousTime: UInt64?
    private var dischargeSince: UInt64?
    private var averageDischargeMA: Double?

    mutating func reset() { self = Self() }

    mutating func applying(
        to snapshot: PowerSnapshot,
        properties: [String: Any],
        systemEstimate: BatteryTimeEstimate?,
        atNanoseconds now: UInt64
    ) -> PowerSnapshot {
        var fresh = BatteryRuntimeEstimate.applying(to: snapshot, readEstimate: { systemEstimate })
        let rawDirection = Self.direction(from: properties, snapshot: snapshot)
        if let previousTime,
           now < previousTime || now - previousTime > Self.maximumGapNanoseconds {
            reset()
        }
        if rawDirection != direction {
            reset()
            direction = rawDirection
        }
        if rawDirection != nil, directionSince == nil { directionSince = now }
        let elapsed = previousTime.map { Double(now - $0) / 1_000_000_000 } ?? 0
        previousTime = now

        // Continue observing while IOPS is available so its temporary omission
        // does not discard an already established discharge window.
        let capacity = Self.rawCapacity(from: properties)
        if rawDirection == .remaining, capacity != nil,
           let discharge = Self.dischargeCurrent(from: properties) {
            if let average = averageDischargeMA {
                let weight = 1 - exp(-elapsed / 60)
                averageDischargeMA = average + weight * (discharge - average)
            } else {
                averageDischargeMA = discharge
                dischargeSince = now
            }
        } else {
            averageDischargeMA = nil
            dischargeSince = nil
        }

        // IOPS remains authoritative, including completed and paused charging.
        switch fresh.batteryTimeEstimate {
        case .remaining(.some), .charging(.some), .full, .notCharging:
            return fresh
        default: break
        }
        fresh.batteryTimeEstimate = nil
        fresh.batteryTimeEstimateSource = nil
        guard let rawDirection, let directionSince else { return fresh }
        // Do not combine a stale IOPS direction with a new registry sample.
        if let systemEstimate, !Self.matches(systemEstimate, direction: rawDirection) {
            // Preserve the start of this wait: a persistent disagreement must
            // expire, not restart Calculating on every sample.
            if now - directionSince < Self.settlingNanoseconds {
                switch rawDirection {
                case .remaining: fresh.batteryTimeEstimate = .remaining(nil)
                case .charging: fresh.batteryTimeEstimate = .charging(nil)
                case .full, .notCharging: break
                }
            }
            return fresh
        }
        switch rawDirection {
        case .full, .notCharging:
            fresh.batteryTimeEstimate = rawDirection == .full ? .full : .notCharging
            fresh.batteryTimeEstimateSource = .batteryGauge
            return fresh
        case .remaining, .charging: break
        }
        guard now - directionSince >= Self.settlingNanoseconds else {
            fresh.batteryTimeEstimate = rawDirection == .remaining ? .remaining(nil) : .charging(nil)
            return fresh
        }

        let gaugeKey = rawDirection == .remaining ? "AvgTimeToEmpty" : "AvgTimeToFull"
        if let minutes = BatterySampler.optionalIntValue(properties[gaugeKey]),
           (0..<65_535).contains(minutes),
           Self.gaugeCurrentMatches(properties, direction: rawDirection) {
            fresh.batteryTimeEstimate = rawDirection == .remaining ? .remaining(minutes) : .charging(minutes)
            fresh.batteryTimeEstimateSource = .batteryGauge
        } else if rawDirection == .remaining, let capacity, let averageDischargeMA,
                  let dischargeSince {
            // Valid discharge measurements may resume after the direction's
            // initial wait has ended. Show the new calculation while it fills.
            guard now - dischargeSince >= Self.settlingNanoseconds else {
                fresh.batteryTimeEstimate = .remaining(nil)
                return fresh
            }
            let minutes = 60 * Double(capacity) / averageDischargeMA
            // Do not suggest minute-level precision for a load-based estimate.
            let rounded = minutes < 5 ? Int(minutes.rounded()) : Int((minutes / 5).rounded()) * 5
            fresh.batteryTimeEstimate = .remaining(max(1, rounded))
            fresh.batteryTimeEstimateSource = .observedDischarge
        }
        // Without usable inputs the bounded wait ends in Unavailable. Later
        // samples can recover; bad optional fields do not restart that wait.
        return fresh
    }

    private static func direction(from properties: [String: Any], snapshot: PowerSnapshot) -> Direction? {
        guard let connected = BatterySampler.optionalBoolValue(properties["ExternalConnected"]),
              connected == snapshot.plugged,
              let charging = BatterySampler.optionalBoolValue(properties["IsCharging"]) else { return nil }
        let full = BatterySampler.optionalBoolValue(properties["FullyCharged"]) == true
        guard !(charging && full) else { return nil }
        // A full-capacity flag does not prevent an unplugged battery from
        // supplying power. The connection, charging flag and power set direction.
        if !connected { return !charging && snapshot.batteryW <= 0 ? .remaining : nil }
        if snapshot.state == .mixedSupply { return .notCharging }
        if charging { return .charging }
        guard snapshot.state != .charging else { return nil }
        return full ? .full : .notCharging
    }

    private static func matches(_ estimate: BatteryTimeEstimate, direction: Direction) -> Bool {
        switch (estimate, direction) {
        case (.remaining, .remaining), (.charging, .charging), (.full, .full), (.notCharging, .notCharging):
            return true
        default: return false
        }
    }

    private static func rawCapacity(from properties: [String: Any]) -> Int? {
        // Ordinary CurrentCapacity/MaxCapacity are percentages on Apple silicon.
        // Only this explicit raw mAh pair is safe in a current-based formula.
        guard let current = BatterySampler.optionalIntValue(properties["AppleRawCurrentCapacity"]),
              let maximum = BatterySampler.optionalIntValue(properties["AppleRawMaxCapacity"]),
              (1...100_000).contains(maximum), (0...maximum).contains(current) else { return nil }
        return current
    }

    private static func gaugeCurrentMatches(_ properties: [String: Any], direction: Direction) -> Bool {
        for key in ["Amperage", "InstantAmperage"] {
            guard let raw = properties[key] else { continue }
            guard let current = BatterySampler.optionalIntValue(raw), current != -1,
                  (-100_000...100_000).contains(current),
                  direction == .remaining ? current <= 0 : current >= 0 else { return false }
        }
        return true
    }

    private static func dischargeCurrent(from properties: [String: Any]) -> Double? {
        let key = properties["Amperage"] == nil ? "InstantAmperage" : "Amperage"
        guard let current = BatterySampler.optionalIntValue(properties[key]),
              (-100_000 ..< -10).contains(current) else { return nil }
        if let instant = properties["InstantAmperage"] {
            guard let value = BatterySampler.optionalIntValue(instant),
                  (-100_000 ..< -10).contains(value) else { return nil }
        }
        return -Double(current)
    }
}
