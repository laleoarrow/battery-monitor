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
        let suiteName = "Wattson.PowerPresentation.Tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        Settings.configureForTest(defaults: defaults)
        defer {
            Settings.resetTestConfiguration()
            defaults.removePersistentDomain(forName: suiteName)
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

    func testIdleBatteryLabelsDoNotClaimFullBelowOneHundredPercent() {
        let header = PopoverHeaderView()
        let flow = makeFlow()
        let ring = RingGaugeView()
        let lanes = LaneView()
        func strings(in view: NSView) -> [String] {
            let own = (view as? NSTextField).map { [$0.stringValue] } ?? []
            return own + view.subviews.flatMap { strings(in: $0) }
        }
        for percent in [80, 100] {
            let snapshot = PowerSnapshot(
                percent: percent, plugged: true, adapterW: 20,
                batteryW: 0, systemW: 20
            )
            let isFull = percent == 100
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
}
