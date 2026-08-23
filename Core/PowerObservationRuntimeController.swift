import Foundation
import os

enum PowerObservationRuntimeEvent: Equatable {
    case normal
    case powerSourceTransition
    case sleepWake

    func merging(_ other: Self) -> Self {
        if self == .sleepWake || other == .sleepWake { return .sleepWake }
        if self == .powerSourceTransition
            || other == .powerSourceTransition {
            return .powerSourceTransition
        }
        return .normal
    }

    fileprivate var bandEvent: PSTRBandEvent {
        switch self {
        case .normal: return .normal
        case .powerSourceTransition: return .powerSourceTransition
        case .sleepWake: return .sleepWake
        }
    }
}

struct PowerObservationRuntimeSample {
    let sequence: UInt64
    let visibleSnapshot: PowerSnapshot?
    let helperResult: HelperPowerObservationFetchResult
    let resolution: PowerResolution
    let shadowComparison: PowerShadowComparison?
}

protocol PowerObservationShadowRecording: AnyObject {
    func record(_ comparison: PowerShadowComparison)
}

final class PrivacySafePowerObservationShadowRecorder:
    PowerObservationShadowRecording
{
    private let log = OSLog(
        subsystem: "com.leoarrow.wattson",
        category: "power-shadow"
    )

    func record(_ comparison: PowerShadowComparison) {
        os_log(
            "shadow seq=%{public}llu adapterDelta=%{public}.3f batteryDelta=%{public}.3f systemDelta=%{public}.3f confidence=%{public}@ reasons=%{public}d residuals=%{public}d fusionAppliedToVisible=false",
            log: log,
            type: .debug,
            comparison.sequence,
            comparison.adapter.deltaWatts ?? .nan,
            comparison.battery.deltaWatts ?? .nan,
            comparison.system.deltaWatts ?? .nan,
            comparison.shadowConfidence.rawValue,
            comparison.shadowReasons.count,
            comparison.residuals.count
        )
    }
}

final class PowerObservationRuntimeController {
    private let batteryReader: any AppleSmartBatteryPowerObservationReading
    private let legacySnapshot: () -> PowerSnapshot?
    private let helperObservation:
        (UInt64) -> HelperPowerObservationFetchResult
    private let clock: () -> UInt64
    private let shadowRecorder: any PowerObservationShadowRecording
    private let acquisitionQueue = DispatchQueue(
        label: "com.leoarrow.wattson.power-observation-runtime",
        qos: .userInitiated,
        attributes: .concurrent
    )
    private let stateLock = NSLock()
    private var sequence: UInt64 = 0
    private var bandTracker = PSTRBandTracker()

    convenience init() {
        self.init(
            batteryReader: AppleSmartBatteryPowerObservationReader(),
            legacySnapshot: BatterySampler.sample,
            helperObservation: { sequence in
                HelperClient.powerObservation(clientSequence: sequence)
            },
            clock: Self.monotonicNow,
            shadowRecorder: PrivacySafePowerObservationShadowRecorder()
        )
    }

    init(
        batteryReader: any AppleSmartBatteryPowerObservationReading,
        legacySnapshot: @escaping () -> PowerSnapshot?,
        helperObservation: @escaping
            (UInt64) -> HelperPowerObservationFetchResult,
        clock: @escaping () -> UInt64,
        shadowRecorder: any PowerObservationShadowRecording
    ) {
        self.batteryReader = batteryReader
        self.legacySnapshot = legacySnapshot
        self.helperObservation = helperObservation
        self.clock = clock
        self.shadowRecorder = shadowRecorder
    }

    func sample(
        event: PowerObservationRuntimeEvent
    ) -> PowerObservationRuntimeSample {
        stateLock.lock()
        defer { stateLock.unlock() }

        precondition(sequence < UInt64.max, "runtime sequence exhausted")
        sequence += 1
        let sampleSequence = sequence
        if event != .normal {
            bandTracker.reset()
            batteryReader.resetFreshness()
        }

        let values = acquire(sequence: sampleSequence)
        let finalizedAt = clock()
        let sources = PowerFusionSources(
            sequence: sampleSequence,
            finalizedAtContinuousNanoseconds: finalizedAt,
            battery: values.battery,
            helperResult: values.helper
        )
        let pstr = sources.smc?.key("PSTR")
        let decision = bandTracker.evaluate(
            rawPSTR: pstr,
            candidates: PowerObservationFusion.pstrCandidates(
                rawWatts: pstr?.status == .present
                    ? pstr?.decodedWatts : nil
            ),
            anchors: PowerObservationFusion.anchors(
                from: values.battery
            ),
            event: event.bandEvent,
            finalizedAtContinuousNanoseconds: finalizedAt,
            policy: nil
        )
        let resolution = addingSignedBatteryEvidence(
            to: PowerObservationFusion.resolve(
                sources: sources,
                pstrDecision: decision
            ),
            battery: values.battery
        )
        assert(!resolution.userVisibleEligible)

        let visibleSnapshot = resolvedLegacySnapshot(
            values.legacy,
            helperResult: values.helper
        )
        let comparison = visibleSnapshot.map { snapshot in
            PowerObservationShadowEvaluator.compare(
                legacy: LegacyVisiblePower(
                    adapterW: snapshot.adapterW,
                    batteryW: snapshot.batteryW,
                    systemW: snapshot.systemW
                ),
                resolution: resolution
            )
        }
        if let comparison {
            shadowRecorder.record(comparison)
        }

        return PowerObservationRuntimeSample(
            sequence: sampleSequence,
            visibleSnapshot: visibleSnapshot,
            helperResult: values.helper,
            resolution: resolution,
            shadowComparison: comparison
        )
    }

