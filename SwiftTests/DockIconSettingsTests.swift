import Foundation
import XCTest
@testable import Wattson

final class DockIconSettingsTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "Wattson.DockIcon.Tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        Settings.configureForTest(defaults: defaults)
    }

    override func tearDown() {
        Settings.resetTestConfiguration()
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testHiddenDefaultAndInvalidValuesDoNotWritePreferences() {
        XCTAssertEqual(Settings.DockIconStyle.allCases.map(\.rawValue), ["hidden", "color", "clear"])
        XCTAssertEqual(Settings.dockIconStyle, .hidden)
        XCTAssertTrue((defaults.persistentDomain(forName: suiteName) ?? [:]).isEmpty)
        for value: Any in ["future-icon", ["invalid"], 1] {
            defaults.set(value, forKey: "appearance.dockIconStyle")
            XCTAssertEqual(Settings.dockIconStyle, .hidden)
            XCTAssertEqual(defaults.object(forKey: "appearance.dockIconStyle") as? NSObject,
                           value as? NSObject)
        }
    }

    func testSavedStyleSurvivesNewDefaultsInstanceIncludingReturnToHidden() {
        for style in Settings.DockIconStyle.allCases.reversed() {
            Settings.dockIconStyle = style
            Settings.configureForTest(defaults: UserDefaults(suiteName: suiteName)!)
            XCTAssertEqual(Settings.dockIconStyle, style)
            XCTAssertEqual(defaults.string(forKey: "appearance.dockIconStyle"), style.rawValue)
        }
    }

    func testExistingLogoAndMenuBarPreferencesDoNotEnableDock() {
        Settings.inAppLogoStyle = .clear
        Settings.menuBarIconStyle = .native
        Settings.showsMenuBarPercentage = false
        Settings.liquidGlassEnabled = true
        XCTAssertEqual(Settings.dockIconStyle, .hidden)
        XCTAssertNil(defaults.object(forKey: "appearance.dockIconStyle"))
        Settings.dockIconStyle = .color
        XCTAssertEqual(Settings.inAppLogoStyle, .clear)
        XCTAssertEqual(Settings.menuBarIconStyle, .native)
        XCTAssertFalse(Settings.showsMenuBarPercentage)
        XCTAssertTrue(Settings.liquidGlassEnabled)
    }

    func testOneTypedNotificationAfterSaveAndNoneForSameChoice() {
        var changes: [Settings.Change] = []
        var saved: [String] = []
        let observer = NotificationCenter.default.addObserver(
            forName: Settings.didChange, object: nil, queue: nil
        ) { [defaults] notification in
            guard let change = notification.userInfo?[Settings.changeUserInfoKey]
                    as? Settings.Change else { return }
            changes.append(change)
            saved.append(defaults?.string(forKey: "appearance.dockIconStyle") ?? "missing")
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        Settings.dockIconStyle = .hidden
        XCTAssertTrue(changes.isEmpty)
        Settings.dockIconStyle = .clear
        Settings.dockIconStyle = .clear
        Settings.dockIconStyle = .hidden
        XCTAssertEqual(changes, [.dockIconStyle, .dockIconStyle])
        XCTAssertEqual(saved, ["clear", "hidden"])
    }

    func testOnlyVisibleChoicesSelectBundledStaticArtwork() {
        for dark in [false, true] {
            XCTAssertNil(Settings.DockIconStyle.hidden.imageResourceName(isDark: dark))
            XCTAssertEqual(Settings.DockIconStyle.color.imageResourceName(isDark: dark), "AppDockLogoColor")
        }
        XCTAssertEqual(Settings.DockIconStyle.clear.imageResourceName(isDark: false), "AppDockLogoClearLight")
        XCTAssertEqual(Settings.DockIconStyle.clear.imageResourceName(isDark: true), "AppDockLogoClearDark")
    }
}
