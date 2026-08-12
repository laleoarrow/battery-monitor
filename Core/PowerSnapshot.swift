import Foundation

enum PowerState {
    case charging
    case pluggedIdle
    case onBattery
    case mixedSupply
}

struct PowerSnapshot {
    static let epsilon: Double = 0.3

    var percent: Int = 0
    var plugged: Bool = false
    /// Adapter output. Always non-negative.
    var adapterW: Double = 0
    /// Signed: positive flows into the battery, negative flows out of it.
    var batteryW: Double = 0
    /// System consumption. Always non-negative.
    var systemW: Double = 0
    var temperatureC: Double? = nil
    var cycleCount: Int = 0
    var lowPowerMode: Bool = false

    /// Everything the sources are putting out right now. Drives the visual
    /// encoding curve and the popover's headline number.
    var totalInputW: Double {
        adapterW + max(-batteryW, 0)
    }

    /// Sources minus sinks. Should be ~0; anything larger means a field was
    /// parsed wrong.
    var conservationError: Double {
        (adapterW + max(-batteryW, 0)) - (systemW + max(batteryW, 0))
    }

    var state: PowerState {
        guard plugged else { return .onBattery }
        if batteryW > Self.epsilon { return .charging }
        if batteryW < -Self.epsilon { return .mixedSupply }
        return .pluggedIdle
    }
}
