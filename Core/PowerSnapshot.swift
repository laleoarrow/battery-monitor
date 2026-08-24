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
    /// Measured power delivered to attached devices, summed across ports.
    /// `nil` means this hardware sample did not publish a usable measurement.
    /// This is an auxiliary breakdown of `systemW`, not another power sink.
    var deviceOutputW: Double? = nil
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

    /// A device reading can outlive the independently sampled system total.
    /// Only expose it as a breakdown while the two samples remain coherent.
    var coherentDeviceOutputW: Double? {
        guard let deviceOutputW,
              deviceOutputW.isFinite,
              systemW.isFinite,
              deviceOutputW >= 0,
              deviceOutputW <= systemW + Self.epsilon else { return nil }
        return min(deviceOutputW, systemW)
    }

    var state: PowerState {
        guard plugged else { return .onBattery }
        if batteryW > Self.epsilon { return .charging }
        if batteryW < -Self.epsilon { return .mixedSupply }
        return .pluggedIdle
    }
}
