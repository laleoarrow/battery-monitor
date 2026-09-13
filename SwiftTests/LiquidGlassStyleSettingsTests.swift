import Foundation
import XCTest
@testable import Wattson

final class LiquidGlassStyleSettingsTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "Wattson.LiquidGlassStyle.Tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        Settings.configureForTest(defaults: defaults)
    }

    override func tearDown() {
        Settings.resetTestConfiguration()
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testDefaultAndInvalidValuesAreRegularWithoutWriting() {
        XCTAssertEqual(Settings.LiquidGlassStyle.allCases.map(\.rawValue), ["regular", "clear"])
        XCTAssertEqual(Settings.liquidGlassStyle, .regular)
        XCTAssertTrue((defaults.persistentDomain(forName: suiteName) ?? [:]).isEmpty)
        for value: Any in ["future-style", ["invalid"], 1] {
            defaults.set(value, forKey: "appearance.liquidGlassStyle")
            XCTAssertEqual(Settings.liquidGlassStyle, .regular)
        }
    }

    func testChoicePersistsThroughOffOnAndReopeningDefaults() {
        Settings.liquidGlassStyle = .clear
        XCTAssertFalse(Settings.liquidGlassEnabled)
        XCTAssertFalse(Settings.usesLiquidGlass)
        XCTAssertEqual(defaults.string(forKey: "appearance.liquidGlassStyle"), "clear")
        Settings.liquidGlassEnabled = true
        Settings.liquidGlassEnabled = false
        XCTAssertEqual(Settings.liquidGlassStyle, .clear)
        Settings.configureForTest(defaults: UserDefaults(suiteName: suiteName)!)
        XCTAssertEqual(Settings.liquidGlassStyle, .clear)
        Settings.liquidGlassEnabled = true
        XCTAssertEqual(Settings.liquidGlassStyle, .clear)
        Settings.liquidGlassStyle = .regular
        XCTAssertEqual(defaults.string(forKey: "appearance.liquidGlassStyle"), "regular")
    }

    func testStyleUsesExistingAppearanceNotificationExactlyOnceAfterPersistence() {
        var changes: [Settings.Change] = []
        var observed: [String] = []
        let observer = NotificationCenter.default.addObserver(
            forName: Settings.didChange, object: nil, queue: nil
        ) { [defaults] notification in
            if let change = notification.userInfo?[Settings.changeUserInfoKey] as? Settings.Change {
                changes.append(change)
                observed.append(defaults?.string(forKey: "appearance.liquidGlassStyle") ?? "missing")
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        Settings.liquidGlassStyle = .regular
        XCTAssertTrue(changes.isEmpty)
        Settings.liquidGlassStyle = .clear
        Settings.liquidGlassStyle = .clear
        XCTAssertEqual(changes, [.liquidGlassAppearance])
        XCTAssertEqual(observed, ["clear"])
        Settings.liquidGlassStyle = .regular
        XCTAssertEqual(changes, [.liquidGlassAppearance, .liquidGlassAppearance])
        XCTAssertEqual(observed, ["clear", "regular"])
    }

    func testExternalChangesAreReadWithoutChangingGlassOptIn() {
        defaults.set("clear", forKey: "appearance.liquidGlassStyle")
        XCTAssertEqual(Settings.liquidGlassStyle, .clear)
        XCTAssertFalse(Settings.liquidGlassEnabled)
        defaults.removeObject(forKey: "appearance.liquidGlassStyle")
        XCTAssertEqual(Settings.liquidGlassStyle, .regular)
        XCTAssertFalse(Settings.liquidGlassEnabled)
    }
}
