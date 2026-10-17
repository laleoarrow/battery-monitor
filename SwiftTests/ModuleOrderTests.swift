import AppKit
import XCTest
@testable import Wattson

private func moduleOrderTestRunID() -> String {
    if let raw = ProcessInfo.processInfo.environment["WATTSON_MODULE_ORDER_TEST_RUN_ID"],
       let id = UUID(uuidString: raw) {
        return id.uuidString
    }
    return UUID().uuidString
}

final class ModuleOrderSettingsTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!
    private let key = "popover.moduleOrder"

    override func setUp() {
        super.setUp()
        suite = "Wattson.SwiftTests.ModuleOrder.\(moduleOrderTestRunID())"
        defaults = UserDefaults(suiteName: suite)!
        Settings.configureForTest(defaults: defaults)
    }

    override func tearDown() {
        Settings.resetTestConfiguration()
        defaults.removePersistentTestDomain(forName: suite)
        defaults = nil
        super.tearDown()
    }

    func testDefaultOrderDoesNotPersistAValue() {
        XCTAssertEqual(Settings.moduleOrder, [.flow, .ring, .lanes, .history, .runtime, .topProcesses])
        XCTAssertNil(defaults.object(forKey: key))
    }

    func testUnknownDuplicateAndMissingModulesNormalizeWithoutRewriting() {
        let saved = ["runtime", "future", "history", "runtime"]
        defaults.set(saved, forKey: key)
        XCTAssertEqual(Settings.moduleOrder, [.runtime, .history, .flow, .ring, .lanes, .topProcesses])
        XCTAssertEqual(defaults.stringArray(forKey: key), saved)
    }

    func testMalformedElementsRetainKnownModulesAndWrongContainersUseDefault() {
        defaults.set(["history", 3, false, ["flow"], "ring"] as [Any], forKey: key)
        XCTAssertEqual(Settings.moduleOrder, [.history, .ring, .flow, .lanes, .runtime, .topProcesses])
        XCTAssertEqual(defaults.array(forKey: key)?.count, 5)
        for invalid: Any in ["history", 4, ["history": 1], [] as [String], ["unknown"]] {
            defaults.set(invalid, forKey: key)
            XCTAssertEqual(Settings.moduleOrder, Settings.Module.allCases)
        }
    }

    func testSetterPersistsNormalizedOrderAndSurvivesReopeningStore() {
        Settings.moduleOrder = [.runtime, .history, .runtime]
        XCTAssertEqual(defaults.stringArray(forKey: key), ["runtime", "history", "flow", "ring", "lanes", "topProcesses"])
        Settings.configureForTest(defaults: UserDefaults(suiteName: suite)!)
        XCTAssertEqual(Settings.moduleOrder, [.runtime, .history, .flow, .ring, .lanes, .topProcesses])
    }

    func testOnlyChangedOrderNotifiesAfterPersistence() {
        var changes: [Settings.Change] = []
        var observed: [[Settings.Module]] = []
        let observer = NotificationCenter.default.addObserver(
            forName: Settings.didChange, object: nil, queue: nil
        ) { notification in
            changes.append(notification.userInfo?[Settings.changeUserInfoKey] as! Settings.Change)
            observed.append(Settings.moduleOrder)
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        Settings.moduleOrder = []
        XCTAssertNil(defaults.object(forKey: key))
        Settings.moduleOrder = [.runtime]
        Settings.moduleOrder = [.runtime, .runtime, .flow, .ring, .lanes, .history]
        Settings.moduleOrder = Settings.Module.allCases

        XCTAssertEqual(changes, [.moduleOrder, .moduleOrder])
        XCTAssertEqual(observed, [[.runtime, .flow, .ring, .lanes, .history, .topProcesses], Settings.Module.allCases])
    }

    func testNoOpSetterDoesNotRewriteMalformedButEquivalentStoredOrder() {
        let saved = ["runtime", "future", "runtime"]
        defaults.set(saved, forKey: key)
        Settings.moduleOrder = [.runtime]
        XCTAssertEqual(defaults.stringArray(forKey: key), saved)
    }

    func testHiddenModulesKeepTheirPositionAndVisibilityIsIndependent() {
        Settings.setModule(.history, visible: false)
        Settings.setModule(.runtime, visible: false)
        let order: [Settings.Module] = [.runtime, .history, .lanes, .ring, .flow, .topProcesses]
        Settings.moduleOrder = order
        XCTAssertFalse(Settings.isModuleVisible(.history))
        XCTAssertFalse(Settings.isModuleVisible(.runtime))
        XCTAssertEqual(Settings.moduleOrder, order)
        Settings.setModule(.history, visible: true)
        XCTAssertEqual(Settings.moduleOrder, order)
        XCTAssertFalse(Settings.isModuleVisible(.runtime))
        Settings.moduleOrder = Settings.Module.allCases
        XCTAssertEqual(Settings.moduleOrder, Settings.Module.allCases)
        XCTAssertTrue(Settings.isModuleVisible(.history))
        XCTAssertFalse(Settings.isModuleVisible(.runtime))
    }

    func testExternalWritesAndRemovalAreReadDirectly() {
        let external = UserDefaults(suiteName: suite)!
        external.set(["lanes", "ring"], forKey: key)
        XCTAssertEqual(Settings.moduleOrder, [.lanes, .ring, .flow, .history, .runtime, .topProcesses])
        external.removeObject(forKey: key)
        XCTAssertEqual(Settings.moduleOrder, Settings.Module.allCases)
    }
}

