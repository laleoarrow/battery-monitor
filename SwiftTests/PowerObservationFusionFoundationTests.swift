import XCTest
@testable import Wattson

final class PowerObservationFusionFoundationTests: XCTestCase {
    func testUnconfiguredBandPolicyNeverSelectsCandidate() throws {
        var tracker = PSTRBandTracker()
        let fixture = try makeRawObservation(
            pdtr: 80,
            pstr: 36.44,
            systemLoad: 101.976,
            systemPowerIn: 110,
            batteryVI: 8
        )
        let events: [PSTRBandEvent] = [
            .normal,
            .powerSourceTransition,
            .sleepWake,
            .helperRestart,
            .rawSourceIdentityChange,
            .sourceLoss,
            .pstrDataTypeChange,
        ]
        for event in events {
            let decision = tracker.evaluate(
                rawPSTR: fixture.smc.key("PSTR"),
                candidates: fixture.evidence.pstrModulo.candidates,
                anchors: PowerObservationFusion.anchors(from: fixture.battery),
                event: event,
                finalizedAtContinuousNanoseconds: fixture.finalizedAtContinuousNanoseconds,
                policy: nil
            )
            guard case let .policyUnavailable(raw, candidates) = decision else {
                return XCTFail("nil policy must remain unavailable for \(event)")
            }
            XCTAssertEqual(raw, 36.44)
            XCTAssertEqual(candidates, [36.44, 101.976, 167.512, 233.048])
        }
    }

    func testBandTrackerRejectsStaleAnchors() throws {
        var tracker = PSTRBandTracker()
        let fixture = try makeRawObservation(pdtr: 80, pstr: 36.44, systemLoad: 101.976)
        let configured = policy(required: 2)
        let goodAnchors = PowerObservationFusion.anchors(from: fixture.battery)
        guard case .pending = tracker.evaluate(
            rawPSTR: fixture.smc.key("PSTR"),
            candidates: fixture.evidence.pstrModulo.candidates,
            anchors: goodAnchors,
            event: .normal,
            finalizedAtContinuousNanoseconds: 900,
            policy: configured
        ) else { return XCTFail("first eligible anchor should start persistence") }
        guard case .selected = tracker.evaluate(
            rawPSTR: fixture.smc.key("PSTR"),
            candidates: fixture.evidence.pstrModulo.candidates,
            anchors: goodAnchors,
            event: .normal,
            finalizedAtContinuousNanoseconds: 950,
            policy: configured
        ) else { return XCTFail("eligible anchor should reach selected before loss") }
        let stale = try FreshnessEvidence(
            evaluatedAtContinuousNanoseconds: 1_000,
            ageMilliseconds: nil,
            updateToken: "a",
            unchangedSinceContinuousNanoseconds: 0,
            unchangedForMilliseconds: 1,
            assessment: .stale,
            basis: .fixtureAnnotation
        )
        let anchor = PSTRBandAnchor(
            identifier: "stale",
            watts: 101.976,
            capture: try interval(100, 110),
            freshness: stale
        )
        guard case let .ineligible(_, _, reasons) = tracker.evaluate(
            rawPSTR: fixture.smc.key("PSTR"),
            candidates: fixture.evidence.pstrModulo.candidates,
            anchors: [anchor],
            event: .normal,
            finalizedAtContinuousNanoseconds: 1_000,
            policy: configured
        ) else { return XCTFail("stale anchor must be ineligible") }
        XCTAssertTrue(reasons.contains(.pstrEvidenceInsufficient))
        guard case let .pending(_, _, _, count, _) = tracker.evaluate(
            rawPSTR: fixture.smc.key("PSTR"),
            candidates: fixture.evidence.pstrModulo.candidates,
            anchors: goodAnchors,
            event: .normal,
            finalizedAtContinuousNanoseconds: 1_100,
            policy: configured
        ) else { return XCTFail("eligible-anchor loss must reset persistence") }
        XCTAssertEqual(count, 1)
    }

    func testBandTrackerTreatsUnknownAndUnconfiguredUnchangedAnchorsAsIneligible() throws {
        var tracker = PSTRBandTracker()
        let fixture = try makeRawObservation(pdtr: 80, pstr: 36.44, systemLoad: 101.976)
        let unknown = PSTRBandAnchor(
            identifier: "unknown",
            watts: 101.976,
            capture: try interval(100, 110),
            freshness: .unknown(at: 110)
        )
        let unchanged = PSTRBandAnchor(
            identifier: "unchanged",
            watts: 101.976,
            capture: try interval(100, 110),
            freshness: try FreshnessEvidence(
                evaluatedAtContinuousNanoseconds: 110,
                ageMilliseconds: nil,
                updateToken: "token",
                unchangedSinceContinuousNanoseconds: 100,
                unchangedForMilliseconds: 0.000_01,
                assessment: .unchanged,
                basis: .derivedUpdateToken
            )
        )
        for anchor in [unknown, unchanged] {
            guard case .ineligible = tracker.evaluate(
                rawPSTR: fixture.smc.key("PSTR"),
                candidates: fixture.evidence.pstrModulo.candidates,
                anchors: [anchor],
                event: .normal,
                finalizedAtContinuousNanoseconds: 200,
                policy: policy(required: 1)
            ) else { return XCTFail("anchor must remain record-only without configured freshness") }
        }
    }

