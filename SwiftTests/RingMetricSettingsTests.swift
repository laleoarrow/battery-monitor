import AppKit
import XCTest
@testable import Wattson

final class RingMetricSettingsTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!
    private let key = "popover.ringMetrics"

    override func setUp() {
        super.setUp()
        suite = "Wattson.SwiftTests.RingMetrics.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        Settings.configureForTest(defaults: defaults)
    }

    override func tearDown() {
        Settings.resetTestConfiguration()
        defaults.removePersistentTestDomain(forName: suite)
        defaults = nil
        super.tearDown()
    }

    func testDefaultsPreserveExistingFourReadingsWithoutWriting() {
        XCTAssertEqual(Settings.ringMetrics, [.systemLoad, .batteryPower, .temperature, .cycleCount])
        XCTAssertEqual(Settings.ringMetrics, Settings.defaultRingMetrics)
        XCTAssertEqual(Settings.RingMetric.allCases.map(\.title), [
            "System Load", "Battery Power", "Battery Temp", "Cycle Count",
            "Battery Time Estimate", "Battery Health", "Battery Voltage", "Battery Current",
            "Adapter Voltage", "Adapter Current", "Adapter Power", "Device Output",
            "Max Capacity", "Design Capacity",
        ])
        XCTAssertNil(defaults.object(forKey: key))
    }

    func testMalformedTypesFallBackWithoutRewriting() {
        for invalid: Any in ["batteryVoltage", true, 3, ["batteryVoltage", 3], ["metric": "cycleCount"]] {
            defaults.set(invalid, forKey: key)
            XCTAssertEqual(Settings.ringMetrics, Settings.defaultRingMetrics)
            XCTAssertNotNil(defaults.object(forKey: key))
        }
        defaults.removeObject(forKey: key)
        XCTAssertEqual(Settings.ringMetrics, Settings.defaultRingMetrics)
        XCTAssertNil(defaults.object(forKey: key))
    }

    func testReadPreservesSelectionOrderFiltersUnknownAndKeepsLatestFourWithoutRewriting() {
        let raw = ["adapterCurrent", "futureMetric", "batteryVoltage", "adapterCurrent"]
        defaults.set(raw, forKey: key)
        XCTAssertEqual(Settings.ringMetrics, [.adapterCurrent, .batteryVoltage])
        XCTAssertEqual(defaults.stringArray(forKey: key), raw)
        let oversized = ["systemLoad", "batteryPower", "temperature", "cycleCount", "batteryVoltage",
                         "futureMetric", "batteryCurrent", "adapterCurrent", "batteryCurrent"]
        defaults.set(oversized, forKey: key)
        XCTAssertEqual(Settings.ringMetrics, [.cycleCount, .batteryVoltage, .batteryCurrent, .adapterCurrent])
        XCTAssertEqual(defaults.stringArray(forKey: key), oversized)
        defaults.set(["futureMetric"], forKey: key)
        XCTAssertEqual(Settings.ringMetrics, [])
    }

    func testSelectionAndEmptySelectionPersistAcrossHidingAndReopening() {
        Settings.ringMetrics = [.adapterCurrent, .batteryVoltage, .batteryVoltage]
        XCTAssertEqual(defaults.stringArray(forKey: key), ["adapterCurrent", "batteryVoltage"])
        Settings.setModule(.ring, visible: false)
        Settings.configureForTest(defaults: UserDefaults(suiteName: suite)!)
        XCTAssertEqual(Settings.ringMetrics, [.adapterCurrent, .batteryVoltage])
        XCTAssertFalse(Settings.isModuleVisible(.ring))
        Settings.setModule(.ring, visible: true)
        XCTAssertEqual(Settings.ringMetrics, [.adapterCurrent, .batteryVoltage])
        Settings.ringMetrics = []
        Settings.configureForTest(defaults: UserDefaults(suiteName: suite)!)
        XCTAssertEqual(Settings.ringMetrics, [])
        XCTAssertEqual(defaults.stringArray(forKey: key), [])
    }

    func testSetterDeduplicatesBeforeKeepingLatestFourAndRemovalRetainsOrder() {
        Settings.ringMetrics = [
            .systemLoad, .systemLoad, .batteryPower, .temperature, .cycleCount,
            .batteryVoltage, .batteryVoltage, .adapterCurrent,
        ]
        XCTAssertEqual(Settings.ringMetrics, [.temperature, .cycleCount, .batteryVoltage, .adapterCurrent])
        XCTAssertEqual(defaults.stringArray(forKey: key), ["temperature", "cycleCount", "batteryVoltage", "adapterCurrent"])
        Settings.configureForTest(defaults: UserDefaults(suiteName: suite)!)
        Settings.ringMetrics += [.batteryHealth]
        XCTAssertEqual(Settings.ringMetrics, [.cycleCount, .batteryVoltage, .adapterCurrent, .batteryHealth])
        Settings.ringMetrics.removeAll { $0 == .batteryVoltage }
        XCTAssertEqual(Settings.ringMetrics, [.cycleCount, .adapterCurrent, .batteryHealth])
    }

    func testOnlyEffectiveChangesNotifyAfterPersistence() {
        var changes: [Settings.Change] = []
        var values: [[String]] = []
        let observer = NotificationCenter.default.addObserver(
            forName: Settings.didChange, object: nil, queue: nil
        ) { [defaults, key] notification in
            changes.append(notification.userInfo?[Settings.changeUserInfoKey] as! Settings.Change)
            values.append(defaults!.stringArray(forKey: key) ?? [])
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        Settings.ringMetrics = Settings.defaultRingMetrics
        Settings.ringMetrics = Array(Settings.defaultRingMetrics.reversed())
        Settings.ringMetrics = [.adapterCurrent, .batteryVoltage, .adapterCurrent]
        Settings.ringMetrics = [.adapterCurrent, .batteryVoltage]
        Settings.ringMetrics = []
        Settings.ringMetrics = []
        XCTAssertEqual(changes, [.ringMetrics, .ringMetrics, .ringMetrics])
        XCTAssertEqual(values, [
            ["cycleCount", "temperature", "batteryPower", "systemLoad"],
            ["adapterCurrent", "batteryVoltage"], [],
        ])
    }

    func testMenuActionsUpdateBothWindowsAndRestoreDefaultMetrics() throws {
        let first = makeController()
        let second = makeController()
        defer { first.close(); second.close() }
        let firstPopup = try popup(in: first)
        let secondPopup = try popup(in: second)
        XCTAssertTrue(firstPopup.pullsDown)
        XCTAssertEqual(firstPopup.title, "Metrics")
        XCTAssertEqual(firstPopup.accessibilityLabel(), "Ring Gauge Metrics")
        XCTAssertTrue(firstPopup.accessibilityHelp()?.contains("up to four") == true)
        XCTAssertTrue(firstPopup.accessibilityHelp()?.contains("earliest selected") == true)
        XCTAssertEqual(checkedMetrics(in: firstPopup), Settings.defaultRingMetrics)
        try perform(item: metricItem(.batteryCurrent, in: firstPopup))
        let fifth: [Settings.RingMetric] = [.batteryPower, .temperature, .cycleCount, .batteryCurrent]
        XCTAssertEqual(Settings.ringMetrics, fifth)
        XCTAssertEqual(checkedMetrics(in: firstPopup), fifth)
        XCTAssertEqual(checkedMetrics(in: secondPopup), fifth)
        try perform(item: metricItem(.adapterCurrent, in: secondPopup))
        let selected: [Settings.RingMetric] = [.temperature, .cycleCount, .batteryCurrent, .adapterCurrent]
        XCTAssertEqual(Settings.ringMetrics, selected)
        XCTAssertEqual(checkedMetrics(in: firstPopup), selected)
        XCTAssertEqual(checkedMetrics(in: secondPopup), selected)
        try perform(item: metricItem(.batteryCurrent, in: secondPopup))
        XCTAssertEqual(Settings.ringMetrics, [.temperature, .cycleCount, .adapterCurrent])
        try perform(item: metricItem(.systemLoad, in: firstPopup))
        XCTAssertEqual(Settings.ringMetrics, [.temperature, .cycleCount, .adapterCurrent, .systemLoad])
        XCTAssertEqual(Set(checkedMetrics(in: firstPopup)), Set(Settings.ringMetrics))
        XCTAssertEqual(Set(checkedMetrics(in: secondPopup)), Set(Settings.ringMetrics))
        XCTAssertEqual(firstPopup.title, "Metrics")
        let restore = try XCTUnwrap(secondPopup.itemArray.first { $0.title == "Restore Default Metrics" })
        try perform(item: restore)
        XCTAssertEqual(Settings.ringMetrics, Settings.defaultRingMetrics)
        XCTAssertEqual(checkedMetrics(in: firstPopup), Settings.defaultRingMetrics)
        XCTAssertEqual(checkedMetrics(in: secondPopup), Settings.defaultRingMetrics)
        XCTAssertFalse(try XCTUnwrap(first.windowForTest).isVisible)
        XCTAssertFalse(try XCTUnwrap(second.windowForTest).isVisible)
    }

    func testHiddenRingDisablesMenuAndSkipsItInKeyboardLoopWhileRetainingSelection() throws {
        let controller = makeController()
        defer { controller.close() }
        let menu = try popup(in: controller)
        Settings.ringMetrics = [.batteryVoltage, .adapterVoltage]
        XCTAssertTrue(keyLoop(in: controller).contains { $0 === menu })
        Settings.setModule(.ring, visible: false)
        XCTAssertFalse(menu.isEnabled)
        XCTAssertFalse(keyLoop(in: controller).contains { $0 === menu })
        try perform(item: metricItem(.batteryVoltage, in: menu))
        try perform(item: XCTUnwrap(menu.itemArray.first { $0.title == "Restore Default Metrics" }))
        XCTAssertEqual(Settings.ringMetrics, [.batteryVoltage, .adapterVoltage])
        Settings.setModule(.ring, visible: true)
        XCTAssertTrue(menu.isEnabled)
        XCTAssertTrue(keyLoop(in: controller).contains { $0 === menu })
        XCTAssertEqual(checkedMetrics(in: menu), [.batteryVoltage, .adapterVoltage])
    }

    func testMetricsControlSharesDetailRowWithoutOverlappingOrGrowingModule() throws {
        let controller = makeController()
        defer { controller.close() }
        let content = try XCTUnwrap(controller.windowForTest?.contentView)
        content.layoutSubtreeIfNeeded()
        let menu = try popup(in: controller)
        let row = try XCTUnwrap(descendants(content).first {
            $0.identifier?.rawValue == "settings.modules.row.ring"
        })
        let detail = try XCTUnwrap(descendants(row).compactMap { $0 as? NSTextField }.first {
            $0.stringValue == "Battery charge and power at a glance."
        })
        let other = try XCTUnwrap(descendants(content).first {
            $0.identifier?.rawValue == "settings.modules.row.lanes"
        })
        let detailFrame = detail.convert(detail.bounds, to: row)
        let menuFrame = menu.convert(menu.bounds, to: row)
        XCTAssertEqual(row.frame.height, other.frame.height, accuracy: 0.5)
        XCTAssertGreaterThan(menuFrame.width, 40)
        XCTAssertLessThanOrEqual(detailFrame.maxX, menuFrame.minX)
        XCTAssertEqual(detailFrame.midY, menuFrame.midY, accuracy: 2)
        XCTAssertTrue(row.bounds.contains(menuFrame))
    }

    private func makeController() -> SettingsWindowController {
        _ = NSApplication.shared
        let dependencies = SettingsWindowDependencies(
            loginItemState: { .notRegistered }, refreshLoginItem: { $0(.notRegistered) },
            setLoginItemEnabled: { _, _ in XCTFail("Metrics must not change login items") },
            systemBatteryIconHidden: { false }, helperAvailable: { false },
            refreshSystemBatteryIcon: { $0(false) },
            setSystemBatteryIconHidden: { _, _ in XCTFail("Metrics must not change the battery icon") },
            systemBatteryIconDidChange: Notification.Name(UUID().uuidString),
            currentVersion: { "test" },
            checkForUpdates: { _ in XCTFail("Metrics must not query updates") },
            openUpdateURL: { _ in XCTFail("Metrics must not open a browser"); return false },
            increaseContrast: { false }, announceAccessibility: { _ in }
        )
        let sections = SettingsWindowController.defaultSections(dependencies: dependencies)
            .filter { $0.identifier == "modules" }
        let controller = SettingsWindowController(sections: sections, dependencies: dependencies, frameAutosaveName: nil)
        controller.refreshSectionsForTest()
        return controller
    }

    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }

    private func popup(in controller: SettingsWindowController) throws -> NSPopUpButton {
        let content = try XCTUnwrap(controller.windowForTest?.contentView)
        return try XCTUnwrap(descendants(content).first {
            $0.identifier?.rawValue == "settings.modules.ring-metrics"
        } as? NSPopUpButton)
    }

    private func metricItem(_ metric: Settings.RingMetric, in menu: NSPopUpButton) throws -> NSMenuItem {
        try XCTUnwrap(menu.itemArray.first { $0.representedObject as? String == metric.rawValue })
    }

    private func checkedMetrics(in menu: NSPopUpButton) -> [Settings.RingMetric] {
        menu.itemArray.filter { $0.state == .on }.compactMap {
            ($0.representedObject as? String).flatMap(Settings.RingMetric.init(rawValue:))
        }
    }

    private func perform(item: NSMenuItem) throws {
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(item.action), to: item.target, from: item))
    }

    private func keyLoop(in controller: SettingsWindowController) -> [NSView] {
        var controls: [NSView] = []
        var next = controller.sidebarNextKeyViewForTest
        while let view = next, view !== controller.sidebarForTest, controls.count < 50 {
            controls.append(view)
            next = view.nextKeyView
        }
        return controls
    }
}
