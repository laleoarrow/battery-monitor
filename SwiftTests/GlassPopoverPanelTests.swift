import AppKit
import XCTest
@testable import Wattson

/// These tests construct hidden windows only. Real focus, menu event delivery,
/// backdrop rendering and cross-app dismissal belong to the GUI VM harness.
final class GlassPopoverPanelTests: XCTestCase {
    func testPanelKeepsOneContinuousMaterialAboveTheNonInteractiveBacking() throws {
        guard #available(macOS 26.0, *) else { throw XCTSkip("Native Liquid Glass needs macOS 26") }
        _ = NSApplication.shared
        for style in [NSGlassEffectView.Style.regular, .clear] {
            let inset = GlassPopoverPanel.contentInset(for: style == .clear ? .clear : .regular)
            let content = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 400))
            let panel = GlassPopoverPanel(content: content,
                frame: NSRect(x: -440, y: 80, width: 360 + 2 * inset, height: 400 + 2 * inset + PopoverPlacement.glassArrowHeight), style: style)
            let root = try XCTUnwrap(panel.contentView)
            XCTAssertEqual(root.subviews.count, 3)
            XCTAssertEqual(root.subviews.compactMap { $0 as? GlassPopoverMaterialView }.count, 1)
            let backing = try XCTUnwrap(root.subviews.first as? GlassBackgroundView)
            XCTAssertNil(backing.hitTest(.zero))
            XCTAssertFalse(backing.isAccessibilityElement())
            let glass = try XCTUnwrap(root.subviews.compactMap { $0 as? GlassPopoverMaterialView }.first)
            XCTAssertNil(glass.hitTest(.zero))
            XCTAssertTrue(content.superview === root)
            XCTAssertTrue(root.subviews.last === content)
            XCTAssertFalse(content.isDescendant(of: glass))
            XCTAssertEqual(content.frame, panel.bodyFrame)
            XCTAssertEqual(content.frame.origin, glass.frame.origin)
            XCTAssertEqual(content.frame.width, glass.frame.width)
            XCTAssertEqual(glass.frame.height - content.frame.height, PopoverPlacement.glassArrowHeight)
            XCTAssertEqual(glass.style, style)
            XCTAssertEqual(backing.layer?.cornerRadius, 0)
            let mask = try XCTUnwrap(backing.layer?.mask as? CAShapeLayer)
            XCTAssertEqual(mask.frame, backing.bounds)
            XCTAssertEqual(try XCTUnwrap(mask.path).boundingBoxOfPath, backing.bounds)
            XCTAssertEqual(glass.frame, root.bounds.insetBy(dx: inset, dy: inset))
            XCTAssertEqual(glass.frame.size, NSSize(width: 360, height: 400 + PopoverPlacement.glassArrowHeight))
            XCTAssertEqual(inset, style == .clear ? 10 : 32)
            XCTAssertFalse(root.isOpaque)
            XCTAssertNil(root.layer?.backgroundColor)
            XCTAssertFalse(panel.isOpaque)
            XCTAssertEqual(panel.hasShadow, style == .clear)
            XCTAssertEqual(panel.backgroundColor, NSColor.clear)
            XCTAssertFalse(panel.isVisible)
            XCTAssertFalse(root is NSVisualEffectView)
            panel.detachContent()
            XCTAssertNil(glass.hitTest(.zero))
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
        for style in [NSGlassEffectView.Style.regular, .clear] {
            let inset = GlassPopoverPanel.contentInset(for: style == .clear ? .clear : .regular)
            let panel = GlassPopoverPanel(content: NSView(),
                frame: NSRect(x: 0, y: 0, width: 360 + 2 * inset, height: 400 + 2 * inset + PopoverPlacement.glassArrowHeight), style: style)
            panel.setFrame(NSRect(x: -440, y: -500, width: 360 + 2 * inset, height: 540 + 2 * inset + PopoverPlacement.glassArrowHeight), display: false)
            let root = try XCTUnwrap(panel.contentView)
            let glass = try XCTUnwrap(root.subviews.compactMap { $0 as? GlassPopoverMaterialView }.first)
            XCTAssertEqual(glass.frame.size, NSSize(width: 360, height: 540 + PopoverPlacement.glassArrowHeight))
            XCTAssertEqual(glass.frame.origin, NSPoint(x: inset, y: inset))
            XCTAssertEqual(root.subviews.first?.frame, glass.frame)
            XCTAssertEqual(root.subviews.last?.frame, panel.bodyFrame)
            XCTAssertEqual(panel.bodyFrame.size, NSSize(width: 360, height: 540))
            let backing = try XCTUnwrap(root.subviews.first as? GlassBackgroundView)
            let mask = try XCTUnwrap(backing.layer?.mask as? CAShapeLayer)
            XCTAssertEqual(mask.frame, backing.bounds)
            XCTAssertEqual(try XCTUnwrap(mask.path).boundingBoxOfPath, backing.bounds)
            XCTAssertFalse(panel.isVisible)
        }
    }

    func testArrowRetainsItsScreenAnchorAcrossResizeAndClampsAtBothCorners() throws {
        guard #available(macOS 26.0, *) else { throw XCTSkip("Native Liquid Glass needs macOS 26") }
        _ = NSApplication.shared
        for style in [NSGlassEffectView.Style.regular, .clear] {
            let inset = GlassPopoverPanel.contentInset(for: style == .clear ? .clear : .regular)
            let panel = GlassPopoverPanel(content: NSView(),
                frame: NSRect(x: -440, y: -500, width: 360 + 2 * inset,
                              height: 400 + 2 * inset + PopoverPlacement.glassArrowHeight), style: style)
            let glass = try XCTUnwrap(panel.materialView)
            let screenAnchor: CGFloat = -300
            panel.point(to: screenAnchor)
            XCTAssertEqual(panel.convertToScreen(NSRect(origin: panel.arrowTip, size: .zero)).origin.x,
                           screenAnchor, accuracy: 0.001)
            XCTAssertEqual(panel.arrowTip.y - panel.bodyFrame.maxY, PopoverPlacement.glassArrowHeight)
            panel.setFrame(NSRect(x: -460, y: -600, width: 400 + 2 * inset,
                                  height: 500 + 2 * inset + PopoverPlacement.glassArrowHeight), display: false)
            XCTAssertEqual(panel.convertToScreen(NSRect(origin: panel.arrowTip, size: .zero)).origin.x,
                           screenAnchor, accuracy: 0.001)
            XCTAssertEqual(panel.bodyFrame.size, NSSize(width: 400, height: 500))
            let backing = try XCTUnwrap(panel.contentView?.subviews.first as? GlassBackgroundView)
            for anchor in [CGFloat(-10_000), CGFloat(10_000)] {
                panel.point(to: anchor)
                let expectedX = GlassPopoverShape.clampedArrowX(anchor - panel.frame.minX - inset,
                                                               width: glass.bounds.width)
                XCTAssertEqual(glass.arrowX, expectedX)
                XCTAssertEqual(panel.arrowTip.x, inset + expectedX)
                let mask = try XCTUnwrap(backing.layer?.mask as? CAShapeLayer)
                let path = try XCTUnwrap(mask.path)
                XCTAssertTrue(path.contains(NSPoint(x: expectedX, y: backing.bounds.maxY - 0.5)))
                XCTAssertFalse(path.contains(NSPoint(x: glass.bounds.midX, y: backing.bounds.maxY - 0.5)))
            }
            XCTAssertFalse(panel.isVisible)
            panel.detachContent()
        }
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
            let glass = try XCTUnwrap(panel.contentView?.subviews.compactMap { $0 as? GlassPopoverMaterialView }.first)
            for name in [NSAppearance.Name.aqua, .darkAqua, .aqua] {
                application.appearance = try XCTUnwrap(NSAppearance(named: name))
                for view in [panel.contentView!, glass, content] {
                    XCTAssertNil(view.appearance)
                    XCTAssertEqual(view.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), name)
                }
                XCTAssertNil(panel.appearance)
                XCTAssertEqual(panel.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), name)
                XCTAssertEqual(glass.style, style)
                XCTAssertFalse(panel.isVisible)
            }
            panel.detachContent()
        }
    }
}