    func testBandTrackerUsesUnchangedAnchorOnlyWithinExplicitPolicyWindow() throws {
        var tracker = PSTRBandTracker()
        let fixture = try makeRawObservation(pdtr: 80, pstr: 36.44, systemLoad: 101.976)
        let freshness = try FreshnessEvidence(
            evaluatedAtContinuousNanoseconds: 110,
            ageMilliseconds: nil,
            updateToken: nil,
            unchangedSinceContinuousNanoseconds: 0,
            unchangedForMilliseconds: 5,
            assessment: .unchanged,
            basis: .sourceReported
        )
        let anchor = PSTRBandAnchor(
            identifier: "bounded-unchanged",
            watts: 101.976,
            capture: try interval(100, 110),
            freshness: freshness
        )
        let configured = PSTRBandPolicy(
            maximumAnchorSkewMilliseconds: 10,
            maximumUnchangedAnchorMilliseconds: 5,
            maximumBestCandidateErrorWatts: 0.01,
            minimumRunnerUpMarginWatts: 10,
            requiredConsecutiveSamples: 1,
            maximumPersistenceGapMilliseconds: 1_000
        )
        guard case .selected = tracker.evaluate(
            rawPSTR: fixture.smc.key("PSTR"),
            candidates: fixture.evidence.pstrModulo.candidates,
            anchors: [anchor],
            event: .normal,
            finalizedAtContinuousNanoseconds: 200,
            policy: configured
        ) else { return XCTFail("explicitly bounded unchanged anchor should be eligible") }

        var noBasisTracker = PSTRBandTracker()
        let noBasis = PSTRBandAnchor(
            identifier: anchor.identifier,
            watts: anchor.watts,
            capture: anchor.capture,
            freshness: try FreshnessEvidence(
                evaluatedAtContinuousNanoseconds: 110,
                ageMilliseconds: nil,
                updateToken: nil,
                unchangedSinceContinuousNanoseconds: 0,
                unchangedForMilliseconds: 5,
                assessment: .unchanged,
                basis: .none
            )
        )
        guard case .ineligible = noBasisTracker.evaluate(
            rawPSTR: fixture.smc.key("PSTR"),
            candidates: fixture.evidence.pstrModulo.candidates,
            anchors: [noBasis],
            event: .normal,
            finalizedAtContinuousNanoseconds: 200,
            policy: configured
        ) else { return XCTFail("unchanged evidence without a basis must remain ineligible") }

        var expiredTracker = PSTRBandTracker()
        let expired = PSTRBandAnchor(
            identifier: anchor.identifier,
            watts: anchor.watts,
            capture: anchor.capture,
            freshness: try FreshnessEvidence(
                evaluatedAtContinuousNanoseconds: 110,
                ageMilliseconds: nil,
                updateToken: "token",
                unchangedSinceContinuousNanoseconds: 0,
                unchangedForMilliseconds: 5.001,
                assessment: .unchanged,
                basis: .derivedUpdateToken
            )
        )
        guard case .ineligible = expiredTracker.evaluate(
            rawPSTR: fixture.smc.key("PSTR"),
            candidates: fixture.evidence.pstrModulo.candidates,
            anchors: [expired],
            event: .normal,
            finalizedAtContinuousNanoseconds: 200,
            policy: configured
        ) else { return XCTFail("expired unchanged anchor must be rejected") }
    }

    func testAutomaticPSTRAnchorsUseSystemLoadButNotSystemPowerIn() throws {
        let fixture = try makeRawObservation(
            pdtr: 100,
            pstr: 36.44,
            systemLoad: 101.976,
            systemPowerIn: 110
        )
        let anchors = PowerObservationFusion.anchors(from: fixture.battery)
        XCTAssertEqual(anchors.map(\.identifier), ["battery.powerTelemetry.systemLoad"])
    }

    func testBandTrackerRejectsAnchorOutsideConfiguredSkew() throws {
        var tracker = PSTRBandTracker()
        let fixture = try makeRawObservation(pdtr: 80, pstr: 36.44, systemLoad: 101.976)
        let anchor = PSTRBandAnchor(
            identifier: "late",
            watts: 101.976,
            capture: try interval(1_000_000_000, 1_000_000_000),
            freshness: changed(at: 1_000_000_000)
        )
        guard case .ineligible = tracker.evaluate(
            rawPSTR: fixture.smc.key("PSTR"),
            candidates: fixture.evidence.pstrModulo.candidates,
            anchors: [anchor],
            event: .normal,
            finalizedAtContinuousNanoseconds: 1_000_000_000,
            policy: policy(required: 1, skew: 1)
        ) else { return XCTFail("out-of-skew anchor must be ineligible") }
    }

