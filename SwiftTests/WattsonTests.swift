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

    private func drag(_ slider: ModeSliderView, in window: NSWindow,
                      from startX: CGFloat, to endX: CGFloat, steps: Int = 30) {
        slider.mouseDown(with: sliderMouseEvent(.leftMouseDown, x: startX, window: window))
        for step in 1...steps {
            let x = startX + (endX - startX) * CGFloat(step) / CGFloat(steps)
            slider.mouseDragged(with: sliderMouseEvent(.leftMouseDragged, x: x, window: window))
        }
        slider.mouseUp(with: sliderMouseEvent(.leftMouseUp, x: endX, window: window))
    }

    func testModeSliderRestingSelectionMeetsTrackEdges() {
        for (mode, index) in [(EnergyMode.auto, 0), (.low, 1), (.high, 2)] {
            let (slider, window) = makeAnimatedSlider(selected: mode)
            defer { window.orderOut(nil) }

            let selection = slider.glassViewFrameForTest
            XCTAssertEqual(selection.minY, slider.bounds.minY, accuracy: 0.01)
            XCTAssertEqual(selection.maxY, slider.bounds.maxY, accuracy: 0.01)
            XCTAssertEqual(selection.midX, slider.detentCentreForTest(index), accuracy: 0.01)
            XCTAssertEqual(selection.width, slider.segmentWidthForTest, accuracy: 0.01)
            XCTAssertEqual(slider.knobCornerRadiusForTest,
                           slider.bounds.height / 2, accuracy: 0.01)
            XCTAssertEqual(slider.selectorCornerRadiusForTest,
                           slider.bounds.height / 2, accuracy: 0.01)
            if index == 0 {
                XCTAssertEqual(selection.minX, slider.bounds.minX, accuracy: 0.01)
            } else if index == 2 {
                XCTAssertEqual(selection.maxX, slider.bounds.maxX, accuracy: 0.01)
            }
        }
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

    func testModeSliderTwoDetentMotionRecordsTheMiddleLabelPeak() {
        let (slider, window) = makeAnimatedSlider(selected: .auto)
        defer { window.orderOut(nil) }
        slider.onSelect = { mode, completion in completion(mode) }

        slider.resetLabelBlendTraceForTest()
        tap(slider, in: window, x: slider.detentCentreForTest(2))

        let middlePeak = slider.labelBlendTraceForTest.compactMap { weights in
            weights.count == 3 ? weights[1] : nil
        }.max() ?? 0
        XCTAssertTrue(
            slider.magneticMotionCentresForTest(from: 0, to: 2).contains {
                abs($0 - slider.detentCentreForTest(1)) < 0.01
            }
        )
        if slider.reducesMotionForTest {
            XCTAssertFalse(slider.settleIsAnimatingForTest)
        } else {
            XCTAssertGreaterThan(middlePeak, 0.99)
        }
    }

    func testModeSliderClickDuringSpringStaysInsideItsVisiblePath() {
        let (slider, window) = makeAnimatedSlider(selected: .auto)
        defer { window.orderOut(nil) }
        slider.onSelect = { mode, completion in completion(mode) }
        let auto = slider.detentCentreForTest(0)
        let low = slider.detentCentreForTest(1)
        let high = slider.detentCentreForTest(2)

        drag(slider, in: window, from: auto, to: high)
        spinMainRunLoop(0.4)
        drag(slider, in: window, from: high, to: low)
        spinMainRunLoop(0.18)
        let visibleBeforeClick = slider.glassViewCentreForTest
        tap(slider, in: window, x: high)
        let visibleAfterClick = slider.glassViewCentreForTest

        if slider.reducesMotionForTest {
            XCTAssertEqual(visibleAfterClick, high, accuracy: 0.5)
        } else {
            XCTAssertEqual(visibleAfterClick, visibleBeforeClick, accuracy: 1)
            var samples = [visibleAfterClick]
            let deadline = Date().addingTimeInterval(0.4)
            while slider.settleIsAnimatingForTest && Date() < deadline {
                spinMainRunLoop(0.01)
                samples.append(slider.glassViewCentreForTest)
            }
            XCTAssertGreaterThan(samples.max() ?? visibleAfterClick, visibleBeforeClick)
            XCTAssertTrue(samples.allSatisfy {
                $0 >= min(visibleBeforeClick, high) - 4
                    && $0 <= max(visibleBeforeClick, high) + 4
            })
            XCTAssertEqual(slider.glassViewCentreForTest, high, accuracy: 0.5)
        }
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

    func testLiveSystemPowerPreservesBatteryBranchAndConservation() {
        let stale = PowerSnapshot(
            percent: 60, plugged: true, adapterW: 70, batteryW: 20, systemW: 50
        )
        let charging = BatterySampler.resolvedLivePower(
            snapshot: stale, adapterW: 63, systemW: 48
        )
        XCTAssertEqual(charging.adapterW, 68, accuracy: 0.001)
        XCTAssertEqual(charging.batteryW, 20, accuracy: 0.001)
        XCTAssertEqual(charging.systemW, 48, accuracy: 0.001)
        XCTAssertEqual(charging.conservationError, 0, accuracy: 0.001)

        // The independently sampled adapter value is deliberately not
        // subtracted from system power: on hardware it can be one generation
        // behind and would turn this charging snapshot into a false discharge.
        let asynchronousPair = BatterySampler.resolvedLivePower(
            snapshot: stale, adapterW: 35, systemW: 48
        )
        XCTAssertEqual(asynchronousPair.adapterW, 68, accuracy: 0.001)
        XCTAssertEqual(asynchronousPair.batteryW, 20, accuracy: 0.001)
        XCTAssertEqual(asynchronousPair.conservationError, 0, accuracy: 0.001)

        var batteryOnly = stale
        batteryOnly.plugged = false
        let discharging = BatterySampler.resolvedLivePower(
            snapshot: batteryOnly, adapterW: nil, systemW: 22
        )
        XCTAssertEqual(discharging.adapterW, 0, accuracy: 0.001)
        XCTAssertEqual(discharging.batteryW, -22, accuracy: 0.001)
        XCTAssertEqual(discharging.systemW, 22, accuracy: 0.001)
        XCTAssertEqual(discharging.conservationError, 0, accuracy: 0.001)
    }

    func testLivePowerUsesEitherSafeBranchAndRejectsInvalidValues() {
        let stale = PowerSnapshot(
            percent: 60, plugged: true, adapterW: 70, batteryW: 20, systemW: 50
        )
        let systemOnly = BatterySampler.resolvedLivePower(
            snapshot: stale, adapterW: nil, systemW: 48
        )
        XCTAssertEqual(systemOnly.adapterW, 68, accuracy: 0.001)
        XCTAssertEqual(systemOnly.batteryW, 20, accuracy: 0.001)
        XCTAssertEqual(systemOnly.systemW, 48, accuracy: 0.001)

        let adapterOnly = BatterySampler.resolvedLivePower(
            snapshot: stale, adapterW: 63, systemW: nil
        )
        XCTAssertEqual(adapterOnly.adapterW, 63, accuracy: 0.001)
        XCTAssertEqual(adapterOnly.batteryW, 20, accuracy: 0.001)
        XCTAssertEqual(adapterOnly.systemW, 43, accuracy: 0.001)

        let unchanged = BatterySampler.resolvedLivePower(
            snapshot: stale, adapterW: .nan, systemW: -.infinity
        )
        XCTAssertEqual(unchanged.adapterW, stale.adapterW)
        XCTAssertEqual(unchanged.batteryW, stale.batteryW)
        XCTAssertEqual(unchanged.systemW, stale.systemW)
    }

    func testBatteryTemperatureUsesPhysicalDeciKelvinThenVirtualCentiCelsius() {
        XCTAssertEqual(
            BatterySampler.resolvedTemperatureC(
                temperatureRaw: 3_057,
                virtualTemperatureRaw: 3_250
            )!,
            32.55,
            accuracy: 0.001
        )
        XCTAssertEqual(
            BatterySampler.resolvedTemperatureC(
                temperatureRaw: 0,
                virtualTemperatureRaw: 3_250
            )!,
            32.5,
            accuracy: 0.001
        )
        XCTAssertEqual(
            BatterySampler.resolvedTemperatureC(
                temperatureRaw: nil,
                virtualTemperatureRaw: 0
            )!,
            0,
            accuracy: 0.001
        )
    }

    func testBatteryTemperatureRejectsMissingAndSentinelValues() {
        XCTAssertNil(BatterySampler.resolvedTemperatureC(
            temperatureRaw: nil,
            virtualTemperatureRaw: nil
        ))
        XCTAssertNil(BatterySampler.resolvedTemperatureC(
            temperatureRaw: 0,
            virtualTemperatureRaw: nil
        ))
        XCTAssertNil(BatterySampler.resolvedTemperatureC(
            temperatureRaw: -1,
            virtualTemperatureRaw: 65_535
        ))
        XCTAssertNil(BatterySampler.resolvedTemperatureC(
            temperatureRaw: Int(Int32.max),
            virtualTemperatureRaw: Int(Int32.min)
        ))
    }

    func testRingGaugeDistinguishesMissingTemperatureFromRealZero() {
        let gauge = RingGaugeView()
        gauge.update(snapshot: PowerSnapshot(temperatureC: nil))
        XCTAssertEqual(gauge.temperatureTextForTest, "—")

        gauge.update(snapshot: PowerSnapshot(temperatureC: 0))
        XCTAssertEqual(gauge.temperatureTextForTest, "0.0°C")
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
