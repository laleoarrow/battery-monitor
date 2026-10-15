import AppKit
import XCTest
@testable import Wattson

/// The global monitor can precede a relayed status-button action. These tests
/// exercise that ordering without creating windows or posting native events.
final class StatusClickDismissalTests: XCTestCase {
    private let anchor = NSRect(x: -500, y: 738, width: 77, height: 30)

    func testGlobalAnchorClickThenButtonActionClosesOnceAndNextClickReopens() {
        for point in [NSPoint(x: -462, y: 753), NSPoint(x: -462, y: 767.5),
                      NSPoint(x: -462, y: 738.5), NSPoint(x: -462, y: anchor.maxY)] {
            var open = true
            var router = ClickRouter()
            if PopoverController.shouldDismissGlobalClick(screenPoint: point, anchorFrame: anchor) {
                open = false
            }
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                for intent in router.intents(for: type) where intent == .primary { open.toggle() }
            }
            XCTAssertFalse(open, "The monitor must leave the same click to the button at \(point)")
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                for intent in router.intents(for: type) where intent == .primary { open.toggle() }
            }
            XCTAssertTrue(open, "The following complete click must still reopen")
        }
    }

    func testGlobalOutsideClickStillDismissesAndMissingAnchorDoesNotBlockDismissal() {
        for point in [NSPoint(x: -501, y: 753), NSPoint(x: -422, y: 753),
                      NSPoint(x: -462, y: 737), NSPoint(x: -462, y: 769)] {
            XCTAssertTrue(PopoverController.shouldDismissGlobalClick(screenPoint: point, anchorFrame: anchor))
        }
        XCTAssertTrue(PopoverController.shouldDismissGlobalClick(screenPoint: .zero, anchorFrame: nil))
    }

    func testGlobalAnchorIncludesScreenTopButNotNeighboringStatusItem() {
        for x in [anchor.minX, anchor.midX, anchor.maxX - 0.5] {
            XCTAssertFalse(PopoverController.shouldDismissGlobalClick(
                screenPoint: NSPoint(x: x, y: anchor.maxY), anchorFrame: anchor))
        }
        XCTAssertFalse(PopoverController.shouldDismissGlobalClick(
            screenPoint: anchor.origin, anchorFrame: anchor))
        XCTAssertTrue(PopoverController.shouldDismissGlobalClick(
            screenPoint: NSPoint(x: anchor.maxX, y: anchor.midY), anchorFrame: anchor))
        XCTAssertTrue(PopoverController.shouldDismissGlobalClick(
            screenPoint: NSPoint(x: anchor.midX, y: anchor.maxY.nextUp), anchorFrame: anchor))
    }

    func testGlobalAnchorRightClickStaysOpenAndOnlySelectsEnergyMode() {
        let point = NSPoint(x: anchor.midX, y: anchor.midY)
        XCTAssertFalse(PopoverController.shouldDismissGlobalClick(screenPoint: point, anchorFrame: anchor))
        var router = ClickRouter()
        let events: [NSEvent.EventType] = [.rightMouseDown, .rightMouseUp]
        let intents: [ClickIntent] = events.flatMap { router.intents(for: $0) }
        XCTAssertEqual(intents.filter { $0 == .secondary }.count, 1)
        XCTAssertFalse(intents.contains(.primary))
    }

    func testEarlyDismissalThenButtonActionClosesInsteadOfReopening() {
        func stateAfterButtonAction(suppressEarlyClose: Bool) -> Bool {
            var open = true
            if !suppressEarlyClose { open = false }
            var router = ClickRouter()
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                for intent in router.intents(for: type) where intent == .primary { open.toggle() }
            }
            return open
        }
        XCTAssertTrue(stateAfterButtonAction(suppressEarlyClose: false),
                      "The previous strategy reproduces close-then-reopen")
        let suppress = PopoverController.shouldPreservePrimaryAnchorPress(
            screenPoint: NSPoint(x: anchor.midX, y: anchor.maxY), anchorFrame: anchor,
            pressedMouseButtons: 1, controlHeld: false)
        XCTAssertFalse(stateAfterButtonAction(suppressEarlyClose: suppress),
                       "The same primary press must leave the popup closed")
    }

    func testEarlyDismissalSuppressionRequiresLiveUnmodifiedPrimaryPress() {
        let point = NSPoint(x: anchor.midX, y: anchor.midY)
        func suppress(buttons: Int = 1, control: Bool = false, at location: NSPoint? = nil) -> Bool {
            PopoverController.shouldPreservePrimaryAnchorPress(screenPoint: location ?? point,
                anchorFrame: anchor, pressedMouseButtons: buttons, controlHeld: control)
        }
        XCTAssertTrue(suppress())
        for buttons in [0, 2, 3, 4] { XCTAssertFalse(suppress(buttons: buttons)) }
        XCTAssertFalse(suppress(control: true))
        XCTAssertFalse(suppress(at: NSPoint(x: anchor.maxX, y: anchor.midY)))
        XCTAssertFalse(PopoverController.shouldPreservePrimaryAnchorPress(screenPoint: point,
            anchorFrame: nil, pressedMouseButtons: 1, controlHeld: false))
    }
}