    func testBandTrackerReportsAmbiguityWhenRunnerUpMarginIsTooSmall() throws {
        var tracker = PSTRBandTracker()
        let stable = try makeRawObservation(
            pdtr: 80,
            pstr: 36.44,
            systemLoad: 101.976
        )
        _ = tracker.evaluate(
            rawPSTR: stable.smc.key("PSTR"),
            candidates: stable.evidence.pstrModulo.candidates,
            anchors: PowerObservationFusion.anchors(from: stable.battery),
            event: .normal,
            finalizedAtContinuousNanoseconds: 100,
            policy: policy(required: 2)
        )
        guard case .selected = tracker.evaluate(
            rawPSTR: stable.smc.key("PSTR"),
            candidates: stable.evidence.pstrModulo.candidates,
            anchors: PowerObservationFusion.anchors(from: stable.battery),
            event: .normal,
            finalizedAtContinuousNanoseconds: 150,
            policy: policy(required: 2)
        ) else { return XCTFail("fixture must reach selected before ambiguity") }
        let fixture = try makeRawObservation(pdtr: 80, pstr: 32.768, systemLoad: 65.536)
        let anchor = PSTRBandAnchor(
            identifier: "midpoint",
            watts: 65.536,
            capture: try interval(100, 110),
            freshness: changed(at: 110)
        )
        guard case let .ambiguous(_, _, best, runnerUp) = tracker.evaluate(
            rawPSTR: fixture.smc.key("PSTR"),
            candidates: fixture.evidence.pstrModulo.candidates,
            anchors: [anchor],
            event: .normal,
            finalizedAtContinuousNanoseconds: 200,
            policy: PSTRBandPolicy(
                maximumAnchorSkewMilliseconds: 1,
                maximumUnchangedAnchorMilliseconds: nil,
                maximumBestCandidateErrorWatts: 40,
                minimumRunnerUpMarginWatts: 1,
                requiredConsecutiveSamples: 1,
                maximumPersistenceGapMilliseconds: 1_000
            )
        ) else { return XCTFail("equidistant candidates must be ambiguous") }
        XCTAssertNotEqual(best, runnerUp)

        guard case let .pending(_, multiple, _, count, _) = tracker.evaluate(
            rawPSTR: stable.smc.key("PSTR"),
            candidates: stable.evidence.pstrModulo.candidates,
            anchors: PowerObservationFusion.anchors(from: stable.battery),
            event: .normal,
            finalizedAtContinuousNanoseconds: 300,
            policy: policy(required: 2)
        ) else { return XCTFail("ambiguity must reset persistence") }
        XCTAssertEqual(multiple, 1)
        XCTAssertEqual(count, 1)
    }

    func testBandTrackerRequiresConfiguredPersistenceBeforeSelection() throws {
        var tracker = PSTRBandTracker()
        let fixture = try makeRawObservation(pdtr: 110, pstr: 36.44, systemLoad: 101.976)
        let anchors = PowerObservationFusion.anchors(from: fixture.battery)
        let first = tracker.evaluate(
            rawPSTR: fixture.smc.key("PSTR"),
            candidates: fixture.evidence.pstrModulo.candidates,
            anchors: anchors,
            event: .normal,
            finalizedAtContinuousNanoseconds: 200,
            policy: policy(required: 2)
        )
        guard case let .pending(_, multiple, _, count, required) = first else {
            return XCTFail("first sample must be pending")
        }
        XCTAssertEqual(multiple, 1)
        XCTAssertEqual(count, 1)
        XCTAssertEqual(required, 2)
        let second = tracker.evaluate(
            rawPSTR: fixture.smc.key("PSTR"),
            candidates: fixture.evidence.pstrModulo.candidates,
            anchors: anchors,
            event: .normal,
            finalizedAtContinuousNanoseconds: 300,
            policy: policy(required: 2)
        )
        guard case let .selected(_, selected, watts) = second else {
            return XCTFail("second sample should select")
        }
        XCTAssertEqual(selected, 1)
        XCTAssertEqual(watts, 101.976)

        let differentBest = try makeRawObservation(
            pdtr: 110,
            pstr: 36.44,
            systemLoad: 36.44
        )
        guard case let .pending(_, multiple, _, count, _) = tracker.evaluate(
            rawPSTR: differentBest.smc.key("PSTR"),
            candidates: differentBest.evidence.pstrModulo.candidates,
            anchors: PowerObservationFusion.anchors(from: differentBest.battery),
            event: .normal,
            finalizedAtContinuousNanoseconds: 400,
            policy: policy(required: 2)
        ) else { return XCTFail("a different best multiple must restart persistence") }
        XCTAssertEqual(multiple, 0)
        XCTAssertEqual(count, 1)
    }

    func testBandTrackerResetsPersistenceOnSleepWakeAndSourceTransition() throws {
        let fixture = try makeRawObservation(pdtr: 110, pstr: 36.44, systemLoad: 101.976)
        let anchors = PowerObservationFusion.anchors(from: fixture.battery)
        let events: [PSTRBandEvent] = [
            .powerSourceTransition,
            .sleepWake,
            .helperRestart,
            .rawSourceIdentityChange,
            .sourceLoss,
            .pstrDataTypeChange,
        ]
        for event in events {
            var tracker = PSTRBandTracker()
            _ = tracker.evaluate(
                rawPSTR: fixture.smc.key("PSTR"), candidates: fixture.evidence.pstrModulo.candidates,
                anchors: anchors, event: .normal, finalizedAtContinuousNanoseconds: 200,
                policy: policy(required: 2)
            )
            guard case .selected = tracker.evaluate(
                rawPSTR: fixture.smc.key("PSTR"), candidates: fixture.evidence.pstrModulo.candidates,
                anchors: anchors, event: .normal, finalizedAtContinuousNanoseconds: 220,
                policy: policy(required: 2)
            ) else { return XCTFail("fixture must reach selected before reset") }
            guard case .ineligible = tracker.evaluate(
                rawPSTR: fixture.smc.key("PSTR"), candidates: fixture.evidence.pstrModulo.candidates,
                anchors: anchors, event: event, finalizedAtContinuousNanoseconds: 250,
                policy: policy(required: 2)
            ) else { return XCTFail("\(event) must reset") }
            guard case let .pending(_, _, _, count, _) = tracker.evaluate(
                rawPSTR: fixture.smc.key("PSTR"), candidates: fixture.evidence.pstrModulo.candidates,
                anchors: anchors, event: .normal, finalizedAtContinuousNanoseconds: 300,
                policy: policy(required: 2)
            ) else { return XCTFail("post-event sample must restart persistence") }
            XCTAssertEqual(count, 1)
        }
    }

