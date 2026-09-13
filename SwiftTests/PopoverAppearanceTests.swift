import AppKit
import XCTest
@testable import Wattson

final class PopoverAppearanceTests: XCTestCase {
    func testGlassPreferencePreservesSystemAppearanceWithoutRebuildingClosedContent() throws {
        _ = NSApplication.shared
        let suite = "Wattson.PopoverAppearance.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        Settings.configureForTest(defaults: defaults)
        defer {
            Settings.resetTestConfiguration()
            defaults.removePersistentDomain(forName: suite)
        }
        let controller = PopoverController()
        let root = try XCTUnwrap(controller.contentViewForTest)
        let frame = root.frame
        let window = controller.contentWindowForTest
        var modeRequests = 0
        var batteryRequests = 0
        controller.setModeSelectHandler { _, _ in modeRequests += 1 }
        controller.setSystemBatteryIconToggleHandler { _, _ in batteryRequests += 1 }
        controller.update(snapshot: PowerSnapshot(percent: 72, plugged: true,
            adapterW: 60, batteryW: 20, systemW: 40), history: [32, 40], peak: 40,
            degraded: false)
        XCTAssertNil(controller.popoverAppearanceForTest)
        for enabled in [true, false, true, false] {
            Settings.liquidGlassEnabled = enabled
            XCTAssertNil(controller.popoverAppearanceForTest)
            XCTAssertNil(controller.classicPopoverForTest.appearance)
            XCTAssertTrue(controller.contentViewForTest === root)
            XCTAssertTrue(controller.contentWindowForTest === window)
            XCTAssertEqual(root.frame, frame)
            XCTAssertEqual(controller.cachedPercentForTest, 72)
            XCTAssertFalse(controller.isOpen)
            XCTAssertFalse(controller.isShownForTest)
            XCTAssertFalse(controller.isWatchingOutsideClicks)
            XCTAssertEqual(controller.contentRenderCountForTest, 0)
            XCTAssertEqual(modeRequests, 0)
            XCTAssertEqual(batteryRequests, 0)
        }
        Settings.liquidGlassEnabled = true
        let existingAppearance = controller.popoverAppearanceForTest
        Settings.showsMenuBarPercentage.toggle()
        XCTAssertTrue(controller.popoverAppearanceForTest === existingAppearance)
        XCTAssertTrue(controller.contentViewForTest === root)
        XCTAssertEqual(modeRequests + batteryRequests, 0)
    }

