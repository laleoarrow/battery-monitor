#if DEBUG

import Dispatch
import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

protocol AppleSmartBatteryObservationReading {
    func readObservation() throws -> AppleSmartBatteryObservation
}

protocol DirectSMCObservationReading {
    func readObservation() throws -> SMCObservation
}

protocol ContinuousNanosecondClockReading {
    func nowContinuousNanoseconds() -> UInt64
}

struct SystemContinuousNanosecondClock: ContinuousNanosecondClockReading {
    func nowContinuousNanoseconds() -> UInt64 {
#if canImport(Darwin)
        clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)
#elseif canImport(Glibc)
        var value = timespec()
        _ = clock_gettime(CLOCK_MONOTONIC_RAW, &value)
        return UInt64(value.tv_sec) * 1_000_000_000
            + UInt64(value.tv_nsec)
#else
        DispatchTime.now().uptimeNanoseconds
#endif
    }
}

enum PowerObservationCollectorError: Error, Equatable {
    case batteryReaderFailed
    case smcReaderFailed
    case invalidObservation
}

private final class PowerObservationResultBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Result<Value, Error>?

    func store(_ value: Result<Value, Error>) {
        lock.lock()
        storage = value
        lock.unlock()
    }

    func load() -> Result<Value, Error>? {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

struct PowerObservationCollector {
    let batteryReader: any AppleSmartBatteryObservationReading
    let smcReader: any DirectSMCObservationReading
    let clock: any ContinuousNanosecondClockReading

    init(
        batteryReader: any AppleSmartBatteryObservationReading,
        smcReader: any DirectSMCObservationReading,
        clock: any ContinuousNanosecondClockReading =
            SystemContinuousNanosecondClock()
    ) {
        self.batteryReader = batteryReader
        self.smcReader = smcReader
        self.clock = clock
    }

    func collect(
        sequence: UInt64,
        scenario: String?
    ) throws -> RawPowerObservation {
        let observationStarted = clock.nowContinuousNanoseconds()
        let batteryBox = PowerObservationResultBox<AppleSmartBatteryObservation>()
        let smcBox = PowerObservationResultBox<SMCObservation>()
        let group = DispatchGroup()
        let queue = DispatchQueue(
            label: "com.leoarrow.wattson.power-observation.collector",
            qos: .userInitiated,
            attributes: .concurrent
        )

        group.enter()
        queue.async {
            batteryBox.store(Result { try batteryReader.readObservation() })
            group.leave()
        }

        group.enter()
        queue.async {
            smcBox.store(Result { try smcReader.readObservation() })
            group.leave()
        }

        group.wait()
        let observationEnded = clock.nowContinuousNanoseconds()

        guard let batteryResult = batteryBox.load() else {
            throw PowerObservationCollectorError.batteryReaderFailed
        }
        guard let smcResult = smcBox.load() else {
            throw PowerObservationCollectorError.smcReaderFailed
        }

        let battery: AppleSmartBatteryObservation
        do {
            battery = try batteryResult.get()
        } catch {
            throw PowerObservationCollectorError.batteryReaderFailed
        }

        let smc: SMCObservation
        do {
            smc = try smcResult.get()
        } catch {
            throw PowerObservationCollectorError.smcReaderFailed
        }

        let evidence = try makeEvidence(
            battery: battery,
            smc: smc,
            observationStarted: observationStarted,
            observationEnded: observationEnded
        )
        let finalizedAt = max(
            observationEnded,
            clock.nowContinuousNanoseconds()
        )

        do {
            return try RawPowerObservation(
                sequence: sequence,
                scenario: scenario,
                finalizedAtContinuousNanoseconds: finalizedAt,
                battery: battery,
                smc: smc,
                evidence: evidence
            )
        } catch {
            throw PowerObservationCollectorError.invalidObservation
        }
    }

    private func makeEvidence(
        battery: AppleSmartBatteryObservation,
        smc: SMCObservation,
        observationStarted: UInt64,
        observationEnded: UInt64
    ) throws -> RawPowerEvidence {
        let batteryVI = try makeBatteryVI(
            battery: battery,
            evaluatedAt: observationEnded
        )
        let systemVI = try makeSystemInputVI(
            battery: battery,
            evaluatedAt: observationEnded
        )

        let presentSMCCaptures = smc.keys.compactMap { key in
            key.status == .present ? key.capture : nil
        }
        let smcKeySkew = maximumMidpointSkewMilliseconds(
            presentSMCCaptures
        )

        let signedBatterySMCSkew: Double?
        if battery.servicePresence == .present,
           smc.connectionStatus == .opened {
            signedBatterySMCSkew = signedMidpointDifferenceMilliseconds(
                battery.capture,
                smc.connectionCapture
            )
        } else {
            signedBatterySMCSkew = nil
        }

        let timing = ObservationTimingEvidence(
            observationStartedContinuousNanoseconds:
                observationStarted,
            observationEndedContinuousNanoseconds:
                observationEnded,
            totalCaptureDurationMilliseconds:
                Double(observationEnded - observationStarted)
                    / 1_000_000,
            smcKeySkewMilliseconds: smcKeySkew,
            batteryMidpointMinusSMCMidpointMilliseconds:
                signedBatterySMCSkew,
            absoluteBatterySMCSkewMilliseconds:
                signedBatterySMCSkew.map(abs)
        )

        let pstr = smc.key("PSTR")
        let rawPSTR = pstr?.status == .present
            ? pstr?.decodedWatts
            : nil
        var anchors: [ModuloAnchor] = []
        let systemLoad = battery.powerTelemetry.systemLoad
        if systemLoad.presence == .present,
           let watts = systemLoad.watts,
           watts.isFinite,
           watts >= 0 {
            anchors.append(
                ModuloAnchor(
                    identifier: systemLoad.identifier,
                    source: systemLoad.source,
                    watts: watts,
                    capture: systemLoad.capture
                )
            )
        }

        return RawPowerEvidence(
            batteryVoltageTimesCurrent: batteryVI,
            systemVoltageTimesCurrent: systemVI,
            timing: timing,
            pstrModulo: PSTRModuloEvidence(
                rawPSTRWatts: rawPSTR,
                anchors: anchors
            ),
            balances: [
                makeIOKitBalance(battery.powerTelemetry),
                makeSMCBalance(smc: smc, batteryVI: batteryVI),
            ]
        )
    }

    private func makeBatteryVI(
        battery: AppleSmartBatteryObservation,
        evaluatedAt: UInt64
    ) throws -> PowerReading {
        let voltage = battery.voltageMillivolts
        let current = battery.instantAmperageMilliamps
        guard voltage.presence == .present,
              current.presence == .present,
              let voltageValue = voltage.value,
              let currentValue = current.value else {
            return .canonicalFixtureMissing(
                identifier: "evidence.batteryVoltageTimesCurrent",
                source: .derivedBatteryVI,
                kind: .derived,
                semantic: .batteryVoltageTimesCurrent,
                capture: battery.capture
            )
        }

        let watts = Double(voltageValue)
            * Double(currentValue) / 1_000_000
        guard watts.isFinite else {
            return try invalidDerivedReading(
                identifier: "evidence.batteryVoltageTimesCurrent",
                source: .derivedBatteryVI,
                semantic: .batteryVoltageTimesCurrent,
                capture: battery.capture,
                evaluatedAt: evaluatedAt,
                issue: "battery voltage/current product is not finite"
            )
        }
        return try PowerReading(
            identifier: "evidence.batteryVoltageTimesCurrent",
            source: .derivedBatteryVI,
            kind: .derived,
            semantic: .batteryVoltageTimesCurrent,
            presence: .present,
            rawInteger: nil,
            rawFloatingPoint: nil,
            rawUnit: nil,
            watts: watts,
            capture: battery.capture,
            freshness: .unknown(at: evaluatedAt),
            validationIssue: nil
        )
    }

    private func makeSystemInputVI(
        battery: AppleSmartBatteryObservation,
        evaluatedAt: UInt64
    ) throws -> PowerReading {
        let voltage = battery.powerTelemetry.systemVoltageInNative
        let current = battery.powerTelemetry.systemCurrentInNative
        guard voltage.presence == .present,
              current.presence == .present,
              let voltageValue = voltage.value,
              let currentValue = current.value else {
            return .canonicalFixtureMissing(
                identifier: "evidence.systemVoltageTimesCurrent",
                source: .derivedSystemInputVI,
                kind: .derived,
                semantic: .systemVoltageTimesCurrent,
                capture: battery.powerTelemetry.capture
            )
        }

        // AppleSmartBattery publishes these two raw fields in units whose
        // product is microwatts on supported hardware. Preserve the source
        // values separately and expose only this diagnostic derived reading.
        let watts = Double(voltageValue)
            * Double(currentValue) / 1_000_000
        guard watts.isFinite else {
            return try invalidDerivedReading(
                identifier: "evidence.systemVoltageTimesCurrent",
                source: .derivedSystemInputVI,
                semantic: .systemVoltageTimesCurrent,
                capture: battery.powerTelemetry.capture,
                evaluatedAt: evaluatedAt,
                issue: "system voltage/current product is not finite"
            )
        }
        return try PowerReading(
            identifier: "evidence.systemVoltageTimesCurrent",
            source: .derivedSystemInputVI,
            kind: .derived,
            semantic: .systemVoltageTimesCurrent,
            presence: .present,
            rawInteger: nil,
            rawFloatingPoint: nil,
            rawUnit: nil,
            watts: watts,
            capture: battery.powerTelemetry.capture,
            freshness: .unknown(at: evaluatedAt),
            validationIssue: nil
        )
    }

    private func invalidDerivedReading(
        identifier: String,
        source: ObservationSource,
        semantic: PowerSemantic,
        capture: MonotonicInterval,
        evaluatedAt: UInt64,
        issue: String
    ) throws -> PowerReading {
        try PowerReading(
            identifier: identifier,
            source: source,
            kind: .derived,
            semantic: semantic,
            presence: .invalid,
            rawInteger: nil,
            rawFloatingPoint: nil,
            rawUnit: nil,
            watts: nil,
            capture: capture,
            freshness: .unknown(at: evaluatedAt),
            validationIssue: issue
        )
    }

    private func makeIOKitBalance(
        _ telemetry: BatteryPowerTelemetryObservation
    ) -> PowerBalanceEvidence {
        let adapter = telemetry.systemPowerIn
        let system = telemetry.systemLoad
        let battery = telemetry.batteryPower
        let adapterWatts = adapter.presence == .present
            ? adapter.watts : nil
        let systemWatts = system.presence == .present
            ? system.watts : nil
        let batteryWatts = battery.presence == .present
            ? battery.watts : nil

        let captures = [adapter, system, battery].compactMap {
            $0.presence == .present ? $0.capture : nil
        }
        let complete = adapterWatts != nil
            && systemWatts != nil
            && batteryWatts != nil

        return PowerBalanceEvidence(
            identifier: "iokit.telemetry",
            adapterSource: adapterWatts == nil ? nil : adapter.source,
            systemSource: systemWatts == nil ? nil : system.source,
            batterySource: batteryWatts == nil ? nil : battery.source,
            externalSource: nil,
            residualWatts: complete
                ? adapterWatts! - systemWatts! - batteryWatts!
                : nil,
            maximumInputSkewMilliseconds: complete
                ? maximumMidpointSkewMilliseconds(captures)
                : nil
        )
    }

    private func makeSMCBalance(
        smc: SMCObservation,
        batteryVI: PowerReading
    ) -> PowerBalanceEvidence {
        let adapter = smc.key("PDTR")
        let system = smc.key("PSTR")
        let adapterWatts = adapter?.status == .present
            ? adapter?.decodedWatts : nil
        let systemWatts = system?.status == .present
            ? system?.decodedWatts : nil
        let batteryWatts = batteryVI.presence == .present
            ? batteryVI.watts : nil
        let complete = adapterWatts != nil
            && systemWatts != nil
            && batteryWatts != nil

        var captures: [MonotonicInterval] = []
        if adapterWatts != nil, let adapter { captures.append(adapter.capture) }
        if systemWatts != nil, let system { captures.append(system.capture) }
        if batteryWatts != nil { captures.append(batteryVI.capture) }

        return PowerBalanceEvidence(
            identifier: "smc.direct",
            adapterSource: adapterWatts == nil ? nil : adapter?.source,
            systemSource: systemWatts == nil ? nil : system?.source,
            batterySource: batteryWatts == nil ? nil : batteryVI.source,
            externalSource: nil,
            residualWatts: complete
                ? adapterWatts! - systemWatts! - batteryWatts!
                : nil,
            maximumInputSkewMilliseconds: complete
                ? maximumMidpointSkewMilliseconds(captures)
                : nil
        )
    }

    private func maximumMidpointSkewMilliseconds(
        _ captures: [MonotonicInterval]
    ) -> Double? {
        guard captures.count >= 2 else { return nil }
        let midpoints = captures.map(\.midpointContinuousNanoseconds)
        guard let minimum = midpoints.min(),
              let maximum = midpoints.max() else { return nil }
        return Double(maximum - minimum) / 1_000_000
    }

    private func signedMidpointDifferenceMilliseconds(
        _ lhs: MonotonicInterval,
        _ rhs: MonotonicInterval
    ) -> Double {
        let lhsMidpoint = lhs.midpointContinuousNanoseconds
        let rhsMidpoint = rhs.midpointContinuousNanoseconds
        if lhsMidpoint >= rhsMidpoint {
            return Double(lhsMidpoint - rhsMidpoint) / 1_000_000
        }
        return -Double(rhsMidpoint - lhsMidpoint) / 1_000_000
    }
}

#endif