    func testBandTrackerResetsAfterConfiguredSampleGap() throws {
        var tracker = PSTRBandTracker()
        let fixture = try makeRawObservation(pdtr: 110, pstr: 36.44, systemLoad: 101.976)
        let anchors = PowerObservationFusion.anchors(from: fixture.battery)
        _ = tracker.evaluate(
            rawPSTR: fixture.smc.key("PSTR"), candidates: fixture.evidence.pstrModulo.candidates,
            anchors: anchors, event: .normal, finalizedAtContinuousNanoseconds: 0,
            policy: policy(required: 2, gap: 1)
        )
        guard case let .pending(_, _, _, count, _) = tracker.evaluate(
            rawPSTR: fixture.smc.key("PSTR"), candidates: fixture.evidence.pstrModulo.candidates,
            anchors: anchors, event: .normal, finalizedAtContinuousNanoseconds: 2_000_000,
            policy: policy(required: 2, gap: 1)
        ) else { return XCTFail("gap should restart persistence") }
        XCTAssertEqual(count, 1)
        guard case .selected = tracker.evaluate(
            rawPSTR: fixture.smc.key("PSTR"), candidates: fixture.evidence.pstrModulo.candidates,
            anchors: anchors, event: .normal, finalizedAtContinuousNanoseconds: 2_000_100,
            policy: policy(required: 2, gap: 1)
        ) else { return XCTFail("post-gap continuity should be selectable") }
        guard case let .pending(_, _, _, regressedCount, _) = tracker.evaluate(
            rawPSTR: fixture.smc.key("PSTR"), candidates: fixture.evidence.pstrModulo.candidates,
            anchors: anchors, event: .normal, finalizedAtContinuousNanoseconds: 1_000_000,
            policy: policy(required: 2, gap: 1)
        ) else { return XCTFail("monotonic regression must restart persistence") }
        XCTAssertEqual(regressedCount, 1)
    }

    func testResolutionSourceAndReasonEncodeAsOpenStrings() throws {
        let sourceData = try JSONEncoder().encode(PowerResolutionSource.smcPDTR)
        let reasonData = try JSONEncoder().encode(PowerResolutionReason.pstrAmbiguous)
        XCTAssertEqual(String(decoding: sourceData, as: UTF8.self), "\"smc.PDTR\"")
        XCTAssertEqual(String(decoding: reasonData, as: UTF8.self), "\"pstr-ambiguous\"")
        XCTAssertEqual(
            try JSONDecoder().decode(PowerResolutionSource.self, from: Data("\"future.source\"".utf8)),
            PowerResolutionSource("future.source")
        )
    }

    func testFusionNeverSelectsNegativeDirectSourceOrLoadAsResolvedPower() throws {
        let fixture = try makeRawObservation(
            pdtr: -1,
            pstr: nil,
            systemLoad: -2,
            systemPowerIn: -3,
            batteryVI: 0
        )
        let resolution = PowerObservationFusion.resolve(
            rawObservation: fixture,
            pstrDecision: .policyUnavailable(
                rawWatts: nil,
                candidates: []
            )
        )
        XCTAssertNil(resolution.adapter)
        XCTAssertNil(resolution.system)
        XCTAssertTrue(resolution.degradationReasons.contains(.invalidDirectValue))
        XCTAssertTrue(resolution.degradationReasons.contains(.adapterUnavailable))
        XCTAssertTrue(resolution.degradationReasons.contains(.systemUnavailable))
        XCTAssertEqual(fixture.smc.key("PDTR")?.decodedWatts, -1)
        XCTAssertEqual(fixture.battery.powerTelemetry.systemLoad.watts, -2)
    }

    func testFusionPrefersDirectPDTRForAdapterWithoutChangingIt() throws {
        let fixture = try makeRawObservation(
            pdtr: 80,
            pstr: 40,
            systemLoad: 55,
            systemPowerIn: 70,
            batteryVI: 15
        )
        let resolution = PowerObservationFusion.resolve(
            rawObservation: fixture,
            pstrDecision: .policyUnavailable(rawWatts: 40, candidates: fixture.evidence.pstrModulo.candidates.map(\.candidateWatts))
        )
        XCTAssertEqual(resolution.adapter?.watts, 80)
        XCTAssertEqual(resolution.adapter?.source, .smcPDTR)
        XCTAssertEqual(fixture.smc.key("PDTR")?.decodedWatts, 80)
    }

    func testFusionUsesDirectIOKitSystemLoadWhilePSTRBandIsUnresolved() throws {
        let fixture = try makeRawObservation(pdtr: 80, pstr: 40, systemLoad: 55)
        let resolution = PowerObservationFusion.resolve(
            rawObservation: fixture,
            pstrDecision: .policyUnavailable(rawWatts: 40, candidates: fixture.evidence.pstrModulo.candidates.map(\.candidateWatts))
        )
        XCTAssertEqual(resolution.system?.watts, 55)
        XCTAssertEqual(resolution.system?.source, .iokitSystemLoad)
        XCTAssertTrue(resolution.degradationReasons.contains(.pstrPolicyUnavailable))
    }

