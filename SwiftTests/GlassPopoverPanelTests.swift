import AppKit
import XCTest
@testable import Wattson

/// These tests construct hidden windows only. Real focus, menu event delivery,
/// backdrop rendering and cross-app dismissal belong to the GUI VM harness.
final class GlassPopoverPanelTests: XCTestCase {
    func testOptionalArrowUpdatesBackingAndBodyWithoutReplacingContent() throws {
        guard #available(macOS 26.0, *) else { throw XCTSkip("Native Liquid Glass needs macOS 26") }
        _ = NSApplication.shared
        for style in [NSGlassEffectView.Style.regular, .clear] {
            let inset = GlassPopoverPanel.contentInset(for: style == .clear ? .clear : .regular)
            let content = NSView()
            let initialFrame = NSRect(x: -440, y: 80, width: 360 + 2 * inset,
                                      height: 400 + 2 * inset + 12)
            let panel = GlassPopoverPanel(content: content, frame: initialFrame, style: style)
            defer { panel.detachContent() }
            let glass = try XCTUnwrap(panel.materialView)
            let foreground = try XCTUnwrap(content.superview)
            let backing = try XCTUnwrap(panel.contentView?.subviews.first as? GlassBackgroundView)
            let previousTop = panel.convertToScreen(panel.bodyFrame).maxY
            for showsArrow in [false, true, false, true] {
                panel.setShowsArrow(showsArrow)
                let frame = NSRect(x: initialFrame.minX, y: initialFrame.minY + (showsArrow ? 0 : 12),
                                   width: initialFrame.width, height: initialFrame.height - (showsArrow ? 0 : 12))
                panel.setFrame(frame, display: false)
                XCTAssertEqual(panel.showsArrow, showsArrow)
                XCTAssertEqual(glass.showsArrow, showsArrow)
                XCTAssertTrue(panel.materialView === glass)
                XCTAssertTrue(content.superview === foreground)
                XCTAssertTrue(content.window === panel)
                XCTAssertEqual(content.bounds.size, NSSize(width: 360, height: 400))
                XCTAssertEqual(panel.convertToScreen(panel.bodyFrame).maxY, previousTop + (showsArrow ? 0 : 12))
                let path = try XCTUnwrap((backing.layer?.mask as? CAShapeLayer)?.path)
                // A shoulder point belongs to the flat top only when the arrow is off.
                XCTAssertEqual(path.contains(CGPoint(x: 80, y: backing.bounds.maxY - 1)), !showsArrow)
                XCTAssertFalse(path.contains(CGPoint(x: 1, y: backing.bounds.maxY - 1)))
                XCTAssertFalse(panel.isVisible)
            }
        }
    }

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
            let foreground = try XCTUnwrap(content.superview)
            XCTAssertFalse(foreground === root)
            XCTAssertTrue(foreground.superview === root)
            XCTAssertTrue(root.subviews.last === foreground)
            XCTAssertFalse(content.isDescendant(of: glass))
            XCTAssertEqual(foreground.frame, panel.bodyFrame)
            XCTAssertEqual(content.frame, foreground.bounds)
            XCTAssertEqual(content.frame.origin, .zero)
            XCTAssertEqual(foreground.frame.origin, glass.frame.origin)
            XCTAssertEqual(foreground.layer?.cornerRadius, 26)
            XCTAssertTrue(try XCTUnwrap(foreground.layer).masksToBounds)
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
            XCTAssertNil(foreground.superview)
            XCTAssertNil(foreground.window)
            XCTAssertEqual(root.subviews.count, 2)
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
            let content = NSView()
            let panel = GlassPopoverPanel(content: content,
                frame: NSRect(x: 0, y: 0, width: 360 + 2 * inset, height: 400 + 2 * inset + PopoverPlacement.glassArrowHeight), style: style)
            panel.setFrame(NSRect(x: -440, y: -500, width: 360 + 2 * inset, height: 540 + 2 * inset + PopoverPlacement.glassArrowHeight), display: false)
            let root = try XCTUnwrap(panel.contentView)
            let glass = try XCTUnwrap(root.subviews.compactMap { $0 as? GlassPopoverMaterialView }.first)
            XCTAssertEqual(glass.frame.size, NSSize(width: 360, height: 540 + PopoverPlacement.glassArrowHeight))
            XCTAssertEqual(glass.frame.origin, NSPoint(x: inset, y: inset))
            XCTAssertEqual(root.subviews.first?.frame, glass.frame)
            XCTAssertEqual(root.subviews.last?.frame, panel.bodyFrame)
            XCTAssertEqual(panel.bodyFrame.size, NSSize(width: 360, height: 540))
            let foreground = try XCTUnwrap(content.superview)
            XCTAssertEqual(foreground.frame, panel.bodyFrame)
            XCTAssertEqual(content.frame, foreground.bounds)
            XCTAssertEqual(content.bounds.size, NSSize(width: 360, height: 540))
            XCTAssertEqual(content.convert(content.bounds, to: root), panel.bodyFrame)
            XCTAssertTrue(content.window === panel)
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

