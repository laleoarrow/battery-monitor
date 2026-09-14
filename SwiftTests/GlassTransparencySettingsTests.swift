import Foundation
import XCTest
@testable import Wattson

final class GlassTransparencySettingsTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!
    private let key = "appearance.liquidGlassTransparency"

    override func setUp() {
        super.setUp()
        suite = "Wattson.GlassTransparency.Tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        Settings.configureForTest(defaults: defaults)
    }

    override func tearDown() {
        Settings.resetTestConfiguration()
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        super.tearDown()
    }

    func testDefaultPreservesNativeGlassAndInvalidValuesCannotEscapeRange() {
        XCTAssertEqual(Settings.liquidGlassTransparency, 1)
        XCTAssertNil(defaults.object(forKey: key))
        for invalid: Any in ["invalid", [1], Double.nan, Double.infinity] {
            defaults.set(invalid, forKey: key)
            XCTAssertEqual(Settings.liquidGlassTransparency, 1)
        }
        defaults.set(-1, forKey: key)
        XCTAssertEqual(Settings.liquidGlassTransparency, 0)
        defaults.set(2, forKey: key)
        XCTAssertEqual(Settings.liquidGlassTransparency, 1)
        Settings.liquidGlassTransparency = 0.45
        Settings.liquidGlassTransparency = .nan
        Settings.liquidGlassTransparency = .infinity
        XCTAssertEqual(Settings.liquidGlassTransparency, 0.45)
        Settings.liquidGlassTransparency = -1
        XCTAssertEqual(Settings.liquidGlassTransparency, 0)
        Settings.liquidGlassTransparency = 2
        XCTAssertEqual(Settings.liquidGlassTransparency, 1)
    }

    func testChoicePersistsIndependentlyOfThemeMaterialAndGlassToggle() {
        Settings.liquidGlassTransparency = 0.37
        Settings.liquidGlassEnabled = true
        Settings.liquidGlassStyle = .clear
        Settings.colorScheme = .dark
        Settings.liquidGlassEnabled = false
        Settings.configureForTest(defaults: UserDefaults(suiteName: suite)!)
        XCTAssertEqual(Settings.liquidGlassTransparency, 0.37)
        Settings.liquidGlassEnabled = true
        Settings.liquidGlassStyle = .regular
        XCTAssertEqual(Settings.liquidGlassTransparency, 0.37)
    }

    func testChangeNotifiesAfterPersistenceWithoutRequestingHostReplacement() {
        var changes: [Settings.Change] = []
        var values: [Double] = []
        let observer = NotificationCenter.default.addObserver(
            forName: Settings.didChange, object: nil, queue: nil
        ) { notification in
            changes.append(notification.userInfo?[Settings.changeUserInfoKey] as! Settings.Change)
            values.append(Settings.liquidGlassTransparency)
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        Settings.liquidGlassTransparency = 1
        Settings.liquidGlassTransparency = 0.5
        Settings.liquidGlassTransparency = 0.5
        Settings.liquidGlassTransparency = 0
        XCTAssertEqual(changes, [.liquidGlassTransparency, .liquidGlassTransparency])
        XCTAssertEqual(values, [0.5, 0])
    }
}
