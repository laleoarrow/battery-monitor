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
UPDATE_CHECKER = ROOT / "Core" / "UpdateChecker.swift"
HELPER_CLIENT = ROOT / "Core" / "HelperClient.swift"
SYSTEM_ICON = ROOT / "Core" / "SystemBatteryIcon.swift"
LOGIN_ITEM = ROOT / "Core" / "LoginItemController.swift"
POWER_SNAPSHOT = ROOT / "Core" / "PowerSnapshot.swift"
ENERGY_MODE = ROOT / "Core" / "EnergyMode.swift"
BATTERY_ICON = ROOT / "MenuBar" / "BatteryIcon.swift"


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
                var increaseContrast = false
                var loginReads: [(LoginItemState) -> Void] = []
                var batteryReads: [(Bool?) -> Void] = []
                var loginWrites: [(Bool, (Result<LoginItemState, Error>) -> Void)] = []
                var batteryWrites: [(Bool, (Bool) -> Void)] = []
                var currentVersion = "3.0.16"
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
            require(first?.appearance?.name == .darkAqua, "reference artwork has fixed dark appearance")
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
                "section order is General, Menu Bar Icon, Modules"
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
            require(approximately(identity.frame.height, 64), "compact identity row height")
            require(
                approximately(identityTile.frame.width, 40)
                    && approximately(identityTile.frame.height, 40),
                "compact identity tile is 40 points"
            )
            require(
                identityTile is NSImageView,
                "sidebar identity uses the real packaged application icon"
            )
            require(
                (identityTile as? NSImageView)?.image != nil,
                "sidebar application icon resolves through AppKit"
            )
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
            require(approximately(controller.sidebarRowHeightForTest, 38), "compact navigation row height")
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
                    ["General", "Menu Bar Icon", "Modules"].contains($0.stringValue)
                }.count == 3
                    && navigationLabels.filter {
                        ["General", "Menu Bar Icon", "Modules"].contains($0.stringValue)
                    }
                    .allSatisfy { approximately($0.font?.pointSize ?? -1, 13) },
                "navigation labels use 13-point type"
            )
            let iconNavigationLabel = navigationLabels.first {
                $0.stringValue == "Menu Bar Icon"
            }
            require(
                (iconNavigationLabel?.attributedStringValue.size().width
                    ?? .greatestFiniteMagnitude)
                    <= (iconNavigationLabel?.frame.width ?? 0) + 1,
                "Menu Bar Icon navigation title is fully visible"
            )
            require(
                descendants(ofType: NSView.self, in: view("settings.section.general", in: first))
                    .filter { $0.identifier?.rawValue.hasPrefix("settings.general.row.") == true }
                    .count == 4,
                "General includes login, Apple battery, manual update, and launch update rows"
            )
            let generalList = view("settings.general.list", in: first)
            let generalRows = descendants(ofType: NSView.self, in: generalList)
                .filter { $0.identifier?.rawValue.hasPrefix("settings.general.row.") == true }
            require(approximately(generalList.frame.width, 503), "compact general list width")
            require(approximately(generalList.frame.height, 272), "General is exactly 4 × 68 points")
            require((generalList as? NSBox)?.cornerRadius == 10, "compact general list radius")
            require(generalRows.allSatisfy { approximately($0.frame.height, 68) }, "four 68-point rows")
            require(
                approximately(
                    (view("settings.general.heading", in: first) as? NSTextField)?.font?.pointSize ?? -1,
                    22
                ),
                "General heading uses 22-point type"
            )
            let generalRowsByIdentifier = Dictionary(
                uniqueKeysWithValues: generalRows.compactMap { row in
                    row.identifier.map { ($0.rawValue, row) }
                }
            )
            for (identifier, expectedMinY) in [
                ("settings.general.row.login", CGFloat(204)),
                ("settings.general.row.battery", CGFloat(136)),
                ("settings.general.row.update", CGFloat(68)),
                ("settings.general.row.automatic-updates", CGFloat(0)),
            ] {
                require(
                    approximately(generalRowsByIdentifier[identifier]?.frame.minY ?? -1, expectedMinY),
                    "\(identifier) retains its 68-point top-down slot"
                )
            }

            controller.refreshSectionsForTest()

            let login = button("Launch at Login", in: first)
            let battery = button("Hide System Battery Icon", in: first)
            let update = button("Check for Updates", in: first)
            let automaticUpdates = button("Check for Updates on Launch", in: first)
            require(controller.sidebarNextKeyViewForTest === login, "Tab enters first General switch")
            require(controller.lastVisibleSwitchNextKeyViewForTest === controller.sidebarForTest, "General key loop returns to sidebar")
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
                        approximately($0.font?.pointSize ?? -1, 14)
                    },
                "General primary labels use 14-point type"
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
            require(automaticUpdates.nextKeyView === controller.sidebarForTest,
                    "automatic update returns to sidebar")

            require(automaticUpdates.state == .on && automaticUpdates.isEnabled,
                    "launch update checking defaults on")
            require(
                label("settings.general.update.detail", in: first).stringValue
                    == "Current version 3.0.16",
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
            fixture.updateChecks.removeFirst()(.success(.upToDate(currentVersion: "3.0.16")))
            require(update.isEnabled && update.title == "Check Now",
                    "up-to-date result restores the action")
            require(
                label("settings.general.update.detail", in: first).stringValue
                    == "Wattson 3.0.16 is up to date",
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
                version: "3.0.17",
                pageURL: URL(
                    string: "https://github.com/laleoarrow/battery-monitor/releases/tag/v3.0.17"
                )!
            )
            fixture.updateChecks.removeFirst()(.success(.updateAvailable(availableRelease)))
            require(update.isEnabled && update.title == "View Update",
                    "available update exposes its release action")
            require(
                label("settings.general.update.detail", in: first).stringValue
                    == "Wattson 3.0.17 is available",
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

            controller.selectSidebarRowForTest(1)
            require(
                controller.selectedSectionIdentifierForTest == "menu-bar-icon",
                "Menu Bar Icon is the second section"
            )
            require(
                controller.visibleSectionIdentifierForTest == "menu-bar-icon",
                "selection delegate shows Menu Bar Icon"
            )
            require(controller.contentHostSubviewCountForTest == 1, "icon page keeps one hosted view")
            first?.contentView?.layoutSubtreeIfNeeded()

            let iconPage = view("settings.section.menu-bar-icon", in: first)
            let iconHeading = view("settings.menu-bar-icon.heading", in: first)
            let iconSubtitle = view("settings.menu-bar-icon.subtitle", in: first)
            let iconGroup = view("settings.menu-bar-icon.group", in: first)
            let iconCards = descendants(ofType: NSView.self, in: iconPage)
                .filter { $0.identifier?.rawValue.hasPrefix("settings.menu-bar-icon.card.") == true }
            let iconPreviews = descendants(ofType: NSImageView.self, in: iconPage)
                .filter {
                    $0.identifier?.rawValue.hasPrefix("settings.menu-bar-icon.preview.") == true
                }
            let iconStateChips = descendants(ofType: NSBox.self, in: iconPage)
                .filter {
                    $0.identifier?.rawValue.hasPrefix("settings.menu-bar-icon.state.") == true
                }
            let iconStateLabels = descendants(ofType: NSTextField.self, in: iconPage)
                .filter {
                    $0.identifier?.rawValue.hasPrefix(
                        "settings.menu-bar-icon.state-label."
                    ) == true
                }
            require(
                approximately((iconHeading as? NSTextField)?.font?.pointSize ?? -1, 22),
                "Menu Bar Icon heading uses 22-point type"
            )
            require(
                approximately((iconSubtitle as? NSTextField)?.font?.pointSize ?? -1, 11),
                "Menu Bar Icon subtitle uses 11-point type"
            )
            require(iconCards.count == 4, "Menu Bar Icon lists all four complete appearances")
            require(
                iconCards.allSatisfy {
                    approximately($0.frame.width, 503) && approximately($0.frame.height, 80)
                },
                "each complete icon option occupies one compact full-width row: "
                    + "\(iconCards.map(\.frame))"
            )
            let iconCardYs = iconCards.map(\.frame.minY).sorted()
            require(
                iconCardYs.count == 4
                    && zip(iconCardYs, iconCardYs.dropFirst()).allSatisfy {
                        approximately($1 - $0, 88)
                    }
                    && Set(iconCards.map { Int($0.frame.minX.rounded()) }).count == 1,
                "four full-width icon rows use eight-point vertical gaps"
            )
            require(iconStateChips.count == 28, "four rows expose all seven runtime states")
            require(iconStateLabels.count == 28, "every runtime-state preview is visibly named")
            let expectedStateLabels = [
                "Battery", "Full", "Charging", "Low", "Low + AC", "Saver", "Saver + AC",
            ]
            let previewStates = MenuBarIconPreviewState.allCases
            require(
                previewStates.map(\.visibleLabel) == expectedStateLabels,
                "preview fixtures use the same visible production order"
            )
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
            for iconCard in iconCards {
                let rowChips = descendants(ofType: NSBox.self, in: iconCard)
                    .filter {
                        $0.identifier?.rawValue.hasPrefix(
                            "settings.menu-bar-icon.state."
                        ) == true
                    }
                let rowLabels = descendants(ofType: NSTextField.self, in: iconCard)
                    .filter {
                        $0.identifier?.rawValue.hasPrefix(
                            "settings.menu-bar-icon.state-label."
                        ) == true
                    }
                let rowPreviews = descendants(ofType: NSImageView.self, in: iconCard)
                    .filter {
                        $0.identifier?.rawValue.hasPrefix(
                            "settings.menu-bar-icon.preview."
                        ) == true
                    }
                require(
                    rowChips.count == 7 && rowLabels.count == 7 && rowPreviews.count == 7,
                    "every option row contains seven complete state previews"
                )
                require(
                    rowLabels.map(\.stringValue) == expectedStateLabels,
                    "every option row shows all state labels in production order"
                )
                require(
                    rowChips.allSatisfy {
                        approximately($0.frame.width, 64)
                            && approximately($0.frame.height, 38)
                    },
                    "state chips stay compact and preserve production icon scale"
                )
                let chipXs = rowChips.map(\.frame.minX).sorted()
                require(
                    zip(chipXs, chipXs.dropFirst()).allSatisfy {
                        approximately($1 - $0, 69)
                    },
                    "seven state chips fit one row with five-point gaps"
                )
            }
            let stateLabelCounts = Dictionary(
                grouping: iconStateLabels.map(\.stringValue),
                by: { $0 }
            ).mapValues(\.count)
            for expectedState in [
                "Battery", "Full", "Charging", "Low", "Low + AC", "Saver", "Saver + AC",
            ] {
                require(
                    stateLabelCounts[expectedState] == 4,
                    "every option shows the \(expectedState) state"
                )
            }
            require(iconPreviews.count == 28, "all 28 states use renderer-backed previews")
            require(
                iconPreviews.allSatisfy {
                    ($0.image?.size.width ?? 0) > 0 && ($0.image?.size.height ?? 0) > 0
                },
                "all 28 renderer-backed preview images are nonempty"
            )
            let percentagePreviews = descendants(ofType: NSTextField.self, in: iconPage)
                .filter {
                    $0.identifier?.rawValue.hasPrefix(
                        "settings.menu-bar-icon.percentage."
                    ) == true
                }
            require(percentagePreviews.count == 14, "two percentage rows show all seven values")
            require(
                percentagePreviews.map(\.stringValue).sorted()
                    == [
                        "10%", "10%", "100%", "100%", "20%", "20%",
                        "42%", "42%", "42%", "42%", "72%", "72%",
                        "75%", "75%",
                    ],
                "percentage rows use every state’s real menu-bar value"
            )
            for percentagePreview in percentagePreviews {
                let matchingIdentifier = percentagePreview.identifier?.rawValue.replacingOccurrences(
                    of: "settings.menu-bar-icon.percentage.",
                    with: "settings.menu-bar-icon.preview."
                )
                let matchingIcon = iconPreviews.first {
                    $0.identifier?.rawValue == matchingIdentifier
                }
                require(
                    matchingIcon != nil
                        && percentagePreview.superview === matchingIcon?.superview
                        && percentagePreview.frame.maxX <= (matchingIcon?.frame.minX ?? -1) + 1,
                    "each percentage sits to the left of its matching renderer glyph: "
                        + "percentage=\(percentagePreview.frame) "
                        + "icon=\(String(describing: matchingIcon?.frame))"
                )
                if let presentation = percentagePreview.superview,
                   let boxContent = presentation.superview,
                   let stateBox = boxContent.superview as? NSBox {
                    let contentFrame = presentation.convert(presentation.bounds, to: stateBox)
                    require(
                        stateBox.bounds.insetBy(dx: 2, dy: 1).contains(contentFrame),
                        "percentage and glyph keep safe insets inside their state chip: "
                            + "content=\(contentFrame) chip=\(stateBox.bounds)"
                    )
                } else {
                    require(false, "percentage preview retains its state-chip hierarchy")
                }
                }
            let iconTitles = descendants(ofType: NSTextField.self, in: iconPage)
                .filter {
                    $0.identifier?.rawValue.hasPrefix(
                        "settings.menu-bar-icon.title."
                    ) == true
                }
            let iconDetails = descendants(ofType: NSTextField.self, in: iconPage)
                .filter {
                    $0.identifier?.rawValue.hasPrefix(
                        "settings.menu-bar-icon.detail."
                    ) == true
                }
            require(
                iconTitles.count == 4 && iconDetails.count == 4
                    && (iconTitles + iconDetails).allSatisfy {
                        $0.attributedStringValue.size().width <= $0.frame.width + 1
                    },
                "all four compact preset labels are fully visible"
            )
            require(iconGroup.isAccessibilityElement(), "icon choices expose one AX group")
            require(iconGroup.accessibilityRole() == .radioGroup, "icon choices use AX radioGroup")
            require(iconGroup.accessibilityLabel() == "Menu Bar Icon", "AX group has a useful label")
            require(!(iconGroup.accessibilityHelp() ?? "").isEmpty, "AX group has help")

            let wattsonIconOnly = button("Wattson icon only", in: first)
            let wattsonWithPercentage = button("Wattson with percentage", in: first)
            let macOSIconOnly = button("macOS 26 icon only", in: first)
            let macOSWithPercentage = button("macOS 26 with percentage", in: first)
            let iconButtons = [
                wattsonIconOnly,
                wattsonWithPercentage,
                macOSIconOnly,
                macOSWithPercentage,
            ]
            require(
                iconButtons.allSatisfy { $0.accessibilityRole() == .radioButton },
                "whole-card options expose AX radioButton roles"
            )
            require(
                iconButtons.allSatisfy { !($0.accessibilityHelp() ?? "").isEmpty },
                "both icon radio buttons expose help"
            )
            require(
                iconButtons.filter { $0.state == .on }.count == 1
                    && wattsonWithPercentage.state == .on,
                "default Wattson plus percentage selects the second preset"
            )
            require(
                (wattsonWithPercentage.accessibilityValue() as? NSNumber)?.boolValue == true
                    && iconButtons.filter { $0 !== wattsonWithPercentage }.allSatisfy {
                        ($0.accessibilityValue() as? NSNumber)?.boolValue == false
                    },
                "AX radio values expose selected semantics"
            )
            require(
                controller.sidebarNextKeyViewForTest === wattsonIconOnly,
                "Tab enters the first Menu Bar Icon card"
            )
            require(wattsonIconOnly.nextKeyView === wattsonWithPercentage, "Tab reaches preset two")
            require(wattsonWithPercentage.nextKeyView === macOSIconOnly, "Tab reaches preset three")
            require(macOSIconOnly.nextKeyView === macOSWithPercentage, "Tab reaches preset four")
            require(macOSWithPercentage.nextKeyView === controller.sidebarForTest, "icon Tab loop returns to sidebar")

            macOSWithPercentage.accessibilityPerformPress()
            require(
                Settings.menuBarIconStyle == .native && Settings.showsMenuBarPercentage
                    && macOSWithPercentage.state == .on
                    && iconButtons.filter { $0.state == .on }.count == 1,
                "AX press selects the complete macOS-with-percentage preset"
            )
            Settings.setMenuBarAppearance(iconStyle: .wattson, showsPercentage: true)

            first?.displayIfNeeded()
            let wattsonDrawsBeforeFocus = controller.iconCardDrawCountForTest(
                "Wattson icon only"
            )
            require(first?.makeFirstResponder(wattsonIconOnly) == true, "first preset accepts keyboard focus")
            require(
                waitUntil {
                    first?.displayIfNeeded()
                    return controller.iconCardDrawCountForTest("Wattson icon only")
                        > wattsonDrawsBeforeFocus
                },
                "focused first preset redraws its visible focus ring"
            )
            first?.displayIfNeeded()
            let wattsonDrawsBeforeTransfer = controller.iconCardDrawCountForTest(
                "Wattson icon only"
            )
            let macOSDrawsBeforeTransfer = controller.iconCardDrawCountForTest(
                "macOS 26 with percentage"
            )
            require(first?.makeFirstResponder(macOSWithPercentage) == true, "fourth preset accepts keyboard focus")
            require(
                waitUntil {
                    first?.displayIfNeeded()
                    return controller.iconCardDrawCountForTest("Wattson icon only")
                            > wattsonDrawsBeforeTransfer
                        && controller.iconCardDrawCountForTest("macOS 26 with percentage")
                            > macOSDrawsBeforeTransfer
                },
                "Tab-style focus movement redraws both old and new visible focus rings"
            )

            let normalizedSystemCopy = (macOSIconOnly.accessibilityHelp() ?? "").lowercased()
            require(
                normalizedSystemCopy.contains("battery artwork")
                    && normalizedSystemCopy.contains("macos 26 menu bar"),
                "System copy truthfully identifies the macOS 26 menu-bar battery artwork"
            )
            require(
                !normalizedSystemCopy.contains("control center")
                    && !normalizedSystemCopy.contains("private")
                    && !normalizedSystemCopy.contains("copied")
                    && !normalizedSystemCopy.contains("macos 27"),
                "System copy makes no private-art or future-version claim"
            )

            macOSIconOnly.performClick(nil)
            require(Settings.menuBarIconStyle == .native, "whole-card click persists macOS style")
            require(!Settings.showsMenuBarPercentage, "whole-card click persists icon-only state")
            require(macOSIconOnly.state == .on, "click keeps exactly one selected")
            require(iconButtons.filter { $0.state == .on }.count == 1, "click selection is atomic")
            Settings.menuBarIconStyle = .wattson
            require(
                wattsonIconOnly.state == .on
                    && iconButtons.filter { $0.state == .on }.count == 1,
                "external icon-style notification selects the matching complete preset"
            )
            Settings.showsMenuBarPercentage = true
            require(
                wattsonWithPercentage.state == .on
                    && iconButtons.filter { $0.state == .on }.count == 1,
                "external percentage notification selects the matching complete preset"
            )

            wattsonIconOnly.keyDown(with: keyEvent(125))
            require(
                Settings.menuBarIconStyle == .wattson && Settings.showsMenuBarPercentage,
                "Down Arrow advances to the next vertical option row"
            )
            wattsonWithPercentage.keyDown(with: keyEvent(126))
            require(
                Settings.menuBarIconStyle == .wattson && !Settings.showsMenuBarPercentage,
                "Up Arrow returns to the previous vertical option row"
            )
            wattsonIconOnly.keyDown(with: keyEvent(124))
            require(
                Settings.menuBarIconStyle == .wattson && Settings.showsMenuBarPercentage,
                "Right Arrow advances to Wattson with percentage"
            )
            wattsonWithPercentage.keyDown(with: keyEvent(124))
            require(
                Settings.menuBarIconStyle == .native && !Settings.showsMenuBarPercentage,
                "Right Arrow advances to macOS 26 icon only"
            )
            macOSIconOnly.keyDown(with: keyEvent(123))
            require(
                Settings.menuBarIconStyle == .wattson && Settings.showsMenuBarPercentage,
                "Left Arrow returns to Wattson with percentage"
            )
            wattsonIconOnly.keyDown(with: keyEvent(119))
            require(
                Settings.menuBarIconStyle == .native && Settings.showsMenuBarPercentage,
                "End selects macOS 26 with percentage"
            )
            macOSWithPercentage.keyDown(with: keyEvent(115))
            require(
                Settings.menuBarIconStyle == .wattson && !Settings.showsMenuBarPercentage,
                "Home selects Wattson icon only"
            )
            Settings.setMenuBarAppearance(iconStyle: .native, showsPercentage: true)
            wattsonIconOnly.keyDown(with: keyEvent(49, characters: " "))
            require(
                Settings.menuBarIconStyle == .wattson && !Settings.showsMenuBarPercentage,
                "Space activates the focused complete preset"
            )
            require(
                iconButtons.filter { $0.state == .on }.count == 1,
                "keyboard interactions preserve one selection"
            )

            controller.selectSidebarRowForTest(2)
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
                approximately((moduleHeading as? NSTextField)?.font?.pointSize ?? -1, 22),
                "Modules heading uses 22-point type"
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
                approximately(moduleSubtitle.frame.minY - moduleGrid.frame.maxY, 10),
                "Modules grid starts 10 points below subtitle"
            )
            let moduleCards = descendants(ofType: NSView.self, in: modulePage)
                .filter { $0.identifier?.rawValue.hasPrefix("settings.modules.card.") == true }
            let modulePreviews = descendants(ofType: NSView.self, in: modulePage)
                .filter { $0.identifier?.rawValue.hasPrefix("settings.modules.preview.") == true }
            require(moduleCards.count == 4, "modules has exactly four cards")
            require(modulePreviews.count == 4, "modules has exactly four static previews")
            require(moduleCards.allSatisfy { approximately($0.frame.width, 233) }, "compact card width")
            require(moduleCards.allSatisfy { approximately($0.frame.height, 166) }, "compact card height")
            require(moduleCards.allSatisfy { ($0 as? NSBox)?.cornerRadius == 10 }, "compact card radius")
            require(modulePreviews.allSatisfy { approximately($0.frame.width, 64) }, "compact preview width")
            require(modulePreviews.allSatisfy { approximately($0.frame.height, 60) }, "compact preview height")
            let cardXs = Array(Set(moduleCards.map { $0.frame.minX })).sorted()
            let cardYs = Array(Set(moduleCards.map { $0.frame.minY })).sorted()
            require(cardXs.count == 2 && approximately(cardXs[1] - cardXs[0], 245), "12-point column gap")
            require(cardYs.count == 2 && approximately(cardYs[1] - cardYs[0], 178), "12-point row gap")
            let modulePrimaryLabels = descendants(ofType: NSTextField.self, in: modulePage)
                .filter { Settings.Module.allCases.map(\.title).contains($0.stringValue) }
            require(
                modulePrimaryLabels.count == 4
                    && modulePrimaryLabels.allSatisfy {
                        approximately($0.font?.pointSize ?? -1, 14)
                    },
                "module primary labels use 14-point type"
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
            require(controller.lastVisibleSwitchNextKeyViewForTest === controller.sidebarForTest, "Modules key loop returns to sidebar")
            flow.performClick(nil)
            require(!Settings.isModuleVisible(.flow), "module writes through shared Settings store")
            Settings.setModule(.flow, visible: true)
            require(flow.state == .on, "module observes shared Settings store")

            // Increase Contrast is a live, appearance-only adaptation. The
            // reference palette and geometry remain exact while it is off;
            // posting AppKit's accessibility display notification updates the
            // retained General and Modules pages without reopening the window.
            let moduleBoxes = moduleCards.compactMap { $0 as? NSBox }
            require((generalList as? NSBox)?.borderWidth == 1, "normal General border is one point")
            require(srgbHex((generalList as? NSBox)?.borderColor) == 0x363838, "normal General border keeps reference sRGB")
            require(moduleBoxes.allSatisfy { $0.borderWidth == 1 }, "normal card borders are one point")
            require(moduleBoxes.allSatisfy { srgbHex($0.borderColor) == 0x363838 }, "normal cards keep reference sRGB")
            require(
                iconStateChips.allSatisfy {
                    $0.borderWidth == 1 && srgbHex($0.borderColor) == 0x363838
                },
                "normal state-chip borders keep the compact reference treatment"
            )
            require(
                controller.iconCardBorderWidthForTest("Wattson icon only") == 2,
                "selected icon card has a clear normal border"
            )
            require(
                srgbHex(controller.iconCardFillColorForTest("Wattson icon only")) == 0x2B362F,
                "selected icon card has a distinct normal fill"
            )
            require(controller.selectedRowStrokeWidthForTest == 0, "normal selected row has no extra outline")
            require(srgbHex(controller.selectedRowFillColorForTest) == 0x2B362F, "normal selection keeps reference sRGB")
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
            require(moduleBoxes.allSatisfy { $0.borderWidth == 2 }, "increased contrast strengthens card borders")
            require(moduleBoxes.allSatisfy { srgbHex($0.borderColor) == 0x8D949A }, "increased contrast brightens card borders")
            require(
                iconStateChips.allSatisfy {
                    $0.borderWidth == 2 && srgbHex($0.borderColor) == 0x8D949A
                },
                "increased contrast strengthens every state-chip border"
            )
            require(
                controller.iconCardBorderWidthForTest("Wattson icon only") == 3,
                "increased contrast strengthens the selected icon-card border"
            )
            require(
                srgbHex(controller.iconCardBorderColorForTest("Wattson icon only")) == 0x8AD88E,
                "increased contrast gives the selected icon card a bright outline"
            )
            require(
                srgbHex(controller.iconCardFillColorForTest("Wattson icon only")) == 0x3B5944,
                "increased contrast strengthens the selected icon-card fill"
            )
            require(controller.selectedRowStrokeWidthForTest == 2, "increased contrast outlines selected row")
            require(srgbHex(controller.selectedRowFillColorForTest) == 0x3B5944, "increased contrast strengthens selection fill")
            require(srgbHex(controller.selectedRowStrokeColorForTest) == 0x8AD88E, "increased contrast gives selection a clear outline")
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
            require(moduleBoxes.allSatisfy { $0.borderWidth == 1 }, "card borders restore exactly")
            require(moduleBoxes.allSatisfy { srgbHex($0.borderColor) == 0x363838 }, "card border sRGB restores exactly")
            require(
                iconStateChips.allSatisfy {
                    $0.borderWidth == 1 && srgbHex($0.borderColor) == 0x363838
                },
                "state-chip contrast styling restores exactly"
            )
            require(
                controller.iconCardBorderWidthForTest("Wattson icon only") == 2
                    && srgbHex(controller.iconCardFillColorForTest("Wattson icon only")) == 0x2B362F,
                "selected icon-card contrast styling restores exactly"
            )
            require(controller.selectedRowStrokeWidthForTest == 0, "selected row outline is removed on restore")
            require(srgbHex(controller.selectedRowFillColorForTest) == 0x2B362F, "selection sRGB restores exactly")
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
                requireButtonHit(iconButton, through: content, phase: "compact Menu Bar Icon")
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
                requireButtonHit(moduleButton, through: content, phase: "compact Modules")
                let card = view("settings.modules.card.\(module.rawValue)", in: window)
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
                "Down key shows Menu Bar Icon"
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
                    str(UPDATE_CHECKER),
                    str(POWER_SNAPSHOT),
                    str(ENERGY_MODE),
                    str(BATTERY_ICON),
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
        self.assertIn('forResource: "AppIconSettings"', source)
        self.assertIn('ofType: "png"', source)
        self.assertIn("NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)", source)
        self.assertNotIn("ECGIconView", source)
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
        self.assertNotIn("ReferenceTrafficLightButton", source)
        self.assertNotIn("applyContentScale", source)
        self.assertNotIn("minimumContentScale", source)
        self.assertNotIn("titlebarSpacer", source)
        self.assertIn("NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast", source)
        self.assertIn("NSWorkspace.accessibilityDisplayOptionsDidChangeNotification", source)
        self.assertIn("NSWorkspace.shared.notificationCenter", source)

    def test_default_sections_use_only_existing_settings(self):
        source = WINDOW.read_text(encoding="utf-8")
        for title in (
            "Launch at Login",
            "Hide System Battery Icon",
            "Check for Updates",
            "Check for Updates on Launch",
            'let identifier = "menu-bar-icon"',
            'let title = "Menu Bar Icon"',
            '"Wattson icon only"',
            '"Wattson with percentage"',
            '"macOS 26 icon only"',
            '"macOS 26 with percentage"',
        ):
            self.assertIn(title, source)
        general_source = source.split(
            "private final class GeneralSettingsSectionController", 1
        )[1].split("private enum MenuBarIconAppearance", 1)[0]
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
        self.assertIn("mode: previewState.mode", icon_source)
        self.assertIn("pressed: false", icon_source)
        self.assertIn("style: appearance.iconStyle", icon_source)
        self.assertIn("MenuBarIconPreviewState.allCases", icon_source)
        self.assertIn("Settings.menuBarIconStyle", icon_source)
        self.assertIn("case .menuBarIconStyle", icon_source)
        self.assertIn("Settings.setMenuBarAppearance(", icon_source)
        self.assertIn("Settings.Module.allCases", source)
        self.assertIn("Settings.isModuleVisible", source)
        self.assertIn("Settings.setModule", source)
        self.assertNotIn("EnergyModeController", source)

    def test_icon_page_lists_every_complete_menu_bar_appearance(self):
        source = WINDOW.read_text(encoding="utf-8")
        general_source = source.split(
            "private final class GeneralSettingsSectionController", 1
        )[1].split("private enum MenuBarIconAppearance", 1)[0]
        icon_source = source.split(
            "private enum MenuBarIconAppearance", 1
        )[1].split("private final class ModuleSettingsSectionController", 1)[0]

        self.assertNotIn("percentageButton", general_source)
        self.assertIn("MenuBarIconAppearance.allCases", icon_source)
        self.assertIn("MenuBarIconPreviewState.allCases", icon_source)
        self.assertIn("showsPercentage", icon_source)
        self.assertIn("Settings.showsMenuBarPercentage", icon_source)
        for label in (
            "Wattson icon only",
            "Wattson with percentage",
            "macOS 26 icon only",
            "macOS 26 with percentage",
        ):
            self.assertIn(label, icon_source)


if __name__ == "__main__":
    unittest.main()
