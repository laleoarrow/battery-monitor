import Foundation

struct LegacyVisiblePower: Codable, Equatable, Sendable {
    let adapterW: Double
    let batteryW: Double
    let systemW: Double
}

struct PowerShadowDelta: Codable, Equatable, Sendable {
    let legacyWatts: Double
    let shadowWatts: Double?
    let deltaWatts: Double?
    let shadowSource: PowerResolutionSource?
}

struct PowerShadowComparison: Codable, Equatable, Sendable {
    let sequence: UInt64
    let adapter: PowerShadowDelta
    let battery: PowerShadowDelta
    let system: PowerShadowDelta
    let shadowConfidence: PowerResolutionConfidence
    let shadowReasons: [PowerResolutionReason]
    let residuals: [PowerResolutionResidual]
    let userVisibleValuesUnchanged: Bool
}

struct PowerObservationShadowEvaluator {
    static func compare(
        legacy: LegacyVisiblePower,
        resolution: PowerResolution
    ) -> PowerShadowComparison {
        PowerShadowComparison(
            sequence: resolution.sequence,
            adapter: delta(
                legacy: legacy.adapterW,
                shadow: resolution.adapter?.watts,
                source: resolution.adapter?.source
            ),
            battery: delta(
                legacy: legacy.batteryW,
                shadow: resolution.battery?.signedWatts,
                source: resolution.battery?.source
            ),
            system: delta(
                legacy: legacy.systemW,
                shadow: resolution.system?.watts,
                source: resolution.system?.source
            ),
            shadowConfidence: resolution.confidence,
            shadowReasons: resolution.degradationReasons,
            residuals: resolution.residuals,
            userVisibleValuesUnchanged: !resolution.userVisibleEligible
        )
    }

    private static func delta(
        legacy: Double,
        shadow: Double?,
        source: PowerResolutionSource?
    ) -> PowerShadowDelta {
        PowerShadowDelta(
            legacyWatts: legacy,
            shadowWatts: shadow,
            deltaWatts: shadow.map { $0 - legacy },
            shadowSource: source
        )
    }
}
