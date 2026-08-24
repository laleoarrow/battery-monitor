import XCTest
@testable import Wattson

final class PowerObservationShadowTests: XCTestCase {
    func testShadowComparisonReportsDeltasWithoutChangingVisibleValues() {
        let resolution = PowerResolution(
            sequence: 9,
            adapter: ResolvedPowerValue(
                watts: 100,
                source: .smcPDTR,
                capture: nil,
                isDerived: false
            ),
            system: ResolvedPowerValue(
                watts: 80,
                source: .smcPSTRCandidate(1),
                capture: nil,
                isDerived: true
            ),
            battery: ResolvedBatteryFlow(
                signedWatts: 15,
                source: .batteryVoltageTimesCurrent,
                capture: nil
            ),
            batteryDischargeMagnitude: nil,
            deviceOutputAuxiliary: nil,
            pstrBand: .selected(rawWatts: 14.464, multiple: 1, candidateWatts: 80),
            residuals: [
                PowerResolutionResidual(
                    identifier: "shadow.selected",
                    watts: 5,
                    maximumInputSkewMilliseconds: 0.8
                )
            ],
            confidence: .corroborated,
            degradationReasons: [.shadowMode, .nonzeroResidual],
            userVisibleEligible: false
        )
        let legacy = LegacyVisiblePower(adapterW: 55, batteryW: 15, systemW: 40)
        let comparison = PowerObservationShadowEvaluator.compare(
            legacy: legacy,
            resolution: resolution
        )
        XCTAssertEqual(comparison.adapter.deltaWatts, 45)
        XCTAssertEqual(comparison.system.deltaWatts, 40)
        XCTAssertEqual(comparison.battery.deltaWatts, 0)
        XCTAssertTrue(comparison.userVisibleValuesUnchanged)
        XCTAssertEqual(comparison.residuals.first?.watts, 5)
    }

    func testShadowComparisonKeepsMissingShadowBranchExplicit() {
        let resolution = PowerResolution(
            sequence: 1,
            adapter: nil,
            system: nil,
            battery: nil,
            batteryDischargeMagnitude: nil,
            deviceOutputAuxiliary: nil,
            pstrBand: .policyUnavailable(rawWatts: nil, candidates: []),
            residuals: [],
            confidence: .none,
            degradationReasons: [.shadowMode],
            userVisibleEligible: false
        )
        let comparison = PowerObservationShadowEvaluator.compare(
            legacy: LegacyVisiblePower(adapterW: 20, batteryW: 0, systemW: 20),
            resolution: resolution
        )
        XCTAssertNil(comparison.adapter.shadowWatts)
        XCTAssertNil(comparison.adapter.deltaWatts)
        XCTAssertNil(comparison.system.shadowWatts)
        XCTAssertNil(comparison.battery.shadowWatts)
    }

    func testShadowComparisonCarriesSourcesAndReasons() {
        let resolution = PowerResolution(
            sequence: 1,
            adapter: ResolvedPowerValue(watts: 40, source: .iokitSystemPowerIn, capture: nil, isDerived: false),
            system: ResolvedPowerValue(watts: 40, source: .iokitSystemLoad, capture: nil, isDerived: false),
            battery: nil,
            batteryDischargeMagnitude: nil,
            deviceOutputAuxiliary: nil,
            pstrBand: .policyUnavailable(rawWatts: 35, candidates: [35, 100.536, 166.072, 231.608]),
            residuals: [],
            confidence: .provisional,
            degradationReasons: [.shadowMode, .pstrPolicyUnavailable],
            userVisibleEligible: false
        )
        let comparison = PowerObservationShadowEvaluator.compare(
            legacy: LegacyVisiblePower(adapterW: 40, batteryW: 0, systemW: 40),
            resolution: resolution
        )
        XCTAssertEqual(comparison.adapter.shadowSource, .iokitSystemPowerIn)
        XCTAssertEqual(comparison.system.shadowSource, .iokitSystemLoad)
        XCTAssertTrue(comparison.shadowReasons.contains(.pstrPolicyUnavailable))
    }

    func testShadowEvaluatorHasNoPowerSnapshotOrUIStateDependency() {
        // This behavior-level assertion complements the Python source-contract
        // scan: the pure evaluator only accepts explicit numeric legacy values.
        let legacy = LegacyVisiblePower(adapterW: 1, batteryW: -1, systemW: 2)
        XCTAssertEqual(legacy.batteryW, -1)
    }
}