    func testFusionUsesSelectedPSTRCandidateOnlyWhenTrackerSelectedIt() throws {
        let fixture = try makeRawObservation(pdtr: 110, pstr: 36.44, systemLoad: 101.976)
        var tracker = PSTRBandTracker()
        let configured = policy(required: 2)
        let pendingDecision = tracker.evaluate(
            rawPSTR: fixture.smc.key("PSTR"),
            candidates: fixture.evidence.pstrModulo.candidates,
            anchors: PowerObservationFusion.anchors(from: fixture.battery),
            event: .normal,
            finalizedAtContinuousNanoseconds: 200,
            policy: configured
        )
        guard case .pending = pendingDecision else {
            return XCTFail("first eligible sample must remain pending")
        }
        let pendingResolution = PowerObservationFusion.resolve(
            rawObservation: fixture,
            pstrDecision: pendingDecision
        )
        XCTAssertEqual(pendingResolution.system?.source, .iokitSystemLoad)

        let selectedDecision = tracker.evaluate(
            rawPSTR: fixture.smc.key("PSTR"),
            candidates: fixture.evidence.pstrModulo.candidates,
            anchors: PowerObservationFusion.anchors(from: fixture.battery),
            event: .normal,
            finalizedAtContinuousNanoseconds: 300,
            policy: configured
        )
        guard case let .selected(raw, multiple, candidateWatts) = selectedDecision else {
            return XCTFail("second consecutive eligible sample must select")
        }
        XCTAssertEqual(raw, 36.44)
        XCTAssertEqual(multiple, 1)
        XCTAssertEqual(candidateWatts, 101.976)

        let resolution = PowerObservationFusion.resolve(
            rawObservation: fixture,
            pstrDecision: selectedDecision
        )
        XCTAssertEqual(resolution.system?.watts, 101.976)
        XCTAssertEqual(resolution.system?.source, .smcPSTRCandidate(1))
        XCTAssertTrue(resolution.system?.isDerived == true)
        XCTAssertEqual(fixture.smc.key("PSTR")?.decodedWatts, 36.44)
    }

    func testFusionUsesSignedBatteryVIAndNeverLetsPPBRChooseDirection() throws {
        let fixture = try makeRawObservation(pdtr: 50, pstr: 40, systemLoad: 40, batteryVI: -5, ppbr: 6)
        let resolution = PowerObservationFusion.resolve(
            rawObservation: fixture,
            pstrDecision: .policyUnavailable(rawWatts: 40, candidates: fixture.evidence.pstrModulo.candidates.map(\.candidateWatts))
        )
        XCTAssertEqual(resolution.battery?.signedWatts, -5)
        XCTAssertEqual(resolution.battery?.source, .batteryVoltageTimesCurrent)
        XCTAssertEqual(resolution.batteryDischargeMagnitude?.watts, 6)
        XCTAssertEqual(resolution.batteryDischargeMagnitude?.source, .smcPPBRMagnitude)
    }

    func testFusionDoesNotUseUnresolvedBatteryPowerAsSignedFlow() throws {
        let fixture = try makeRawObservation(
            pdtr: 50, pstr: 40, systemLoad: 40,
            telemetryBatteryPower: -10,
            batteryVI: nil,
            ppbr: 10
        )
        let resolution = PowerObservationFusion.resolve(
            rawObservation: fixture,
            pstrDecision: .policyUnavailable(rawWatts: 40, candidates: fixture.evidence.pstrModulo.candidates.map(\.candidateWatts))
        )
        XCTAssertNil(resolution.battery)
        XCTAssertTrue(resolution.degradationReasons.contains(.batteryDirectionUnavailable))
    }

    func testDeviceOutputRemainsAuxiliaryAndIsNotAddedToSystem() throws {
        let fixture = try makeRawObservation(
            pdtr: 60, pstr: 40, systemLoad: 40,
            batteryVI: 20,
            deviceOutput: 7
        )
        let resolution = PowerObservationFusion.resolve(
            rawObservation: fixture,
            pstrDecision: .policyUnavailable(rawWatts: 40, candidates: fixture.evidence.pstrModulo.candidates.map(\.candidateWatts))
        )
        XCTAssertEqual(resolution.system?.watts, 40)
        XCTAssertEqual(resolution.deviceOutputAuxiliary?.watts, 7)
    }

    func testFusionPreservesNonzeroResidualInsteadOfForcingConservation() throws {
        let fixture = try makeRawObservation(pdtr: 100, pstr: 40, systemLoad: 40, batteryVI: 15)
        let resolution = PowerObservationFusion.resolve(
            rawObservation: fixture,
            pstrDecision: .selected(rawWatts: 40, multiple: 0, candidateWatts: 40)
        )
        XCTAssertTrue(resolution.residuals.contains { $0.identifier == "smc.direct" && $0.watts == 45 })
        XCTAssertTrue(resolution.degradationReasons.contains(.nonzeroResidual))
        XCTAssertEqual(resolution.adapter?.watts, 100)
        XCTAssertEqual(resolution.system?.watts, 40)
        XCTAssertEqual(resolution.battery?.signedWatts, 15)

        let tinyFixture = try makeRawObservation(
            pdtr: 40.000_000_5,
            pstr: 40,
            systemLoad: 40,
            batteryVI: 0
        )
        let tinyResolution = PowerObservationFusion.resolve(
            rawObservation: tinyFixture,
            pstrDecision: .selected(rawWatts: 40, multiple: 0, candidateWatts: 40)
        )
        XCTAssertTrue(tinyResolution.residuals.contains { $0.watts != 0 })
        XCTAssertTrue(tinyResolution.degradationReasons.contains(.nonzeroResidual))
    }