    private func acquire(
        sequence: UInt64
    ) -> RuntimeAcquisitionValues {
        let group = DispatchGroup()
        let box = RuntimeAcquisitionBox()

        group.enter()
        acquisitionQueue.async { [legacySnapshot] in
            box.setLegacy(legacySnapshot())
            group.leave()
        }
        group.enter()
        acquisitionQueue.async { [batteryReader] in
            box.setBattery(batteryReader.readObservation())
            group.leave()
        }
        group.enter()
        acquisitionQueue.async { [helperObservation] in
            box.setHelper(helperObservation(sequence))
            group.leave()
        }
        group.wait()
        return box.values()
    }

    private func resolvedLegacySnapshot(
        _ snapshot: PowerSnapshot?,
        helperResult: HelperPowerObservationFetchResult
    ) -> PowerSnapshot? {
        guard let snapshot else { return nil }

        let livePower: HelperClient.LivePower?
        switch helperResult {
        case let .legacyV4(power):
            livePower = power
        case let .v5(response):
            livePower = legacyLivePower(from: response)
        case .failed:
            livePower = nil
        }
        guard let livePower else { return snapshot }
        return BatterySampler.resolvedLivePower(
            snapshot: snapshot,
            adapterW: livePower.adapterW,
            systemW: livePower.systemW
        )
    }

    private func addingSignedBatteryEvidence(
        to resolution: PowerResolution,
        battery: AppleSmartBatteryObservation
    ) -> PowerResolution {
        let voltage = battery.voltageMillivolts
        let current: Observed<Int64>
        if battery.instantAmperageMilliamps.presence == .present {
            current = battery.instantAmperageMilliamps
        } else if battery.instantAmperageMilliamps.presence == .missing {
            current = battery.averageAmperageMilliamps
        } else {
            return resolution
        }
        guard voltage.presence == .present,
              current.presence == .present,
              let voltageValue = voltage.value,
              let currentValue = current.value else { return resolution }

        let signedWatts = Double(voltageValue)
            * Double(currentValue) / 1_000_000
        guard signedWatts.isFinite else { return resolution }

        let flow = ResolvedBatteryFlow(
            signedWatts: signedWatts,
            source: .batteryVoltageTimesCurrent,
            capture: battery.capture
        )
        var residuals = resolution.residuals
        var reasons = Set(resolution.degradationReasons)
        reasons.remove(.batteryDirectionUnavailable)
        if let adapter = resolution.adapter,
           let system = resolution.system {
            let residual = adapter.watts - system.watts - signedWatts
            residuals.append(PowerResolutionResidual(
                identifier: "shadow.selected",
                watts: residual,
                maximumInputSkewMilliseconds: maximumSkew([
                    adapter.capture,
                    system.capture,
                    flow.capture,
                ])
            ))
            if residual != 0 { reasons.insert(.nonzeroResidual) }
        }
        return PowerResolution(
            sequence: resolution.sequence,
            adapter: resolution.adapter,
            system: resolution.system,
            battery: flow,
            batteryDischargeMagnitude:
                resolution.batteryDischargeMagnitude,
            deviceOutputAuxiliary: resolution.deviceOutputAuxiliary,
            pstrBand: resolution.pstrBand,
            residuals: residuals,
            confidence: resolution.confidence,
            degradationReasons: reasons.sorted {
                $0.rawValue < $1.rawValue
            },
            userVisibleEligible: false
        )
    }

    private func legacyLivePower(
        from response: PowerObservationV5Response
    ) -> HelperClient.LivePower? {
        guard response.ok,
              response.connection.status == .opened else { return nil }

        func watts(_ name: String) -> Double? {
            guard let key = response.key(name),
                  key.status == .present,
                  let watts = key.decodedWatts,
                  watts.isFinite,
                  watts >= 0 else { return nil }
            return watts
        }
        let adapter = watts("PDTR")
        let system = watts("PSTR")
        guard adapter != nil || system != nil else { return nil }
        return HelperClient.LivePower(
            adapterW: adapter,
            systemW: system
        )
    }

    private func maximumSkew(
        _ captures: [MonotonicInterval?]
    ) -> Double? {
        let values = captures.compactMap {
            $0?.midpointContinuousNanoseconds
        }
        guard values.count >= 2,
              let minimum = values.min(),
              let maximum = values.max() else { return nil }
        return Double(maximum - minimum) / 1_000_000
    }

    private static func monotonicNow() -> UInt64 {
#if os(macOS)
        clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)
#else
        DispatchTime.now().uptimeNanoseconds
#endif
    }
}

private struct RuntimeAcquisitionValues {
    let legacy: PowerSnapshot?
    let battery: AppleSmartBatteryObservation
    let helper: HelperPowerObservationFetchResult
}

private final class RuntimeAcquisitionBox {
    private let lock = NSLock()
    private var legacy: PowerSnapshot?
    private var battery: AppleSmartBatteryObservation?
    private var helper: HelperPowerObservationFetchResult?

    func setLegacy(_ value: PowerSnapshot?) {
        lock.lock()
        legacy = value
        lock.unlock()
    }

    func setBattery(_ value: AppleSmartBatteryObservation) {
        lock.lock()
        battery = value
        lock.unlock()
    }

    func setHelper(_ value: HelperPowerObservationFetchResult) {
        lock.lock()
        helper = value
        lock.unlock()
    }

    func values() -> RuntimeAcquisitionValues {
        lock.lock()
        defer { lock.unlock() }
        let missingCapture = try! MonotonicInterval(
            startedContinuousNanoseconds: 0,
            endedContinuousNanoseconds: 0
        )
        return RuntimeAcquisitionValues(
            legacy: legacy,
            battery: battery ?? .canonicalFixtureMissing(
                capture: missingCapture
            ),
            helper: helper ?? .failed(.legacyV4Unavailable)
        )
    }
}