    func testForegroundRasterClipsOversizedChildrenAtBodyEdgesAndRoundedCorners() throws {
        guard #available(macOS 26.0, *) else { throw XCTSkip("Native Liquid Glass needs macOS 26") }
        _ = NSApplication.shared
        let padding = 50
        for style in [NSGlassEffectView.Style.regular, .clear] {
            let inset = GlassPopoverPanel.contentInset(for: style == .clear ? .clear : .regular)
            let content = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 400))
            content.wantsLayer = true
            content.layer?.cornerRadius = 7
            content.layer?.masksToBounds = false
            let panel = GlassPopoverPanel(content: content,
                frame: NSRect(x: 0, y: 0, width: 360 + 2 * inset,
                              height: 400 + 2 * inset + PopoverPlacement.glassArrowHeight), style: style)
            defer { panel.detachContent() }
            let root = try XCTUnwrap(panel.contentView)
            root.layoutSubtreeIfNeeded()
            let foreground = try XCTUnwrap(root.subviews.last)
            let layer = try XCTUnwrap(foreground.layer)
            // Hidden NSView children do not populate their backing sublayers.
            // A direct layer exercises the actual viewport's clipping here.
            let oversized = CALayer()
            oversized.frame = CGRect(x: -80, y: -80, width: 520, height: 560)
            oversized.backgroundColor = NSColor.systemRed.cgColor
            layer.addSublayer(oversized)
            defer { oversized.removeFromSuperlayer() }
            let body = NSRect(x: CGFloat(padding), y: CGFloat(padding), width: 360, height: 400)
            let outside = [
                NSPoint(x: body.minX - 4, y: body.midY), NSPoint(x: body.maxX + 4, y: body.midY),
                NSPoint(x: body.midX, y: body.minY - 4), NSPoint(x: body.midX, y: body.maxY + 4),
            ]
            let corners = [
                NSPoint(x: body.minX + 1, y: body.minY + 1), NSPoint(x: body.maxX - 2, y: body.minY + 1),
                NSPoint(x: body.minX + 1, y: body.maxY - 2), NSPoint(x: body.maxX - 2, y: body.maxY - 2),
            ]
            let clipped = try rasterize(layer, padding: padding)
            let unmaskedControl: ForegroundRaster = try {
                let originalClipping = layer.masksToBounds
                layer.masksToBounds = false
                defer { layer.masksToBounds = originalClipping }
                return try rasterize(layer, padding: padding)
            }()
            // A renderer that silently clips every layer would make a broken
            // host pass. The same oversized child must spill in this control.
            guard (outside + corners).allSatisfy({ unmaskedControl.alpha(at: $0) > 0.99 }) else {
                XCTFail("Unmasked raster control did not spill; CALayer rendering cannot establish foreground clipping")
                return
            }
            let interior = [NSPoint(x: body.midX, y: body.midY),
                NSPoint(x: body.minX + 2, y: body.midY), NSPoint(x: body.maxX - 2, y: body.midY),
                NSPoint(x: body.midX, y: body.minY + 2), NSPoint(x: body.midX, y: body.maxY - 2)]
            for point in interior { XCTAssertGreaterThan(clipped.alpha(at: point), 0.99) }
            for point in outside + corners {
                XCTAssertEqual(clipped.alpha(at: point), 0, accuracy: 0.001,
                               "Foreground escaped body at \(point), style=\(style)")
            }
            XCTAssertEqual(content.layer?.cornerRadius, 7)
            XCTAssertFalse(try XCTUnwrap(content.layer).masksToBounds)
            XCTAssertFalse(panel.isVisible)
            panel.detachContent()
        }
    }

    func testDetachingForegroundPreservesSharedContentLayerAndRemovesWrapper() throws {
        guard #available(macOS 26.0, *) else { throw XCTSkip("Native Liquid Glass needs macOS 26") }
        _ = NSApplication.shared
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 400))
        content.wantsLayer = true
        let layer = try XCTUnwrap(content.layer)
        let originalMask = CAShapeLayer()
        originalMask.path = CGPath(rect: content.bounds, transform: nil)
        layer.mask = originalMask
        layer.cornerRadius = 9
        layer.masksToBounds = false
        let panel = GlassPopoverPanel(content: content,
            frame: NSRect(x: 0, y: 0, width: 424, height: 476), style: .regular)
        let root = try XCTUnwrap(panel.contentView)
        let foreground = try XCTUnwrap(content.superview)
        XCTAssertFalse(foreground === root)
        XCTAssertTrue(foreground.superview === root)
        XCTAssertTrue(layer.mask === originalMask)
        XCTAssertEqual(layer.cornerRadius, 9)
        XCTAssertFalse(layer.masksToBounds)
        panel.detachContent()
        XCTAssertNil(content.superview)
        XCTAssertNil(content.window)
        XCTAssertNil(foreground.superview)
        XCTAssertEqual(root.subviews.count, 2)
        XCTAssertTrue(content.layer === layer)
        XCTAssertTrue(layer.mask === originalMask)
        XCTAssertEqual(layer.cornerRadius, 9)
        XCTAssertFalse(layer.masksToBounds)
        XCTAssertFalse(panel.isVisible)
    }

    private struct ForegroundRaster {
        let bytes: [UInt8]
        let width: Int
        func alpha(at point: NSPoint) -> Double {
            Double(bytes[(Int(point.y) * width + Int(point.x)) * 4 + 3]) / 255
        }
    }

    private func rasterize(_ layer: CALayer, padding: Int) throws -> ForegroundRaster {
        let width = Int(layer.bounds.width) + 2 * padding
        let height = Int(layer.bounds.height) + 2 * padding
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        context.clear(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        context.translateBy(x: CGFloat(padding), y: CGFloat(padding))
        layer.render(in: context)
        let data = try XCTUnwrap(context.data)
        let bytes = Array(UnsafeRawBufferPointer(start: data, count: width * height * 4))
        return ForegroundRaster(bytes: bytes, width: width)
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
            let foreground = try XCTUnwrap(content.superview)
            for name in [NSAppearance.Name.aqua, .darkAqua, .aqua] {
                application.appearance = try XCTUnwrap(NSAppearance(named: name))
                for view in [panel.contentView!, glass, foreground, content] {
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
