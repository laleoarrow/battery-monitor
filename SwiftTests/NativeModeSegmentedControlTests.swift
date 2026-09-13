import AppKit
import XCTest
@testable import Wattson

final class NativeModeSegmentedControlTests: XCTestCase {
    private var suiteName = ""
    private var previousReduceMotion: String?

    override func setUp() {
        super.setUp()
        suiteName = "Wattson.NativeModeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        Settings.configureForTest(defaults: defaults)
        previousReduceMotion = ProcessInfo.processInfo.environment["WATTSON_FORCE_REDUCE_MOTION"]
        setenv("WATTSON_FORCE_REDUCE_MOTION", "0", 1)
    }

    override func tearDown() {
        Settings.resetTestConfiguration()
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        if let previousReduceMotion {
            setenv("WATTSON_FORCE_REDUCE_MOTION", previousReduceMotion, 1)
        } else {
            unsetenv("WATTSON_FORCE_REDUCE_MOTION")
        }
        super.tearDown()
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    private func modeSlider(in footer: PopoverFooterView) -> ModeSliderView {
        descendants(of: footer).compactMap { $0 as? ModeSliderView }.first!
    }

    private func nativeControl(in footer: PopoverFooterView) -> NativeModeSegmentedControl {
        descendants(of: footer).compactMap { $0 as? NativeModeSegmentedControl }.first!
    }

    private func glassControl(in footer: PopoverFooterView) -> NativeGlassModeControl {
        descendants(of: footer).compactMap { $0 as? NativeGlassModeControl }.first!
    }

    private func menuButton(in footer: PopoverFooterView) -> NSButton {
        descendants(of: footer).compactMap { $0 as? NSButton }.first {
            $0.action == NSSelectorFromString("showMenu")
        }!
    }

    func testGlassChoiceAtConstructionUsesNativeControlsOnlyOnSupportedSystems() {
        // This suite retains C's native-button contract; A2 has its own suite.
        if #available(macOS 26.0, *) { setenv("WATTSON_FORCE_REDUCE_MOTION", "1", 1) }
        Settings.liquidGlassEnabled = true
        let footer = PopoverFooterView()
        footer.frame = NSRect(x: 0, y: 0, width: PopoverStyle.contentWidth,
                              height: PopoverFooterView.preferredHeight)
        footer.layoutSubtreeIfNeeded()
        let menu = menuButton(in: footer)
        if #available(macOS 26.0, *) {
            XCTAssertTrue(modeSlider(in: footer).isHidden)
            XCTAssertTrue(nativeControl(in: footer).isHidden)
            XCTAssertFalse(glassControl(in: footer).isHiddenOrHasHiddenAncestor)
            XCTAssertTrue(menu.isBordered)
            XCTAssertEqual(menu.bezelStyle, .glass)
            XCTAssertEqual(menu.frame.size, NSSize(width: 38, height: 38))
            XCTAssertEqual(menu.borderShape, .circle)
        } else {
            XCTAssertFalse(modeSlider(in: footer).isHidden)
            XCTAssertTrue(nativeControl(in: footer).isHidden)
            XCTAssertFalse(menu.isBordered)
            XCTAssertEqual(menu.frame.size, NSSize(width: 22, height: 20))
        }
    }