/// Native view tests: execute in the disposable macOS test environment.
final class ModuleOrderViewTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
        suite = "Wattson.SwiftTests.ModuleOrderView.\(moduleOrderTestRunID())"
        defaults = UserDefaults(suiteName: suite)!
        Settings.configureForTest(defaults: defaults)
    }

    override func tearDown() {
        Settings.resetTestConfiguration()
        defaults.removePersistentTestDomain(forName: suite)
        defaults = nil
        super.tearDown()
    }

    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }

    private func assertVerticallyAdjacent(_ upper: NSView, _ lower: NSView,
                                         file: StaticString = #filePath, line: UInt = #line) {
        guard let parent = upper.superview, lower.superview === parent else {
            XCTFail("Module frames must share the same coordinate system", file: file, line: line)
            return
        }
        // The document is flipped, but arranged frames use their stack's coordinates.
        let upperBottom = parent.isFlipped ? upper.frame.maxY : upper.frame.minY
        let lowerTop = parent.isFlipped ? lower.frame.minY : lower.frame.maxY
        XCTAssertEqual(upperBottom, lowerTop, accuracy: 0.5, file: file, line: line)
    }

    func testSavedOrderControlsActualFramesAndQuickMenu() {
        let order: [Settings.Module] = [.runtime, .history, .lanes, .ring, .flow, .topProcesses]
        Settings.moduleOrder = order
        let content = PopoverContentViewController()
        content.setViewportHeight(content.preferredHeight)

        XCTAssertEqual(content.moduleOrderForTest, order)
        XCTAssertEqual(content.moduleMenuItemsForTest.compactMap { $0.representedObject as? String },
                       order.map(\.rawValue))
        XCTAssertEqual(content.moduleMenuItemsForTest.map(\.title), order.map(\.title))
        let sections = order.map { content.moduleViewForTest($0) }
        for (first, second) in zip(sections, sections.dropFirst()) {
            assertVerticallyAdjacent(first, second)
        }
        XCTAssertEqual(content.preferredHeight, 799 + TopProcessesView.preferredHeight(count: 3))
    }

    func testLiveOrderRetainsObjectsDataHeightScrollFocusAndHistoryAttachment() throws {
        let content = PopoverContentViewController()
        content.setViewportHeight(240)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 240),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = content.view
        defer {
            content.setPresentationActive(false)
            content.setAnimationsEnabled(false)
            window.contentView = nil
            window.close()
        }
        content.setPresentationActive(true)
        content.update(snapshot: PowerSnapshot(percent: 70, batteryW: -20, systemW: 20),
                       history: [10, 20], peak: 20, degraded: false,
                       historyTiming: .init(sampledAt: [0, 2], referenceTime: 2))
        let views = Settings.Module.allCases.map { content.moduleViewForTest($0) }
        let history = try XCTUnwrap(content.moduleViewForTest(.history) as? HistoryView)
        let clip = try XCTUnwrap(history.layer?.sublayers?.first { $0.masksToBounds })
        let line = try XCTUnwrap(clip.sublayers?.compactMap { $0 as? CAShapeLayer }.first { $0.strokeColor != nil })
        // A detach invokes HistoryView.stopMotion(). This sentinel detects that
        // lifecycle side effect without requiring a visible animated window.
        let motion = CABasicAnimation(keyPath: "position.x")
        motion.duration = 60
        line.add(motion, forKey: "history.stroke")
        XCTAssertTrue(history.hasChartAnimationForTest)
        let renders = history.renderCountForTest
        let ceiling = history.chartCeilingForTest
        let counts = content.moduleUpdateCountsForTest
        let footerUpdates = content.footerUpdateCountForTest
        let naturalHeight = content.preferredHeight
        let scroll = try XCTUnwrap(descendants(content.view).compactMap { $0 as? NSScrollView }.first)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 180))
        scroll.reflectScrolledClipView(scroll.contentView)
        let offset = scroll.contentView.bounds.origin
        XCTAssertTrue(window.makeFirstResponder(scroll))
        let focus = window.firstResponder
        var heightNotifications = 0
        content.heightDidChange = { _ in heightNotifications += 1 }

        for order in [Array(Settings.Module.allCases.reversed()), Settings.Module.allCases] {
            Settings.moduleOrder = order

            XCTAssertEqual(content.moduleOrderForTest, order)
            XCTAssertEqual(content.moduleMenuItemsForTest.compactMap { $0.representedObject as? String },
                           order.map(\.rawValue))
            for (module, original) in zip(Settings.Module.allCases, views) {
                XCTAssertTrue(content.moduleViewForTest(module) === original)
                XCTAssertTrue(original.window === window)
            }
            XCTAssertTrue(window.firstResponder === focus)
            XCTAssertEqual(scroll.contentView.bounds.origin, offset)
            XCTAssertEqual(content.preferredHeight, naturalHeight)
            XCTAssertEqual(heightNotifications, 0)
            XCTAssertEqual(content.latestHistoryForTest, [10, 20])
            XCTAssertEqual(content.moduleUpdateCountsForTest, counts)
            XCTAssertEqual(content.footerUpdateCountForTest, footerUpdates)
            XCTAssertEqual(history.renderCountForTest, renders)
            XCTAssertEqual(history.chartCeilingForTest, ceiling)
            XCTAssertTrue(history.hasChartAnimationForTest)
        }
    }

    func testHiddenModuleRestoresItsReorderedPositionAndExactHeight() {
        let content = PopoverContentViewController()
        content.setViewportHeight(content.preferredHeight)
        let fullHeight = content.preferredHeight
        Settings.setModule(.history, visible: false)
        Settings.setModule(.runtime, visible: false)
        let order: [Settings.Module] = [.runtime, .history, .flow, .lanes, .ring, .topProcesses]

        Settings.moduleOrder = order

        XCTAssertEqual(content.moduleOrderForTest, order)
        XCTAssertTrue(content.moduleIsHiddenForTest(.history))
        XCTAssertTrue(content.moduleIsHiddenForTest(.runtime))
        XCTAssertEqual(content.preferredHeight,
                       fullHeight - HistoryView.preferredHeight - PopoverRuntimeView.preferredHeight)
        XCTAssertEqual(content.moduleMenuItemsForTest.map(\.state), [.off, .off, .on, .on, .on, .on])
        content.toggleModuleFromMenuForTest(.runtime)
        Settings.setModule(.history, visible: true)
        content.setViewportHeight(content.preferredHeight)
        XCTAssertEqual(content.moduleOrderForTest, order)
        XCTAssertEqual(content.preferredHeight, fullHeight)
        assertVerticallyAdjacent(content.moduleViewForTest(.runtime), content.moduleViewForTest(.history))
    }

    func testAllHiddenModulesCanReorderWithoutAddingHeight() {
        let content = PopoverContentViewController()
        _ = content.view
        for module in Settings.Module.allCases { Settings.setModule(module, visible: false) }
        let height = content.preferredHeight
        let order: [Settings.Module] = [.history, .runtime, .lanes, .flow, .ring, .topProcesses]
        Settings.moduleOrder = order
        content.setViewportHeight(height)
        XCTAssertEqual(height, PopoverHeaderView.preferredHeight + PopoverFooterView.preferredHeight + 24)
        XCTAssertEqual(content.preferredHeight, height)
        XCTAssertEqual(content.moduleOrderForTest, order)
        XCTAssertTrue(Settings.Module.allCases.allSatisfy { content.moduleIsHiddenForTest($0) })
        XCTAssertTrue(content.moduleMenuItemsForTest.allSatisfy { $0.state == .off })
    }

    func testProcessCountChangesOnlyItsModuleHeightAndHidingRemovesItEntirely() {
        let content = PopoverContentViewController()
        content.setViewportHeight(content.preferredHeight)
        let processView = content.moduleViewForTest(.topProcesses)
        let defaultHeight = content.preferredHeight
        var notifications: [CGFloat] = []
        content.heightDidChange = { height in
            notifications.append(height)
            content.setViewportHeight(height)
        }

        Settings.topProcessCount = 10
        XCTAssertTrue(processView === content.moduleViewForTest(.topProcesses))
        XCTAssertEqual(processView.frame.height, TopProcessesView.preferredHeight(count: 10))
        XCTAssertEqual(content.preferredHeight, defaultHeight
                       + TopProcessesView.preferredHeight(count: 10)
                       - TopProcessesView.preferredHeight(count: 3))
        XCTAssertEqual(notifications.count, 1)
        let expandedHeight = content.preferredHeight
        Settings.setModule(.topProcesses, visible: false)
        XCTAssertEqual(content.preferredHeight, expandedHeight - TopProcessesView.preferredHeight(count: 10))
        XCTAssertTrue(processView.isHidden)
        Settings.topProcessCount = 1
        XCTAssertEqual(content.preferredHeight, expandedHeight - TopProcessesView.preferredHeight(count: 10))
        Settings.setModule(.topProcesses, visible: true)
        XCTAssertEqual(processView.frame.height, TopProcessesView.preferredHeight(count: 1))
    }
}
