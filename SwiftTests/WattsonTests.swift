import XCTest
@testable import Wattson

final class WattsonTests: XCTestCase {
    private func spinMainRunLoop(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    private func makeAnimatedSlider(selected: EnergyMode) -> (ModeSliderView, NSWindow) {
        _ = NSApplication.shared
        let slider = ModeSliderView(modes: [.auto, .low, .high])
        let window = NSWindow(
            contentRect: NSRect(x: -10_000, y: -10_000,
                                width: 300, height: ModeSliderView.preferredHeight),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.contentView = slider
        slider.frame = window.contentView!.bounds
        slider.update(selected: selected,
                      enabledModes: [.auto, .low, .high],
                      tint: .systemBlue)
        slider.layoutSubtreeIfNeeded()
        window.alphaValue = 0.01
        window.orderFrontRegardless()
        spinMainRunLoop(0.05)
        return (slider, window)
    }

    private func sliderMouseEvent(_ type: NSEvent.EventType, x: CGFloat,
                                  window: NSWindow) -> NSEvent {
        NSEvent.mouseEvent(
            with: type,
            location: NSPoint(x: x, y: ModeSliderView.preferredHeight / 2),
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        )!
    }

    private func tap(_ slider: ModeSliderView, in window: NSWindow, x: CGFloat) {
        slider.mouseDown(with: sliderMouseEvent(.leftMouseDown, x: x, window: window))
        slider.mouseUp(with: sliderMouseEvent(.leftMouseUp, x: x, window: window))
    }

    func testModeSliderRegrabMaterializesPresentationWithoutJump() {
        let (slider, window) = makeAnimatedSlider(selected: .auto)
        defer { window.orderOut(nil) }
        slider.onSelect = { mode, completion in completion(mode) }

        tap(slider, in: window, x: slider.detentCentreForTest(2))
        spinMainRunLoop(0.075)
        let visibleBeforeGrab = slider.glassViewCentreForTest
        slider.mouseDown(with: sliderMouseEvent(.leftMouseDown,
                                                x: visibleBeforeGrab,
                                                window: window))

        if slider.reducesMotionForTest {
            XCTAssertEqual(visibleBeforeGrab, slider.detentCentreForTest(2), accuracy: 0.5)
        } else {
            XCTAssertGreaterThan(visibleBeforeGrab, slider.detentCentreForTest(0) + 2)
            XCTAssertLessThan(visibleBeforeGrab, slider.detentCentreForTest(2) - 2)
        }
        XCTAssertEqual(slider.knobCentreForTest, visibleBeforeGrab, accuracy: 1)
        XCTAssertFalse(slider.settleIsAnimatingForTest)
    }

    func testModeSliderRejectionReversesFromPresentationPosition() {
        let (slider, window) = makeAnimatedSlider(selected: .high)
        defer { window.orderOut(nil) }
        var completion: ((EnergyMode?) -> Void)?
        slider.onSelect = { _, callback in completion = callback }

        tap(slider, in: window, x: slider.detentCentreForTest(0))
        spinMainRunLoop(0.08)
        let visibleBeforeRejection = slider.glassViewCentreForTest
        completion?(.high)
        let visibleAfterRejection = slider.glassViewCentreForTest

        if slider.reducesMotionForTest {
            XCTAssertEqual(visibleBeforeRejection, slider.detentCentreForTest(0), accuracy: 0.5)
            XCTAssertEqual(visibleAfterRejection, slider.detentCentreForTest(2), accuracy: 0.5)
            XCTAssertFalse(slider.settleIsAnimatingForTest)
        } else {
            XCTAssertGreaterThan(visibleBeforeRejection, slider.detentCentreForTest(0) + 2)
            XCTAssertLessThan(visibleBeforeRejection, slider.detentCentreForTest(2) - 2)
            XCTAssertEqual(visibleAfterRejection, visibleBeforeRejection, accuracy: 1)
            XCTAssertTrue(slider.settleIsAnimatingForTest)
        }

        spinMainRunLoop(0.4)
        XCTAssertEqual(slider.glassViewCentreForTest,
                       slider.detentCentreForTest(2), accuracy: 0.5)
    }

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
