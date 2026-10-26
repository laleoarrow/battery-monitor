import AppKit
import XCTest
@testable import Wattson

/// Hidden production-content hosts only; native compositor verification runs
/// separately in the disposable GUI VM.
final class GlassPopoverBackgroundTests: XCTestCase {
    private let overrides = [
        "WATTSON_FORCE_REDUCE_TRANSPARENCY": "1",
        "WATTSON_FORCE_REDUCE_MOTION": "1",
        "WATTSON_FORCE_INCREASE_CONTRAST": "0",
    ]
    private var previousEnvironment: [String: String] = [:]
    private var suite = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        for (key, value) in overrides {
            previousEnvironment[key] = ProcessInfo.processInfo.environment[key]
            setenv(key, value, 1)
        }
        suite = testDefaultsSuite("GlassPopoverBackground")
        defaults = UserDefaults(suiteName: suite)!
        Settings.configureForTest(defaults: defaults)
        Settings.liquidGlassEnabled = true
    }

    override func tearDown() {
        Settings.resetTestConfiguration()
        defaults.removePersistentTestDomain(forName: suite)
        for key in overrides.keys {
            if let previous = previousEnvironment[key] { setenv(key, previous, 1) }
            else { unsetenv(key) }
        }
        previousEnvironment.removeAll()
        defaults = nil
        super.tearDown()
    }

    func testReducedTransparencyUsesOneContinuousArrowAndBodyBackingInBothStyles() throws {
        guard #available(macOS 26.0, *) else { throw XCTSkip("Native Liquid Glass needs macOS 26") }
        _ = NSApplication.shared
        for style in [NSGlassEffectView.Style.regular, .clear] {
            let inset = GlassPopoverPanel.contentInset(for: style == .clear ? .clear : .regular)
            let content = PopoverContentViewController()
            content.setViewportHeight(content.preferredHeight)
            let panel = GlassPopoverPanel(content: content.view,
                frame: NSRect(x: 0, y: 0, width: 360 + 2 * inset, height: content.preferredHeight + 2 * inset + PopoverPlacement.glassArrowHeight), style: style)
            let root = try XCTUnwrap(panel.contentView)
            let backing = try XCTUnwrap(root.subviews.first as? GlassBackgroundView)
            let glass = try XCTUnwrap(root.subviews.compactMap { $0 as? GlassPopoverMaterialView }.first)
            backing.updateLayer()
            XCTAssertNil(content.view.layer?.backgroundColor)
            XCTAssertEqual(backing.layer?.backgroundColor?.alpha, 1)
            XCTAssertEqual(backing.layer?.cornerRadius, 0)
            XCTAssertEqual(backing.frame, glass.frame)
            XCTAssertEqual(content.view.convert(content.view.bounds, to: root), panel.bodyFrame)
            XCTAssertEqual(backing.frame.height - content.view.frame.height, PopoverPlacement.glassArrowHeight)
            let mask = try XCTUnwrap(backing.layer?.mask as? CAShapeLayer)
            let path = try XCTUnwrap(mask.path)
            XCTAssertEqual(path.boundingBoxOfPath, backing.bounds)
            XCTAssertTrue(path.contains(NSPoint(x: glass.arrowX, y: backing.bounds.maxY - 0.5)))
            XCTAssertFalse(path.contains(NSPoint(x: 1, y: backing.bounds.maxY - 0.5)))
            XCTAssertFalse(try XCTUnwrap(content.view.layer).masksToBounds)
            XCTAssertTrue(content.view.superview?.superview === root)
            XCTAssertNil(glass.hitTest(.zero))
            XCTAssertFalse(panel.isVisible)
            panel.detachContent()
        }
    }

    func testPopupInputFloorPreservesOpacityThemesAndForegroundWithoutChangingDefaultBacking() throws {
        guard #available(macOS 26.0, *) else { throw XCTSkip("Native Liquid Glass needs macOS 26") }
        _ = NSApplication.shared
        setenv("WATTSON_FORCE_REDUCE_TRANSPARENCY", "0", 1)
        var themeColors: [[CGFloat]] = []
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = try XCTUnwrap(NSAppearance(named: name))
            let defaultBacking = GlassBackgroundView(frame: NSRect(x: 0, y: 0, width: 100, height: 100), cornerRadius: 26)
            defaultBacking.appearance = appearance
            for style in [NSGlassEffectView.Style.regular, .clear] {
                let inset = GlassPopoverPanel.contentInset(for: style == .clear ? .clear : .regular)
                let content = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 400))
                content.wantsLayer = true
                let panel = GlassPopoverPanel(content: content,
                    frame: NSRect(x: 0, y: 0, width: 360 + 2 * inset,
                                  height: 400 + 2 * inset + PopoverPlacement.glassArrowHeight), style: style)
                panel.appearance = appearance
                let backing = try XCTUnwrap(panel.contentView?.subviews.first as? GlassBackgroundView)
                for transparency in [0.0, 0.5, 1.0] {
                    Settings.liquidGlassTransparency = transparency
                    defaultBacking.updateLayer()
                    backing.updateLayer()
                    let plainColor = try XCTUnwrap(defaultBacking.layer?.backgroundColor)
                    let popupColor = try XCTUnwrap(backing.layer?.backgroundColor)
                    XCTAssertEqual(plainColor.alpha, CGFloat(1 - transparency), accuracy: 0.0001)
                    XCTAssertEqual(popupColor.alpha, CGFloat(max(1 - transparency, 1.0 / 255.0)), accuracy: 0.0001)
                    if transparency == 1 {
                        let popupRGB = try XCTUnwrap(NSColor(cgColor: popupColor)?.usingColorSpace(.sRGB))
                        var expectedRGB: NSColor?
                        appearance.performAsCurrentDrawingAppearance {
                            expectedRGB = NSColor.windowBackgroundColor.usingColorSpace(.sRGB)
                        }
                        let expected = try XCTUnwrap(expectedRGB)
                        XCTAssertEqual(popupRGB.redComponent, expected.redComponent, accuracy: 0.001)
                        XCTAssertEqual(popupRGB.greenComponent, expected.greenComponent, accuracy: 0.001)
                        XCTAssertEqual(popupRGB.blueComponent, expected.blueComponent, accuracy: 0.001)
                        if style == .regular {
                            themeColors.append([popupRGB.redComponent, popupRGB.greenComponent, popupRGB.blueComponent])
                        }
                    }
                    XCTAssertEqual(content.alphaValue, 1)
                    XCTAssertEqual(panel.materialView?.alphaValue, 1)
                    XCTAssertNil(content.layer?.backgroundColor)
                    XCTAssertTrue(content.superview?.superview === panel.contentView)
                    XCTAssertFalse(panel.isVisible)
                }
                panel.detachContent()
            }
        }
        XCTAssertEqual(themeColors.count, 2)
        XCTAssertNotEqual(themeColors.first, themeColors.last)
    }

    func testReparentingRefreshesFallbackWithUnchangedAppearanceAndGlassPreference() throws {
        guard #available(macOS 26.0, *) else { throw XCTSkip("Native Liquid Glass needs macOS 26") }
        _ = NSApplication.shared
        let content = PopoverContentViewController()
        content.setViewportHeight(content.preferredHeight)
        // Pin the same appearance so only actual host changes can refresh the fill.
        content.view.appearance = NSAppearance(named: .aqua)
        let classic = NSWindow(contentRect: content.view.frame,
            styleMask: .borderless, backing: .buffered, defer: false)
        classic.contentView = content.view
        XCTAssertEqual(content.view.layer?.backgroundColor?.alpha, 1)
        for style in [NSGlassEffectView.Style.regular, .clear] {
            let inset = GlassPopoverPanel.contentInset(for: style == .clear ? .clear : .regular)
            classic.contentView = nil
            let panel = GlassPopoverPanel(content: content.view,
                frame: NSRect(x: 0, y: 0, width: 360 + 2 * inset, height: content.preferredHeight + 2 * inset + PopoverPlacement.glassArrowHeight), style: style)
            XCTAssertTrue(content.view.window === panel)
            XCTAssertNil(content.view.layer?.backgroundColor)
            panel.detachContent()
            classic.contentView = content.view
            XCTAssertTrue(content.view.window === classic)
            XCTAssertEqual(content.view.layer?.backgroundColor?.alpha, 1)
            XCTAssertTrue(Settings.liquidGlassEnabled)
            XCTAssertFalse(panel.isVisible)
            XCTAssertFalse(classic.isVisible)
        }
        classic.contentView = nil
    }
}
