import Foundation

// MARK: - Resolution vocabulary

struct PowerResolutionSource: RawRepresentable, Codable, Hashable, Sendable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    init(_ rawValue: String) { self.init(rawValue: rawValue) }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(try container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension PowerResolutionSource {
    static let iokitSystemPowerIn = Self("iokit.SystemPowerIn")
    static let iokitSystemLoad = Self("iokit.SystemLoad")
    static let batteryVoltageTimesCurrent = Self("derived.batteryVoltageTimesCurrent")
    static let smcPDTR = Self("smc.PDTR")
    static let smcPSTRRaw = Self("smc.PSTR.raw")
    static func smcPSTRCandidate(_ multiple: Int) -> Self {
        Self("smc.PSTR.candidate.\(multiple)")
    }
    static let smcPPBRMagnitude = Self("smc.PPBR.magnitude")
    static let deviceOutputMeasuredTotal = Self("deviceOutput.measuredTotal")
    static let legacyV4Adapter = Self("helper.v4.adapter")
    static let legacyV4System = Self("helper.v4.system")
}

struct PowerResolutionReason: RawRepresentable, Codable, Hashable, Sendable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    init(_ rawValue: String) { self.init(rawValue: rawValue) }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(try container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension PowerResolutionReason {
    static let shadowMode = Self("shadow-mode")
    static let pstrPolicyUnavailable = Self("pstr-policy-unavailable")
    static let pstrEvidenceInsufficient = Self("pstr-evidence-insufficient")
    static let pstrAmbiguous = Self("pstr-ambiguous")
    static let pstrPersistencePending = Self("pstr-persistence-pending")
    static let pstrEventReset = Self("pstr-event-reset")
    static let pstrSourceLoss = Self("pstr-source-loss")
    static let helperV5Partial = Self("helper-v5-partial")
    static let legacyV4NoRawEvidence = Self("legacy-v4-no-raw-evidence")
    static let batteryDirectionUnavailable = Self("battery-direction-unavailable")
    static let freshnessUnknown = Self("freshness-unknown")
    static let freshnessUnchanged = Self("freshness-unchanged-not-stale")
    static let freshnessStale = Self("freshness-stale")
    static let nonzeroResidual = Self("nonzero-residual-preserved")
    static let adapterUnavailable = Self("adapter-unavailable")
    static let systemUnavailable = Self("system-unavailable")
    static let invalidDirectValue = Self("invalid-direct-value")
    static let deviceOutputUnknown = Self("device-output-unknown")
}

enum PowerResolutionConfidence: String, Codable, Equatable, Sendable {
    case none
    case degraded
    case provisional
    case corroborated
}

struct ResolvedPowerValue: Codable, Equatable, Sendable {
    let watts: Double
    let source: PowerResolutionSource
    let capture: MonotonicInterval?
    let isDerived: Bool
}

struct ResolvedBatteryFlow: Codable, Equatable, Sendable {
    /// Positive means power flows into the battery; negative means discharge.
    let signedWatts: Double
    let source: PowerResolutionSource
    let capture: MonotonicInterval?
}

struct PowerResolutionResidual: Codable, Equatable, Sendable {
    let identifier: String
    let watts: Double
    let maximumInputSkewMilliseconds: Double?
}

struct PowerResolution: Codable, Equatable, Sendable {
    let sequence: UInt64
    let adapter: ResolvedPowerValue?
    let system: ResolvedPowerValue?
    let battery: ResolvedBatteryFlow?
    let batteryDischargeMagnitude: ResolvedPowerValue?
    let deviceOutputAuxiliary: ResolvedPowerValue?
    let pstrBand: PSTRBandDecision
    let residuals: [PowerResolutionResidual]
    let confidence: PowerResolutionConfidence
    let degradationReasons: [PowerResolutionReason]

    /// Foundation code is deliberately shadow-only. The final Phase 2 gate is
    /// required before any result may replace legacy user-visible values.
    let userVisibleEligible: Bool

    init(
        sequence: UInt64,
        adapter: ResolvedPowerValue?,
        system: ResolvedPowerValue?,
        battery: ResolvedBatteryFlow?,
        batteryDischargeMagnitude: ResolvedPowerValue?,
        deviceOutputAuxiliary: ResolvedPowerValue?,
        pstrBand: PSTRBandDecision,
        residuals: [PowerResolutionResidual],
        confidence: PowerResolutionConfidence,
        degradationReasons: [PowerResolutionReason],
        userVisibleEligible: Bool
    ) {
        self.sequence = sequence
        self.adapter = adapter
        self.system = system
        self.battery = battery
        self.batteryDischargeMagnitude = batteryDischargeMagnitude
        self.deviceOutputAuxiliary = deviceOutputAuxiliary
        self.pstrBand = pstrBand
        self.residuals = residuals
        self.confidence = confidence
        self.degradationReasons = degradationReasons
        _ = userVisibleEligible
        self.userVisibleEligible = false
    }

    private enum CodingKeys: String, CodingKey {
        case sequence
        case adapter
        case system
        case battery
        case batteryDischargeMagnitude
        case deviceOutputAuxiliary
        case pstrBand
        case residuals
        case confidence
        case degradationReasons
        case userVisibleEligible
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sequence = try container.decode(UInt64.self, forKey: .sequence)
        adapter = try container.decodeIfPresent(ResolvedPowerValue.self, forKey: .adapter)
        system = try container.decodeIfPresent(ResolvedPowerValue.self, forKey: .system)
        battery = try container.decodeIfPresent(ResolvedBatteryFlow.self, forKey: .battery)
        batteryDischargeMagnitude = try container.decodeIfPresent(
            ResolvedPowerValue.self,
            forKey: .batteryDischargeMagnitude
        )
        deviceOutputAuxiliary = try container.decodeIfPresent(
            ResolvedPowerValue.self,
            forKey: .deviceOutputAuxiliary
        )
        pstrBand = try container.decode(PSTRBandDecision.self, forKey: .pstrBand)
        residuals = try container.decode([PowerResolutionResidual].self, forKey: .residuals)
        confidence = try container.decode(PowerResolutionConfidence.self, forKey: .confidence)
        degradationReasons = try container.decode(
            [PowerResolutionReason].self,
            forKey: .degradationReasons
        )
        _ = try container.decode(Bool.self, forKey: .userVisibleEligible)
        userVisibleEligible = false
    }
}

struct PowerFusionSources: Sendable {
    let sequence: UInt64
    let finalizedAtContinuousNanoseconds: UInt64
    let battery: AppleSmartBatteryObservation
    let smc: SMCObservation?
    let helperV5WasPartial: Bool
    let legacyV4: HelperClient.LivePower?

    init(rawObservation: RawPowerObservation) {
        sequence = rawObservation.sequence
        finalizedAtContinuousNanoseconds = rawObservation.finalizedAtContinuousNanoseconds
        battery = rawObservation.battery
        smc = rawObservation.smc
        helperV5WasPartial = rawObservation.smc.keys.contains { $0.status != .present }
        legacyV4 = nil
    }

    init(
        sequence: UInt64,
        finalizedAtContinuousNanoseconds: UInt64,
        battery: AppleSmartBatteryObservation,
        helperResult: HelperPowerObservationFetchResult?
    ) {
        self.sequence = sequence
        self.finalizedAtContinuousNanoseconds = finalizedAtContinuousNanoseconds
        self.battery = battery
        switch helperResult {
        case let .v5(response):
            smc = try? response.asSMCObservation()
            helperV5WasPartial = response.partial
            legacyV4 = nil
        case let .legacyV4(power):
            smc = nil
            helperV5WasPartial = false
            legacyV4 = power
        case .failed, .none:
            smc = nil
            helperV5WasPartial = false
            legacyV4 = nil
        }
    }
}

// MARK: - Parameterized PSTR band tracker

struct PSTRBandPolicy: Codable, Equatable, Sendable {
    let maximumAnchorSkewMilliseconds: Double
    /// Nil means unchanged/frozen anchors are record-only and cannot select a band.
    /// A non-nil value is evidence-calibrated outside this foundation layer.
    let maximumUnchangedAnchorMilliseconds: Double?
    let maximumBestCandidateErrorWatts: Double
    let minimumRunnerUpMarginWatts: Double
    let requiredConsecutiveSamples: Int
    let maximumPersistenceGapMilliseconds: Double

    init(
        maximumAnchorSkewMilliseconds: Double,
        maximumUnchangedAnchorMilliseconds: Double?,
        maximumBestCandidateErrorWatts: Double,
        minimumRunnerUpMarginWatts: Double,
        requiredConsecutiveSamples: Int,
        maximumPersistenceGapMilliseconds: Double
    ) {
        self.maximumAnchorSkewMilliseconds = maximumAnchorSkewMilliseconds
        self.maximumUnchangedAnchorMilliseconds = maximumUnchangedAnchorMilliseconds
        self.maximumBestCandidateErrorWatts = maximumBestCandidateErrorWatts
        self.minimumRunnerUpMarginWatts = minimumRunnerUpMarginWatts
        self.requiredConsecutiveSamples = requiredConsecutiveSamples
        self.maximumPersistenceGapMilliseconds = maximumPersistenceGapMilliseconds
    }

    var isStructurallyValid: Bool {
        maximumAnchorSkewMilliseconds.isFinite
            && maximumAnchorSkewMilliseconds >= 0
            && (maximumUnchangedAnchorMilliseconds == nil
                || (maximumUnchangedAnchorMilliseconds!.isFinite
                    && maximumUnchangedAnchorMilliseconds! >= 0))
            && maximumBestCandidateErrorWatts.isFinite
            && maximumBestCandidateErrorWatts >= 0
            && minimumRunnerUpMarginWatts.isFinite
            && minimumRunnerUpMarginWatts >= 0
            && requiredConsecutiveSamples > 0
            && maximumPersistenceGapMilliseconds.isFinite
            && maximumPersistenceGapMilliseconds >= 0
    }
}

struct PSTRBandAnchor: Codable, Equatable, Sendable {
    let identifier: String
    let watts: Double
    let capture: MonotonicInterval
    let freshness: FreshnessEvidence
}

enum PSTRBandEvent: String, Codable, Equatable, Sendable {
    case normal
    case powerSourceTransition
    case sleepWake
    case helperRestart
    case rawSourceIdentityChange
    case sourceLoss
    case pstrDataTypeChange
}

enum PSTRBandDecision: Codable, Equatable, Sendable {
    case policyUnavailable(rawWatts: Double?, candidates: [Double])
    case ineligible(rawWatts: Double?, candidates: [Double], reasons: [PowerResolutionReason])
    case ambiguous(rawWatts: Double, candidates: [Double], bestMultiple: Int, runnerUpMultiple: Int)
    case pending(rawWatts: Double, multiple: Int, candidateWatts: Double, observedCount: Int, requiredCount: Int)
    case selected(rawWatts: Double, multiple: Int, candidateWatts: Double)

    private enum CodingKeys: String, CodingKey {
        case kind, rawWatts, candidates, reasons, bestMultiple, runnerUpMultiple
        case multiple, candidateWatts, observedCount, requiredCount
    }
    private enum Kind: String, Codable {
        case policyUnavailable, ineligible, ambiguous, pending, selected
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .policyUnavailable:
            self = .policyUnavailable(
                rawWatts: try container.decodeIfPresent(Double.self, forKey: .rawWatts),
                candidates: try container.decode([Double].self, forKey: .candidates)
            )
        case .ineligible:
            self = .ineligible(
                rawWatts: try container.decodeIfPresent(Double.self, forKey: .rawWatts),
                candidates: try container.decode([Double].self, forKey: .candidates),
                reasons: try container.decode([PowerResolutionReason].self, forKey: .reasons)
            )
        case .ambiguous:
            self = .ambiguous(
                rawWatts: try container.decode(Double.self, forKey: .rawWatts),
                candidates: try container.decode([Double].self, forKey: .candidates),
                bestMultiple: try container.decode(Int.self, forKey: .bestMultiple),
                runnerUpMultiple: try container.decode(Int.self, forKey: .runnerUpMultiple)
            )
        case .pending:
            self = .pending(
                rawWatts: try container.decode(Double.self, forKey: .rawWatts),
                multiple: try container.decode(Int.self, forKey: .multiple),
                candidateWatts: try container.decode(Double.self, forKey: .candidateWatts),
                observedCount: try container.decode(Int.self, forKey: .observedCount),
                requiredCount: try container.decode(Int.self, forKey: .requiredCount)
            )
        case .selected:
            self = .selected(
                rawWatts: try container.decode(Double.self, forKey: .rawWatts),
                multiple: try container.decode(Int.self, forKey: .multiple),
                candidateWatts: try container.decode(Double.self, forKey: .candidateWatts)
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .policyUnavailable(raw, candidates):
            try container.encode(Kind.policyUnavailable, forKey: .kind)
            try container.encodeIfPresent(raw, forKey: .rawWatts)
            try container.encode(candidates, forKey: .candidates)
        case let .ineligible(raw, candidates, reasons):
            try container.encode(Kind.ineligible, forKey: .kind)
            try container.encodeIfPresent(raw, forKey: .rawWatts)
            try container.encode(candidates, forKey: .candidates)
            try container.encode(reasons, forKey: .reasons)
        case let .ambiguous(raw, candidates, best, runnerUp):
            try container.encode(Kind.ambiguous, forKey: .kind)
            try container.encode(raw, forKey: .rawWatts)
            try container.encode(candidates, forKey: .candidates)
            try container.encode(best, forKey: .bestMultiple)
            try container.encode(runnerUp, forKey: .runnerUpMultiple)
        case let .pending(raw, multiple, watts, count, required):
            try container.encode(Kind.pending, forKey: .kind)
            try container.encode(raw, forKey: .rawWatts)
            try container.encode(multiple, forKey: .multiple)
            try container.encode(watts, forKey: .candidateWatts)
            try container.encode(count, forKey: .observedCount)
            try container.encode(required, forKey: .requiredCount)
        case let .selected(raw, multiple, watts):
            try container.encode(Kind.selected, forKey: .kind)
            try container.encode(raw, forKey: .rawWatts)
            try container.encode(multiple, forKey: .multiple)
            try container.encode(watts, forKey: .candidateWatts)
        }
    }
}

struct PSTRBandTracker: Sendable {
    private var pendingMultiple: Int?
    private var pendingCount = 0
    private var lastFinalizedAt: UInt64?

    mutating func reset() {
        pendingMultiple = nil
        pendingCount = 0
        lastFinalizedAt = nil
    }

    mutating func evaluate(
        rawPSTR: SMCKeyObservation?,
        candidates: [ModuloCandidate],
        anchors: [PSTRBandAnchor],
        event: PSTRBandEvent,
        finalizedAtContinuousNanoseconds: UInt64,
        policy: PSTRBandPolicy?
    ) -> PSTRBandDecision {
        let raw = rawPSTR?.status == .present ? rawPSTR?.decodedWatts : nil
        let candidateWatts = candidates.map(\.candidateWatts)

        guard let policy, policy.isStructurallyValid else {
            reset()
            return .policyUnavailable(rawWatts: raw, candidates: candidateWatts)
        }
        guard event == .normal else {
            reset()
            return .ineligible(
                rawWatts: raw,
                candidates: candidateWatts,
                reasons: [event == .sourceLoss ? .pstrSourceLoss : .pstrEventReset]
            )
        }
        guard let rawPSTR,
              rawPSTR.status == .present,
              let raw,
              raw.isFinite,
              candidates.count == 4,
              candidates.map(\.multiple) == [0, 1, 2, 3],
              let pstrCapture = Optional(rawPSTR.capture) else {
            reset()
            return .ineligible(
                rawWatts: raw,
                candidates: candidateWatts,
                reasons: [.pstrEvidenceInsufficient]
            )
        }

        if let lastFinalizedAt {
            if finalizedAtContinuousNanoseconds < lastFinalizedAt {
                reset()
            } else {
                let gap = Double(finalizedAtContinuousNanoseconds - lastFinalizedAt) / 1_000_000
                if gap > policy.maximumPersistenceGapMilliseconds {
                    reset()
                }
            }
        }
        lastFinalizedAt = finalizedAtContinuousNanoseconds

        let eligibleAnchors = anchors.filter { anchor in
            guard anchor.watts.isFinite, anchor.watts >= 0 else { return false }
            switch anchor.freshness.assessment {
            case .changed:
                break
            case .unchanged:
                guard anchor.freshness.basis != .none,
                      let unchangedFor = anchor.freshness.unchangedForMilliseconds,
                      let maximumUnchanged = policy.maximumUnchangedAnchorMilliseconds,
                      unchangedFor <= maximumUnchanged else { return false }
            case .unknown, .stale:
                return false
            }
            let lhs = pstrCapture.midpointContinuousNanoseconds
            let rhs = anchor.capture.midpointContinuousNanoseconds
            let delta = lhs >= rhs ? lhs - rhs : rhs - lhs
            return Double(delta) / 1_000_000 <= policy.maximumAnchorSkewMilliseconds
        }
        guard !eligibleAnchors.isEmpty else {
            reset()
            return .ineligible(
                rawWatts: raw,
                candidates: candidateWatts,
                reasons: [.pstrEvidenceInsufficient]
            )
        }

        let ranked = candidates.map { candidate -> (ModuloCandidate, Double) in
            let error = eligibleAnchors.reduce(0.0) {
                $0 + abs(candidate.candidateWatts - $1.watts)
            } / Double(eligibleAnchors.count)
            return (candidate, error)
        }.sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
            return lhs.0.multiple < rhs.0.multiple
        }
        guard ranked.count >= 2 else {
            reset()
            return .ineligible(rawWatts: raw, candidates: candidateWatts, reasons: [.pstrEvidenceInsufficient])
        }
        let best = ranked[0]
        let runnerUp = ranked[1]
        guard best.1 <= policy.maximumBestCandidateErrorWatts else {
            reset()
            return .ineligible(rawWatts: raw, candidates: candidateWatts, reasons: [.pstrEvidenceInsufficient])
        }
        guard runnerUp.1 - best.1 >= policy.minimumRunnerUpMarginWatts else {
            reset()
            return .ambiguous(
                rawWatts: raw,
                candidates: candidateWatts,
                bestMultiple: best.0.multiple,
                runnerUpMultiple: runnerUp.0.multiple
            )
        }

        if pendingMultiple == best.0.multiple {
            pendingCount += 1
        } else {
            pendingMultiple = best.0.multiple
            pendingCount = 1
        }
        if pendingCount < policy.requiredConsecutiveSamples {
            return .pending(
                rawWatts: raw,
                multiple: best.0.multiple,
                candidateWatts: best.0.candidateWatts,
                observedCount: pendingCount,
                requiredCount: policy.requiredConsecutiveSamples
            )
        }
        return .selected(
            rawWatts: raw,
            multiple: best.0.multiple,
            candidateWatts: best.0.candidateWatts
        )
    }
}

// MARK: - Conservative shadow fusion

struct PowerObservationFusion {
    static func pstrCandidates(rawWatts: Double?) -> [ModuloCandidate] {
        guard let rawWatts,
              rawWatts.isFinite,
              rawWatts >= 0 else { return [] }
        return PSTRModuloEvidence.candidateMultiples.map { multiple in
            ModuloCandidate(
                multiple: multiple,
                candidateWatts: rawWatts
                    + Double(multiple) * PSTRModuloEvidence.requiredModulusWatts,
                deltaToAnchorsWatts: []
            )
        }
    }

    static func anchors(from observation: AppleSmartBatteryObservation) -> [PSTRBandAnchor] {
        // PSTR is platform/system consumption. SystemPowerIn includes the battery
        // branch and is deliberately not treated as a like-for-like PSTR anchor.
        let systemLoad = observation.powerTelemetry.systemLoad
        guard systemLoad.presence == .present,
              let watts = systemLoad.watts,
              watts.isFinite,
              watts >= 0 else { return [] }
        return [PSTRBandAnchor(
            identifier: systemLoad.identifier,
            watts: watts,
            capture: systemLoad.capture,
            freshness: observation.powerTelemetry.freshness
        )]
    }

    static func resolve(
        sources: PowerFusionSources,
        pstrDecision: PSTRBandDecision
    ) -> PowerResolution {
        var reasons: Set<PowerResolutionReason> = [.shadowMode]
        var residuals: [PowerResolutionResidual] = []

        let smcPDTR = sources.smc?.key("PDTR")
        let smcPSTR = sources.smc?.key("PSTR")
        let smcPPBR = sources.smc?.key("PPBR")
        let telemetry = sources.battery.powerTelemetry

        let adapter: ResolvedPowerValue?
        if smcPDTR?.status == .present,
           let watts = smcPDTR?.decodedWatts,
           watts.isFinite,
           watts >= 0 {
            adapter = ResolvedPowerValue(watts: watts, source: .smcPDTR, capture: smcPDTR?.capture, isDerived: false)
        } else if telemetry.systemPowerIn.presence == .present,
                  telemetry.freshness.assessment != .stale,
                  let watts = telemetry.systemPowerIn.watts,
                  watts.isFinite,
                  watts >= 0 {
            adapter = ResolvedPowerValue(watts: watts, source: .iokitSystemPowerIn, capture: telemetry.systemPowerIn.capture, isDerived: false)
        } else if let watts = sources.legacyV4?.adapterW {
            adapter = ResolvedPowerValue(watts: watts, source: .legacyV4Adapter, capture: nil, isDerived: false)
            reasons.insert(.legacyV4NoRawEvidence)
        } else {
            adapter = nil
            reasons.insert(.adapterUnavailable)
        }

        let system: ResolvedPowerValue?
        if case let .selected(_, multiple, candidateWatts) = pstrDecision,
           smcPSTR?.status == .present {
            system = ResolvedPowerValue(
                watts: candidateWatts,
                source: .smcPSTRCandidate(multiple),
                capture: smcPSTR?.capture,
                isDerived: multiple != 0
            )
        } else if telemetry.systemLoad.presence == .present,
                  telemetry.freshness.assessment != .stale,
                  let watts = telemetry.systemLoad.watts,
                  watts.isFinite,
                  watts >= 0 {
            system = ResolvedPowerValue(watts: watts, source: .iokitSystemLoad, capture: telemetry.systemLoad.capture, isDerived: false)
        } else if let watts = sources.legacyV4?.systemW {
            system = ResolvedPowerValue(watts: watts, source: .legacyV4System, capture: nil, isDerived: false)
            reasons.insert(.legacyV4NoRawEvidence)
        } else {
            system = nil
            reasons.insert(.systemUnavailable)
        }

        if (smcPDTR?.status == .present && (smcPDTR?.decodedWatts ?? -.infinity) < 0)
            || (telemetry.systemPowerIn.presence == .present
                && (telemetry.systemPowerIn.watts ?? -.infinity) < 0)
            || (telemetry.systemLoad.presence == .present
                && (telemetry.systemLoad.watts ?? -.infinity) < 0) {
            reasons.insert(.invalidDirectValue)
        }

        switch pstrDecision {
        case .policyUnavailable:
            reasons.insert(.pstrPolicyUnavailable)
        case .ineligible:
            reasons.insert(.pstrEvidenceInsufficient)
        case .ambiguous:
            reasons.insert(.pstrAmbiguous)
        case .pending:
            reasons.insert(.pstrPersistencePending)
        case .selected:
            break
        }

        // The signed V×I evidence lives outside AppleSmartBatteryObservation in
        // Phase 1 RawPowerEvidence. The source-only initializer cannot invent it.
        let battery: ResolvedBatteryFlow? = nil
        reasons.insert(.batteryDirectionUnavailable)

        let ppbrMagnitude: ResolvedPowerValue?
        if smcPPBR?.status == .present, let watts = smcPPBR?.decodedWatts {
            ppbrMagnitude = ResolvedPowerValue(
                watts: watts,
                source: .smcPPBRMagnitude,
                capture: smcPPBR?.capture,
                isDerived: false
            )
        } else {
            ppbrMagnitude = nil
        }

        let deviceOutput: ResolvedPowerValue?
        let measuredOutput = sources.battery.deviceOutput.measuredTotalWatts
        if measuredOutput.presence == .present, let watts = measuredOutput.watts {
            deviceOutput = ResolvedPowerValue(
                watts: watts,
                source: .deviceOutputMeasuredTotal,
                capture: measuredOutput.capture,
                isDerived: true
            )
        } else {
            deviceOutput = nil
            reasons.insert(.deviceOutputUnknown)
        }

        if sources.helperV5WasPartial { reasons.insert(.helperV5Partial) }
        switch telemetry.freshness.assessment {
        case .unknown: reasons.insert(.freshnessUnknown)
        case .unchanged: reasons.insert(.freshnessUnchanged)
        case .stale: reasons.insert(.freshnessStale)
        case .changed: break
        }

        // Preserve every directly supplied nonzero residual. Do not repair it.
        if let adapter, let system {
            let batteryWatts = battery?.signedWatts
            if let batteryWatts {
                let residual = adapter.watts - system.watts - batteryWatts
                residuals.append(PowerResolutionResidual(
                    identifier: "shadow.selected",
                    watts: residual,
                    maximumInputSkewMilliseconds: maximumSkew([
                        adapter.capture, system.capture, battery?.capture,
                    ])
                ))
                if residual != 0 { reasons.insert(.nonzeroResidual) }
            }
        }

        let confidence: PowerResolutionConfidence
        if adapter == nil && system == nil {
            confidence = .none
        } else if reasons.contains(.legacyV4NoRawEvidence)
                    || reasons.contains(.systemUnavailable)
                    || reasons.contains(.adapterUnavailable)
                    || reasons.contains(.freshnessStale) {
            confidence = .degraded
        } else if case .selected = pstrDecision,
                  adapter?.source == .smcPDTR,
                  battery != nil {
            confidence = .corroborated
        } else {
            confidence = .provisional
        }

        return PowerResolution(
            sequence: sources.sequence,
            adapter: adapter,
            system: system,
            battery: battery,
            batteryDischargeMagnitude: ppbrMagnitude,
            deviceOutputAuxiliary: deviceOutput,
            pstrBand: pstrDecision,
            residuals: residuals,
            confidence: confidence,
            degradationReasons: reasons.sorted { $0.rawValue < $1.rawValue },
            userVisibleEligible: false
        )
    }

    static func resolve(
        rawObservation: RawPowerObservation,
        pstrDecision: PSTRBandDecision
    ) -> PowerResolution {
        var resolution = resolve(
            sources: PowerFusionSources(rawObservation: rawObservation),
            pstrDecision: pstrDecision
        )

        let batteryEvidence = rawObservation.evidence.batteryVoltageTimesCurrent
        if batteryEvidence.presence == .present,
           let signedWatts = batteryEvidence.watts {
            let flow = ResolvedBatteryFlow(
                signedWatts: signedWatts,
                source: .batteryVoltageTimesCurrent,
                capture: batteryEvidence.capture
            )
            var residuals = resolution.residuals
            if let adapter = resolution.adapter, let system = resolution.system {
                let residual = adapter.watts - system.watts - signedWatts
                residuals.append(PowerResolutionResidual(
                    identifier: "shadow.selected",
                    watts: residual,
                    maximumInputSkewMilliseconds: maximumSkew([
                        adapter.capture, system.capture, flow.capture,
                    ])
                ))
            }
            var reasons = resolution.degradationReasons.filter {
                $0 != .batteryDirectionUnavailable
            }
            if residuals.contains(where: { $0.watts != 0 }) {
                reasons.append(.nonzeroResidual)
            }
            reasons = Array(Set(reasons)).sorted { $0.rawValue < $1.rawValue }
            resolution = PowerResolution(
                sequence: resolution.sequence,
                adapter: resolution.adapter,
                system: resolution.system,
                battery: flow,
                batteryDischargeMagnitude: resolution.batteryDischargeMagnitude,
                deviceOutputAuxiliary: resolution.deviceOutputAuxiliary,
                pstrBand: resolution.pstrBand,
                residuals: residuals,
                confidence: confidence(
                    adapter: resolution.adapter,
                    system: resolution.system,
                    battery: flow,
                    pstrDecision: resolution.pstrBand,
                    reasons: reasons
                ),
                degradationReasons: reasons,
                userVisibleEligible: false
            )
        }

        // Carry Phase 1 evidence residuals without reinterpreting them.
        let carried = rawObservation.evidence.balances.compactMap { balance -> PowerResolutionResidual? in
            guard let watts = balance.residualWatts else { return nil }
            return PowerResolutionResidual(
                identifier: balance.identifier,
                watts: watts,
                maximumInputSkewMilliseconds: balance.maximumInputSkewMilliseconds
            )
        }
        if !carried.isEmpty {
            var reasons = resolution.degradationReasons
            if carried.contains(where: { $0.watts != 0 }) {
                reasons.append(.nonzeroResidual)
            }
            resolution = PowerResolution(
                sequence: resolution.sequence,
                adapter: resolution.adapter,
                system: resolution.system,
                battery: resolution.battery,
                batteryDischargeMagnitude: resolution.batteryDischargeMagnitude,
                deviceOutputAuxiliary: resolution.deviceOutputAuxiliary,
                pstrBand: resolution.pstrBand,
                residuals: deduplicate(resolution.residuals + carried),
                confidence: resolution.confidence,
                degradationReasons: Array(Set(reasons)).sorted { $0.rawValue < $1.rawValue },
                userVisibleEligible: false
            )
        }
        return resolution
    }

    private static func confidence(
        adapter: ResolvedPowerValue?,
        system: ResolvedPowerValue?,
        battery: ResolvedBatteryFlow?,
        pstrDecision: PSTRBandDecision,
        reasons: [PowerResolutionReason]
    ) -> PowerResolutionConfidence {
        if adapter == nil && system == nil { return .none }
        let reasonSet = Set(reasons)
        if reasonSet.contains(.legacyV4NoRawEvidence)
            || reasonSet.contains(.systemUnavailable)
            || reasonSet.contains(.adapterUnavailable)
            || reasonSet.contains(.freshnessStale) {
            return .degraded
        }
        if case .selected = pstrDecision,
           adapter?.source == .smcPDTR,
           battery != nil {
            return .corroborated
        }
        return .provisional
    }

    private static func maximumSkew(_ captures: [MonotonicInterval?]) -> Double? {
        let values = captures.compactMap { $0?.midpointContinuousNanoseconds }
        guard values.count >= 2, let minimum = values.min(), let maximum = values.max() else {
            return nil
        }
        return Double(maximum - minimum) / 1_000_000
    }

    private static func deduplicate(
        _ residuals: [PowerResolutionResidual]
    ) -> [PowerResolutionResidual] {
        var seen = Set<String>()
        return residuals.filter { seen.insert($0.identifier).inserted }
    }
}
