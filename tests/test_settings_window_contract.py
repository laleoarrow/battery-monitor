import os
import pathlib
import plistlib
import shutil
import subprocess
from local_runtime import TemporaryDirectory, bundle_identifier, run
import textwrap
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
WINDOW = ROOT / "MenuBar" / "SettingsWindowController.swift"
SETTINGS = ROOT / "Core" / "Settings.swift"
UPDATE_CHECKER = ROOT / "Core" / "UpdateChecker.swift"
HELPER_CLIENT = ROOT / "Core" / "HelperClient.swift"
SYSTEM_ICON = ROOT / "Core" / "SystemBatteryIcon.swift"
LOGIN_ITEM = ROOT / "Core" / "LoginItemController.swift"
POWER_SNAPSHOT = ROOT / "Core" / "PowerSnapshot.swift"
ENERGY_MODE = ROOT / "Core" / "EnergyMode.swift"
BATTERY_ICON = ROOT / "MenuBar" / "BatteryIcon.swift"
BATTERY_ICON_27 = ROOT / "MenuBar" / "BatteryIcon27.swift"


class SettingsWindowContractTests(unittest.TestCase):
    def test_appkit_window_layout_state_and_release_contract(self):
        if shutil.which("xcrun") is None:
            self.skipTest("Xcode command line tools are unavailable")

        interactive = os.environ.get("WATTSON_RUN_INTERACTION") == "1"
        # macOS 27 reached stress cycle 300 at 178s with assertions passing;
        # keep the full workload and give its cumulative stress a bounded budget.
        runtime_timeout = 300 if interactive else 120
        print(
            f"settings-contract config: interactive={interactive} "
            f"runtime-watchdog={runtime_timeout}s compile-watchdog=120s optimization=Onone",
            flush=True,
        )

        harness = textwrap.dedent(
            r"""
            import AppKit
            import CoreText
            import Darwin
            import Foundation

            let contractStarted = ProcessInfo.processInfo.systemUptime
            func tracePhase(_ phase: String) {
                let elapsed = ProcessInfo.processInfo.systemUptime - contractStarted
                let line = String(format: "settings-contract %.3fs %@\n", elapsed, phase)
                FileHandle.standardError.write(Data(line.utf8))
            }
            tracePhase("start")

            func require(
                _ condition: @autoclosure () -> Bool,
                _ message: String
            ) {
                if !condition() {
                    FileHandle.standardError.write(Data((message + "\n").utf8))
                    exit(1)
                }
            }

            func descendants<T: NSView>(ofType type: T.Type, in view: NSView) -> [T] {
                let local = (view as? T).map { [$0] } ?? []
                return local + view.subviews.flatMap { descendants(ofType: type, in: $0) }
            }

            func button(_ accessibilityLabel: String, in window: NSWindow?) -> NSButton {
                guard let content = window?.contentView,
                      let match = descendants(ofType: NSButton.self, in: content)
                        .first(where: { $0.accessibilityLabel() == accessibilityLabel }) else {
                    FileHandle.standardError.write(Data(("missing button: " + accessibilityLabel + "\n").utf8))
                    exit(1)
                }
                return match
            }

            func label(_ identifier: String, in window: NSWindow?) -> NSTextField {
                guard let content = window?.contentView,
                      let match = descendants(ofType: NSTextField.self, in: content)
                        .first(where: { $0.accessibilityIdentifier() == identifier }) else {
                    FileHandle.standardError.write(Data(("missing label: " + identifier + "\n").utf8))
                    exit(1)
                }
                return match
            }

            func view(_ identifier: String, in window: NSWindow?) -> NSView {
                guard let content = window?.contentView,
                      let match = descendants(ofType: NSView.self, in: content)
                        .first(where: { $0.identifier?.rawValue == identifier }) else {
                    FileHandle.standardError.write(Data(("missing view: " + identifier + "\n").utf8))
                    exit(1)
                }
                return match
            }

            func approximately(_ actual: CGFloat, _ expected: CGFloat) -> Bool {
                abs(actual - expected) <= 1
            }

            func approximately(_ actual: NSRect, _ expected: NSRect) -> Bool {
                approximately(actual.origin.x, expected.origin.x)
                    && approximately(actual.origin.y, expected.origin.y)
                    && approximately(actual.size.width, expected.size.width)
                    && approximately(actual.size.height, expected.size.height)
            }

            func keyEvent(_ keyCode: UInt16, characters: String = "") -> NSEvent {
                guard let event = NSEvent.keyEvent(
                    with: .keyDown,
                    location: .zero,
                    modifierFlags: [],
                    timestamp: 0,
                    windowNumber: 0,
                    context: nil,
                    characters: characters,
                    charactersIgnoringModifiers: characters,
                    isARepeat: false,
                    keyCode: keyCode
                ) else {
                    FileHandle.standardError.write(Data("could not create key event\n".utf8))
                    exit(1)
                }
                return event
            }

            func srgbHex(_ color: NSColor?) -> UInt32? {
                guard let converted = color?.usingColorSpace(.sRGB) else { return nil }
                return UInt32((converted.redComponent * 255).rounded()) << 16
                    | UInt32((converted.greenComponent * 255).rounded()) << 8
                    | UInt32((converted.blueComponent * 255).rounded())
            }

            func isLabelColor(_ color: NSColor?, alpha: CGFloat? = nil) -> Bool {
                guard let converted = color?.usingColorSpace(.sRGB),
                      let label = NSColor.labelColor.usingColorSpace(.sRGB) else { return false }
                return srgbHex(converted) == srgbHex(label)
                    && abs(converted.alphaComponent - (alpha ?? label.alphaComponent)) < 0.001
            }

            func logoArtwork(_ resource: String) -> NSImage {
                guard let url = Bundle.main.url(forResource: resource, withExtension: "png"),
                      let image = NSImage(contentsOf: url) else {
                    fatalError("missing bundled logo fixture: \(resource)")
                }
                return image
            }

            func requireButtonHit(
                _ button: NSButton,
                through content: NSView,
                phase: String
            ) {
                guard let hitTestCoordinateSpace = content.superview else {
                    require(false, "\(phase) content retains a window coordinate space")
                    return
                }
                let center = button.convert(
                    NSPoint(x: button.bounds.midX, y: button.bounds.midY),
                    to: hitTestCoordinateSpace
                )
                let hit = content.hitTest(center)
                require(
                    hit === button,
                    "\(phase) hit testing reaches "
                        + "\(button.accessibilityLabel() ?? "unlabelled button"): "
                        + "center=\(center) wanted=\(ObjectIdentifier(button)) "
                        + "hit=\(String(describing: hit)) "
                        + "hit-label=\(hit?.accessibilityLabel() ?? "none")"
                )
            }

            func requireTrafficLightsClearIdentity(
                controller: SettingsWindowController,
                in window: NSWindow,
                identity: NSView
            ) {
                window.contentView?.superview?.layoutSubtreeIfNeeded()
                let identityInWindow = identity.convert(identity.bounds, to: nil)
                for trafficButton in controller.trafficLightButtonsForTest {
                    require(!trafficButton.isHidden, "native traffic-light button remains visible")
                    let trafficFrame = trafficButton.superview?.convert(
                        trafficButton.frame,
                        to: nil
                    ) ?? trafficButton.frame
                    require(
                        !identityInWindow.intersects(trafficFrame),
                        "identity avoids native traffic-light button"
                    )
                }
            }

            func waitUntil(
                timeout: TimeInterval = 1,
                _ condition: () -> Bool
            ) -> Bool {
                let deadline = Date().addingTimeInterval(timeout)
                while !condition(), Date() < deadline {
                    RunLoop.main.run(
                        mode: .default,
                        before: min(deadline, Date().addingTimeInterval(0.01))
                    )
                }
                return condition()
            }

            func openFDCount() -> Int {
                (try? FileManager.default.contentsOfDirectory(atPath: "/dev/fd").count) ?? -1
            }

            func residentBytes() -> UInt64 {
                var info = mach_task_basic_info()
                var count = mach_msg_type_number_t(
                    MemoryLayout.size(ofValue: info) / MemoryLayout<natural_t>.size
                )
                let status = withUnsafeMutablePointer(to: &info) { pointer in
                    pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                        task_info(
                            mach_task_self_,
                            task_flavor_t(MACH_TASK_BASIC_INFO),
                            $0,
                            &count
                        )
                    }
                }
                return status == KERN_SUCCESS ? UInt64(info.resident_size) : 0
            }

            func maximumUpwardGrowth(_ samples: [UInt64]) -> UInt64 {
                guard var priorLow = samples.first else { return 0 }
                var growth: UInt64 = 0
                for sample in samples.dropFirst() {
                    if sample >= priorLow {
                        growth = max(growth, sample - priorLow)
                    } else {
                        priorLow = sample
                    }
                }
                return growth
            }

            do {
                let mib: UInt64 = 1_024 * 1_024
                let cases: [(name: String, samples: [UInt64], growth: UInt64)] = [
                    ("decreasing", [112, 108, 104, 100], 0),
                    ("cumulative rise", [100, 104, 108, 112], 12),
                    ("drop then rise", [100, 90, 99], 9),
                    ("peak then fall", [100, 109, 101], 9),
                    ("exact eight", [100, 104, 108], 8),
                ]
                for test in cases {
                    let growth = maximumUpwardGrowth(test.samples.map { $0 * mib })
                    require(growth == test.growth * mib
                        && (growth <= 8 * mib) == (test.growth <= 8),
                        "RSS growth policy: " + test.name)
                }
                let observedMacOS27: [UInt64] = [
                    760_872_960, 758_267_904, 758_988_800, 734_773_248, 733_069_312,
                    732_954_624, 728_481_792, 730_038_272, 730_333_184,
                ]
                let observedGrowth = maximumUpwardGrowth(observedMacOS27)
                require(observedGrowth == 1_851_392 && observedGrowth <= 8 * mib,
                    "observed declining macOS 27 RSS retains its smaller upward excursion")
                require(maximumUpwardGrowth([]) == 0
                    && maximumUpwardGrowth([UInt64.max]) == 0
                    && maximumUpwardGrowth([UInt64.max, 0, 8 * mib]) == 8 * mib
                    && maximumUpwardGrowth([0, UInt64.max, 0]) == UInt64.max,
                    "RSS growth subtraction is safe for empty and full-range unsigned samples")
            }
            tracePhase("RSS growth policy regression cases passed")

            func relieveAllocatorPressure() {
                _ = malloc_zone_pressure_relief(nil, 0)
            }

            final class WeakReference<T: AnyObject> {
                weak var value: T?
                init(_ value: T?) { self.value = value }
            }

            final class AttachmentTrackingView: NSView {
                var attachmentCount = 0
                override var acceptsFirstResponder: Bool { true }
                override func viewDidMoveToSuperview() {
                    super.viewDidMoveToSuperview()
                    if superview != nil { attachmentCount += 1 }
                }
            }

            final class SelectionFixtureSection: SettingsSectionController {
                let identifier: String
                var title: String { identifier }
                let sidebarIcon: ModuleIconArtwork.SidebarIcon = .general
                let trackedView = AttachmentTrackingView()
                var view: NSView { trackedView }
                init(_ identifier: String) { self.identifier = identifier }
                func refresh() {}
            }

            enum FixtureError: LocalizedError {
                case rejected
                var errorDescription: String? { "Fixture rejected the update." }
            }

            final class FixtureState {
                var loginState = LoginItemState.enabled
                var batteryHidden: Bool? = false
                var batteryReadStatus: SystemBatteryIconReadStatus = .ready
                var helperAvailable = true
                var increaseContrast = false
                var loginReads: [(LoginItemState) -> Void] = []
                var batteryReads: [(Bool?) -> Void] = []
                var loginWrites: [(Bool, (Result<LoginItemState, Error>) -> Void)] = []
                var batteryWrites: [(Bool, (Bool) -> Void)] = []
                var currentVersion = "3.0.17"
                var updateChecks: [(Result<UpdateCheckOutcome, Error>) -> Void] = []
                var openedUpdateURLs: [URL] = []
                var announcements: [String] = []
            }

            extension SettingsWindowDependencies {
                static func fixture(
                    _ fixture: FixtureState,
                    batteryNotification: Notification.Name
                ) -> SettingsWindowDependencies {
                    SettingsWindowDependencies(
                        loginItemState: { fixture.loginState },
                        refreshLoginItem: { fixture.loginReads.append($0) },
                        setLoginItemEnabled: { enabled, completion in
                            fixture.loginWrites.append((enabled, completion))
                        },
                        systemBatteryIconHidden: { fixture.batteryHidden },
                        helperAvailable: { fixture.helperAvailable },
                        refreshSystemBatteryIcon: { fixture.batteryReads.append($0) },
                        setSystemBatteryIconHidden: { hidden, completion in
                            fixture.batteryWrites.append((hidden, completion))
                        },
                        systemBatteryIconDidChange: batteryNotification,
                        currentVersion: { fixture.currentVersion },
                        checkForUpdates: { fixture.updateChecks.append($0) },
                        openUpdateURL: { url in
                            fixture.openedUpdateURLs.append(url)
                            return true
                        },
                        increaseContrast: { fixture.increaseContrast },
                        announceAccessibility: { fixture.announcements.append($0) },
                        systemBatteryIconReadStatus: { fixture.batteryReadStatus }
                    )
                }
            }

            let app = NSApplication.shared
            let originalAppAppearance = app.appearance
            defer { app.appearance = originalAppAppearance }
            app.appearance = NSAppearance(named: .darkAqua)
            require(app.activationPolicy() != .regular, "fixture must not change activation policy")

            func followNativeKeyLoop(
                in window: NSWindow, from source: NSView, to target: NSView, reverse: Bool = false
            ) {
                require(window.makeFirstResponder(source), "key-loop source accepts focus")
                let linked = reverse ? source.previousKeyView : source.nextKeyView
                require(linked === target, "configured key loop retains the intended control order")
                let eligible = reverse ? source.previousValidKeyView : source.nextValidKeyView
                require(eligible != nil, "native key loop has an eligible destination")
                if app.isFullKeyboardAccessEnabled {
                    require(eligible === target, "full keyboard access includes the intended popup")
                }
                if reverse { window.selectPreviousKeyView(nil) }
                else { window.selectNextKeyView(nil) }
                require(window.firstResponder === eligible,
                    "Tab follows AppKit's native keyboard policy: fullKeyboard=\(app.isFullKeyboardAccessEnabled)")
                // macOS may skip popups when Keyboard Navigation is off. Still
                // exercise their focus/scroll behavior without changing that
                // system preference or overriding production responder policy.
                if eligible !== target {
                    require(!app.isFullKeyboardAccessEnabled,
                        "only the native reduced key loop may skip the intended popup")
                    require(window.makeFirstResponder(target), "explicit popup focus succeeds")
                }
                require(window.firstResponder === target, "target control owns focus before visibility checks")
                tracePhase("key loop: fullKeyboard=\(app.isFullKeyboardAccessEnabled) "
                    + "reverse=\(reverse) nativeReachedTarget=\(eligible === target)")
            }

            let suiteName = ProcessInfo.processInfo.environment["WATTSON_TEST_DEFAULTS_SUITE"]!
            let defaults = UserDefaults(suiteName: suiteName)!
            defaults.removePersistentDomain(forName: suiteName)
            Settings.configureForTest(defaults: defaults)
            defer {
                Settings.resetTestConfiguration()
                defaults.removePersistentDomain(forName: suiteName)
            }

            let fixture = FixtureState()
            let batteryNotification = Notification.Name("FixtureBatteryStateDidChange")
            let dependencies = SettingsWindowDependencies.fixture(
                fixture,
                batteryNotification: batteryNotification
            )
            // Exercise completion state before constructing any window. The
            // focused headless mode exits after these production-view fixtures.
            var batteryCompletionFailures: [String] = []
            let batteryCompletionCases: [(String, Bool?, SystemBatteryIconReadStatus, Bool, Bool?)] = [
                ("failed-write-newer-ready", true, .ready, false, true),
                ("failed-write-newer-failed", nil, .failed(.requestFailed), false, nil),
                ("successful-write-readback-failed", nil, .failed(.requestFailed), true, nil),
                ("failed-status-rejects-old-value", false, .failed(.requestFailed), true, nil),
            ]
            require(app.windows.isEmpty, "battery completion fixture starts without windows")
            for (name, observedHidden, status, succeeded, expectedHidden) in batteryCompletionCases {
                autoreleasepool {
                    let completionFixture = FixtureState()
                    let notification = Notification.Name("BatteryCompletion-" + UUID().uuidString)
                    let completionDependencies = SettingsWindowDependencies.fixture(
                        completionFixture, batteryNotification: notification
                    )
                    guard let section = SettingsWindowController.defaultSections(
                        dependencies: completionDependencies
                    ).first(where: { $0.identifier == "general" }),
                          let checkbox = descendants(ofType: NSButton.self, in: section.view)
                            .first(where: { $0.accessibilityLabel() == "Hide System Battery Icon" }),
                          let detail = descendants(ofType: NSTextField.self, in: section.view)
                            .first(where: { $0.accessibilityIdentifier() == "settings.general.battery.detail" }) else {
                        require(false, "battery completion production controls exist")
                        return
                    }
                    section.refresh()
                    completionFixture.loginReads.removeFirst()(.enabled)
                    completionFixture.batteryReads.removeFirst()(false)
                    require(checkbox.state == .off && checkbox.isEnabled,
                            "battery completion fixture begins with known visible icon")
                    checkbox.performClick(nil)
                    require(completionFixture.batteryWrites.count == 1
                            && completionFixture.batteryWrites[0].0,
                            "battery completion fixture submits one native hide request")
                    completionFixture.batteryHidden = observedHidden
                    completionFixture.batteryReadStatus = status
                    NotificationCenter.default.post(name: notification, object: nil)
                    require(!checkbox.isEnabled, "new observation cannot finish a pending mutation")
                    completionFixture.batteryWrites.removeFirst().1(succeeded)
                    let stateMatches = checkbox.state == (expectedHidden.map { $0 ? .on : .off } ?? .mixed)
                    let enabledMatches = checkbox.isEnabled == (expectedHidden != nil)
                    let detailMatches = expectedHidden != nil || detail.stringValue == "Status unavailable"
                    if !stateMatches || !enabledMatches || !detailMatches {
                        batteryCompletionFailures.append(
                            "\(name): state=\(checkbox.state.rawValue) enabled=\(checkbox.isEnabled) "
                                + "detail=\(detail.stringValue)"
                        )
                    }
                    if let expectedHidden, stateMatches, enabledMatches {
                        checkbox.performClick(nil)
                        require(completionFixture.batteryWrites.count == 1
                                && completionFixture.batteryWrites[0].0 == !expectedHidden,
                                "next click inverts the latest observed authority")
                    } else if !checkbox.isEnabled {
                        checkbox.performClick(nil)
                        require(completionFixture.batteryWrites.isEmpty,
                                "failed readback cannot submit another mutation")
                    }
                    tracePhase("battery completion \(name): "
                        + "\(stateMatches && enabledMatches && detailMatches ? "passed" : "failed")")
                }
            }
            require(app.windows.isEmpty, "battery completion fixtures do not create windows")
            require(batteryCompletionFailures.isEmpty, batteryCompletionFailures.joined(separator: "\n"))
            tracePhase("battery completion no-window fixtures passed")
            if ProcessInfo.processInfo.environment["WATTSON_SETTINGS_BATTERY_COMPLETION_ONLY"] == "1" {
                exit(0)
            }
            autoreleasepool {
                let initialSection = SelectionFixtureSection("initial")
                let otherSection = SelectionFixtureSection("other")
                let selectionController = SettingsWindowController(
                    sections: [initialSection, otherSection],
                    dependencies: dependencies,
                    frameAutosaveName: nil
                )
                require(selectionController.visibleSectionIdentifierForTest == "initial"
                    && initialSection.trackedView.attachmentCount == 1,
                    "native initial selection attaches its page exactly once: "
                        + "attachments=\(initialSection.trackedView.attachmentCount) "
                        + "visible=\(selectionController.visibleSectionIdentifierForTest ?? "none") "
                        + "selectedRow=\(selectionController.sidebarForTest.selectedRow)")
                guard let selectionWindow = selectionController.windowForTest,
                      let host = initialSection.view.superview else {
                    fatalError("initial selection must retain its host and window")
                }
                let constraints = host.constraints.map(ObjectIdentifier.init)
                require(selectionWindow.makeFirstResponder(initialSection.view),
                    "selection fixture page accepts keyboard focus")
                selectionController.tableViewSelectionDidChange(Notification(
                    name: NSTableView.selectionDidChangeNotification,
                    object: selectionController.sidebarForTest
                ))
                require(initialSection.trackedView.attachmentCount == 1
                    && host.constraints.map(ObjectIdentifier.init) == constraints,
                    "repeated same-page notification preserves attachment and constraints")
                require(selectionWindow.firstResponder === initialSection.view,
                    "repeated same-page notification preserves keyboard focus")
                selectionController.selectSectionForTest(identifier: "other")
                require(selectionController.visibleSectionIdentifierForTest == "other"
                    && otherSection.trackedView.attachmentCount == 1,
                    "native selection callback attaches the next page once")
                selectionController.selectSectionForTest(identifier: "initial")
                require(selectionController.visibleSectionIdentifierForTest == "initial"
                    && initialSection.trackedView.attachmentCount == 2,
                    "returning to a page reuses and reattaches it once")
                selectionWindow.contentView?.layoutSubtreeIfNeeded()
                require(approximately(initialSection.view.frame, host.bounds),
                    "deferred section layout fills the host at the normal layout pass")
            }
            let controller = SettingsWindowController(
                sections: SettingsWindowController.defaultSections(dependencies: dependencies),
                dependencies: dependencies,
                frameAutosaveName: nil
            )

            let first = controller.windowForTest
            let glassSwitch = view("settings.appearance.liquid-glass", in: first) as! NSSwitch
            let glassStyle = view("settings.appearance.liquid-glass-style", in: first) as! NSPopUpButton
            let popoverArrow = view("settings.appearance.popover-arrow", in: first) as! NSSwitch
            let transparency = view("settings.appearance.glass-transparency", in: first) as! NSSlider
            let logoPopup = view("settings.appearance.in-app-logo", in: first) as! NSPopUpButton
            let dockPopup = view("settings.appearance.dock-icon", in: first) as! NSPopUpButton
            let colorScheme = view("settings.appearance.color-scheme", in: first) as! NSPopUpButton
            let feedbackButton = button("Send Feedback", in: first)
            let keyLoopEnd: NSView = colorScheme
            require(glassSwitch.state == .off && !Settings.liquidGlassEnabled,
                "global Liquid Glass defaults off")
            require(glassSwitch.accessibilityLabel() == "Global Liquid Glass",
                "appearance switch has an accessible purpose")
            require(glassStyle.itemTitles == ["Standard Glass", "Clear Glass"]
                && glassStyle.selectedItem?.representedObject as? String == "regular",
                "native popup offers the two approved backgrounds with Standard selected by default")
            require(!glassStyle.isEnabled && Settings.liquidGlassStyle == .regular,
                "background selection is disabled while Liquid Glass is off")
            require(!popoverArrow.isEnabled && popoverArrow.state == .on
                && Settings.showPopoverArrow,
                "popup arrow defaults on and stays disabled in Classic")
            require(popoverArrow.accessibilityLabel() == "Show Popover Arrow"
                && popoverArrow.accessibilityHelp()?.contains("closer to the menu bar") == true,
                "popup arrow describes its geometry effect accessibly")
            popoverArrow.state = .off
            popoverArrow.sendAction(popoverArrow.action!, to: popoverArrow.target)
            require(Settings.showPopoverArrow, "disabled popup arrow cannot change preferences")
            popoverArrow.state = .on
            require(!transparency.isEnabled && transparency.minValue == 0 && transparency.maxValue == 100
                && transparency.doubleValue == 100 && transparency.isContinuous,
                "transparency starts at unchanged native glass and stays disabled in Classic")
            transparency.doubleValue = 50
            transparency.sendAction(transparency.action!, to: transparency.target)
            require(Settings.liquidGlassTransparency == 1, "disabled transparency cannot change preferences")
            transparency.doubleValue = 100
            require(glassStyle.accessibilityLabel() == "Popup glass background"
                && glassStyle.accessibilityHelp()?.contains("more transparency") == true,
                "background choice has an accessible label and explains its material difference")
            glassStyle.selectItem(at: 1)
            glassStyle.sendAction(glassStyle.action!, to: glassStyle.target)
            require(Settings.liquidGlassStyle == .regular,
                "a disabled background choice cannot submit an appearance change")
            glassStyle.selectItem(at: 0)
            require(glassSwitch.isDescendant(of: view("settings.general.appearance", in: first))
                && !glassSwitch.isDescendant(of: view("settings.sidebar", in: first)),
                "Liquid Glass belongs to General Appearance, outside sidebar navigation")
            require(glassSwitch.nextKeyView === logoPopup
                && logoPopup.nextKeyView === dockPopup
                && dockPopup.nextKeyView === feedbackButton
                && feedbackButton.nextKeyView === controller.sidebarForTest,
                "appearance keyboard loop reaches feedback and returns to navigation")
            require(logoPopup.itemTitles == ["Color", "Clear"] && logoPopup.isEnabled
                && logoPopup.selectedItem?.representedObject as? String == "color",
                "native logo popup defaults to Color and remains enabled with glass off")
            require(logoPopup.accessibilityLabel() == "In-App Logo"
                && logoPopup.accessibilityHelp()?.contains("Finder and menu bar icons stay unchanged") == true
                && logoPopup.accessibilityHelp()?.contains("static artwork") == true,
                "logo picker explains its scope and static previews accessibly")
            require(logoPopup.itemArray.allSatisfy { $0.image?.size == NSSize(width: 24, height: 24) },
                "both native menu choices have 24-point image previews")
            require(dockPopup.itemTitles == ["Hidden", "Color", "Clear"]
                && dockPopup.isEnabled && Settings.dockIconStyle == .hidden
                && dockPopup.selectedItem?.representedObject as? String == "hidden",
                "Dock icon defaults to Hidden independently of Liquid Glass")
            require(dockPopup.itemArray[0].image == nil
                && dockPopup.itemArray.dropFirst().allSatisfy { $0.image?.size == NSSize(width: 24, height: 24) },
                "Dock Hidden has no artwork and visible choices have static previews")
            let dockHelp = view("settings.appearance.dock-icon.help", in: first) as! NSTextField
            require(dockPopup.accessibilityLabel() == "Dock Icon"
                && dockPopup.accessibilityHelp()?.contains("Restart Wattson to apply. Finder icon stays unchanged.") == true
                && dockPopup.accessibilityHelp()?.contains("Hidden keeps Wattson menu-bar-only.") == true
                && dockHelp.stringValue == "Restart Wattson to apply." && !dockHelp.isHidden,
                "Dock choice shows concise restart help and accessibly explains Finder scope and Hidden behavior")
            if #available(macOS 26, *) {
                require(glassSwitch.isEnabled, "native Liquid Glass is selectable on macOS 26")
            } else {
                require(!glassSwitch.isEnabled, "unsupported OS cannot enable native Liquid Glass")
                require(glassSwitch.accessibilityHelp()?.contains("Requires macOS 26") == true,
                    "unsupported OS explains the compatibility boundary")
            }
            require(first?.isVisible == false, "ordinary contract does not show a window")
            require(first?.isReleasedWhenClosed == false, "retained")
            require(first?.isRestorable == false, "not visibility-restored")
            require(first?.styleMask.contains(.miniaturizable) == true, "reference shell shows minimize")
            require(first?.styleMask.contains(.resizable) == false, "compact shell does not advertise resizing")
            require(first?.styleMask.contains(.fullSizeContentView) == true, "full-height content under titlebar")
            require(first?.titleVisibility == .hidden, "centered window title hidden")
            require(first?.titlebarAppearsTransparent == true, "titlebar is visually unified")
            require(
                first?.contentView?.frame.size == NSSize(width: 720, height: 520),
                "compact content size"
            )
            require(
                first?.contentMinSize == NSSize(width: 720, height: 520)
                    && first?.contentMaxSize == NSSize(width: 720, height: 520),
                "compact composition cannot be distorted by resizing"
            )
            require(first?.appearance == nil, "System theme inherits macOS appearance")
            require(first?.frameAutosaveName.isEmpty == true, "nil autosave skips persistence")
            require(controller.trafficLightButtonsForTest.count == 3, "three native traffic controls")
            require(
                controller.trafficLightButtonsForTest[0]
                    === first?.standardWindowButton(.closeButton)
                    && controller.trafficLightButtonsForTest[1]
                    === first?.standardWindowButton(.miniaturizeButton)
                    && controller.trafficLightButtonsForTest[2]
                    === first?.standardWindowButton(.zoomButton),
                "traffic controls are AppKit's native buttons"
            )
            require(
                first?.standardWindowButton(.zoomButton)?.isEnabled == false,
                "fixed-size native zoom control is disabled"
            )
            require(
                controller.sectionIdentifiersForTest == ["general", "menu-bar-icon", "modules"],
                "section order is General, Display, Modules"
            )
            require(Set(controller.sectionIdentifiersForTest).count == 3, "unique section identifiers")
            require(controller.selectedSectionIdentifierForTest == "general", "general initially selected")
            require(controller.visibleSectionIdentifierForTest == "general", "general initially visible")
            require(controller.contentHostSubviewCountForTest == 1, "one visible page in content host")

            first?.contentView?.layoutSubtreeIfNeeded()
            let sidebar = view("settings.sidebar", in: first)
            let identity = view("settings.sidebar.identity", in: first)
            let trafficSafeArea = view("settings.sidebar.traffic-safe-area", in: first)
            let navigation = view("settings.sidebar.navigation", in: first)
            let divider = view("settings.sidebar.divider", in: first)
            let identityTile = view("settings.sidebar.identity.tile", in: first)
            require(approximately(sidebar.frame.width, 176), "compact sidebar width")
            require(approximately(sidebar.frame.height, 520), "sidebar spans full content height")
            require(approximately(divider.frame.height, 520), "divider spans full content height")
            require(approximately(trafficSafeArea.frame.height, 52), "native traffic-light safe area")
            require(approximately(identity.frame.height, 56), "compact identity row height")
            require(
                approximately(identityTile.frame.width, 32)
                    && approximately(identityTile.frame.height, 32),
                "compact identity tile is 32 points"
            )
            let identityName = descendants(ofType: NSTextField.self, in: identity)
                .first { $0.stringValue == "Wattson" }!
            require(identityName.font == .systemFont(ofSize: 14, weight: .medium),
                "sidebar identity has a restrained 14-point name")
            require(
                identityTile is NSImageView,
                "sidebar identity uses the real packaged application icon"
            )
            require(
                (identityTile as? NSImageView)?.image != nil,
                "sidebar application icon resolves through AppKit"
            )
            require((identityTile as! NSImageView).image?.tiffRepresentation
                == logoArtwork("AppLogoColor").tiffRepresentation,
                "default sidebar uses the packaged Color logo independently of window material")
            require(approximately(identity.frame.maxY, trafficSafeArea.frame.minY), "identity begins below traffic safe area")
            require(approximately(navigation.frame.minX, 12), "compact navigation leading inset")
            require(approximately(sidebar.frame.maxX - navigation.frame.maxX, 12), "compact navigation trailing inset")
            require(approximately(divider.frame.width, 1), "native divider width")
            require(divider.wantsUpdateLayer, "divider resolves semantic color dynamically")
            first?.appearance = NSAppearance(named: .aqua)
            first?.contentView?.layoutSubtreeIfNeeded()
            require(approximately(divider.frame.width, 1), "Aqua divider stays one point")
            first?.appearance = NSAppearance(named: .darkAqua)
            first?.contentView?.layoutSubtreeIfNeeded()
            require(divider.wantsUpdateLayer, "Dark Aqua divider stays dynamic")
            require(approximately(divider.frame.width, 1), "Dark Aqua divider stays one point")
            first?.appearance = nil
            require(approximately(controller.contentHostFrameForTest.width, 503), "compact content width")
            require(controller.sidebarStyleForTest == .sourceList, "source-list sidebar")
            require(controller.sidebarAllowsEmptySelectionForTest == false, "sidebar disallows empty selection")
            require(approximately(controller.sidebarRowHeightForTest, 32), "compact navigation row height")
            require(approximately(controller.sidebarRowGapForTest, 4), "navigation row gap")
            require(
                controller.sidebarRectForRowForTest(2).maxY
                    <= controller.sidebarVisibleRectForTest.maxY + 1,
                "sidebar navigation fits all three rows without scrolling: "
                    + "row=\(controller.sidebarRectForRowForTest(2)) "
                    + "visible=\(controller.sidebarVisibleRectForTest)"
            )
            let navigationLabels = descendants(ofType: NSTextField.self, in: navigation)
            require(
                navigationLabels.filter {
                    ["General", "Display", "Modules"].contains($0.stringValue)
                }.count == 3
                    && navigationLabels.filter {
                        ["General", "Display", "Modules"].contains($0.stringValue)
                    }
                    .allSatisfy { $0.font == .systemFont(ofSize: 13, weight: .regular) },
                "navigation labels use restrained 13-point regular type"
            )
            let iconNavigationLabel = navigationLabels.first {
                $0.stringValue == "Display"
            }
            require(
                (iconNavigationLabel?.attributedStringValue.size().width
                    ?? .greatestFiniteMagnitude)
                    <= (iconNavigationLabel?.frame.width ?? 0) + 1,
                "Display navigation title is fully visible"
            )
            let navigationIcons = ["general", "menu-bar-icon", "modules"].map {
                view("settings.sidebar.icon.\($0)", in: first) as! NSImageView
            }
            let navigationArtwork = ModuleIconArtwork.SidebarIcon.allCases
            for (index, icon) in navigationIcons.enumerated() {
                let cell = controller.sidebarForTest.view(
                    atColumn: 0, row: index, makeIfNecessary: true
                ) as! NSTableCellView
                let title = cell.textField!
                let iconAlignment = icon.superview!.convert(
                    icon.alignmentRect(forFrame: icon.frame), to: cell
                )
                let titleAlignment = title.superview!.convert(
                    title.alignmentRect(forFrame: title.frame), to: cell
                )
                require(approximately(iconAlignment.width, 24)
                    && approximately(iconAlignment.height, 24)
                    && icon.superview === cell && cell.imageView === icon,
                    "sidebar vector icons use an aligned frame without tile enclosures")
                cell.effectiveAppearance.performAsCurrentDrawingAppearance {
                    let ink = title.textColor!.usingColorSpace(.sRGB)!
                    let blue = NSColor.systemBlue.usingColorSpace(.sRGB)!
                    let expectedImage = ModuleIconArtwork.sidebarImage(
                        for: navigationArtwork[index], side: 18, ink: ink,
                        accent: blue, increasedContrast: false)
                    let normalArtwork = expectedImage.tiffRepresentation
                    require(icon.image?.isTemplate == false && icon.contentTintColor == nil
                        && icon.image?.tiffRepresentation == normalArtwork,
                        "each sidebar uses its matching 18-point neutral-and-blue vector artwork")
                    let previousStyle = cell.backgroundStyle
                    cell.backgroundStyle = .emphasized
                    let selectedArtwork = ModuleIconArtwork.sidebarImage(
                        for: navigationArtwork[index], side: 18, ink: .white,
                        accent: .white, increasedContrast: false).tiffRepresentation
                    require(icon.image?.tiffRepresentation == selectedArtwork
                        && selectedArtwork != normalArtwork,
                        "emphasized sidebar artwork becomes white rather than blue on blue")
                    cell.backgroundStyle = previousStyle
                    require(icon.image?.tiffRepresentation == normalArtwork,
                        "leaving selection restores the sidebar's neutral-and-blue artwork")
                }
                require(approximately(titleAlignment.minX - iconAlignment.maxX, 9),
                    "sidebar titles have a consistent nine-point symbol gap")
                require(approximately(iconAlignment.midY, cell.bounds.midY)
                    && iconAlignment.minY >= 3
                    && cell.bounds.maxY - iconAlignment.maxY >= 3,
                    "sidebar symbols keep clear vertical whitespace inside each row")
                require(title.attributedStringValue.size().width <= title.frame.width + 1,
                    "every sidebar title remains fully visible")
            }
            require(
                descendants(ofType: NSView.self, in: view("settings.section.general", in: first))
                    .filter { $0.identifier?.rawValue.hasPrefix("settings.general.row.") == true }
                    .count == 6,
                "General includes four operational rows, appearance and feedback"
            )
            let generalList = view("settings.general.list", in: first)
            let updatesList = view("settings.general.updates.list", in: first)
            for (list, expectedIdentifiers) in [
                (generalList, ["login", "battery"]),
                (updatesList, ["update", "automatic-updates"]),
            ] {
                require(approximately(list.frame.width, 503), "full-width General group")
                require(approximately(list.frame.height, 136), "each operational group is 2 × 68 points")
                require((list as? NSBox)?.cornerRadius == 14, "consistent rounded General groups")
                let rows = descendants(ofType: NSView.self, in: list)
                    .filter { $0.identifier?.rawValue.hasPrefix("settings.general.row.") == true }
                    .sorted { $0.frame.minY > $1.frame.minY }
                require(rows.map { $0.identifier!.rawValue }
                    == expectedIdentifiers.map { "settings.general.row.\($0)" },
                    "startup and update controls belong to separate named groups")
                require(rows.allSatisfy { approximately($0.frame.height, 68) }, "operational rows retain readable height")
                for (index, row) in rows.enumerated() {
                    require(approximately(row.frame.minY, 68 - CGFloat(index) * 68),
                        "each group keeps its top-down row order")
                }
            }
            for (identifier, title) in [
                ("startup", "Startup & Menu Bar"), ("updates", "Updates"),
                ("appearance", "Appearance"), ("support", "Support"),
            ] {
                let groupHeading = view("settings.general.\(identifier).heading", in: first) as! NSTextField
                require(groupHeading.stringValue == title
                    && groupHeading.font == .systemFont(ofSize: 12, weight: .semibold)
                    && (groupHeading.superview as? NSStackView)?.arrangedSubviews.first === groupHeading,
                    "every General group has the same external heading treatment")
            }
            let appearanceSection = view("settings.general.appearance", in: first)
            for (title, inset) in [
                ("Theme", CGFloat(16)), ("Liquid Glass", 16),
                ("In-App Logo", 16), ("Dock Icon", 16),
                ("Popup background", 32), ("Show Popover Arrow", 32), ("Transparency", 32),
            ] {
                let appearanceLabel = descendants(ofType: NSTextField.self, in: appearanceSection)
                    .first { $0.stringValue == title }!
                let row = title == "Liquid Glass"
                    ? view("settings.general.row.appearance", in: first) : appearanceLabel.superview!
                let alignment = appearanceLabel.superview!
                    .convert(appearanceLabel.alignmentRect(forFrame: appearanceLabel.frame), to: row)
                require(approximately(alignment.minX, inset),
                    "appearance peers align and only glass dependencies are indented: \(title)")
            }
            for identifier in ["settings.appearance.background.label",
                               "settings.appearance.popover-arrow.label",
                               "settings.appearance.transparency.label"] {
                let detail = view(identifier, in: first) as! NSTextField
                require(approximately(detail.font?.pointSize ?? -1, 12),
                    "glass dependency labels use readable 12-point type")
            }
            let transparencyValue = descendants(ofType: NSTextField.self, in: transparency.superview!)
                .first { $0.stringValue.hasSuffix("%") }!
            require(approximately(transparencyValue.font?.pointSize ?? -1, 12),
                "glass transparency value matches its readable dependency label")
            let generalScroll = view("settings.general.scroll", in: first) as! NSScrollView
            let generalDocument = generalScroll.documentView!
            require(generalDocument.isFlipped && approximately(generalScroll.documentVisibleRect.minY, 0),
                "General form starts at the top of its scroll viewport")
            require(generalScroll.documentVisibleRect.contains(
                colorScheme.convert(colorScheme.bounds, to: generalDocument)),
                "Theme is visible without scrolling in the normal state")
            glassStyle.scrollToVisible(glassStyle.bounds)
            require(generalScroll.documentVisibleRect.contains(
                glassStyle.convert(glassStyle.bounds, to: generalDocument)),
                "background popup is reachable in the scroll view")
            generalScroll.contentView.scroll(to: .zero)
            require(
                approximately(
                    (view("settings.general.heading", in: first) as? NSTextField)?.font?.pointSize ?? -1,
                    18
                ),
                "General heading uses 18-point type"
            )
            for (index, identifier) in ["login", "battery", "update", "automatic-updates", "feedback"].enumerated() {
                let row = view("settings.general.row.\(identifier)", in: first)
                let symbols = descendants(ofType: NSImageView.self, in: row)
                require(symbols.count == 1 && symbols[0].superview === row
                    && symbols[0].image != nil
                    && approximately(symbols[0].alignmentRect(forFrame: symbols[0].frame).width, 28)
                    && approximately(symbols[0].alignmentRect(forFrame: symbols[0].frame).height, 28),
                    "General uses consistent vector icons without decorative tile enclosures")
                let primary = descendants(ofType: NSTextField.self, in: row)
                    .first { $0.font?.pointSize == 13 }!
                row.effectiveAppearance.performAsCurrentDrawingAppearance {
                    let expected = ModuleIconArtwork.generalImage(
                        for: ModuleIconArtwork.GeneralIcon.allCases[index], side: 20,
                        ink: primary.textColor!.usingColorSpace(.sRGB)!,
                        accent: NSColor.systemBlue.usingColorSpace(.sRGB)!,
                        increasedContrast: false)
                    require(symbols[0].image?.isTemplate == false
                        && symbols[0].contentTintColor == nil
                        && symbols[0].image?.tiffRepresentation == expected.tiffRepresentation,
                        "each General row resolves its matching 20-point vector artwork")
                }
                let alignment = primary.superview!
                    .convert(primary.alignmentRect(forFrame: primary.frame), to: row)
                require(approximately(alignment.minX, 56),
                    "General labels share a compact aligned text column")
            }

            controller.refreshSectionsForTest()

            let login = button("Launch at Login", in: first)
            let battery = button("Hide System Battery Icon", in: first)
            let update = button("Check for Updates", in: first)
            let automaticUpdates = button("Check for Updates on Launch", in: first)
            require(controller.sidebarNextKeyViewForTest === login, "Tab enters first General switch")
            require(controller.lastVisibleSwitchNextKeyViewForTest === controller.sidebarForTest,
                    "General feedback action returns to navigation")
            require(dockPopup.nextKeyView === feedbackButton,
                    "appearance controls reach the feedback action")
            require(feedbackButton.isEnabled && feedbackButton.title == "Report…"
                    && feedbackButton.accessibilityLabel() == "Send Feedback",
                    "feedback uses an enabled native report action")
            require(feedbackButton.becomeFirstResponder(), "feedback accepts keyboard focus")
            let feedbackRow = view("settings.general.row.feedback", in: first)
            require(generalScroll.documentVisibleRect.contains(
                feedbackRow.convert(feedbackRow.bounds, to: generalDocument)),
                "keyboard focus reveals the feedback row")
            _ = feedbackButton.resignFirstResponder()
            generalScroll.contentView.scroll(to: .zero)
            require(login.accessibilityLabel() == "Launch at Login", "login accessibility label")
            require(battery.accessibilityLabel() == "Hide System Battery Icon", "battery accessibility label")
            require(
                login.title.isEmpty && battery.title.isEmpty && automaticUpdates.title.isEmpty,
                "General switches have no clipped visible titles"
            )
            require(
                [login, battery, automaticUpdates].allSatisfy {
                    approximately($0.frame.width, 38) && approximately($0.frame.height, 22)
                },
                "General uses compact toggle switches"
            )
            require(
                approximately(update.frame.width, 88) && approximately(update.frame.height, 28),
                "manual update action uses one compact native button"
            )
            let generalVisibleTitles = Set(
                descendants(ofType: NSTextField.self, in: view("settings.section.general", in: first))
                    .map(\.stringValue)
            )
            let generalPrimaryLabels = descendants(
                ofType: NSTextField.self,
                in: view("settings.section.general", in: first)
            ).filter {
                [
                    "Launch at Login",
                    "Hide System Battery Icon",
                    "Check for Updates",
                    "Check for Updates on Launch",
                ].contains($0.stringValue)
            }
            require(
                generalPrimaryLabels.count == 4
                    && generalPrimaryLabels.allSatisfy {
                        approximately($0.font?.pointSize ?? -1, 13)
                    },
                "General primary labels use 13-point type"
            )
            require(generalVisibleTitles.contains("Launch at Login"), "login primary title remains visible")
            require(
                generalVisibleTitles.contains("Hide System Battery Icon"),
                "battery primary title remains visible"
            )
            require(generalVisibleTitles.contains("Check for Updates"),
                    "manual update primary title remains visible")
            require(generalVisibleTitles.contains("Check for Updates on Launch"),
                    "automatic update primary title remains visible")
            require(
                approximately(label("settings.general.login.detail", in: first).font?.pointSize ?? -1, 11)
                    && approximately(label("settings.general.battery.detail", in: first).font?.pointSize ?? -1, 11)
                    && approximately(label("settings.general.update.detail", in: first).font?.pointSize ?? -1, 11)
                    && approximately(label("settings.general.automatic-updates.detail", in: first).font?.pointSize ?? -1, 11),
                "General detail labels use 11-point type"
            )
            require(
                descendants(ofType: NSView.self, in: view("settings.section.general", in: first))
                    .allSatisfy {
                        $0.identifier?.rawValue != "settings.general.row.native-icon"
                    },
                "icon style is not duplicated in General"
            )
            require(!(login.accessibilityHelp() ?? "").isEmpty, "login accessibility help")
            require(!(battery.accessibilityHelp() ?? "").isEmpty, "battery accessibility help")
            require(!(update.accessibilityHelp() ?? "").isEmpty, "manual update accessibility help")
            require(!(automaticUpdates.accessibilityHelp() ?? "").isEmpty,
                    "automatic update accessibility help")
            require(login.nextKeyView === battery, "login tabs to battery")
            require(battery.nextKeyView === update, "battery tabs to manual update")
            require(update.nextKeyView === automaticUpdates, "manual update tabs to automatic update")
            require(automaticUpdates.nextKeyView === keyLoopEnd,
                    "automatic update returns to sidebar")

            require(automaticUpdates.state == .on && automaticUpdates.isEnabled,
                    "launch update checking defaults on")
            require(
                label("settings.general.update.detail", in: first).stringValue
                    == "Current version 3.0.17",
                "manual update row shows the installed version"
            )
            require(
                label("settings.general.automatic-updates.detail", in: first).stringValue
                    == "Check GitHub when Wattson opens",
                "automatic update row explains its launch behavior"
            )

            automaticUpdates.performClick(nil)
            require(!Settings.checksForUpdatesOnLaunch && automaticUpdates.state == .off,
                    "automatic update option persists off")
            automaticUpdates.performClick(nil)
            require(Settings.checksForUpdatesOnLaunch && automaticUpdates.state == .on,
                    "automatic update option persists on")

            update.performClick(nil)
            require(fixture.updateChecks.count == 1, "manual update check dispatches once")
            require(!update.isEnabled && update.title == "Checking…",
                    "manual update button exposes progress")
            fixture.updateChecks.removeFirst()(.success(.upToDate(currentVersion: "3.0.17")))
            require(update.isEnabled && update.title == "Check Now",
                    "up-to-date result restores the action")
            require(
                label("settings.general.update.detail", in: first).stringValue
                    == "Wattson 3.0.17 is up to date",
                "up-to-date result is visible inline"
            )

            update.performClick(nil)
            fixture.updateChecks.removeFirst()(.failure(FixtureError.rejected))
            require(update.isEnabled && update.title == "Try Again",
                    "failed update check remains retryable")
            require(!label("settings.general.update.error", in: first).isHidden,
                    "failed update check is visible inline")

            update.performClick(nil)
            let availableRelease = UpdateRelease(
                version: "3.0.18",
                pageURL: URL(
                    string: "https://github.com/laleoarrow/battery-monitor/releases/tag/v3.0.18"
                )!
            )
            fixture.updateChecks.removeFirst()(.success(.updateAvailable(availableRelease)))
            require(update.isEnabled && update.title == "View Update",
                    "available update exposes its release action")
            require(
                label("settings.general.update.detail", in: first).stringValue
                    == "Wattson 3.0.18 is available",
                "available version is visible inline"
            )
            update.performClick(nil)
            require(fixture.openedUpdateURLs == [availableRelease.pageURL],
                    "View Update opens the exact trusted release URL")
            fixture.announcements.removeAll()

            require(fixture.loginReads.count == 1, "refresh requests login state once")
            require(fixture.batteryReads.count == 1, "refresh requests battery state once")
            require(login.state == .mixed && !login.isEnabled, "login checking state")
            require(battery.state == .mixed && !battery.isEnabled, "battery checking state")
            require(label("settings.general.login.detail", in: first).stringValue == "Checking…", "login checking detail")
            require(label("settings.general.battery.detail", in: first).stringValue == "Checking…", "battery checking detail")
            require(login.accessibilityHelp()?.contains("Checking…") == true, "login checking accessibility help")
            require(battery.accessibilityHelp()?.contains("Checking…") == true, "battery checking accessibility help")

            fixture.loginReads.removeFirst()(.enabled)
            fixture.batteryReads.removeFirst()(false)
            require(login.state == .on && login.isEnabled, "authoritative login enabled state")
            require(battery.state == .off && battery.isEnabled, "authoritative battery visible state")

            // Shared notifications must distinguish an unfinished read from a
            // real failure, including nil-to-nil transitions across windows.
            fixture.batteryReadStatus = .checking
            fixture.batteryHidden = nil
            NotificationCenter.default.post(name: batteryNotification, object: nil)
            require(battery.state == .mixed && !battery.isEnabled, "shared battery checking disables toggle")
            require(label("settings.general.battery.detail", in: first).stringValue == "Checking…",
                    "shared checking notification does not render a failure")
            fixture.batteryReadStatus = .failed(.preferenceMissing)
            NotificationCenter.default.post(name: batteryNotification, object: nil)
            require(label("settings.general.battery.detail", in: first).stringValue == "Status unavailable",
                    "settled shared failure is distinct from checking")
            fixture.batteryReadStatus = .checking
            NotificationCenter.default.post(name: batteryNotification, object: nil)
            require(label("settings.general.battery.detail", in: first).stringValue == "Checking…",
                    "failed shared state can retry")
            fixture.batteryReadStatus = .ready
            fixture.batteryHidden = false
            NotificationCenter.default.post(name: batteryNotification, object: nil)
            require(battery.state == .off && battery.isEnabled, "shared retry recovers authority")

            controller.refreshSectionsForTest()
            fixture.loginReads.removeFirst()(.unavailable)
            fixture.helperAvailable = false
            fixture.batteryReads.removeFirst()(nil)
            require(login.state == .mixed && !login.isEnabled, "login unavailable state")
            require(
                label("settings.general.login.detail", in: first).stringValue == "Full installer required",
                "login unavailable detail"
            )
            require(login.accessibilityHelp()?.contains("Full installer required") == true, "login unavailable accessibility help")
            require(battery.state == .mixed && !battery.isEnabled, "unknown battery state")
            require(
                label("settings.general.battery.detail", in: first).stringValue == "Full installer required",
                "battery helper-unavailable detail"
            )
            require(battery.accessibilityHelp()?.contains("Full installer required") == true, "battery helper-unavailable accessibility help")

            controller.refreshSectionsForTest()
            fixture.loginReads.removeFirst()(.readFailed)
            fixture.helperAvailable = true
            fixture.batteryReads.removeFirst()(nil)
            require(login.state == .mixed && !login.isEnabled, "login read-failed state")
            require(
                label("settings.general.login.detail", in: first).stringValue == "Status unavailable",
                "login read-failed detail"
            )
            require(battery.state == .mixed && !battery.isEnabled, "battery read-failed state")
            require(
                label("settings.general.battery.detail", in: first).stringValue == "Status unavailable",
                "battery read-failed detail"
            )
            require(battery.accessibilityHelp()?.contains("Status unavailable") == true, "battery read-failed accessibility help")

            controller.refreshSectionsForTest()
            fixture.loginReads.removeFirst()(.enabled)
            fixture.batteryReads.removeFirst()(false)

            login.performClick(nil)
            require(fixture.loginWrites.count == 1, "login mutation dispatched once")
            require(fixture.loginWrites[0].0 == false, "login mutation carries requested state")
            require(!login.isEnabled, "login disabled during mutation")
            fixture.loginState = .notRegistered
            fixture.loginWrites.removeFirst().1(.success(.notRegistered))
            require(login.state == .off && login.isEnabled, "successful login mutation renders readback")

            login.performClick(nil)
            require(fixture.loginWrites.count == 1, "second login mutation dispatched once")
            require(fixture.loginWrites[0].0 == true, "second login mutation inverts authority")
            fixture.loginState = .unavailable
            fixture.loginWrites.removeFirst().1(.failure(FixtureError.rejected))
            require(login.state == .mixed && !login.isEnabled, "failed login mutation renders degraded authority")
            require(
                label("settings.general.login.detail", in: first).stringValue == "Full installer required",
                "failed login mutation renders authoritative unavailable detail"
            )
            require(!label("settings.general.login.error", in: first).isHidden, "inline login error")
            require(login.accessibilityHelp()?.contains("Fixture rejected") == true, "login error accessibility help")
            require(fixture.announcements.count == 1, "one login error announcement")

            battery.performClick(nil)
            require(fixture.batteryWrites.count == 1, "battery mutation dispatched once")
            require(fixture.batteryWrites[0].0 == true, "battery mutation carries requested state")
            require(!battery.isEnabled, "battery disabled during mutation")
            fixture.batteryHidden = true
            fixture.batteryWrites.removeFirst().1(true)
            require(battery.state == .on && battery.isEnabled, "successful battery mutation renders readback")

            battery.performClick(nil)
            require(fixture.batteryWrites.count == 1, "second battery mutation dispatched once")
            require(fixture.batteryWrites[0].0 == false, "second battery mutation inverts authority")
            fixture.batteryWrites.removeFirst().1(false)
            require(battery.state == .on && battery.isEnabled, "failed battery mutation restores authority")
            require(!label("settings.general.battery.error", in: first).isHidden, "inline battery error")
            require(battery.accessibilityHelp()?.contains("couldn’t update") == true, "battery error accessibility help")
            require(fixture.announcements.count == 2, "one battery error announcement")

            // A newer refresh may begin while this page is waiting on its
            // write. Completing the write must not re-enable a checking control.
            fixture.batteryReadStatus = .ready
            battery.performClick(nil)
            fixture.batteryReadStatus = .checking
            NotificationCenter.default.post(name: batteryNotification, object: nil)
            fixture.batteryWrites.removeFirst().1(true)
            require(!battery.isEnabled
                    && label("settings.general.battery.detail", in: first).stringValue == "Checking…",
                    "write completion respects a newer pending shared read")
            fixture.batteryReadStatus = .ready
            fixture.batteryHidden = false
            NotificationCenter.default.post(name: batteryNotification, object: nil)
            require(battery.state == .off, "battery notification reloads shared authority")
            require(label("settings.general.battery.error", in: first).isHidden, "battery authority clears inline error")
            require(battery.accessibilityHelp()?.contains("couldn’t update") == false, "battery authority clears error accessibility help")

            controller.selectSidebarRowForTest(1)
            require(
                controller.selectedSectionIdentifierForTest == "menu-bar-icon",
                "Icon is the second section"
            )
            require(
                controller.visibleSectionIdentifierForTest == "menu-bar-icon",
                "selection delegate shows Display"
            )
            require(controller.contentHostSubviewCountForTest == 1, "icon page keeps one hosted view")
            first?.contentView?.layoutSubtreeIfNeeded()

            let iconPage = view("settings.section.menu-bar-icon", in: first)
            let iconHeading = view("settings.menu-bar-icon.heading", in: first)
            let iconSubtitle = view("settings.menu-bar-icon.subtitle", in: first)
            let iconGroup = view("settings.menu-bar-icon.group", in: first)
            let iconPreviewGroup = view("settings.menu-bar-icon.preview-group", in: first)
            let iconButtons = descendants(ofType: NSButton.self, in: iconPage)
                .filter { $0.identifier?.rawValue.hasPrefix("settings.menu-bar-icon.style.") == true }
            let wattsonStyle = button("Wattson", in: first)
            let macOS26Style = button("macOS 26", in: first)
            let macOS27Style = button("macOS 27", in: first)
            let styleChoices: [(style: Settings.MenuBarIconStyle, button: NSButton, suffix: String, title: String)] = [
                (.wattson, wattsonStyle, "wattson", "Wattson"),
                (.native, macOS26Style, "macos", "macOS 26"),
                (.native27, macOS27Style, "macos27", "macOS 27"),
            ]
            let percentagePopup = view("settings.menu-bar-icon.percentage", in: first) as! NSPopUpButton
            let iconStates = descendants(ofType: NSView.self, in: iconPage)
                .filter { $0.identifier?.rawValue.hasPrefix("settings.menu-bar-icon.state.") == true }
            let iconPreviews = descendants(ofType: NSImageView.self, in: iconPage)
                .filter { $0.identifier?.rawValue.hasPrefix("settings.menu-bar-icon.preview.") == true }
            let iconStateLabels = descendants(ofType: NSTextField.self, in: iconPage)
                .filter { $0.identifier?.rawValue.hasPrefix("settings.menu-bar-icon.state-label.") == true }
            let percentagePreviews = descendants(ofType: NSTextField.self, in: iconPage)
                .filter { $0.identifier?.rawValue.hasPrefix("settings.menu-bar-icon.percentage.") == true }
            let expectedStateLabels = [
                "Battery", "Full", "Charging", "Low", "Low + AC", "Saver", "Saver + AC",
            ]
            let previewStates = MenuBarIconPreviewState.allCases
            require(
                approximately((iconHeading as? NSTextField)?.font?.pointSize ?? -1, 18)
                    && approximately((iconSubtitle as? NSTextField)?.font?.pointSize ?? -1, 13),
                "Display retains the compact Settings heading hierarchy"
            )
            require(iconButtons.count == 3 && iconStates.count == 21 && iconPreviews.count == 21,
                "Display presents each style once with all seven real runtime previews")
            require(iconStateLabels.map(\.stringValue) == expectedStateLabels,
                "one shared header names the seven aligned runtime states")
            require(previewStates.map(\.visibleLabel) == expectedStateLabels,
                "preview fixtures use the same visible production order")
            require(approximately(iconPreviewGroup.frame.width, 503)
                && iconButtons.allSatisfy { approximately($0.frame.width, iconGroup.bounds.width) },
                "the preview group retains the existing 503-point width with full-width native option rows")
            let iconRects = iconButtons.map { $0.convert($0.bounds, to: iconPage) }
            require(zip(iconRects, iconRects.dropFirst()).allSatisfy {
                    !$0.intersects($1) && approximately($0.minX, $1.minX)
                }
                && iconRects.allSatisfy { iconPage.bounds.insetBy(dx: -1, dy: -1).contains($0) },
                "style rows align without overlap or content clipping")
            require(percentagePopup.itemTitles == ["Off", "On"]
                && percentagePopup.accessibilityLabel() == "Show percentage",
                "percentage is a separate labelled compact Off/On preference")
            require(percentagePreviews.count == 21,
                "three retained style rows keep all seven percentage objects")
            for choice in styleChoices {
                let values = percentagePreviews.filter {
                    $0.identifier?.rawValue.hasPrefix("settings.menu-bar-icon.percentage.\(choice.suffix).") == true
                }.map(\.stringValue)
                require(values == ["75%", "100%", "72%", "10%", "20%", "42%", "42%"],
                    "each retained percentage label keeps the real runtime value: " + choice.suffix)
            }
            require(descendants(ofType: NSTextField.self, in: iconPage).allSatisfy {
                $0.identifier?.rawValue.hasPrefix("settings.menu-bar-icon.title.") != true
            }, "native radio titles have no duplicate text labels")

            let nativeRadioReference = NSButton(
                radioButtonWithTitle: "Reference", target: nil, action: nil
            )
            nativeRadioReference.controlSize = .small
            nativeRadioReference.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            func verifyNativeStyleControls() {
                for choice in styleChoices {
                    let suffix = choice.suffix
                    let styleButton = choice.button
                    let expectedTitle = choice.title
                    require(styleButton.cell is NSButtonCell && styleButton.title == expectedTitle
                        && styleButton.accessibilityRole() == .radioButton
                        && styleButton.focusRingType == nativeRadioReference.focusRingType
                        && styleButton.controlSize == nativeRadioReference.controlSize
                        && styleButton.focusRingType != .none,
                        "style uses a real titled native radio cell and system focus: " + suffix)
                    guard let cell = styleButton.cell as? NSButtonCell,
                          let font = styleButton.font else {
                        require(false, "native style retains its button cell and font")
                        return
                    }
                    let radioRect = cell.imageRect(forBounds: styleButton.bounds)
                    let radioInGroup = styleButton.convert(radioRect, to: iconPreviewGroup)
                    require(!radioRect.isEmpty && radioInGroup.minX >= 8
                        && iconPreviewGroup.bounds.insetBy(dx: -0.5, dy: -0.5).contains(radioInGroup),
                        "native radio artwork keeps an eight-point margin inside its group: "
                            + "\(suffix) radio=\(radioInGroup) group=\(iconPreviewGroup.bounds)")
                    let titleRect = cell.titleRect(forBounds: styleButton.bounds)
                    let titleSize = (styleButton.title as NSString).size(withAttributes: [.font: font])
                    let firstState = iconStates.first {
                        $0.identifier?.rawValue == "settings.menu-bar-icon.state.\(suffix).battery"
                    }!
                    let previewStart = firstState.convert(firstState.bounds, to: styleButton).minX
                    let previewInGroup = firstState.convert(firstState.bounds, to: iconPreviewGroup)
                    require(approximately(previewInGroup.minX, 86),
                        "the native radio inset preserves the existing preview column position")
                    require(font.pointSize == nativeRadioReference.font?.pointSize && styleButton.alignment == .left
                        && titleSize.width <= titleRect.width + 0.5
                        && titleSize.height <= titleRect.height + 0.5
                        && styleButton.bounds.insetBy(dx: -0.5, dy: -0.5).contains(titleRect)
                        && titleRect.maxX <= previewStart + 0.5,
                        "native title stays readable before every preview column: "
                            + "\(suffix) title=\(titleRect) size=\(titleSize) previewStart=\(previewStart)")
                }
            }
            verifyNativeStyleControls()

            func verifyDisplayPreviews(showingPercentage: Bool) {
                first?.contentView?.layoutSubtreeIfNeeded()
                require(percentagePreviews.filter { !$0.isHidden }.count == (showingPercentage ? 14 : 0),
                    "On exposes exactly fourteen external labels; macOS 27 embeds its numbers")
                for (index, previewState) in previewStates.enumerated() {
                    let header = iconStateLabels[index]
                    let headerFrame = header.convert(header.bounds, to: iconPage)
                    let headerTextSize = header.attributedStringValue.size()
                    let headerInk = CTLineGetBoundsWithOptions(
                        CTLineCreateWithAttributedString(header.attributedStringValue),
                        .useGlyphPathBounds
                    )
                    let headerTextOriginX = headerFrame.midX - headerTextSize.width / 2
                    require(headerTextSize.width <= header.frame.width + 1,
                        "shared runtime-state label is readable: " + header.stringValue)
                    for choice in styleChoices {
                        let suffix = "\(choice.suffix).\(previewState.identifierSuffix)"
                        let state = iconStates.first {
                            $0.identifier?.rawValue == "settings.menu-bar-icon.state.\(suffix)"
                        }!
                        let image = iconPreviews.first {
                            $0.identifier?.rawValue == "settings.menu-bar-icon.preview.\(suffix)"
                        }!
                        let percentage = percentagePreviews.first {
                            $0.identifier?.rawValue == "settings.menu-bar-icon.percentage.\(suffix)"
                        }!
                        let stateFrame = state.convert(state.bounds, to: iconPage)
                        require(approximately(headerFrame.midX, stateFrame.midX),
                            "shared column header aligns with all style rows: " + suffix)
                        require(headerTextSize.width <= stateFrame.width + 0.5
                            && headerTextOriginX + headerInk.minX >= stateFrame.minX - 0.5
                            && headerTextOriginX + headerInk.maxX <= stateFrame.maxX + 0.5,
                            "shared column header ink fits its corresponding preview column: " + suffix)
                        require((image.image?.size.width ?? 0) > 0
                            && (image.image?.size.height ?? 0) > 0
                            && approximately(image.bounds.size.width, image.image!.size.width)
                            && approximately(image.bounds.size.height, image.image!.size.height)
                            && image.imageScaling == .scaleNone,
                            "each style keeps its real renderer size without scaling: " + suffix)
                        let glyphInState = image.convert(image.bounds, to: state)
                        require(state.bounds.insetBy(dx: -0.5, dy: -0.5).contains(glyphInState),
                            "the complete production glyph fits its column: " + suffix)
                        let externalPercentage = showingPercentage && choice.style != .native27
                        require(percentage.isHidden == !externalPercentage,
                            "percentage is external only for Wattson and macOS 26: " + suffix)
                        if choice.style == .native27 {
                            require(approximately(image.bounds.width, 25) && approximately(image.bounds.height, 16),
                                "macOS 27 retains its natural canvas for embedded numbers: " + suffix)
                        }
                        if externalPercentage {
                            // NSTextField adds transparent frame padding outside its
                            // alignment rect. Measure text and glyph ink inside the
                            // actual column rather than treating that padding as ink.
                            let textInState = percentage.superview!.convert(
                                percentage.alignmentRect(forFrame: percentage.frame), to: state
                            )
                            let textSize = percentage.attributedStringValue.size()
                            let textInk = CTLineGetBoundsWithOptions(
                                CTLineCreateWithAttributedString(percentage.attributedStringValue),
                                .useGlyphPathBounds
                            )
                            require(textSize.width <= textInState.width + 0.5
                                && textSize.height <= textInState.height + 0.5
                                && textInk.minX >= -0.5 && textInk.maxX <= textInState.width + 0.5
                                && state.bounds.insetBy(dx: -0.5, dy: -0.5).contains(textInState)
                                && textInState.maxX <= glyphInState.minX + 0.5,
                                "percentage stays fully visible to the left of its icon: "
                                    + "\(suffix) text=\(textInState) glyph=\(glyphInState) state=\(state.bounds)")
                        }
                    }
                }
            }
            verifyDisplayPreviews(showingPercentage: true)
            let expectedWattsonKeys: [(Int, Bool, BatteryIcon.TintRole)] = [
                (75, false, .template),
                (100, true, .template),
                (72, true, .charging),
                (10, false, .lowBattery),
                (20, true, .lowBattery),
                (42, false, .lowPower),
                (42, true, .lowPower),
            ]
            let expectedNativeKeys: [(Int, Bool, BatteryIcon.TintRole)] = [
                (75, false, .template),
                (100, true, .template),
                (72, true, .template),
                (10, false, .template),
                (20, true, .template),
                (42, false, .lowPower),
                (42, true, .lowPower),
            ]
            let testAppearance = NSAppearance(named: .aqua)!
            for (index, previewState) in previewStates.enumerated() {
                let wattsonKey = BatteryIcon.renderKey(
                    for: previewState.snapshot,
                    mode: previewState.mode,
                    pressed: false,
                    style: .wattson,
                    appearance: testAppearance,
                    increasedContrast: false
                )
                let expectedWattson = expectedWattsonKeys[index]
                require(
                    wattsonKey.percent == expectedWattson.0
                        && wattsonKey.showsBolt == expectedWattson.1
                        && wattsonKey.tintRole == expectedWattson.2,
                    "Wattson preview fixture matches its real tint and bolt semantics: "
                        + previewState.visibleLabel
                )

                let nativeKey = BatteryIcon.renderKey(
                    for: previewState.snapshot,
                    mode: previewState.mode,
                    pressed: false,
                    style: .native,
                    appearance: testAppearance,
                    increasedContrast: false
                )
                let expectedNative = expectedNativeKeys[index]
                require(
                    nativeKey.percent == expectedNative.0
                        && nativeKey.showsBolt == expectedNative.1
                        && nativeKey.tintRole == expectedNative.2,
                    "macOS preview fixture matches its exact fill and power bolt: "
                        + previewState.visibleLabel
                )
            }
            require(iconGroup.isAccessibilityElement() && iconGroup.accessibilityRole() == .radioGroup,
                "style choices expose one accessibility radio group")
            require(!(iconGroup.accessibilityLabel() ?? "").isEmpty
                && !(iconGroup.accessibilityHelp() ?? "").isEmpty,
                "style group has a useful accessible name and help")
            require(iconButtons.allSatisfy {
                $0.accessibilityRole() == .radioButton && !($0.accessibilityHelp() ?? "").isEmpty
            }, "each style exposes accessible radio semantics")
            require(wattsonStyle.state == .on && macOS26Style.state == .off
                && macOS27Style.state == .off && percentagePopup.indexOfSelectedItem == 1,
                "existing Wattson-with-percentage default selects its two independent preferences")
            require((wattsonStyle.accessibilityValue() as? NSNumber)?.boolValue == true
                && (macOS26Style.accessibilityValue() as? NSNumber)?.boolValue == false
                && (macOS27Style.accessibilityValue() as? NSNumber)?.boolValue == false,
                "accessibility values identify the selected style")
            require(controller.sidebarNextKeyViewForTest === wattsonStyle
                && wattsonStyle.nextKeyView === macOS26Style
                && macOS26Style.nextKeyView === macOS27Style
                && macOS27Style.nextKeyView === percentagePopup
                && percentagePopup.nextKeyView === controller.sidebarForTest,
                "Tab visits all three styles and percentage choice before returning to navigation")

            let legacyPreviews = iconPreviews.filter {
                $0.identifier?.rawValue.hasPrefix("settings.menu-bar-icon.preview.macos27.") != true
            }
            let embeddedPreviews = iconPreviews.filter {
                $0.identifier?.rawValue.hasPrefix("settings.menu-bar-icon.preview.macos27.") == true
            }
            func previewPixels(_ imageView: NSImageView) -> Data {
                guard let image = imageView.image,
                      let tiff = image.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiff),
                      let png = bitmap.representation(using: .png, properties: [:]) else {
                    require(false, "renderer preview can be rasterized for a pixel comparison")
                    return Data()
                }
                return png
            }
            Settings.showsMenuBarPercentage = false
            let legacyImages = legacyPreviews.map { $0.image! }
            let legacyPixels = legacyPreviews.map(previewPixels)
            let embeddedOffPixels = embeddedPreviews.map(previewPixels)
            require(legacyImages.count == 14 && embeddedOffPixels.count == 7,
                "the UI separates fourteen existing glyphs from seven embedded-number glyphs")
            Settings.showsMenuBarPercentage = true
            verifyDisplayPreviews(showingPercentage: true)
            let embeddedOnImages = embeddedPreviews.map { $0.image! }
            let embeddedOnPixels = embeddedPreviews.map(previewPixels)
            require(zip(embeddedOffPixels, embeddedOnPixels).allSatisfy { $0 != $1 },
                "each macOS 27 preview actually renders its embedded number when enabled")
            require(zip(legacyPreviews, legacyImages).allSatisfy { $0.image === $1 }
                && legacyPreviews.map(previewPixels) == legacyPixels,
                "percentage changes preserve the identities and pixels of the fourteen existing glyphs")
            NotificationCenter.default.post(name: Settings.didChange, object: nil,
                userInfo: [Settings.changeUserInfoKey: Settings.Change.menuBarPercentage])
            require(zip(embeddedPreviews, embeddedOnImages).allSatisfy { $0.image === $1 },
                "repeated percentage refreshes retain macOS 27 images when visibility is unchanged")
            Settings.showsMenuBarPercentage = false
            verifyDisplayPreviews(showingPercentage: false)
            require(embeddedPreviews.map(previewPixels) == embeddedOffPixels
                && zip(legacyPreviews, legacyImages).allSatisfy { $0.image === $1 }
                && legacyPreviews.map(previewPixels) == legacyPixels,
                "disabling percentage restores embedded glyph pixels without replacing existing styles")
            Settings.showsMenuBarPercentage = true

            // Begin with the other style so this also verifies a persisted write
            // rather than only the default fallback value.
            macOS26Style.accessibilityPerformPress()
            for choice in styleChoices {
                let style = choice.style
                let styleButton = choice.button
                for showsPercentage in [false, true] {
                    styleButton.accessibilityPerformPress()
                    percentagePopup.selectItem(at: showsPercentage ? 1 : 0)
                    percentagePopup.sendAction(percentagePopup.action!, to: percentagePopup.target)
                    require(Settings.menuBarIconStyle == style
                        && Settings.showsMenuBarPercentage == showsPercentage
                        && defaults.string(forKey: "menubar.iconStyle") == style.rawValue
                        && defaults.bool(forKey: "menubar.showsPercentage") == showsPercentage,
                        "style and percentage retain all six persisted combinations")
                    require(styleButton.state == .on && iconButtons.filter { $0.state == .on }.count == 1,
                        "independent preference changes keep exactly one selected style")
                    verifyDisplayPreviews(showingPercentage: showsPercentage)
                }
            }
            Settings.setMenuBarAppearance(iconStyle: .wattson, showsPercentage: true)

            require(first?.makeFirstResponder(wattsonStyle) == true
                && first?.firstResponder === wattsonStyle,
                "first native style accepts actual window keyboard focus")
            followNativeKeyLoop(in: first!, from: wattsonStyle, to: macOS26Style)
            followNativeKeyLoop(in: first!, from: macOS26Style, to: wattsonStyle, reverse: true)
            followNativeKeyLoop(in: first!, from: macOS26Style, to: macOS27Style)
            followNativeKeyLoop(in: first!, from: macOS27Style, to: macOS26Style, reverse: true)
            followNativeKeyLoop(in: first!, from: macOS27Style, to: percentagePopup)
            followNativeKeyLoop(in: first!, from: percentagePopup, to: macOS27Style, reverse: true)

            for choice in styleChoices where choice.style != .wattson {
                let help = (choice.button.accessibilityHelp() ?? "").lowercased()
                require(help.contains(choice.title.lowercased()) && help.contains("battery")
                    && help.contains("menu-bar"),
                    "each native-style description identifies its own macOS version")
                require(!help.contains("control center") && !help.contains("private")
                    && !help.contains("copied"),
                    "style help makes no private-art or copied-asset claim")
            }

            func displayViewIdentities() -> [ObjectIdentifier] {
                descendants(ofType: NSView.self, in: iconPage).filter {
                    $0.identifier?.rawValue.hasPrefix("settings.menu-bar-icon.") == true
                }.map(ObjectIdentifier.init)
            }
            let retainedDisplayViews = displayViewIdentities()
            require(first?.makeFirstResponder(percentagePopup) == true, "percentage popup accepts focus")
            Settings.setMenuBarAppearance(iconStyle: .native27, showsPercentage: false)
            require(macOS27Style.state == .on && percentagePopup.indexOfSelectedItem == 0
                && first?.firstResponder === percentagePopup,
                "external notifications synchronize both choices without stealing popup focus")
            verifyDisplayPreviews(showingPercentage: false)
            require(first?.makeFirstResponder(wattsonStyle) == true, "style accepts focus before external change")
            Settings.showsMenuBarPercentage = true
            Settings.menuBarIconStyle = .wattson
            require(wattsonStyle.state == .on && percentagePopup.indexOfSelectedItem == 1
                && first?.firstResponder === wattsonStyle,
                "separate external preference notifications retain style focus")
            verifyDisplayPreviews(showingPercentage: true)
            let currentDisplayViews = displayViewIdentities()
            require(currentDisplayViews == retainedDisplayViews,
                "style and percentage updates reuse all Display controls and previews")

            wattsonStyle.keyDown(with: keyEvent(125))
            require(Settings.menuBarIconStyle == .native && Settings.showsMenuBarPercentage,
                "Down Arrow selects macOS 26 while preserving percentage")
            macOS26Style.keyDown(with: keyEvent(125))
            require(Settings.menuBarIconStyle == .native27 && Settings.showsMenuBarPercentage,
                "Down Arrow reaches macOS 27 while preserving percentage")
            macOS27Style.keyDown(with: keyEvent(125))
            require(Settings.menuBarIconStyle == .wattson && Settings.showsMenuBarPercentage,
                "Down Arrow wraps through all three styles")
            wattsonStyle.keyDown(with: keyEvent(126))
            require(Settings.menuBarIconStyle == .native27 && Settings.showsMenuBarPercentage,
                "Up Arrow wraps to the last style")
            macOS27Style.keyDown(with: keyEvent(126))
            require(Settings.menuBarIconStyle == .native && Settings.showsMenuBarPercentage,
                "Up Arrow returns to macOS 26")
            macOS26Style.keyDown(with: keyEvent(126))
            require(Settings.menuBarIconStyle == .wattson && Settings.showsMenuBarPercentage,
                "Up Arrow returns to Wattson")
            wattsonStyle.keyDown(with: keyEvent(124))
            require(Settings.menuBarIconStyle == .native && Settings.showsMenuBarPercentage,
                "Right Arrow selects the next style without changing percentage")
            macOS26Style.keyDown(with: keyEvent(124))
            require(Settings.menuBarIconStyle == .native27 && Settings.showsMenuBarPercentage,
                "Right Arrow reaches the third style without changing percentage")
            macOS27Style.keyDown(with: keyEvent(123))
            require(Settings.menuBarIconStyle == .native && Settings.showsMenuBarPercentage,
                "Left Arrow returns to macOS 26 without changing percentage")
            macOS26Style.keyDown(with: keyEvent(123))
            require(Settings.menuBarIconStyle == .wattson && Settings.showsMenuBarPercentage,
                "Left Arrow returns to Wattson without changing percentage")
            Settings.showsMenuBarPercentage = false
            wattsonStyle.keyDown(with: keyEvent(119))
            require(Settings.menuBarIconStyle == .native27 && !Settings.showsMenuBarPercentage,
                "End selects macOS 27 while preserving icon-only mode")
            macOS27Style.keyDown(with: keyEvent(115))
            require(Settings.menuBarIconStyle == .wattson && !Settings.showsMenuBarPercentage,
                "Home selects Wattson while preserving icon-only mode")
            Settings.menuBarIconStyle = .native27
            wattsonStyle.keyDown(with: keyEvent(49, characters: " "))
            require(Settings.menuBarIconStyle == .wattson && !Settings.showsMenuBarPercentage
                && iconButtons.filter { $0.state == .on }.count == 1,
                "Space activates only the focused style and preserves one selection")

            controller.selectSidebarRowForTest(2)
            require(controller.selectedSectionIdentifierForTest == "modules", "modules selectable")
            require(controller.visibleSectionIdentifierForTest == "modules", "selection delegate swaps page")
            require(controller.contentHostSubviewCountForTest == 1, "page swap keeps one hosted view")
            first?.contentView?.layoutSubtreeIfNeeded()
            let modulePage = view("settings.section.modules", in: first)
            let moduleHeading = view("settings.modules.heading", in: first)
            let moduleSubtitle = view("settings.modules.subtitle", in: first)
            let moduleList = view("settings.modules.list", in: first)
            let moduleScroll = view("settings.modules.scroll", in: first) as! NSScrollView
            let topProcessCount = view("settings.modules.top-process-count", in: first) as! NSPopUpButton
            let topProcessesCompact = view("settings.modules.top-processes-compact", in: first) as! NSPopUpButton
            let restoreModuleOrder = button("Restore Default Order", in: first)
            func verifyRestoreModuleOrderLayout() {
                let restoreRect = restoreModuleOrder.convert(restoreModuleOrder.bounds, to: modulePage)
                let subtitleRect = moduleSubtitle.convert(moduleSubtitle.bounds, to: modulePage)
                let viewportRect = moduleScroll.contentView.convert(
                    moduleScroll.contentView.bounds, to: modulePage
                )
                require(!restoreModuleOrder.isHiddenOrHasHiddenAncestor && restoreModuleOrder.isEnabled,
                    "Restore Default Order stays visible and enabled")
                require(modulePage.bounds.insetBy(dx: -0.5, dy: -0.5).contains(restoreRect)
                    && !restoreRect.intersects(subtitleRect)
                    && !restoreRect.intersects(viewportRect)
                    && !subtitleRect.intersects(viewportRect),
                    "restore action fits the subtitle row without clipping or covering content")
                require(restoreModuleOrder.frame.width + 1 >= restoreModuleOrder.intrinsicContentSize.width
                    && moduleSubtitle.frame.width + 1 >= moduleSubtitle.intrinsicContentSize.width,
                    "restore action and module subtitle remain fully readable")
            }
            require(restoreModuleOrder.identifier?.rawValue == "settings.modules.restore-default-order"
                && restoreModuleOrder.accessibilityIdentifier() == "settings.modules.restore-default-order",
                "restore action has a stable view and accessibility identifier")
            verifyRestoreModuleOrderLayout()
            require(
                approximately(moduleHeading.frame.height, moduleHeading.intrinsicContentSize.height),
                "Modules heading keeps intrinsic height"
            )
            require(
                approximately((moduleHeading as? NSTextField)?.font?.pointSize ?? -1, 18),
                "Modules heading uses 18-point type"
            )
            require(
                approximately(moduleSubtitle.frame.height, moduleSubtitle.intrinsicContentSize.height),
                "Modules subtitle keeps intrinsic height"
            )
            require(
                approximately((moduleSubtitle as? NSTextField)?.font?.pointSize ?? -1, 11),
                "Modules subtitle uses 11-point type"
            )
            require(
                approximately(moduleSubtitle.frame.minY
                    - moduleScroll.convert(moduleScroll.bounds, to: modulePage).maxY, 10),
                "Modules viewport starts 10 points below subtitle"
            )
            let moduleRows = descendants(ofType: NSView.self, in: modulePage)
                .filter { $0.identifier?.rawValue.hasPrefix("settings.modules.row.") == true }
            let moduleIcons = descendants(ofType: NSImageView.self, in: modulePage)
                .filter { $0.identifier?.rawValue.hasPrefix("settings.modules.icon.") == true }
            require(moduleRows.count == 6, "one row per module including top energy processes")
            require(moduleIcons.count == 6 && moduleIcons.allSatisfy { $0.image != nil },
                "all six module symbols resolve to native images")
            func moduleGeometryDescription() -> String {
                "rows=\(moduleRows.map { $0.frame.width }) page=\(modulePage.bounds) "
                    + "scroll=\(moduleScroll.frame) clip=\(moduleScroll.contentView.frame) "
                    + "document=\(moduleScroll.documentView!.frame) "
                    + "scroller=\(moduleScroll.scrollerStyle.rawValue) "
                    + "preferred=\(NSScroller.preferredScrollerStyle.rawValue)"
            }
            // AppKit may apply the preferred legacy scroller after the page is
            // attached. Settle its clip and document before measuring the rows.
            let moduleLayoutSettled = waitUntil {
                first?.contentView?.layoutSubtreeIfNeeded()
                moduleScroll.tile()
                moduleScroll.contentView.layoutSubtreeIfNeeded()
                moduleScroll.documentView?.layoutSubtreeIfNeeded()
                let viewportWidth = moduleScroll.contentView.bounds.width
                return approximately(moduleScroll.documentView!.frame.width, viewportWidth)
                    && moduleRows.allSatisfy { approximately($0.frame.width, viewportWidth - 40) }
            }
            tracePhase("module-layout \(moduleGeometryDescription())")
            require(moduleLayoutSettled, "module clip/document layout settles: \(moduleGeometryDescription())")
            let availableModuleWidth = moduleScroll.contentView.bounds.width - 40
            require(moduleRows.allSatisfy { approximately($0.frame.width, availableModuleWidth) },
                "full-width module rows match the native viewport and two 20-point optical insets: "
                    + moduleGeometryDescription())
            require(moduleRows.allSatisfy { approximately($0.frame.height, 72) }, "six compact module rows retain their existing geometry")
            require(moduleScroll.documentView!.frame.height > moduleScroll.contentView.bounds.height
                && moduleScroll.hasVerticalScroller && !moduleScroll.drawsBackground,
                "six rows scroll within the compact window on a clear background")
            require(topProcessCount.itemArray.map(\.tag) == Array(1...10)
                && topProcessCount.selectedItem?.tag == 3 && topProcessCount.isEnabled,
                "top process count defaults to three and offers one through ten")
            require(topProcessCount.accessibilityLabel() == "Number of Processes Shown"
                && topProcessCount.accessibilityIdentifier() == "settings.modules.top-process-count",
                "top process count has stable accessibility identity and purpose")
            require(topProcessesCompact.accessibilityLabel() == "Compact view"
                && topProcessesCompact.accessibilityIdentifier() == "settings.modules.top-processes-compact"
                && topProcessesCompact.accessibilityHelp() == "Hide CPU and idle wakeup details."
                && topProcessesCompact.selectedItem?.tag == 0 && topProcessesCompact.isEnabled,
                "compact process view defaults off and has an accessible purpose")
            require(topProcessesCompact.itemArray.map(\.title) == ["Off", "On"]
                && topProcessesCompact.itemArray.map(\.tag) == [0, 1],
                "compact view offers explicit Off and On choices")
            require(topProcessesCompact.controlSize == .small
                && topProcessesCompact.controlSize == topProcessCount.controlSize
                && topProcessesCompact.font == topProcessCount.font,
                "compact view matches the process count popup's small control size and type")
            topProcessesCompact.selectItem(withTag: 1)
            topProcessesCompact.sendAction(topProcessesCompact.action!, to: topProcessesCompact.target)
            require(Settings.topProcessesCompact && topProcessesCompact.selectedItem?.tag == 1,
                "compact process popup writes shared settings in place")
            topProcessesCompact.selectItem(withTag: 0)
            topProcessesCompact.sendAction(topProcessesCompact.action!, to: topProcessesCompact.target)
            require(!Settings.topProcessesCompact && topProcessesCompact.selectedItem?.tag == 0,
                "compact popup Off choice restores detailed rows")
            topProcessesCompact.selectItem(withTag: 1)
            topProcessesCompact.sendAction(topProcessesCompact.action!, to: topProcessesCompact.target)
            topProcessCount.selectItem(withTag: 7)
            topProcessCount.sendAction(topProcessCount.action!, to: topProcessCount.target)
            require(Settings.topProcessCount == 7, "process count control writes shared settings")
            Settings.setModule(.topProcesses, visible: false)
            require(!topProcessCount.isEnabled && topProcessCount.selectedItem?.tag == 7
                && !topProcessesCompact.isEnabled && topProcessesCompact.selectedItem?.tag == 1,
                "hiding the module disables its display options while retaining their choices")
            topProcessesCompact.selectItem(withTag: 0)
            topProcessesCompact.sendAction(topProcessesCompact.action!, to: topProcessesCompact.target)
            require(Settings.topProcessesCompact, "disabled compact popup cannot change saved preferences")
            let runtimeHandleForCount = view("settings.modules.reorder.runtime", in: first)
            let topProcessSwitch = button(Settings.Module.topProcesses.title, in: first)
            require(runtimeHandleForCount.nextKeyView === topProcessSwitch,
                "a disabled process count is skipped in the keyboard loop")
            Settings.topProcessCount = 4
            Settings.topProcessesCompact = false
            require(topProcessCount.selectedItem?.tag == 4,
                "process count observes external changes while disabled")
            require(topProcessesCompact.selectedItem?.tag == 0 && !topProcessesCompact.isEnabled,
                "compact view observes external changes while its module is hidden")
            Settings.setModule(.topProcesses, visible: true)
            require(topProcessCount.isEnabled && topProcessCount.selectedItem?.tag == 4
                && topProcessesCompact.isEnabled && topProcessesCompact.selectedItem?.tag == 0,
                "showing the module restores both retained display controls")
            require(runtimeHandleForCount.nextKeyView === topProcessCount
                && topProcessCount.nextKeyView === topProcessesCompact
                && topProcessesCompact.nextKeyView === topProcessSwitch,
                "count then compact view appear before the module switch in keyboard order")
            Settings.topProcessCount = 3
            let initialModuleOffset = moduleScroll.contentView.bounds.origin
            require(first?.makeFirstResponder(topProcessCount) == true,
                "the count selector accepts keyboard focus")
            first?.contentView?.layoutSubtreeIfNeeded()
            require(moduleScroll.contentView.bounds.origin.y > initialModuleOffset.y,
                "focusing the process count reveals the bottom of the module list")
            verifyRestoreModuleOrderLayout()
            let countRect = topProcessCount.convert(topProcessCount.bounds, to: modulePage)
            let visibleModuleViewport = moduleScroll.contentView.convert(
                moduleScroll.contentView.bounds, to: modulePage
            )
            require(visibleModuleViewport.contains(countRect),
                "the focused count stays inside the viewport below the fixed header")
            require(first?.makeFirstResponder(topProcessesCompact) == true,
                "the compact process popup accepts keyboard focus")
            first?.contentView?.layoutSubtreeIfNeeded()
            let compactRect = topProcessesCompact.convert(topProcessesCompact.bounds, to: modulePage)
            let compactViewport = moduleScroll.contentView.convert(moduleScroll.contentView.bounds, to: modulePage)
            require(compactViewport.contains(compactRect) && compactViewport.contains(countRect),
                "compact popup focus reveals both display options without clipping")
            require(view("settings.modules.top-processes-compact", in: first) === topProcessesCompact,
                "display preference changes retain the original compact popup")
            moduleScroll.contentView.scroll(to: initialModuleOffset)
            moduleScroll.reflectScrolledClipView(moduleScroll.contentView)
            first?.contentView?.layoutSubtreeIfNeeded()
            require(moduleIcons.allSatisfy {
                let alignment = $0.alignmentRect(forFrame: $0.frame)
                return approximately(alignment.width, 28) && approximately(alignment.height, 28)
            }, "consistent native icon size")
            let rowYs = moduleRows.map { $0.frame.minY }.sorted()
            require(zip(rowYs, rowYs.dropFirst()).allSatisfy { approximately($1 - $0, 72) },
                "module rows form one contiguous list")
            for row in moduleRows {
                let labels = descendants(ofType: NSTextField.self, in: row)
                let isProcessRow = row.identifier?.rawValue == "settings.modules.row.topProcesses"
                require(labels.count == (isProcessRow ? 3 : 2) && labels.allSatisfy {
                    $0.frame.width + 1 >= $0.intrinsicContentSize.width
                }, "module names and descriptions fit without truncation")
                let primary = labels.first { $0.font?.pointSize == 13 }!
                require(labels.filter { $0 !== primary }.allSatisfy {
                    approximately($0.font?.pointSize ?? -1, 11)
                },
                    "module descriptions retain a quiet 11-point secondary role")
                let alignment = primary.superview!
                    .convert(primary.alignmentRect(forFrame: primary.frame), to: row)
                require(approximately(alignment.minX, 56),
                    "Modules uses the same native symbol and label alignment as General")
            }
            let modulePrimaryLabels = descendants(ofType: NSTextField.self, in: modulePage)
                .filter { Settings.Module.allCases.map(\.title).contains($0.stringValue) }
            require(
                modulePrimaryLabels.count == 6
                    && modulePrimaryLabels.allSatisfy {
                        approximately($0.font?.pointSize ?? -1, 13)
                    },
                "module primary labels use 13-point type"
            )

            for module in Settings.Module.allCases {
                let moduleButton = button(module.title, in: first)
                require(moduleButton.state == .on, "module defaults visible: \(module.rawValue)")
                require(moduleButton.accessibilityLabel() == module.title, "module accessibility label")
                require(moduleButton.title.isEmpty, "module switch has no clipped visible title")
                require(
                    approximately(moduleButton.frame.width, 38)
                        && approximately(moduleButton.frame.height, 22),
                    "module uses compact toggle: \(module.rawValue)"
                )
            }
            let flow = button(Settings.Module.flow.title, in: first)
            require(controller.sidebarNextKeyViewForTest === flow, "Tab enters first Modules switch")
            let lastModuleHandle = view("settings.modules.reorder.topProcesses", in: first)
            require(lastModuleHandle.nextKeyView === restoreModuleOrder
                && restoreModuleOrder.nextKeyView === controller.sidebarForTest,
                "Modules key loop reaches Restore Default Order before returning to navigation")
            flow.performClick(nil)
            require(!Settings.isModuleVisible(.flow), "module writes through shared Settings store")
            Settings.setModule(.flow, visible: true)
            require(flow.state == .on, "module observes shared Settings store")
            let runtimeModule = button(Settings.Module.runtime.title, in: first)
            runtimeModule.performClick(nil)
            require(!Settings.isModuleVisible(.runtime), "runtime switch writes shared module state")
            Settings.setModule(.runtime, visible: true)
            require(runtimeModule.state == .on, "runtime switch observes menu/shared changes")

            // Reordering changes presentation, never the identity or visibility
            // of a module. Exercise the real controls and their keyboard/AX path.
            tracePhase("module-order")
            let originalModuleRows = Dictionary(uniqueKeysWithValues: moduleRows.map {
                ($0.identifier!.rawValue, ObjectIdentifier($0))
            })
            let originalModuleButtons = Dictionary(uniqueKeysWithValues: Settings.Module.allCases.map {
                ($0, ObjectIdentifier(button($0.title, in: first)))
            })
            func displayedModuleOrder() -> [Settings.Module] {
                moduleRows.sorted {
                    $0.convert($0.bounds, to: modulePage).midY
                        > $1.convert($1.bounds, to: modulePage).midY
                }.compactMap {
                    Settings.Module(rawValue: $0.identifier!.rawValue
                        .replacingOccurrences(of: "settings.modules.row.", with: ""))
                }
            }
            func settleModuleOrder() {
                first?.contentView?.layoutSubtreeIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.25))
                first?.contentView?.layoutSubtreeIfNeeded()
            }
            for module in Settings.Module.allCases {
                let handle = view("settings.modules.reorder.\(module.rawValue)", in: first)
                let toggle = button(module.title, in: first)
                require(handle.acceptsFirstResponder, "reorder handle supports keyboard focus")
                require(handle.accessibilityLabel() == "Reorder \(module.title)",
                    "reorder handle has a distinct accessible label")
                let handleRect = handle.convert(handle.bounds, to: modulePage)
                let toggleRect = toggle.convert(toggle.bounds, to: modulePage)
                require(handleRect.minX >= toggleRect.maxX && handleRect.width >= 24
                    && handleRect.height >= 24, "drag target is separate from the switch and easy to hit")
            }
            Settings.setModule(.history, visible: false)
            Settings.moduleOrder = Array(Settings.Module.allCases.reversed())
            settleModuleOrder()
            require(displayedModuleOrder() == Settings.moduleOrder,
                "Settings shows the externally saved order including the disabled module")
            require(!Settings.isModuleVisible(.history), "moving a hidden module keeps it disabled")
            require(moduleRows.allSatisfy {
                originalModuleRows[$0.identifier!.rawValue] == ObjectIdentifier($0)
            }, "reordering retains all six row instances")
            require(Settings.Module.allCases.allSatisfy {
                originalModuleButtons[$0] == ObjectIdentifier(button($0.title, in: first))
            }, "reordering retains switches and their stable identities")
            button(Settings.Module.flow.title, in: first).performClick(nil)
            require(!Settings.isModuleVisible(.flow) && !Settings.isModuleVisible(.history),
                "a moved switch still changes its own module")
            let visibilityBeforeRestore = Settings.Module.allCases.map { Settings.isModuleVisible($0) }
            var restoreChanges: [Settings.Change] = []
            let restoreObserver = NotificationCenter.default.addObserver(
                forName: Settings.didChange, object: nil, queue: .main
            ) { note in
                if let change = note.userInfo?[Settings.changeUserInfoKey] as? Settings.Change {
                    restoreChanges.append(change)
                }
            }
            restoreModuleOrder.performClick(nil)
            settleModuleOrder()
            require(Settings.moduleOrder == Settings.Module.allCases
                && displayedModuleOrder() == Settings.Module.allCases
                && restoreChanges == [.moduleOrder],
                "Restore Default Order saves and displays the original order once")
            require(Settings.Module.allCases.map { Settings.isModuleVisible($0) } == visibilityBeforeRestore,
                "restoring order preserves every module visibility choice")
            require(moduleRows.allSatisfy {
                originalModuleRows[$0.identifier!.rawValue] == ObjectIdentifier($0)
            } && Settings.Module.allCases.allSatisfy {
                originalModuleButtons[$0] == ObjectIdentifier(button($0.title, in: first))
            }, "restoring order retains all module rows and switches")
            restoreModuleOrder.performClick(nil)
            require(restoreModuleOrder.isEnabled && restoreChanges == [.moduleOrder],
                "restoring an already-default order stays enabled and is a no-op")
            NotificationCenter.default.removeObserver(restoreObserver)
            Settings.setModule(.flow, visible: true)
            Settings.setModule(.history, visible: true)
            settleModuleOrder()
            let flowHandle = view("settings.modules.reorder.flow", in: first)
            first?.makeFirstResponder(controller.sidebarForTest)
            first?.makeFirstResponder(flowHandle)
            require(controller.moduleReorderShowsKeyboardFocusForTest(.flow),
                "keyboard focus acquisition shows the reorder cue")
            let handleCenter = flowHandle.convert(
                NSPoint(x: flowHandle.bounds.midX, y: flowHandle.bounds.midY), to: nil)
            func handleMouseEvent(_ type: NSEvent.EventType, at point: NSPoint) -> NSEvent {
                NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 1,
                    windowNumber: first!.windowNumber, context: nil, eventNumber: 1,
                    clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)!
            }
            var observedDragStarts: [NSEvent] = []
            controller.observeModuleReorderDragStartForTest(.flow) { observedDragStarts.append($0) }
            let handleDown = handleMouseEvent(.leftMouseDown, at: handleCenter)
            flowHandle.mouseDown(with: handleDown)
            require(first?.firstResponder === flowHandle
                && !controller.moduleReorderShowsKeyboardFocusForTest(.flow),
                "mouse focus remains keyboard reachable without a persistent blue frame")
            flowHandle.mouseDragged(with: handleMouseEvent(.leftMouseDragged,
                at: NSPoint(x: handleCenter.x + 3, y: handleCenter.y)))
            require(observedDragStarts.isEmpty, "sub-threshold pointer movement does not initiate a drag")
            let outsideHandle = NSPoint(x: -100, y: -100)
            let handleDrag = handleMouseEvent(.leftMouseDragged, at: outsideHandle)
            flowHandle.mouseDragged(with: handleDrag)
            require(observedDragStarts.count == 1 && observedDragStarts[0] === handleDown
                && observedDragStarts[0].type == .leftMouseDown
                && observedDragStarts[0].locationInWindow == handleCenter,
                "drag initiation receives the original mouse-down object even when the first move is outside")
            flowHandle.mouseDragged(with: handleDrag)
            flowHandle.mouseUp(with: handleMouseEvent(.leftMouseUp, at: outsideHandle))
            require(observedDragStarts.count == 1
                && !controller.moduleReorderShowsKeyboardFocusForTest(.flow),
                "one press starts at most one drag and mouse completion keeps the focus cue quiet")
            flowHandle.keyDown(with: keyEvent(126))
            require(controller.moduleReorderShowsKeyboardFocusForTest(.flow),
                "keyboard input after mouse interaction restores the focus cue")
            flowHandle.mouseDown(with: handleDown)
            flowHandle.mouseUp(with: handleMouseEvent(.leftMouseUp, at: outsideHandle))
            flowHandle.mouseDragged(with: handleDrag)
            require(observedDragStarts.count == 1, "mouse-up clears the pending drag event")
            flowHandle.mouseDown(with: handleDown)
            controller.selectSectionForTest(identifier: "general")
            controller.selectSectionForTest(identifier: "modules")
            flowHandle.mouseDragged(with: handleDrag)
            require(observedDragStarts.count == 1, "leaving the page clears the pending drag event")
            controller.observeModuleReorderDragStartForTest(.flow, handler: nil)
            require(Settings.moduleOrder == Settings.Module.allCases
                && Settings.Module.allCases.allSatisfy { Settings.isModuleVisible($0) },
                "event-forwarding checks do not simulate a drop or modify modules")
            func verifyModuleDragPreflight(buttons: [Int], expectsStart: Bool) {
                let savedOrder = Settings.moduleOrder
                let visibility = Settings.Module.allCases.map { Settings.isModuleVisible($0) }
                var reads = 0
                var starts: [NSEvent] = []
                var changes = 0
                let observer = NotificationCenter.default.addObserver(
                    forName: Settings.didChange, object: nil, queue: .main
                ) { _ in changes += 1 }
                controller.configureModuleDragPreflightForTest(buttons: {
                    let value = buttons[min(reads, buttons.count - 1)]
                    reads += 1
                    return value
                }, onStart: { starts.append($0) })
                defer {
                    controller.configureModuleDragPreflightForTest(buttons: nil, onStart: nil)
                    NotificationCenter.default.removeObserver(observer)
                }
                let down = handleMouseEvent(.leftMouseDown, at: handleCenter)
                flowHandle.mouseDown(with: down)
                flowHandle.mouseDragged(with: handleDrag)
                flowHandle.mouseUp(with: handleMouseEvent(.leftMouseUp, at: outsideHandle))
                require(reads == buttons.count, "drag preflight checks live button state at the expected stages")
                require(starts.count == (expectsStart ? 1 : 0),
                    "released pointer does not reach the native session boundary")
                if expectsStart {
                    require(starts[0] === down && starts[0].type == .leftMouseDown,
                        "held pointer retains the original mouse-down event at the native boundary")
                }
                require(controller.moduleDragStateIsClearForTest
                    && moduleRows.allSatisfy { $0.alphaValue == 1 },
                    "preflight rejection leaves no pending session, preview or dimmed row")
                require(Settings.moduleOrder == savedOrder && changes == 0
                    && Settings.Module.allCases.map { Settings.isModuleVisible($0) } == visibility,
                    "preflight checks preserve order and visibility without notifications")
                require(!controller.moduleReorderShowsKeyboardFocusForTest(.flow),
                    "preflight rejection does not leave a mouse-origin focus frame")
            }
            verifyModuleDragPreflight(buttons: [0], expectsStart: false)
            verifyModuleDragPreflight(buttons: [2], expectsStart: false)
            first?.makeFirstResponder(controller.sidebarForTest)
            first?.makeFirstResponder(flowHandle)
            var orderNotifications = 0
            let orderObserver = NotificationCenter.default.addObserver(
                forName: Settings.didChange, object: nil, queue: .main
            ) { note in
                if note.userInfo?[Settings.changeUserInfoKey] as? Settings.Change == .moduleOrder {
                    orderNotifications += 1
                }
            }
            flowHandle.keyDown(with: keyEvent(126))
            require(Settings.moduleOrder == Settings.Module.allCases && orderNotifications == 0,
                "moving above the first row is a no-op")
            flowHandle.keyDown(with: keyEvent(125))
            settleModuleOrder()
            require(Settings.moduleOrder == [.ring, .flow, .lanes, .history, .runtime, .topProcesses]
                && displayedModuleOrder() == Settings.moduleOrder && orderNotifications == 1,
                "Down Arrow moves the focused module once and saves once")
            require(first?.firstResponder === flowHandle,
                "keyboard reordering preserves focus on the same handle")
            let moveUp = flowHandle.accessibilityCustomActions()?.first { $0.name == "Move Up" }
            require(moveUp?.handler?() == true, "VoiceOver Move Up invokes the same reorder path")
            settleModuleOrder()
            require(Settings.moduleOrder == Settings.Module.allCases && orderNotifications == 2,
                "accessibility move restores the initial order without changing visibility")
            require(flowHandle.accessibilityCustomActions()?.contains { $0.name == "Move Up" } == false,
                "first row does not advertise an unavailable Move Up action")
            require(Settings.Module.allCases.allSatisfy { Settings.isModuleVisible($0) },
                "keyboard and accessibility order changes preserve all module switches")
            let finalHandle = view("settings.modules.reorder.topProcesses", in: first)
            let ringMetrics = view("settings.modules.ring-metrics", in: first)
            require(finalHandle.accessibilityCustomActions()?.contains { $0.name == "Move Down" } == false,
                "last row does not advertise an unavailable Move Down action")
            require(controller.sidebarNextKeyViewForTest === button(Settings.Module.flow.title, in: first)
                && button(Settings.Module.flow.title, in: first).nextKeyView === flowHandle
                && flowHandle.nextKeyView === ringMetrics
                && ringMetrics.nextKeyView === button(Settings.Module.ring.title, in: first)
                && finalHandle.nextKeyView === restoreModuleOrder
                && restoreModuleOrder.nextKeyView === controller.sidebarForTest,
                "key loop follows module order and the restore action before navigation")
            NotificationCenter.default.removeObserver(orderObserver)

            // Increase Contrast is a live, appearance-only adaptation. The
            // reference palette and geometry remain exact while it is off;
            // posting AppKit's accessibility display notification updates the
            // retained General and Modules pages without reopening the window.
            let moduleBoxes = [moduleList as! NSBox]
            require((generalList as? NSBox)?.borderWidth == 1, "normal General border is one point")
            require(srgbHex((generalList as? NSBox)?.borderColor) == 0x363838, "normal General border keeps reference sRGB")
            require(moduleBoxes.allSatisfy { $0.borderWidth == 1 }, "normal module list border is one point")
            require(moduleBoxes.allSatisfy { srgbHex($0.borderColor) == 0x363838 }, "normal module list keeps reference sRGB")
            verifyNativeStyleControls()
            require(controller.selectedRowStrokeWidthForTest == 0, "normal selected row has no extra outline")
            require(isLabelColor(controller.selectedRowFillColorForTest, alpha: 0.07),
                "normal sidebar selection has a restrained neutral fill")
            require(controller.toggleTrackStrokeWidthForTest("Hide System Battery Icon") == 1, "normal off toggle outline is one point")
            require(srgbHex(controller.toggleTrackColorForTest("Hide System Battery Icon")) == 0x2E3032, "normal off toggle keeps reference track sRGB")
            require(srgbHex(controller.toggleTrackStrokeColorForTest("Hide System Battery Icon")) == 0x363838, "normal off toggle keeps reference outline sRGB")
            require(approximately(divider.frame.width, 1), "normal divider geometry remains one point")
            require(controller.dividerVisualStrokeWidthForTest == 1, "normal divider stroke is one point")
            require(srgbHex(controller.dividerColorForTest) == 0x363838, "normal divider keeps reference sRGB")

            fixture.increaseContrast = true
            NSWorkspace.shared.notificationCenter.post(
                name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                object: NSWorkspace.shared
            )
            first?.contentView?.layoutSubtreeIfNeeded()
            require((generalList as? NSBox)?.borderWidth == 2, "increased contrast strengthens General border")
            require(srgbHex((generalList as? NSBox)?.borderColor) == 0x8D949A, "increased contrast brightens General border")
            require(moduleBoxes.allSatisfy { $0.borderWidth == 2 }, "increased contrast strengthens the module list border")
            require(moduleBoxes.allSatisfy { srgbHex($0.borderColor) == 0x8D949A }, "increased contrast brightens the module list border")
            verifyNativeStyleControls()
            require(displayViewIdentities() == retainedDisplayViews, "contrast refresh reuses every Display control and preview")
            verifyDisplayPreviews(showingPercentage: false)
            require(controller.selectedRowStrokeWidthForTest == 2, "increased contrast outlines selected row")
            require(isLabelColor(controller.selectedRowFillColorForTest, alpha: 0.14),
                "increased contrast strengthens the neutral sidebar fill")
            require(isLabelColor(controller.selectedRowStrokeColorForTest),
                "increased contrast outlines sidebar selection in the semantic label color")
            require(controller.toggleTrackStrokeWidthForTest("Hide System Battery Icon") == 2, "increased contrast strengthens off toggle outline")
            require(srgbHex(controller.toggleTrackColorForTest("Hide System Battery Icon")) == 0x575B5F, "increased contrast brightens off toggle track")
            require(srgbHex(controller.toggleTrackStrokeColorForTest("Hide System Battery Icon")) == 0xB9C0C6, "increased contrast brightens off toggle outline")
            require(approximately(divider.frame.width, 1), "increased contrast does not shift reference geometry")
            require(controller.dividerVisualStrokeWidthForTest == 2, "increased contrast strengthens divider stroke")
            require(srgbHex(controller.dividerColorForTest) == 0x8D949A, "increased contrast brightens divider")

            fixture.increaseContrast = false
            NSWorkspace.shared.notificationCenter.post(
                name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                object: NSWorkspace.shared
            )
            first?.contentView?.layoutSubtreeIfNeeded()
            require((generalList as? NSBox)?.borderWidth == 1, "General border restores exactly")
            require(srgbHex((generalList as? NSBox)?.borderColor) == 0x363838, "General border sRGB restores exactly")
            require(moduleBoxes.allSatisfy { $0.borderWidth == 1 }, "module list border restores exactly")
            require(moduleBoxes.allSatisfy { srgbHex($0.borderColor) == 0x363838 }, "module list border sRGB restores exactly")
            verifyNativeStyleControls()
            require(controller.selectedRowStrokeWidthForTest == 0, "selected row outline is removed on restore")
            require(isLabelColor(controller.selectedRowFillColorForTest, alpha: 0.07),
                "sidebar selection restores its restrained neutral fill")
            require(controller.toggleTrackStrokeWidthForTest("Hide System Battery Icon") == 1, "off toggle outline restores exactly")
            require(srgbHex(controller.toggleTrackColorForTest("Hide System Battery Icon")) == 0x2E3032, "off toggle track sRGB restores exactly")
            require(controller.dividerVisualStrokeWidthForTest == 1, "divider stroke restores exactly")
            require(srgbHex(controller.dividerColorForTest) == 0x363838, "divider sRGB restores exactly")

            guard let window = first, let content = window.contentView else {
                require(false, "compact reference retains window content")
                exit(1)
            }
            let contentHost = view("settings.content.host", in: window)
            controller.selectSectionForTest(identifier: "general")
            content.layoutSubtreeIfNeeded()
            for generalButton in [login, battery, update, automaticUpdates] {
                requireButtonHit(generalButton, through: content, phase: "compact General")
            }
            controller.selectSectionForTest(identifier: "menu-bar-icon")
            content.layoutSubtreeIfNeeded()
            for iconButton in iconButtons {
                requireButtonHit(iconButton, through: content, phase: "compact Display")
                let cardInHost = iconButton.convert(iconButton.bounds, to: contentHost)
                require(
                    contentHost.bounds.insetBy(dx: -1, dy: -1).contains(cardInHost),
                    "\(iconButton.accessibilityLabel() ?? "icon") card stays in content bounds"
                )
            }
            controller.selectSectionForTest(identifier: "modules")
            content.layoutSubtreeIfNeeded()
            for module in Settings.Module.allCases {
                let moduleButton = button(module.title, in: window)
                let card = view("settings.modules.row.\(module.rawValue)", in: window)
                card.scrollToVisible(card.bounds.insetBy(dx: 0, dy: -20))
                content.layoutSubtreeIfNeeded()
                requireButtonHit(moduleButton, through: content, phase: "compact Modules")
                let cardInHost = card.convert(card.bounds, to: contentHost)
                require(
                    contentHost.bounds.insetBy(dx: -1, dy: -1).contains(cardInHost),
                    "\(module.rawValue) card stays in compact content bounds"
                )
            }
            requireTrafficLightsClearIdentity(
                controller: controller,
                in: window,
                identity: identity
            )

            let stableWindow = controller.windowForTest
            let stableSectionViews = controller.sectionViewIdentitiesForTest
            for index in 0..<1_000 {
                let identifiers = ["general", "menu-bar-icon", "modules"]
                controller.selectSectionForTest(identifier: identifiers[index % identifiers.count])
                require(controller.contentHostSubviewCountForTest == 1, "switch keeps one hosted page")
            }
            require(stableWindow === controller.windowForTest, "switches keep one window")
            require(stableSectionViews == controller.sectionViewIdentitiesForTest, "switches reuse section views")

            controller.selectSectionForTest(identifier: "general")
            require(colorScheme.itemTitles == ["System", "Light", "Dark"] && colorScheme.isEnabled,
                "Theme offers System, Light and Dark independently of glass")
            let readsBeforeTheme = [fixture.loginReads.count, fixture.batteryReads.count,
                fixture.loginWrites.count, fixture.batteryWrites.count, fixture.updateChecks.count]
            let themeWindowFrame = window.frame
            for glass in [false, true, false] {
                Settings.liquidGlassEnabled = glass
                for host in [NSAppearance.Name.aqua, .darkAqua] {
                    app.appearance = NSAppearance(named: host)
                    for (index, scheme) in Settings.ColorScheme.allCases.enumerated() {
                        window.makeFirstResponder(colorScheme)
                        let scrollOffset = generalScroll.contentView.bounds.origin
                        colorScheme.selectItem(at: index)
                        colorScheme.sendAction(colorScheme.action!, to: colorScheme.target)
                        let expected = scheme.appearance?.name ?? host
                        require(Settings.colorScheme == scheme
                            && window.appearance?.name == scheme.appearance?.name
                            && window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == expected,
                            "user Theme selection overrides or follows the host immediately")
                        let heading = view("settings.general.heading", in: window) as! NSTextField
                        window.effectiveAppearance.performAsCurrentDrawingAppearance {
                            let foreground = heading.textColor!.usingColorSpace(.deviceRGB)!.redComponent
                            require(expected == .aqua ? foreground < 0.3 : foreground > 0.8,
                                "Classic and glass headings have readable light/dark foregrounds")
                        }
                        require(window.firstResponder === colorScheme
                            && approximately(generalScroll.contentView.bounds.origin.y, scrollOffset.y)
                            && window.frame == themeWindowFrame
                            && stableSectionViews == controller.sectionViewIdentitiesForTest,
                            "Theme changes retain the window, controls, focus and scroll position")
                    }
                }
            }
            require(readsBeforeTheme == [fixture.loginReads.count, fixture.batteryReads.count,
                fixture.loginWrites.count, fixture.batteryWrites.count, fixture.updateChecks.count],
                "Theme changes never query or mutate system controls")
            controller.selectSectionForTest(identifier: "menu-bar-icon")
            let displayGlassBeforeTheme = Settings.liquidGlassEnabled
            let displayThemeBeforeTheme = Settings.colorScheme
            let displayStyleBeforeTheme = Settings.menuBarIconStyle
            let displayPercentageBeforeTheme = Settings.showsMenuBarPercentage
            for glass in [false, true] {
                for scheme in [Settings.ColorScheme.light, .dark] {
                    for increasedContrast in [false, true] {
                        fixture.increaseContrast = increasedContrast
                        require(window.makeFirstResponder(percentagePopup),
                            "percentage popup owns focus before Display appearance refresh")
                        Settings.colorScheme = scheme
                        Settings.liquidGlassEnabled = glass
                        NSWorkspace.shared.notificationCenter.post(
                            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                            object: NSWorkspace.shared
                        )
                        if #available(macOS 26, *) {
                            let surfaces = descendants(ofType: NSGlassEffectView.self, in: iconPage)
                                .filter { $0.identifier?.rawValue == "settings.control-group.glass" }
                            if Settings.usesLiquidGlass {
                                let systemRadius = NSGlassEffectView().cornerRadius
                                require(surfaces.count == 1 && surfaces.allSatisfy {
                                    abs($0.cornerRadius - systemRadius) < 0.001
                                }, "Display group uses the current system default glass corner radius")
                            } else {
                                require(surfaces.isEmpty, "Classic Display has no retained glass wrapper")
                            }
                        }
                        for choice in styleChoices {
                            let style = choice.style
                            let selectedButton = choice.button
                            for showsPercentage in [false, true] {
                                Settings.setMenuBarAppearance(iconStyle: style, showsPercentage: showsPercentage)
                                verifyDisplayPreviews(showingPercentage: showsPercentage)
                                verifyNativeStyleControls()
                                require(window.firstResponder === percentagePopup
                                    && selectedButton.state == .on
                                    && window.frame == themeWindowFrame
                                    && stableSectionViews == controller.sectionViewIdentitiesForTest,
                                    "theme, material and contrast keep Display preferences, focus and geometry")
                                require(displayViewIdentities() == retainedDisplayViews,
                                    "appearance adaptation reuses every Display control and preview")
                            }
                        }
                    }
                }
            }
            fixture.increaseContrast = false
            NSWorkspace.shared.notificationCenter.post(
                name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                object: NSWorkspace.shared
            )
            Settings.colorScheme = displayThemeBeforeTheme
            Settings.liquidGlassEnabled = displayGlassBeforeTheme
            Settings.setMenuBarAppearance(iconStyle: displayStyleBeforeTheme,
                showsPercentage: displayPercentageBeforeTheme)
            controller.selectSectionForTest(identifier: "general")
            require(readsBeforeTheme == [fixture.loginReads.count, fixture.batteryReads.count,
                fixture.loginWrites.count, fixture.batteryWrites.count, fixture.updateChecks.count],
                "Display appearance and preference changes never query system controls")
            Settings.colorScheme = .dark
            let reopenedTheme = SettingsWindowController(dependencies: dependencies, frameAutosaveName: nil)
            require(reopenedTheme.windowForTest?.appearance?.name == .darkAqua,
                "reopening Settings restores the saved theme")
            Settings.colorScheme = .system
            require(reopenedTheme.windowForTest?.appearance == nil && window.appearance == nil,
                "System removes the override from every retained Settings window")
            app.appearance = NSAppearance(named: .darkAqua)
            generalScroll.contentView.scroll(to: .zero)
            let originalSystemIcon = app.applicationIconImage?.tiffRepresentation
            let originalMenuStyle = Settings.menuBarIconStyle
            let originalMenuPercentage = Settings.showsMenuBarPercentage
            let operationsBeforeLogo = [fixture.loginReads.count, fixture.batteryReads.count,
                fixture.loginWrites.count, fixture.batteryWrites.count, fixture.updateChecks.count]
            window.makeFirstResponder(logoPopup)
            for (index, style, resource) in [(1, "clear", "AppLogoClearDark"),
                                            (0, "color", "AppLogoColor"),
                                            (1, "clear", "AppLogoClearDark")] {
                logoPopup.selectItem(at: index)
                logoPopup.sendAction(logoPopup.action!, to: logoPopup.target)
                require(Settings.inAppLogoStyle.rawValue == style
                    && defaults.string(forKey: "appearance.inAppLogoStyle") == style,
                    "logo choice persists even when Liquid Glass is off")
                require((identityTile as! NSImageView).image?.tiffRepresentation
                    == logoArtwork(resource).tiffRepresentation,
                    "logo choice immediately updates the retained sidebar image")
                require(window.firstResponder === logoPopup
                    && stableWindow === controller.windowForTest
                    && stableSectionViews == controller.sectionViewIdentitiesForTest
                    && controller.visibleSectionIdentifierForTest == "general",
                    "logo changes preserve window, page identities and keyboard focus")
            }
            require(operationsBeforeLogo == [fixture.loginReads.count, fixture.batteryReads.count,
                fixture.loginWrites.count, fixture.batteryWrites.count, fixture.updateChecks.count],
                "logo selection performs no helper read, write or update check")
            Settings.inAppLogoStyle = .color
            require(logoPopup.selectedItem?.representedObject as? String == "color",
                "external logo changes immediately synchronize the native selection")
            Settings.inAppLogoStyle = .clear
            require(Settings.menuBarIconStyle == originalMenuStyle
                && Settings.showsMenuBarPercentage == originalMenuPercentage
                && app.applicationIconImage?.tiffRepresentation == originalSystemIcon,
                "in-app logo choice does not mutate menu bar or application system icon")
            let originalPolicy = app.activationPolicy()
            let inAppBeforeDock = Settings.inAppLogoStyle
            let identityBeforeDock = (identityTile as! NSImageView).image?.tiffRepresentation
            window.makeFirstResponder(dockPopup)
            for (index, value) in [(1, "color"), (0, "hidden"), (2, "clear")] {
                dockPopup.selectItem(at: index)
                dockPopup.sendAction(dockPopup.action!, to: dockPopup.target)
                require(Settings.dockIconStyle.rawValue == value
                    && defaults.string(forKey: "appearance.dockIconStyle") == value,
                    "Dock picker saves its next-launch choice")
                require(app.activationPolicy() == originalPolicy
                    && app.applicationIconImage?.tiffRepresentation == originalSystemIcon,
                    "saving Dock appearance does not immediately change activation policy or system artwork")
                require(Settings.inAppLogoStyle == inAppBeforeDock
                    && (identityTile as! NSImageView).image?.tiffRepresentation == identityBeforeDock
                    && Settings.menuBarIconStyle == originalMenuStyle
                    && Settings.showsMenuBarPercentage == originalMenuPercentage,
                    "Dock settings do not overwrite the independent in-app logo or menu-bar preferences")
                require(window.firstResponder === dockPopup
                    && stableWindow === controller.windowForTest
                    && stableSectionViews == controller.sectionViewIdentitiesForTest
                    && controller.visibleSectionIdentifierForTest == "general",
                    "Dock preference changes retain focused control, window and page identities")
            }
            Settings.dockIconStyle = .hidden
            require(dockPopup.selectedItem?.representedObject as? String == "hidden",
                "typed Dock notification synchronizes the visible selection")
            defaults.set("color", forKey: "appearance.dockIconStyle")
            NotificationCenter.default.post(name: Settings.didChange, object: nil)
            require(dockPopup.selectedItem?.representedObject as? String == "color",
                "untyped settings notification reloads the persisted Dock choice")
            Settings.dockIconStyle = .clear
            require(operationsBeforeLogo == [fixture.loginReads.count, fixture.batteryReads.count,
                fixture.loginWrites.count, fixture.batteryWrites.count, fixture.updateChecks.count],
                "Dock choices and preference notifications perform no helper request or update check")
            require(app.activationPolicy() == originalPolicy
                && app.applicationIconImage?.tiffRepresentation == originalSystemIcon,
                "Dock notification synchronization never applies the restart-only preference")
            let classicLogoScroll = view("settings.general.scroll", in: window) as! NSScrollView
            content.layoutSubtreeIfNeeded()
            _ = logoPopup.scrollToVisible(logoPopup.bounds)
            require(classicLogoScroll.documentVisibleRect.contains(logoPopup.convert(
                logoPopup.bounds, to: classicLogoScroll.documentView)),
                "Classic General can scroll to the full logo control without shrinking existing rows")
            followNativeKeyLoop(in: window, from: logoPopup, to: dockPopup)
            require(window.firstResponder === dockPopup
                && classicLogoScroll.documentVisibleRect.contains(dockPopup.convert(
                    dockPopup.bounds, to: classicLogoScroll.documentView))
                && classicLogoScroll.documentVisibleRect.contains(dockHelp.convert(
                    dockHelp.bounds, to: classicLogoScroll.documentView)),
                "Classic focus reveals the Dock picker together with its restart explanation: "
                    + "focused=\(window.firstResponder === dockPopup) "
                    + "responder=\(String(describing: window.firstResponder)) "
                    + "visible=\(classicLogoScroll.documentVisibleRect) "
                    + "picker=\(dockPopup.convert(dockPopup.bounds, to: classicLogoScroll.documentView)) "
                    + "help=\(dockHelp.convert(dockHelp.bounds, to: classicLogoScroll.documentView)) "
                    + "scale=\(window.backingScaleFactor) fullKeyboard=\(app.isFullKeyboardAccessEnabled)")
            _ = dockHelp.scrollToVisible(dockHelp.bounds)
            require(classicLogoScroll.documentVisibleRect.contains(dockHelp.convert(
                dockHelp.bounds, to: classicLogoScroll.documentView)),
                "Classic scroll reveals the complete restart explanation")

            if #available(macOS 26, *) {
                controller.selectSectionForTest(identifier: "general")
                let oldLogin = login.state
                let oldBattery = battery.state
                let loginReads = fixture.loginReads.count
                let batteryReads = fixture.batteryReads.count
                let loginWrites = fixture.loginWrites.count
                let batteryWrites = fixture.batteryWrites.count
                let updateChecks = fixture.updateChecks.count
                let originalUpdatePreference = Settings.checksForUpdatesOnLaunch
                window.makeFirstResponder(automaticUpdates)
                Settings.liquidGlassEnabled = true
                let transparencyIsAdjustable = !GlassBackgroundView.accessibilityRequiresSolidBackground
                require(glassStyle.isEnabled && glassSwitch.nextKeyView === glassStyle
                    && glassStyle.nextKeyView === popoverArrow && popoverArrow.isEnabled
                    && popoverArrow.nextKeyView === (transparencyIsAdjustable ? transparency : logoPopup)
                    && (!transparencyIsAdjustable || transparency.nextKeyView === logoPopup)
                    && logoPopup.nextKeyView === dockPopup
                    && dockPopup.nextKeyView === feedbackButton,
                    "glass-on includes the background popup in the General keyboard loop")
                require(dockPopup.isEnabled && Settings.dockIconStyle == .clear,
                    "glass-on retains the independent next-launch Dock preference")
                require(logoPopup.isEnabled && Settings.inAppLogoStyle == .clear,
                    "turning glass on retains the independent Clear logo selection")
                require(window.appearance == nil
                    && window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
                        == app.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]),
                    "glass inherits the app appearance instead of pinning dark mode")
                require(controller.sidebarForTest.selectionHighlightStyle == .regular,
                    "glass sidebar uses system selection")
                let nativeSplit = window.contentViewController?.children.first as? NSSplitViewController
                require(nativeSplit?.splitViewItems.first?.behavior == .sidebar,
                    "AppKit owns the floating glass sidebar")
                require(nativeSplit?.splitViewItems.last?.automaticallyAdjustsSafeAreaInsets == true,
                    "detail content respects the native sidebar safe area")
                require(window.toolbar != nil && window.toolbarStyle == .unified,
                    "glass uses a native unified toolbar for window corners and traffic-light spacing")
                let pageTitleItem = window.toolbar!.items.first {
                    $0.itemIdentifier.rawValue == "settings.section-title"
                }!
                let pageTitle = pageTitleItem.view as! NSTextField
                require(pageTitle.stringValue == "General" && !pageTitleItem.isBordered
                    && view("settings.general.heading", in: window).isHidden,
                    "the current page has one visible title without a glass button backing")
                require(pageTitle.font == .systemFont(ofSize: 15, weight: .medium),
                    "native toolbar page titles keep a restrained 15-point hierarchy")
                let sidebarInWindow = sidebar.convert(sidebar.bounds, to: nil)
                for trafficButton in controller.trafficLightButtonsForTest {
                    let buttonFrame = trafficButton.convert(trafficButton.bounds, to: nil)
                    require(sidebarInWindow.contains(buttonFrame)
                        && buttonFrame.minX >= 16
                        && content.bounds.maxY - buttonFrame.maxY >= 12,
                        "native window controls sit inside the sidebar with toolbar corner clearance")
                }
                let backdrop = view("settings.window.backdrop", in: window) as! NSVisualEffectView
                require(!window.isOpaque && window.backgroundColor.alphaComponent == 0,
                    "glass has no opaque window backing exposed around the floating sidebar")
                require(!backdrop.isHidden && backdrop.material == .underWindowBackground
                    && backdrop.blendingMode == .behindWindow,
                    "window uses the documented behind-window system material")
                let backdropInWindow = backdrop.convert(backdrop.bounds, to: nil)
                require(backdrop.superview === nativeSplit?.splitViewItems.last?.viewController.view
                    && backdropInWindow.contains(content.convert(content.bounds, to: nil)),
                    "the continuous backdrop covers the window and the floating sidebar's rounded edges")
                sidebar.effectiveAppearance.performAsCurrentDrawingAppearance {
                    sidebar.updateLayer()
                    require(sidebar.layer?.backgroundColor?.alpha == 0,
                        "the native glass sidebar has no custom backing fill")
                }
                let container = view("settings.glass-container", in: window) as! NSGlassEffectContainerView
                let glassScroll = view("settings.general.scroll", in: window) as! NSScrollView
                let fixedHeading = view("settings.general.heading", in: window)
                require(container === glassScroll.documentView && container.spacing == 0
                    && container.contentView != nil && container.isFlipped,
                    "General glass groups share a flipped batching container inside the scroll document")
                require(container.isDescendant(of: glassScroll.contentView)
                    && glassScroll.contentView.clipsToBounds
                    && !fixedHeading.isDescendant(of: container)
                    && !contentHost.isDescendant(of: container),
                    "batching elevation stays inside the clip boundary and cannot lift over the fixed heading")
                require(!controller.sidebarForTest.isDescendant(of: container),
                    "custom glass never lifts the system sidebar into the detail layer")
                require(divider.isHidden, "glass navigation has no extra painted divider")
                let switches = descendants(ofType: NSSwitch.self, in: content).filter { !$0.isHidden }
                require(switches.count == 5, "General exposes three native switches and two appearance switches")
                require(feedbackButton.bezelStyle == .glass,
                    "feedback uses the same native glass style as other actions")
                let nativeLogin = switches.first { $0.accessibilityLabel() == "Launch at Login" }!
                let nativeUpdates = switches.first { $0.accessibilityLabel() == "Check for Updates on Launch" }!
                require(window.firstResponder === nativeUpdates,
                    "focused baseline switch transfers focus to the same native control")
                window.makeFirstResponder(glassStyle)
                glassStyle.selectItem(at: 1)
                glassStyle.sendAction(glassStyle.action!, to: glassStyle.target)
                require(Settings.liquidGlassStyle == .clear
                    && defaults.string(forKey: "appearance.liquidGlassStyle") == "clear",
                    "native popup persists the selected clear glass background")
                require(window.firstResponder === glassStyle,
                    "changing background style preserves keyboard focus")
                let arrowGlassIdentities = descendants(ofType: NSGlassEffectView.self, in: content)
                    .map(ObjectIdentifier.init)
                let arrowWindowFrame = window.frame
                let arrowSectionIdentities = controller.sectionViewIdentitiesForTest
                window.makeFirstResponder(popoverArrow)
                popoverArrow.state = .off
                popoverArrow.sendAction(popoverArrow.action!, to: popoverArrow.target)
                require(!Settings.showPopoverArrow
                    && defaults.object(forKey: "appearance.showPopoverArrow") as? Bool == false,
                    "native popup arrow switch persists the hidden choice")
                require(window.firstResponder === popoverArrow && window.frame == arrowWindowFrame
                    && controller.sectionViewIdentitiesForTest == arrowSectionIdentities
                    && descendants(ofType: NSGlassEffectView.self, in: content)
                        .map(ObjectIdentifier.init) == arrowGlassIdentities,
                    "popup arrow changes preserve Settings hosts, geometry and keyboard focus")
                Settings.showPopoverArrow = true
                require(popoverArrow.state == .on,
                    "external popup arrow changes synchronize its visible native switch")
                Settings.showPopoverArrow = false
                require(transparency.isEnabled == transparencyIsAdjustable,
                    "macOS accessibility preferences take priority over the transparency control")
                if transparencyIsAdjustable {
                    let glassViews = descendants(ofType: NSGlassEffectView.self, in: content)
                    let identities = glassViews.map(ObjectIdentifier.init)
                    let originalFrame = window.frame
                    window.makeFirstResponder(transparency)
                    for value in [0.0, 50.0, 100.0] {
                        transparency.doubleValue = value
                        transparency.sendAction(transparency.action!, to: transparency.target)
                        require(Settings.liquidGlassTransparency == value / 100
                            && window.firstResponder === transparency && window.frame == originalFrame,
                            "slider changes persist immediately without moving the window or losing focus")
                        require(descendants(ofType: NSGlassEffectView.self, in: content).map(ObjectIdentifier.init) == identities
                            && glassViews.allSatisfy { $0.alphaValue == 1 && $0.contentView?.alphaValue == 1 },
                            "transparency retains native glass hosts and fully opaque foreground controls")
                    }
                    transparency.doubleValue = 50
                    transparency.sendAction(transparency.action!, to: transparency.target)
                    transparency.keyDown(with: keyEvent(123, characters: "\u{f702}"))
                    require(Settings.liquidGlassTransparency < 0.5,
                        "the native slider supports keyboard adjustment")
                    let beforeIncrement = Settings.liquidGlassTransparency
                    require(transparency.cell?.accessibilityRole() == .slider
                        && transparency.cell?.accessibilityLabel() == "Glass transparency",
                        "the exposed native slider cell has a meaningful accessible label")
                    _ = transparency.cell?.accessibilityPerformIncrement()
                    require(Settings.liquidGlassTransparency > beforeIncrement,
                        "the native slider supports VoiceOver adjustment")
                    Settings.liquidGlassTransparency = 1
                    require(transparency.doubleValue == 100,
                        "external transparency changes synchronize the displayed control")
                } else {
                    transparency.doubleValue = 50
                    transparency.sendAction(transparency.action!, to: transparency.target)
                    require(Settings.liquidGlassTransparency == 1,
                        "accessibility override cannot be bypassed with a control action")
                }
                require(fixture.loginReads.count == loginReads
                    && fixture.batteryReads.count == batteryReads
                    && fixture.loginWrites.count == loginWrites
                    && fixture.batteryWrites.count == batteryWrites
                    && fixture.updateChecks.count == updateChecks,
                    "background choice performs no helper or update request")
                Settings.liquidGlassStyle = .regular
                require(glassStyle.selectedItem?.representedObject as? String == "regular",
                    "external style changes immediately update the native selection")
                Settings.liquidGlassStyle = .clear
                window.makeFirstResponder(nativeUpdates)
                require(controller.sidebarNextKeyViewForTest === nativeLogin,
                    "glass keyboard loop reaches the native switch")
                require(!login.isAccessibilityElement() && nativeLogin.isAccessibilityElement(),
                    "native switch has one accessible control, not a duplicate wrapper")
                require(nativeLogin.state == (oldLogin == .on ? .on : .off)
                    && nativeLogin.isEnabled == (login.isEnabled && oldLogin != .mixed),
                    "glass retains authoritative toggle state")
                require(nativeLogin.accessibilityHelp() == login.accessibilityHelp(),
                    "native switch keeps current help and recovery details")
                require(update.bezelStyle == .glass, "primary action uses the native glass bezel")
                let heading = descendants(ofType: NSTextField.self, in: content)
                    .first { $0.stringValue == "General" && $0.font?.pointSize == 18 }!
                let detail = label("settings.general.login.detail", in: window)
                let surfacesBeforeAppearance = descendants(ofType: NSGlassEffectView.self, in: content)
                    .map(ObjectIdentifier.init)
                let nativeUpdateState = nativeUpdates.state
                let nativeUpdateEnabled = nativeUpdates.isEnabled
                var resolvedHeadingColors: [UInt32] = []
                for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
                    app.appearance = NSAppearance(named: appearanceName)
                    require(window.appearance == nil
                        && window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == appearanceName,
                        "retained glass window follows an app appearance change")
                    for element in [heading, detail, nativeUpdates, container] as [NSView] {
                        require(element.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
                            == appearanceName,
                            "native glass controls and labels inherit the actual window appearance")
                    }
                    heading.effectiveAppearance.performAsCurrentDrawingAppearance {
                        require(srgbHex(heading.textColor) == srgbHex(.labelColor),
                            "glass heading resolves semantic text using its effective appearance")
                        resolvedHeadingColors.append(srgbHex(heading.textColor)!)
                    }
                    detail.effectiveAppearance.performAsCurrentDrawingAppearance {
                        require(srgbHex(detail.textColor) == srgbHex(.secondaryLabelColor),
                            "glass details resolve secondary text using their effective appearance")
                    }
                    let logoResource = appearanceName == .aqua ? "AppLogoClearLight" : "AppLogoClearDark"
                    require((identityTile as! NSImageView).image?.tiffRepresentation
                        == logoArtwork(logoResource).tiffRepresentation,
                        "selected Clear logo refreshes with the retained window effective appearance")
                    let expectedPreview = logoArtwork(logoResource)
                    expectedPreview.size = NSSize(width: 24, height: 24)
                    require(logoPopup.selectedItem?.image?.tiffRepresentation == expectedPreview.tiffRepresentation,
                        "Clear menu preview refreshes to the same effective appearance")
                    require(dockPopup.selectedItem?.image?.tiffRepresentation == expectedPreview.tiffRepresentation
                        && app.activationPolicy() == originalPolicy
                        && app.applicationIconImage?.tiffRepresentation == originalSystemIcon,
                        "Dock Clear preview adapts to appearance without applying the next-launch setting")
                    require(window.firstResponder === nativeUpdates
                        && nativeUpdates.state == nativeUpdateState
                        && nativeUpdates.isEnabled == nativeUpdateEnabled,
                        "system appearance changes preserve focused control and operation state")
                    require(surfacesBeforeAppearance
                        == descendants(ofType: NSGlassEffectView.self, in: content).map(ObjectIdentifier.init),
                        "system appearance changes retain the native glass surfaces")
                }
                require(resolvedHeadingColors[0] != resolvedHeadingColors[1],
                    "Light and Dark appearances actually produce different foreground colors")
                require(stableWindow === controller.windowForTest
                    && stableSectionViews == controller.sectionViewIdentitiesForTest,
                    "appearance toggle does not rebuild the window or sections")
                require(controller.visibleSectionIdentifierForTest == "general",
                    "appearance toggle preserves the selected page")
                require(fixture.loginReads.count == loginReads
                    && fixture.batteryReads.count == batteryReads
                    && fixture.loginWrites.count == loginWrites
                    && fixture.batteryWrites.count == batteryWrites
                    && fixture.updateChecks.count == updateChecks,
                    "appearance toggle performs no helper or update request")
                nativeUpdates.state = originalUpdatePreference ? .off : .on
                nativeUpdates.sendAction(nativeUpdates.action!, to: nativeUpdates.target)
                require(Settings.checksForUpdatesOnLaunch != originalUpdatePreference,
                    "native switch routes the existing settings action")
                Settings.checksForUpdatesOnLaunch = originalUpdatePreference
                for identifier in ["general", "menu-bar-icon", "modules"] {
                    controller.selectSectionForTest(identifier: identifier)
                    content.layoutSubtreeIfNeeded()
                    let inlineTitle = view("settings.\(identifier).heading", in: window) as! NSTextField
                    require(inlineTitle.isHidden && pageTitle.stringValue == inlineTitle.stringValue
                        && pageTitleItem.label == inlineTitle.stringValue,
                        "each page updates the visible and accessible native toolbar title")
                    if identifier == "modules" {
                        let savedStyle = Settings.liquidGlassStyle
                        for style: Settings.LiquidGlassStyle in [.regular, .clear] {
                            Settings.liquidGlassStyle = style
                            content.layoutSubtreeIfNeeded()
                            verifyRestoreModuleOrderLayout()
                            require(restoreModuleOrder.bezelStyle == .glass,
                                "restore action follows the native glass button appearance")
                        }
                        Settings.liquidGlassStyle = savedStyle
                    }
                    let surfaces = descendants(ofType: NSGlassEffectView.self, in: content)
                        .filter { $0.identifier?.rawValue == "settings.control-group.glass" }
                    let expectedGroups = identifier == "general" ? 4 : 1
                    require(surfaces.count == expectedGroups && surfaces.allSatisfy {
                        $0.contentView != nil && $0.style == .regular && $0.tintColor == nil
                    }, "functional groups use untinted native glass containing their controls")
                    for surface in surfaces {
                        if let fill = surface.contentView as? NSBox {
                            require(fill.cornerRadius == surface.cornerRadius,
                                "group fill and glass share their corner shape at every transparency")
                        }
                    }
                }
                controller.selectSectionForTest(identifier: "general")
                window.makeFirstResponder(descendants(ofType: NSSwitch.self, in: content)
                    .first { $0.accessibilityLabel() == "Check for Updates on Launch" })
                app.appearance = NSAppearance(named: .aqua)
                Settings.liquidGlassEnabled = false
                require(!glassStyle.isEnabled && Settings.liquidGlassStyle == .clear
                    && glassStyle.selectedItem?.representedObject as? String == "clear",
                    "disabling glass retains its saved background choice")
                require(!popoverArrow.isEnabled && popoverArrow.state == .off
                    && !Settings.showPopoverArrow,
                    "disabling glass retains its hidden arrow choice without an active control")
                require(glassSwitch.nextKeyView === logoPopup
                    && logoPopup.nextKeyView === dockPopup
                    && dockPopup.nextKeyView === feedbackButton,
                    "glass-off removes the disabled style popup from the keyboard loop")
                require(dockPopup.isEnabled && Settings.dockIconStyle == .clear,
                    "Dock picker stays available in Classic with its saved next-launch choice")
                require(logoPopup.isEnabled && Settings.inAppLogoStyle == .clear,
                    "glass-off keeps the independent logo selection enabled and saved")
                require(window.appearance == nil
                    && window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua,
                    "Classic keeps following the chosen System theme")
                require(window.isOpaque && backdrop.isHidden,
                    "off restores the opaque classic window and disables its backdrop")
                require(window.toolbar == nil && !fixedHeading.isHidden
                    && (generalList as! NSBox).cornerRadius == 14,
                    "Classic restores its inline title, compact window chrome and group corners")
                require(descendants(ofType: NSGlassEffectView.self, in: content)
                    .allSatisfy { $0.identifier?.rawValue != "settings.control-group.glass" },
                    "off removes custom glass while retaining the controls")
                require(update.bezelStyle == .rounded, "off restores baseline primary bezel")
                require(controller.sidebarForTest.selectionHighlightStyle == .none,
                    "off restores baseline custom sidebar selection")
                require(login.isAccessibilityElement() && nativeLogin.isHidden,
                    "off restores the baseline switch and removes duplicate native accessibility")
                require(window.firstResponder === automaticUpdates,
                    "disabling glass restores focus to the same baseline control")
                require(login.state == oldLogin && battery.state == oldBattery,
                    "round trip preserves authoritative control state")
                require((identityTile as! NSImageView).image?.tiffRepresentation == logoArtwork("AppLogoClearLight").tiffRepresentation,
                    "Classic Clear logo follows the light window")
                window.effectiveAppearance.performAsCurrentDrawingAppearance {
                    require(srgbHex(controller.dividerColorForTest) == 0xCCD0D3,
                        "Classic resolves its light divider palette")
                }
                let root = view("settings.root", in: window)
                for enabled in [false, true, false] {
                    window.makeFirstResponder(glassSwitch)
                    Settings.liquidGlassEnabled = enabled
                    require(window.firstResponder === glassSwitch,
                        "appearance switch retains keyboard focus while moving between native and classic layouts")
                    window.appearance = NSAppearance(named: .darkAqua)
                    root.updateLayer()
                    NSAppearance(named: .darkAqua)!.performAsCurrentDrawingAppearance {
                        if enabled {
                            require(root.layer?.backgroundColor?.alpha
                                == (GlassBackgroundView.accessibilityRequiresSolidBackground ? 1 : 0),
                                "native background transparency follows the system accessibility preference")
                        } else {
                            require(srgbHex(root.layer?.backgroundColor.flatMap(NSColor.init(cgColor:)))
                                == UInt32(0x151618),
                                "same-appearance off/on/off restores the Classic CGColor")
                        }
                    }
                }
                Settings.liquidGlassEnabled = true
                let glassFixture = FixtureState()
                let glassController = SettingsWindowController(
                    dependencies: .fixture(glassFixture, batteryNotification: batteryNotification),
                    frameAutosaveName: nil
                )
                let glassWindow = glassController.windowForTest!
                let glassControls = descendants(ofType: NSSwitch.self, in: glassWindow.contentView!)
                let initialNativeLogin = glassControls
                    .first { $0.accessibilityLabel() == "Launch at Login" }!
                require(glassWindow.appearance == nil
                    && glassWindow.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua
                    && !glassWindow.isVisible,
                    "glass-on initialization inherits Light appearance without showing a window")
                require(glassController.sidebarNextKeyViewForTest === initialNativeLogin,
                    "glass-on initialization immediately has the native key loop")
                let nativeAutomaticUpdates = glassControls
                    .first { $0.accessibilityLabel() == "Check for Updates on Launch" }!
                let globalAppearance = glassControls
                    .first { $0.accessibilityLabel() == "Global Liquid Glass" }!
                let glassBackground = view("settings.appearance.liquid-glass-style", in: glassWindow) as! NSPopUpButton
                let restoredArrow = view("settings.appearance.popover-arrow", in: glassWindow) as! NSSwitch
                let restoredLogo = view("settings.appearance.in-app-logo", in: glassWindow) as! NSPopUpButton
                let restoredDock = view("settings.appearance.dock-icon", in: glassWindow) as! NSPopUpButton
                let restoredFeedback = button("Send Feedback", in: glassWindow)
                let restoredTransparency = view("settings.appearance.glass-transparency", in: glassWindow) as! NSSlider
                require(glassBackground.isEnabled
                    && glassBackground.selectedItem?.representedObject as? String == "clear"
                    && globalAppearance.nextKeyView === glassBackground
                    && glassBackground.nextKeyView === restoredArrow
                    && restoredArrow.nextKeyView === (transparencyIsAdjustable ? restoredTransparency : restoredLogo)
                    && (!transparencyIsAdjustable || restoredTransparency.nextKeyView === restoredLogo)
                    && restoredLogo.nextKeyView === restoredDock
                    && restoredDock.nextKeyView === restoredFeedback
                    && restoredFeedback.nextKeyView === glassController.sidebarForTest,
                    "new Settings windows restore the background and complete the native key loop")
                require(restoredArrow.isEnabled && restoredArrow.state == .off,
                    "new Settings windows restore the independently saved hidden arrow")
                require(restoredDock.isEnabled
                    && restoredDock.selectedItem?.representedObject as? String == "clear",
                    "reopening Settings restores the pending Dock choice without needing to restart the app")
                require(restoredLogo.isEnabled
                    && restoredLogo.selectedItem?.representedObject as? String == "clear"
                    && (view("settings.sidebar.identity.tile", in: glassWindow) as! NSImageView).image?.tiffRepresentation
                        == logoArtwork("AppLogoClearLight").tiffRepresentation,
                    "reopened Settings restores the independent logo in its actual Light appearance")
                glassWindow.contentView?.layoutSubtreeIfNeeded()
                let normalGlassScroll = view("settings.general.scroll", in: glassWindow) as! NSScrollView
                let fixedGlassHeading = glassWindow.toolbar!.items.first {
                    $0.itemIdentifier.rawValue == "settings.section-title"
                }!.view!
                let headingFrameBeforeScroll = fixedGlassHeading.convert(fixedGlassHeading.bounds, to: nil)
                require(view("settings.general.controls-recovery", in: glassWindow).isHidden,
                    "normal glass layout fixture has no expanded recovery help")
                _ = glassBackground.scrollToVisible(glassBackground.bounds)
                require(normalGlassScroll.documentVisibleRect.contains(
                    glassBackground.convert(glassBackground.bounds, to: normalGlassScroll.documentView)),
                    "normal glass Settings keeps the background choice reachable")
                _ = restoredLogo.scrollToVisible(restoredLogo.bounds)
                require(normalGlassScroll.documentVisibleRect.contains(restoredLogo.convert(
                    restoredLogo.bounds, to: normalGlassScroll.documentView)),
                    "normal glass Settings keeps the full logo control reachable by scrolling")
                normalGlassScroll.contentView.scroll(to: .zero)
                normalGlassScroll.reflectScrolledClipView(normalGlassScroll.contentView)
                followNativeKeyLoop(in: glassWindow, from: glassBackground, to: restoredArrow)
                require(normalGlassScroll.documentVisibleRect.contains(restoredArrow.convert(
                    restoredArrow.bounds, to: normalGlassScroll.documentView)),
                    "keyboard focus reveals the full popup arrow switch")
                if transparencyIsAdjustable {
                    followNativeKeyLoop(in: glassWindow, from: restoredArrow, to: restoredTransparency)
                    require(normalGlassScroll.documentVisibleRect.contains(restoredTransparency.convert(
                        restoredTransparency.bounds, to: normalGlassScroll.documentView)),
                        "keyboard focus scrolls the full transparency slider into view")
                    followNativeKeyLoop(in: glassWindow, from: restoredTransparency, to: restoredLogo)
                } else {
                    followNativeKeyLoop(in: glassWindow, from: restoredArrow, to: restoredLogo)
                }
                require(glassWindow.firstResponder === restoredLogo,
                    "logo choice receives focus after native key-loop verification")
                require(normalGlassScroll.documentVisibleRect.contains(restoredLogo.convert(
                    restoredLogo.bounds, to: normalGlassScroll.documentView)),
                    "keyboard focus scrolls the full logo control into view")
                require(fixedGlassHeading.convert(fixedGlassHeading.bounds, to: nil) == headingFrameBeforeScroll
                    && !fixedGlassHeading.convert(fixedGlassHeading.bounds, to: nil).intersects(
                        normalGlassScroll.contentView.convert(normalGlassScroll.contentView.bounds, to: nil)),
                    "scrolling the logo into view leaves the fixed heading outside the clipped form")
                let visibleGlassList = view("settings.general.list", in: glassWindow)
                require(normalGlassScroll.contentView.convert(normalGlassScroll.contentView.bounds, to: nil)
                    .contains(visibleGlassList.convert(visibleGlassList.visibleRect, to: nil)),
                    "the scrolled first glass group's visible region stays within the clip viewport")
                if transparencyIsAdjustable {
                    followNativeKeyLoop(in: glassWindow, from: restoredLogo, to: restoredTransparency, reverse: true)
                    followNativeKeyLoop(in: glassWindow, from: restoredTransparency, to: restoredArrow, reverse: true)
                } else {
                    followNativeKeyLoop(in: glassWindow, from: restoredLogo, to: restoredArrow, reverse: true)
                }
                followNativeKeyLoop(in: glassWindow, from: restoredArrow, to: glassBackground, reverse: true)
                require(glassWindow.firstResponder === glassBackground,
                    "background choice receives focus after native reverse key-loop verification")
                followNativeKeyLoop(in: glassWindow, from: restoredLogo, to: restoredDock)
                let restoredDockHelp = view("settings.appearance.dock-icon.help", in: glassWindow) as! NSTextField
                require(glassWindow.firstResponder === restoredDock
                    && normalGlassScroll.documentVisibleRect.contains(restoredDock.convert(
                        restoredDock.bounds, to: normalGlassScroll.documentView))
                    && normalGlassScroll.documentVisibleRect.contains(restoredDockHelp.convert(
                        restoredDockHelp.bounds, to: normalGlassScroll.documentView)),
                    "native popup focus reveals the Dock picker and restart explanation together")
                followNativeKeyLoop(in: glassWindow, from: restoredDock, to: restoredLogo, reverse: true)
                require(glassWindow.firstResponder === restoredLogo,
                    "logo choice receives focus after the Dock reverse key-loop verification")
                _ = restoredDockHelp.scrollToVisible(restoredDockHelp.bounds)
                require(normalGlassScroll.documentVisibleRect.contains(restoredDockHelp.convert(
                    restoredDockHelp.bounds, to: normalGlassScroll.documentView)),
                    "normal Glass page can reveal the complete Dock restart explanation")
                let recoveryButton = descendants(ofType: NSButton.self, in: glassWindow.contentView!)
                    .first { $0.accessibilityIdentifier() == "settings.general.controls-recovery.button" }!
                let nativeBattery = glassControls
                    .first { $0.accessibilityLabel() == "Hide System Battery Icon" }!
                let restoredUpdate = button("Check for Updates", in: glassWindow)
                require(nativeBattery.nextKeyView === restoredUpdate
                    && nativeAutomaticUpdates.nextKeyView === view("settings.appearance.color-scheme", in: glassWindow),
                    "native key loop initially bypasses hidden recovery")
                glassController.refreshSectionsForTest()
                for nativeUnknown in [initialNativeLogin, nativeBattery] {
                    require(nativeUnknown.state == .off && !nativeUnknown.isEnabled,
                        "checking state never becomes an on NSSwitch")
                    require(nativeUnknown.accessibilityValueDescription() == "Unknown"
                        && nativeUnknown.accessibilityHelp()?.contains("Checking") == true,
                        "disabled checking switch explains unknown state to accessibility")
                    nativeUnknown.sendAction(nativeUnknown.action!, to: nativeUnknown.target)
                }
                require(glassFixture.loginWrites.isEmpty && glassFixture.batteryWrites.isEmpty,
                    "unknown controls cannot submit a setting change")
                glassFixture.loginReads.removeFirst()(.readFailed)
                glassFixture.batteryReads.removeFirst()(nil)
                for nativeUnknown in [initialNativeLogin, nativeBattery] {
                    require(nativeUnknown.state == .off && !nativeUnknown.isEnabled,
                        "failed helper read never shows the setting as on")
                    require(nativeUnknown.accessibilityValueDescription() == "Unknown"
                        && nativeUnknown.accessibilityHelp()?.contains("Status unavailable") == true,
                        "failed helper read remains explicit in accessibility")
                }
                require(nativeBattery.nextKeyView === recoveryButton
                    && recoveryButton.nextKeyView === restoredUpdate,
                    "async helper failure adds Repair Controls to the active native key loop")
                glassFixture.helperAvailable = false
                glassController.refreshSectionsForTest()
                glassFixture.loginReads.removeFirst()(.unavailable)
                glassFixture.batteryReads.removeFirst()(nil)
                require(initialNativeLogin.state == .off && nativeBattery.state == .off
                    && initialNativeLogin.accessibilityHelp()?.contains("Full installer required") == true,
                    "unavailable helper does not masquerade as enabled settings")
                require(recoveryButton.title == "Enable Controls…"
                    && nativeBattery.nextKeyView === recoveryButton
                    && recoveryButton.nextKeyView === restoredUpdate,
                    "missing helper retains the reachable Enable Controls action")
                glassController.selectSectionForTest(identifier: "modules")
                glassController.selectSectionForTest(identifier: "general")
                require(nativeBattery.nextKeyView === recoveryButton
                    && recoveryButton.nextKeyView === restoredUpdate,
                    "rebuilding the visible recovery key loop follows visual order without a self-loop")
                glassWindow.contentView?.layoutSubtreeIfNeeded()
                let recoveryScroll = view("settings.general.scroll", in: glassWindow) as! NSScrollView
                _ = globalAppearance.scrollToVisible(globalAppearance.bounds)
                require(recoveryScroll.documentVisibleRect.contains(globalAppearance.convert(
                    globalAppearance.bounds, to: recoveryScroll.documentView)),
                    "expanded recovery help does not make Appearance unreachable")
                _ = glassBackground.scrollToVisible(glassBackground.bounds)
                require(recoveryScroll.documentVisibleRect.contains(glassBackground.convert(
                    glassBackground.bounds, to: recoveryScroll.documentView)),
                    "expanded recovery help does not make the background choice unreachable")
                _ = restoredLogo.scrollToVisible(restoredLogo.bounds)
                require(recoveryScroll.documentVisibleRect.contains(restoredLogo.convert(
                    restoredLogo.bounds, to: recoveryScroll.documentView)),
                    "expanded recovery help keeps the logo choice reachable")
                _ = restoredDockHelp.scrollToVisible(restoredDockHelp.bounds)
                require(recoveryScroll.documentVisibleRect.contains(restoredDockHelp.convert(
                    restoredDockHelp.bounds, to: recoveryScroll.documentView)),
                    "expanded recovery help keeps the Dock setting explanation reachable")
                glassWindow.makeFirstResponder(restoredDock)
                require(recoveryScroll.documentVisibleRect.contains(restoredDock.convert(
                    restoredDock.bounds, to: recoveryScroll.documentView)),
                    "expanded recovery keeps keyboard access to the Dock choice")
                glassFixture.helperAvailable = true
                glassController.refreshSectionsForTest()
                glassFixture.loginReads.removeFirst()(.enabled)
                glassFixture.batteryReads.removeFirst()(false)
                require(initialNativeLogin.state == .on && initialNativeLogin.isEnabled
                    && nativeBattery.state == .off && nativeBattery.isEnabled,
                    "authoritative recovery restores true binary native state")
                require(initialNativeLogin.accessibilityValueDescription() != "Unknown",
                    "authoritative recovery clears the unknown accessibility description")
                require(nativeBattery.nextKeyView === restoredUpdate
                    && nativeAutomaticUpdates.nextKeyView === view("settings.appearance.color-scheme", in: glassWindow)
                    && recoveryButton.nextKeyView == nil,
                    "async helper recovery removes the hidden action without breaking the native key loop")
                glassWindow.makeFirstResponder(glassBackground)
                Settings.liquidGlassEnabled = false
                require(glassWindow.firstResponder === globalAppearance,
                    "turning glass off moves focus away from the disabled popup to its enable switch")
                glassWindow.makeFirstResponder(restoredLogo)
                Settings.liquidGlassEnabled = true
                Settings.liquidGlassEnabled = false
                require(glassWindow.firstResponder === restoredLogo
                    && restoredLogo.isEnabled && Settings.inAppLogoStyle == .clear,
                    "logo focus and saved choice survive material changes")
                glassWindow.makeFirstResponder(restoredDock)
                Settings.liquidGlassEnabled = true
                Settings.liquidGlassEnabled = false
                require(glassWindow.firstResponder === restoredDock && restoredDock.isEnabled
                    && Settings.dockIconStyle == .clear && app.activationPolicy() == originalPolicy,
                    "Dock focus and pending preference survive material changes without taking effect")
            }

            // A repeated refresh starts a newer read. Its result wins even if
            // an older fixture completion arrives afterward.
            controller.refreshSectionsForTest()
            controller.refreshSectionsForTest()
            require(fixture.loginReads.count == 2, "repeated refreshes reuse the window")
            let olderLoginRead = fixture.loginReads.removeFirst()
            let newerLoginRead = fixture.loginReads.removeFirst()
            if #available(macOS 26, *) {
                Settings.liquidGlassEnabled = true
                require(!login.isEnabled, "theme switch preserves in-flight disabled control")
                require(fixture.loginReads.isEmpty, "theme does not start another login read")
                Settings.liquidGlassEnabled = false
                require(!login.isEnabled, "theme round trip keeps operation in flight")
            }
            newerLoginRead(.notRegistered)
            olderLoginRead(.enabled)
            require(login.state == .off && login.isEnabled, "stale login refresh ignored")

            let olderBatteryRead = fixture.batteryReads.removeFirst()
            let newerBatteryRead = fixture.batteryReads.removeFirst()
            newerBatteryRead(true)
            olderBatteryRead(false)
            require(battery.state == .on && battery.isEnabled, "stale battery refresh ignored")

            require(app.activationPolicy() != .regular, "show does not change activation policy")

            tracePhase("state, layout, appearance and action assertions complete")
            var headlessControllers: [WeakReference<SettingsWindowController>] = []
            var headlessWindows: [WeakReference<NSWindow>] = []
            autoreleasepool {
                for _ in 0..<50 {
                    let loopFixture = FixtureState()
                    let loopDependencies = SettingsWindowDependencies.fixture(
                        loopFixture,
                        batteryNotification: batteryNotification
                    )
                    var candidate: SettingsWindowController? = SettingsWindowController(
                        dependencies: loopDependencies,
                        frameAutosaveName: nil
                    )
                    headlessControllers.append(WeakReference(candidate))
                    headlessWindows.append(WeakReference(candidate?.windowForTest))
                    candidate = nil
                }
            }
            require(headlessControllers.allSatisfy { $0.value == nil }, "headless controllers released")
            require(headlessWindows.allSatisfy { $0.value == nil }, "headless windows released")
            tracePhase("headless 50-controller release assertions complete")

            guard ProcessInfo.processInfo.environment["WATTSON_RUN_INTERACTION"] == "1" else {
                exit(0)
            }
            controller.show(activateApp: false)
            require(first?.isVisible == true, "interactive window visible")
            let preflightSection = controller.selectedSectionIdentifierForTest
            controller.selectSectionForTest(identifier: "modules")
            first?.contentView?.layoutSubtreeIfNeeded()
            verifyModuleDragPreflight(buttons: [1, 0], expectsStart: false)
            verifyModuleDragPreflight(buttons: [1, 2], expectsStart: false)
            verifyModuleDragPreflight(buttons: [1, 1], expectsStart: true)
            controller.selectSectionForTest(identifier: preflightSection)
            let minimizeTraffic = controller.trafficLightButtonsForTest[1]
            minimizeTraffic.performClick(nil)
            require(
                waitUntil { first?.isMiniaturized == true },
                "reference minimize control forwards native action"
            )
            first?.deminiaturize(nil)
            require(
                waitUntil { first?.isMiniaturized == false },
                "window restores after native minimize"
            )
            first?.contentView?.layoutSubtreeIfNeeded()
            let identityInWindow = identity.convert(identity.bounds, to: nil)
            for buttonType in [
                NSWindow.ButtonType.closeButton,
                .miniaturizeButton,
                .zoomButton,
            ] {
                if let trafficButton = first?.standardWindowButton(buttonType) {
                    let trafficFrame = trafficButton.superview?.convert(trafficButton.frame, to: nil)
                        ?? trafficButton.frame
                    require(!identityInWindow.intersects(trafficFrame), "identity avoids traffic-light button")
                }
            }
            first?.makeFirstResponder(controller.sidebarForTest)
            let up = NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: first?.windowNumber ?? 0,
                context: nil,
                characters: "\u{F700}",
                charactersIgnoringModifiers: "\u{F700}",
                isARepeat: false,
                keyCode: 126
            )!
            controller.sidebarForTest.keyDown(with: up)
            require(controller.visibleSectionIdentifierForTest == "general", "Up key shows General")
            let down = NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: first?.windowNumber ?? 0,
                context: nil,
                characters: "\u{F701}",
                charactersIgnoringModifiers: "\u{F701}",
                isARepeat: false,
                keyCode: 125
            )!
            controller.sidebarForTest.keyDown(with: down)
            require(
                controller.visibleSectionIdentifierForTest == "menu-bar-icon",
                "Down key shows Display"
            )
            controller.sidebarForTest.keyDown(with: down)
            require(controller.visibleSectionIdentifierForTest == "modules", "second Down key shows Modules")
            require(controller.selectedSectionIdentifierForTest == "modules", "keyboard selection stays non-empty")
            first?.close()
            controller.show(activateApp: false)
            require(first === controller.windowForTest, "single window identity")
            require(controller.selectedSectionIdentifierForTest == "modules", "selection survives close and reopen")
            require(controller.visibleSectionIdentifierForTest == "modules", "reopen preserves visible page")
            fixture.loginReads.removeFirst()(.enabled)
            fixture.batteryReads.removeFirst()(false)
            first?.close()

            tracePhase("visible window, keyboard and reopen assertions complete")
            var reuseFixture = FixtureState()
            let reuseDependencies = SettingsWindowDependencies.fixture(
                reuseFixture,
                batteryNotification: batteryNotification
            )
            let reuseController = SettingsWindowController(
                dependencies: reuseDependencies,
                frameAutosaveName: nil
            )
            reuseController.windowForTest?.animationBehavior = .none
            relieveAllocatorPressure()
            let reuseBaselineRSS = residentBytes()
            for _ in 0..<500 {
                reuseController.show(activateApp: false)
                reuseFixture.loginReads.removeFirst()(.enabled)
                reuseFixture.batteryReads.removeFirst()(false)
                reuseController.windowForTest?.close()
            }
            relieveAllocatorPressure()
            let reuseRSS = residentBytes()
            require(
                reuseRSS <= reuseBaselineRSS + 8 * 1_024 * 1_024,
                "single-window RSS bounded: \(reuseBaselineRSS) -> \(reuseRSS)"
            )
            tracePhase("reuse 500-cycle assertions complete")

            func createReleaseBatch(_ phase: String) -> (
                controllers: [WeakReference<SettingsWindowController>],
                windows: [WeakReference<NSWindow>]
            ) {
                var constructionTime: TimeInterval = 0
                var presentationTime: TimeInterval = 0
                var releasedControllers: [WeakReference<SettingsWindowController>] = []
                var releasedWindows: [WeakReference<NSWindow>] = []
                autoreleasepool {
                    for _ in 0..<50 {
                        let loopFixture = FixtureState()
                        let loopDependencies = SettingsWindowDependencies.fixture(
                            loopFixture,
                            batteryNotification: batteryNotification
                        )
                        let constructionStarted = ProcessInfo.processInfo.systemUptime
                        var candidate: SettingsWindowController? = SettingsWindowController(
                            dependencies: loopDependencies,
                            frameAutosaveName: nil
                        )
                        constructionTime += ProcessInfo.processInfo.systemUptime - constructionStarted
                        candidate?.windowForTest?.animationBehavior = .none
                        let presentationStarted = ProcessInfo.processInfo.systemUptime
                        candidate?.show(activateApp: false)
                        presentationTime += ProcessInfo.processInfo.systemUptime - presentationStarted
                        releasedControllers.append(WeakReference(candidate))
                        releasedWindows.append(WeakReference(candidate?.windowForTest))
                        candidate?.close()
                        candidate = nil
                    }
                }
                tracePhase(String(
                    format: "%@ 50 created: construction=%.3fs presentation=%.3fs",
                    phase, constructionTime, presentationTime
                ))
                return (releasedControllers, releasedWindows)
            }

            func drainAndRequireReleased(
                _ batch: (
                    controllers: [WeakReference<SettingsWindowController>],
                    windows: [WeakReference<NSWindow>]
                )
            ) {
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 1))
                require(
                    batch.controllers.allSatisfy { $0.value == nil },
                    "settings controllers released"
                )
                require(
                    batch.windows.allSatisfy { $0.value == nil },
                    "settings windows released: \(batch.windows.filter { $0.value != nil }.count) retained"
                )
            }

            for _ in 0..<3 {
                drainAndRequireReleased(createReleaseBatch("warmup"))
            }
            tracePhase("warmup 150-controller release assertions complete")
            relieveAllocatorPressure()
            let warmFDs = openFDCount()
            let warmRSS = residentBytes()
            require(warmFDs >= 0 && warmRSS > 0, "warm stress baselines")

            var memoryCurve = [
                "reuse0 rss=\(reuseBaselineRSS)",
                "reuse500 rss=\(reuseRSS)",
                "warm150 rss=\(warmRSS) fd=\(warmFDs)",
            ]
            var createRSS: [UInt64] = []

            for completed in stride(from: 50, through: 500, by: 50) {
                drainAndRequireReleased(createReleaseBatch("stress \(completed)"))
                relieveAllocatorPressure()
                let batchRSS = residentBytes()
                createRSS.append(batchRSS)
                memoryCurve.append(
                    "created\(completed) rss=\(batchRSS) fd=\(openFDCount()) windows=\(NSWindow.windowNumbers(options: .allApplications)?.count ?? 0)"
                )
            }
            let finalFDs = openFDCount()
            let finalRSS = residentBytes()
            let plateau = createRSS.dropFirst()
            let plateauSpread = (plateau.max() ?? finalRSS) - (plateau.min() ?? finalRSS)
            let plateauUpwardGrowth = maximumUpwardGrowth(Array(plateau))
            memoryCurve.append("final rss=\(finalRSS) fd=\(finalFDs) plateauSpread=\(plateauSpread) plateauUpwardGrowth=\(plateauUpwardGrowth)")
            FileHandle.standardError.write(Data((memoryCurve.joined(separator: "; ") + "\n").utf8))
            require(
                finalFDs <= warmFDs + 2,
                "descriptor count bounded: \(warmFDs) -> \(finalFDs)"
            )
            require(
                finalRSS <= warmRSS + 8 * 1_024 * 1_024,
                "create/release RSS bounded after warm150: \(warmRSS) -> \(finalRSS)"
            )
            require(
                plateauUpwardGrowth <= 8 * 1_024 * 1_024,
                "create/release RSS growth bounded within 8 MiB after 100 cycles: upward \(plateauUpwardGrowth)"
            )
            tracePhase("all assertions complete")
            """
        )

        with TemporaryDirectory(prefix="wattson-settings-window-") as temp:
            temp_path = pathlib.Path(temp)
            main = temp_path / "main.swift"
            bundle = temp_path / "SettingsContract.app" / "Contents"
            resources = bundle / "Resources"
            resources.mkdir(parents=True)
            executable = bundle / "MacOS" / "settings-window-contract"
            executable.parent.mkdir()
            (bundle / "Info.plist").write_bytes(plistlib.dumps({
                "CFBundleExecutable": executable.name,
                "CFBundleIdentifier": bundle_identifier(),
                "CFBundlePackageType": "APPL",
                "LSUIElement": True,
            }))
            for resource in ("AppLogoColor", "AppLogoClearLight", "AppLogoClearDark"):
                shutil.copy2(ROOT / "design" / "icon" / "in-app-logo" / f"{resource}.png", resources)
            main.write_text(harness, encoding="utf-8")
            compile_result = run(
                [
                    "xcrun",
                    "swiftc",
                    "-warnings-as-errors",
                    "-D",
                    "DEBUG",
                    "-framework",
                    "AppKit",
                    str(HELPER_CLIENT),
                    str(SYSTEM_ICON),
                    str(LOGIN_ITEM),
                    str(SETTINGS),
                    str(ROOT / "Core" / "SettingsAppearance.swift"),
                    str(ROOT / "Core" / "GlassBackgroundView.swift"),
                    str(ROOT / "Core" / "FeedbackDiagnostics.swift"),
                    str(UPDATE_CHECKER),
                    str(POWER_SNAPSHOT),
                    str(ENERGY_MODE),
                    str(BATTERY_ICON),
                    str(BATTERY_ICON_27),
                    str(ROOT / "MenuBar" / "ModuleIconArtwork.swift"),
                    str(WINDOW),
                    str(main),
                    "-o",
                    str(executable),
                ],
                capture_output=True,
                text=True,
                check=False,
                timeout=120,
            )
            self.assertEqual(
                compile_result.returncode,
                0,
                f"settings window contract did not compile:\n{compile_result.stderr}",
            )
            try:
                run_result = run(
                    [str(executable)],
                    capture_output=True,
                    text=True,
                    check=False,
                    timeout=runtime_timeout,
                )
            except subprocess.TimeoutExpired as error:
                # Preserve the original timeout failure while exposing the last
                # completed phase instead of discarding all captured progress.
                if error.stderr:
                    output = error.stderr.decode("utf-8", errors="replace") \
                        if isinstance(error.stderr, bytes) else error.stderr
                    print(output, end="", flush=True)
                raise
            if interactive or os.environ.get("WATTSON_SETTINGS_BATTERY_COMPLETION_ONLY") == "1":
                print(run_result.stderr, end="")
            self.assertEqual(
                run_result.returncode,
                0,
                f"settings window contract failed:\n{run_result.stdout}{run_result.stderr}",
            )

    def test_source_has_no_timer_and_uses_the_narrow_section_boundary(self):
        source = WINDOW.read_text(encoding="utf-8")
        self.assertIn('NSImage(named: "AppIconSettings")', source)
        self.assertIn("NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)", source)
        self.assertNotIn("ECGIconView", source)
        self.assertIn("protocol SettingsSectionController: AnyObject", source)
        self.assertIn("var identifier: String { get }", source)
        self.assertIn("var title: String { get }", source)
        self.assertIn("var sidebarIcon: ModuleIconArtwork.SidebarIcon { get }", source)
        self.assertIn("var view: NSView { get }", source)
        self.assertIn("func refresh()", source)
        self.assertNotIn("Timer(", source)
        self.assertNotIn("scheduledTimer", source)
        self.assertNotIn("DispatchSource.makeTimerSource", source)
        self.assertNotIn("CVDisplayLink", source)
        self.assertNotIn("CABasicAnimation", source)
        self.assertNotIn("ReferenceTrafficLightButton", source)
        self.assertNotIn("applyContentScale", source)
        self.assertNotIn("minimumContentScale", source)
        self.assertNotIn("titlebarSpacer", source)
        self.assertIn("NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast", source)
        self.assertIn("NSWorkspace.accessibilityDisplayOptionsDidChangeNotification", source)
        self.assertIn("NSWorkspace.shared.notificationCenter", source)

    def test_liquid_glass_is_an_appearance_only_native_opt_in(self):
        source = WINDOW.read_text(encoding="utf-8")
        appearance_refresh = source.split(
            "private func refreshLiquidGlassAppearance()", 1
        )[1].split("    @available(*, unavailable)", 1)[0]
        self.assertNotIn("refreshSections()", appearance_refresh)
        self.assertNotIn(".refresh()", appearance_refresh)
        self.assertNotIn("configureContent()", appearance_refresh)
        self.assertNotIn("showSection(", appearance_refresh)
        self.assertIn("Settings.liquidGlassEnabled", source)
        self.assertIn("Settings.usesLiquidGlass", source)
        self.assertIn("let nativeSwitch = SettingsScrollingSwitch()", source)
        self.assertIn("private final class SettingsScrollingSwitch: NSSwitch", source)
        self.assertIn("NSSplitViewItem(sidebarWithViewController: navigation)", source)
        self.assertIn("detailItem.automaticallyAdjustsSafeAreaInsets = true", source)
        self.assertIn("enabled ? .glass : .rounded", source)
        self.assertIn("identityIcon.refreshLogo()", source)
        self.assertIn("glass.contentView = controls", source)
        self.assertIn("container.contentView = document", source)
        self.assertIn("scroll.documentView = scrollDocument", source)
        self.assertNotIn("container.contentView = contentHost", source)
        self.assertIn("windowBackdrop.material = .underWindowBackground", source)

    def test_display_uses_native_radio_drawing_and_system_glass_corners(self):
        source = WINDOW.read_text(encoding="utf-8")
        radio = source.split("private final class MenuBarIconStyleButton", 1)[1].split(
            "private final class MenuBarIconSettingsSectionController", 1
        )[0]
        self.assertIn("setButtonType(.radio)", radio)
        self.assertIn("title = visibleTitle", radio)
        self.assertNotIn("override func draw(", radio)
        self.assertNotIn("NSBezierPath", radio)
        self.assertNotIn("focusRingType =", radio)
        self.assertNotIn("cardBorder", radio)
        self.assertNotIn("iconCard", source)
        surface = source.split("private final class SettingsGlassSurface", 1)[1].split(
            "private final class SettingsAdaptiveBorderBox", 1
        )[0]
        self.assertIn("NSGlassEffectView()", surface)
        self.assertNotIn("glass.cornerRadius =", surface)

    def test_in_app_logo_uses_static_resources_without_changing_system_icons(self):
        source = WINDOW.read_text(encoding="utf-8")
        logo_action = source.split("@objc private func selectInAppLogo(", 1)[1].split(
            "@objc private func selectDockIcon(", 1
        )[0]
        self.assertIn("Settings.inAppLogoStyle = style", logo_action)
        self.assertNotIn("Settings.usesLiquidGlass", logo_action)
        self.assertNotIn("refreshSections", logo_action)
        self.assertNotIn("applicationIconImage =", source)
        self.assertNotIn("setIcon(", source)
        self.assertIn("Finder and menu bar icons stay unchanged", source)
        self.assertIn("Previews are static artwork", source)
        artwork = source.split("private enum SettingsLogoArtwork", 1)[1].split(
            "private final class GeneralSettingsSectionController", 1
        )[0]
        for resource in ("AppLogoColor", "AppLogoClearLight", "AppLogoClearDark"):
            self.assertIn(f'"{resource}"', artwork)
        self.assertIn("viewDidChangeEffectiveAppearance()", artwork)
        self.assertNotIn("Timer", artwork)
        self.assertNotIn("glassEffect", artwork)

    def test_dock_icon_is_a_separate_restart_only_preference(self):
        source = WINDOW.read_text(encoding="utf-8")
        dock_action = source.split("@objc private func selectDockIcon(", 1)[1].split(
            "private func refreshDockControls()", 1
        )[0]
        self.assertIn("Settings.DockIconStyle(rawValue: value)", dock_action)
        self.assertIn("Settings.dockIconStyle = style", dock_action)
        for unrelated in ("Settings.usesLiquidGlass", "inAppLogoStyle", "menuBarIconStyle",
                          "refreshSections", "refreshLiquidGlassAppearance", "refreshLogo"):
            self.assertNotIn(unrelated, dock_action)
        for immediate_application in ("setActivationPolicy", "applicationIconImage =", "setIcon(",
                                      "NSApp.terminate", "Process("):
            self.assertNotIn(immediate_application, source)
        self.assertIn('"settings.appearance.dock-icon"', source)
        self.assertIn('dockPopup.setAccessibilityLabel("Dock Icon")', source)
        self.assertIn('"settings.appearance.dock-icon.help"', source)
        self.assertIn("Restart Wattson to apply. Finder icon stays unchanged.", source)
        self.assertIn("Hidden keeps Wattson menu-bar-only.", source)
        self.assertIn("for style in Settings.DockIconStyle.allCases", source)
        self.assertIn("dockPopup.addItem(withTitle: style.title)", source)
        self.assertIn("dockPopup.refreshPreviews()", source)
        self.assertIn("if change == nil || change == .dockIconStyle { self?.refreshDockControls() }", source)
        self.assertIn("private let dockPopup = SettingsAppearancePopupButton(", source)
        self.assertIn("dockPopup.focusScrollView = dockRow", source)
        self.assertIn("revealSettingsRow(target)", source)

    def test_default_sections_use_only_existing_settings(self):
        source = WINDOW.read_text(encoding="utf-8")
        for title in (
            "Launch at Login",
            "Hide System Battery Icon",
            "Check for Updates",
            "Check for Updates on Launch",
            'let identifier = "menu-bar-icon"',
            'let title = "Display"',
            '"Show percentage"',
        ):
            self.assertIn(title, source)
        general_source = source.split(
            "private final class GeneralSettingsSectionController", 1
        )[1].split("private enum MenuBarIconStyleKeyCommand", 1)[0]
        self.assertNotIn("menuBarIconStyle", general_source)
        self.assertNotIn("nativeIconButton", general_source)
        self.assertNotIn("menuBarPercentage", general_source)
        self.assertNotIn("showsMenuBarPercentage", general_source)
        icon_source = source.split(
            "private final class MenuBarIconSettingsSectionController", 1
        )[1].split("private final class ModuleSettingsSectionController", 1)[0]
        self.assertIn("var snapshot: PowerSnapshot", source)
        self.assertIn("PowerSnapshot(", source)
        for state in (
            "onBattery",
            "pluggedFull",
            "charging",
            "lowBattery",
            "lowBatteryPlugged",
            "lowPower",
            "lowPowerPlugged",
        ):
            self.assertIn(state, source)
        for percent in (75, 100, 72, 10, 20, 42):
            self.assertIn(f"percent: {percent}", source)
        self.assertIn("BatteryIcon.image(", icon_source)
        self.assertIn(
            "imageView.widthAnchor.constraint(equalToConstant: preview.image.size.width)",
            source,
        )
        self.assertIn(
            "imageView.heightAnchor.constraint(equalToConstant: preview.image.size.height)",
            source,
        )
        self.assertNotIn(
            "imageView.widthAnchor.constraint(equalToConstant: BatteryIcon.width)",
            source,
        )
        self.assertIn("mode: state.mode", icon_source)
        self.assertIn("pressed: false", icon_source)
        self.assertIn("style: style", icon_source)
        self.assertIn("MenuBarIconPreviewState.allCases", icon_source)
        self.assertIn("Settings.menuBarIconStyle", icon_source)
        self.assertIn("case .menuBarIconStyle", icon_source)
        self.assertIn("Settings.setMenuBarAppearance(", icon_source)
        self.assertIn("Settings.Module.allCases", source)
        self.assertIn("Settings.isModuleVisible", source)
        self.assertIn("Settings.setModule", source)
        self.assertNotIn("EnergyModeController", source)

    def test_display_keeps_style_and_percentage_independent(self):
        source = WINDOW.read_text(encoding="utf-8")
        general_source = source.split(
            "private final class GeneralSettingsSectionController", 1
        )[1].split("private enum MenuBarIconStyleKeyCommand", 1)[0]
        icon_source = source.split(
            "private final class MenuBarIconStyleButton", 1
        )[1].split("private final class ModuleSettingsSectionController", 1)[0]

        self.assertNotIn("showsMenuBarPercentage", general_source)
        self.assertIn("Settings.MenuBarIconStyle.allCases", icon_source)
        self.assertIn("MenuBarIconPreviewState.allCases", icon_source)
        self.assertIn('"settings.menu-bar-icon.percentage"', icon_source)
        self.assertIn('setAccessibilityLabel("Show percentage")', icon_source)
        self.assertIn("Settings.showsMenuBarPercentage", icon_source)
        self.assertIn("imageView.imageScaling = .scaleNone", icon_source)
        for old_combined_label in (
            '"Wattson icon only"',
            '"Wattson with percentage"',
            '"macOS 26 icon only"',
            '"macOS 26 with percentage"',
        ):
            self.assertNotIn(old_combined_label, icon_source)


if __name__ == "__main__":
    unittest.main()
