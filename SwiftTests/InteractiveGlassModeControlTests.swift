import XCTest
@testable import Wattson

/// Pure production intent/geometry policy. Real SwiftUI gesture recognition,
/// focus rings and compositor appearance need the separate GUI matrix.
final class InteractiveGlassModeControlTests: XCTestCase {
    private func model(_ selected: EnergyMode = .auto,
                       enabled: [EnergyMode] = [.auto, .low, .high]) -> InteractiveGlassModeModel {
        let result = InteractiveGlassModeModel(modes: [.auto, .low, .high])
        result.update(selected: selected, enabledModes: enabled)
        return result
    }
    private func grab(_ model: InteractiveGlassModeModel, x: CGFloat? = nil) {
        model.remember(model.beginDrag(startX: x ?? (CGFloat(model.selectedIndex) + 0.5) * model.slotWidth))
    }

    func testDraggingDoesNotCommitAndReleaseCommitsOnlyOnce() {
        let state = model()
        var requests: [EnergyMode] = []
        state.onSelect = { requests.append($0) }
        grab(state)
        for x in stride(from: 0.0, through: 188.0, by: 4) {
            XCTAssertNotNil(state.dragOrigin(translationX: x))
        }
        XCTAssertEqual(requests, [])
        XCTAssertEqual(state.selected, .auto)
        XCTAssertTrue(state.finishDrag(translationX: 188))
        XCTAssertEqual(requests, [.high])
        XCTAssertEqual(state.selected, .auto, "Only the owner can accept a mode")
        XCTAssertFalse(state.finishDrag(translationX: 188))
        XCTAssertEqual(requests, [.high])
    }

    func testGrabOffsetAndContinuousGeometryArePreserved() {
        let state = model(.low)
        grab(state, x: state.slotWidth + 7)
        XCTAssertEqual(state.dragOrigin(translationX: 5), state.slotWidth + 5)
        XCTAssertEqual(state.dragOrigin(translationX: 11), state.slotWidth + 11)
        XCTAssertEqual(state.dragOrigin(translationX: -10_000), 0)
        XCTAssertEqual(state.dragOrigin(translationX: 10_000), 2 * state.slotWidth)
    }

    func testPressOutsideSelectedThumbCannotJumpIntoADrag() {
        let state = model()
        var requests = 0
        state.onSelect = { _ in requests += 1 }
        grab(state, x: state.slotWidth + 15)
        XCTAssertTrue(state.isDragging, "The captured label gesture still needs Escape cancellation")
        XCTAssertNil(state.dragOrigin(translationX: 5))
        XCTAssertNil(state.dragOrigin(translationX: 160))
        XCTAssertFalse(state.finishDrag(translationX: 160))
        XCTAssertEqual(requests, 0)
        XCTAssertTrue(state.request(1), "Ordinary enabled-button clicks remain available")
        XCTAssertEqual(requests, 1)
    }

    func testUnselectedLabelJitterActivatesOnceWithoutMovingTheThumb() {
        let state = model(.low)
        var requests: [EnergyMode] = []
        state.onSelect = { requests.append($0) }
        grab(state, x: 15) // Auto label, away from the selected Low capsule.
        XCTAssertNil(state.dragOrigin(translationX: 8))
        XCTAssertEqual(requests, [])
        XCTAssertEqual(state.selected, .low)
        XCTAssertTrue(state.finishDrag(translationX: 8))
        XCTAssertEqual(requests, [.auto])
        XCTAssertEqual(state.selected, .low, "Only the owner accepts the click")
        XCTAssertFalse(state.finishDrag(translationX: 8))
        XCTAssertEqual(requests, [.auto])
    }

