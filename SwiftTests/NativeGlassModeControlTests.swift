import AppKit
import XCTest
@testable import Wattson

final class NativeGlassModeControlTests: XCTestCase {
    private var suiteName = ""
    private var previousReduceMotion: String?

    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
        suiteName = "Wattson.NativeGlassModeTests.\(UUID().uuidString)"
        Settings.configureForTest(defaults: UserDefaults(suiteName: suiteName)!)
        previousReduceMotion = ProcessInfo.processInfo.environment["WATTSON_FORCE_REDUCE_MOTION"]
        setenv("WATTSON_FORCE_REDUCE_MOTION", "0", 1)
    }

    override func tearDown() {
        Settings.resetTestConfiguration()
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        if let previousReduceMotion { setenv("WATTSON_FORCE_REDUCE_MOTION", previousReduceMotion, 1) }
        else { unsetenv("WATTSON_FORCE_REDUCE_MOTION") }
        super.tearDown()
    }

    private func buttons(_ control: NativeGlassModeControl) -> [NSButton] {
        control.subviews.compactMap { $0 as? NSButton }
    }

    private func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }

    private func footerAndControl() -> (PopoverFooterView, NativeGlassModeControl) {
        Settings.liquidGlassEnabled = true
        let footer = PopoverFooterView()
        footer.frame = NSRect(x: 0, y: 0, width: PopoverStyle.contentWidth, height: 78)
        footer.update(mode: .auto, helperInstalled: true, systemBatteryIconHidden: false, tint: .systemBlue)
        footer.layoutSubtreeIfNeeded()
        return (footer, descendants(footer).compactMap { $0 as? NativeGlassModeControl }.first!)
    }

    private func key(_ code: UInt16) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                      timestamp: 0, windowNumber: 0, context: nil,
                                      characters: "", charactersIgnoringModifiers: "",
                                      isARepeat: false, keyCode: code))
    }

    func testRealButtonsHaveUnnestedGlassFullLabelsAndEqualGeometry() {
        guard #available(macOS 26.0, *) else { return }
        let control = NativeGlassModeControl(modes: [.auto, .low, .high])
        control.frame = NSRect(x: 0, y: 0, width: 281, height: 38)
        control.update(selected: .low, enabledModes: [.auto, .low])
        control.layoutSubtreeIfNeeded()
        let items = buttons(control)
        XCTAssertEqual(items.map(\.title), ["Auto", "Low Power", "High Power"])
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(control.subviews.count, 3)
        XCTAssertNil(control.layer?.backgroundColor)
        XCTAssertEqual(control.accessibilityRole(), .radioGroup)
        XCTAssertEqual(control.accessibilityLabel(), "Power Mode")
        XCTAssertEqual(control.accessibilityValueDescription(), "Low Power")
        XCTAssertEqual(control.accessibilityChildren()?.count, 3)
        for (index, button) in items.enumerated() {
            XCTAssertEqual(button.bezelStyle, .glass)
            XCTAssertEqual(button.borderShape, .capsule)
            XCTAssertTrue(button.isBordered)
            XCTAssertEqual(button.frame.height, 38)
            XCTAssertEqual(button.frame.width, CGFloat(269) / 3, accuracy: 0.001)
            XCTAssertLessThan(button.title.size(withAttributes: [.font: button.font!]).width,
                              button.frame.width - 16)
            XCTAssertEqual(button.state, index == 1 ? .on : .off)
            XCTAssertEqual(button.tintProminence, index == 1 ? .primary : .none)
            XCTAssertFalse(button.isAccessibilityElement())
            XCTAssertTrue(button.cell?.isAccessibilityElement() == true)
            XCTAssertEqual(button.cell?.accessibilityRole(), .checkBox)
            XCTAssertEqual(button.cell?.accessibilityLabel(), button.title)
            XCTAssertEqual((button.cell?.accessibilityValue() as? NSNumber)?.intValue, index == 1 ? 1 : 0)
            XCTAssertEqual(button.cell?.accessibilityChildren()?.count ?? 0, 0)
            if index > 0 { XCTAssertEqual(button.frame.minX - items[index - 1].frame.maxX, 6, accuracy: 0.001) }
        }
        XCTAssertFalse(items[2].isEnabled)
    }

    func testRepeatedNativeToggleClickCannotClearSelectionOrRepeatIntent() {
        let control = NativeGlassModeControl(modes: [.auto, .low, .high])
        control.update(selected: .low, enabledModes: [.auto, .low, .high])
        var requests: [EnergyMode] = []
        control.onSelect = { requests.append($0) }
        buttons(control)[1].performClick(nil)
        buttons(control)[1].performClick(nil)
        XCTAssertTrue(requests.isEmpty)
        XCTAssertEqual(buttons(control).map(\.state), [.off, .on, .off])
        buttons(control)[0].performClick(nil)
        XCTAssertEqual(requests, [.auto])
        XCTAssertEqual(control.selectedModeForTest, .low, "Intent must not replace the owner's state")
        XCTAssertEqual(buttons(control).map(\.state), [.off, .on, .off])
    }

    func testDisabledModeAndBusyGroupRejectMouseKeyboardAndAccessibilityActions() throws {
        let control = NativeGlassModeControl(modes: [.auto, .low, .high])
        var requests: [EnergyMode] = []
        control.onSelect = { requests.append($0) }
        control.update(selected: .low, enabledModes: [.auto, .low])
        buttons(control)[2].performClick(nil)
        control.selectModeForTest(.high)
        XCTAssertFalse(control.accessibilityPerformIncrement())
        control.keyDown(with: try key(124))
        XCTAssertTrue(requests.isEmpty)
        control.update(selected: .low, enabledModes: [])
        buttons(control)[0].performClick(nil)
        control.selectModeForTest(.auto)
        XCTAssertFalse(control.isAccessibilityEnabled())
        XCTAssertFalse(control.accessibilityPerformPress())
        XCTAssertFalse(control.accessibilityPerformIncrement())
        XCTAssertFalse(control.accessibilityPerformDecrement())
        XCTAssertTrue(requests.isEmpty)
        XCTAssertEqual(buttons(control).map(\.state), [.off, .on, .off])
    }

    func testArrowsSkipDisabledModesAndReturnActsOnFocusedButton() throws {
        let control = NativeGlassModeControl(modes: [.auto, .low, .high])
        control.update(selected: .auto, enabledModes: [.auto, .high])
        var requests: [EnergyMode] = []
        control.onSelect = { mode in
            requests.append(mode)
            control.update(selected: mode, enabledModes: [.auto, .high])
        }
        buttons(control)[0].keyDown(with: try key(124))
        XCTAssertEqual(requests, [.high])
        XCTAssertEqual(control.selectedModeForTest, .high)
        XCTAssertTrue(control.accessibilityPerformDecrement())
        XCTAssertEqual(requests, [.high, .auto])
        buttons(control)[2].keyDown(with: try key(36))
        XCTAssertEqual(requests, [.high, .auto, .high])
    }

    func testFooterBusyDisablesAllButtonsThenSameModeConfirmationReenablesThem() {
        guard #available(macOS 26.0, *) else { return }
        let (footer, control) = footerAndControl()
        var completion: ((EnergyMode?) -> Void)?
        var requests: [EnergyMode] = []
        footer.onSelect = { mode, callback in requests.append(mode); completion = callback }
        buttons(control)[1].performClick(nil)
        XCTAssertEqual(requests, [.low])
        XCTAssertEqual(control.selectedModeForTest, .low)
        XCTAssertTrue(buttons(control).allSatisfy { !$0.isEnabled })
        control.selectModeForTest(.auto)
        buttons(control)[0].performClick(nil)
        XCTAssertEqual(requests, [.low])
        completion?(.low)
        XCTAssertTrue(buttons(control)[0].isEnabled)
        XCTAssertTrue(buttons(control)[1].isEnabled)
        XCTAssertEqual(buttons(control).map(\.state), [.off, .on, .off])
        buttons(control)[1].performClick(nil)
        XCTAssertEqual(requests, [.low])
        XCTAssertEqual(buttons(control).map(\.state), [.off, .on, .off])
    }

    func testFooterFailureRollsBackToLatestObservationAndBackgroundCompletionUsesMain() {
        guard #available(macOS 26.0, *) else { return }
        let (footer, control) = footerAndControl()
        var completion: ((EnergyMode?) -> Void)?
        footer.onSelect = { _, callback in completion = callback }
        control.selectModeForTest(.low)
        footer.update(mode: .high, helperInstalled: true, systemBatteryIconHidden: false, tint: .systemBlue)
        let finished = expectation(description: "main-thread rollback")
        let callback = completion
        DispatchQueue.global().async {
            callback?(nil)
            DispatchQueue.main.async { finished.fulfill() }
        }
        wait(for: [finished], timeout: 1)
        XCTAssertEqual(control.selectedModeForTest, .high)
        XCTAssertEqual(buttons(control).map(\.state), [.off, .off, .on])
        XCTAssertTrue(buttons(control)[0].isEnabled)
    }

    func testRuntimeToggleTransfersFocusFromGroupAndEveryChildAndReusesButtons() {
        guard #available(macOS 26.0, *) else { return }
        let (footer, control) = footerAndControl()
        footer.update(mode: .low, helperInstalled: true, systemBatteryIconHidden: false, tint: .systemBlue)
        let originalButtons = buttons(control)
        let window = NSWindow(contentRect: footer.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = footer
        defer { window.orderOut(nil) }
        let slider = descendants(footer).compactMap { $0 as? ModeSliderView }.first!
        let segmented = descendants(footer).compactMap { $0 as? NativeModeSegmentedControl }.first!
        var requests = 0
        footer.onSelect = { _, _ in requests += 1 }
        for reduceMotion in [false, true] {
            setenv("WATTSON_FORCE_REDUCE_MOTION", reduceMotion ? "1" : "0", 1)
            for source in [control as NSView] + originalButtons.filter(\.isEnabled) {
                XCTAssertTrue(window.makeFirstResponder(source))
                footer.applyReduceMotionChangeForTest(reduceMotion)
                XCTAssertTrue(window.firstResponder === source, "No control switch must not steal child focus")
                Settings.liquidGlassEnabled = false
                XCTAssertTrue(window.firstResponder === (reduceMotion ? segmented as NSView : slider))
                Settings.liquidGlassEnabled = true
                XCTAssertTrue(window.firstResponder === control.keyboardFocusView)
                XCTAssertTrue(control.keyboardFocusView === originalButtons[1])
                XCTAssertTrue(zip(buttons(control), originalButtons).allSatisfy { $0 === $1 })
            }
        }
        XCTAssertEqual(requests, 0)
    }

    func testPendingRequestSurvivesGlassOffOnAndFailureRestoresAvailability() {
        guard #available(macOS 26.0, *) else { return }
        let (footer, control) = footerAndControl()
        var completion: ((EnergyMode?) -> Void)?
        var requests = 0
        footer.onSelect = { _, callback in requests += 1; completion = callback }
        control.selectModeForTest(.low)
        Settings.liquidGlassEnabled = false
        Settings.liquidGlassEnabled = true
        XCTAssertEqual(control.selectedModeForTest, .low)
        XCTAssertTrue(buttons(control).allSatisfy { !$0.isEnabled })
        XCTAssertEqual(requests, 1)
        completion?(nil)
        XCTAssertEqual(control.selectedModeForTest, .auto)
        XCTAssertTrue(buttons(control)[0].isEnabled)
        XCTAssertTrue(buttons(control)[1].isEnabled)
        XCTAssertEqual(requests, 1)
    }

    func testBusyParksModeFocusThenRestoresSelectionWithoutStealingMenuFocus() {
        guard #available(macOS 26.0, *) else { return }
        let (footer, control) = footerAndControl()
        let window = NSWindow(contentRect: footer.bounds, styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.contentView = footer
        defer { window.orderOut(nil) }
        let slider = descendants(footer).compactMap { $0 as? ModeSliderView }.first!
        let menu = descendants(footer).compactMap { $0 as? NSButton }.first {
            $0.action == NSSelectorFromString("showMenu")
        }!
        var completion: ((EnergyMode?) -> Void)?
        footer.onSelect = { _, callback in completion = callback }
        XCTAssertTrue(window.makeFirstResponder(buttons(control)[0]))
        buttons(control)[1].performClick(nil)
        XCTAssertTrue(window.firstResponder === control, "Disable must park focused buttons in the group")
        XCTAssertTrue(buttons(control).allSatisfy { !$0.isEnabled })
        Settings.liquidGlassEnabled = false
        XCTAssertTrue(window.firstResponder === slider)
        Settings.liquidGlassEnabled = true
        XCTAssertTrue(window.firstResponder === control)
        completion?(.low)
        XCTAssertTrue(window.firstResponder === buttons(control)[1])
        XCTAssertEqual(control.selectedModeForTest, .low)

        buttons(control)[0].performClick(nil)
        XCTAssertTrue(window.firstResponder === control)
        XCTAssertTrue(window.makeFirstResponder(menu))
        completion?(nil)
        XCTAssertTrue(window.firstResponder === menu, "Completion must not reclaim focus from another control")
        XCTAssertEqual(control.selectedModeForTest, .low)
    }
}
