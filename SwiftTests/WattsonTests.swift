import XCTest
@testable import Wattson

final class WattsonTests: XCTestCase {
    func testPowerSnapshotUsesSignedBatteryFlow() {
        let charging = PowerSnapshot(
            percent: 60,
            plugged: true,
            adapterW: 70,
            batteryW: 20,
            systemW: 50
        )
        XCTAssertEqual(charging.totalInputW, 70, accuracy: 0.001)
        XCTAssertEqual(charging.conservationError, 0, accuracy: 0.001)

        let mixed = PowerSnapshot(
            percent: 40,
            plugged: true,
            adapterW: 35,
            batteryW: -10,
            systemW: 45
        )
        XCTAssertEqual(mixed.totalInputW, 45, accuracy: 0.001)
        XCTAssertEqual(mixed.conservationError, 0, accuracy: 0.001)
    }

    func testHistoryIsBoundedAndChronological() {
        let history = PowerHistory()
        for value in 0..<75 {
            history.append(Double(value))
        }

        XCTAssertEqual(history.samples.count, 60)
        XCTAssertEqual(history.samples.first, 15)
        XCTAssertEqual(history.samples.last, 74)
        XCTAssertEqual(history.peak, 74)
    }
}
