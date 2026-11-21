import AppKit
import XCTest
@testable import Wattson

final class PowerPresentationStateTests: XCTestCase {
    private func makeFlow() -> PowerFlowView {
        let flow = PowerFlowView()
        flow.frame = NSRect(
            x: 0, y: 0, width: PopoverStyle.contentWidth,
            height: PowerFlowView.preferredHeight
        )
        flow.layoutSubtreeIfNeeded()
        return flow
    }

    func testUnpluggedLowAndZeroPowerNeverUsesAdapterAsSource() {
        let flow = makeFlow()
        flow.setAnimationsEnabled(true)
        for watts in [0.0, 0.1, 0.3, 5.0] {
            flow.update(
                snapshot: PowerSnapshot(
                    percent: 80, plugged: false, adapterW: 0,
                    batteryW: -watts, systemW: watts
                ),
                animated: false
            )
            XCTAssertEqual(flow.topologyForTest, "batteryLed", "watts=\(watts)")
            XCTAssertEqual(flow.branchThicknessesForTest[0], 0)
            XCTAssertEqual(
                flow.branchThicknessesForTest[1],
                watts > 0 ? VisualEncoding.thickness(watts) : 0
            )
            if watts == 0 { XCTAssertNil(flow.flowMetricsForTest()) }
        }
    }

    func testZeroWattBranchesNeverKeepAnActivePowerFlow() {
        let flow = makeFlow()
        flow.setAnimationsEnabled(true)
        for snapshot in [
            PowerSnapshot(percent: 80, plugged: true, adapterW: 0,
                          batteryW: 0, systemW: 0),
            PowerSnapshot(percent: 80, plugged: true, adapterW: 20,
                          batteryW: 20, systemW: 0),
            PowerSnapshot(percent: 80, plugged: false, adapterW: 0,
                          batteryW: -12, systemW: 12, deviceOutputW: 12),
        ] {
            flow.update(snapshot: snapshot, animated: false)
            XCTAssertEqual(flow.branchThicknessesForTest[0], 0)
            if snapshot.totalInputW == 0 {
                XCTAssertEqual(flow.branchThicknessesForTest, [0, 0])
                XCTAssertNil(flow.flowMetricsForTest())
            }
        }
    }

    func testFailedReadingFreezesMotionUntilFreshReadingReturns() {
        let suiteName = testDefaultsSuite("PowerPresentation")
        let defaults = UserDefaults(suiteName: suiteName)!
        Settings.configureForTest(defaults: defaults)
        defer {
            Settings.resetTestConfiguration()
            defaults.removePersistentTestDomain(forName: suiteName)
        }
        let content = PopoverContentViewController()
        _ = content.view
        content.view.layoutSubtreeIfNeeded()
        content.setPresentationActive(true)
        let lastReading = PowerSnapshot(
            percent: 80, plugged: true, adapterW: 40,
            batteryW: 10, systemW: 30, deviceOutputW: 5
        )
        content.update(snapshot: lastReading, history: [40], peak: 40, degraded: false)
        content.setAnimationsEnabled(true)
        XCTAssertGreaterThan(content.runningModuleAnimationCountForTest, 0)

        content.update(snapshot: lastReading, history: [40], peak: 40, degraded: true)
        XCTAssertEqual(content.runningModuleAnimationCountForTest, 0)
        // Opening or changing display options must not restart stale motion.
        content.setAnimationsEnabled(false)
        content.setAnimationsEnabled(true)
        XCTAssertEqual(content.runningModuleAnimationCountForTest, 0)
        for module in [PopoverModule.flow, .ring, .lanes] {
            content.setModuleVisibleForTest(module, visible: false)
            content.setModuleVisibleForTest(module, visible: true)
        }
        XCTAssertEqual(content.runningModuleAnimationCountForTest, 0)

        content.update(snapshot: lastReading, history: [40], peak: 40, degraded: false)
        XCTAssertGreaterThan(content.runningModuleAnimationCountForTest, 0)
        content.update(snapshot: lastReading, history: [40], peak: 40, degraded: true)
        content.setAnimationsEnabled(false)
        content.update(snapshot: lastReading, history: [40], peak: 40, degraded: false)
        XCTAssertEqual(content.runningModuleAnimationCountForTest, 0)
    }

    func testIdleBatteryLabelsUseReportedFullStateInsteadOfPercentage() {
        let header = PopoverHeaderView()
        let flow = makeFlow()
        let ring = RingGaugeView()
        let lanes = LaneView()
        func strings(in view: NSView) -> [String] {
            let own = (view as? NSTextField).map { [$0.stringValue] } ?? []
            return own + view.subviews.flatMap { strings(in: $0) }
        }
        let cases: [(Int, BatteryTimeEstimate?, BatteryTimeEstimateSource?, Bool)] = [
            (80, nil, nil, false), (100, nil, nil, false),
            (100, .notCharging, .system, false),
            (99, .full, .system, true), (80, .full, .batteryGauge, true),
            (100, .full, nil, false), (100, .full, .observedDischarge, false),
        ]
        for (percent, estimate, source, isFull) in cases {
            let snapshot = PowerSnapshot(
                percent: percent, plugged: true, adapterW: 20,
                batteryW: 0, systemW: 20,
                batteryTimeEstimate: estimate, batteryTimeEstimateSource: source
            )
            XCTAssertEqual(
                header.statePresentationForTest(snapshot: snapshot).text,
                isFull ? "Plugged In · Full" : "Plugged In · Not Charging"
            )
            flow.update(snapshot: snapshot, animated: false)
            XCTAssertEqual(
                flow.nodePresentationsForTest[1].caption,
                isFull ? "Battery · Full" : "Battery · Idle"
            )
            ring.update(snapshot: snapshot)
            lanes.update(snapshot: snapshot)
            for view in [ring as NSView, lanes as NSView] {
                XCTAssertTrue(strings(in: view).contains(isFull ? "Full" : "Idle"))
                if !isFull { XCTAssertFalse(strings(in: view).contains("Full")) }
            }
        }
    }

