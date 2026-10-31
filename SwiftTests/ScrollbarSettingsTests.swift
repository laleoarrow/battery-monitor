import AppKit
import XCTest
@testable import Wattson

final class ScrollbarSettingsTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!
    private let key = "appearance.scrollbarStyle"

    override func setUp() {
        super.setUp()
        suite = testDefaultsSuite("ScrollbarSettings")
        defaults = UserDefaults(suiteName: suite)!
        Settings.configureForTest(defaults: defaults)
    }

    override func tearDown() {
        Settings.resetTestConfiguration()
        defaults.removePersistentTestDomain(forName: suite)
        defaults = nil
        super.tearDown()
    }

    func testMissingAndInvalidPreferenceDefaultsToFlowWithoutWriting() {
        XCTAssertEqual(Settings.scrollbarStyle, .flow)
        XCTAssertNil(defaults.object(forKey: key))
        for invalid: Any in ["future-style", 42, ["flow"], ["style": "hidden"]] {
            defaults.set(invalid, forKey: key)
            XCTAssertEqual(Settings.scrollbarStyle, .flow)
        }
        defaults.removeObject(forKey: key)
        XCTAssertEqual(Settings.scrollbarStyle, .flow)
    }

    func testEveryChoicePersistsBeforeSingleNotificationAndKeepsOtherPreferences() {
        Settings.colorScheme = .dark
        Settings.liquidGlassEnabled = true
        let before = defaults.persistentDomain(forName: suite) ?? [:]
        var changes: [Settings.Change] = []
        var saved: [String] = []
        let observer = NotificationCenter.default.addObserver(
            forName: Settings.didChange, object: nil, queue: nil
        ) { [defaults, key] notification in
            changes.append(notification.userInfo?[Settings.changeUserInfoKey] as! Settings.Change)
            saved.append(defaults!.string(forKey: key) ?? "missing")
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        Settings.scrollbarStyle = .flow
        for style in Settings.ScrollbarStyle.allCases {
            Settings.scrollbarStyle = style
            Settings.scrollbarStyle = style
            Settings.configureForTest(defaults: UserDefaults(suiteName: suite)!)
            XCTAssertEqual(Settings.scrollbarStyle, style)
        }
        XCTAssertEqual(changes, [.scrollbarStyle, .scrollbarStyle, .scrollbarStyle])
        XCTAssertEqual(saved, ["hidden", "simple", "flow"])
        var after = defaults.persistentDomain(forName: suite) ?? [:]
        after.removeValue(forKey: key)
        XCTAssertEqual(after as NSDictionary, before as NSDictionary)
    }

    func testAppearancePopupOffersAllChoicesAndUpdatesInBothDirections() throws {
        _ = NSApplication.shared
        let dependencies = SettingsWindowDependencies(
            loginItemState: { .notRegistered },
            refreshLoginItem: { $0(.notRegistered) },
            setLoginItemEnabled: { _, _ in XCTFail("Scrollbar must not change login items") },
            systemBatteryIconHidden: { false },
            helperAvailable: { true },
            refreshSystemBatteryIcon: { $0(false) },
            setSystemBatteryIconHidden: { _, _ in XCTFail("Scrollbar must not change the system battery icon") },
            systemBatteryIconDidChange: Notification.Name(UUID().uuidString),
            currentVersion: { "5.0.2" },
            checkForUpdates: { _ in XCTFail("Scrollbar must not check updates") },
            openUpdateURL: { _ in XCTFail("Scrollbar must not open a browser"); return false },
            increaseContrast: { false },
            announceAccessibility: { _ in }
        )
        let section = try XCTUnwrap(SettingsWindowController.defaultSections(dependencies: dependencies)
            .first { $0.identifier == "general" })
        func descendants(_ view: NSView) -> [NSView] {
            [view] + view.subviews.flatMap(descendants)
        }
        let appearance = try XCTUnwrap(descendants(section.view).first {
            $0.identifier?.rawValue == "settings.general.appearance"
        })
        let popup = try XCTUnwrap(descendants(appearance).first {
            $0.identifier?.rawValue == "settings.appearance.scrollbar-style"
        } as? NSPopUpButton)
        XCTAssertEqual(popup.itemTitles, ["Hidden", "Simple", "Flow"])
        XCTAssertEqual(popup.selectedItem?.representedObject as? String, "flow")
        XCTAssertEqual(popup.accessibilityLabel(), "Scrollbar")
        for style in Settings.ScrollbarStyle.allCases {
            popup.selectItem(withTitle: style.title)
            XCTAssertTrue(popup.sendAction(popup.action, to: popup.target))
            XCTAssertEqual(Settings.scrollbarStyle, style)
        }
        Settings.scrollbarStyle = .simple
        XCTAssertEqual(popup.selectedItem?.representedObject as? String, "simple")
        XCTAssertFalse(Settings.liquidGlassEnabled)
        XCTAssertEqual(Settings.colorScheme, .system)
    }
}
