import XCTest
@testable import Wattson

final class WattsonTests: XCTestCase {
    func testPowerSnapshotUsesSignedBatteryFlow() {
        let charging = PowerSnapshot(
            percent: 60,
            plugged: true,
            adapterW: 70,
            batteryW: 20,
            systemW: 50
        )
        XCTAssertEqual(charging.totalInputW, 70, accuracy: 0.001)
        XCTAssertEqual(charging.conservationError, 0, accuracy: 0.001)

        let mixed = PowerSnapshot(
            percent: 40,
            plugged: true,
            adapterW: 35,
            batteryW: -10,
            systemW: 45
        )
        XCTAssertEqual(mixed.totalInputW, 45, accuracy: 0.001)
        XCTAssertEqual(mixed.conservationError, 0, accuracy: 0.001)
    }

    func testHistoryIsBoundedAndChronological() {
        let history = PowerHistory()
        for value in 0..<75 {
            history.append(Double(value))
        }

        XCTAssertEqual(history.samples.count, 60)
        XCTAssertEqual(history.samples.first, 15)
        XCTAssertEqual(history.samples.last, 74)
        XCTAssertEqual(history.peak, 74)
    }

    func testHistoryPresentationMaterializesOrderAndPeakTogether() {
        let history = PowerHistory()
        for value in 0..<75 {
            history.append(Double(value))
        }
        let presentation = history.presentation
        XCTAssertEqual(presentation.samples.count, 60)
        XCTAssertEqual(presentation.samples.first, 15)
        XCTAssertEqual(presentation.samples.last, 74)
        XCTAssertEqual(presentation.peak, 74)
    }

    func testHistoryViewSkipsAnIdenticalPathRebuild() {
        let view = HistoryView()
        view.frame = NSRect(
            x: 0, y: 0, width: PopoverStyle.contentWidth,
            height: HistoryView.preferredHeight
        )
        view.layoutSubtreeIfNeeded()

        view.update(samples: [10, 20, 15], peak: 20, color: .systemBlue)
        XCTAssertEqual(view.renderCountForTest, 1)
        view.update(samples: [10, 20, 15], peak: 20, color: .systemBlue)
        XCTAssertEqual(view.renderCountForTest, 1)

        view.update(samples: [10, 20, 15], peak: 20, color: .systemRed)
        XCTAssertEqual(view.renderCountForTest, 2)
        view.update(samples: [10, 21, 15], peak: 21, color: .systemRed)
        XCTAssertEqual(view.renderCountForTest, 3)
    }

    func testBatteryIconRenderKeyIgnoresWattsButTracksVisualChanges() {
        let baseline = PowerSnapshot(
            percent: 67, plugged: true, adapterW: 70, batteryW: 20, systemW: 50
        )
        let changedWatts = PowerSnapshot(
            percent: 67, plugged: true, adapterW: 95, batteryW: 30, systemW: 65
        )
        let appearance = NSAppearance(named: .darkAqua)!
        let first = BatteryIcon.renderKey(
            for: baseline, mode: .auto, pressed: false,
            appearance: appearance, increasedContrast: false
        )
        let samePixels = BatteryIcon.renderKey(
            for: changedWatts, mode: .auto, pressed: false,
            appearance: appearance, increasedContrast: false
        )
        XCTAssertEqual(first, samePixels)

        var changedPercent = baseline
        changedPercent.percent = 66
        XCTAssertNotEqual(first, BatteryIcon.renderKey(
            for: changedPercent, mode: .auto, pressed: false,
            appearance: appearance, increasedContrast: false
        ))
        XCTAssertNotEqual(first, BatteryIcon.renderKey(
            for: baseline, mode: .low, pressed: false,
            appearance: appearance, increasedContrast: false
        ))
        XCTAssertNotEqual(first, BatteryIcon.renderKey(
            for: baseline, mode: .auto, pressed: false,
            appearance: NSAppearance(named: .aqua)!, increasedContrast: false
        ))
        XCTAssertNotEqual(first, BatteryIcon.renderKey(
            for: baseline, mode: .auto, pressed: false,
            appearance: appearance, increasedContrast: true
        ))
    }

    func testPluggedIdleBreathingIsIdempotentAndStopsWhenHidden() {
        let flow = PowerFlowView()
        flow.frame = NSRect(
            x: 0, y: 0, width: PopoverStyle.contentWidth,
            height: PowerFlowView.preferredHeight
        )
        flow.layoutSubtreeIfNeeded()
        let full = PowerSnapshot(
            percent: 100, plugged: true, adapterW: 52,
            batteryW: 0, systemW: 52
        )

        flow.update(snapshot: full, animated: false)
        XCTAssertEqual(flow.breathingMetricsForTest.running, 0)
        flow.setAnimationsEnabled(true)
        let started = flow.breathingMetricsForTest
        XCTAssertEqual(started.running, 1)
        XCTAssertEqual(started.installations, 1)

        flow.update(snapshot: full, animated: true)
        XCTAssertEqual(flow.breathingMetricsForTest.installations, 1)

        flow.setAnimationsEnabled(false)
        XCTAssertEqual(flow.breathingMetricsForTest.running, 0)
        flow.update(snapshot: full, animated: false)
        XCTAssertEqual(flow.breathingMetricsForTest.running, 0)
    }

    func testClosedPopoverCachesWithoutRenderingContent() {
        let popover = PopoverController()
        let old = PowerSnapshot(percent: 40, plugged: false, batteryW: -20, systemW: 20)
        let newest = PowerSnapshot(percent: 39, plugged: false, batteryW: -22, systemW: 22)

        popover.update(snapshot: old, history: [20], peak: 20, degraded: false)
        popover.update(snapshot: newest, history: [20, 22], peak: 22, degraded: false)
        XCTAssertEqual(popover.contentRenderCountForTest, 0)
        XCTAssertEqual(popover.cachedPercentForTest, 39)

        popover.applyLatestPresentationForTest()
        XCTAssertEqual(popover.contentRenderCountForTest, 1)
    }
}
