import AppKit
import XCTest
@testable import Wattson

final class RingMetricViewTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
        suite = "Wattson.SwiftTests.RingMetricView.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        Settings.configureForTest(defaults: defaults)
    }

    override func tearDown() {
        Settings.resetTestConfiguration()
        defaults.removePersistentTestDomain(forName: suite)
        defaults = nil
        super.tearDown()
    }

    private func makeGauge() -> RingGaugeView {
        let gauge = RingGaugeView()
        gauge.frame = NSRect(x: 0, y: 0, width: PopoverStyle.contentWidth,
                             height: RingGaugeView.preferredHeight)
        return gauge
    }

    func testDefaultSelectionRetainsFourReadingsAndHeight() {
        let gauge = makeGauge()
        gauge.update(snapshot: PowerSnapshot(percent: 72, plugged: true, batteryW: 7.8,
                                             systemW: 26.6, temperatureC: 33.1, cycleCount: 307))
        gauge.layoutSubtreeIfNeeded()
        XCTAssertEqual(gauge.selectedMetricsForTest, Settings.defaultRingMetrics)
        XCTAssertEqual(gauge.bounds.height, 138)
        XCTAssertEqual(gauge.readingForTest(.systemLoad)?.value, "26.6 W")
        XCTAssertEqual(gauge.readingForTest(.batteryPower)?.caption, "To Battery")
        XCTAssertEqual(gauge.readingForTest(.temperature)?.value, "33.1°C")
        XCTAssertEqual(gauge.readingForTest(.cycleCount)?.value, "307")
        XCTAssertTrue(gauge.statsFitBoundsForTest)
    }

    func testFourElectricalReadingsFitAndKeepBatteryAndAdapterValuesDistinct() {
        Settings.ringMetrics = [.batteryVoltage, .batteryCurrent, .adapterVoltage, .adapterCurrent]
        let gauge = makeGauge()
        let snapshot = PowerSnapshot(percent: 72, plugged: true, adapterW: 34.4,
                                     batteryW: 7.8, systemW: 26.6, deviceOutputW: 2.2,
                                     temperatureC: 33.1, cycleCount: 307,
                                     batteryVoltageV: 12.81, batteryCurrentMA: 607,
                                     adapterVoltageV: 20, adapterCurrentMA: 2237,
                                     batteryHealthPercent: 81.3, maxCapacityMAh: 6975,
                                     designCapacityMAh: 8579, batteryTimeEstimate: .charging(5))
        gauge.update(snapshot: snapshot)
        gauge.layoutSubtreeIfNeeded()
        XCTAssertEqual(gauge.readingForTest(.batteryVoltage)?.caption, "Battery Voltage")
        XCTAssertEqual(gauge.readingForTest(.batteryVoltage)?.value, "12.81 V")
        XCTAssertEqual(gauge.readingForTest(.adapterVoltage)?.caption, "Adapter Voltage")
        XCTAssertEqual(gauge.readingForTest(.adapterVoltage)?.value, "20.00 V")
        XCTAssertEqual(gauge.readingForTest(.batteryCurrent)?.value, "+607 mA")
        XCTAssertEqual(gauge.readingForTest(.adapterCurrent)?.value, "2237 mA")
        XCTAssertEqual(gauge.bounds.height, 138)
        XCTAssertTrue(gauge.statsFitBoundsForTest)

        Settings.ringMetrics = [.timeEstimate, .batteryHealth, .maxCapacity, .designCapacity]
        gauge.reloadMetrics()
        gauge.update(snapshot: snapshot)
        gauge.layoutSubtreeIfNeeded()
        XCTAssertEqual(gauge.readingForTest(.batteryHealth)?.value, "81%")
        XCTAssertEqual(gauge.readingForTest(.timeEstimate)?.value, "5m")
        XCTAssertEqual(gauge.readingForTest(.maxCapacity)?.value, "6975 mAh")
        XCTAssertEqual(gauge.readingForTest(.designCapacity)?.value, "8579 mAh")
        XCTAssertTrue(gauge.statsFitBoundsForTest)

        Settings.ringMetrics = [.systemLoad, .cycleCount, .adapterPower, .deviceOutput]
        gauge.reloadMetrics()
        gauge.update(snapshot: snapshot)
        gauge.layoutSubtreeIfNeeded()
        XCTAssertEqual(gauge.readingForTest(.cycleCount)?.value, "307")
        XCTAssertEqual(gauge.readingForTest(.adapterPower)?.value, "34.4 W")
        XCTAssertEqual(gauge.readingForTest(.deviceOutput)?.value, "2.2 W")
        XCTAssertTrue(gauge.statsFitBoundsForTest)
    }

    func testUnknownValuesStayUnavailableAndDischargeCurrentKeepsItsSign() {
        let groups: [[Settings.RingMetric]] = [
            [.batteryCurrent, .batteryVoltage, .adapterVoltage, .adapterCurrent],
            [.batteryHealth, .maxCapacity, .designCapacity, .timeEstimate],
        ]
        for group in groups {
            Settings.ringMetrics = group
            let gauge = makeGauge()
            gauge.update(snapshot: PowerSnapshot(batteryCurrentMA: -920))
            for metric in group {
                XCTAssertEqual(gauge.readingForTest(metric)?.value, metric == .batteryCurrent ? "-920 mA" : "—")
            }
        }
    }

    func testTimeEstimateFollowsPowerStateAndStatusWordsFit() {
        Settings.ringMetrics = [.timeEstimate]
        let gauge = makeGauge()
        let cases: [(PowerSnapshot, String)] = [
            (PowerSnapshot(plugged: true, batteryW: 1, batteryTimeEstimate: .charging(nil)), "Calculating…"),
            (PowerSnapshot(percent: 100, plugged: true, batteryTimeEstimate: .full), "Fully Charged"),
            (PowerSnapshot(plugged: true, batteryTimeEstimate: .notCharging), "Not Charging"),
            (PowerSnapshot(plugged: true, batteryW: -1, batteryTimeEstimate: .charging(3)), "Not Charging"),
            (PowerSnapshot(batteryTimeEstimate: .remaining(265)), "4h 25m"),
            (PowerSnapshot(batteryTimeEstimate: .remaining(0)), "<1m"),
            (PowerSnapshot(batteryTimeEstimate: .remaining(18), batteryTimeEstimateSource: .observedDischarge), "≈18m"),
            (PowerSnapshot(batteryTimeEstimate: .charging(4)), "—"),
        ]
        for (snapshot, expected) in cases {
            gauge.update(snapshot: snapshot)
            gauge.layoutSubtreeIfNeeded()
            XCTAssertEqual(gauge.readingForTest(.timeEstimate)?.value, expected)
            XCTAssertTrue(gauge.statsFitBoundsForTest, expected)
        }
    }

    func testFailedSamplingHidesRetainedTimeEstimateInOpenPopover() throws {
        Settings.ringMetrics = [.timeEstimate]
        let content = PopoverContentViewController()
        content.setViewportHeight(content.preferredHeight)
        let gauge = try XCTUnwrap(content.moduleViewForTest(.ring) as? RingGaugeView)
        let snapshot = PowerSnapshot(plugged: true, batteryW: 1, batteryTimeEstimate: .charging(5))
        content.update(snapshot: snapshot, history: [], peak: 0, degraded: false)
        XCTAssertEqual(gauge.readingForTest(.timeEstimate)?.value, "5m")
        content.update(snapshot: snapshot, history: [], peak: 0, degraded: true)
        XCTAssertEqual(gauge.readingForTest(.timeEstimate)?.value, "—")
        Settings.ringMetrics = [.batteryVoltage, .timeEstimate]
        XCTAssertEqual(gauge.readingForTest(.timeEstimate)?.value, "—")
        content.update(snapshot: snapshot, history: [], peak: 0, degraded: false)
        XCTAssertEqual(gauge.readingForTest(.timeEstimate)?.value, "5m")
    }

    func testFifthSelectionReplacesOldestWithoutResizingOrLosingRetainedReadings() throws {
        let content = PopoverContentViewController()
        content.setViewportHeight(content.preferredHeight)
        let gauge = try XCTUnwrap(content.moduleViewForTest(.ring) as? RingGaugeView)
        content.update(snapshot: PowerSnapshot(cycleCount: 307, batteryVoltageV: 12.81),
                       history: [], peak: 0, degraded: false)
        let initialHeight = content.preferredHeight
        var heightChanges = 0
        content.heightDidChange = { [weak content] in
            heightChanges += 1
            content?.setViewportHeight($0)
        }

        Settings.ringMetrics += [.batteryVoltage]
        content.view.layoutSubtreeIfNeeded()
        XCTAssertTrue(gauge === content.moduleViewForTest(.ring))
        XCTAssertEqual(gauge.selectedMetricsForTest, [.batteryPower, .temperature, .cycleCount, .batteryVoltage])
        XCTAssertNil(gauge.readingForTest(.systemLoad))
        XCTAssertEqual(content.preferredHeight, initialHeight)
        XCTAssertEqual(gauge.frame.height, 138)
        XCTAssertEqual(heightChanges, 0)
        XCTAssertEqual(gauge.readingForTest(.batteryVoltage)?.value, "12.81 V")
        XCTAssertEqual(gauge.readingForTest(.cycleCount)?.value, "307")
        XCTAssertTrue(gauge.statsFitBoundsForTest)

        Settings.setModule(.ring, visible: false)
        let hiddenHeight = content.preferredHeight
        Settings.ringMetrics = []
        XCTAssertEqual(content.preferredHeight, hiddenHeight)
        Settings.setModule(.ring, visible: true)
        XCTAssertEqual(gauge.frame.height, 138)
        XCTAssertEqual(gauge.visibleReadingFramesForTest, [])
        XCTAssertEqual(content.preferredHeight, initialHeight)

        Settings.ringMetrics = Settings.defaultRingMetrics
        XCTAssertEqual(gauge.readingForTest(.cycleCount)?.value, "307")
        XCTAssertEqual(content.preferredHeight, initialHeight)
    }
}