    func testFoundationResolutionCanNeverSwitchUserVisibleValues() throws {
        let fixture = try makeRawObservation(pdtr: 100, pstr: 40, systemLoad: 40, batteryVI: 15)
        let resolution = PowerObservationFusion.resolve(
            rawObservation: fixture,
            pstrDecision: .selected(rawWatts: 40, multiple: 0, candidateWatts: 40)
        )
        XCTAssertFalse(resolution.userVisibleEligible)
        XCTAssertTrue(resolution.degradationReasons.contains(.shadowMode))

        let injected = PowerResolution(
            sequence: resolution.sequence,
            adapter: resolution.adapter,
            system: resolution.system,
            battery: resolution.battery,
            batteryDischargeMagnitude: resolution.batteryDischargeMagnitude,
            deviceOutputAuxiliary: resolution.deviceOutputAuxiliary,
            pstrBand: resolution.pstrBand,
            residuals: resolution.residuals,
            confidence: resolution.confidence,
            degradationReasons: resolution.degradationReasons,
            userVisibleEligible: true
        )
        XCTAssertFalse(injected.userVisibleEligible)
        XCTAssertTrue(PowerObservationShadowEvaluator.compare(
            legacy: LegacyVisiblePower(adapterW: 1, batteryW: 2, systemW: 3),
            resolution: injected
        ).userVisibleValuesUnchanged)

        let encoded = try JSONEncoder().encode(resolution)
        let falseJSON = String(decoding: encoded, as: UTF8.self)
        let trueJSON = falseJSON.replacingOccurrences(
            of: "\"userVisibleEligible\":false",
            with: "\"userVisibleEligible\":true"
        )
        XCTAssertNotEqual(trueJSON, falseJSON)
        let decoded = try JSONDecoder().decode(
            PowerResolution.self,
            from: Data(trueJSON.utf8)
        )
        XCTAssertFalse(decoded.userVisibleEligible)
    }

    func testLegacyV4FallbackIsExplicitlyDegradedAndHasNoRawTiming() throws {
        let capture = try interval(0, 1)
        let battery = AppleSmartBatteryObservation.canonicalFixtureMissing(capture: capture)
        let sources = PowerFusionSources(
            sequence: 1,
            finalizedAtContinuousNanoseconds: 1,
            battery: battery,
            helperResult: .legacyV4(HelperClient.LivePower(adapterW: 30, systemW: 20))
        )
        let resolution = PowerObservationFusion.resolve(
            sources: sources,
            pstrDecision: .policyUnavailable(rawWatts: nil, candidates: [])
        )
        XCTAssertEqual(resolution.adapter?.source, .legacyV4Adapter)
        XCTAssertEqual(resolution.system?.source, .legacyV4System)
        XCTAssertEqual(resolution.confidence, .degraded)
        XCTAssertTrue(resolution.degradationReasons.contains(.legacyV4NoRawEvidence))
    }

    func testUnchangedFreshnessIsNotSilentlyPromotedToStale() throws {
        let fixture = try makeRawObservation(pdtr: 50, pstr: 40, systemLoad: 40, freshness: .unchanged)
        let resolution = PowerObservationFusion.resolve(
            rawObservation: fixture,
            pstrDecision: .policyUnavailable(rawWatts: 40, candidates: fixture.evidence.pstrModulo.candidates.map(\.candidateWatts))
        )
        XCTAssertTrue(resolution.degradationReasons.contains(.freshnessUnchanged))
        XCTAssertFalse(resolution.degradationReasons.contains(PowerResolutionReason("stale")))
    }

    func testStaleTelemetryIsExplicitlyDegraded() throws {
        let adapterFallbackFixture = try makeRawObservation(
            pdtr: nil,
            pstr: 40,
            systemLoad: 40,
            systemPowerIn: 50,
            freshness: .stale
        )
        let adapterFallbackResolution = PowerObservationFusion.resolve(
            rawObservation: adapterFallbackFixture,
            pstrDecision: .selected(rawWatts: 40, multiple: 0, candidateWatts: 40)
        )
        XCTAssertNil(adapterFallbackResolution.adapter)
        XCTAssertEqual(adapterFallbackResolution.system?.source, .smcPSTRCandidate(0))
        XCTAssertTrue(adapterFallbackResolution.degradationReasons.contains(.freshnessStale))
        XCTAssertTrue(adapterFallbackResolution.degradationReasons.contains(.adapterUnavailable))
        XCTAssertEqual(adapterFallbackResolution.confidence, .degraded)

        let systemFallbackFixture = try makeRawObservation(
            pdtr: 50,
            pstr: 40,
            systemLoad: 40,
            systemPowerIn: 50,
            freshness: .stale
        )
        let systemFallbackResolution = PowerObservationFusion.resolve(
            rawObservation: systemFallbackFixture,
            pstrDecision: .policyUnavailable(
                rawWatts: 40,
                candidates: systemFallbackFixture.evidence.pstrModulo.candidates.map(\.candidateWatts)
            )
        )
        XCTAssertEqual(systemFallbackResolution.adapter?.source, .smcPDTR)
        XCTAssertNil(systemFallbackResolution.system)
        XCTAssertTrue(systemFallbackResolution.degradationReasons.contains(.freshnessStale))
        XCTAssertTrue(systemFallbackResolution.degradationReasons.contains(.systemUnavailable))
        XCTAssertEqual(systemFallbackResolution.confidence, .degraded)
    }

    // MARK: fixture builders

