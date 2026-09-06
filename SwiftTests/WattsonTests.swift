import XCTest
@testable import Wattson

final class WattsonTests: XCTestCase {
    private func spinMainRunLoop(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    private func makeAnimatedSlider(selected: EnergyMode,
                                    forceLegacyMaterials: Bool = false) -> (ModeSliderView, NSWindow) {
        _ = NSApplication.shared
        let slider = forceLegacyMaterials
            ? ModeSliderView(modes: [.auto, .low, .high], forceLegacyMaterialsForTest: true)
            : ModeSliderView(modes: [.auto, .low, .high])
        let window = NSWindow(
            contentRect: NSRect(x: 20, y: 20,
                                width: 300, height: ModeSliderView.preferredHeight),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.contentView = slider
        slider.frame = window.contentView!.bounds
        slider.update(selected: selected,
                      enabledModes: [.auto, .low, .high],
                      tint: .systemBlue)
        slider.layoutSubtreeIfNeeded()
        window.alphaValue = 0
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

    func testLegacyModeSliderLensSamplesRealTrackPixelsAndRefractsDuringDrag() {
        _ = NSApplication.shared
        let slider = ModeSliderView(
            modes: [.auto, .low, .high],
            forceLegacyMaterialsForTest: true
        )
        let window = NSWindow(
            contentRect: NSRect(x: -10_000, y: -10_000,
                                width: 300, height: ModeSliderView.preferredHeight),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        defer { window.orderOut(nil) }
        window.contentView = slider
        slider.frame = window.contentView!.bounds
        slider.update(selected: .auto,
                      enabledModes: [.auto, .low, .high],
                      tint: .systemBlue)
        window.alphaValue = 0.01
        window.orderFrontRegardless()
        slider.layoutSubtreeIfNeeded()
        spinMainRunLoop(0.05)

        guard let sampledTrack = slider.fallbackLensSampleImageForTest,
              let data = sampledTrack.dataProvider?.data as Data? else {
            return XCTFail("legacy lens must cache real AppKit-rendered track pixels")
        }
        XCTAssertGreaterThan(sampledTrack.width, 200)
        XCTAssertGreaterThan(sampledTrack.height, 20)
        XCTAssertGreaterThan(Set(data).count, 8, "sample must contain real rendered chrome pixels")
        XCTAssertGreaterThan(slider.fallbackLensRimWidthForTest ?? 0, 0)
        XCTAssertEqual(slider.fallbackLensSamplingEnabledForTest, false)
        XCTAssertEqual(slider.fallbackLensMagnificationForTest ?? -1, 1, accuracy: 0.001)

        let capturesBeforeDrag = slider.fallbackLensCaptureCountForTest
        let start = slider.detentCentreForTest(0)
        slider.mouseDown(with: sliderMouseEvent(.leftMouseDown, x: start, window: window))
        slider.mouseDragged(with: sliderMouseEvent(.leftMouseDragged,
                                                   x: start + 6,
                                                   window: window))
        let firstLiftedSample = slider.fallbackLensSampleRectForTest
        for step in 1...60 {
            let x = start + (slider.detentCentreForTest(1) - start) * CGFloat(step) / 60
            slider.mouseDragged(with: sliderMouseEvent(.leftMouseDragged,
                                                       x: x,
                                                       window: window))
        }
        let during = slider.fallbackLensSampleRectForTest

        XCTAssertEqual(slider.fallbackLensSamplingEnabledForTest, true)
        XCTAssertEqual(slider.fallbackLensMagnificationForTest ?? -1, 1.105, accuracy: 0.001)
        XCTAssertNotNil(firstLiftedSample)
        XCTAssertNotNil(during)
        XCTAssertGreaterThan(
            (during?.midX ?? 0) - (firstLiftedSample?.midX ?? 0),
            0.15
        )
        XCTAssertEqual(slider.knobScaleForTest.width, 1, accuracy: 0.01)
        XCTAssertEqual(slider.knobScaleForTest.height, 1, accuracy: 0.01)
        XCTAssertEqual(
            slider.fallbackLensCaptureCountForTest,
            capturesBeforeDrag,
            "dragging must only move the cached crop, never recapture the view"
        )

        slider.mouseUp(with: sliderMouseEvent(.leftMouseUp,
                                              x: slider.detentCentreForTest(1),
                                              window: window))
        XCTAssertEqual(slider.fallbackLensSamplingEnabledForTest, false)
        XCTAssertEqual(slider.fallbackLensMagnificationForTest ?? -1, 1, accuracy: 0.001)
    }

    func testLegacyClickSettleNeverEnablesDragOnlyRefractionDuringRefresh() throws {
        let (slider, window) = makeAnimatedSlider(
            selected: .auto,
            forceLegacyMaterials: true
        )
        defer { window.orderOut(nil) }
        slider.onSelect = { mode, completion in completion(mode) }

        tap(slider, in: window, x: slider.detentCentreForTest(2))
        if slider.reducesMotionForTest {
            throw XCTSkip("test requires animated legacy settle")
        }
        XCTAssertTrue(slider.settleIsAnimatingForTest)
        XCTAssertEqual(slider.fallbackLensSamplingEnabledForTest, false)

        slider.update(
            selected: .high,
            enabledModes: [.auto, .low, .high],
            tint: .systemGreen
        )
        XCTAssertEqual(slider.fallbackLensSamplingEnabledForTest, false)
        XCTAssertEqual(slider.fallbackLensMagnificationForTest ?? -1, 1, accuracy: 0.001)

        spinMainRunLoop(0.5)
        XCTAssertEqual(slider.fallbackLensSamplingEnabledForTest, false)
        XCTAssertEqual(slider.fallbackLensMagnificationForTest ?? -1, 1, accuracy: 0.001)
    }

    func testMacOS26ModeSliderUsesNativeClearGlassAsTheMovingLens() throws {
        guard #available(macOS 26.0, *) else { throw XCTSkip("requires native Liquid Glass") }
        let (slider, window) = makeAnimatedSlider(selected: .auto)
        defer { window.orderOut(nil) }

        XCTAssertEqual(slider.nativeSelectorStyleForTest,
                       NSGlassEffectView.Style.clear.rawValue)
        XCTAssertEqual(slider.nativeGlassContainerSpacingForTest ?? -1, 0, accuracy: 0.01)
        XCTAssertEqual(slider.nativeSelectorIsInsideContainerForTest, true)
        XCTAssertEqual(slider.nativeSelectorFillAlphaForTest ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(slider.nativeSelectorContentFillAlphaForTest ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(slider.nativeSelectorBorderWidthForTest, 0)
        XCTAssertFalse(slider.nativeSelectorHasCustomChromeForTest)
        XCTAssertNil(slider.fallbackLensSampleImageForTest)
    }

    func testMacOS26NativeGlassStaysAiryAtRestAndOnlyStrengthensDuringMotion() throws {
        guard #available(macOS 26.0, *) else { throw XCTSkip("requires native Liquid Glass") }
        let (slider, window) = makeAnimatedSlider(selected: .auto)
        defer { window.orderOut(nil) }
        slider.onSelect = { mode, completion in completion(mode) }

        XCTAssertEqual(slider.nativeSelectorOpacityForTest ?? -1, 0.045, accuracy: 0.001)

        tap(slider, in: window, x: slider.detentCentreForTest(2))
        guard !slider.reducesMotionForTest else { return }
        XCTAssertEqual(slider.nativeSelectorOpacityForTest ?? -1, 0.14, accuracy: 0.001)

        let deadline = Date().addingTimeInterval(0.6)
        while slider.settleIsAnimatingForTest && Date() < deadline {
            spinMainRunLoop(0.008)
        }
        XCTAssertEqual(slider.nativeSelectorOpacityForTest ?? -1, 0.045, accuracy: 0.001)

        let start = slider.detentCentreForTest(2)
        slider.mouseDown(with: sliderMouseEvent(.leftMouseDown, x: start, window: window))
        slider.mouseDragged(with: sliderMouseEvent(.leftMouseDragged,
                                                   x: start - 12,
                                                   window: window))
        XCTAssertEqual(slider.nativeSelectorOpacityForTest ?? -1, 0.14, accuracy: 0.001)
    }

    func testMacOS26ModeSliderMovesGlassAndItsGeometryOnOneDisplayTimeline() throws {
        guard #available(macOS 26.0, *) else { throw XCTSkip("requires native Liquid Glass") }
        let (slider, window) = makeAnimatedSlider(selected: .auto)
        defer { window.orderOut(nil) }
        slider.onSelect = { mode, completion in completion(mode) }

        tap(slider, in: window, x: slider.detentCentreForTest(2))
        guard !slider.reducesMotionForTest else {
            XCTAssertFalse(slider.settleIsAnimatingForTest)
            return
        }

        XCTAssertFalse(
            slider.nativeSettleUsesHostLayerAnimationForTest,
            "native AppKit glass must follow real view geometry instead of a separate CA proxy"
        )
        var moved = false
        var intermediateFrames = 0
        let startCentre = slider.detentCentreForTest(0)
        let targetCentre = slider.detentCentreForTest(2)
        let deadline = Date().addingTimeInterval(0.5)
        while slider.settleIsAnimatingForTest && Date() < deadline {
            spinMainRunLoop(0.008)
            let glass = slider.glassViewFrameForTest
            let selector = try XCTUnwrap(slider.nativeSelectorFrameInSliderForTest)
            XCTAssertEqual(selector.minX, glass.minX, accuracy: 0.5)
            XCTAssertEqual(selector.minY, glass.minY, accuracy: 0.5)
            XCTAssertEqual(selector.width, glass.width, accuracy: 0.5)
            XCTAssertEqual(selector.height, glass.height, accuracy: 0.5)
            moved = moved || glass.midX > startCentre + 3
            if glass.midX > startCentre + 3, glass.midX < targetCentre - 3 {
                intermediateFrames += 1
            }
        }
        XCTAssertTrue(moved)
        XCTAssertGreaterThanOrEqual(intermediateFrames, 3)
        XCTAssertEqual(slider.glassViewCentreForTest,
                       slider.detentCentreForTest(2), accuracy: 0.5)
    }

    func testEnablingReduceMotionStopsEveryModeSliderSettleDriverImmediately() throws {
        guard #available(macOS 26.0, *) else { throw XCTSkip("requires native test host") }
        for forceLegacyMaterials in [false, true] {
            let (slider, window) = makeAnimatedSlider(
                selected: .auto,
                forceLegacyMaterials: forceLegacyMaterials
            )
            defer { window.orderOut(nil) }
            slider.onSelect = { mode, completion in completion(mode) }

            tap(slider, in: window, x: slider.detentCentreForTest(2))
            guard !slider.reducesMotionForTest else {
                throw XCTSkip("test requires normal motion at launch")
            }
            spinMainRunLoop(0.04)
            XCTAssertTrue(slider.settleIsAnimatingForTest)

            slider.applyReduceMotionChangeForTest(true)

            XCTAssertFalse(slider.settleIsAnimatingForTest)
            XCTAssertEqual(slider.glassViewCentreForTest,
                           slider.detentCentreForTest(2), accuracy: 0.5)
            spinMainRunLoop(0.35)
            XCTAssertFalse(slider.settleIsAnimatingForTest)
            XCTAssertEqual(slider.glassViewCentreForTest,
                           slider.detentCentreForTest(2), accuracy: 0.5)

            slider.applyReduceMotionChangeForTest(false)
            tap(slider, in: window, x: slider.detentCentreForTest(0))
            XCTAssertTrue(slider.settleIsAnimatingForTest)
            spinMainRunLoop(0.35)
            XCTAssertFalse(slider.settleIsAnimatingForTest)
            XCTAssertEqual(slider.glassViewCentreForTest,
                           slider.detentCentreForTest(0), accuracy: 0.5)

            let start = slider.detentCentreForTest(0)
            slider.mouseDown(with: sliderMouseEvent(.leftMouseDown,
                                                    x: start,
                                                    window: window))
            slider.mouseDragged(with: sliderMouseEvent(.leftMouseDragged,
                                                       x: start + 24,
                                                       window: window))
            XCTAssertEqual(slider.knobScaleForTest.width, 1, accuracy: 0.01)
            XCTAssertEqual(slider.knobScaleForTest.height, 1, accuracy: 0.01)
            let draggedCentre = slider.glassViewCentreForTest

            slider.applyReduceMotionChangeForTest(true)

            XCTAssertEqual(slider.knobScaleForTest.width, 1, accuracy: 0.01)
            XCTAssertEqual(slider.knobScaleForTest.height, 1, accuracy: 0.01)
            XCTAssertEqual(slider.glassViewCentreForTest, draggedCentre, accuracy: 0.5)
            XCTAssertNotEqual(slider.fallbackLensSamplingEnabledForTest, true)
            slider.mouseUp(with: sliderMouseEvent(.leftMouseUp,
                                                  x: start + 24,
                                                  window: window))
        }
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

    func testModeSliderDirectDragKeepsRestingFootprint() {
        for forceLegacyMaterials in [false, true] {
            let (slider, window) = makeAnimatedSlider(
                selected: .auto,
                forceLegacyMaterials: forceLegacyMaterials
            )
            defer { window.orderOut(nil) }

            let start = slider.detentCentreForTest(0)
            let target = slider.detentCentreForTest(1)
            slider.mouseDown(with: sliderMouseEvent(.leftMouseDown,
                                                    x: start,
                                                    window: window))
            slider.mouseDragged(with: sliderMouseEvent(.leftMouseDragged,
                                                       x: target,
                                                       window: window))

            XCTAssertEqual(slider.glassViewCentreForTest, target, accuracy: 0.5)
            XCTAssertEqual(slider.knobScaleForTest.width, 1, accuracy: 0.01)
            XCTAssertEqual(slider.knobScaleForTest.height, 1, accuracy: 0.01)

            slider.mouseUp(with: sliderMouseEvent(.leftMouseUp,
                                                  x: target,
                                                  window: window))
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
            let path = slider.magneticMotionCentresForTest(from: 0, to: 2)
            XCTAssertGreaterThanOrEqual(visibleBeforeGrab, (path.min() ?? 0) - 0.5)
            XCTAssertLessThanOrEqual(visibleBeforeGrab, (path.max() ?? 0) + 0.5)
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
            // A busy compositor may expose any point on the named magnetic
            // path, including its intentional bounded overshoot.
            let path = slider.magneticMotionCentresForTest(from: 2, to: 0)
            XCTAssertGreaterThanOrEqual(visibleBeforeRejection, (path.min() ?? 0) - 0.5)
            XCTAssertLessThanOrEqual(visibleBeforeRejection, (path.max() ?? 0) + 0.5)
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

    func testDeviceOutputIsAuxiliaryAndCoherent() {
        var snapshot = PowerSnapshot(
            percent: 60, plugged: true, adapterW: 70,
            batteryW: 20, systemW: 50, deviceOutputW: 7.5
        )
        let totalInputW = snapshot.totalInputW
        let conservationError = snapshot.conservationError
        XCTAssertEqual(snapshot.coherentDeviceOutputW, 7.5)
        XCTAssertEqual(snapshot.totalInputW, 70, accuracy: 0.001)
        XCTAssertEqual(snapshot.conservationError, 0, accuracy: 0.001)

        snapshot.deviceOutputW = 50
        XCTAssertEqual(snapshot.coherentDeviceOutputW, 50)

        for invalid in [50.2, .nan, -1] {
            snapshot.deviceOutputW = invalid
            XCTAssertNil(snapshot.coherentDeviceOutputW)
            XCTAssertEqual(snapshot.totalInputW, totalInputW, accuracy: 0.001)
            XCTAssertEqual(snapshot.conservationError, conservationError, accuracy: 0.001)
        }
    }

    func testDeviceOutputParserUsesOnlyValidMeasuredWatts() throws {
        let details: [Any] = [
            ["PortIndex": 2, "Watts": 7_078, "PDPowermW": 60_000],
            ["PortIndex": 3, "Watts": 2_250],
            ["PDPowermW": NSNumber(value: 140_000)],
        ]
        XCTAssertEqual(
            try XCTUnwrap(BatterySampler.resolvedDeviceOutputW(details)),
            9.328, accuracy: 0.000_001
        )
        XCTAssertEqual(
            try XCTUnwrap(BatterySampler.resolvedDeviceOutputW([["Watts": 0]])),
            0, accuracy: 0.000_001
        )

        for invalidWatts: Any in [kCFBooleanTrue as Any, -1, 7.078, 1_000_001] {
            XCTAssertNil(BatterySampler.resolvedDeviceOutputW([["Watts": invalidWatts]]))
        }
        let invalidDetails: [Any?] = [
            nil,
            [Any](),
            [["PDPowermW": NSNumber(value: 140_000)]],
            [["PortIndex": 1, "Watts": 2_000],
             ["PortIndex": 1, "Watts": 3_000]],
            [["PortIndex": 1, "Watts": 2_000],
             ["PortIndex": 2, "Watts": "invalid"]],
        ]
        for details in invalidDetails {
            XCTAssertNil(BatterySampler.resolvedDeviceOutputW(details))
        }
    }

    func testDeviceOutputRejectsOversizedPortArraysWithoutReportingZero() {
        let maximumPorts = Array(repeating: ["Watts": 0], count: 64)
        XCTAssertEqual(BatterySampler.resolvedDeviceOutputW(maximumPorts), 0)
        XCTAssertNil(BatterySampler.resolvedDeviceOutputW(
            maximumPorts + [["Watts": 0]]
        ))
        XCTAssertNil(BatterySampler.resolvedDeviceOutputW(
            Array(repeating: ["PDPowermW": 0], count: 64) + [["Watts": 100]]
        ))
    }

    func testResolvedSnapshotCarriesDeviceOutputThroughLivePowerMerge() throws {
        let props: [String: Any] = [
            "CurrentCapacity": NSNumber(value: 60),
            "MaxCapacity": NSNumber(value: 100),
            "ExternalConnected": kCFBooleanTrue as Any,
            "PowerTelemetryData": [
                "SystemPowerIn": NSNumber(value: 60_000),
                "SystemLoad": NSNumber(value: 50_000),
                "BatteryPower": NSNumber(value: 10_000),
            ],
            "PowerOutDetails": [
                ["Watts": NSNumber(value: 7_500)],
            ],
        ]
        let snapshot = try XCTUnwrap(
            BatterySampler.resolvedSnapshot(from: props, lowPowerMode: false)
        )
        XCTAssertEqual(snapshot.deviceOutputW, 7.5)
        let fresh = BatterySampler.resolvedLivePower(
            snapshot: snapshot, adapterW: nil, systemW: 48
        )
        XCTAssertEqual(fresh.deviceOutputW, 7.5)
        XCTAssertEqual(fresh.conservationError, 0, accuracy: 0.001)
    }

    func testSignedBatteryCurrentOverridesAsynchronousTotalsAndKeepsDeviceOutputAuxiliary() throws {
        func snapshot(
            instantAmperage: Int,
            systemPowerIn: Int,
            systemLoad: Int,
            deviceOutput: Int? = nil
        ) throws -> PowerSnapshot {
            var props: [String: Any] = [
                "CurrentCapacity": NSNumber(value: 100),
                "MaxCapacity": NSNumber(value: 100),
                "ExternalConnected": kCFBooleanTrue as Any,
                "IsCharging": kCFBooleanFalse as Any,
                "Voltage": NSNumber(value: 12_000),
                "InstantAmperage": NSNumber(value: instantAmperage),
                "Amperage": NSNumber(value: instantAmperage),
                "PowerTelemetryData": [
                    "SystemPowerIn": NSNumber(value: systemPowerIn),
                    "SystemLoad": NSNumber(value: systemLoad),
                    "BatteryPower": NSNumber(value: systemPowerIn - systemLoad),
                ],
            ]
            if let deviceOutput {
                props["PowerOutDetails"] = [[
                    "PortIndex": NSNumber(value: 1),
                    "Watts": NSNumber(value: deviceOutput),
                ]]
            }
            return try XCTUnwrap(
                BatterySampler.resolvedSnapshot(from: props, lowPowerMode: false)
            )
        }

        // ExternalConnected and IsCharging update promptly, while the two
        // source/sink totals can straddle different firmware generations. A
        // measured zero signed battery current agrees with the idle flag and
        // must prevent their temporary deficit from becoming Battery Assist.
        let idle = try snapshot(
            instantAmperage: 0,
            systemPowerIn: 41_500,
            systemLoad: 48_700,
            deviceOutput: 14_083
        )
        XCTAssertEqual(idle.adapterW, 48.7, accuracy: 0.001)
        XCTAssertEqual(idle.batteryW, 0, accuracy: 0.001)
        XCTAssertEqual(idle.systemW, 48.7, accuracy: 0.001)
        XCTAssertEqual(idle.state, .pluggedIdle)
        XCTAssertEqual(try XCTUnwrap(idle.deviceOutputW), 14.083, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(idle.coherentDeviceOutputW), 14.083, accuracy: 0.001)
        XCTAssertEqual(idle.totalInputW, 48.7, accuracy: 0.001)
        XCTAssertEqual(idle.conservationError, 0, accuracy: 0.001)

        let flow = PowerFlowView()
        flow.frame = NSRect(
            x: 0, y: 0, width: PopoverStyle.contentWidth,
            height: PowerFlowView.preferredHeight
        )
        flow.update(snapshot: idle, animated: false)
        flow.layoutSubtreeIfNeeded()
        XCTAssertEqual(flow.topologyForTest, "adapterLed")
        XCTAssertEqual(
            flow.nodePresentationsForTest.map { $0.caption },
            ["Adapter", "Battery · Full", "System Total"]
        )
        let deviceReadout = (flow.accessibilityChildren() ?? [])
            .compactMap { $0 as? NSTextField }
            .filter { $0.accessibilityLabel() == "Device Output" }
        XCTAssertEqual(deviceReadout.map(\.stringValue), ["Device Output · 14.1 W"])

        // Signed V×I remains the direction authority when non-zero, even when
        // the independently sampled source/load totals imply the opposite.
        let mixed = try snapshot(
            instantAmperage: -1_000,
            systemPowerIn: 60_000,
            systemLoad: 40_000
        )
        XCTAssertEqual(mixed.adapterW, 28, accuracy: 0.001)
        XCTAssertEqual(mixed.batteryW, -12, accuracy: 0.001)
        XCTAssertEqual(mixed.systemW, 40, accuracy: 0.001)
        XCTAssertEqual(mixed.state, .mixedSupply)
        XCTAssertEqual(mixed.conservationError, 0, accuracy: 0.001)

        let charging = try snapshot(
            instantAmperage: 600,
            systemPowerIn: 41_500,
            systemLoad: 48_700
        )
        XCTAssertEqual(charging.adapterW, 55.9, accuracy: 0.001)
        XCTAssertEqual(charging.batteryW, 7.2, accuracy: 0.001)
        XCTAssertEqual(charging.systemW, 48.7, accuracy: 0.001)
        XCTAssertEqual(charging.state, .charging)
        XCTAssertEqual(charging.conservationError, 0, accuracy: 0.001)

        for invalidInstant: Double? in [
            nil, .nan, .infinity, -.infinity, 1_001, -1_001,
        ] {
            let fallback = BatterySampler.resolvedPower(
                plugged: true,
                chargingHint: false,
                systemPowerIn: 60_000,
                systemLoad: 40_000,
                batteryPower: -7_200,
                fallbackBatteryW: -7.2,
                instantBatteryW: invalidInstant
            )
            XCTAssertEqual(fallback.adapterW, 60, accuracy: 0.001)
            XCTAssertEqual(fallback.batteryW, 20, accuracy: 0.001)
            XCTAssertEqual(fallback.systemW, 40, accuracy: 0.001)
        }
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

        let outOfRange = BatterySampler.resolvedLivePower(
            snapshot: stale, adapterW: 1_001, systemW: 1_001
        )
        XCTAssertEqual(outOfRange.adapterW, stale.adapterW)
        XCTAssertEqual(outOfRange.batteryW, stale.batteryW)
        XCTAssertEqual(outOfRange.systemW, stale.systemW)

        var corruptBattery = stale
        corruptBattery.batteryW = .nan
        let sanitized = BatterySampler.resolvedLivePower(
            snapshot: corruptBattery, adapterW: nil, systemW: 48
        )
        XCTAssertEqual(sanitized.adapterW, 48, accuracy: 0.001)
        XCTAssertEqual(sanitized.batteryW, 0, accuracy: 0.001)
        XCTAssertEqual(sanitized.systemW, 48, accuracy: 0.001)
        XCTAssertEqual(sanitized.conservationError, 0, accuracy: 0.001)

        var maximumCharge = stale
        maximumCharge.batteryW = 1_000
        let boundedCharge = BatterySampler.resolvedLivePower(
            snapshot: maximumCharge, adapterW: nil, systemW: 900
        )
        XCTAssertEqual(boundedCharge.adapterW, 1_000, accuracy: 0.001)
        XCTAssertEqual(boundedCharge.batteryW, 100, accuracy: 0.001)
        XCTAssertEqual(boundedCharge.systemW, 900, accuracy: 0.001)

        var maximumDischarge = stale
        maximumDischarge.batteryW = -1_000
        let boundedDischarge = BatterySampler.resolvedLivePower(
            snapshot: maximumDischarge, adapterW: 900, systemW: nil
        )
        XCTAssertEqual(boundedDischarge.adapterW, 900, accuracy: 0.001)
        XCTAssertEqual(boundedDischarge.batteryW, -100, accuracy: 0.001)
        XCTAssertEqual(boundedDischarge.systemW, 1_000, accuracy: 0.001)
        XCTAssertEqual(boundedDischarge.conservationError, 0, accuracy: 0.001)
    }

    func testInstantCurrentIsSignedAndFallsBackOnlyWhenMissing() {
        let wrappedNegative = NSNumber(
            value: UInt32(bitPattern: Int32(-2_000))
        )
        XCTAssertEqual(BatterySampler.optionalIntValue(wrappedNegative), -2_000)
        XCTAssertEqual(
            BatterySampler.optionalIntValue(NSNumber(value: UInt64.max - 3_134)),
            -3_135
        )
        XCTAssertNil(BatterySampler.optionalIntValue(NSNumber(value: 12.5)))

        func watts(_ instant: Int?, _ fallback: Int?) -> Double? {
            BatterySampler.resolvedInstantBatteryW(
                voltage: 12_000,
                instantAmperage: instant,
                amperage: fallback
            )
        }

        XCTAssertEqual(watts(-2_000, 1_000)!, -24, accuracy: 0.001)
        XCTAssertEqual(watts(nil, 1_000)!, 12, accuracy: 0.001)
        XCTAssertEqual(watts(0, 1_000)!, 0, accuracy: 0.001)
        for invalidInstant in [
            -1,
            Int(Int32.min),
            Int(Int32.max),
            -100_001,
            100_001,
            Int.min,
            Int.max,
        ] {
            XCTAssertEqual(watts(invalidInstant, -2_000)!, -24, accuracy: 0.001)
        }
        XCTAssertEqual(watts(80_000, nil)!, 960, accuracy: 0.001)
        XCTAssertNil(watts(100_000, nil))
        XCTAssertNil(BatterySampler.resolvedInstantBatteryW(
            voltage: Int.max,
            instantAmperage: 100_000,
            amperage: nil
        ))
        XCTAssertNil(BatterySampler.resolvedInstantBatteryW(
            voltage: 0, instantAmperage: 1_000, amperage: nil
        ))
        XCTAssertNil(watts(nil, nil))
        XCTAssertNil(watts(-1, Int(Int32.max)))
    }

    func testMissingTelemetryRejectsInvalidFallbackAmperage() {
        func sampleEquivalent(_ amperage: Int) -> PowerSnapshot {
            let fallbackBatteryW = BatterySampler.resolvedFallbackBatteryW(
                voltage: 12_000,
                amperage: amperage
            )
            let instantBatteryW = BatterySampler.resolvedInstantBatteryW(
                voltage: 12_000,
                instantAmperage: nil,
                amperage: amperage
            )
            let power = BatterySampler.resolvedPower(
                plugged: true,
                chargingHint: true,
                systemPowerIn: nil,
                systemLoad: nil,
                batteryPower: nil,
                fallbackBatteryW: fallbackBatteryW,
                instantBatteryW: instantBatteryW
            )
            return PowerSnapshot(
                plugged: true,
                adapterW: power.adapterW,
                batteryW: power.batteryW,
                systemW: power.systemW
            )
        }

        for invalidAmperage in [
            -1, Int(Int32.min), Int(Int32.max),
            -100_001, 100_001, Int.min, Int.max,
        ] {
            let snapshot = sampleEquivalent(invalidAmperage)
            XCTAssertEqual(snapshot.adapterW, 0, accuracy: 0.001)
            XCTAssertEqual(snapshot.batteryW, 0, accuracy: 0.001)
            XCTAssertEqual(snapshot.systemW, 0, accuracy: 0.001)
            XCTAssertEqual(snapshot.state, .pluggedIdle)
            XCTAssertEqual(snapshot.conservationError, 0, accuracy: 0.001)
        }

        let valid = sampleEquivalent(1_000)
        XCTAssertEqual(valid.adapterW, 12, accuracy: 0.001)
        XCTAssertEqual(valid.batteryW, 12, accuracy: 0.001)
        XCTAssertEqual(valid.systemW, 0, accuracy: 0.001)
        XCTAssertEqual(valid.conservationError, 0, accuracy: 0.001)
    }

    func testResolvedPowerRandomizedInputsStayFiniteAndConserveEnergy() {
        var state: UInt64 = 0x57A7_7501_C0DE_CAFE
        func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state
        }
        func optionalTelemetry(signed: Bool) -> Int? {
            if next().isMultiple(of: 5) { return nil }
            let magnitude = Int(next() % 2_400_001) - (signed ? 1_200_000 : 200_000)
            return magnitude
        }
        let exceptionalFallbacks: [Double] = [
            .nan, .infinity, -.infinity, -1_001, 1_001,
        ]

        for fallback in exceptionalFallbacks {
            let power = BatterySampler.resolvedPower(
                plugged: true,
                chargingHint: false,
                systemPowerIn: nil,
                systemLoad: nil,
                batteryPower: nil,
                fallbackBatteryW: fallback,
                instantBatteryW: fallback
            )
            XCTAssertTrue(power.adapterW.isFinite)
            XCTAssertTrue(power.batteryW.isFinite)
            XCTAssertTrue(power.systemW.isFinite)
        }

        var observedBooleanPairs = Set<String>()
        for index in 0..<50_000 {
            let fallback = index < exceptionalFallbacks.count
                ? exceptionalFallbacks[index]
                : Double(Int(next() % 2_400_001) - 1_200_000) / 1_000
            let instant: Double? = next().isMultiple(of: 4) ? nil : fallback
            let flags = next()
            let plugged = flags & (1 << 32) != 0
            let chargingHint = flags & (1 << 33) != 0
            observedBooleanPairs.insert("\(plugged)-\(chargingHint)")
            let power = BatterySampler.resolvedPower(
                plugged: plugged,
                chargingHint: chargingHint,
                systemPowerIn: optionalTelemetry(signed: false),
                systemLoad: optionalTelemetry(signed: true),
                batteryPower: optionalTelemetry(signed: true),
                fallbackBatteryW: fallback,
                instantBatteryW: instant
            )
            let snapshot = PowerSnapshot(
                plugged: true,
                adapterW: power.adapterW,
                batteryW: power.batteryW,
                systemW: power.systemW
            )
            XCTAssertTrue(power.adapterW.isFinite, "adapter at iteration \(index)")
            XCTAssertTrue(power.batteryW.isFinite, "battery at iteration \(index)")
            XCTAssertTrue(power.systemW.isFinite, "system at iteration \(index)")
            XCTAssertGreaterThanOrEqual(power.adapterW, 0, "adapter at iteration \(index)")
            XCTAssertGreaterThanOrEqual(power.systemW, 0, "system at iteration \(index)")
            XCTAssertLessThanOrEqual(power.adapterW, 1_000, "adapter at iteration \(index)")
            XCTAssertLessThanOrEqual(abs(power.batteryW), 1_000, "battery at iteration \(index)")
            XCTAssertLessThanOrEqual(power.systemW, 1_000, "system at iteration \(index)")
            XCTAssertEqual(snapshot.conservationError, 0, accuracy: 0.000_001)
        }
        XCTAssertEqual(observedBooleanPairs.count, 4)
    }

    func testBatteryCapacityNormalizesAppleSiliconAndIntelUnits() {
        XCTAssertEqual(BatterySampler.resolvedBatteryPercent(
            currentCapacity: NSNumber(value: 67),
            maxCapacity: NSNumber(value: 100)
        ), 67)
        XCTAssertEqual(BatterySampler.resolvedBatteryPercent(
            currentCapacity: NSNumber(value: 3_500),
            maxCapacity: NSNumber(value: 7_000)
        ), 50)
        XCTAssertEqual(BatterySampler.resolvedBatteryPercent(
            currentCapacity: NSNumber(value: 7_100),
            maxCapacity: NSNumber(value: 7_000)
        ), 100)
        XCTAssertEqual(BatterySampler.resolvedBatteryPercent(
            currentCapacity: NSNumber(value: 0),
            maxCapacity: NSNumber(value: 7_000)
        ), 0)
    }

    func testBatteryCapacityRequiresUnitsFromMaximumCapacity() {
        XCTAssertNil(BatterySampler.resolvedBatteryPercent(
            currentCapacity: NSNumber(value: 67), maxCapacity: nil
        ))
        XCTAssertNil(BatterySampler.resolvedBatteryPercent(
            currentCapacity: NSNumber(value: 0), maxCapacity: nil
        ))
        XCTAssertNil(BatterySampler.resolvedBatteryPercent(
            currentCapacity: NSNumber(value: 3_500), maxCapacity: nil
        ))

        for invalidMaximum: Any in [
            kCFBooleanTrue as Any,
            NSNumber(value: 0),
            NSNumber(value: -1),
            NSNumber(value: 12.5),
            NSNumber(value: Int.max),
        ] {
            XCTAssertNil(BatterySampler.resolvedBatteryPercent(
                currentCapacity: NSNumber(value: 67),
                maxCapacity: invalidMaximum
            ))
        }
        for invalidCurrent: Any in [
            kCFBooleanTrue as Any,
            NSNumber(value: -1),
            NSNumber(value: Int.max),
        ] {
            XCTAssertNil(BatterySampler.resolvedBatteryPercent(
                currentCapacity: invalidCurrent,
                maxCapacity: NSNumber(value: 100)
            ))
        }
        XCTAssertEqual(BatterySampler.resolvedBatteryPercent(
            currentCapacity: NSNumber(value: 101),
            maxCapacity: NSNumber(value: 100)
        ), 100)
    }

    func testInitialBatterySampleDistinguishesAbsentFromTemporaryReadFailure() {
        switch BatterySampler.sampleResult(from: nil, lowPowerMode: false) {
        case .absent: break
        default: XCTFail("missing service must be absent")
        }
        switch BatterySampler.sampleResult(from: [:], lowPowerMode: false) {
        case .temporarilyUnavailable: break
        default: XCTFail("present service with incomplete fields must retry")
        }
        let props: [String: Any] = [
            "CurrentCapacity": NSNumber(value: 3_500),
            "MaxCapacity": NSNumber(value: 7_000),
            "ExternalConnected": kCFBooleanFalse as Any,
        ]
        switch BatterySampler.sampleResult(from: props, lowPowerMode: true) {
        case let .snapshot(snapshot):
            XCTAssertEqual(snapshot.percent, 50)
            XCTAssertTrue(snapshot.lowPowerMode)
        default:
            XCTFail("valid fields must produce a snapshot")
        }
    }

    func testPluggedTransitionUsesInstantBatteryFlowUntilSourceTelemetryArrives() {
        func resolve(
            plugged: Bool = true,
            chargingHint: Bool,
            systemPowerIn: Int?,
            systemLoad: Int? = 40_000,
            instantBatteryW: Double
        ) -> PowerSnapshot {
            let power = BatterySampler.resolvedPower(
                plugged: plugged,
                chargingHint: chargingHint,
                systemPowerIn: systemPowerIn,
                systemLoad: systemLoad,
                batteryPower: -9_000,
                fallbackBatteryW: -9,
                instantBatteryW: instantBatteryW
            )
            return PowerSnapshot(
                plugged: plugged,
                adapterW: power.adapterW,
                batteryW: power.batteryW,
                systemW: power.systemW
            )
        }

        func check(
            _ snapshot: PowerSnapshot,
            adapterW: Double,
            batteryW: Double,
            systemW: Double,
            state: PowerState,
            _ message: String
        ) {
            XCTAssertEqual(snapshot.adapterW, adapterW, accuracy: 0.001, message)
            XCTAssertEqual(snapshot.batteryW, batteryW, accuracy: 0.001, message)
            XCTAssertEqual(snapshot.systemW, systemW, accuracy: 0.001, message)
            XCTAssertEqual(snapshot.state, state, message)
            XCTAssertEqual(snapshot.conservationError, 0, accuracy: 0.001, message)
        }

        let cases: [(
            String, Bool, Bool, Int?, Int?, Double,
            Double, Double, Double, PowerState
        )] = [
            ("zero source charge", true, false, 0, 40_000, 24, 64, 24, 40, .charging),
            ("source sentinel", true, false, -1, 40_000, 24, 64, 24, 40, .charging),
            ("transition idle", true, true, nil, 40_000, 0, 40, 0, 40, .pluggedIdle),
            ("stale charging hint", true, true, 0, 40_000, -12, 28, -12, 40, .mixedSupply),
            ("bounded discharge", true, true, nil, 40_000, -60, 0, -40, 40, .mixedSupply),
            ("nil load charge", true, false, nil, nil, 24, 24, 24, 0, .charging),
            ("nil load idle", true, true, nil, nil, 0, 0, 0, 0, .pluggedIdle),
            ("nil load mixed", true, true, nil, nil, -12, 0, -12, 12, .mixedSupply),
            ("zero load charge", true, false, 0, 0, 24, 24, 24, 0, .charging),
            ("zero load mixed", true, true, 0, 0, -12, 0, -12, 12, .mixedSupply),
            ("unplug old AC", false, true, 60_000, 40_000, 24, 0, -40, 40, .onBattery),
            ("signed current overrides asynchronous totals", true, false,
             60_000, 40_000, -12, 28, -12, 40, .mixedSupply),
        ]
        for (name, plugged, hint, source, load, instant,
             adapter, battery, system, state) in cases {
            check(
                resolve(
                    plugged: plugged,
                    chargingHint: hint,
                    systemPowerIn: source,
                    systemLoad: load,
                    instantBatteryW: instant
                ),
                adapterW: adapter,
                batteryW: battery,
                systemW: system,
                state: state,
                name
            )
        }

        let mergeCases: [(Int?, Double, PowerState)] = [
            (nil, 24, .charging), (nil, 0, .pluggedIdle),
            (nil, -12, .mixedSupply), (0, 24, .charging),
            (0, -12, .mixedSupply),
        ]
        for (load, instant, state) in mergeCases {
            let transition = resolve(
                chargingHint: true,
                systemPowerIn: nil,
                systemLoad: load,
                instantBatteryW: instant
            )
            check(
                BatterySampler.resolvedLivePower(
                    snapshot: transition, adapterW: 1, systemW: 45
                ),
                adapterW: 45 + instant,
                batteryW: instant,
                systemW: 45,
                state: state,
                "live PSTR merge"
            )
        }
    }

    func testAdapterOnlyTelemetryUsesSignedInstantBatteryFlow() {
        func resolve(chargingHint: Bool, instantBatteryW: Double) -> PowerSnapshot {
            let power = BatterySampler.resolvedPower(
                plugged: true,
                chargingHint: chargingHint,
                systemPowerIn: 60_000,
                systemLoad: nil,
                batteryPower: nil,
                fallbackBatteryW: abs(instantBatteryW),
                instantBatteryW: instantBatteryW
            )
            return PowerSnapshot(
                plugged: true,
                adapterW: power.adapterW,
                batteryW: power.batteryW,
                systemW: power.systemW
            )
        }

        let discharging = resolve(chargingHint: true, instantBatteryW: -12)
        XCTAssertEqual(discharging.adapterW, 60, accuracy: 0.001)
        XCTAssertEqual(discharging.batteryW, -12, accuracy: 0.001)
        XCTAssertEqual(discharging.systemW, 72, accuracy: 0.001)
        XCTAssertEqual(discharging.state, .mixedSupply)
        XCTAssertEqual(discharging.conservationError, 0, accuracy: 0.001)

        let charging = resolve(chargingHint: false, instantBatteryW: 12)
        XCTAssertEqual(charging.adapterW, 60, accuracy: 0.001)
        XCTAssertEqual(charging.batteryW, 12, accuracy: 0.001)
        XCTAssertEqual(charging.systemW, 48, accuracy: 0.001)
        XCTAssertEqual(charging.state, .charging)
        XCTAssertEqual(charging.conservationError, 0, accuracy: 0.001)
    }

    func testCycleCountRejectsWrappedAndImplausibleValues() {
        XCTAssertEqual(BatterySampler.resolvedCycleCount(NSNumber(value: 1_234)), 1_234)
        XCTAssertEqual(BatterySampler.resolvedCycleCount(NSNumber(value: 0)), 0)
        for raw: Any in [
            NSNumber(value: -1),
            NSNumber(value: Int32.min),
            NSNumber(value: UInt32.max),
            NSNumber(value: Int.max),
            NSNumber(value: 100_001),
            kCFBooleanTrue as Any,
            NSNumber(value: 1.5),
        ] {
            XCTAssertEqual(BatterySampler.resolvedCycleCount(raw), 0)
        }
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

    func testRingGaugeReusesTrailingSlotWithoutChangingGeometry() {
        let gauge = RingGaugeView()
        gauge.frame = NSRect(
            x: 0, y: 0,
            width: PopoverStyle.contentWidth,
            height: RingGaugeView.preferredHeight
        )
        gauge.layoutSubtreeIfNeeded()
        let fixedFrames = gauge.visibleReadingFramesForTest
        var snapshot = PowerSnapshot(
            percent: 72, plugged: true, adapterW: 68,
            batteryW: 22.2, systemW: 45.8,
            temperatureC: 34.2, cycleCount: 116
        )
        let sequence: [(Double?, String, String)] = [
            (nil, "Cycle Count", "116"),
            (7.5, "Device Output", "7.5 W"),
            (0, "Device Output", "0.0 W"),
            (46.2, "Cycle Count", "116"),
            (nil, "Cycle Count", "116"),
        ]

        XCTAssertEqual(RingGaugeView.preferredHeight, 138)
        XCTAssertEqual(gauge.bounds.height, 138)
        XCTAssertEqual(fixedFrames.count, 8)
        for (output, caption, value) in sequence {
            snapshot.deviceOutputW = output
            gauge.update(snapshot: snapshot)
            gauge.layoutSubtreeIfNeeded()
            XCTAssertEqual(gauge.trailingReadingForTest.caption, caption)
            XCTAssertEqual(gauge.trailingReadingForTest.value, value)
            XCTAssertEqual(gauge.visibleReadingFramesForTest, fixedFrames)
            XCTAssertTrue(gauge.statsFitBoundsForTest)

            let children = gauge.accessibilityChildren() ?? []
            let fields = children.compactMap { $0 as? NSTextField }
            let trailingElements = fields
                .filter { $0.accessibilityLabel() == caption }
            XCTAssertEqual(children.count, 9)
            XCTAssertEqual(fields.count, 1)
            XCTAssertEqual(trailingElements.count, 1)
            XCTAssertEqual(trailingElements.first?.accessibilityRole(), .staticText)
            XCTAssertEqual(trailingElements.first?.accessibilityValue(), value)
            XCTAssertEqual(
                fields.filter { $0.accessibilityLabel() == "Device Output" }.count,
                caption == "Device Output" ? 1 : 0
            )
        }
    }

    func testPositiveCoherentDeviceOutputUsesSystemTotalAcrossInstrumentLabels() throws {
        let gauge = RingGaugeView()
        let lanes = LaneView()
        gauge.frame = NSRect(
            x: 0, y: 0,
            width: PopoverStyle.contentWidth,
            height: RingGaugeView.preferredHeight
        )
        lanes.frame = NSRect(
            x: 0, y: 0,
            width: PopoverStyle.contentWidth,
            height: LaneView.preferredHeight
        )

        func caption(_ text: String, in view: NSView) -> NSTextField? {
            view.subviews.compactMap { $0 as? NSTextField }.first {
                $0.stringValue == text
            }
        }

        func assertSystemCaption(
            _ expected: String,
            snapshot: PowerSnapshot,
            file: StaticString = #filePath,
            line: UInt = #line
        ) throws {
            gauge.update(snapshot: snapshot)
            lanes.update(snapshot: snapshot)
            gauge.layoutSubtreeIfNeeded()
            lanes.layoutSubtreeIfNeeded()

            for view in [gauge, lanes] {
                let field = try XCTUnwrap(caption(expected, in: view), file: file, line: line)
                XCTAssertEqual(
                    field.accessibilityValue(),
                    expected,
                    file: file,
                    line: line
                )
                let other = expected == "System Total" ? "System Load" : "System Total"
                XCTAssertNil(caption(other, in: view), file: file, line: line)
            }
        }

        let baseline = PowerSnapshot(
            percent: 67, plugged: false, adapterW: 0,
            batteryW: -39.7, systemW: 39.7
        )
        try assertSystemCaption("System Load", snapshot: baseline)

        var measuredZero = baseline
        measuredZero.deviceOutputW = 0
        try assertSystemCaption("System Load", snapshot: measuredZero)

        var split = baseline
        split.deviceOutputW = 12.2
        try assertSystemCaption("System Total", snapshot: split)
        XCTAssertEqual(split.totalInputW, baseline.totalInputW, accuracy: 0.001)
        XCTAssertEqual(split.conservationError, baseline.conservationError, accuracy: 0.001)

        var inconsistent = baseline
        inconsistent.deviceOutputW = 39.8
        try assertSystemCaption("System Load", snapshot: inconsistent)
        XCTAssertEqual(inconsistent.deviceOutputW, 39.8)
        XCTAssertNil(inconsistent.coherentDeviceOutputW)
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
        XCTAssertEqual(history.presentationMaterializationCountForTest, 1)

        let repeated = history.presentation
        XCTAssertEqual(repeated.samples, presentation.samples)
        XCTAssertEqual(repeated.peak, presentation.peak)
        XCTAssertEqual(history.presentationMaterializationCountForTest, 1)

        history.append(75)
        XCTAssertEqual(history.presentation.peak, 75)
        XCTAssertEqual(history.presentationMaterializationCountForTest, 2)

        history.reset()
        XCTAssertTrue(history.presentation.samples.isEmpty)
        XCTAssertEqual(history.presentation.peak, 0)
        XCTAssertEqual(history.presentationMaterializationCountForTest, 3)
        history.append(9)
        XCTAssertEqual(history.samples, [9])
    }

    func testHistoryRejectsNonFiniteValuesAndSurvivesLongWraps() {
        let history = PowerHistory()
        history.append(.nan)
        history.append(.infinity)
        history.append(-.infinity)
        XCTAssertTrue(history.samples.isEmpty)

        history.append(-3)
        XCTAssertEqual(history.samples, [0])
        for value in 0..<100_000 {
            history.append(Double(value))
        }
        XCTAssertEqual(history.samples.count, 60)
        XCTAssertEqual(history.samples.first, 99_940)
        XCTAssertEqual(history.samples.last, 99_999)
        XCTAssertTrue(history.samples.allSatisfy { $0.isFinite && $0 >= 0 })
    }

    func testStatusButtonPresentationIgnoresNonVisualTelemetry() {
        let baseline = PowerSnapshot(
            percent: 67, plugged: true, adapterW: 70, batteryW: 20, systemW: 50
        )
        let changedWatts = PowerSnapshot(
            percent: 67, plugged: true, adapterW: 95, batteryW: 30, systemW: 65
        )

        let first = StatusButtonPresentation(
            snapshot: baseline, showsPercentage: true, degraded: false
        )
        let sameChrome = StatusButtonPresentation(
            snapshot: changedWatts, showsPercentage: true, degraded: false
        )
        XCTAssertEqual(first, sameChrome)
        XCTAssertEqual(first.title, "67% ")
        XCTAssertEqual(first.alpha, 1)
        XCTAssertNotEqual(first, StatusButtonPresentation(
            snapshot: baseline, showsPercentage: false, degraded: false
        ))
        XCTAssertNotEqual(first, StatusButtonPresentation(
            snapshot: baseline, showsPercentage: true, degraded: true
        ))
    }

    func testColdStartAvailabilityDistinguishesAbsentFromRepeatedPartialReads() {
        var absent = StartupAvailabilityReducer()
        let absentPlan = absent.start(.absent)
        XCTAssertTrue(absentPlan.shouldTerminate)
        XCTAssertFalse(absentPlan.shouldRetry)
        XCTAssertNil(absentPlan.snapshot)
        XCTAssertFalse(absentPlan.shouldRecordHistory)
        XCTAssertFalse(absent.hasUsableSnapshot)
        XCTAssertFalse(absent.isDegraded)

        var partial = StartupAvailabilityReducer()
        let partialPlan = partial.start(.temporarilyUnavailable)
        XCTAssertFalse(partialPlan.shouldTerminate)
        XCTAssertTrue(partialPlan.shouldRetry)
        XCTAssertNil(partialPlan.snapshot)
        XCTAssertFalse(partialPlan.shouldRecordHistory)
        XCTAssertFalse(partial.hasUsableSnapshot)
        XCTAssertTrue(partial.isDegraded)

        for _ in 0..<3 {
            let repeated = partial.finish(nil, recordHistory: true)
            XCTAssertFalse(repeated.shouldTerminate)
            XCTAssertFalse(repeated.shouldRetry)
            XCTAssertNil(repeated.snapshot)
            XCTAssertFalse(repeated.shouldRecordHistory)
            XCTAssertFalse(partial.hasUsableSnapshot)
            XCTAssertTrue(partial.isDegraded)
        }
    }

    func testColdPartialAvailabilityRecoversAndRecordsRequestedHistory() {
        var availability = StartupAvailabilityReducer()
        _ = availability.start(.temporarilyUnavailable)

        let recovered = PowerSnapshot(
            percent: 68, plugged: true, adapterW: 61, batteryW: 9, systemW: 52
        )
        let plan = availability.finish(recovered, recordHistory: true)

        XCTAssertEqual(plan.snapshot?.percent, 68)
        XCTAssertTrue(plan.shouldRecordHistory)
        XCTAssertFalse(plan.shouldRetry)
        XCTAssertFalse(plan.shouldTerminate)
        XCTAssertTrue(availability.hasUsableSnapshot)
        XCTAssertFalse(availability.isDegraded)
    }

    func testAvailabilityRetainsUsableStateAcrossDegradationAndRecovery() {
        var availability = StartupAvailabilityReducer()
        let initial = availability.start(.snapshot(PowerSnapshot(
            percent: 67, plugged: false, batteryW: -18, systemW: 18
        )))
        XCTAssertEqual(initial.snapshot?.percent, 67)
        XCTAssertTrue(initial.shouldRecordHistory)
        XCTAssertTrue(availability.hasUsableSnapshot)
        XCTAssertFalse(availability.isDegraded)

        let degraded = availability.finish(nil, recordHistory: true)
        XCTAssertNil(degraded.snapshot)
        XCTAssertFalse(degraded.shouldRecordHistory)
        XCTAssertTrue(availability.hasUsableSnapshot)
        XCTAssertTrue(availability.isDegraded)

        let recovered = availability.finish(
            PowerSnapshot(percent: 66, plugged: false, batteryW: -20, systemW: 20),
            recordHistory: false
        )
        XCTAssertEqual(recovered.snapshot?.percent, 66)
        XCTAssertFalse(recovered.shouldRecordHistory)
        XCTAssertTrue(availability.hasUsableSnapshot)
        XCTAssertFalse(availability.isDegraded)
    }

    func testPeriodicSampleRequestsCoalesceWithoutCatchUpStorm() {
        var requests = SampleRequestCoalescer()
        XCTAssertTrue(requests.request(
            recordHistory: false, requiresFreshFollowUp: false
        ))

        for index in 0..<10_000 {
            XCTAssertFalse(requests.request(
                recordHistory: index.isMultiple(of: 2),
                requiresFreshFollowUp: false
            ))
        }

        let completed = requests.complete()
        XCTAssertTrue(completed.recordHistory)
        XCTAssertFalse(completed.requiresFreshFollowUp)
        XCTAssertTrue(completed.publishCurrent)
        XCTAssertFalse(requests.isInFlight)
        XCTAssertTrue(requests.request(
            recordHistory: false, requiresFreshFollowUp: false
        ))
    }

    func testEventSampleRequestsRetainAtMostOneFreshFollowUp() {
        var requests = SampleRequestCoalescer()
        XCTAssertTrue(requests.request(
            recordHistory: false, requiresFreshFollowUp: false
        ))

        for index in 0..<10_000 {
            XCTAssertFalse(requests.request(
                recordHistory: index == 9_999, requiresFreshFollowUp: true
            ))
        }

        let first = requests.complete()
        XCTAssertTrue(first.recordHistory)
        XCTAssertTrue(first.requiresFreshFollowUp)
        XCTAssertTrue(first.publishCurrent)

        // Ordinary events keep one follow-up without discarding completed work
        // or recording the same coalesced history request twice.
        XCTAssertTrue(requests.request(
            recordHistory: first.recordHistory && !first.publishCurrent,
            requiresFreshFollowUp: false
        ))
        let second = requests.complete()
        XCTAssertFalse(second.recordHistory)
        XCTAssertFalse(second.requiresFreshFollowUp)
        XCTAssertTrue(second.publishCurrent)
        XCTAssertFalse(requests.isInFlight)
    }

    func testContinuousEventSamplesDoNotStarvePublication() {
        var requests = SampleRequestCoalescer()
        var publications = 0
        var historyRecords = 0
        XCTAssertTrue(requests.request(
            recordHistory: false, requiresFreshFollowUp: false
        ))

        for index in 0..<100 {
            XCTAssertFalse(requests.request(
                recordHistory: index.isMultiple(of: 2),
                requiresFreshFollowUp: false
            ))
            XCTAssertFalse(requests.request(
                recordHistory: false, requiresFreshFollowUp: true
            ))
            let completed = requests.complete()
            XCTAssertTrue(completed.requiresFreshFollowUp)
            // Mirror finishSample: only non-superseded results are published.
            if completed.publishCurrent {
                publications += 1
                if completed.recordHistory { historyRecords += 1 }
            }
            XCTAssertTrue(requests.request(
                recordHistory: completed.recordHistory && !completed.publishCurrent,
                requiresFreshFollowUp: false
            ))
        }

        XCTAssertEqual(publications, 100)
        XCTAssertEqual(historyRecords, 50)
        let final = requests.complete()
        XCTAssertTrue(final.publishCurrent)
        XCTAssertFalse(final.requiresFreshFollowUp)
        XCTAssertFalse(final.recordHistory)
    }

    func testWakeSampleSupersedesUntilOnePostWakeAcquisitionCompletes() {
        var requests = SampleRequestCoalescer()
        XCTAssertTrue(requests.request(
            recordHistory: true, requiresFreshFollowUp: false
        ))
        XCTAssertFalse(requests.request(
            recordHistory: false, requiresFreshFollowUp: true
        ))
        XCTAssertFalse(requests.request(
            recordHistory: true, requiresFreshFollowUp: true,
            supersedesCurrent: true
        ))
        // Later ordinary notifications must not downgrade wake invalidation.
        XCTAssertFalse(requests.request(
            recordHistory: false, requiresFreshFollowUp: true
        ))
        let beforeWake = requests.complete()
        XCTAssertFalse(beforeWake.publishCurrent)
        XCTAssertTrue(beforeWake.requiresFreshFollowUp)
        XCTAssertTrue(beforeWake.recordHistory)

        XCTAssertTrue(requests.request(
            recordHistory: beforeWake.recordHistory && !beforeWake.publishCurrent,
            requiresFreshFollowUp: false
        ))
        // A post-wake IOPS event keeps a follow-up but does not suppress the
        // first acquisition started after wake or its single history record.
        XCTAssertFalse(requests.request(
            recordHistory: false, requiresFreshFollowUp: true
        ))
        let afterWake = requests.complete()
        XCTAssertTrue(afterWake.publishCurrent)
        XCTAssertTrue(afterWake.recordHistory)
        XCTAssertTrue(afterWake.requiresFreshFollowUp)
        XCTAssertTrue(requests.request(
            recordHistory: afterWake.recordHistory && !afterWake.publishCurrent,
            requiresFreshFollowUp: false
        ))
        let final = requests.complete()
        XCTAssertTrue(final.publishCurrent)
        XCTAssertFalse(final.recordHistory)
        XCTAssertFalse(final.requiresFreshFollowUp)
    }

    func testIdleWakeSamplePublishesWithoutUnnecessaryFollowUp() {
        var requests = SampleRequestCoalescer()
        XCTAssertTrue(requests.request(
            recordHistory: true, requiresFreshFollowUp: true,
            supersedesCurrent: true
        ))
        let completed = requests.complete()
        XCTAssertTrue(completed.publishCurrent)
        XCTAssertTrue(completed.recordHistory)
        XCTAssertFalse(completed.requiresFreshFollowUp)
    }

    func testSupersedingSampleAlwaysRetainsAFreshFollowUp() {
        var requests = SampleRequestCoalescer()
        XCTAssertTrue(requests.request(
            recordHistory: false, requiresFreshFollowUp: false
        ))
        XCTAssertFalse(requests.request(
            recordHistory: true, requiresFreshFollowUp: false,
            supersedesCurrent: true
        ))
        let completed = requests.complete()
        XCTAssertFalse(completed.publishCurrent)
        XCTAssertTrue(completed.recordHistory)
        XCTAssertTrue(completed.requiresFreshFollowUp)
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
            style: .wattson,
            appearance: appearance, increasedContrast: false
        )
        let samePixels = BatteryIcon.renderKey(
            for: changedWatts, mode: .auto, pressed: false,
            style: .wattson,
            appearance: appearance, increasedContrast: false
        )
        XCTAssertEqual(first, samePixels)

        var changedPercent = baseline
        changedPercent.percent = 66
        XCTAssertNotEqual(first, BatteryIcon.renderKey(
            for: changedPercent, mode: .auto, pressed: false,
            style: .wattson,
            appearance: appearance, increasedContrast: false
        ))
        XCTAssertNotEqual(first, BatteryIcon.renderKey(
            for: baseline, mode: .low, pressed: false,
            style: .wattson,
            appearance: appearance, increasedContrast: false
        ))
        XCTAssertNotEqual(first, BatteryIcon.renderKey(
            for: baseline, mode: .auto, pressed: false,
            style: .wattson,
            appearance: NSAppearance(named: .aqua)!, increasedContrast: false
        ))
        XCTAssertNotEqual(first, BatteryIcon.renderKey(
            for: baseline, mode: .auto, pressed: false,
            style: .wattson,
            appearance: appearance, increasedContrast: true
        ))
        XCTAssertNotEqual(first, BatteryIcon.renderKey(
            for: baseline, mode: .auto, pressed: false,
            style: .native,
            appearance: appearance, increasedContrast: false
        ))
    }

    func testNativeBatteryIconKeyTracksExactFillAndSystemPowerAdornment() {
        let baseline = PowerSnapshot(
            percent: 67, plugged: false, adapterW: 0, batteryW: -20, systemW: 20
        )
        let dark = NSAppearance(named: .darkAqua)!
        let first = BatteryIcon.renderKey(
            for: baseline, mode: .auto, pressed: false,
            style: .native,
            appearance: dark, increasedContrast: false
        )
        let lowPower = BatteryIcon.renderKey(
            for: baseline, mode: .low, pressed: false,
            style: .native,
            appearance: dark, increasedContrast: false
        )
        XCTAssertNotEqual(first, lowPower)
        XCTAssertEqual(lowPower.tintRole, .lowPower)
        XCTAssertEqual(BatteryIcon.renderKey(
            for: baseline, mode: .low, pressed: true,
            style: .native,
            appearance: dark, increasedContrast: false
        ).tintRole, .template)

        var changedPercent = baseline
        changedPercent.percent = 68
        XCTAssertNotEqual(first, BatteryIcon.renderKey(
            for: changedPercent, mode: .auto, pressed: false,
            style: .native,
            appearance: dark, increasedContrast: false
        ))
        var pluggedIdle = baseline
        pluggedIdle.plugged = true
        pluggedIdle.batteryW = 0
        pluggedIdle.adapterW = 20
        let pluggedKey = BatteryIcon.renderKey(
            for: pluggedIdle, mode: .auto, pressed: false,
            style: .native,
            appearance: dark, increasedContrast: false
        )
        XCTAssertNotEqual(first, pluggedKey)
        XCTAssertTrue(pluggedKey.showsBolt)
        var charging = pluggedIdle
        charging.batteryW = 5
        charging.systemW = 15
        let chargingKey = BatteryIcon.renderKey(
            for: charging, mode: .auto, pressed: false,
            style: .native,
            appearance: dark, increasedContrast: false
        )
        XCTAssertEqual(pluggedKey, chargingKey)
        XCTAssertTrue(chargingKey.showsBolt)
    }

    func testNativeBatteryRendersEveryConnectedPowerStateWithTheSameSystemBolt() throws {
        let onBattery = PowerSnapshot(
            percent: 42, plugged: false, adapterW: 0, batteryW: -18, systemW: 18
        )
        let pluggedIdle = PowerSnapshot(
            percent: 42, plugged: true, adapterW: 42, batteryW: 0, systemW: 42
        )
        let charging = PowerSnapshot(
            percent: 42, plugged: true, adapterW: 60, batteryW: 18, systemW: 42
        )
        let images = [onBattery, pluggedIdle, charging].map {
            BatteryIcon.image(for: $0, mode: .auto, pressed: false, style: .native)
        }
        XCTAssertTrue(images.allSatisfy(\.isTemplate))
        let pixels = try images.map { try XCTUnwrap($0.tiffRepresentation) }
        XCTAssertNotEqual(pixels[0], pixels[1])
        XCTAssertEqual(pixels[1], pixels[2])
        XCTAssertNotEqual(pixels[0], pixels[2])
    }

    func testNativeBatteryIconIsAResolutionIndependentTemplate() {
        let snapshot = PowerSnapshot(
            percent: 42, plugged: true, adapterW: 65, batteryW: 20, systemW: 45
        )
        let image = BatteryIcon.image(
            for: snapshot, mode: .auto, pressed: false, style: .native
        )
        XCTAssertTrue(image.isTemplate)
        XCTAssertEqual(image.size.width, 25)
        XCTAssertEqual(image.size.height, 14)
    }

    func testNativeFullBatteryUsesTheOpaqueSystemFill() throws {
        let snapshot = PowerSnapshot(
            percent: 100, plugged: true, adapterW: 42, batteryW: 0, systemW: 42
        )
        let image = BatteryIcon.image(
            for: snapshot, mode: .auto, pressed: false, style: .native
        )
        let data = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
        let scaleX = CGFloat(bitmap.pixelsWide) / image.size.width
        let scaleY = CGFloat(bitmap.pixelsHigh) / image.size.height
        let fill = try XCTUnwrap(bitmap.colorAt(
            x: Int((3 * scaleX).rounded(.down)),
            y: Int((7 * scaleY).rounded(.down))
        ))
        XCTAssertGreaterThan(fill.alphaComponent, 0.95)
    }

    func testNativeLowPowerColorsTheFillButKeepsANeutralOutline() throws {
        let snapshot = PowerSnapshot(
            percent: 42, plugged: false, adapterW: 0, batteryW: -18, systemW: 18
        )
        let image = BatteryIcon.image(
            for: snapshot, mode: .low, pressed: false, style: .native
        )
        XCTAssertFalse(image.isTemplate)

        let data = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
        var yellowPixels = 0
        var neutralPixels = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      color.alphaComponent > 0.2 else { continue }
                let red = color.redComponent
                let green = color.greenComponent
                let blue = color.blueComponent
                if red > 0.7 && green > 0.5 && blue < 0.35 {
                    yellowPixels += 1
                } else if max(red, green, blue) - min(red, green, blue) < 0.12 {
                    neutralPixels += 1
                }
            }
        }
        XCTAssertGreaterThan(yellowPixels, 0, "the battery fill must be yellow")
        XCTAssertGreaterThan(neutralPixels, 0, "the outline must remain menu-bar neutral")
    }

    func testDeviceOutputPowerFlowLayoutsFallbacksAndAccessibility() {
        let flow = PowerFlowView()
        flow.frame = NSRect(
            x: 0, y: 0, width: PopoverStyle.contentWidth,
            height: PowerFlowView.preferredHeight
        )
        flow.layoutSubtreeIfNeeded()

        func show(_ snapshot: PowerSnapshot) {
            flow.update(snapshot: snapshot, animated: false)
            flow.layoutSubtreeIfNeeded()
        }
        func deviceOutputFields() -> [NSTextField] {
            (flow.accessibilityChildren() ?? [])
                .compactMap { $0 as? NSTextField }
                .filter { $0.accessibilityLabel() == "Device Output" }
        }
        let deviceOutputPortIconData = FlowNodeView
            .iconImageForTest(symbol: "device.output.port")?
            .tiffRepresentation
        XCTAssertNotNil(deviceOutputPortIconData)

        func descendants(of view: NSView) -> [NSView] {
            view.subviews + view.subviews.flatMap(descendants(of:))
        }

        func isEffectivelyVisible(_ view: NSView) -> Bool {
            var candidate: NSView? = view
            while let current = candidate {
                if current.isHidden || current.alphaValue <= 0 { return false }
                candidate = current.superview
            }
            return true
        }
        func visibleIconViews() -> [NSImageView] {
            descendants(of: flow)
                .compactMap { $0 as? NSImageView }
                .filter { $0.image != nil && isEffectivelyVisible($0) }
        }

        func iconViews(matching imageData: Data?, visibleOnly: Bool = false) -> [NSImageView] {
            guard let imageData else { return [] }
            let icons = descendants(of: flow)
                .compactMap { $0 as? NSImageView }
                .filter {
                $0.image?.tiffRepresentation == imageData
            }
            return visibleOnly ? icons.filter(isEffectivelyVisible) : icons
        }

        func deviceOutputPortIconViews(visibleOnly: Bool = false) -> [NSImageView] {
            iconViews(matching: deviceOutputPortIconData, visibleOnly: visibleOnly)
        }

        func assertPluggedDeviceOutputAccessory(
            _ watts: Double,
            file: StaticString = #filePath,
            line: UInt = #line
        ) {
            let fields = deviceOutputFields()
            XCTAssertEqual(fields.count, 1, file: file, line: line)
            guard let readout = fields.first else { return }
            let value = PopoverStyle.watts(watts)
            XCTAssertEqual(
                readout.stringValue,
                "Device Output · \(value)",
                file: file,
                line: line
            )
            XCTAssertEqual(readout.accessibilityRole(), .staticText, file: file, line: line)
            XCTAssertEqual(readout.accessibilityLabel(), "Device Output", file: file, line: line)
            XCTAssertEqual(readout.accessibilityValue(), value, file: file, line: line)

            XCTAssertEqual(flow.nodePresentationsForTest.count, 3, file: file, line: line)
            XCTAssertEqual(flow.nodeFramesForTest.count, 3, file: file, line: line)
            XCTAssertEqual(flow.branchThicknessesForTest.count, 2, file: file, line: line)

            let deviceIcons = deviceOutputPortIconViews()
            XCTAssertEqual(
                deviceIcons.count,
                1,
                "plugged Device Output must own exactly one port-template icon",
                file: file,
                line: line
            )
            XCTAssertEqual(
                deviceOutputPortIconViews(visibleOnly: true).count,
                1,
                "the inline port-template icon must be visible with the readout",
                file: file,
                line: line
            )
            XCTAssertEqual(
                visibleIconViews().count,
                4,
                "the three graph nodes plus one inline cable icon must be visible",
                file: file,
                line: line
            )

            guard let icon = deviceIcons.first,
                  let well = icon.superview else { return }
            XCTAssertFalse(icon.isAccessibilityElement(), file: file, line: line)
            XCTAssertFalse(icon.cell?.isAccessibilityElement() ?? true, file: file, line: line)
            XCTAssertEqual(well.bounds.width, 26, accuracy: 0.5, file: file, line: line)
            XCTAssertEqual(well.bounds.height, 26, accuracy: 0.5, file: file, line: line)
            XCTAssertEqual(well.layer?.cornerRadius ?? 0, 8, accuracy: 1, file: file, line: line)
            XCTAssertEqual(well.layer?.borderWidth ?? 0, 0.5, accuracy: 0.01, file: file, line: line)
            XCTAssertNotNil(well.layer?.backgroundColor, file: file, line: line)
            XCTAssertNotNil(well.layer?.borderColor, file: file, line: line)

            let wellFrame = flow.convert(well.bounds, from: well)
            let readoutFrame = flow.convert(readout.bounds, from: readout)
            XCTAssertLessThan(wellFrame.maxX, readoutFrame.minX, file: file, line: line)
            let gap = readoutFrame.minX - wellFrame.maxX
            XCTAssertGreaterThanOrEqual(gap, 4, file: file, line: line)
            XCTAssertLessThanOrEqual(gap, 8, file: file, line: line)
            XCTAssertEqual(wellFrame.midY, readoutFrame.midY, accuracy: 1, file: file, line: line)
            XCTAssertEqual(
                wellFrame.union(readoutFrame).midX,
                flow.bounds.midX,
                accuracy: 0.75,
                "icon and text must be centred as one inline group",
                file: file,
                line: line
            )
            XCTAssertLessThan(
                readoutFrame.width,
                flow.bounds.width / 2,
                "the text frame must hug its content so the combined group can be centred",
                file: file,
                line: line
            )
        }

        func assertNoPluggedDeviceOutputAccessory(
            file: StaticString = #filePath,
            line: UInt = #line
        ) {
            XCTAssertTrue(deviceOutputFields().isEmpty, file: file, line: line)
            XCTAssertTrue(
                deviceOutputPortIconViews().isEmpty,
                "hidden/invalid Device Output must clear the accessory icon image",
                file: file,
                line: line
            )
            XCTAssertEqual(visibleIconViews().count, 3, file: file, line: line)
            XCTAssertEqual(flow.nodePresentationsForTest.count, 3, file: file, line: line)
            XCTAssertEqual(flow.nodeFramesForTest.count, 3, file: file, line: line)
            XCTAssertEqual(flow.branchThicknessesForTest.count, 2, file: file, line: line)
        }
        func onBattery(_ output: Double?) -> PowerSnapshot {
            PowerSnapshot(
                percent: 67, plugged: false, adapterW: 0,
                batteryW: -39.7, systemW: 39.7, deviceOutputW: output
            )
        }

        let split = onBattery(12.2)
        show(split)
        XCTAssertEqual(flow.topologyForTest, "batteryOutputSplit")
        let presentations = flow.nodePresentationsForTest
        XCTAssertEqual(
            presentations.map { $0.caption },
            ["Battery 67%", "Device Output", "Mac Load"]
        )
        XCTAssertEqual(
            presentations.map { $0.value },
            ["39.7 W", "12.2 W", "27.5 W"]
        )
        let accessibleFields = (flow.accessibilityChildren() ?? [])
            .compactMap { $0 as? NSTextField }
        XCTAssertEqual(accessibleFields.count, 3)
        XCTAssertEqual(
            accessibleFields.map { $0.accessibilityLabel() },
            presentations.map { Optional($0.caption) }
        )
        XCTAssertEqual(
            accessibleFields.map { $0.accessibilityValue() },
            presentations.map { Optional($0.value) }
        )
        XCTAssertTrue(accessibleFields.allSatisfy { $0.accessibilityRole() == .staticText })
        XCTAssertEqual(deviceOutputFields().map(\.stringValue), ["12.2 W"])
        XCTAssertEqual(
            deviceOutputPortIconViews().count,
            1,
            "on-battery Device Output must reuse the same port-template icon"
        )
        XCTAssertEqual(
            visibleIconViews().count,
            3,
            "on-battery already uses a Device Output node and must not add an accessory duplicate"
        )
        XCTAssertEqual(flow.branchThicknessesForTest.count, 2)

        let thicknesses = flow.branchThicknessesForTest
        XCTAssertEqual(thicknesses[0], VisualEncoding.thickness(27.5), accuracy: 0.001)
        XCTAssertEqual(thicknesses[1], VisualEncoding.thickness(12.2), accuracy: 0.001)
        XCTAssertGreaterThan(thicknesses[0], thicknesses[1])
        XCTAssertEqual(
            PowerFlowView.preferredHeight,
            PowerFlowView.plotHeight + 22 + PopoverStyle.sectionPadding * 2
        )
        XCTAssertEqual(flow.bounds.height, PowerFlowView.preferredHeight)
        XCTAssertEqual(flow.nodeFramesForTest.count, 3)
        XCTAssertTrue(flow.nodeContentsFitForTest)
        let splitFrames = flow.nodeFramesForTest
        XCTAssertTrue(splitFrames.enumerated().allSatisfy { index, frame in
            splitFrames.dropFirst(index + 1).allSatisfy {
                NSIntersectionRect(frame, $0).isEmpty
            }
        })

        show(onBattery(0.1))
        XCTAssertEqual(flow.topologyForTest, "batteryOutputSplit")
        XCTAssertEqual(
            flow.nodePresentationsForTest.map { $0.caption },
            ["Battery 67%", "Device Output", "Mac Load"]
        )
        XCTAssertEqual(
            flow.nodePresentationsForTest.map { $0.value },
            ["39.7 W", "0.1 W", "39.6 W"]
        )
        XCTAssertEqual(
            flow.branchThicknessesForTest[0],
            VisualEncoding.thickness(39.6),
            accuracy: 0.001
        )
        XCTAssertEqual(
            flow.branchThicknessesForTest[1],
            VisualEncoding.thickness(0.1),
            accuracy: 0.001
        )
        XCTAssertTrue(flow.nodeContentsFitForTest)

        for output: Double? in [nil, 0, -.leastNonzeroMagnitude, -1, .nan, .infinity, 39.8, 40.1] {
            show(onBattery(output))
            XCTAssertEqual(flow.topologyForTest, "batteryLed")
            assertNoPluggedDeviceOutputAccessory()
            XCTAssertTrue(flow.nodeContentsFitForTest)
        }
        show(split)
        XCTAssertEqual(flow.topologyForTest, "batteryOutputSplit")
        XCTAssertEqual(flow.nodeFramesForTest, splitFrames)
        XCTAssertTrue(flow.nodeContentsFitForTest)

        let charging = PowerSnapshot(
            percent: 72, plugged: true, adapterW: 68,
            batteryW: 22.2, systemW: 45.8, deviceOutputW: 7.5
        )
        var chargingWithoutDeviceOutput = charging
        chargingWithoutDeviceOutput.deviceOutputW = nil
        show(chargingWithoutDeviceOutput)
        assertNoPluggedDeviceOutputAccessory()
        let chargingBaselineThicknesses = flow.branchThicknessesForTest
        let chargingBaselineNodeFrames = flow.nodeFramesForTest

        show(charging)
        XCTAssertEqual(flow.topologyForTest, "adapterLed")
        XCTAssertEqual(
            flow.nodePresentationsForTest.map { $0.caption },
            ["Adapter", "To Battery", "System Total"]
        )
        XCTAssertEqual(flow.branchThicknessesForTest, chargingBaselineThicknesses)
        XCTAssertEqual(flow.nodeFramesForTest, chargingBaselineNodeFrames)
        assertPluggedDeviceOutputAccessory(7.5)
        XCTAssertEqual(charging.totalInputW, 68, accuracy: 0.001)
        XCTAssertEqual(charging.conservationError, 0, accuracy: 0.001)

        let pluggedIdle = PowerSnapshot(
            percent: 100, plugged: true, adapterW: 52,
            batteryW: 0, systemW: 52, deviceOutputW: 7.5
        )
        var pluggedIdleWithoutDeviceOutput = pluggedIdle
        pluggedIdleWithoutDeviceOutput.deviceOutputW = nil
        show(pluggedIdleWithoutDeviceOutput)
        assertNoPluggedDeviceOutputAccessory()
        let pluggedIdleBaselineThicknesses = flow.branchThicknessesForTest
        let pluggedIdleBaselineNodeFrames = flow.nodeFramesForTest

        show(pluggedIdle)
        XCTAssertEqual(flow.topologyForTest, "adapterLed")
        XCTAssertEqual(
            flow.nodePresentationsForTest.map { $0.caption },
            ["Adapter", "Battery · Full", "System Total"]
        )
        XCTAssertEqual(flow.branchThicknessesForTest, pluggedIdleBaselineThicknesses)
        XCTAssertEqual(flow.nodeFramesForTest, pluggedIdleBaselineNodeFrames)
        assertPluggedDeviceOutputAccessory(7.5)
        XCTAssertEqual(pluggedIdle.totalInputW, 52, accuracy: 0.001)
        XCTAssertEqual(pluggedIdle.conservationError, 0, accuracy: 0.001)

        let mixed = PowerSnapshot(
            percent: 41, plugged: true, adapterW: 30,
            batteryW: -9.7, systemW: 39.7, deviceOutputW: 12.2
        )
        var mixedWithoutDeviceOutput = mixed
        mixedWithoutDeviceOutput.deviceOutputW = nil
        show(mixedWithoutDeviceOutput)
        assertNoPluggedDeviceOutputAccessory()
        let mixedBaselineThicknesses = flow.branchThicknessesForTest
        let mixedBaselineNodeFrames = flow.nodeFramesForTest

        show(mixed)
        XCTAssertEqual(flow.topologyForTest, "batteryLed")
        XCTAssertEqual(
            flow.nodePresentationsForTest.map { $0.caption },
            ["Adapter", "Battery Assist", "System Total"]
        )
        XCTAssertEqual(flow.branchThicknessesForTest, mixedBaselineThicknesses)
        XCTAssertEqual(flow.nodeFramesForTest, mixedBaselineNodeFrames)
        assertPluggedDeviceOutputAccessory(12.2)
        XCTAssertEqual(mixed.totalInputW, 39.7, accuracy: 0.001)
        XCTAssertEqual(mixed.conservationError, 0, accuracy: 0.001)
        XCTAssertTrue(flow.nodeContentsFitForTest)

        for output: Double? in [nil, 0, -.leastNonzeroMagnitude, -1, .nan, .infinity, 45.9] {
            var invalid = charging
            invalid.deviceOutputW = output
            show(invalid)
            XCTAssertEqual(flow.topologyForTest, "adapterLed")
            assertNoPluggedDeviceOutputAccessory()
            XCTAssertEqual(flow.branchThicknessesForTest, chargingBaselineThicknesses)
            XCTAssertEqual(flow.nodeFramesForTest, chargingBaselineNodeFrames)
            XCTAssertEqual(invalid.totalInputW, 68, accuracy: 0.001)
            XCTAssertEqual(invalid.conservationError, 0, accuracy: 0.001)
        }

        var allSystemPowerLeavesThroughDevice = charging
        allSystemPowerLeavesThroughDevice.deviceOutputW = charging.systemW
        show(allSystemPowerLeavesThroughDevice)
        XCTAssertEqual(flow.branchThicknessesForTest, chargingBaselineThicknesses)
        XCTAssertEqual(flow.nodeFramesForTest, chargingBaselineNodeFrames)
        assertPluggedDeviceOutputAccessory(charging.systemW)

        show(onBattery(12.2))
        XCTAssertEqual(flow.topologyForTest, "batteryOutputSplit")
        XCTAssertEqual(deviceOutputFields().count, 1, "on-battery split must not add a duplicate readout")
        XCTAssertEqual(deviceOutputFields().first?.stringValue, "12.2 W")
        XCTAssertEqual(
            deviceOutputPortIconViews().count,
            1,
            "on-battery Device Output must reuse the same port-template icon"
        )
        XCTAssertEqual(visibleIconViews().count, 3)
        XCTAssertEqual(flow.nodePresentationsForTest.count, 3)
        XCTAssertEqual(flow.nodeFramesForTest.count, 3)
        XCTAssertEqual(flow.branchThicknessesForTest.count, 2)
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

    func testReducedMotionUpdatesCreateNoImplicitGeometryAnimations() {
        let content = PopoverContentViewController()
        _ = content.view
        content.view.frame = NSRect(x: 0, y: 0, width: 360, height: 500)
        content.view.layoutSubtreeIfNeeded()
        content.setAnimationsEnabled(false)
        content.update(
            snapshot: PowerSnapshot(
                percent: 52, plugged: true, adapterW: 96, batteryW: 35, systemW: 61
            ),
            history: [20, 96], peak: 96, degraded: false
        )
        CATransaction.flush()
        XCTAssertEqual(
            content.runningModuleAnimationCountForTest, 0,
            content.runningAnimationDescriptionsForTest.joined(separator: "\n")
        )
    }

    func testHiddenModulesSkipUpdatesAndRefreshOnceWhenShown() {
        let suiteName = "Wattson.HiddenModules.Tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        Settings.configureForTest(defaults: defaults)
        defer {
            Settings.resetTestConfiguration()
            defaults.removePersistentDomain(forName: suiteName)
        }

        let content = PopoverContentViewController()
        _ = content.view
        content.setPresentationActive(true)
        for module in PopoverModule.allCases {
            content.setModuleVisibleForTest(module, visible: false)
        }
        let before = content.moduleUpdateCountsForTest
        for value in 1...100 {
            content.update(
                snapshot: PowerSnapshot(
                    percent: 50, plugged: false,
                    batteryW: -Double(value), systemW: Double(value)
                ),
                history: [Double(value)], peak: Double(value), degraded: false
            )
        }
        XCTAssertEqual(content.moduleUpdateCountsForTest, before)

        content.setModuleVisibleForTest(.history, visible: true)
        XCTAssertEqual(
            content.moduleUpdateCountsForTest[.history, default: 0],
            before[.history, default: 0] + 1
        )
        XCTAssertEqual(content.latestHistoryForTest, [100])
    }

    func testSettingsModuleChangeUpdatesLivePopover() {
        let suiteName = "Wattson.LivePopoverSettings.Tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        Settings.configureForTest(defaults: defaults)
        defer {
            Settings.resetTestConfiguration()
            defaults.removePersistentDomain(forName: suiteName)
        }

        let content = PopoverContentViewController()
        _ = content.view
        let initialHeight = content.preferredHeight
        XCTAssertFalse(content.moduleIsHiddenForTest(.flow))

        Settings.setModule(.flow, visible: false)
        spinMainRunLoop(0.05)

        XCTAssertTrue(content.moduleIsHiddenForTest(.flow))
        XCTAssertEqual(
            content.preferredHeight,
            initialHeight - PowerFlowView.preferredHeight,
            accuracy: 0.01
        )
    }

    func testShowingModuleWhilePopoverIsClosedDoesNotRenderIt() {
        let suiteName = "Wattson.ClosedPopoverSettings.Tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        Settings.configureForTest(defaults: defaults)
        defer {
            Settings.resetTestConfiguration()
            defaults.removePersistentDomain(forName: suiteName)
        }

        let content = PopoverContentViewController()
        _ = content.view
        Settings.setModule(.flow, visible: false)
        spinMainRunLoop(0.02)
        let rendersBeforeShowing = content.moduleUpdateCountsForTest[.flow, default: 0]

        Settings.setModule(.flow, visible: true)
        spinMainRunLoop(0.02)

        XCTAssertFalse(content.moduleIsHiddenForTest(.flow))
        XCTAssertEqual(
            content.moduleUpdateCountsForTest[.flow, default: 0],
            rendersBeforeShowing
        )
    }

    func testQuickMenuModuleActionWritesSharedSettings() {
        let suiteName = "Wattson.QuickMenuSettings.Tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        Settings.configureForTest(defaults: defaults)
        defer {
            Settings.resetTestConfiguration()
            defaults.removePersistentDomain(forName: suiteName)
        }

        let content = PopoverContentViewController()
        _ = content.view
        XCTAssertTrue(Settings.isModuleVisible(.ring))

        content.toggleModuleFromMenuForTest(.ring)

        XCTAssertFalse(Settings.isModuleVisible(.ring))
        XCTAssertTrue(content.moduleIsHiddenForTest(.ring))
    }

    func testPopoverSettingsRelayDefersPresenterToNextMainTurn() {
        let popover = PopoverController()
        var presented = false
        popover.setSettingsHandler { presented = true }

        popover.presentSettingsFromQuickMenuForTest()

        XCTAssertFalse(presented)
        spinMainRunLoop(0.05)
        XCTAssertTrue(presented)
        XCTAssertFalse(popover.isOpen)
        XCTAssertFalse(popover.isWatchingOutsideClicks)
    }

    func testClosedPopoverCachesSystemBatteryIconStateWithoutFooterWork() {
        let popover = PopoverController()
        let before = popover.footerUpdateCountForTest
        popover.updateSystemBatteryIconState(true)
        XCTAssertEqual(popover.footerUpdateCountForTest, before)
        XCTAssertEqual(popover.cachedSystemBatteryIconStateForTest, true)
    }

    func testRepeatedReadOperationsCollapseToOnePendingRead() {
        let operations = CoalescingReadOperationQueue<Int>(
            label: "com.leoarrow.wattson.tests.coalesced-reads"
        )
        let firstStarted = expectation(description: "first read started")
        let latestCompleted = expectation(description: "latest read completed")
        let releaseFirst = DispatchSemaphore(value: 0)
        let stateLock = NSLock()
        var executedValues: [Int] = []
        var completedValues: [Int] = []

        func enqueue(_ value: Int) {
            operations.enqueueRead(
                operation: {
                    stateLock.lock()
                    executedValues.append(value)
                    stateLock.unlock()
                    if value == 1 {
                        firstStarted.fulfill()
                        releaseFirst.wait()
                    }
                    return value
                },
                completion: { result in
                    stateLock.lock()
                    completedValues.append(result)
                    stateLock.unlock()
                    if result == 10_000 { latestCompleted.fulfill() }
                }
            )
        }

        enqueue(1)
        wait(for: [firstStarted], timeout: 1)
        for value in 2...10_000 { enqueue(value) }
        releaseFirst.signal()
        wait(for: [latestCompleted], timeout: 1)

        stateLock.lock()
        let executed = executedValues
        let completed = completedValues
        stateLock.unlock()
        XCTAssertEqual(executed, [1, 10_000])
        XCTAssertEqual(completed, [1, 10_000])
    }

    func testMutationDiscardsStalePendingReadsAndWaitsForOnlyCurrentRead() {
        let operations = CoalescingReadOperationQueue<Int>(
            label: "com.leoarrow.wattson.tests.mutation-priority"
        )
        let firstStarted = expectation(description: "first read started")
        let mutationStarted = expectation(description: "mutation started")
        let latestCompleted = expectation(description: "latest read completed")
        let releaseFirst = DispatchSemaphore(value: 0)
        let stateLock = NSLock()
        var executionOrder: [String] = []

        func record(_ value: String) {
            stateLock.lock()
            executionOrder.append(value)
            stateLock.unlock()
        }

        operations.enqueueRead(
            operation: {
                record("read-current")
                firstStarted.fulfill()
                releaseFirst.wait()
                return 1
            },
            completion: { _ in }
        )
        wait(for: [firstStarted], timeout: 1)

        for value in 2...10_000 {
            operations.enqueueRead(
                operation: {
                    record("stale-\(value)")
                    return value
                },
                completion: { _ in }
            )
        }
        operations.enqueueMutation(
            operation: {
                record("mutation")
                mutationStarted.fulfill()
                return true
            },
            completion: { _ in }
        )
        operations.enqueueRead(
            operation: {
                record("read-latest")
                return 10_001
            },
            completion: { value in
                XCTAssertEqual(value, 10_001)
                latestCompleted.fulfill()
            }
        )

        releaseFirst.signal()
        wait(for: [mutationStarted, latestCompleted], timeout: 1)
        stateLock.lock()
        let observedOrder = executionOrder
        stateLock.unlock()
        XCTAssertEqual(observedOrder, ["read-current", "mutation", "read-latest"])
    }

    func testMutationsStaySerializedAndCompletionsRunOnMainThread() {
        let operations = CoalescingReadOperationQueue<Int>(
            label: "com.leoarrow.wattson.tests.serial-mutations"
        )
        let firstStarted = expectation(description: "first mutation started")
        let firstCompleted = expectation(description: "first mutation completed")
        let secondCompleted = expectation(description: "second mutation completed")
        let releaseFirst = DispatchSemaphore(value: 0)
        let stateLock = NSLock()
        var executionOrder: [Int] = []

        operations.enqueueMutation(
            operation: {
                stateLock.lock()
                executionOrder.append(1)
                stateLock.unlock()
                firstStarted.fulfill()
                releaseFirst.wait()
                return 1
            },
            completion: { value in
                XCTAssertTrue(Thread.isMainThread)
                XCTAssertEqual(value, 1)
                firstCompleted.fulfill()
            }
        )
        wait(for: [firstStarted], timeout: 1)
        operations.enqueueMutation(
            operation: {
                stateLock.lock()
                executionOrder.append(2)
                stateLock.unlock()
                return 2
            },
            completion: { value in
                XCTAssertTrue(Thread.isMainThread)
                XCTAssertEqual(value, 2)
                secondCompleted.fulfill()
            }
        )

        stateLock.lock()
        let beforeRelease = executionOrder
        stateLock.unlock()
        XCTAssertEqual(beforeRelease, [1])
        releaseFirst.signal()
        wait(for: [firstCompleted, secondCompleted], timeout: 1)
        stateLock.lock()
        let afterCompletion = executionOrder
        stateLock.unlock()
        XCTAssertEqual(afterCompletion, [1, 2])
    }

    func testIndependentControllersShareOneHelperSettingsWorker() {
        let worker = SerialOperationWorker(
            label: "com.leoarrow.wattson.tests.shared-settings-worker"
        )
        let loginOperations = CoalescingReadOperationQueue<Int>(
            label: "com.leoarrow.wattson.tests.login-operations",
            worker: worker
        )
        let iconOperations = CoalescingReadOperationQueue<Int>(
            label: "com.leoarrow.wattson.tests.icon-operations",
            worker: worker
        )
        let loginStarted = expectation(description: "slow login operation started")
        let iconCompleted = expectation(description: "icon mutation completed")
        let releaseLogin = DispatchSemaphore(value: 0)
        let stateLock = NSLock()
        var iconStartedBeforeLoginFinished = false
        var loginFinished = false

        loginOperations.enqueueRead(
            operation: {
                loginStarted.fulfill()
                releaseLogin.wait()
                stateLock.lock()
                loginFinished = true
                stateLock.unlock()
                return 1
            },
            completion: { _ in }
        )
        wait(for: [loginStarted], timeout: 1)

        iconOperations.enqueueMutation(
            operation: {
                stateLock.lock()
                iconStartedBeforeLoginFinished = !loginFinished
                stateLock.unlock()
                return true
            },
            completion: { _ in iconCompleted.fulfill() }
        )
        spinMainRunLoop(0.05)
        stateLock.lock()
        let startedTooSoon = iconStartedBeforeLoginFinished
        stateLock.unlock()
        XCTAssertFalse(startedTooSoon)

        releaseLogin.signal()
        wait(for: [iconCompleted], timeout: 1)
        stateLock.lock()
        let overlapped = iconStartedBeforeLoginFinished
        stateLock.unlock()
        XCTAssertFalse(overlapped)
    }

    func testMutationCanCancelPendingReadUntilSharedWorkerSelectsIt() {
        let worker = SerialOperationWorker(
            label: "com.leoarrow.wattson.tests.cancel-before-selection"
        )
        let operations = CoalescingReadOperationQueue<Int>(
            label: "com.leoarrow.wattson.tests.handoff-race",
            worker: worker
        )
        let firstStarted = expectation(description: "first read started")
        let blockerStarted = expectation(description: "foreign worker task started")
        let mutationCompleted = expectation(description: "mutation completed")
        let releaseFirst = DispatchSemaphore(value: 0)
        let releaseBlocker = DispatchSemaphore(value: 0)
        let stateLock = NSLock()
        var pendingReadExecutions = 0

        operations.enqueueRead(
            operation: {
                firstStarted.fulfill()
                releaseFirst.wait()
                return 1
            },
            completion: { _ in }
        )
        wait(for: [firstStarted], timeout: 1)
        operations.enqueueRead(
            operation: {
                stateLock.lock()
                pendingReadExecutions += 1
                stateLock.unlock()
                return 2
            },
            completion: { _ in }
        )
        worker.async {
            blockerStarted.fulfill()
            releaseBlocker.wait()
        }
        releaseFirst.signal()
        wait(for: [blockerStarted], timeout: 1)

        operations.enqueueMutation(
            operation: { true },
            completion: { _ in mutationCompleted.fulfill() }
        )
        releaseBlocker.signal()
        wait(for: [mutationCompleted], timeout: 1)
        stateLock.lock()
        let executions = pendingReadExecutions
        stateLock.unlock()
        XCTAssertEqual(executions, 0)
    }

    func testExplicitCancellationDropsOnlyThePendingRead() {
        let worker = SerialOperationWorker(
            label: "com.leoarrow.wattson.tests.explicit-read-cancellation"
        )
        let operations = CoalescingReadOperationQueue<Int>(
            label: "com.leoarrow.wattson.tests.cancel-pending-read",
            worker: worker
        )
        let firstStarted = expectation(description: "current read started")
        let firstCompleted = expectation(description: "current read completed")
        let releaseFirst = DispatchSemaphore(value: 0)
        let stateLock = NSLock()
        var pendingExecutions = 0

        operations.enqueueRead(
            operation: {
                firstStarted.fulfill()
                releaseFirst.wait()
                return 1
            },
            completion: { value in
                XCTAssertEqual(value, 1)
                firstCompleted.fulfill()
            }
        )
        wait(for: [firstStarted], timeout: 1)
        operations.enqueueRead(
            operation: {
                stateLock.lock()
                pendingExecutions += 1
                stateLock.unlock()
                return 2
            },
            completion: { _ in XCTFail("cancelled read completed") }
        )

        operations.cancelPendingRead()
        releaseFirst.signal()
        wait(for: [firstCompleted], timeout: 1)
        spinMainRunLoop(0.02)
        stateLock.lock()
        let executions = pendingExecutions
        stateLock.unlock()
        XCTAssertEqual(executions, 0)
    }

    func testSynchronousMutationIsReentrantOnSharedWorker() {
        let worker = SerialOperationWorker(
            label: "com.leoarrow.wattson.tests.reentrant-mutation"
        )
        let operations = CoalescingReadOperationQueue<Int>(
            label: "com.leoarrow.wattson.tests.reentrant-operations",
            worker: worker
        )
        let completed = expectation(description: "reentrant mutation returned")
        worker.async {
            let value: Int = operations.performMutation { 42 }
            XCTAssertEqual(value, 42)
            completed.fulfill()
        }
        wait(for: [completed], timeout: 1)
    }

    func testLoginItemRejectsRepeatedSetWhileUpdateIsInFlightAndRestoresReadback() {
        let setStarted = expectation(description: "set started")
        let firstCompleted = expectation(description: "first set completed")
        let repeatedCompleted = expectation(description: "repeated sets completed")
        repeatedCompleted.expectedFulfillmentCount = 9_999
        let releaseSet = DispatchSemaphore(value: 0)
        let stateLock = NSLock()
        var setCalls = 0

        LoginItemController.configureForTest(
            available: true,
            initialState: .enabled,
            send: { request, _ in
                switch request["op"] as? String {
                case "setLaunchAtLoginEnabled":
                    stateLock.lock()
                    setCalls += 1
                    stateLock.unlock()
                    setStarted.fulfill()
                    releaseSet.wait()
                    return ["ok": false, "error": "login item update failed"]
                case "getLaunchAtLoginEnabled":
                    return ["ok": true, "enabled": true]
                default:
                    return nil
                }
            }
        )
        defer { LoginItemController.resetTestConfiguration() }

        LoginItemController.setEnabled(false) { result in
            guard case .failure = result else {
                XCTFail("failed write must report failure")
                return
            }
            firstCompleted.fulfill()
        }
        XCTAssertEqual(LoginItemController.state, .checking)
        wait(for: [setStarted], timeout: 1)

        for index in 2...10_000 {
            LoginItemController.setEnabled(index.isMultiple(of: 2)) { result in
                guard case let .failure(error) = result,
                      case LoginItemError.updateInProgress = error else {
                    XCTFail("repeated write must fail immediately as in progress")
                    return
                }
                repeatedCompleted.fulfill()
            }
        }
        wait(for: [repeatedCompleted], timeout: 1)
        releaseSet.signal()
        wait(for: [firstCompleted], timeout: 1)

        XCTAssertEqual(LoginItemController.state, .enabled)
        stateLock.lock()
        let observedSetCalls = setCalls
        stateLock.unlock()
        XCTAssertEqual(observedSetCalls, 1)
    }

    func testResettingLoginItemTestConfigurationWaitsForInFlightRead() {
        let readStarted = expectation(description: "login-item read started")
        let readFinished = expectation(description: "login-item read finished")
        let releaseRead = DispatchSemaphore(value: 0)
        let stateLock = NSLock()
        var finished = false

        LoginItemController.configureForTest(
            available: true,
            initialState: .enabled,
            send: { request, _ in
                XCTAssertEqual(request["op"] as? String, "getLaunchAtLoginEnabled")
                readStarted.fulfill()
                releaseRead.wait()
                stateLock.lock()
                finished = true
                stateLock.unlock()
                readFinished.fulfill()
                return ["ok": true, "enabled": true]
            }
        )

        LoginItemController.refresh()
        wait(for: [readStarted], timeout: 1)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
            releaseRead.signal()
        }

        LoginItemController.resetTestConfiguration()
        stateLock.lock()
        let resetReturnedAfterRead = finished
        stateLock.unlock()
        wait(for: [readFinished], timeout: 1)
        XCTAssertTrue(resetReturnedAfterRead)
    }

    func testAvailableRefreshDuringLoginItemSetDoesNotInvalidateTheWrite() {
        let setStarted = expectation(description: "set started")
        let setCompleted = expectation(description: "set completed")
        let refreshCompleted = expectation(description: "refresh completed")
        let releaseSet = DispatchSemaphore(value: 0)

        LoginItemController.configureForTest(
            available: true,
            initialState: .enabled,
            send: { request, _ in
                guard request["op"] as? String == "setLaunchAtLoginEnabled" else {
                    XCTFail("refresh during a write must not start another helper read")
                    return nil
                }
                setStarted.fulfill()
                releaseSet.wait()
                return ["ok": true, "enabled": false]
            }
        )
        defer { LoginItemController.resetTestConfiguration() }

        LoginItemController.setEnabled(false) { result in
            guard case let .success(state) = result else {
                XCTFail("write should still complete successfully")
                return
            }
            XCTAssertEqual(state, .notRegistered)
            setCompleted.fulfill()
        }
        wait(for: [setStarted], timeout: 1)
        LoginItemController.refresh { state in
            XCTAssertEqual(state, .notRegistered)
            refreshCompleted.fulfill()
        }
        releaseSet.signal()
        wait(for: [setCompleted, refreshCompleted], timeout: 1)
        XCTAssertEqual(LoginItemController.state, .notRegistered)
    }

    func testSupersededLoginItemRefreshStillCompletesEveryWaitingCaller() {
        let firstReadStarted = expectation(description: "first login-item read started")
        let waitingCallerCompleted = expectation(
            description: "superseded login-item refresh caller completed"
        )
        let releaseFirstRead = DispatchSemaphore(value: 0)
        let stateLock = NSLock()
        var readCount = 0

        LoginItemController.configureForTest(
            available: true,
            initialState: .enabled,
            send: { request, _ in
                XCTAssertEqual(request["op"] as? String, "getLaunchAtLoginEnabled")
                stateLock.lock()
                readCount += 1
                let currentRead = readCount
                stateLock.unlock()
                if currentRead == 1 {
                    firstReadStarted.fulfill()
                    releaseFirstRead.wait()
                    return ["ok": true, "enabled": true]
                }
                return ["ok": true, "enabled": false]
            }
        )
        defer { LoginItemController.resetTestConfiguration() }

        LoginItemController.refresh { state in
            XCTAssertEqual(state, .notRegistered)
            waitingCallerCompleted.fulfill()
        }
        wait(for: [firstReadStarted], timeout: 1)

        // Popover/status refreshes intentionally have no completion. They may
        // supersede helper I/O, but must not strand a Settings caller waiting
        // for the latest authoritative state.
        LoginItemController.refresh()
        releaseFirstRead.signal()

        wait(for: [waitingCallerCompleted], timeout: 1)
        XCTAssertEqual(LoginItemController.state, .notRegistered)
        stateLock.lock()
        let observedReadCount = readCount
        stateLock.unlock()
        XCTAssertEqual(observedReadCount, 2)
    }

    func testRecoveredAvailabilityRefreshSurvivesAStaleInFlightSet() {
        let setStarted = expectation(description: "login-item set started")
        let setCompleted = expectation(description: "stale login-item set completed")
        let unavailableCompleted = expectation(description: "unavailable refresh completed")
        let recoveredCompleted = expectation(description: "recovered refresh completed")
        let releaseSet = DispatchSemaphore(value: 0)

        LoginItemController.configureForTest(
            available: true,
            initialState: .enabled,
            send: { request, _ in
                switch request["op"] as? String {
                case "setLaunchAtLoginEnabled":
                    setStarted.fulfill()
                    releaseSet.wait()
                    return ["ok": true, "enabled": false]
                case "getLaunchAtLoginEnabled":
                    return ["ok": true, "enabled": false]
                default:
                    XCTFail("unexpected login-item helper operation")
                    return nil
                }
            }
        )
        defer { LoginItemController.resetTestConfiguration() }

        LoginItemController.setEnabled(false) { result in
            guard case .success = result else {
                XCTFail("the stale helper mutation still returns its own result")
                return
            }
            setCompleted.fulfill()
        }
        wait(for: [setStarted], timeout: 1)

        LoginItemController.setAvailabilityForTest(false)
        LoginItemController.refresh { state in
            XCTAssertEqual(state, .unavailable)
            unavailableCompleted.fulfill()
        }
        wait(for: [unavailableCompleted], timeout: 1)

        LoginItemController.setAvailabilityForTest(true)
        LoginItemController.refresh { state in
            XCTAssertEqual(state, .notRegistered)
            recoveredCompleted.fulfill()
        }
        releaseSet.signal()

        wait(for: [setCompleted, recoveredCompleted], timeout: 1)
        XCTAssertEqual(LoginItemController.state, .notRegistered)
    }

    func testFailedLoginItemSetCompletesBeforeCoalescedReadbackStarts() {
        let setCompleted = expectation(description: "failed set completed")
        let readbackStarted = expectation(description: "follow-up read started")
        let readbackCompleted = expectation(description: "follow-up read completed")
        let releaseReadback = DispatchSemaphore(value: 0)
        let stateLock = NSLock()
        var operationsAtSetCompletion: [String] = []
        var observedOperations: [String] = []
        var readbackHasStarted = false

        LoginItemController.configureForTest(
            available: true,
            initialState: .enabled,
            send: { request, _ in
                let operation = request["op"] as? String ?? "unknown"
                stateLock.lock()
                observedOperations.append(operation)
                let isFirstReadback = operation == "getLaunchAtLoginEnabled"
                    && !readbackHasStarted
                if isFirstReadback { readbackHasStarted = true }
                stateLock.unlock()
                if operation == "getLaunchAtLoginEnabled" {
                    if isFirstReadback {
                        readbackStarted.fulfill()
                        releaseReadback.wait()
                    }
                    return ["ok": true, "enabled": true]
                }
                return nil
            }
        )
        defer { LoginItemController.resetTestConfiguration() }

        LoginItemController.setEnabled(false) { result in
            guard case .failure = result else {
                XCTFail("nil write reply must fail")
                return
            }
            XCTAssertEqual(LoginItemController.state, .enabled)
            stateLock.lock()
            operationsAtSetCompletion = observedOperations
            stateLock.unlock()
            setCompleted.fulfill()
        }
        wait(for: [setCompleted], timeout: 1)
        XCTAssertEqual(operationsAtSetCompletion, ["setLaunchAtLoginEnabled"])

        wait(for: [readbackStarted], timeout: 1)
        releaseReadback.signal()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            LoginItemController.refresh { state in
                XCTAssertEqual(state, .enabled)
                readbackCompleted.fulfill()
            }
        }
        wait(for: [readbackCompleted], timeout: 1)
        stateLock.lock()
        let finalOperations = observedOperations
        stateLock.unlock()
        XCTAssertEqual(finalOperations.first, "setLaunchAtLoginEnabled")
        XCTAssertEqual(
            finalOperations.filter { $0 == "getLaunchAtLoginEnabled" }.count,
            2
        )
    }

    func testFailedLoginItemSetKeepsRefreshWaitersForAuthoritativeReadback() {
        let setStarted = expectation(description: "login-item set started")
        let setCompleted = expectation(description: "failed set completed")
        let readbackStarted = expectation(description: "authoritative readback started")
        let refreshCompleted = expectation(description: "waiting refresh completed")
        let releaseSet = DispatchSemaphore(value: 0)
        let releaseReadback = DispatchSemaphore(value: 0)
        let stateLock = NSLock()
        var waiterDidComplete = false

        LoginItemController.configureForTest(
            available: true,
            initialState: .enabled,
            send: { request, _ in
                switch request["op"] as? String {
                case "setLaunchAtLoginEnabled":
                    setStarted.fulfill()
                    releaseSet.wait()
                    return nil
                case "getLaunchAtLoginEnabled":
                    readbackStarted.fulfill()
                    releaseReadback.wait()
                    return ["ok": true, "enabled": false]
                default:
                    XCTFail("unexpected login-item helper operation")
                    return nil
                }
            }
        )
        defer { LoginItemController.resetTestConfiguration() }

        LoginItemController.setEnabled(false) { result in
            guard case .failure = result else {
                XCTFail("nil write reply must fail")
                return
            }
            setCompleted.fulfill()
        }
        wait(for: [setStarted], timeout: 1)

        LoginItemController.refresh { state in
            XCTAssertEqual(state, .notRegistered)
            stateLock.lock()
            waiterDidComplete = true
            stateLock.unlock()
            refreshCompleted.fulfill()
        }
        releaseSet.signal()

        wait(for: [setCompleted, readbackStarted], timeout: 1)
        stateLock.lock()
        let completedBeforeReadback = waiterDidComplete
        stateLock.unlock()
        XCTAssertFalse(
            completedBeforeReadback,
            "a restoration value must not settle an authoritative refresh waiter"
        )

        releaseReadback.signal()
        wait(for: [refreshCompleted], timeout: 1)
        XCTAssertEqual(LoginItemController.state, .notRegistered)
    }

    func testUnavailableRefreshInvalidatesOlderLoginItemCompletion() {
        let readStarted = expectation(description: "old read started")
        let unavailableCompleted = expectation(description: "unavailable refresh completed")
        let olderCallerCompleted = expectation(description: "older refresh caller completed")
        let releaseRead = DispatchSemaphore(value: 0)

        LoginItemController.configureForTest(
            available: true,
            initialState: .notRegistered,
            send: { _, _ in
                readStarted.fulfill()
                releaseRead.wait()
                return ["ok": true, "enabled": true]
            }
        )
        defer { LoginItemController.resetTestConfiguration() }

        LoginItemController.refresh { state in
            XCTAssertEqual(state, .unavailable)
            olderCallerCompleted.fulfill()
        }
        wait(for: [readStarted], timeout: 1)
        LoginItemController.setAvailabilityForTest(false)
        LoginItemController.refresh { state in
            XCTAssertEqual(state, .unavailable)
            unavailableCompleted.fulfill()
        }
        wait(for: [olderCallerCompleted, unavailableCompleted], timeout: 1)
        releaseRead.signal()
        spinMainRunLoop(0.02)
        XCTAssertEqual(LoginItemController.state, .unavailable)
    }

    func testUnavailableRefreshCannotBeOverwrittenByInFlightLoginItemSet() {
        let setStarted = expectation(description: "set started")
        let unavailableCompleted = expectation(description: "unavailable refresh completed")
        let setCompleted = expectation(description: "stale set completed")
        let releaseSet = DispatchSemaphore(value: 0)

        LoginItemController.configureForTest(
            available: true,
            initialState: .enabled,
            send: { request, _ in
                XCTAssertEqual(
                    request["op"] as? String,
                    "setLaunchAtLoginEnabled"
                )
                setStarted.fulfill()
                releaseSet.wait()
                return ["ok": true, "enabled": false]
            }
        )
        defer { LoginItemController.resetTestConfiguration() }

        LoginItemController.setEnabled(false) { result in
            guard case .success(.notRegistered) = result else {
                XCTFail("the completed command still reports its own result")
                return
            }
            setCompleted.fulfill()
        }
        wait(for: [setStarted], timeout: 1)
        LoginItemController.setAvailabilityForTest(false)
        LoginItemController.refresh { state in
            XCTAssertEqual(state, .unavailable)
            unavailableCompleted.fulfill()
        }
        wait(for: [unavailableCompleted], timeout: 1)
        releaseSet.signal()
        wait(for: [setCompleted], timeout: 1)
        XCTAssertEqual(LoginItemController.state, .unavailable)
    }
}
