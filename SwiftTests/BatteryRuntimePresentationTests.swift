import AppKit
import XCTest
@testable import Wattson

final class BatteryRuntimePresentationTests: XCTestCase {
    func testRuntimeUsesHoursAndMinutesWithoutLosingOtherHeaderReadings() {
        let header = PopoverHeaderView()
        let runtime = PopoverRuntimeView()
        header.frame = NSRect(x: 0, y: 0, width: PopoverStyle.contentWidth,
                              height: PopoverHeaderView.preferredHeight)
        XCTAssertEqual(PopoverHeaderView.preferredHeight + PopoverRuntimeView.preferredHeight, 72)
        for (minutes, text) in [(0, "<1m"), (35, "35m"), (60, "1h 0m"), (265, "4h 25m")] {
            let snapshot = PowerSnapshot(percent: 41, batteryW: -12, systemW: 12,
                                         estimatedRuntimeMinutes: minutes)
            XCTAssertEqual(runtime.runtimePresentationForTest(snapshot: snapshot),
                           "Est. Battery Runtime · \(text)")
            XCTAssertEqual(header.statePresentationForTest(snapshot: snapshot).text, "On Battery")
            XCTAssertTrue(header.layoutFitsForTest(snapshot: snapshot))
            XCTAssertTrue(runtime.layoutFitsForTest(snapshot: snapshot))
        }
    }

    func testRuntimeHidesOldOrUnknownEstimatesAndNeverShowsACAsBatteryRuntime() {
        let runtime = PopoverRuntimeView()
        let known = PowerSnapshot(percent: 41, batteryW: -12, systemW: 12,
                                  estimatedRuntimeMinutes: 265)
        XCTAssertEqual(runtime.runtimePresentationForTest(snapshot: known, degraded: true),
                       "Est. Battery Runtime · Unavailable")
        for minutes in [nil, -1] as [Int?] {
            var unknown = known
            unknown.estimatedRuntimeMinutes = minutes
            XCTAssertEqual(runtime.runtimePresentationForTest(snapshot: unknown),
                           "Est. Battery Runtime · Estimating…")
        }
        for batteryW in [20.0, 0, -12] {
            let snapshot = PowerSnapshot(percent: 100, plugged: true, adapterW: 40,
                                         batteryW: batteryW, systemW: 40 - batteryW,
                                         estimatedRuntimeMinutes: 265)
            XCTAssertEqual(runtime.runtimePresentationForTest(snapshot: snapshot),
                           "Est. Battery Runtime · External Power")
        }
    }

    func testLowBatteryAndLowPowerKeepTheMacOSEstimate() {
        let runtime = PopoverRuntimeView()
        for lowPower in [false, true] {
            let snapshot = PowerSnapshot(percent: 8, batteryW: -10, systemW: 10,
                                         lowPowerMode: lowPower, estimatedRuntimeMinutes: 18)
            XCTAssertEqual(runtime.runtimePresentationForTest(snapshot: snapshot),
                           "Est. Battery Runtime · 18m")
        }
    }

    func testRuntimeMenuChoiceRemovesExactlyItsOwnHeightAndPersists() {
        withIsolatedSettings { defaults in
            let content = PopoverContentViewController()
            _ = content.view
            let defaultHeight = content.preferredHeight
            XCTAssertFalse(content.moduleIsHiddenForTest(.runtime))

            content.toggleModuleFromMenuForTest(.runtime)

            XCTAssertFalse(Settings.isModuleVisible(.runtime))
            XCTAssertEqual(defaults.object(forKey: Settings.Module.runtime.defaultsKey) as? Bool, false)
            XCTAssertTrue(content.moduleIsHiddenForTest(.runtime))
            XCTAssertEqual(content.preferredHeight, defaultHeight - 24)
            for module in [PopoverModule.flow, .ring, .lanes, .history] {
                XCTAssertFalse(content.moduleIsHiddenForTest(module))
            }
            let reopened = PopoverContentViewController()
            _ = reopened.view
            XCTAssertTrue(reopened.moduleIsHiddenForTest(.runtime))
            XCTAssertEqual(reopened.preferredHeight, defaultHeight - 24)

            content.toggleModuleFromMenuForTest(.runtime)
            XCTAssertEqual(content.preferredHeight, defaultHeight)
            XCTAssertFalse(reopened.moduleIsHiddenForTest(.runtime))
        }
    }

    func testHiddenRuntimeSkipsRenderingAndShowsNewestCachedState() {
        withIsolatedSettings { _ in
            let content = PopoverContentViewController()
            _ = content.view
            content.setPresentationActive(true)
            content.update(snapshot: PowerSnapshot(estimatedRuntimeMinutes: 265),
                           history: [], peak: 0, degraded: false)
            XCTAssertEqual(content.runtimePresentationForTest, "Est. Battery Runtime · 4h 25m")
            Settings.setModule(.runtime, visible: false)
            let before = content.moduleUpdateCountsForTest[.runtime, default: 0]

            content.update(snapshot: PowerSnapshot(estimatedRuntimeMinutes: 35),
                           history: [], peak: 0, degraded: true)
            XCTAssertEqual(content.moduleUpdateCountsForTest[.runtime, default: 0], before)
            XCTAssertEqual(content.runtimePresentationForTest, "Est. Battery Runtime · 4h 25m")

            Settings.setModule(.runtime, visible: true)
            XCTAssertEqual(content.moduleUpdateCountsForTest[.runtime, default: 0], before + 1)
            XCTAssertEqual(content.runtimePresentationForTest, "Est. Battery Runtime · Unavailable")
            Settings.setModule(.runtime, visible: false)
            content.update(snapshot: PowerSnapshot(estimatedRuntimeMinutes: 35),
                           history: [], peak: 0, degraded: false)
            Settings.setModule(.runtime, visible: true)
            XCTAssertEqual(content.runtimePresentationForTest, "Est. Battery Runtime · 35m")
        }
    }

    private func withIsolatedSettings(_ body: (UserDefaults) -> Void) {
        let suiteName = "Wattson.RuntimeModule.Tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        Settings.configureForTest(defaults: defaults)
        defer {
            Settings.resetTestConfiguration()
            defaults.removePersistentDomain(forName: suiteName)
        }
        body(defaults)
    }
}