    private func makeRawObservation(
        pdtr: Double?,
        pstr: Double?,
        systemLoad: Double?,
        systemPowerIn: Double? = nil,
        telemetryBatteryPower: Double? = nil,
        batteryVI: Double? = nil,
        ppbr: Double? = 1,
        deviceOutput: Double? = nil,
        freshness: FreshnessAssessment = .changed
    ) throws -> RawPowerObservation {
        let capture = try interval(100, 110)
        let telemetryFreshness = try FreshnessEvidence(
            evaluatedAtContinuousNanoseconds: 110,
            ageMilliseconds: nil,
            updateToken: "token",
            unchangedSinceContinuousNanoseconds: 100,
            unchangedForMilliseconds: freshness == .unchanged ? 10 : 0,
            assessment: freshness,
            basis: freshness == .stale ? .sourceReported : .derivedUpdateToken
        )
        let telemetry = BatteryPowerTelemetryObservation(
            presence: .present,
            capture: capture,
            systemPowerIn: try reading(
                "battery.powerTelemetry.systemPowerIn",
                source: .appleSmartBatteryPowerTelemetry,
                semantic: .systemInput,
                watts: systemPowerIn,
                capture: capture
            ),
            systemLoad: try reading(
                "battery.powerTelemetry.systemLoad",
                source: .appleSmartBatteryPowerTelemetry,
                semantic: .systemLoad,
                watts: systemLoad,
                capture: capture
            ),
            batteryPower: try reading(
                "battery.powerTelemetry.batteryPower",
                source: .appleSmartBatteryPowerTelemetry,
                semantic: .firmwareBatteryPowerUnresolvedSign,
                watts: telemetryBatteryPower,
                capture: capture
            ),
            systemVoltageInNative: Observed<Int64>.canonicalFixtureMissing(
                identifier: "battery.powerTelemetry.systemVoltageIn",
                source: .appleSmartBatteryPowerTelemetry,
                kind: .raw,
                unit: .registryNative,
                capture: capture
            ),
            systemCurrentInNative: Observed<Int64>.canonicalFixtureMissing(
                identifier: "battery.powerTelemetry.systemCurrentIn",
                source: .appleSmartBatteryPowerTelemetry,
                kind: .raw,
                unit: .registryNative,
                capture: capture
            ),
            updateToken: "token",
            freshness: telemetryFreshness
        )
        let output = try deviceOutputObservation(deviceOutput, capture: capture)
        let battery = AppleSmartBatteryObservation(
            servicePresence: .present,
            capture: capture,
            currentCapacity: .canonicalFixtureMissing(
                identifier: "battery.currentCapacity", source: .appleSmartBatteryRegistry,
                kind: .raw, unit: .registryNative, capture: capture
            ),
            maxCapacity: .canonicalFixtureMissing(
                identifier: "battery.maxCapacity", source: .appleSmartBatteryRegistry,
                kind: .raw, unit: .registryNative, capture: capture
            ),
            externalConnected: .canonicalFixtureMissing(
                identifier: "battery.externalConnected", source: .appleSmartBatteryRegistry,
                kind: .hint, unit: .boolean, capture: capture
            ),
            isCharging: .canonicalFixtureMissing(
                identifier: "battery.isCharging", source: .appleSmartBatteryRegistry,
                kind: .hint, unit: .boolean, capture: capture
            ),
            voltageMillivolts: .canonicalFixtureMissing(
                identifier: "battery.voltageMillivolts", source: .appleSmartBatteryRegistry,
                kind: .measured, unit: .millivolts, capture: capture
            ),
            instantAmperageMilliamps: .canonicalFixtureMissing(
                identifier: "battery.instantAmperageMilliamps", source: .appleSmartBatteryRegistry,
                kind: .measured, unit: .milliamps, capture: capture
            ),
            averageAmperageMilliamps: .canonicalFixtureMissing(
                identifier: "battery.averageAmperageMilliamps", source: .appleSmartBatteryRegistry,
                kind: .measured, unit: .milliamps, capture: capture
            ),
            powerTelemetry: telemetry,
            adapterCapability: .canonicalFixtureMissing(capture: capture),
            deviceOutput: output
        )
        let keys = try [
            smcKey("PDTR", source: .smcPDTR, watts: pdtr, capture: capture),
            smcKey("PSTR", source: .smcPSTR, watts: pstr, capture: capture),
            smcKey("PPBR", source: .smcPPBR, watts: ppbr, capture: capture),
        ]
        let smc = try SMCObservation(
            connectionStatus: .opened,
            connectionCapture: capture,
            keys: keys
        )
        let anchors: [ModuloAnchor]
        if let systemLoad, systemLoad >= 0 {
            anchors = [ModuloAnchor(
                identifier: "battery.powerTelemetry.systemLoad",
                source: .appleSmartBatteryPowerTelemetry,
                watts: systemLoad,
                capture: capture
            )]
        } else {
            anchors = []
        }
        let batteryEvidence = try derivedReading(
            "evidence.batteryVoltageTimesCurrent",
            source: .derivedBatteryVI,
            semantic: .batteryVoltageTimesCurrent,
            watts: batteryVI,
            capture: capture
        )
        var balances: [PowerBalanceEvidence] = []
        if let systemPowerIn, let systemLoad, let telemetryBatteryPower {
            balances.append(PowerBalanceEvidence(
                identifier: "iokit.telemetry",
                adapterSource: .appleSmartBatteryPowerTelemetry,
                systemSource: .appleSmartBatteryPowerTelemetry,
                batterySource: .appleSmartBatteryPowerTelemetry,
                externalSource: nil,
                residualWatts: systemPowerIn - systemLoad - telemetryBatteryPower,
                maximumInputSkewMilliseconds: 0
            ))
        }
        if let pdtr, let pstr, let batteryVI {
            balances.append(PowerBalanceEvidence(
                identifier: "smc.direct",
                adapterSource: .smcPDTR,
                systemSource: .smcPSTR,
                batterySource: .derivedBatteryVI,
                externalSource: nil,
                residualWatts: pdtr - pstr - batteryVI,
                maximumInputSkewMilliseconds: 0
            ))
        }
        let evidence = RawPowerEvidence(
            batteryVoltageTimesCurrent: batteryEvidence,
            systemVoltageTimesCurrent: .canonicalFixtureMissing(
                identifier: "evidence.systemVoltageTimesCurrent",
                source: .derivedSystemInputVI,
                kind: .derived,
                semantic: .systemVoltageTimesCurrent,
                capture: capture
            ),
            timing: ObservationTimingEvidence(
                observationStartedContinuousNanoseconds: 100,
                observationEndedContinuousNanoseconds: 110,
                totalCaptureDurationMilliseconds: 0.000_01,
                smcKeySkewMilliseconds: 0,
                batteryMidpointMinusSMCMidpointMilliseconds: 0,
                absoluteBatterySMCSkewMilliseconds: 0
            ),
            pstrModulo: PSTRModuloEvidence(rawPSTRWatts: pstr, anchors: anchors),
            balances: balances
        )
        return try RawPowerObservation(
            sequence: 1,
            scenario: "fixture",
            finalizedAtContinuousNanoseconds: 110,
            battery: battery,
            smc: smc,
            evidence: evidence
        )
    }

