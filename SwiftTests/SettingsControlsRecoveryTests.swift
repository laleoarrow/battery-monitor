import AppKit
import XCTest
@testable import Wattson

final class SettingsControlsRecoveryTests: XCTestCase {
    private final class Fixture {
        var helperAvailable = false
        var loginState = LoginItemState.unavailable
        var batteryHidden: Bool?
        var loginReads: [(LoginItemState) -> Void] = []
        var batteryReads: [(Bool?) -> Void] = []
        var writes = 0
        var openedURLs: [URL] = []
        var openSucceeds = true
        var announcements: [String] = []

        var dependencies: SettingsWindowDependencies {
            SettingsWindowDependencies(
                loginItemState: { self.loginState },
                refreshLoginItem: { self.loginReads.append($0) },
                setLoginItemEnabled: { _, _ in self.writes += 1 },
                systemBatteryIconHidden: { self.batteryHidden },
                helperAvailable: { self.helperAvailable },
                refreshSystemBatteryIcon: { self.batteryReads.append($0) },
                setSystemBatteryIconHidden: { _, _ in self.writes += 1 },
                systemBatteryIconDidChange: Notification.Name(UUID().uuidString),
                currentVersion: { "3.0.28" },
                checkForUpdates: { _ in XCTFail("Recovery must not check or download updates") },
                openUpdateURL: {
                    self.openedURLs.append($0)
                    return self.openSucceeds
                },
                increaseContrast: { false },
                announceAccessibility: { self.announcements.append($0) }
            )
        }

        func settle(login: LoginItemState, battery: Bool?) {
            loginState = login
            batteryHidden = battery
            loginReads.removeFirst()(login)
            batteryReads.removeFirst()(battery)
        }
    }

    private func generalSection(_ fixture: Fixture) throws -> SettingsSectionController {
        _ = NSApplication.shared
        return try XCTUnwrap(SettingsWindowController.defaultSections(
            dependencies: fixture.dependencies
        ).first { $0.identifier == "general" })
    }

    private func find<T: NSView>(_ identifier: String, in view: NSView) -> T? {
        if view.identifier?.rawValue == identifier || view.accessibilityIdentifier() == identifier {
            return view as? T
        }
        return view.subviews.lazy.compactMap { self.find(identifier, in: $0) as T? }.first
    }

    private func rowButton(_ identifier: String, in view: NSView) throws -> NSButton {
        let row: NSView = try XCTUnwrap(find("settings.general.row.\(identifier)", in: view))
        return try XCTUnwrap(row.subviews.compactMap { $0 as? NSButton }.first)
    }

    func testMissingHelperOffersOptionalInstallerOnlyAfterExplicitClick() throws {
        let fixture = Fixture()
        let section = try generalSection(fixture)
        let login = try rowButton("login", in: section.view)
        let battery = try rowButton("battery", in: section.view)
        let automaticUpdates = try rowButton("automatic-updates", in: section.view)
        let nextControl = NSButton()
        automaticUpdates.nextKeyView = nextControl
        section.refresh()
        fixture.settle(login: .unavailable, battery: nil)
        let recovery: NSStackView = try XCTUnwrap(find("settings.general.controls-recovery", in: section.view))
        let button: NSButton = try XCTUnwrap(find("settings.general.controls-recovery.button", in: section.view))
        let detail: NSTextField = try XCTUnwrap(find("settings.general.controls-recovery.detail", in: section.view))

        XCTAssertFalse(recovery.isHidden)
        XCTAssertEqual(button.title, "Enable Controls…")
        XCTAssertNotNil(button.image)
        XCTAssertTrue(detail.stringValue.contains("Monitoring continues"))
        XCTAssertTrue(detail.stringValue.contains("live SMC power"))
        XCTAssertTrue(detail.stringValue.contains("cancel"))
        XCTAssertTrue(fixture.openedURLs.isEmpty)
        XCTAssertEqual(fixture.writes, 0)
        XCTAssertFalse(login.isEnabled)
        XCTAssertFalse(battery.isEnabled)
        XCTAssertTrue(automaticUpdates.nextKeyView === button)
        XCTAssertTrue(button.nextKeyView === nextControl)

        button.performClick(nil)
        XCTAssertEqual(fixture.openedURLs.map(\.absoluteString), [
            "https://github.com/laleoarrow/battery-monitor/releases/latest",
        ])
        XCTAssertEqual(fixture.writes, 0)
        XCTAssertFalse(recovery.isHidden, "Returning from the browser must not claim installation succeeded")

        fixture.helperAvailable = true
        section.refresh()
        fixture.settle(login: .enabled, battery: false)
        XCTAssertTrue(recovery.isHidden, "Existing asynchronous refresh detects successful recovery")
        XCTAssertTrue(login.isEnabled)
        XCTAssertTrue(battery.isEnabled)
        XCTAssertTrue(automaticUpdates.nextKeyView === nextControl)
        XCTAssertEqual(fixture.writes, 0)
        XCTAssertEqual(fixture.openedURLs.count, 1)
    }

    func testFailedReadOffersRepairAndFailedBrowserOpenKeepsControlsUnchanged() throws {
        let fixture = Fixture()
        fixture.helperAvailable = true
        fixture.openSucceeds = false
        let section = try generalSection(fixture)
        section.refresh()
        fixture.settle(login: .readFailed, battery: nil)
        let recovery: NSStackView = try XCTUnwrap(find("settings.general.controls-recovery", in: section.view))
        let button: NSButton = try XCTUnwrap(find("settings.general.controls-recovery.button", in: section.view))
        let detail: NSTextField = try XCTUnwrap(find("settings.general.controls-recovery.detail", in: section.view))

        XCTAssertFalse(recovery.isHidden)
        XCTAssertEqual(button.title, "Repair Controls…")
        button.performClick(nil)
        XCTAssertTrue(detail.stringValue.contains("Couldn’t open GitHub"))
        XCTAssertEqual(fixture.announcements, [detail.stringValue])
        XCTAssertEqual(fixture.writes, 0)
        XCTAssertEqual(fixture.loginState, .readFailed)
        XCTAssertNil(fixture.batteryHidden)
    }

    func testStaleFailedReadCannotReopenRecoveryAfterNewerSuccess() throws {
        let fixture = Fixture()
        fixture.helperAvailable = true
        let section = try generalSection(fixture)
        section.refresh()
        section.refresh()
        let olderLogin = fixture.loginReads.removeFirst()
        let olderBattery = fixture.batteryReads.removeFirst()
        fixture.settle(login: .notRegistered, battery: false)
        olderLogin(.readFailed)
        olderBattery(nil)
        let recovery: NSStackView = try XCTUnwrap(find("settings.general.controls-recovery", in: section.view))

        XCTAssertTrue(recovery.isHidden)
        XCTAssertTrue(fixture.openedURLs.isEmpty)
        XCTAssertEqual(fixture.writes, 0)
    }
}