    func testJitterRejectsReleaseOutsideOriginalLabelInEitherAxis() {
        let state = model(.low)
        var requests = 0
        state.onSelect = { _ in requests += 1 }
        for offset in [NSPoint(x: 90, y: 0), NSPoint(x: -16, y: 0),
                       NSPoint(x: 8, y: 20), NSPoint(x: 8, y: -20),
                       NSPoint(x: CGFloat.infinity, y: 0), NSPoint(x: 8, y: CGFloat.nan)] {
            grab(state, x: 15)
            XCTAssertFalse(state.finishDrag(translationX: offset.x, translationY: offset.y))
        }
        for start in [NSPoint(x: -1, y: 19), NSPoint(x: 15, y: -1),
                      NSPoint(x: CGFloat.nan, y: 19), NSPoint(x: 15, y: CGFloat.infinity)] {
            state.remember(state.beginDrag(startX: start.x, startY: start.y))
            XCTAssertFalse(state.finishDrag(translationX: 8))
        }
        XCTAssertEqual(requests, 0)
        XCTAssertEqual(state.selected, .low)
    }

    func testCancelledOrDisabledJitterCannotActivateOnRelease() {
        let state = model(.low)
        var requests = 0
        state.onSelect = { _ in requests += 1 }
        let old = state.beginDrag(startX: 15)
        state.remember(old)
        state.cancel()
        state.remember(old)
        XCTAssertFalse(state.finishDrag(translationX: 8))
        grab(state, x: 15)
        state.update(selected: .low, enabledModes: [.low, .high])
        XCTAssertFalse(state.finishDrag(translationX: 8))
        grab(state, x: 15) // Already disabled when the original press begins.
        XCTAssertFalse(state.finishDrag(translationX: 8))
        XCTAssertEqual(requests, 0)
    }

    func testNonThumbEscapeCancellationRejectsLateUpdatesAndRelease() {
        let state = model(.low)
        var requests = 0
        state.onSelect = { _ in requests += 1 }
        let originalPress = state.beginDrag(startX: 15)
        state.remember(originalPress)
        XCTAssertTrue(state.isDragging)
        XCTAssertNil(state.dragOrigin(translationX: 8), "Active does not mean the lens moves")
        XCTAssertTrue(state.cancelDragIfActive(), "Same cancellation policy as the AppKit Escape bridge")
        XCTAssertFalse(state.isDragging)
        XCTAssertFalse(state.cancelDragIfActive())
        state.remember(originalPress) // Late SwiftUI update after Escape.
        XCTAssertFalse(state.isDragging)
        XCTAssertFalse(state.finishDrag(translationX: 8))
        XCTAssertEqual(requests, 0)
        XCTAssertEqual(state.selected, .low)

        state.update(selected: .low, enabledModes: [.low])
        for x in [CGFloat(15), CGFloat(-1), CGFloat.nan] {
            grab(state, x: x) // Disabled Auto, outside track, invalid location.
            XCTAssertFalse(state.isDragging)
            XCTAssertFalse(state.cancelDragIfActive())
            XCTAssertFalse(state.finishDrag(translationX: 8))
        }
    }

    func testJitterOwnerAcceptanceOrBusyStateRejectsARepeatedChildAction() {
        for busy in [false, true] {
            let state = model(.low)
            var requests: [EnergyMode] = []
            state.onSelect = { requested in
                requests.append(requested)
                state.update(selected: requested, enabledModes: busy ? [] : [.auto, .low, .high])
            }
            grab(state, x: 15)
            XCTAssertTrue(state.finishDrag(translationX: 8))
            _ = state.request(0) // A late action from the original Auto button.
            XCTAssertFalse(state.finishDrag(translationX: 8))
            XCTAssertEqual(requests, [.auto])
            XCTAssertEqual(state.selected, .auto)
        }
    }

    func testOwnerRefreshDoesNotTakeGeometryButCancelUsesLatestOwnerValue() {
        let state = model()
        grab(state)
        let generation = state.generation
        state.update(selected: .low, enabledModes: [.auto, .low, .high])
        XCTAssertEqual(state.generation, generation)
        XCTAssertEqual(state.dragOrigin(translationX: 30), 30)
        state.cancel()
        XCTAssertNil(state.dragOrigin(translationX: 30))
        XCTAssertEqual(state.selected, .low)
        XCTAssertFalse(state.finishDrag(translationX: 160))
    }