    func testReportedChargingStateOverridesPowerThresholdWithoutChangingFlow() {
        let header = PopoverHeaderView()
        let flow = makeFlow()
        let cases: [(Double, BatteryTimeEstimate, String)] = [
            (0, .charging(nil), "Charging"),
            (0.1, .charging(12), "Charging"),
            (1, .notCharging, "Plugged In · Not Charging"),
            (1, .full, "Plugged In · Full"),
        ]
        for (batteryW, estimate, expected) in cases {
            let snapshot = PowerSnapshot(
                percent: 100, plugged: true, adapterW: 20 + batteryW,
                batteryW: batteryW, systemW: 20,
                batteryTimeEstimate: estimate, batteryTimeEstimateSource: .system
            )
            XCTAssertEqual(header.statePresentationForTest(snapshot: snapshot).text, expected)
            XCTAssertEqual(snapshot.state, batteryW > PowerSnapshot.epsilon ? .charging : .pluggedIdle)
            flow.update(snapshot: snapshot, animated: false)
            XCTAssertEqual(flow.topologyForTest, "adapterLed")
        }
    }

    func testReportedExternalStatesCannotReplaceBatteryOrMixedSupplyState() {
        for estimate in [BatteryTimeEstimate.full, .notCharging, .charging(12)] {
            for plugged in [false, true] {
                let snapshot = PowerSnapshot(
                    percent: 100, plugged: plugged, adapterW: plugged ? 10 : 0,
                    batteryW: -10, systemW: plugged ? 20 : 10,
                    batteryTimeEstimate: estimate, batteryTimeEstimateSource: .system
                )
                XCTAssertEqual(PopoverStyle.stateTitle(snapshot), plugged ? "Mixed Power · Adapter Limited" : "On Battery")
                XCTAssertEqual(PopoverStyle.batteryFlowLabel(snapshot), plugged ? "Battery Assist" : "Battery Output")
            }
        }
    }

    func testUSBDeadbandUsesCapacityAndOfficialStateWithoutAFalseBatteryFlow() {
        let flow = makeFlow()
        for batteryW in [-0.2, 0, 0.2] {
            flow.update(snapshot: PowerSnapshot(percent: 72, plugged: true,
                adapterW: 32 + batteryW, batteryW: batteryW, systemW: 32,
                deviceOutputW: 7.5, systemChargingState: .charging), animated: false)
            XCTAssertEqual(flow.topologyForTest, "adapterOutputSplit")
            XCTAssertEqual(flow.nodePresentationsForTest[1].caption, "Battery")
            XCTAssertEqual(flow.nodePresentationsForTest[1].value, "72 %")
            XCTAssertEqual(flow.branchThicknessesForTest[1], 0)
        }
        for (state, caption) in [(BatteryChargingState.full, "Battery · Full"),
                                  (.notCharging, "Battery · Idle")] {
            flow.update(snapshot: PowerSnapshot(percent: 99, plugged: true,
                adapterW: 32, systemW: 32, deviceOutputW: 7.5,
                systemChargingState: state), animated: false)
            XCTAssertEqual(flow.nodePresentationsForTest[1].caption, caption)
            XCTAssertEqual(flow.nodePresentationsForTest[1].value, "99 %")
        }
    }

    func testFlowThemeIsConsistentForEachConditionIncludingZeroAdapter() {
        let flow = makeFlow()
        let fixtures: [(PowerSnapshot, NSColor)] = [
            (.init(percent: 72, plugged: true, adapterW: 68, batteryW: 22.2,
                   systemW: 45.8, deviceOutputW: 7.5), PopoverStyle.green),
            (.init(percent: 99, plugged: true, adapterW: 32, systemW: 32,
                   deviceOutputW: 7.5, systemChargingState: .full), PopoverStyle.blue),
            (.init(percent: 44, plugged: true, adapterW: 30, batteryW: -9.7,
                   systemW: 39.7, deviceOutputW: 12.2), PopoverStyle.blue),
            (.init(percent: 44, plugged: true, batteryW: -20,
                   systemW: 20, deviceOutputW: 5), PopoverStyle.neutral),
            (.init(percent: 44, batteryW: -20, systemW: 20, deviceOutputW: 5), PopoverStyle.neutral),
        ]
        for (snapshot, expected) in fixtures {
            flow.update(snapshot: snapshot, animated: false)
            XCTAssertEqual(flow.conditionColorForTest.usingColorSpace(.sRGB)?.cgColor.components,
                           expected.usingColorSpace(.sRGB)?.cgColor.components)
        }
        let zeroMac = PowerSnapshot(percent: 44, plugged: true, adapterW: 10,
                                    batteryW: -10, systemW: 20, deviceOutputW: 20)
        flow.update(snapshot: zeroMac, animated: false)
        XCTAssertEqual(flow.topologyForTest, "mixedOutputSplit")
        XCTAssertEqual(flow.nodePresentationsForTest[2].value, "0.0 W")
        XCTAssertEqual(flow.branchThicknessesForTest[1], 0)
    }
}
