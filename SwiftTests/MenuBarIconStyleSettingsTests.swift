import Foundation
import XCTest
@testable import Wattson

final class MenuBarIconStyleSettingsTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = ProcessInfo.processInfo.environment["WATTSON_ICON_STYLE_TEST_DEFAULTS_SUITE"]
            .map { registerTestDefaultsSuite($0) }
            ?? testDefaultsSuite("MenuBarIconStyle")
        defaults = UserDefaults(suiteName: suiteName)!
        Settings.configureForTest(defaults: defaults)
    }

    override func tearDown() {
        Settings.resetTestConfiguration()
        defaults.removePersistentTestDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testStableStyleValuesAndDefaultDoNotWritePreferences() {
        XCTAssertEqual(Settings.MenuBarIconStyle.allCases.map(\.rawValue), ["wattson", "native", "native27"])
        XCTAssertEqual(Settings.MenuBarIconStyle.allCases.map(\.title), ["Wattson", "macOS 26", "macOS 27"])
        XCTAssertEqual(Settings.MenuBarIconStyle.allCases.map(\.identifierSuffix), ["wattson", "macos", "macos27"])
        XCTAssertEqual(Settings.menuBarIconStyle, .wattson)
        XCTAssertTrue(Settings.showsMenuBarPercentage)
        XCTAssertTrue((defaults.persistentDomain(forName: suiteName) ?? [:]).isEmpty)
    }

    func testAllSixAppearancesPersistWithoutChangingOtherPreferences() {
        Settings.inAppLogoStyle = .clear
        Settings.liquidGlassEnabled = true
        Settings.setModule(.topProcesses, visible: false)
        for style in Settings.MenuBarIconStyle.allCases {
            for percentage in [false, true] {
                Settings.setMenuBarAppearance(iconStyle: style, showsPercentage: percentage)
                Settings.configureForTest(defaults: UserDefaults(suiteName: suiteName)!)
                XCTAssertEqual(Settings.menuBarIconStyle, style)
                XCTAssertEqual(Settings.showsMenuBarPercentage, percentage)
                XCTAssertEqual(defaults.string(forKey: "menubar.iconStyle"), style.rawValue)
                XCTAssertEqual(defaults.object(forKey: "menubar.showsPercentage") as? Bool, percentage)
                XCTAssertEqual(Settings.inAppLogoStyle, .clear)
                XCTAssertTrue(Settings.liquidGlassEnabled)
                XCTAssertFalse(Settings.isModuleVisible(.topProcesses))
            }
        }
    }

    func testEveryAtomicAppearanceTransitionNotifiesOnlyAfterBothValuesPersist() {
        var changes: [Settings.Change] = []
        var observed: [(String?, Bool?)] = []
        var keptNilObject = true
        let observer = NotificationCenter.default.addObserver(
            forName: Settings.didChange, object: nil, queue: nil
        ) { [defaults] notification in
            keptNilObject = keptNilObject && notification.object == nil
            if let change = notification.userInfo?[Settings.changeUserInfoKey] as? Settings.Change {
                changes.append(change)
                observed.append((
                    defaults?.string(forKey: "menubar.iconStyle"),
                    defaults?.object(forKey: "menubar.showsPercentage") as? Bool
                ))
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        for initialStyle in Settings.MenuBarIconStyle.allCases {
            for initialPercentage in [false, true] {
                for targetStyle in Settings.MenuBarIconStyle.allCases {
                    for targetPercentage in [false, true] {
                        Settings.setMenuBarAppearance(iconStyle: initialStyle, showsPercentage: initialPercentage)
                        changes.removeAll()
                        observed.removeAll()
                        Settings.setMenuBarAppearance(iconStyle: targetStyle, showsPercentage: targetPercentage)
                        var expected: [Settings.Change] = []
                        if initialStyle != targetStyle { expected.append(.menuBarIconStyle) }
                        if initialPercentage != targetPercentage { expected.append(.menuBarPercentage) }
                        XCTAssertEqual(changes, expected)
                        XCTAssertEqual(observed.count, expected.count)
                        XCTAssertTrue(observed.allSatisfy {
                            $0.0 == targetStyle.rawValue && $0.1 == targetPercentage
                        })
                        XCTAssertEqual(Settings.menuBarIconStyle, targetStyle)
                        XCTAssertEqual(Settings.showsMenuBarPercentage, targetPercentage)
                        Settings.setMenuBarAppearance(iconStyle: targetStyle, showsPercentage: targetPercentage)
                        XCTAssertEqual(changes, expected, "Repeating a landed choice must not notify")
                    }
                }
            }
        }
        XCTAssertTrue(keptNilObject)
    }

    func testChangingStyleAlonePreservesPercentageAndUsesExistingNotification() {
        var changes: [Settings.Change] = []
        let observer = NotificationCenter.default.addObserver(
            forName: Settings.didChange, object: nil, queue: nil
        ) { notification in
            if let change = notification.userInfo?[Settings.changeUserInfoKey] as? Settings.Change {
                changes.append(change)
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        for percentage in [false, true] {
            Settings.showsMenuBarPercentage = percentage
            for style in [Settings.MenuBarIconStyle.native27, .native, .wattson] {
                changes.removeAll()
                Settings.menuBarIconStyle = style
                Settings.menuBarIconStyle = style
                XCTAssertEqual(changes, [.menuBarIconStyle])
                XCTAssertEqual(Settings.showsMenuBarPercentage, percentage)
            }
        }
    }

    func testLegacyNativeChoiceAndUnknownValuesAreReadWithoutRewriting() {
        defaults.set("native", forKey: "menubar.iconStyle")
        defaults.set(false, forKey: "menubar.showsPercentage")
        Settings.configureForTest(defaults: UserDefaults(suiteName: suiteName)!)
        XCTAssertEqual(Settings.menuBarIconStyle, .native)
        XCTAssertEqual(defaults.string(forKey: "menubar.iconStyle"), "native")
        Settings.showsMenuBarPercentage = true
        XCTAssertEqual(Settings.menuBarIconStyle, .native)
        XCTAssertEqual(defaults.string(forKey: "menubar.iconStyle"), "native")
        for value: Any in ["future-style", ["invalid"], 27] {
            defaults.set(value, forKey: "menubar.iconStyle")
            XCTAssertEqual(Settings.menuBarIconStyle, .wattson)
            XCTAssertEqual(defaults.object(forKey: "menubar.iconStyle") as? NSObject, value as? NSObject)
            XCTAssertTrue(Settings.showsMenuBarPercentage)
        }
    }
}
