import AppKit
import XCTest
@testable import Wattson

final class ModeSliderAppearanceTests: XCTestCase {
    private final class FlippedDocumentView: NSView {
        override var isFlipped: Bool { true }
    }

    private func withTransparencyReduced(_ reduced: Bool, _ body: () throws -> Void) rethrows {
        let key = "WATTSON_FORCE_REDUCE_TRANSPARENCY"
        let prior = ProcessInfo.processInfo.environment[key]
        setenv(key, reduced ? "1" : "0", 1)
        defer {
            if let prior { setenv(key, prior, 1) }
            else { unsetenv(key) }
        }
        try body()
    }

    private func makeSlider(legacy: Bool = true) -> ModeSliderView {
        _ = NSApplication.shared
        let slider = ModeSliderView(modes: [.auto, .low, .high],
                                    forceLegacyMaterialsForTest: legacy)
        slider.update(selected: .auto, enabledModes: [.auto, .low, .high], tint: .systemBlue)
        return slider
    }

    private func apply(_ name: NSAppearance.Name, to slider: ModeSliderView) {
        slider.appearance = NSAppearance(named: name)!
        // An unattached view does not receive every display-driven callback.
        slider.viewDidChangeEffectiveAppearance()
    }

    private func rgb(_ color: CGColor?) throws -> NSColor {
        let color = try XCTUnwrap(color)
        return try XCTUnwrap(NSColor(cgColor: color)?.usingColorSpace(.deviceRGB))
    }

    private func resolved(_ color: NSColor, in appearance: NSAppearance) -> CGColor {
        var result = NSColor.clear.cgColor
        appearance.performAsCurrentDrawingAppearance { result = color.cgColor }
        return result
    }

    func testFallbackLayersAndBlendedLabelsUseTheViewsAppearanceNotGlobalDrawingAppearance() throws {
        try withTransparencyReduced(false) {
            let slider = makeSlider()
            NSAppearance(named: .darkAqua)!.performAsCurrentDrawingAppearance {
                apply(.aqua, to: slider)
            }
            let lightFill = try rgb(slider.trackFillForTest)
            let expectedLight = try rgb(resolved(PopoverStyle.well, in: slider.effectiveAppearance))
            XCTAssertEqual(lightFill.redComponent, expectedLight.redComponent, accuracy: 0.001)
            XCTAssertGreaterThan(lightFill.redComponent, 0.5)
            XCTAssertEqual(try rgb(slider.selectorFillForTest).redComponent, 0, accuracy: 0.001)
            let lightLabel = try XCTUnwrap(slider.activeLabelColorForTest?.usingColorSpace(.deviceRGB))

            NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance {
                apply(.darkAqua, to: slider)
            }
            let darkFill = try rgb(slider.trackFillForTest)
            let expectedDark = try rgb(resolved(PopoverStyle.well, in: slider.effectiveAppearance))
            XCTAssertEqual(darkFill.redComponent, expectedDark.redComponent, accuracy: 0.001)
            XCTAssertLessThan(darkFill.redComponent, 0.5)
            XCTAssertEqual(try rgb(slider.selectorFillForTest).redComponent, 1, accuracy: 0.001)
            let darkLabel = try XCTUnwrap(slider.activeLabelColorForTest?.usingColorSpace(.deviceRGB))
            XCTAssertLessThan(lightLabel.blueComponent, darkLabel.blueComponent)
            XCTAssertEqual(slider.fallbackSelectorOpacityForTest ?? -1, 0.105, accuracy: 0.001)
        }
    }

