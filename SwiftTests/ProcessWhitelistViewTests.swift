import AppKit
import Darwin
import XCTest
@testable import Wattson

final class ProcessWhitelistViewTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "Wattson.SwiftTests.ProcessWhitelistView.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        Settings.configureForTest(defaults: defaults)
    }

    override func tearDown() {
        Settings.resetTestConfiguration()
        defaults.removePersistentTestDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testRulesFilterBeforeDisplayLimitAndRuleRemovalRefreshesTheSameSample() {
        let view = makeView()
        let state = TopProcessesState.ready([
            process(41, name: "python3.12"), process(42, name: "Mail"),
            process(43, name: "WindowServer"), process(44, name: "Safari"),
        ])
        Settings.processWhitelist = [.init(pattern: "python*", mode: .wildcard)]
        view.update(state: state, count: 3)
        XCTAssertEqual(visibleNames(view), ["Mail", "WindowServer", "Safari"])
        let updates = view.contentUpdatesForTest

        Settings.processWhitelist = [.init(pattern: "^(python|Mail)", mode: .regex)]
        view.update(state: state, count: 3)
        XCTAssertEqual(visibleNames(view), ["WindowServer", "Safari"])
        XCTAssertEqual(view.contentUpdatesForTest, updates + 1)

        Settings.processWhitelist = []
        view.update(state: state, count: 3)
        XCTAssertEqual(visibleNames(view), ["python3.12", "Mail", "WindowServer"])
        XCTAssertEqual(view.contentUpdatesForTest, updates + 2)
        view.update(state: state, count: 3)
        XCTAssertEqual(view.contentUpdatesForTest, updates + 2)
    }

    func testAllHiddenCandidatesExplainWhitelistAndRemainDistinctFromAnEmptySample() throws {
        let view = makeView()
        Settings.processWhitelist = [.init(pattern: "*", mode: .wildcard)]
        view.update(state: .ready([process(41, name: "Mail")]), count: 3)
        XCTAssertTrue(view.processRowsForTest.isEmpty)
        let status = try XCTUnwrap(view.subviews.compactMap { $0 as? NSTextField }.last)
        XCTAssertFalse(status.isHidden)
        XCTAssertEqual(status.stringValue, "All processes are whitelisted")
        XCTAssertFalse(status.accessibilityHelp()?.isEmpty ?? true)

        view.update(state: .ready([]), count: 3)
        XCTAssertEqual(status.stringValue, "No active processes")
        XCTAssertFalse(status.isHidden)
    }

    func testSettingsChangesImmediatelyFilterAndRestoreTheRetainedPopoverSample() throws {
        let content = PopoverContentViewController()
        content.setViewportHeight(content.preferredHeight)
        let processView = try XCTUnwrap(content.moduleViewForTest(.topProcesses) as? TopProcessesView)
        content.updateTopProcesses(.ready([
            process(41, name: "Worker"), process(42, name: "Mail"),
            process(43, name: "WindowServer"), process(44, name: "Safari"),
        ]))
        XCTAssertEqual(visibleNames(processView), ["Worker", "Mail", "WindowServer"])
        let height = content.preferredHeight
        let updates = content.moduleUpdateCountsForTest
        let footerUpdates = content.footerUpdateCountForTest

        Settings.processWhitelist = [.init(pattern: "Worker", mode: .exact)]
        XCTAssertTrue(processView === content.moduleViewForTest(.topProcesses))
        XCTAssertEqual(visibleNames(processView), ["Mail", "WindowServer", "Safari"])

        Settings.processWhitelist = []
        XCTAssertEqual(visibleNames(processView), ["Worker", "Mail", "WindowServer"])
        XCTAssertEqual(content.preferredHeight, height)
        XCTAssertEqual(content.moduleUpdateCountsForTest[.topProcesses, default: 0],
                       updates[.topProcesses, default: 0] + 2)
        for module in PopoverModule.allCases where module != .topProcesses {
            XCTAssertEqual(content.moduleUpdateCountsForTest[module, default: 0], updates[module, default: 0])
        }
        XCTAssertEqual(content.footerUpdateCountForTest, footerUpdates)
    }

    func testCommandClickOffersWhitelistWithoutIdentityAndHidesOnlyTheExactNameImmediately() throws {
        let view = makeView()
        let literalName = "worker[1].*?"
        let values = [
            process(41, name: literalName), process(42, name: "worker1.zz"),
            process(43, name: "worker[1].*? child"), process(44, name: "Mail"),
        ]
        view.update(state: .ready(values), count: 3)
        let row = try XCTUnwrap(view.processRowsForTest.first)
        let button = try actionButton(view)
        var forceQuits = 0
        view.forceQuitHandler = { _ in forceQuits += 1 }

        try click(row)
        XCTAssertEqual(button.actionKind, .forceQuit)
        XCTAssertFalse(button.isEnabled)
        button.performClick(nil)
        XCTAssertTrue(Settings.processWhitelist.isEmpty)

        try click(row, modifiers: .command)
        XCTAssertEqual(button.actionKind, .whitelist)
        XCTAssertFalse(button.isHidden)
        XCTAssertTrue(button.isEnabled)
        XCTAssertEqual(button.accessibilityLabel(), "Add \(literalName) to Whitelist")
        XCTAssertNotNil(button.image)
        button.performClick(nil)

        XCTAssertEqual(Settings.processWhitelist, [.init(pattern: literalName, mode: .exact)])
        XCTAssertEqual(visibleNames(view), ["worker1.zz", "worker[1].*? child", "Mail"])
        XCTAssertNil(view.selectedProcessForTest)
        XCTAssertEqual(forceQuits, 0)
    }

    func testChangingModifierSwitchesActionAndRepeatingTheSameActionClearsSelection() throws {
        let view = makeView()
        let value = process(41, name: "Worker", identified: true)
        view.update(state: .ready([value]), count: 3)
        let row = try XCTUnwrap(view.processRowsForTest.first)
        let button = try actionButton(view)
        var forceQuits: [EnergyProcess] = []
        view.forceQuitHandler = { forceQuits.append($0) }

        try click(row, modifiers: .command)
        XCTAssertEqual(button.actionKind, .whitelist)
        try click(row)
        XCTAssertEqual(view.selectedProcessForTest, value)
        XCTAssertEqual(button.actionKind, .forceQuit)
        XCTAssertEqual(button.accessibilityLabel(), "Force Quit Worker")
        button.performClick(nil)
        XCTAssertEqual(forceQuits, [value])
        XCTAssertTrue(Settings.processWhitelist.isEmpty)

        try click(row, modifiers: .command)
        XCTAssertEqual(button.actionKind, .whitelist)
        XCTAssertEqual(view.selectedProcessForTest, value)
        try click(row, modifiers: .command)
        XCTAssertNil(view.selectedProcessForTest)
        XCTAssertTrue(button.isHidden)
        button.performClick(nil)
        XCTAssertTrue(Settings.processWhitelist.isEmpty)
        XCTAssertEqual(forceQuits, [value])
    }

    func testWhitelistActionFollowsIdentityAcrossRerankingAndUsesTheCurrentName() throws {
        let view = makeView()
        let first = process(41, name: "Worker", identified: true)
        let second = process(42, name: "Mail", identified: true)
        view.update(state: .ready([first, second]), count: 3)
        let previousButton = try actionButton(view)
        try click(view.processRowsForTest[0], modifiers: .command)
        let refreshed = process(41, name: "Renamed Worker", identified: true, score: 91)
        view.update(state: .ready([second, refreshed]), count: 3)

        XCTAssertEqual(view.selectedProcessForTest, refreshed)
        XCTAssertTrue(previousButton.isHidden)
        previousButton.performClick(nil)
        XCTAssertTrue(Settings.processWhitelist.isEmpty)
        let currentButton = try actionButton(view, at: 1)
        XCTAssertEqual(currentButton.actionKind, .whitelist)
        XCTAssertEqual(currentButton.accessibilityLabel(), "Add Renamed Worker to Whitelist")
        currentButton.performClick(nil)
        XCTAssertEqual(Settings.processWhitelist, [.init(pattern: "Renamed Worker", mode: .exact)])
        XCTAssertEqual(visibleNames(view), ["Mail"])
    }

    func testRemovedOrReusedIdentityCannotDispatchAStaleWhitelistAction() throws {
        let view = makeView()
        let original = process(41, name: "Worker", identified: true)
        let other = process(42, name: "Mail", identified: true)
        view.update(state: .ready([original, other]), count: 3)
        try click(view.processRowsForTest[0], modifiers: .command)
        let button = try actionButton(view)

        view.update(state: .ready([other]), count: 3)
        XCTAssertNil(view.selectedProcessForTest)
        XCTAssertTrue(button.isHidden)
        button.performClick(nil)
        XCTAssertTrue(Settings.processWhitelist.isEmpty)

        view.update(state: .ready([original]), count: 3)
        try click(view.processRowsForTest[0], modifiers: .command)
        view.update(state: .ready([process(41, name: "Worker", identified: true, startedAt: 8)]), count: 3)
        XCTAssertNil(view.selectedProcessForTest)
        XCTAssertTrue(button.isHidden)
        button.performClick(nil)
        XCTAssertTrue(Settings.processWhitelist.isEmpty)
    }

    func testCommandKeyboardSelectionAndArrowNavigationRetainWhitelistMode() throws {
        let view = makeView()
        view.update(state: .ready([process(41, name: "Worker"), process(42, name: "Mail")]), count: 3)
        let rows = view.processRowsForTest
        rows[0].keyDown(with: try keyEvent(36, modifiers: .command))
        XCTAssertEqual(view.selectedProcessForTest?.name, "Worker")
        XCTAssertEqual(try actionButton(view).actionKind, .whitelist)

        rows[0].keyDown(with: try keyEvent(125))
        XCTAssertEqual(view.selectedProcessForTest?.name, "Mail")
        XCTAssertEqual(try actionButton(view, at: 1).actionKind, .whitelist)
        rows[1].keyDown(with: try keyEvent(53))
        XCTAssertNil(view.selectedProcessForTest)

        rows[1].keyDown(with: try keyEvent(49, modifiers: .command))
        XCTAssertEqual(view.selectedProcessForTest?.name, "Mail")
        XCTAssertEqual(try actionButton(view, at: 1).actionKind, .whitelist)
        view.forceQuitButtonsForTest[1].performClick(nil)
        XCTAssertEqual(Settings.processWhitelist, [.init(pattern: "Mail", mode: .exact)])
        XCTAssertEqual(visibleNames(view), ["Worker"])
    }

    private func makeView() -> TopProcessesView {
        let view = TopProcessesView()
        view.frame = NSRect(x: 0, y: 0, width: PopoverStyle.contentWidth,
                            height: TopProcessesView.preferredHeight(count: 3))
        return view
    }

    private func actionButton(_ view: TopProcessesView, at index: Int = 0) throws -> ProcessActionButton {
        try XCTUnwrap(view.forceQuitButtonsForTest[index] as? ProcessActionButton)
    }

    private func visibleNames(_ view: TopProcessesView) -> [String] {
        view.processRowsForTest.compactMap { $0.accessibilityLabel() }
    }

    private func process(_ pid: Int32, name: String, identified: Bool = false,
                         startedAt: UInt64 = 7, score: Double = 40) -> EnergyProcess {
        let identity: ProcessIdentity?
        if identified {
            var token = audit_token_t()
            token.val.5 = UInt32(pid)
            token.val.7 = 1
            identity = ProcessIdentity(pid: pid, startedAt: startedAt,
                                       auditToken: withUnsafeBytes(of: &token) { Data($0) })
        } else {
            identity = nil
        }
        return EnergyProcess(pid: pid, name: name, energyImpact: score,
                             cpuPercent: score, idleWakeupsPerSecond: 0, terminationIdentity: identity)
    }

    private func click(_ row: NSView, modifiers: NSEvent.ModifierFlags = []) throws {
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 40, y: 11),
                                                    modifierFlags: modifiers, timestamp: 0, windowNumber: 0,
                                                    context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        row.mouseDown(with: event)
    }

    private func keyEvent(_ keyCode: UInt16, modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                                      timestamp: 0, windowNumber: 0, context: nil, characters: "",
                                      charactersIgnoringModifiers: "", isARepeat: false, keyCode: keyCode))
    }
}
