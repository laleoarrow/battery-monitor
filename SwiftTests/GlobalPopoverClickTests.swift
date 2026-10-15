import AppKit
import XCTest
@testable import Wattson

/// Monitor routing with hidden native windows; actual event delivery is
/// verified separately in the disposable GUI VM.
final class GlobalPopoverClickTests: XCTestCase {
    private var contentWindow: NSWindow!
    private var foreignWindow: NSWindow!
    private let body = NSRect(x: 500, y: 100, width: 360, height: 500)
    private let anchor = NSRect(x: 640, y: 700, width: 40, height: 24)

    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
        contentWindow = NSWindow(contentRect: body, styleMask: [.borderless],
                                 backing: .buffered, defer: false)
        foreignWindow = NSWindow(contentRect: body, styleMask: [.borderless],
                                 backing: .buffered, defer: false)
        contentWindow.isReleasedWhenClosed = false
        foreignWindow.isReleasedWhenClosed = false
    }

    override func tearDown() {
        contentWindow.close()
        foreignWindow.close()
        contentWindow = nil
        foreignWindow = nil
        super.tearDown()
    }

    private func mouseDown(in window: NSWindow?, type: NSEvent.EventType = .leftMouseDown) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: type, location: NSPoint(x: 180, y: 250),
            modifierFlags: [], timestamp: 0, windowNumber: window?.windowNumber ?? 0,
            context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
    }

    private func dismisses(_ event: NSEvent, content: NSWindow?, at point: NSPoint? = nil) -> Bool {
        PopoverController.shouldDismissGlobalClick(
            screenPoint: point ?? NSPoint(x: body.midX, y: body.midY), anchorFrame: anchor,
            eventWindow: event.window, eventWindowNumber: event.windowNumber, contentWindow: content)
    }

    func testRelayedPopupMouseDownStaysWithItsNativeContentWindow() throws {
        let event = try mouseDown(in: contentWindow)
        XCTAssertTrue(event.window === contentWindow)
        XCTAssertGreaterThan(event.windowNumber, 0)
        XCTAssertFalse(dismisses(event, content: contentWindow),
                       "A duplicate global delivery must not close before the content button's mouse-up")
        XCTAssertFalse(contentWindow.isVisible)
        XCTAssertFalse(foreignWindow.isVisible)
    }

    func testContentWindowIdentityDoesNotRequireAnEventWindowNumber() {
        XCTAssertFalse(PopoverController.shouldDismissGlobalClick(
            screenPoint: NSPoint(x: body.midX, y: body.midY), anchorFrame: anchor,
            eventWindow: contentWindow, eventWindowNumber: 0, contentWindow: contentWindow))
    }

    func testGlobalEventWithoutWindowObjectUsesPositiveContentWindowNumber() throws {
        let event = try mouseDown(in: contentWindow)
        XCTAssertFalse(PopoverController.shouldDismissGlobalClick(
            screenPoint: NSPoint(x: body.midX, y: body.midY), anchorFrame: anchor,
            eventWindow: nil, eventWindowNumber: event.windowNumber, contentWindow: contentWindow),
                       "Global monitoring may carry the target number without an AppKit window object")
    }

    func testForeignWindowAtSameCoordinatesAndUnknownWindowStillDismiss() throws {
        XCTAssertNotEqual(contentWindow.windowNumber, foreignWindow.windowNumber)
        XCTAssertEqual(contentWindow.frame, foreignWindow.frame)
        XCTAssertTrue(dismisses(try mouseDown(in: foreignWindow), content: contentWindow),
                      "The popup's rectangle must not shield another window drawn over it")
        XCTAssertTrue(PopoverController.shouldDismissGlobalClick(
            screenPoint: NSPoint(x: body.midX, y: body.midY), anchorFrame: anchor,
            eventWindow: nil, eventWindowNumber: foreignWindow.windowNumber, contentWindow: contentWindow))
        XCTAssertTrue(dismisses(try mouseDown(in: nil), content: contentWindow))
        XCTAssertTrue(PopoverController.shouldDismissGlobalClick(
            screenPoint: NSPoint(x: body.midX, y: body.midY), anchorFrame: anchor,
            eventWindow: nil, eventWindowNumber: -1, contentWindow: contentWindow))
        XCTAssertTrue(PopoverController.shouldDismissGlobalClick(
            screenPoint: NSPoint(x: body.midX, y: body.midY), anchorFrame: anchor,
            eventWindow: foreignWindow, eventWindowNumber: contentWindow.windowNumber,
            contentWindow: contentWindow), "An explicit different window must not be hidden by a numeric fallback")
    }

    func testClosedOrReplacedContentDoesNotRetainPreviousWindowExemption() throws {
        let event = try mouseDown(in: contentWindow)
        XCTAssertFalse(dismisses(event, content: contentWindow))
        XCTAssertTrue(dismisses(event, content: nil))
        XCTAssertTrue(dismisses(event, content: foreignWindow))
        XCTAssertFalse(dismisses(try mouseDown(in: foreignWindow), content: foreignWindow))
    }

    func testAnchorAndRightClickRoutingRetainExistingToggleOwnership() throws {
        let anchorPoint = NSPoint(x: anchor.midX, y: anchor.midY)
        for type in [NSEvent.EventType.leftMouseDown, .rightMouseDown, .otherMouseDown] {
            let event = try mouseDown(in: foreignWindow, type: type)
            XCTAssertFalse(dismisses(event, content: contentWindow, at: anchorPoint))
            XCTAssertTrue(dismisses(event, content: contentWindow))
            XCTAssertFalse(dismisses(try mouseDown(in: contentWindow, type: type), content: contentWindow))
        }
    }
}