    func testOpaqueSelectorsFollowLightAndDarkWithoutReintroducingNativeChrome() throws {
        try withTransparencyReduced(true) {
            for legacy in [true, false] {
                let slider = makeSlider(legacy: legacy)
                apply(.aqua, to: slider)
                let light = try rgb(slider.selectorFillForTest)
                XCTAssertGreaterThan(light.redComponent, 0.8)
                XCTAssertEqual(light.alphaComponent, 1)
                apply(.darkAqua, to: slider)
                let dark = try rgb(slider.selectorFillForTest)
                XCTAssertLessThan(dark.redComponent, 0.3)
                XCTAssertEqual(dark.alphaComponent, 1)
                if !legacy, #available(macOS 26.0, *) {
                    XCTAssertEqual(slider.nativeSelectorContentFillAlphaForTest, 1)
                    XCTAssertEqual(slider.nativeSelectorBorderWidthForTest, 0)
                    XCTAssertFalse(slider.nativeSelectorHasCustomChromeForTest)
                }
            }
        }
    }

    func testHighContrastKeepsTheSelectionEdgeVisibleInBothAppearances() {
        let key = "WATTSON_FORCE_INCREASE_CONTRAST"
        let prior = ProcessInfo.processInfo.environment[key]
        defer {
            if let prior { setenv(key, prior, 1) }
            else { unsetenv(key) }
        }
        withTransparencyReduced(false) {
            for legacy in [true, false] {
                setenv(key, "0", 1)
                let slider = makeSlider(legacy: legacy)
                for name: NSAppearance.Name in [.aqua, .darkAqua] {
                    apply(name, to: slider)
                    let normalWidth = slider.fallbackLensRimWidthForTest
                    let normalOpacity = slider.nativeSelectorOpacityForTest

                    // Named high-contrast appearances can resolve to plain Aqua
                    // unless the user's preference is enabled. Inject only the
                    // DEBUG flag and exercise the production notification path.
                    setenv(key, "1", 1)
                    NSWorkspace.shared.notificationCenter.post(
                        name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                        object: NSWorkspace.shared
                    )
                    if let normalWidth {
                        XCTAssertGreaterThan(slider.fallbackLensRimWidthForTest ?? 0, normalWidth)
                    } else {
                        XCTAssertNotNil(normalOpacity)
                        XCTAssertEqual(slider.nativeSelectorOpacityForTest, 1)
                        XCTAssertEqual(slider.nativeSelectorFillAlphaForTest, 0)
                    }

                    setenv(key, "0", 1)
                    NSWorkspace.shared.notificationCenter.post(
                        name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                        object: NSWorkspace.shared
                    )
                    XCTAssertEqual(slider.fallbackLensRimWidthForTest, normalWidth)
                    XCTAssertEqual(slider.nativeSelectorOpacityForTest, normalOpacity)
                }
            }
        }
    }

    func testAppearanceChangeDropsPreviouslySampledPixelsBeforeRecapture() throws {
        try withTransparencyReduced(false) {
            let slider = makeSlider()
            apply(.darkAqua, to: slider)
            let context = try XCTUnwrap(CGContext(data: nil, width: 4, height: 4,
                bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            slider.installOpticalSnapshotForTest(try XCTUnwrap(context.makeImage()))
            XCTAssertNotNil(slider.fallbackLensSampleImageForTest)
            XCTAssertFalse(slider.opticalSnapshotDirtyForTest)

            apply(.aqua, to: slider)
            XCTAssertNil(slider.fallbackLensSampleImageForTest)
            XCTAssertTrue(slider.opticalSnapshotDirtyForTest)
            XCTAssertEqual(slider.fallbackLensSamplingEnabledForTest, false)
        }
    }

    func testKeyboardFocusUsesOnlyALocalMarkerAndClearsOnResign() {
        let slider = makeSlider()
        XCTAssertEqual(slider.focusRingTypeForTest, .none)
        XCTAssertFalse(slider.keyboardFocusMarkerVisibleForTest)
        XCTAssertTrue(slider.becomeFirstResponder())
        XCTAssertTrue(slider.keyboardFocusMarkerVisibleForTest)
        XCTAssertTrue(slider.resignFirstResponder())
        XCTAssertFalse(slider.keyboardFocusMarkerVisibleForTest)
    }

    func testKeyboardFocusScrollsTheWholeSliderIntoAShortViewport() {
        let slider = makeSlider()
        slider.frame = NSRect(x: 0, y: 400, width: 300, height: ModeSliderView.preferredHeight)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 320, height: 100))
        let document = FlippedDocumentView(frame: NSRect(x: 0, y: 0, width: 320, height: 450))
        scroll.documentView = document
        document.addSubview(slider)
        let window = NSWindow(contentRect: scroll.frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.contentView = scroll
        window.contentView?.layoutSubtreeIfNeeded()
        scroll.contentView.scroll(to: .zero)
        XCTAssertFalse(scroll.documentVisibleRect.intersects(slider.frame))

        XCTAssertTrue(window.makeFirstResponder(slider))
        XCTAssertTrue(window.firstResponder === slider)
        XCTAssertTrue(scroll.documentVisibleRect.contains(slider.frame))
        XCTAssertTrue(slider.keyboardFocusMarkerVisibleForTest)
        XCTAssertEqual(slider.selectedIndexForTest, 0)
        XCTAssertFalse(slider.settleIsAnimatingForTest)
    }
}
