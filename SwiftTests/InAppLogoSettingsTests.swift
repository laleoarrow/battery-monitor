import Foundation
import XCTest
@testable import Wattson

final class InAppLogoSettingsTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "Wattson.InAppLogo.Tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        Settings.configureForTest(defaults: defaults)
    }

    override func tearDown() {
        Settings.resetTestConfiguration()
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testColorDefaultAndInvalidValuesDoNotWritePreferences() {
        XCTAssertEqual(Settings.InAppLogoStyle.allCases.map(\.rawValue), ["color", "clear"])
        XCTAssertEqual(Settings.inAppLogoStyle, .color)
        XCTAssertTrue((defaults.persistentDomain(forName: suiteName) ?? [:]).isEmpty)
        for value: Any in ["future-logo", ["invalid"], 1] {
            defaults.set(value, forKey: "appearance.inAppLogoStyle")
            XCTAssertEqual(Settings.inAppLogoStyle, .color)
            XCTAssertEqual(defaults.object(forKey: "appearance.inAppLogoStyle") as? NSObject,
                           value as? NSObject)
        }
    }

    func testLogoPersistsIndependentlyOfMaterialsAndMenuBarChoice() {
        Settings.menuBarIconStyle = .native
        Settings.showsMenuBarPercentage = false
        Settings.liquidGlassStyle = .regular
        Settings.inAppLogoStyle = .clear
        XCTAssertFalse(Settings.liquidGlassEnabled)
        XCTAssertEqual(defaults.string(forKey: "appearance.inAppLogoStyle"), "clear")
        for enabled in [true, false, true, false] {
            Settings.liquidGlassEnabled = enabled
            XCTAssertEqual(Settings.inAppLogoStyle, .clear)
        }
        Settings.liquidGlassStyle = .clear
        Settings.configureForTest(defaults: UserDefaults(suiteName: suiteName)!)
        XCTAssertEqual(Settings.inAppLogoStyle, .clear)
        Settings.inAppLogoStyle = .color
        XCTAssertEqual(Settings.menuBarIconStyle, .native)
        XCTAssertFalse(Settings.showsMenuBarPercentage)
        XCTAssertFalse(Settings.liquidGlassEnabled)
        XCTAssertEqual(Settings.liquidGlassStyle, .clear)
    }

    func testOneTypedNotificationAfterPersistenceAndNoOpForSameChoice() {
        var changes: [Settings.Change] = []
        var saved: [String] = []
        let observer = NotificationCenter.default.addObserver(
            forName: Settings.didChange, object: nil, queue: nil
        ) { [defaults] notification in
            guard let change = notification.userInfo?[Settings.changeUserInfoKey]
                as? Settings.Change else { return }
            changes.append(change)
            saved.append(defaults?.string(forKey: "appearance.inAppLogoStyle") ?? "missing")
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        Settings.inAppLogoStyle = .color
        XCTAssertTrue(changes.isEmpty)
        Settings.inAppLogoStyle = .clear
        Settings.inAppLogoStyle = .clear
        XCTAssertEqual(changes, [.inAppLogoStyle])
        XCTAssertEqual(saved, ["clear"])
        Settings.inAppLogoStyle = .color
        XCTAssertEqual(changes, [.inAppLogoStyle, .inAppLogoStyle])
        XCTAssertEqual(saved, ["clear", "color"])
    }

    func testExternalPreferenceReadDoesNotChangeOtherSettings() {
        defaults.set("clear", forKey: "appearance.inAppLogoStyle")
        XCTAssertEqual(Settings.inAppLogoStyle, .clear)
        XCTAssertFalse(Settings.liquidGlassEnabled)
        XCTAssertEqual(Settings.menuBarIconStyle, .wattson)
        defaults.removeObject(forKey: "appearance.inAppLogoStyle")
        XCTAssertEqual(Settings.inAppLogoStyle, .color)
    }
}
