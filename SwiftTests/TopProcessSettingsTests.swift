import Foundation
import XCTest
@testable import Wattson

final class TopProcessSettingsTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!
    private let key = "popover.topProcessCount"

    override func setUp() {
        super.setUp()
        suite = "Wattson.SwiftTests.TopProcesses.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        Settings.configureForTest(defaults: defaults)
    }

    override func tearDown() {
        Settings.resetTestConfiguration()
        defaults.removePersistentTestDomain(forName: suite)
        defaults = nil
        super.tearDown()
    }

    func testNewModuleDefaultsVisibleAtEndAndCountDefaultsThreeWithoutWriting() {
        XCTAssertEqual(Settings.Module.allCases.last, .topProcesses)
        XCTAssertEqual(Settings.Module.topProcesses.title, "Process Activity")
        XCTAssertTrue(Settings.isModuleVisible(.topProcesses))
        XCTAssertEqual(Settings.topProcessCount, 3)
        XCTAssertNil(defaults.object(forKey: key))
        XCTAssertNil(defaults.object(forKey: Settings.Module.topProcesses.defaultsKey))
    }

    func testBoundsClampOnReadWithoutRewritingAndInvalidValuesUseDefault() {
        for (stored, expected) in [(0, 1), (-100, 1), (1, 1), (10, 10), (11, 10), (Int.max, 10)] {
            defaults.set(stored, forKey: key)
            XCTAssertEqual(Settings.topProcessCount, expected)
            XCTAssertEqual(defaults.integer(forKey: key), stored)
        }
        for invalid: Any in ["invalid", true, false, 3.5, [3], ["count": 3]] {
            defaults.set(invalid, forKey: key)
            XCTAssertEqual(Settings.topProcessCount, 3)
        }
        defaults.removeObject(forKey: key)
        XCTAssertEqual(Settings.topProcessCount, 3)
    }

    func testSetterPersistsClampedCountAndRetainsItWhileModuleIsHidden() {
        Settings.topProcessCount = -20
        XCTAssertEqual(defaults.integer(forKey: key), 1)
        Settings.topProcessCount = 100
        XCTAssertEqual(defaults.integer(forKey: key), 10)
        Settings.setModule(.topProcesses, visible: false)
        Settings.configureForTest(defaults: UserDefaults(suiteName: suite)!)
        XCTAssertEqual(Settings.topProcessCount, 10)
        XCTAssertFalse(Settings.isModuleVisible(.topProcesses))
        Settings.setModule(.topProcesses, visible: true)
        XCTAssertEqual(Settings.topProcessCount, 10)
    }

    func testOnlyChangedEffectiveCountsNotifyAfterPersistence() {
        var changes: [Settings.Change] = []
        var values: [Int] = []
        let observer = NotificationCenter.default.addObserver(
            forName: Settings.didChange, object: nil, queue: nil
        ) { [defaults, key] notification in
            changes.append(notification.userInfo?[Settings.changeUserInfoKey] as! Settings.Change)
            values.append(defaults!.integer(forKey: key))
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        Settings.topProcessCount = 3
        Settings.topProcessCount = 0
        Settings.topProcessCount = -1
        Settings.topProcessCount = 10
        Settings.topProcessCount = 100
        XCTAssertEqual(changes, [.topProcessCount, .topProcessCount])
        XCTAssertEqual(values, [1, 10])
    }
}