    func testGlassRuntimeTogglePreservesFocusSelectionAndExactBaselineGeometry() throws {
        guard #available(macOS 26.0, *) else { return }
        _ = NSApplication.shared
        let footer = PopoverFooterView()
        footer.frame = NSRect(x: 0, y: 0, width: PopoverStyle.contentWidth,
                              height: PopoverFooterView.preferredHeight)
        footer.update(mode: .low, helperInstalled: true,
                      systemBatteryIconHidden: false, tint: .systemBlue)
        footer.layoutSubtreeIfNeeded()
        let slider = modeSlider(in: footer)
        let native = nativeControl(in: footer)
        let menu = menuButton(in: footer)
        let baselineModeFrame = slider.frame
        let baselineMenuFrame = menu.frame
        let baselineNativeBordered = native.cell?.isBordered
        let baselineKnobOpacity = slider.nativeSelectorOpacityForTest
        let window = NSWindow(contentRect: footer.bounds, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        defer { window.orderOut(nil) }
        window.contentView = footer
        XCTAssertFalse(Settings.liquidGlassEnabled)
        XCTAssertFalse(slider.isHidden)
        XCTAssertTrue(native.isHidden)
        XCTAssertFalse(menu.isBordered)
        XCTAssertEqual(baselineMenuFrame,
                       NSRect(x: footer.bounds.width - 22, y: 42, width: 22, height: 20))
        XCTAssertTrue(window.makeFirstResponder(slider))

        setenv("WATTSON_FORCE_REDUCE_MOTION", "1", 1)
        Settings.liquidGlassEnabled = true
        footer.layoutSubtreeIfNeeded()
        let glass = glassControl(in: footer)
        XCTAssertTrue(slider.isHidden)
        XCTAssertTrue(native.isHidden)
        XCTAssertFalse(glass.isHiddenOrHasHiddenAncestor)
        XCTAssertEqual(glass.selectedModeForTest, .low)
        XCTAssertTrue(window.firstResponder === glass.keyboardFocusView)
        XCTAssertEqual(native.cell?.isBordered, baselineNativeBordered)
        XCTAssertEqual(glass.convert(glass.bounds, to: footer),
                       NSRect(x: 0, y: 36, width: baselineModeFrame.width, height: 38))
        XCTAssertGreaterThan(menu.convert(menu.bounds, to: footer).minX,
                             glass.convert(glass.bounds, to: footer).maxX)
        XCTAssertEqual(menu.bezelStyle, .glass)
        XCTAssertTrue(menu.isBordered)

        setenv("WATTSON_FORCE_REDUCE_MOTION", "0", 1)
        Settings.liquidGlassEnabled = false
        footer.layoutSubtreeIfNeeded()
        XCTAssertFalse(slider.isHidden)
        XCTAssertTrue(native.isHidden)
        XCTAssertTrue(window.firstResponder === slider)
        XCTAssertEqual(slider.selectedIndexForTest, 1)
        XCTAssertEqual(slider.frame, baselineModeFrame)
        XCTAssertEqual(menu.frame, baselineMenuFrame)
        XCTAssertEqual(native.cell?.isBordered, baselineNativeBordered)
        XCTAssertTrue(native.superview === footer)
        XCTAssertTrue(menu.superview === footer)
        XCTAssertEqual(slider.nativeSelectorOpacityForTest, baselineKnobOpacity)
        XCTAssertFalse(menu.isBordered)
        XCTAssertEqual(menu.contentTintColor, PopoverStyle.secondaryText)

        var openedMenu: NSView?
        footer.onShowMenu = { openedMenu = $0 }
        menu.performClick(nil)
        XCTAssertTrue(openedMenu === menu)
    }

    func testGlassToggleDoesNotDuplicatePendingModeRequestsOrLoseRollback() throws {
        guard #available(macOS 26.0, *) else { return }
        let footer = PopoverFooterView()
        footer.update(mode: .auto, helperInstalled: true,
                      systemBatteryIconHidden: false, tint: .systemBlue)
        let slider = modeSlider(in: footer)
        var requests: [EnergyMode] = []
        var completion: ((EnergyMode?) -> Void)?
        footer.onSelect = { mode, callback in
            requests.append(mode)
            completion = callback
        }
        slider.keyDown(with: try keyEvent(124))
        setenv("WATTSON_FORCE_REDUCE_MOTION", "1", 1)
        Settings.liquidGlassEnabled = true
        let glass = glassControl(in: footer)
        XCTAssertEqual(requests, [.low])
        XCTAssertEqual(glass.selectedModeForTest, .low)
        XCTAssertTrue(glass.subviews.compactMap { $0 as? NSButton }.allSatisfy { !$0.isEnabled })
        footer.update(mode: .auto, helperInstalled: true,
                      systemBatteryIconHidden: false, tint: .systemGreen)
        setenv("WATTSON_FORCE_REDUCE_MOTION", "0", 1)
        Settings.liquidGlassEnabled = false
        XCTAssertEqual(slider.selectedIndexForTest, 1)
        completion?(nil)
        XCTAssertEqual(slider.selectedIndexForTest, 0)

        setenv("WATTSON_FORCE_REDUCE_MOTION", "1", 1)
        Settings.liquidGlassEnabled = true
        glass.selectModeForTest(.low)
        setenv("WATTSON_FORCE_REDUCE_MOTION", "0", 1)
        Settings.liquidGlassEnabled = false
        completion?(.low)
        XCTAssertEqual(slider.selectedIndexForTest, 1)
        XCTAssertEqual(requests, [.low, .low])
    }

    func testDisablingGlassStillHonorsReduceMotionAndKeepsMenuFocus() {
        guard #available(macOS 26.0, *) else { return }
        _ = NSApplication.shared
        setenv("WATTSON_FORCE_REDUCE_MOTION", "1", 1)
        let footer = PopoverFooterView()
        footer.frame = NSRect(x: 0, y: 0, width: PopoverStyle.contentWidth,
                              height: PopoverFooterView.preferredHeight)
        let menu = menuButton(in: footer)
        let native = nativeControl(in: footer)
        let baselineNativeBordered = native.cell?.isBordered
        footer.update(mode: .low, helperInstalled: true,
                      systemBatteryIconHidden: false, tint: .systemBlue)
        footer.layoutSubtreeIfNeeded()
        let baselineNativeFrame = native.frame
        let baselineMenuFrame = menu.frame
        let window = NSWindow(contentRect: footer.bounds, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        defer { window.orderOut(nil) }
        window.contentView = footer
        for focused in [native as NSView, menu as NSView] {
            XCTAssertTrue(window.makeFirstResponder(focused))
            for enabled in [true, false, true, false] {
                Settings.liquidGlassEnabled = enabled
                footer.layoutSubtreeIfNeeded()
                XCTAssertTrue(modeSlider(in: footer).isHidden)
                XCTAssertEqual(native.isHiddenOrHasHiddenAncestor, enabled)
                let expectedFocus = enabled && focused === native
                    ? glassControl(in: footer).keyboardFocusView : focused
                XCTAssertTrue(window.firstResponder === expectedFocus)
                XCTAssertEqual(native.selectedModeForTest, .low)
                XCTAssertEqual(menu.isBordered, enabled)
                if !enabled {
                    XCTAssertTrue(native.superview === footer)
                    XCTAssertTrue(menu.superview === footer)
                    XCTAssertEqual(native.frame, baselineNativeFrame)
                    XCTAssertEqual(menu.frame, baselineMenuFrame)
                    XCTAssertEqual(native.cell?.isBordered, baselineNativeBordered)
                }
            }
        }
    }

    func testGlassOperationLayerUsesOneReusableContainerWithoutAnExtraModeSurface() throws {
        guard #available(macOS 26.0, *) else { return }
        let footer = PopoverFooterView()
        footer.frame = NSRect(x: 0, y: 0, width: PopoverStyle.contentWidth,
                              height: PopoverFooterView.preferredHeight)
        let native = nativeControl(in: footer)
        let menu = menuButton(in: footer)
        let baselineNativeBordered = native.cell?.isBordered
        var originalContainer: NSGlassEffectContainerView?
        var originalGroup: NativeGlassModeControl?
        for enabled in [true, false, true] {
            setenv("WATTSON_FORCE_REDUCE_MOTION", enabled ? "1" : "0", 1)
            Settings.liquidGlassEnabled = enabled
            footer.layoutSubtreeIfNeeded()
            // The classic slider owns its own internal materials; only this
            // direct footer child is the new operation-layer container.
            let containers = footer.subviews.compactMap { $0 as? NSGlassEffectContainerView }
            XCTAssertEqual(containers.count, 1)
            let container = try XCTUnwrap(containers.first)
            let content = try XCTUnwrap(container.contentView)
            let surfaces = content.subviews.compactMap { $0 as? NSGlassEffectView }
            XCTAssertEqual(surfaces.count, 0)
            let group = glassControl(in: footer)
            if let originalContainer, let originalGroup {
                XCTAssertTrue(container === originalContainer)
                XCTAssertTrue(group === originalGroup)
            } else {
                originalContainer = container
                originalGroup = group
            }
            XCTAssertEqual(container.spacing, 0)
            XCTAssertEqual(container.isHidden, !enabled)
            XCTAssertTrue(content.layer?.backgroundColor == nil
                          || content.layer?.backgroundColor?.alpha == 0)
            XCTAssertNil(group.layer?.backgroundColor)
            XCTAssertTrue(group.superview === content)
            XCTAssertEqual(descendants(of: footer).filter { $0 === native }.count, 1)
            XCTAssertEqual(descendants(of: footer).filter { $0 === menu }.count, 1)
            if enabled {
                XCTAssertTrue(native.superview === footer)
                XCTAssertTrue(menu.superview === content)
                XCTAssertEqual(container.frame, NSRect(x: 0, y: 36, width: footer.bounds.width, height: 38))
                let modeFrame = group.convert(group.bounds, to: footer)
                let menuFrame = menu.convert(menu.bounds, to: footer)
                XCTAssertEqual(modeFrame, NSRect(x: 0, y: 36, width: footer.bounds.width - 46, height: 38))
                XCTAssertEqual(menuFrame, NSRect(x: footer.bounds.width - 38, y: 36, width: 38, height: 38))
                XCTAssertEqual(menuFrame.minX - modeFrame.maxX, 8)
                XCTAssertEqual(native.cell?.isBordered, baselineNativeBordered)
                XCTAssertEqual(group.subviews.compactMap { $0 as? NSButton }.count, 3)
                XCTAssertEqual(menu.borderShape, .circle)
            } else {
                XCTAssertTrue(native.superview === footer)
                XCTAssertTrue(menu.superview === footer)
            }
        }
    }

    func testGlassButtonsKeepNativeSelectionAccessibilityAndDisabledActions() {
        guard #available(macOS 26.0, *) else { return }
        setenv("WATTSON_FORCE_REDUCE_MOTION", "1", 1)
        let footer = PopoverFooterView()
        Settings.liquidGlassEnabled = true
        let native = glassControl(in: footer)
        native.update(selected: .low, enabledModes: [.auto, .low])
        var requests: [EnergyMode] = []
        native.onSelect = { requests.append($0) }
        let buttons = native.subviews.compactMap { $0 as? NSButton }
        XCTAssertTrue(buttons.allSatisfy { $0.isBordered && $0.bezelStyle == .glass })
        XCTAssertEqual(native.selectedModeForTest, .low)
        XCTAssertEqual(native.accessibilityLabel(), "Power Mode")
        XCTAssertEqual(native.accessibilityValueDescription(), "Low Power")
        XCTAssertEqual(native.accessibilityRole(), .radioGroup)
        XCTAssertEqual(native.accessibilityChildren()?.count, 3)
        XCTAssertFalse(buttons[2].isEnabled)
        native.selectModeForTest(.high)
        XCTAssertFalse(native.accessibilityPerformIncrement())
        XCTAssertTrue(requests.isEmpty)
        XCTAssertEqual(native.selectedModeForTest, .low)
        XCTAssertTrue(native.accessibilityPerformDecrement())
        XCTAssertEqual(requests, [.auto])
        native.update(selected: .auto, enabledModes: [])
        XCTAssertTrue(buttons.allSatisfy { !$0.isEnabled })
        XCTAssertFalse(native.isAccessibilityEnabled())
        XCTAssertFalse(native.accessibilityPerformPress())
        XCTAssertFalse(native.accessibilityPerformIncrement())
        XCTAssertEqual(requests, [.auto])
    }

    func testUnrelatedSettingsDoNotReselectOrRestyleModeControls() {
        let footer = PopoverFooterView()
        footer.update(mode: .low, helperInstalled: true,
                      systemBatteryIconHidden: false, tint: .systemBlue)
        let slider = modeSlider(in: footer)
        let baseline = slider.highlightCallCountForTest
        Settings.showsMenuBarPercentage.toggle()
        Settings.setModule(.flow, visible: false)
        Settings.checksForUpdatesOnLaunch.toggle()
        XCTAssertFalse(slider.isHidden)
        XCTAssertEqual(slider.selectedIndexForTest, 1)
        XCTAssertEqual(slider.highlightCallCountForTest, baseline)
    }

    func testAppearanceObserversDoNotRetainFooter() {
        weak var releasedFooter: PopoverFooterView?
        autoreleasepool {
            let footer = PopoverFooterView()
            releasedFooter = footer
        }
        XCTAssertNil(releasedFooter)
        Settings.liquidGlassEnabled = true
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

    func testNewestIntentReplacesAStaleSliderRequestAcrossControlSwitches() throws {
        let footer = PopoverFooterView()
        footer.update(mode: .auto, helperInstalled: true,
                      systemBatteryIconHidden: false, tint: .systemBlue)
        let slider = modeSlider(in: footer)
        let native = nativeControl(in: footer)
        var completions: [(EnergyMode?) -> Void] = []
        footer.onSelect = { _, completion in completions.append(completion) }

        footer.applyReduceMotionChangeForTest(false)
        slider.keyDown(with: try keyEvent(124))
        XCTAssertEqual(slider.selectedIndexForTest, 1)

        footer.applyReduceMotionChangeForTest(true)
        native.selectModeForTest(.auto)
        footer.applyReduceMotionChangeForTest(false)
        XCTAssertEqual(slider.selectedIndexForTest, 0)

        completions[1](.auto)
        XCTAssertEqual(slider.selectedIndexForTest, 0)
        completions[0](.low)
        XCTAssertEqual(slider.selectedIndexForTest, 0)
    }

    func testFailedIntentRollsBackToLatestAuthoritativeRefresh() {
        let footer = PopoverFooterView()
        footer.update(mode: .low, helperInstalled: true,
                      systemBatteryIconHidden: false, tint: .systemBlue)
        let native = nativeControl(in: footer)
        var completion: ((EnergyMode?) -> Void)?
        footer.onSelect = { _, callback in completion = callback }

        footer.applyReduceMotionChangeForTest(true)
        native.selectModeForTest(.auto)
        footer.update(mode: .auto, helperInstalled: true,
                      systemBatteryIconHidden: false, tint: .systemGreen)
        XCTAssertEqual(native.selectedModeForTest, .auto)

        completion?(nil)
        XCTAssertEqual(native.selectedModeForTest, .auto)
    }

    func testUnchangedTelemetryDoesNotRepeatModeControlLayerWork() {
        let footer = PopoverFooterView()
        footer.applyReduceMotionChangeForTest(false)
        footer.update(mode: .auto, helperInstalled: true,
                      systemBatteryIconHidden: false, tint: .systemBlue)
        let slider = modeSlider(in: footer)
        let baseline = slider.highlightCallCountForTest

        for _ in 0..<1_000 {
            footer.update(mode: .auto, helperInstalled: true,
                          systemBatteryIconHidden: false, tint: .systemBlue)
        }
        XCTAssertEqual(slider.highlightCallCountForTest, baseline)

        footer.update(mode: .auto, helperInstalled: true,
                      systemBatteryIconHidden: false, tint: .systemGreen)
        XCTAssertEqual(slider.highlightCallCountForTest, baseline + 1)
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
