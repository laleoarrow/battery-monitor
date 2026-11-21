import AppKit
import XCTest
@testable import Wattson

final class RuntimeActivityMonitorTests: XCTestCase {
    private final class RuntimeWindow: NSWindow {
        override var isVisible: Bool { true }
    }

    private var window: RuntimeWindow!
    private var runtime: PopoverRuntimeView!
    private var button: NSButton!
    private var feedback: FooterHoverFeedbackView!
    private var openCount = 0
    private var previousEnvironment: [String: String] = [:]
    private let environmentKeys = ["WATTSON_FORCE_REDUCE_MOTION", "WATTSON_FORCE_REDUCE_TRANSPARENCY",
                                   "WATTSON_FORCE_INCREASE_CONTRAST"]

    override func setUpWithError() throws {
        try super.setUpWithError()
        _ = NSApplication.shared
        for key in environmentKeys {
            previousEnvironment[key] = ProcessInfo.processInfo.environment[key]
            setenv(key, "0", 1)
        }
        openCount = 0
        runtime = PopoverRuntimeView(openActivityMonitor: { [weak self] in self?.openCount += 1 })
        runtime.frame = NSRect(x: 0, y: 0, width: PopoverStyle.contentWidth,
                               height: PopoverRuntimeView.preferredHeight)
        window = RuntimeWindow(contentRect: runtime.bounds, styleMask: [.borderless],
                               backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = runtime
        runtime.layoutSubtreeIfNeeded()
        button = try XCTUnwrap(runtime.subviews.compactMap { $0 as? NSButton }.first)
        feedback = try XCTUnwrap(runtime.subviews.compactMap { $0 as? FooterHoverFeedbackView }.first)
    }

    override func tearDown() {
        runtime?.removeFromSuperview()
        window?.close()
        button = nil
        feedback = nil
        runtime = nil
        window = nil
        for key in environmentKeys {
            if let value = previousEnvironment[key] { setenv(key, value, 1) }
            else { unsetenv(key) }
        }
        previousEnvironment.removeAll()
        super.tearDown()
    }

    private func hover(_ point: NSPoint) throws {
        feedback.pointerLocationForTest = point
        let event = try XCTUnwrap(NSEvent.enterExitEvent(with: .mouseEntered, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
            eventNumber: 0, trackingNumber: 0, userData: nil))
        feedback.mouseEntered(with: event)
    }

    private func assertCleared(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNil(feedback.hoveredIndexForTest, file: file, line: line)
        XCTAssertEqual(feedback.glowForTest.opacity, 0, file: file, line: line)
        for layer in [feedback.glowForTest, feedback.reflectionForTest, feedback.rimReflectionForTest] {
            XCTAssertNil(layer.animationKeys(), file: file, line: line)
        }
    }

    func testIdleButtonPreservesClockArtworkAndOnlyAddsAnAccessibleAction() throws {
        let clock = try XCTUnwrap(runtime.subviews.compactMap { $0 as? NSImageView }.first)
        let layout = runtime.sectionLayoutForTest
        XCTAssertEqual(button.frame, layout.iconWellFrame)
        XCTAssertEqual(button.frame, NSRect(x: 12, y: 22, width: 44, height: 44))
        XCTAssertEqual(clock.frame, NSRect(x: 22, y: 32, width: 24, height: 24))
        XCTAssertNotNil(clock.image)
        XCTAssertFalse(button.isBordered)
        XCTAssertTrue(button.isTransparent)
        XCTAssertEqual(button.title, "")
        XCTAssertNil(button.image)
        XCTAssertEqual(button.toolTip, "Open Activity Monitor")
        XCTAssertEqual(button.accessibilityLabel(), "Open Activity Monitor")
        XCTAssertTrue(button.isAccessibilityElement())
        XCTAssertEqual(button.accessibilityRole(), .button)
        XCTAssertFalse(clock.isAccessibilityElement())
        XCTAssertFalse(feedback.isAccessibilityElement())
        XCTAssertTrue(runtime.subviews.last === feedback)
        XCTAssertEqual(feedback.regionsForTest.count, 1)
        XCTAssertEqual(feedback.regionsForTest[0].rect, button.frame)
        XCTAssertEqual(feedback.regionsForTest[0].cornerRadius, 11)
        assertCleared()
        XCTAssertEqual(openCount, 0)
    }

    func testClickAndAccessibilityPressEachOpenActivityMonitorOnce() throws {
        let point = NSPoint(x: button.frame.midX, y: button.frame.midY)
        XCTAssertNil(feedback.hitTest(point))
        XCTAssertTrue(runtime.hitTest(point) === button)
        button.performClick(nil)
        XCTAssertEqual(openCount, 1)
        _ = button.accessibilityPerformPress()
        XCTAssertEqual(openCount, 2)
    }

    func testHoverFollowsPointerOnlyInsideClockAndPreservesIdleArtwork() throws {
        let region = try XCTUnwrap(feedback.regionsForTest.first).rect
        let colors = runtime.wellColorsForTest
        let clock = try XCTUnwrap(runtime.subviews.compactMap { $0 as? NSImageView }.first)
        let image = clock.image
        let geometry = runtime.subviews.map(\.frame)
        try hover(NSPoint(x: region.minX + 10, y: region.midY))
        let firstCenter = feedback.reflectionForTest.startPoint
        try hover(NSPoint(x: region.maxX - 10, y: region.midY))
        XCTAssertEqual(feedback.hoveredIndexForTest, 0)
        XCTAssertGreaterThan(feedback.reflectionForTest.startPoint.x, firstCenter.x)
        XCTAssertEqual(feedback.reflectionForTest.startPoint, feedback.rimReflectionForTest.startPoint)
        XCTAssertNotNil(feedback.reflectionForTest.animation(forKey: "startPoint"))
        XCTAssertEqual(runtime.wellColorsForTest.fill, colors.fill)
        XCTAssertEqual(runtime.wellColorsForTest.border, colors.border)
        XCTAssertTrue(clock.image === image)
        XCTAssertEqual(runtime.subviews.map(\.frame), geometry)
        try hover(NSPoint(x: region.maxX + 20, y: region.midY))
        XCTAssertNil(feedback.hoveredIndexForTest)
        XCTAssertEqual(feedback.glowForTest.opacity, 0)
        XCTAssertEqual(openCount, 0)
    }

    func testRoundedSquareHoverAndBothMasksFollowClockWellInsteadOfACircle() throws {
        let region = try XCTUnwrap(feedback.regionsForTest.first).rect
        let localPoint = NSPoint(x: 5, y: 5)
        let point = NSPoint(x: region.minX + localPoint.x, y: region.minY + localPoint.y)
        try hover(point)
        XCTAssertEqual(feedback.hoveredIndexForTest, 0,
                       "The rounded square's shoulders must remain interactive")
        XCTAssertTrue(try XCTUnwrap(feedback.glowForTest.path).contains(point))
        for gradient in [feedback.reflectionForTest, feedback.rimReflectionForTest] {
            let mask = try XCTUnwrap(gradient.mask as? CAShapeLayer)
            XCTAssertTrue(try XCTUnwrap(mask.path).contains(localPoint))
            XCTAssertFalse(try XCTUnwrap(mask.path).contains(NSPoint(x: 1, y: 1)))
        }
        try hover(NSPoint(x: region.minX + 1, y: region.minY + 1))
        XCTAssertNil(feedback.hoveredIndexForTest)
    }

    func testDismissHideAndDetachCancelClockFeedbackAndRejectLateHover() throws {
        let rect = try XCTUnwrap(feedback.regionsForTest.first).rect
        let point = NSPoint(x: rect.midX, y: rect.midY)
        try hover(point)
        runtime.setPresentationActive(false)
        assertCleared()
        try hover(point)
        assertCleared()
        runtime.setPresentationActive(true)
        try hover(point)
        runtime.isHidden = true
        assertCleared()
        try hover(point)
        assertCleared()
        runtime.isHidden = false
        try hover(point)
        runtime.removeFromSuperview()
        assertCleared()
        XCTAssertEqual(openCount, 0)
    }
}
