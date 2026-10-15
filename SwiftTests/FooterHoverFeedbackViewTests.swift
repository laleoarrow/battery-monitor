import AppKit
import XCTest
@testable import Wattson

final class FooterHoverFeedbackViewTests: XCTestCase {
    private final class FeedbackWindow: NSWindow {
        var simulatedKey = true
        var simulatedVisible = true
        override var isKeyWindow: Bool { simulatedKey }
        override var isVisible: Bool { simulatedVisible }
    }

    private var window: FeedbackWindow!
    private var content: NSView!
    private var feedback: FooterHoverFeedbackView!
    private var previousEnvironment: [String: String] = [:]
    private let environmentKeys = ["WATTSON_FORCE_REDUCE_MOTION", "WATTSON_FORCE_REDUCE_TRANSPARENCY",
                                   "WATTSON_FORCE_INCREASE_CONTRAST"]
    private let regions = [
        FooterHoverFeedbackView.Region(rect: NSRect(x: 0, y: 20, width: 90, height: 38), enabled: true),
        FooterHoverFeedbackView.Region(rect: NSRect(x: 96, y: 20, width: 90, height: 38), enabled: true),
        FooterHoverFeedbackView.Region(rect: NSRect(x: 192, y: 20, width: 38, height: 38), enabled: true),
    ]

    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
        for key in environmentKeys {
            previousEnvironment[key] = ProcessInfo.processInfo.environment[key]
            setenv(key, "0", 1)
        }
        window = FeedbackWindow(contentRect: NSRect(x: 0, y: 0, width: 240, height: 78),
                                styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        content = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 78))
        window.contentView = content
        feedback = FooterHoverFeedbackView(frame: content.bounds)
        content.addSubview(feedback)
        feedback.update(regions: regions)
    }

    override func tearDown() {
        feedback.removeFromSuperview()
        window.close()
        feedback = nil
        content = nil
        window = nil
        for key in environmentKeys {
            if let value = previousEnvironment[key] { setenv(key, value, 1) }
            else { unsetenv(key) }
        }
        previousEnvironment.removeAll()
        super.tearDown()
    }

    private func event(_ type: NSEvent.EventType = .mouseEntered) throws -> NSEvent {
        try XCTUnwrap(NSEvent.enterExitEvent(with: type, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: window.windowNumber, context: nil,
            eventNumber: 0, trackingNumber: 0, userData: nil))
    }

    private func hover(_ point: NSPoint) throws {
        feedback.pointerLocationForTest = point
        feedback.mouseEntered(with: try event())
    }

    private func assertNoReflectionAnimations(file: StaticString = #filePath, line: UInt = #line) {
        for item in [feedback.glowForTest, feedback.reflectionForTest, feedback.rimReflectionForTest] {
            XCTAssertNil(item.animationKeys(), file: file, line: line)
        }
    }

    func testOverlayLeavesClickKeyboardAndAccessibilityWithOriginalControl() throws {
        let button = NSButton(title: "Auto", target: nil, action: nil)
        button.frame = NSRect(x: 0, y: 20, width: 90, height: 38)
        content.addSubview(button, positioned: .below, relativeTo: feedback)
        let responder = window.firstResponder
        try hover(NSPoint(x: 45, y: 39))
        XCTAssertNil(feedback.hitTest(NSPoint(x: 45, y: 39)))
        XCTAssertTrue(content.hitTest(NSPoint(x: 45, y: 39)) === button)
        XCTAssertTrue(window.firstResponder === responder)
        XCTAssertFalse(feedback.acceptsFirstResponder)
        XCTAssertFalse(feedback.isAccessibilityElement())
        XCTAssertEqual(feedback.accessibilityChildren()?.count ?? 0, 0)
        XCTAssertEqual(feedback.trackingAreas.count, 1)
        XCTAssertTrue(feedback.trackingAreas[0].options.contains(.activeAlways))
        XCTAssertFalse(feedback.trackingAreas[0].options.contains(.activeInKeyWindow))
        XCTAssertFalse(feedback.trackingAreas[0].options.contains(.activeInActiveApp))
    }

    func testCurrentPointerWinsOverOutOfOrderEnterAndExitEvents() throws {
        try hover(NSPoint(x: 45, y: 39))
        XCTAssertEqual(feedback.hoveredIndexForTest, 0)
        XCTAssertEqual((feedback.glowForTest.animation(forKey: "hover") as? CABasicAnimation)?.duration, 0.14)
        try hover(NSPoint(x: 141, y: 39))
        feedback.mouseExited(with: try event(.mouseExited))
        XCTAssertEqual(feedback.hoveredIndexForTest, 1, "A late exit must not clear the button now under the pointer")
        feedback.pointerLocationForTest = NSPoint(x: 235, y: 39)
        feedback.mouseExited(with: try event(.mouseExited))
        XCTAssertNil(feedback.hoveredIndexForTest)
        XCTAssertEqual(feedback.glowForTest.opacity, 0)
        XCTAssertEqual((feedback.glowForTest.animation(forKey: "hover") as? CABasicAnimation)?.duration, 0.18)
    }

    func testOnlyEnabledRoundedRegionsReceiveFeedback() throws {
        try hover(NSPoint(x: 0, y: 20))
        XCTAssertNil(feedback.hoveredIndexForTest, "The capsule's outside corner is not part of the button")
        try hover(NSPoint(x: 93, y: 39))
        XCTAssertNil(feedback.hoveredIndexForTest, "The native buttons' gap is not an action")
        try hover(NSPoint(x: 211, y: 39))
        XCTAssertEqual(feedback.hoveredIndexForTest, 2)
        feedback.update(regions: regions.map { .init(rect: $0.rect, enabled: false) })
        XCTAssertNil(feedback.hoveredIndexForTest)
        XCTAssertEqual(feedback.glowForTest.opacity, 0)
        XCTAssertNil(feedback.glowForTest.animationKeys())
        try hover(NSPoint(x: 211, y: 39))
        XCTAssertNil(feedback.hoveredIndexForTest)
    }

    func testOrdinaryRefreshKeepsTrackingAndHoverButGeometryChangesClearIt() throws {
        let area = feedback.trackingAreas[0]
        try hover(NSPoint(x: 45, y: 39))
        feedback.update(regions: regions)
        XCTAssertEqual(feedback.hoveredIndexForTest, 0)
        XCTAssertTrue(feedback.trackingAreas[0] === area)
        feedback.update(regions: [.init(rect: regions[0].rect.offsetBy(dx: 20, dy: 0), enabled: true)])
        XCTAssertNil(feedback.hoveredIndexForTest)
        XCTAssertEqual(feedback.glowForTest.opacity, 0)
        XCTAssertTrue(feedback.trackingAreas[0] === area)
    }

    func testReflectionFollowsPointerWithinSameButtonWithoutChangingItsControl() throws {
        let selectedButton = NSButton(title: "Auto", target: nil, action: #selector(NSResponder.cancelOperation(_:)))
        selectedButton.setButtonType(.pushOnPushOff)
        selectedButton.state = .on
        selectedButton.frame = regions[0].rect
        content.addSubview(selectedButton, positioned: .below, relativeTo: feedback)
        let responder = window.firstResponder
        let area = feedback.trackingAreas[0]
        try hover(NSPoint(x: 20, y: 39))
        let first = feedback.reflectionForTest.startPoint
        let initialMask = feedback.reflectionForTest.mask?.bounds
        XCTAssertFalse(feedback.reflectionForTest.isHidden)
        try hover(NSPoint(x: 70, y: 39))
        XCTAssertEqual(feedback.hoveredIndexForTest, 0)
        XCTAssertGreaterThan(feedback.reflectionForTest.startPoint.x, first.x)
        XCTAssertEqual(feedback.reflectionForTest.startPoint.x, 70 / 90, accuracy: 0.001)
        XCTAssertEqual(feedback.rimReflectionForTest.startPoint, feedback.reflectionForTest.startPoint)
        XCTAssertEqual((feedback.reflectionForTest.animation(forKey: "startPoint") as? CABasicAnimation)?.duration, 0.08)
        XCTAssertEqual(feedback.reflectionForTest.mask?.bounds, initialMask)
        XCTAssertEqual(feedback.regionsForTest, regions)
        XCTAssertTrue(feedback.trackingAreas[0] === area)
        XCTAssertEqual(selectedButton.state, .on)
        XCTAssertEqual(selectedButton.action, #selector(NSResponder.cancelOperation(_:)))
        XCTAssertTrue(content.hitTest(NSPoint(x: 70, y: 39)) === selectedButton)
        XCTAssertTrue(window.firstResponder === responder)
    }

    func testReflectionCenterStaysInsideTheButtonAndDoesNotSweepAcrossButtons() throws {
        try hover(NSPoint(x: 1, y: 39))
        XCTAssertEqual(feedback.reflectionForTest.startPoint.x, 0.08, accuracy: 0.001)
        try hover(NSPoint(x: 89, y: 39))
        XCTAssertEqual(feedback.reflectionForTest.startPoint.x, 0.92, accuracy: 0.001)
        try hover(NSPoint(x: 141, y: 21))
        XCTAssertEqual(feedback.hoveredIndexForTest, 1)
        XCTAssertEqual(feedback.reflectionForTest.startPoint.y, 0.08, accuracy: 0.001)
        XCTAssertNil(feedback.reflectionForTest.animationKeys(), "A new button must not inherit the old reflection's travel")
        try hover(NSPoint(x: 141, y: 57))
        XCTAssertEqual(feedback.reflectionForTest.startPoint.y, 0.92, accuracy: 0.001)
        XCTAssertEqual(feedback.reflectionForTest.frame, regions[1].rect)
    }

    func testAccessibilityUsesStaticFeedbackAtEveryPointerPosition() throws {
        for key in environmentKeys {
            for resetKey in environmentKeys { setenv(resetKey, "0", 1) }
            setenv(key, "1", 1)
            NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                                                       object: nil)
            try hover(NSPoint(x: 20, y: 39))
            let center = feedback.reflectionForTest.startPoint
            try hover(NSPoint(x: 70, y: 39))
            XCTAssertEqual(feedback.hoveredIndexForTest, 0)
            XCTAssertEqual(feedback.glowForTest.opacity, 1)
            XCTAssertEqual(feedback.glowForTest.shadowOpacity, 0)
            XCTAssertTrue(feedback.reflectionForTest.isHidden)
            XCTAssertTrue(feedback.rimReflectionForTest.isHidden)
            XCTAssertEqual(feedback.reflectionForTest.startPoint, center)
            assertNoReflectionAnimations()
        }
    }

    func testCancellationRemovesReflectionInterpolationAsWellAsHoverFade() throws {
        try hover(NSPoint(x: 20, y: 39))
        try hover(NSPoint(x: 70, y: 39))
        XCTAssertNotNil(feedback.reflectionForTest.animation(forKey: "startPoint"))
        feedback.setPresentationActive(false)
        assertNoReflectionAnimations()
        XCTAssertEqual(feedback.glowForTest.opacity, 0)
        feedback.setPresentationActive(true)
        try hover(NSPoint(x: 20, y: 39))
        try hover(NSPoint(x: 70, y: 39))
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        assertNoReflectionAnimations()
        try hover(NSPoint(x: 20, y: 39))
        try hover(NSPoint(x: 70, y: 39))
        feedback.isHidden = true
        assertNoReflectionAnimations()
        feedback.isHidden = false
        try hover(NSPoint(x: 20, y: 39))
        try hover(NSPoint(x: 70, y: 39))
        let nextAppearance: NSAppearance.Name = PopoverStyle.isDark(feedback.effectiveAppearance) ? .aqua : .darkAqua
        feedback.appearance = NSAppearance(named: nextAppearance)
        assertNoReflectionAnimations()
    }

    func testHiddenDetachedInactiveAndThemeChangesClearImmediately() throws {
        try hover(NSPoint(x: 45, y: 39))
        feedback.isHidden = true
        XCTAssertNil(feedback.hoveredIndexForTest)
        feedback.isHidden = false
        try hover(NSPoint(x: 45, y: 39))
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        XCTAssertNil(feedback.hoveredIndexForTest)
        try hover(NSPoint(x: 45, y: 39))
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: nil)
        XCTAssertNil(feedback.hoveredIndexForTest)
        try hover(NSPoint(x: 45, y: 39))
        let nextAppearance: NSAppearance.Name = PopoverStyle.isDark(feedback.effectiveAppearance) ? .aqua : .darkAqua
        feedback.appearance = NSAppearance(named: nextAppearance)
        XCTAssertNil(feedback.hoveredIndexForTest)
        try hover(NSPoint(x: 45, y: 39))
        feedback.removeFromSuperview()
        XCTAssertNil(feedback.hoveredIndexForTest)
        XCTAssertEqual(feedback.glowForTest.opacity, 0)
        XCTAssertNil(feedback.glowForTest.animationKeys())
    }

    func testAccessibilitySettingsRemoveAnimationAndBlurWithoutAddingColor() throws {
        setenv("WATTSON_FORCE_REDUCE_MOTION", "1", 1)
        try hover(NSPoint(x: 45, y: 39))
        XCTAssertEqual(feedback.glowForTest.opacity, 1)
        XCTAssertNil(feedback.glowForTest.animationKeys())
        setenv("WATTSON_FORCE_REDUCE_TRANSPARENCY", "1", 1)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                                                   object: nil)
        XCTAssertNil(feedback.hoveredIndexForTest)
        try hover(NSPoint(x: 45, y: 39))
        XCTAssertNil(feedback.glowForTest.animationKeys())
        XCTAssertEqual(feedback.glowForTest.shadowOpacity, 0)
        setenv("WATTSON_FORCE_INCREASE_CONTRAST", "1", 1)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                                                   object: nil)
        XCTAssertEqual(feedback.glowForTest.lineWidth, 1)
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            feedback.appearance = NSAppearance(named: appearance)
            let fill = try XCTUnwrap(NSColor(cgColor: try XCTUnwrap(feedback.glowForTest.fillColor))?.usingColorSpace(.deviceRGB))
            let stroke = try XCTUnwrap(NSColor(cgColor: try XCTUnwrap(feedback.glowForTest.strokeColor))?.usingColorSpace(.deviceRGB))
            XCTAssertEqual(fill.redComponent, fill.greenComponent, accuracy: 0.001)
            XCTAssertEqual(fill.greenComponent, fill.blueComponent, accuracy: 0.001)
            XCTAssertEqual(stroke.redComponent, stroke.greenComponent, accuracy: 0.001)
            XCTAssertEqual(stroke.greenComponent, stroke.blueComponent, accuracy: 0.001)
            XCTAssertEqual(stroke.alphaComponent, 0.6, accuracy: 0.001)
        }
    }

    func testNonKeyClassicPresentationCanHoverWithoutAcquiringFocus() throws {
        window.simulatedKey = false
        let responder = window.firstResponder
        try hover(NSPoint(x: 45, y: 39))
        XCTAssertEqual(feedback.hoveredIndexForTest, 0)
        XCTAssertFalse(window.isKeyWindow)
        XCTAssertTrue(window.firstResponder === responder)
    }

    func testInactivePresentationOrOrderedOutWindowRejectsLateTrackingCallbacks() throws {
        try hover(NSPoint(x: 45, y: 39))
        XCTAssertEqual(feedback.hoveredIndexForTest, 0)
        feedback.setPresentationActive(false)
        feedback.mouseEntered(with: try event())
        feedback.mouseMoved(with: try event())
        XCTAssertNil(feedback.hoveredIndexForTest)
        XCTAssertEqual(feedback.glowForTest.opacity, 0)
        feedback.setPresentationActive(true)
        try hover(NSPoint(x: 45, y: 39))
        XCTAssertEqual(feedback.hoveredIndexForTest, 0)
        window.simulatedVisible = false
        feedback.mouseEntered(with: try event())
        XCTAssertNil(feedback.hoveredIndexForTest)
        XCTAssertEqual(feedback.glowForTest.opacity, 0)
        XCTAssertNil(feedback.glowForTest.animationKeys())
    }

    func testTrackingDoesNotLightClippedAwayButtons() throws {
        let clip = NSClipView(frame: NSRect(x: 0, y: 0, width: 100, height: 78))
        content.addSubview(clip)
        feedback.removeFromSuperview()
        clip.documentView = feedback
        XCTAssertTrue(feedback.visibleRect.contains(NSPoint(x: 45, y: 39)))
        XCTAssertFalse(feedback.visibleRect.contains(NSPoint(x: 141, y: 39)))
        try hover(NSPoint(x: 45, y: 39))
        XCTAssertEqual(feedback.hoveredIndexForTest, 0)
        try hover(NSPoint(x: 141, y: 39))
        feedback.mouseMoved(with: try event())
        XCTAssertNil(feedback.hoveredIndexForTest)
        XCTAssertEqual(feedback.glowForTest.opacity, 0)
    }

    func testObserverLifecycleDoesNotRetainDetachedOverlay() {
        weak var released: FooterHoverFeedbackView?
        autoreleasepool {
            let temporary = FooterHoverFeedbackView(frame: .zero)
            released = temporary
            content.addSubview(temporary)
            temporary.removeFromSuperview()
        }
        XCTAssertNil(released)
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                                                   object: nil)
    }
}