    func testGlassPopoverInitialAppearanceAndObserverLifetime() throws {
        _ = NSApplication.shared
        let suite = "Wattson.PopoverAppearanceLifetime.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        Settings.configureForTest(defaults: defaults)
        defer {
            Settings.resetTestConfiguration()
            defaults.removePersistentDomain(forName: suite)
        }
        Settings.liquidGlassEnabled = true
        weak var releasedController: PopoverController?
        autoreleasepool {
            let controller = PopoverController()
            releasedController = controller
            XCTAssertNil(controller.popoverAppearanceForTest)
            if #unavailable(macOS 26) {
                XCTAssertFalse(Settings.usesLiquidGlass)
            }
            XCTAssertFalse(controller.isOpen)
        }
        XCTAssertNil(releasedController)
        Settings.liquidGlassEnabled = false
        Settings.liquidGlassEnabled = true
        XCTAssertNil(releasedController)
    }

    private func resolved(_ color: NSColor, _ appearance: NSAppearance) -> NSColor {
        var result = color
        appearance.performAsCurrentDrawingAppearance {
            result = color.usingColorSpace(.sRGB) ?? color
        }
        return result
    }

    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }

    func testPanelInheritsAppearanceAndKeepsNativePopoverSurfaceUncovered() throws {
        _ = NSApplication.shared
        let content = PopoverContentViewController()
        content.setViewportHeight(content.preferredHeight)
        XCTAssertNil(content.view.appearance)
        XCTAssertFalse(content.view is NSVisualEffectView)
        XCTAssertNil(content.view.layer?.backgroundColor)
        XCTAssertEqual(content.view.frame.width, 360)
        XCTAssertEqual(descendants(content.view).compactMap { $0 as? NSScrollView }.count, 1)
    }

    func testRealGlassContentInheritsLightDarkAndResolvesSemanticReadingColor() throws {
        guard #available(macOS 26.0, *) else { throw XCTSkip("Native Liquid Glass needs macOS 26") }
        let application = NSApplication.shared
        let originalAppearance = application.appearance
        defer { application.appearance = originalAppearance }
        let snapshot = PowerSnapshot(percent: 72, plugged: true,
            adapterW: 68, batteryW: 22.2, systemW: 45.8)
        for style in [NSGlassEffectView.Style.regular, .clear] {
            let content = PopoverContentViewController()
            content.setViewportHeight(content.preferredHeight)
            let panel = GlassPopoverPanel(content: content.view,
                frame: NSRect(x: 0, y: 0, width: 380, height: content.preferredHeight + 20), style: style)
            var originalReadings: [String]?
            var originalFrames: [NSRect]?
            for name in [NSAppearance.Name.aqua, .darkAqua, .aqua] {
                application.appearance = try XCTUnwrap(NSAppearance(named: name))
                content.update(snapshot: snapshot, history: [45, 68], peak: 68, degraded: false)
                content.view.layoutSubtreeIfNeeded()
                let fields = descendants(content.view).compactMap { $0 as? NSTextField }
                let reading = try XCTUnwrap(fields.first { $0.font?.pointSize == 29 })
                let color = resolved(try XCTUnwrap(reading.textColor), reading.effectiveAppearance)
                XCTAssertEqual(reading.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), name)
                XCTAssertNil(content.view.appearance)
                XCTAssertNil(panel.appearance)
                XCTAssertEqual(reading.stringValue, "68.0")
                if name == .aqua { XCTAssertLessThan(color.redComponent, 0.3) }
                else { XCTAssertGreaterThan(color.redComponent, 0.8) }
                if let originalReadings, let originalFrames {
                    XCTAssertEqual(fields.map(\.stringValue), originalReadings)
                    XCTAssertEqual(fields.map(\.frame), originalFrames)
                } else {
                    originalReadings = fields.map(\.stringValue)
                    originalFrames = fields.map(\.frame)
                }
                XCTAssertFalse(panel.isVisible)
            }
            panel.detachContent()
        }
    }

    func testPaletteResolvesToReadableLightAndDarkInstruments() throws {
        let light = try XCTUnwrap(NSAppearance(named: .aqua))
        let dark = try XCTUnwrap(NSAppearance(named: .darkAqua))
        XCTAssertFalse(PopoverStyle.isDark(light))
        XCTAssertTrue(PopoverStyle.isDark(dark))
        XCTAssertGreaterThan(resolved(PopoverStyle.well, light).redComponent, 0.8)
        XCTAssertLessThan(resolved(PopoverStyle.well, dark).redComponent, 0.3)
        XCTAssertLessThan(resolved(PopoverStyle.primaryText, light).redComponent, 0.3)
        XCTAssertGreaterThan(resolved(PopoverStyle.primaryText, dark).redComponent, 0.8)
        for color in [PopoverStyle.green, PopoverStyle.blue, PopoverStyle.amber,
                      PopoverStyle.neutral, PopoverStyle.red] {
            let lightColor = resolved(color, light)
            let darkColor = resolved(color, dark)
            XCTAssertFalse(lightColor.isEqual(darkColor))
            XCTAssertEqual(lightColor.alphaComponent, 1)
            XCTAssertEqual(darkColor.alphaComponent, 1)
        }
    }

    func testAttachingWindowStartsFocusInViewportWithoutResettingScroll() throws {
        let content = PopoverContentViewController()
        content.setViewportHeight(240)
        let scroll = try XCTUnwrap(descendants(content.view).compactMap { $0 as? NSScrollView }.first)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 30))
        let window = NSWindow(contentRect: content.view.frame, styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.contentView = content.view
        XCTAssertTrue(window.initialFirstResponder === scroll)
        XCTAssertEqual(scroll.contentView.bounds.minY, 30, accuracy: 0.5)
    }

    func testHistoryCacheIncludesResolvedAppearanceButNotRepeatedSamples() throws {
        let history = HistoryView()
        let samples = [20.0, 35.0, 24.0]
        history.appearance = NSAppearance(named: .darkAqua)
        history.update(samples: samples, peak: 35, color: PopoverStyle.neutral)
        let first = history.renderCountForTest
        history.update(samples: samples, peak: 35, color: PopoverStyle.neutral)
        XCTAssertEqual(history.renderCountForTest, first)
        history.appearance = NSAppearance(named: .aqua)
        history.update(samples: samples, peak: 35, color: PopoverStyle.neutral)
        XCTAssertEqual(history.renderCountForTest, first + 1)
        history.update(samples: samples, peak: 35, color: PopoverStyle.neutral)
        XCTAssertEqual(history.renderCountForTest, first + 1)
    }

    func testLightDarkSwitchPreservesPowerReadingsAndGeometryAcrossStates() throws {
        let content = PopoverContentViewController()
        content.setViewportHeight(content.preferredHeight)
        let snapshots = [
            PowerSnapshot(percent: 72, plugged: true, adapterW: 60, batteryW: 20, systemW: 40),
            PowerSnapshot(percent: 100, plugged: true, adapterW: 40, batteryW: 0, systemW: 40),
            PowerSnapshot(percent: 41, plugged: false, adapterW: 0, batteryW: -37, systemW: 37),
            PowerSnapshot(percent: 18, plugged: true, adapterW: 28, batteryW: -32, systemW: 60),
            PowerSnapshot(percent: 12, plugged: false, adapterW: 0, batteryW: -10, systemW: 10,
                          lowPowerMode: true),
            PowerSnapshot(percent: 67, plugged: false, adapterW: 0, batteryW: -40, systemW: 40,
                          deviceOutputW: 12),
        ]
        for snapshot in snapshots {
            content.view.appearance = NSAppearance(named: .darkAqua)
            content.update(snapshot: snapshot, history: [20, 30], peak: 30, degraded: false)
            content.view.layoutSubtreeIfNeeded()
            let fields = descendants(content.view).compactMap { $0 as? NSTextField }
            let readings = fields.map(\.stringValue)
            let frames = fields.map(\.frame)
            content.view.appearance = NSAppearance(named: .aqua)
            content.update(snapshot: snapshot, history: [20, 30], peak: 30, degraded: false)
            content.view.layoutSubtreeIfNeeded()
            XCTAssertEqual(fields.map(\.stringValue), readings)
            XCTAssertEqual(fields.map(\.frame), frames)
            XCTAssertEqual(content.runningModuleAnimationCountForTest, 0)
        }
    }

    func testViewportResizeKeepsNaturalDocumentAndClampsOldScrollOffset() throws {
        let content = PopoverContentViewController()
        let naturalHeight = content.preferredHeight
        content.setViewportHeight(240)
        content.view.layoutSubtreeIfNeeded()
        let scroll = try XCTUnwrap(descendants(content.view).compactMap { $0 as? NSScrollView }.first)
        let document = try XCTUnwrap(scroll.documentView)
        XCTAssertEqual(document.frame.height, naturalHeight)
        XCTAssertEqual(document.frame.width, scroll.contentSize.width)
        XCTAssertEqual(scroll.contentSize.height, 240, accuracy: 0.5)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: naturalHeight - 240))
        content.setViewportHeight(naturalHeight)
        content.view.layoutSubtreeIfNeeded()
        XCTAssertEqual(document.frame.height, naturalHeight)
        XCTAssertEqual(document.frame.width, PopoverStyle.width)
        XCTAssertEqual(scroll.contentView.bounds.minY, 0, accuracy: 0.5)
        XCTAssertFalse(scroll.hasVerticalScroller)
    }

    func testBothScrollerStylesKeepInstrumentsInsideTheViewport() throws {
        let content = PopoverContentViewController()
        content.setViewportHeight(240)
        let scroll = try XCTUnwrap(descendants(content.view).compactMap { $0 as? NSScrollView }.first)
        let document = try XCTUnwrap(scroll.documentView)
        for style in [NSScroller.Style.legacy, .overlay, .legacy] {
            scroll.scrollerStyle = style
            scroll.tile()
            content.view.layoutSubtreeIfNeeded()
            XCTAssertEqual(document.frame.width, scroll.contentSize.width)
            XCTAssertEqual(scroll.contentView.bounds.minX, 0)
            for section in descendants(document).compactMap({ $0 as? PopoverSection }) {
                let frame = section.convert(section.bounds, to: document)
                XCTAssertEqual(frame.width, PopoverStyle.contentWidth)
                XCTAssertGreaterThanOrEqual(frame.minX, 0)
                XCTAssertLessThanOrEqual(frame.maxX, scroll.contentSize.width)
            }
        }
    }

    func testFooterButtonsRevealKeyboardFocusWithoutInvokingActions() throws {
        let content = PopoverContentViewController()
        content.setViewportHeight(240)
        content.view.layoutSubtreeIfNeeded()
        let scroll = try XCTUnwrap(descendants(content.view).compactMap { $0 as? NSScrollView }.first)
        let document = try XCTUnwrap(scroll.documentView)
        let footer = try XCTUnwrap(descendants(document).compactMap { $0 as? PopoverFooterView }.first)
        let buttons = descendants(footer).compactMap { $0 as? NSButton }
        XCTAssertEqual(buttons.count, 2)
        for button in buttons {
            button.isEnabled = true
            scroll.contentView.scroll(to: .zero)
            XCTAssertTrue(button.becomeFirstResponder())
            let frame = button.convert(button.bounds, to: document)
            XCTAssertTrue(scroll.documentVisibleRect.contains(frame))
            XCTAssertTrue(button.resignFirstResponder())
        }
    }

    func testReducedMotionChooserRevealsKeyboardFocusWithoutSelectingMode() {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 360, height: 100))
        let document = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 500))
        scroll.documentView = document
        let chooser = NativeModeSegmentedControl(modes: [.auto, .low, .high])
        chooser.frame.origin.y = 400
        document.addSubview(chooser)
        chooser.update(selected: .auto, enabledModes: [.auto, .low, .high])
        var selected = false
        chooser.onSelect = { _ in selected = true }
        scroll.contentView.scroll(to: .zero)
        XCTAssertTrue(chooser.becomeFirstResponder())
        XCTAssertTrue(scroll.documentVisibleRect.contains(chooser.frame))
        XCTAssertEqual(chooser.selectedModeForTest, .auto)
        XCTAssertFalse(selected)
    }
}
