import AppKit
import XCTest
@testable import Wattson

final class NativeModeSegmentedControlTests: XCTestCase {
    private func modeSlider(in footer: PopoverFooterView) -> ModeSliderView {
        footer.subviews.compactMap { $0 as? ModeSliderView }.first!
    }

    private func nativeControl(in footer: PopoverFooterView) -> NativeModeSegmentedControl {
        footer.subviews.compactMap { $0 as? NativeModeSegmentedControl }.first!
    }

    private func keyEvent(_ keyCode: UInt16) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode
        ))
    }

    func testNativeControlUsesProductOrderAndEqualNativeSegments() {
        let control = NativeModeSegmentedControl(modes: [.auto, .low, .high])
        control.frame = NSRect(x: 0, y: 0, width: 300,
                               height: NativeModeSegmentedControl.preferredHeight)
        control.layoutSubtreeIfNeeded()

        XCTAssertEqual(control.segmentCount, 3)
        XCTAssertEqual((0..<3).compactMap(control.label(forSegment:)),
                       ["Auto", "Low Power", "High Power"])
        XCTAssertEqual(control.segmentStyle, .automatic)
        XCTAssertEqual(control.segmentDistribution, .fillEqually)
    }

    func testUpdatePreservesSelectionAndSegmentAvailabilityForAccessibility() {
        let control = NativeModeSegmentedControl(modes: [.auto, .low, .high])
        control.update(selected: .low, enabledModes: [.auto, .low])

        XCTAssertEqual(control.selectedModeForTest, .low)
        XCTAssertTrue(control.isEnabled(forSegment: 0))
        XCTAssertTrue(control.isEnabled(forSegment: 1))
        XCTAssertFalse(control.isEnabled(forSegment: 2))
        XCTAssertEqual(control.accessibilityLabel(), "Power Mode")
        XCTAssertEqual(control.accessibilityValueDescription(), "Low Power")
        XCTAssertFalse(control.isAccessibilityElement())
        let nativeGroup = control.cell as? NSSegmentedCell
        XCTAssertEqual(nativeGroup?.accessibilityRole(), .radioGroup)
        XCTAssertEqual(nativeGroup?.accessibilityLabel(), "Power Mode")
        XCTAssertEqual(
            nativeGroup?.accessibilityChildren()?.compactMap {
                ($0 as AnyObject).accessibilityLabel()
            },
            ["Auto", "Low Power", "High Power"]
        )
        XCTAssertTrue(control.isAccessibilityEnabled())

        control.update(selected: .low, enabledModes: [])
        XCTAssertFalse(control.isAccessibilityEnabled())
    }

    func testNativeControlEmitsIntentAndAlwaysAcceptsFooterSelection() {
        let control = NativeModeSegmentedControl(modes: [.auto, .low, .high])
        control.update(selected: .auto, enabledModes: [.auto, .low, .high])
        var requested: [EnergyMode] = []
        control.onSelect = { requested.append($0) }

        control.selectModeForTest(.low)
        XCTAssertEqual(control.selectedModeForTest, .low)
        XCTAssertEqual(requested, [.low])

        control.update(selected: .auto, enabledModes: [.auto, .low, .high])
        XCTAssertEqual(control.selectedModeForTest, .auto)
    }

    func testKeyboardAndAccessibilityStepAcrossEnabledSegmentsOnly() throws {
        let control = NativeModeSegmentedControl(modes: [.auto, .low, .high])
        control.update(selected: .auto, enabledModes: [.auto, .high])
        var requested: [EnergyMode] = []
        control.onSelect = { requested.append($0) }

        control.keyDown(with: try keyEvent(124))
        XCTAssertEqual(requested, [.high])
        XCTAssertEqual(control.selectedModeForTest, .high)
        XCTAssertFalse(control.accessibilityPerformIncrement())

        XCTAssertTrue(control.accessibilityPerformDecrement())
        XCTAssertEqual(requested, [.high, .auto])
        XCTAssertEqual(control.accessibilityValueDescription(), "Auto")
    }

    func testFooterReturnsBackgroundHandlerCompletionToMainAndRollsBackNativeIntent() {
        let footer = PopoverFooterView()
        footer.update(mode: .auto, helperInstalled: true,
                      systemBatteryIconHidden: false, tint: .systemBlue)
        let native = nativeControl(in: footer)
        let updated = expectation(description: "main-thread footer completion")
        footer.onSelect = { _, completion in
            DispatchQueue.global().async {
                completion(nil)
                DispatchQueue.main.async { updated.fulfill() }
            }
        }

        footer.applyReduceMotionChangeForTest(true)
        native.selectModeForTest(.low)
        XCTAssertEqual(native.selectedModeForTest, .low)
        wait(for: [updated], timeout: 1)

        XCTAssertEqual(native.selectedModeForTest, .auto)
    }

    func testFooterIgnoresStaleCompletionAcrossNativeIntents() {
        let footer = PopoverFooterView()
        footer.update(mode: .auto, helperInstalled: true,
                      systemBatteryIconHidden: false, tint: .systemBlue)
        let native = nativeControl(in: footer)
        var requested: [EnergyMode] = []
        var completions: [(EnergyMode?) -> Void] = []
        footer.onSelect = { mode, completion in
            requested.append(mode)
            completions.append(completion)
        }

        footer.applyReduceMotionChangeForTest(true)
        native.selectModeForTest(.low)
        native.selectModeForTest(.auto)
        XCTAssertEqual(requested, [.low, .auto])

        completions[0](.low)
        XCTAssertEqual(native.selectedModeForTest, .auto)
        completions[1](nil)
        XCTAssertEqual(native.selectedModeForTest, .auto)
    }

    func testFooterSwitchesControlsAtRuntimeAndTransfersFocusAndState() {
        _ = NSApplication.shared
        let footer = PopoverFooterView()
        footer.frame = NSRect(x: 0, y: 0, width: PopoverStyle.contentWidth,
                              height: PopoverFooterView.preferredHeight)
        footer.update(mode: .low, helperInstalled: true,
                      systemBatteryIconHidden: false, tint: .systemBlue)
        footer.layoutSubtreeIfNeeded()
        let slider = modeSlider(in: footer)
        let native = nativeControl(in: footer)
        let window = NSWindow(contentRect: footer.bounds, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        defer { window.orderOut(nil) }
        window.contentView = footer

        footer.applyReduceMotionChangeForTest(false)
        XCTAssertFalse(slider.isHidden)
        XCTAssertTrue(native.isHidden)
        XCTAssertEqual(slider.selectedIndexForTest, 1)
        XCTAssertTrue(window.makeFirstResponder(slider))

        footer.applyReduceMotionChangeForTest(true)
        XCTAssertTrue(slider.isHidden)
        XCTAssertFalse(native.isHidden)
        XCTAssertEqual(native.selectedModeForTest, .low)
        XCTAssertTrue(window.firstResponder === native)
        XCTAssertEqual(native.frame, slider.frame)

        footer.applyReduceMotionChangeForTest(false)
        XCTAssertFalse(slider.isHidden)
        XCTAssertTrue(native.isHidden)
        XCTAssertTrue(window.firstResponder === slider)
        XCTAssertEqual(slider.selectedIndexForTest, 1)
    }

    func testFooterKeepsAsyncRollbackAndConfirmationAcrossControlSwitches() {
        let footer = PopoverFooterView()
        footer.update(mode: .auto, helperInstalled: true,
                      systemBatteryIconHidden: false, tint: .systemBlue)
        let slider = modeSlider(in: footer)
        let native = nativeControl(in: footer)
        var completion: ((EnergyMode?) -> Void)?
        footer.onSelect = { _, callback in completion = callback }

        footer.applyReduceMotionChangeForTest(true)
        native.selectModeForTest(.low)
        XCTAssertEqual(native.selectedModeForTest, .low)
        footer.update(mode: .auto, helperInstalled: true,
                      systemBatteryIconHidden: false, tint: .systemGreen)
        footer.applyReduceMotionChangeForTest(false)
        XCTAssertEqual(slider.selectedIndexForTest, 1)

        completion?(nil)
        XCTAssertEqual(slider.selectedIndexForTest, 0)
        footer.applyReduceMotionChangeForTest(true)
        XCTAssertEqual(native.selectedModeForTest, .auto)

        native.selectModeForTest(.low)
        completion?(.low)
        footer.applyReduceMotionChangeForTest(false)
        XCTAssertEqual(slider.selectedIndexForTest, 1)
    }

    func testNormalSliderAsyncSelectionSurvivesSwitchToReducedMotion() throws {
        let footer = PopoverFooterView()
        footer.update(mode: .auto, helperInstalled: true,
                      systemBatteryIconHidden: false, tint: .systemBlue)
        let slider = modeSlider(in: footer)
        let native = nativeControl(in: footer)
        var completion: ((EnergyMode?) -> Void)?
        footer.onSelect = { _, callback in completion = callback }

        footer.applyReduceMotionChangeForTest(false)
        slider.keyDown(with: try keyEvent(124))
        XCTAssertEqual(slider.selectedIndexForTest, 1)

        footer.applyReduceMotionChangeForTest(true)
        XCTAssertEqual(native.selectedModeForTest, .low)
        completion?(nil)
        XCTAssertEqual(native.selectedModeForTest, .auto)

        footer.applyReduceMotionChangeForTest(false)
        slider.keyDown(with: try keyEvent(124))
        completion?(.low)
        footer.applyReduceMotionChangeForTest(true)
        XCTAssertEqual(native.selectedModeForTest, .low)
    }

    func testFooterObservesForcedReduceMotionChangesWithoutASetting() {
        let previous = ProcessInfo.processInfo.environment["WATTSON_FORCE_REDUCE_MOTION"]
        defer {
            if let previous {
                setenv("WATTSON_FORCE_REDUCE_MOTION", previous, 1)
            } else {
                unsetenv("WATTSON_FORCE_REDUCE_MOTION")
            }
        }

        setenv("WATTSON_FORCE_REDUCE_MOTION", "0", 1)
        let footer = PopoverFooterView()
        let slider = modeSlider(in: footer)
        let native = nativeControl(in: footer)
        XCTAssertFalse(slider.isHidden)
        XCTAssertTrue(native.isHidden)

        setenv("WATTSON_FORCE_REDUCE_MOTION", "1", 1)
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: NSWorkspace.shared
        )
        XCTAssertTrue(slider.isHidden)
        XCTAssertFalse(native.isHidden)

        setenv("WATTSON_FORCE_REDUCE_MOTION", "0", 1)
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: NSWorkspace.shared
        )
        XCTAssertFalse(slider.isHidden)
        XCTAssertTrue(native.isHidden)
    }
}
