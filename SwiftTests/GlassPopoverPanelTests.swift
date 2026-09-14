import AppKit
import XCTest
@testable import Wattson

/// These tests construct hidden windows only. Real focus, menu event delivery,
/// backdrop rendering and cross-app dismissal belong to the GUI VM harness.
final class GlassPopoverPanelTests: XCTestCase {
    func testPanelKeepsOneNativeMaterialAboveTheNonInteractiveBacking() throws {
        guard #available(macOS 26.0, *) else { throw XCTSkip("Native Liquid Glass needs macOS 26") }
        _ = NSApplication.shared
        for style in [NSGlassEffectView.Style.regular, .clear] {
            let content = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 400))
            let panel = GlassPopoverPanel(content: content,
                frame: NSRect(x: -420, y: 80, width: 380, height: 420), style: style)
            let root = try XCTUnwrap(panel.contentView)
            XCTAssertEqual(root.subviews.count, 3)
            XCTAssertEqual(root.subviews.compactMap { $0 as? NSGlassEffectView }.count, 1)
            let backing = try XCTUnwrap(root.subviews.first as? GlassBackgroundView)
            XCTAssertNil(backing.hitTest(.zero))
            XCTAssertFalse(backing.isAccessibilityElement())
            let glass = try XCTUnwrap(root.subviews.compactMap { $0 as? NSGlassEffectView }.first)
            XCTAssertNil(glass.contentView)
            XCTAssertTrue(content.superview === root)
            XCTAssertTrue(root.subviews.last === content)
            XCTAssertFalse(content.isDescendant(of: glass))
            XCTAssertEqual(content.frame, glass.frame)
            XCTAssertEqual(glass.style, style)
            XCTAssertNil(glass.tintColor)
            XCTAssertEqual(glass.cornerRadius, 26)
            XCTAssertEqual(glass.frame, root.bounds.insetBy(dx: 10, dy: 10))
            XCTAssertFalse(root.isOpaque)
            XCTAssertNil(root.layer?.backgroundColor)
            XCTAssertFalse(panel.isOpaque)
            XCTAssertEqual(panel.hasShadow, style == .clear)
            XCTAssertEqual(panel.backgroundColor, NSColor.clear)
            XCTAssertFalse(panel.isVisible)
            XCTAssertFalse(root is NSVisualEffectView)
            panel.detachContent()
            XCTAssertNil(glass.contentView)
            XCTAssertNil(content.superview)
            XCTAssertNil(content.window)
        }
    }

    func testPanelCanReceiveKeyboardWithoutActivatingOrBecomingMain() throws {
        guard #available(macOS 26.0, *) else { throw XCTSkip("Native Liquid Glass needs macOS 26") }
        _ = NSApplication.shared
        let panel = GlassPopoverPanel(content: NSView(),
            frame: NSRect(x: 0, y: 0, width: 380, height: 420), style: .regular)
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertFalse(panel.styleMask.contains(.titled))
        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertFalse(panel.isRestorable)
        XCTAssertFalse(panel.isReleasedWhenClosed)
        XCTAssertFalse(panel.hidesOnDeactivate)
        XCTAssertNil(panel.appearance)
        XCTAssertEqual(panel.title, "Wattson Power Monitor")
        XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertFalse(panel.isVisible)
    }

    func testPanelResizeMaintainsOpticalMarginAndContentSize() throws {
        guard #available(macOS 26.0, *) else { throw XCTSkip("Native Liquid Glass needs macOS 26") }
        _ = NSApplication.shared
        let panel = GlassPopoverPanel(content: NSView(),
            frame: NSRect(x: 0, y: 0, width: 380, height: 420), style: .clear)
        panel.setFrame(NSRect(x: -380, y: -500, width: 380, height: 560), display: false)
        let root = try XCTUnwrap(panel.contentView)
        let glass = try XCTUnwrap(root.subviews.compactMap { $0 as? NSGlassEffectView }.first)
        XCTAssertEqual(glass.frame.size, NSSize(width: 360, height: 540))
        XCTAssertEqual(glass.frame.origin, NSPoint(x: 10, y: 10))
        XCTAssertEqual(root.subviews.first?.frame, glass.frame)
        XCTAssertEqual(root.subviews.last?.frame, glass.frame)
        XCTAssertFalse(panel.isVisible)
    }

    func testEscapeAndDirectCloseRelayDismissalWithoutRetainingOwner() throws {
        guard #available(macOS 26.0, *) else { throw XCTSkip("Native Liquid Glass needs macOS 26") }
        _ = NSApplication.shared
        let panel = GlassPopoverPanel(content: NSView(),
            frame: NSRect(x: 0, y: 0, width: 380, height: 420), style: .regular)
        var dismissals = 0
        var escapes = 0
        panel.onDismiss = { dismissals += 1 }
        panel.onEscape = { escapes += 1 }
        panel.cancelOperation(nil)
        XCTAssertEqual(escapes, 1)
        XCTAssertEqual(dismissals, 0)
        panel.close()
        XCTAssertEqual(dismissals, 1)
        panel.onDismiss = nil
        panel.onEscape = nil
        panel.cancelOperation(nil)
        XCTAssertEqual(escapes, 1)
        XCTAssertEqual(dismissals, 1)
    }

    func testRetiredClassicCallbackCannotAffectReplacementHost() throws {
        _ = NSApplication.shared
        let controller = PopoverController()
        let root = try XCTUnwrap(controller.contentViewForTest)
        let retired = controller.classicPopoverForTest
        controller.retireClassicHostForTest()
        XCTAssertFalse(controller.classicPopoverForTest === retired)
        XCTAssertNil(retired.delegate)
        XCTAssertNil(retired.contentViewController)
        XCTAssertTrue(controller.contentViewForTest === root)
        XCTAssertEqual(controller.classicLifecycleCountsForTest.shows, 0)
        XCTAssertEqual(controller.classicLifecycleCountsForTest.closes, 0)
        controller.popoverDidClose(Notification(name: NSPopover.didCloseNotification, object: retired))
        XCTAssertEqual(controller.classicLifecycleCountsForTest.closes, 0)
        XCTAssertFalse(controller.isOpen)
        XCTAssertFalse(controller.isWatchingOutsideClicks)
        XCTAssertEqual(controller.lifetimeObserverCountForTest, 0)
    }

    func testEscapeRoutingLeavesUnrelatedOwnAppWindowUntouched() throws {
        guard #available(macOS 26.0, *) else { throw XCTSkip("Native Liquid Glass needs macOS 26") }
        _ = NSApplication.shared
        let panel = GlassPopoverPanel(content: NSView(),
            frame: NSRect(x: 0, y: 0, width: 380, height: 420), style: .regular)
        // Hidden stand-in only: no alert is presented and no window is made key.
        let other = NSWindow(contentRect: .zero, styleMask: .titled, backing: .buffered, defer: false)
        XCTAssertTrue(panel.ownsEscapeEvent(eventWindow: panel, keyWindow: panel))
        XCTAssertTrue(panel.ownsEscapeEvent(eventWindow: panel, keyWindow: other))
        XCTAssertTrue(panel.ownsEscapeEvent(eventWindow: nil, keyWindow: panel))
        XCTAssertFalse(panel.ownsEscapeEvent(eventWindow: other, keyWindow: panel))
        XCTAssertFalse(panel.ownsEscapeEvent(eventWindow: other, keyWindow: other))
        XCTAssertFalse(panel.ownsEscapeEvent(eventWindow: nil, keyWindow: other))
        XCTAssertFalse(panel.ownsEscapeEvent(eventWindow: nil, keyWindow: nil))
        XCTAssertFalse(panel.isVisible)
        XCTAssertFalse(other.isVisible)
    }

    func testBothGlassMaterialsInheritAppLightDarkAppearance() throws {
        guard #available(macOS 26.0, *) else { throw XCTSkip("Native Liquid Glass needs macOS 26") }
        let application = NSApplication.shared
        let originalAppearance = application.appearance
        defer { application.appearance = originalAppearance }
        for style in [NSGlassEffectView.Style.regular, .clear] {
            let content = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 400))
            let panel = GlassPopoverPanel(content: content,
                frame: NSRect(x: 0, y: 0, width: 380, height: 420), style: style)
            let glass = try XCTUnwrap(panel.contentView?.subviews.compactMap { $0 as? NSGlassEffectView }.first)
            for name in [NSAppearance.Name.aqua, .darkAqua, .aqua] {
                application.appearance = try XCTUnwrap(NSAppearance(named: name))
                for view in [panel.contentView!, glass, content] {
                    XCTAssertNil(view.appearance)
                    XCTAssertEqual(view.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), name)
                }
                XCTAssertNil(panel.appearance)
                XCTAssertEqual(panel.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), name)
                XCTAssertEqual(glass.style, style)
                XCTAssertNil(glass.tintColor)
                XCTAssertFalse(panel.isVisible)
            }
            panel.detachContent()
        }
    }
}
