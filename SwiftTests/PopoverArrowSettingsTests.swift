import Foundation
import XCTest
@testable import Wattson

final class PopoverArrowSettingsTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!
    private let key = "appearance.showPopoverArrow"

    override func setUp() {
        super.setUp()
        suite = "Wattson.SwiftTests.PopoverArrow.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        Settings.configureForTest(defaults: defaults)
    }

    override func tearDown() {
        Settings.resetTestConfiguration()
        defaults.removePersistentTestDomain(forName: suite)
        defaults = nil
        super.tearDown()
    }

    func testDefaultRetainsArrowWithoutPersistingAndInvalidValuesUseDefault() {
        XCTAssertTrue(Settings.showPopoverArrow)
        XCTAssertNil(defaults.object(forKey: key))
        for invalid: Any in ["invalid", [false], ["arrow": false]] {
            defaults.set(invalid, forKey: key)
            XCTAssertTrue(Settings.showPopoverArrow)
        }
    }

    func testChoicePersistsIndependentlyOfGlassStyleThemeAndClassic() {
        Settings.showPopoverArrow = false
        Settings.liquidGlassEnabled = true
        Settings.liquidGlassStyle = .clear
        Settings.colorScheme = .light
        Settings.liquidGlassTransparency = 0.5
        Settings.liquidGlassEnabled = false
        Settings.configureForTest(defaults: UserDefaults(suiteName: suite)!)
        XCTAssertFalse(Settings.showPopoverArrow)
        Settings.liquidGlassEnabled = true
        Settings.liquidGlassStyle = .regular
        Settings.colorScheme = .dark
        XCTAssertFalse(Settings.showPopoverArrow)
        XCTAssertEqual(defaults.object(forKey: key) as? Bool, false)
    }

    func testChangeNotifiesOnceAfterPersistenceWithoutAppearanceReplacement() {
        var changes: [Settings.Change] = []
        var values: [Bool] = []
        let observer = NotificationCenter.default.addObserver(
            forName: Settings.didChange, object: nil, queue: nil
        ) { [defaults, key] notification in
            changes.append(notification.userInfo?[Settings.changeUserInfoKey] as! Settings.Change)
            values.append(defaults!.object(forKey: key) as! Bool)
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        Settings.showPopoverArrow = true
        Settings.showPopoverArrow = false
        Settings.showPopoverArrow = false
        Settings.showPopoverArrow = true
        XCTAssertEqual(changes, [.popoverArrow, .popoverArrow])
        XCTAssertEqual(values, [false, true])
    }

    func testExternalWritesAndRemovalAreReadWithoutChangingClassicPreference() {
        defaults.set(false, forKey: key)
        XCTAssertFalse(Settings.showPopoverArrow)
        XCTAssertFalse(Settings.liquidGlassEnabled)
        defaults.removeObject(forKey: key)
        XCTAssertTrue(Settings.showPopoverArrow)
        XCTAssertFalse(Settings.liquidGlassEnabled)
    }
}