    private func reading(
        _ identifier: String,
        source: ObservationSource,
        semantic: PowerSemantic,
        watts: Double?,
        capture: MonotonicInterval
    ) throws -> PowerReading {
        guard let watts else {
            return .canonicalFixtureMissing(
                identifier: identifier, source: source, kind: .measured,
                semantic: semantic, capture: capture
            )
        }
        return try PowerReading(
            identifier: identifier,
            source: source,
            kind: .measured,
            semantic: semantic,
            presence: .present,
            rawInteger: Int64((watts * 1_000).rounded()),
            rawFloatingPoint: nil,
            rawUnit: .milliwatts,
            watts: watts,
            capture: capture,
            freshness: changed(at: capture.endedContinuousNanoseconds),
            validationIssue: nil
        )
    }

    private func derivedReading(
        _ identifier: String,
        source: ObservationSource,
        semantic: PowerSemantic,
        watts: Double?,
        capture: MonotonicInterval
    ) throws -> PowerReading {
        guard let watts else {
            return .canonicalFixtureMissing(
                identifier: identifier, source: source, kind: .derived,
                semantic: semantic, capture: capture
            )
        }
        return try PowerReading(
            identifier: identifier,
            source: source,
            kind: .derived,
            semantic: semantic,
            presence: .present,
            rawInteger: nil,
            rawFloatingPoint: nil,
            rawUnit: nil,
            watts: watts,
            capture: capture,
            freshness: changed(at: capture.endedContinuousNanoseconds),
            validationIssue: nil
        )
    }

    private func smcKey(
        _ key: String,
        source: ObservationSource,
        watts: Double?,
        capture: MonotonicInterval
    ) throws -> SMCKeyObservation {
        SMCKeyObservation(
            key: key,
            source: source,
            status: watts == nil ? .keyUnavailable : .present,
            capture: capture,
            dataTypeFourCC: watts == nil ? nil : "flt ",
            rawBytesHex: watts == nil ? nil : "00000000",
            decodedWatts: watts,
            ioReturn: nil,
            validationIssue: watts == nil ? "fixture missing" : nil
        )
    }

    private func deviceOutputObservation(
        _ watts: Double?,
        capture: MonotonicInterval
    ) throws -> DeviceOutputObservation {
        guard let watts else { return .canonicalFixtureMissing(capture: capture) }
        let total = try PowerReading(
            identifier: "battery.deviceOutput.measuredTotalWatts",
            source: .derivedAggregate,
            kind: .derived,
            semantic: .deviceOutputMeasuredTotal,
            presence: .present,
            rawInteger: nil,
            rawFloatingPoint: nil,
            rawUnit: nil,
            watts: watts,
            capture: capture,
            freshness: changed(at: capture.endedContinuousNanoseconds),
            validationIssue: nil
        )
        let port = DeviceOutputPortObservation(
            arrayIndex: 0,
            portIndex: nil,
            locationIdentifierWasPresent: false,
            measuredWatts: try reading(
                "battery.deviceOutput.ports[0].measuredWatts",
                source: .appleSmartBatteryPowerOutWatts,
                semantic: .deviceOutput,
                watts: watts,
                capture: capture
            ),
            pdPowerRaw: .canonicalFixtureMissing(
                identifier: "battery.deviceOutput.ports[0].pdPowerRaw",
                source: .appleSmartBatteryPowerOutPDPower,
                kind: .raw,
                semantic: .unknown,
                capture: capture
            )
        )
        return DeviceOutputObservation(
            fieldPresence: .present,
            capture: capture,
            ports: [port],
            measuredTotalWatts: total,
            completeness: .complete
        )
    }

    private func interval(_ start: UInt64, _ end: UInt64) throws -> MonotonicInterval {
        try MonotonicInterval(
            startedContinuousNanoseconds: start,
            endedContinuousNanoseconds: end
        )
    }

    private func changed(at time: UInt64) -> FreshnessEvidence {
        try! FreshnessEvidence(
            evaluatedAtContinuousNanoseconds: time,
            ageMilliseconds: nil,
            updateToken: "token",
            unchangedSinceContinuousNanoseconds: time,
            unchangedForMilliseconds: 0,
            assessment: .changed,
            basis: .derivedUpdateToken
        )
    }

    private func policy(
        required: Int,
        skew: Double = 10,
        gap: Double = 1_000
    ) -> PSTRBandPolicy {
        PSTRBandPolicy(
            maximumAnchorSkewMilliseconds: skew,
            maximumUnchangedAnchorMilliseconds: nil,
            maximumBestCandidateErrorWatts: 0.01,
            minimumRunnerUpMarginWatts: 10,
            requiredConsecutiveSamples: required,
            maximumPersistenceGapMilliseconds: gap
        )
    }
}
