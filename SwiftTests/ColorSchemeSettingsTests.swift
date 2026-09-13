import AppKit
import XCTest
@testable import Wattson

final class ColorSchemeSettingsTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suite = "Wattson.ColorScheme.Tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        Settings.configureForTest(defaults: defaults)
    }

    override func tearDown() {
        Settings.resetTestConfiguration()
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        super.tearDown()
    }

    func testMissingAndUnknownChoicesFollowSystemWithoutWritingDefaults() {
        XCTAssertEqual(Settings.colorScheme, .system)
        XCTAssertNil(Settings.colorScheme.appearance)
        XCTAssertTrue((defaults.persistentDomain(forName: suite) ?? [:]).isEmpty)
        for value: Any in ["future-theme", 17, ["invalid"]] {
            defaults.set(value, forKey: "appearance.colorScheme")
            XCTAssertEqual(Settings.colorScheme, .system)
        }
    }

    func testPersistsBeforeNotifyingAndRemainsIndependentOfGlassAndIcons() {
        var changes: [Settings.Change] = []
        var saved: [String] = []
        let observer = NotificationCenter.default.addObserver(
            forName: Settings.didChange, object: nil, queue: nil
        ) { [defaults] notification in
            guard let change = notification.userInfo?[Settings.changeUserInfoKey] as? Settings.Change else { return }
            changes.append(change)
            saved.append(defaults?.string(forKey: "appearance.colorScheme") ?? "missing")
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        Settings.colorScheme = .system
        Settings.colorScheme = .light
        Settings.colorScheme = .light
        Settings.colorScheme = .dark
        XCTAssertEqual(changes, [.colorScheme, .colorScheme])
        XCTAssertEqual(saved, ["light", "dark"])
        Settings.configureForTest(defaults: UserDefaults(suiteName: suite)!)
        XCTAssertEqual(Settings.colorScheme, .dark)
        XCTAssertFalse(Settings.liquidGlassEnabled)
        XCTAssertEqual(Settings.liquidGlassStyle, .regular)
        XCTAssertEqual(Settings.inAppLogoStyle, .color)
        XCTAssertEqual(Settings.dockIconStyle, .hidden)
        Settings.colorScheme = .system
        XCTAssertEqual(defaults.string(forKey: "appearance.colorScheme"), "system")
        XCTAssertNil(Settings.colorScheme.appearance)
    }

    func testClosedPopoverRestoresAndChangesThemeWithoutOpeningOrRendering() throws {
        _ = NSApplication.shared
        Settings.colorScheme = .dark
        let controller = PopoverController()
        let root = try XCTUnwrap(controller.contentViewForTest)
        XCTAssertEqual(controller.popoverAppearanceForTest?.name, .darkAqua)
        for scheme in [Settings.ColorScheme.light, .system, .dark, .system] {
            Settings.colorScheme = scheme
            controller.retireClassicHostForTest()
            for glass in [true, false] {
                Settings.liquidGlassEnabled = glass
                XCTAssertEqual(controller.popoverAppearanceForTest?.name, scheme.appearance?.name)
                XCTAssertTrue(controller.contentViewForTest === root)
                XCTAssertEqual(controller.contentRenderCountForTest, 0)
                XCTAssertFalse(controller.isOpen)
                XCTAssertFalse(controller.isWatchingOutsideClicks)
            }
        }
    }
}