    func testCancelledGestureCannotBeResurrectedByLateUpdatesOrMouseUp() {
        let state = model()
        let old = state.beginDrag(startX: 40)
        state.remember(old)
        state.cancel() // Escape, close, resign, hide, detach or theme change.
        state.remember(old) // SwiftUI can deliver another update before release.
        XCTAssertFalse(state.isDragging)
        XCTAssertNil(state.dragOrigin(translationX: 170))
        XCTAssertFalse(state.finishDrag(translationX: 170))
        grab(state)
        XCTAssertTrue(state.isDragging, "A genuinely new gesture must work after cancellation")
    }

    func testBusyCancelsGestureAndRejectsEveryIntentUntilOwnerRestoresAvailability() {
        let state = model()
        var requests: [EnergyMode] = []
        state.onSelect = { requests.append($0) }
        grab(state)
        state.update(selected: .low, enabledModes: [])
        XCTAssertFalse(state.isDragging)
        XCTAssertFalse(state.finishDrag(translationX: 180))
        for index in 0..<3 { XCTAssertFalse(state.request(index)) }
        XCTAssertFalse(state.move(1))
        state.update(selected: .auto, enabledModes: [.auto, .low]) // owner rollback
        XCTAssertEqual(state.selected, .auto)
        XCTAssertEqual(requests, [])
        XCTAssertTrue(state.request(1))
        XCTAssertEqual(requests, [.low])
    }

    func testDisabledDestinationIsSkippedAtReleaseAndForKeyboard() {
        let state = model(enabled: [.auto, .high])
        var requests: [EnergyMode] = []
        state.onSelect = { requests.append($0) }
        grab(state)
        XCTAssertTrue(state.finishDrag(translationX: 140))
        XCTAssertEqual(requests, [.high])
        XCTAssertTrue(state.move(1, from: 0))
        XCTAssertEqual(requests, [.high, .high])
        XCTAssertFalse(state.request(1))
        XCTAssertFalse(state.move(-1, from: 0))
    }

    func testChangedAvailabilityAndGeometryCancelExistingGrab() {
        let state = model()
        grab(state)
        state.update(selected: .auto, enabledModes: [.auto, .low])
        XCTAssertFalse(state.finishDrag(translationX: 140))
        grab(state)
        state.setRowWidth(400)
        XCTAssertNil(state.dragOrigin(translationX: 140))
        XCTAssertEqual(state.trackWidth, 354)
        XCTAssertEqual(state.slotWidth, 118)
    }

    func testRepeatedSelectedClickDoesNotToggleOffOrRequest() {
        let state = model(.low)
        var requests = 0
        state.onSelect = { _ in requests += 1 }
        XCTAssertTrue(state.request(1))
        XCTAssertTrue(state.request(1))
        XCTAssertEqual(requests, 0)
        XCTAssertEqual(state.selected, .low)
        XCTAssertFalse(state.request(-1))
        XCTAssertFalse(state.request(3))
    }

    func testPointerDoesNotCreateKeyboardFocusOrReclaimMenuFocus() {
        let state = model()
        state.onSelect = { _ in }
        grab(state)
        XCTAssertTrue(state.finishDrag(translationX: 100))
        XCTAssertNil(state.focusRequest)
        state.focusedIndex = state.modes.count
        XCTAssertTrue(state.request(1))
        XCTAssertNil(state.focusRequest, "Pending completion must not take focus from the menu")
        state.focusedIndex = 0
        XCTAssertTrue(state.request(1))
        XCTAssertEqual(state.focusRequest?.index, 1)
    }

    func testInvalidPointerValuesFailClosed() {
        let state = model()
        grab(state)
        XCTAssertNil(state.dragOrigin(translationX: .infinity))
        XCTAssertNil(state.dragOrigin(translationX: .nan))
        XCTAssertFalse(state.finishDrag(translationX: .nan))
    }
}
