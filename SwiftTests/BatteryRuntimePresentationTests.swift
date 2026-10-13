import AppKit
import XCTest
@testable import Wattson

final class BatteryRuntimePresentationTests: XCTestCase {
    func testRuntimeUsesHoursAndMinutesWithoutLosingOtherHeaderReadings() {
        let header = PopoverHeaderView()
        header.frame = NSRect(x: 0, y: 0, width: PopoverStyle.contentWidth,
                              height: PopoverHeaderView.preferredHeight)
        for (minutes, text) in [(0, "<1m"), (35, "35m"), (60, "1h 0m"), (265, "4h 25m")] {
            let snapshot = PowerSnapshot(percent: 41, batteryW: -12, systemW: 12,
                                         estimatedRuntimeMinutes: minutes)
            XCTAssertEqual(header.runtimePresentationForTest(snapshot: snapshot),
                           "Est. Battery Runtime · \(text)")
            XCTAssertEqual(header.statePresentationForTest(snapshot: snapshot).text, "On Battery")
            XCTAssertTrue(header.layoutFitsForTest(snapshot: snapshot))
        }
    }

    func testRuntimeHidesOldOrUnknownEstimatesAndNeverShowsACAsBatteryRuntime() {
        let header = PopoverHeaderView()
        let known = PowerSnapshot(percent: 41, batteryW: -12, systemW: 12,
                                  estimatedRuntimeMinutes: 265)
        XCTAssertEqual(header.runtimePresentationForTest(snapshot: known, degraded: true),
                       "Est. Battery Runtime · Unavailable")
        for minutes in [nil, -1] as [Int?] {
            var unknown = known
            unknown.estimatedRuntimeMinutes = minutes
            XCTAssertEqual(header.runtimePresentationForTest(snapshot: unknown),
                           "Est. Battery Runtime · Estimating…")
        }
        for batteryW in [20.0, 0, -12] {
            let snapshot = PowerSnapshot(percent: 100, plugged: true, adapterW: 40,
                                         batteryW: batteryW, systemW: 40 - batteryW,
                                         estimatedRuntimeMinutes: 265)
            XCTAssertEqual(header.runtimePresentationForTest(snapshot: snapshot),
                           "Est. Battery Runtime · External Power")
        }
    }

    func testLowBatteryAndLowPowerKeepTheMacOSEstimate() {
        let header = PopoverHeaderView()
        for lowPower in [false, true] {
            let snapshot = PowerSnapshot(percent: 8, batteryW: -10, systemW: 10,
                                         lowPowerMode: lowPower, estimatedRuntimeMinutes: 18)
            XCTAssertEqual(header.runtimePresentationForTest(snapshot: snapshot),
                           "Est. Battery Runtime · 18m")
        }
    }
}
