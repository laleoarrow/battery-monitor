import Foundation

struct PowerFusionReplayInput: Sendable {
    let observation: RawPowerObservation
    let legacyVisible: LegacyVisiblePower?
    let event: PSTRBandEvent

    init(
        observation: RawPowerObservation,
        legacyVisible: LegacyVisiblePower? = nil,
        event: PSTRBandEvent = .normal
    ) {
        self.observation = observation
        self.legacyVisible = legacyVisible
        self.event = event
    }
}

struct PowerFusionReplayOutput: Codable, Equatable, Sendable {
    let sequence: UInt64
    let pstrDecision: PSTRBandDecision
    let resolution: PowerResolution
    let shadowComparison: PowerShadowComparison?
}

struct PowerObservationFusionReplay: Sendable {
    private var bandTracker = PSTRBandTracker()

    mutating func reset() {
        bandTracker.reset()
    }

    mutating func consume(
        _ input: PowerFusionReplayInput,
        policy: PSTRBandPolicy?
    ) -> PowerFusionReplayOutput {
        let observation = input.observation
        let pstr = observation.smc.key("PSTR")
        let candidates: [ModuloCandidate]
        if observation.evidence.pstrModulo.status == .candidatesGenerated {
            candidates = observation.evidence.pstrModulo.candidates
        } else {
            candidates = PowerObservationFusion.pstrCandidates(
                rawWatts: pstr?.status == .present ? pstr?.decodedWatts : nil
            )
        }
        let decision = bandTracker.evaluate(
            rawPSTR: pstr,
            candidates: candidates,
            anchors: PowerObservationFusion.anchors(from: observation.battery),
            event: input.event,
            finalizedAtContinuousNanoseconds:
                observation.finalizedAtContinuousNanoseconds,
            policy: policy
        )
        let resolution = PowerObservationFusion.resolve(
            rawObservation: observation,
            pstrDecision: decision
        )
        let comparison = input.legacyVisible.map {
            PowerObservationShadowEvaluator.compare(
                legacy: $0,
                resolution: resolution
            )
        }
        return PowerFusionReplayOutput(
            sequence: observation.sequence,
            pstrDecision: decision,
            resolution: resolution,
            shadowComparison: comparison
        )
    }
}
