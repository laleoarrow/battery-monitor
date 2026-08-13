import os
import pathlib
import shutil
import subprocess
import tempfile
import textwrap
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
WINDOW = ROOT / "MenuBar" / "SettingsWindowController.swift"
SETTINGS = ROOT / "Core" / "Settings.swift"
HELPER_CLIENT = ROOT / "Core" / "HelperClient.swift"
SYSTEM_ICON = ROOT / "Core" / "SystemBatteryIcon.swift"
LOGIN_ITEM = ROOT / "Core" / "LoginItemController.swift"


class SettingsWindowContractTests(unittest.TestCase):
    def test_appkit_window_layout_state_and_release_contract(self):
        if shutil.which("xcrun") is None:
            self.skipTest("Xcode command line tools are unavailable")

        harness = textwrap.dedent(
            r"""
            import AppKit
            import Darwin
            import Foundation

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

            func relieveAllocatorPressure() {
                _ = malloc_zone_pressure_relief(nil, 0)
            }

            final class WeakReference<T: AnyObject> {
                weak var value: T?
                init(_ value: T?) { self.value = value }
            }

            enum FixtureError: LocalizedError {
                case rejected
                var errorDescription: String? { "Fixture rejected the update." }
            }

            final class FixtureState {
                var loginState = LoginItemState.enabled
                var batteryHidden: Bool? = false
                var helperAvailable = true
                var loginReads: [(LoginItemState) -> Void] = []
                var batteryReads: [(Bool?) -> Void] = []
                var loginWrites: [(Bool, (Result<LoginItemState, Error>) -> Void)] = []
                var batteryWrites: [(Bool, (Bool) -> Void)] = []
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
                        announceAccessibility: { fixture.announcements.append($0) }
                    )
                }
            }

            let app = NSApplication.shared
            require(app.activationPolicy() != .regular, "fixture must not change activation policy")

            let suiteName = "Wattson.SettingsWindowContract.\(UUID().uuidString)"
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
            let controller = SettingsWindowController(
                sections: SettingsWindowController.defaultSections(dependencies: dependencies),
                dependencies: dependencies,
                frameAutosaveName: nil
            )

            let first = controller.windowForTest
            require(first?.isVisible == false, "ordinary contract does not show a window")
            require(first?.isReleasedWhenClosed == false, "retained")
            require(first?.isRestorable == false, "not visibility-restored")
            require(first?.styleMask.contains(.miniaturizable) == false, "no minimize")
            require(first?.styleMask.contains(.resizable) == false, "no zoom/resize")
            require(first?.styleMask.contains(.fullSizeContentView) == true, "full-height content under titlebar")
            require(first?.titleVisibility == .hidden, "centered window title hidden")
            require(first?.titlebarAppearsTransparent == true, "titlebar is visually unified")
            require(
                first?.contentView?.frame.size == NSSize(width: 720, height: 520),
                "approved content size"
            )
            require(first?.frameAutosaveName.isEmpty == true, "nil autosave skips persistence")
            require(controller.sectionIdentifiersForTest == ["general", "modules"], "section order")
            require(Set(controller.sectionIdentifiersForTest).count == 2, "unique section identifiers")
            require(controller.selectedSectionIdentifierForTest == "general", "general initially selected")
            require(controller.visibleSectionIdentifierForTest == "general", "general initially visible")
            require(controller.contentHostSubviewCountForTest == 1, "one visible page in content host")

            first?.contentView?.layoutSubtreeIfNeeded()
            let sidebar = view("settings.sidebar", in: first)
            let identity = view("settings.sidebar.identity", in: first)
            let trafficSafeArea = view("settings.sidebar.traffic-safe-area", in: first)
            let navigation = view("settings.sidebar.navigation", in: first)
            let divider = view("settings.sidebar.divider", in: first)
            require(approximately(sidebar.frame.width, 176), "fixed sidebar width")
            require(approximately(sidebar.frame.height, 520), "sidebar spans full content height")
            require(approximately(divider.frame.height, 520), "divider spans full content height")
            require(trafficSafeArea.frame.height >= 28, "traffic-light safe area reserved")
            require(approximately(identity.frame.height, 72), "identity row height")
            require(approximately(identity.frame.maxY, trafficSafeArea.frame.minY), "identity begins below traffic safe area")
            require(approximately(navigation.frame.minX, 12), "navigation leading inset")
            require(approximately(sidebar.frame.maxX - navigation.frame.maxX, 12), "navigation trailing inset")
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
            require(approximately(controller.contentHostFrameForTest.width, 479), "usable content width")
            require(controller.sidebarStyleForTest == .sourceList, "source-list sidebar")
            require(controller.sidebarAllowsEmptySelectionForTest == false, "sidebar disallows empty selection")
            require(approximately(controller.sidebarRowHeightForTest, 44), "navigation row height")
            require(approximately(controller.sidebarRowGapForTest, 4), "navigation row gap")
            require(
                descendants(ofType: NSView.self, in: view("settings.section.general", in: first))
                    .filter { $0.identifier?.rawValue.hasPrefix("settings.general.row.") == true }
                    .count == 3,
                "general has exactly three rows"
            )
            let generalList = view("settings.general.list", in: first)
            let generalRows = descendants(ofType: NSView.self, in: generalList)
                .filter { $0.identifier?.rawValue.hasPrefix("settings.general.row.") == true }
            require(approximately(generalList.frame.width, 479), "general list width")
            require(approximately(generalList.frame.height, 228), "general list height")
            require((generalList as? NSBox)?.cornerRadius == 12, "general list radius")
            require(generalRows.allSatisfy { approximately($0.frame.height, 76) }, "three 76-point rows")

            controller.refreshSectionsForTest()

            let percentage = button("Show Battery Percentage in Menu Bar", in: first)
            let login = button("Launch at Login", in: first)
            let battery = button("Hide System Battery Icon", in: first)
            require(controller.sidebarNextKeyViewForTest === percentage, "Tab enters first General switch")
            require(controller.lastVisibleSwitchNextKeyViewForTest === controller.sidebarForTest, "General key loop returns to sidebar")
            require(percentage.accessibilityLabel() == "Show Battery Percentage in Menu Bar", "percentage accessibility label")
            require(login.accessibilityLabel() == "Launch at Login", "login accessibility label")
            require(battery.accessibilityLabel() == "Hide System Battery Icon", "battery accessibility label")
            require(percentage.title.isEmpty && login.title.isEmpty && battery.title.isEmpty, "General switches have no clipped visible titles")
            let generalVisibleTitles = Set(
                descendants(ofType: NSTextField.self, in: view("settings.section.general", in: first))
                    .map(\.stringValue)
            )
            require(
                generalVisibleTitles.contains("Show Battery Percentage in Menu Bar"),
                "percentage primary title remains visible"
            )
            require(generalVisibleTitles.contains("Launch at Login"), "login primary title remains visible")
            require(
                generalVisibleTitles.contains("Hide System Battery Icon"),
                "battery primary title remains visible"
            )
            require(!(percentage.accessibilityHelp() ?? "").isEmpty, "percentage accessibility help")
            require(!(login.accessibilityHelp() ?? "").isEmpty, "login accessibility help")
            require(!(battery.accessibilityHelp() ?? "").isEmpty, "battery accessibility help")

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

            fixture.batteryHidden = false
            NotificationCenter.default.post(name: batteryNotification, object: nil)
            require(battery.state == .off, "battery notification reloads shared authority")
            require(label("settings.general.battery.error", in: first).isHidden, "battery authority clears inline error")
            require(battery.accessibilityHelp()?.contains("couldn’t update") == false, "battery authority clears error accessibility help")

            percentage.performClick(nil)
            require(Settings.showsMenuBarPercentage == false, "percentage uses shared Settings store")
            Settings.showsMenuBarPercentage = true
            require(percentage.state == .on, "percentage observes shared Settings store")

            controller.selectSidebarRowForTest(1)
            require(controller.selectedSectionIdentifierForTest == "modules", "modules selectable")
            require(controller.visibleSectionIdentifierForTest == "modules", "selection delegate swaps page")
            require(controller.contentHostSubviewCountForTest == 1, "page swap keeps one hosted view")
            first?.contentView?.layoutSubtreeIfNeeded()
            let modulePage = view("settings.section.modules", in: first)
            let moduleHeading = view("settings.modules.heading", in: first)
            let moduleSubtitle = view("settings.modules.subtitle", in: first)
            let moduleGrid = view("settings.modules.grid", in: first)
            require(
                approximately(moduleHeading.frame.height, moduleHeading.intrinsicContentSize.height),
                "Modules heading keeps intrinsic height"
            )
            require(
                approximately(moduleSubtitle.frame.height, moduleSubtitle.intrinsicContentSize.height),
                "Modules subtitle keeps intrinsic height"
            )
            require(
                approximately(moduleSubtitle.frame.minY - moduleGrid.frame.maxY, 24),
                "Modules grid starts 24 points below subtitle"
            )
            let moduleCards = descendants(ofType: NSView.self, in: modulePage)
                .filter { $0.identifier?.rawValue.hasPrefix("settings.modules.card.") == true }
            let modulePreviews = descendants(ofType: NSView.self, in: modulePage)
                .filter { $0.identifier?.rawValue.hasPrefix("settings.modules.preview.") == true }
            require(moduleCards.count == 4, "modules has exactly four cards")
            require(modulePreviews.count == 4, "modules has exactly four static previews")
            require(moduleCards.allSatisfy { approximately($0.frame.width, 233.5) }, "card width")
            require(moduleCards.allSatisfy { approximately($0.frame.height, 166) }, "card height")
            require(moduleCards.allSatisfy { ($0 as? NSBox)?.cornerRadius == 12 }, "card radius")
            require(modulePreviews.allSatisfy { approximately($0.frame.width, 64) }, "preview width")
            require(modulePreviews.allSatisfy { approximately($0.frame.height, 64) }, "preview height")
            let cardXs = Array(Set(moduleCards.map { $0.frame.minX })).sorted()
            let cardYs = Array(Set(moduleCards.map { $0.frame.minY })).sorted()
            require(cardXs.count == 2 && approximately(cardXs[1] - cardXs[0], 245.5), "12-point column gap")
            require(cardYs.count == 2 && approximately(cardYs[1] - cardYs[0], 178), "12-point row gap")

            for module in Settings.Module.allCases {
                let moduleButton = button(module.title, in: first)
                require(moduleButton.state == .on, "module defaults visible: \(module.rawValue)")
                require(moduleButton.accessibilityLabel() == module.title, "module accessibility label")
                require(moduleButton.title.isEmpty, "module switch has no clipped visible title")
            }
            let flow = button(Settings.Module.flow.title, in: first)
            require(controller.sidebarNextKeyViewForTest === flow, "Tab enters first Modules switch")
            require(controller.lastVisibleSwitchNextKeyViewForTest === controller.sidebarForTest, "Modules key loop returns to sidebar")
            flow.performClick(nil)
            require(!Settings.isModuleVisible(.flow), "module writes through shared Settings store")
            Settings.setModule(.flow, visible: true)
            require(flow.state == .on, "module observes shared Settings store")

            let stableWindow = controller.windowForTest
            let stableSectionViews = controller.sectionViewIdentitiesForTest
            for index in 0..<1_000 {
                controller.selectSectionForTest(identifier: index.isMultiple(of: 2) ? "general" : "modules")
                require(controller.contentHostSubviewCountForTest == 1, "switch keeps one hosted page")
            }
            require(stableWindow === controller.windowForTest, "switches keep one window")
            require(stableSectionViews == controller.sectionViewIdentitiesForTest, "switches reuse section views")

            // A repeated refresh starts a newer read. Its result wins even if
            // an older fixture completion arrives afterward.
            controller.refreshSectionsForTest()
            controller.refreshSectionsForTest()
            require(fixture.loginReads.count == 2, "repeated refreshes reuse the window")
            let olderLoginRead = fixture.loginReads.removeFirst()
            let newerLoginRead = fixture.loginReads.removeFirst()
            newerLoginRead(.notRegistered)
            olderLoginRead(.enabled)
            require(login.state == .off && login.isEnabled, "stale login refresh ignored")

            let olderBatteryRead = fixture.batteryReads.removeFirst()
            let newerBatteryRead = fixture.batteryReads.removeFirst()
            newerBatteryRead(true)
            olderBatteryRead(false)
            require(battery.state == .on && battery.isEnabled, "stale battery refresh ignored")

            require(app.activationPolicy() != .regular, "show does not change activation policy")

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

            guard ProcessInfo.processInfo.environment["WATTSON_RUN_INTERACTION"] == "1" else {
                exit(0)
            }

            controller.show(activateApp: false)
            require(first?.isVisible == true, "interactive window visible")
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
            require(controller.visibleSectionIdentifierForTest == "modules", "Down key shows Modules")
            require(controller.selectedSectionIdentifierForTest == "modules", "keyboard selection stays non-empty")
            first?.close()
            controller.show(activateApp: false)
            require(first === controller.windowForTest, "single window identity")
            require(controller.selectedSectionIdentifierForTest == "modules", "selection survives close and reopen")
            require(controller.visibleSectionIdentifierForTest == "modules", "reopen preserves visible page")
            fixture.loginReads.removeFirst()(.enabled)
            fixture.batteryReads.removeFirst()(false)
            first?.close()

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

            func createReleaseBatch() -> (
                controllers: [WeakReference<SettingsWindowController>],
                windows: [WeakReference<NSWindow>]
            ) {
                var releasedControllers: [WeakReference<SettingsWindowController>] = []
                var releasedWindows: [WeakReference<NSWindow>] = []
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
                        candidate?.windowForTest?.animationBehavior = .none
                        candidate?.show(activateApp: false)
                        releasedControllers.append(WeakReference(candidate))
                        releasedWindows.append(WeakReference(candidate?.windowForTest))
                        candidate?.close()
                        candidate = nil
                    }
                }
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
                drainAndRequireReleased(createReleaseBatch())
            }
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
                drainAndRequireReleased(createReleaseBatch())
                relieveAllocatorPressure()
                let batchRSS = residentBytes()
                createRSS.append(batchRSS)
                memoryCurve.append(
                    "created\(completed) rss=\(batchRSS) fd=\(openFDCount()) windows=\(NSWindow.windowNumbers(options: .allApplications)?.count ?? 0)"
                )
            }
            let finalFDs = openFDCount()
            let finalRSS = residentBytes()
            FileHandle.standardError.write(Data((memoryCurve.joined(separator: "; ") + "\n").utf8))
            require(
                finalFDs <= warmFDs + 2,
                "descriptor count bounded: \(warmFDs) -> \(finalFDs)"
            )
            require(
                finalRSS <= warmRSS + 8 * 1_024 * 1_024,
                "create/release RSS bounded after warm150: \(warmRSS) -> \(finalRSS)"
            )
            let plateau = createRSS.dropFirst()
            let plateauSpread = (plateau.max() ?? finalRSS) - (plateau.min() ?? finalRSS)
            require(
                plateauSpread <= 8 * 1_024 * 1_024,
                "create/release RSS plateaus within 8 MiB after 100 cycles: spread \(plateauSpread)"
            )
            """
        )

        with tempfile.TemporaryDirectory(prefix="wattson-settings-window-") as temp:
            temp_path = pathlib.Path(temp)
            main = temp_path / "main.swift"
            executable = temp_path / "settings-window-contract"
            isolated_home = temp_path / "isolated-home"
            isolated_home.mkdir()
            main.write_text(harness, encoding="utf-8")
            compile_result = subprocess.run(
                [
                    "xcrun",
                    "swiftc",
                    "-D",
                    "DEBUG",
                    "-framework",
                    "AppKit",
                    str(HELPER_CLIENT),
                    str(SYSTEM_ICON),
                    str(LOGIN_ITEM),
                    str(SETTINGS),
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
            run_result = subprocess.run(
                [str(executable)],
                capture_output=True,
                text=True,
                check=False,
                timeout=120,
                env={
                    **os.environ,
                    "CFFIXED_USER_HOME": str(isolated_home),
                },
            )
            if os.environ.get("WATTSON_RUN_INTERACTION") == "1":
                print(run_result.stderr, end="")
            self.assertEqual(
                run_result.returncode,
                0,
                f"settings window contract failed:\n{run_result.stdout}{run_result.stderr}",
            )

    def test_source_has_no_timer_and_uses_the_narrow_section_boundary(self):
        source = WINDOW.read_text(encoding="utf-8")
        self.assertIn("protocol SettingsSectionController: AnyObject", source)
        self.assertIn("var identifier: String { get }", source)
        self.assertIn("var title: String { get }", source)
        self.assertIn("var symbolName: String { get }", source)
        self.assertIn("var view: NSView { get }", source)
        self.assertIn("func refresh()", source)
        self.assertNotIn("Timer(", source)
        self.assertNotIn("scheduledTimer", source)
        self.assertNotIn("DispatchSource.makeTimerSource", source)
        self.assertNotIn("CVDisplayLink", source)
        self.assertNotIn("CABasicAnimation", source)

    def test_default_sections_use_only_existing_settings(self):
        source = WINDOW.read_text(encoding="utf-8")
        for title in (
            "Show Battery Percentage in Menu Bar",
            "Launch at Login",
            "Hide System Battery Icon",
        ):
            self.assertIn(title, source)
        self.assertIn("Settings.Module.allCases", source)
        self.assertIn("Settings.isModuleVisible", source)
        self.assertIn("Settings.setModule", source)
        self.assertNotIn("EnergyModeController", source)


if __name__ == "__main__":
    unittest.main()
