import AppKit
import XCTest
@testable import Wattson

final class ProcessWhitelistSettingsTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!
    private var controller: ProcessWhitelistWindowController!

    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
        suite = "Wattson.SwiftTests.ProcessWhitelistEditor.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        Settings.configureForTest(defaults: defaults)
        controller = ProcessWhitelistWindowController()
    }

    override func tearDown() {
        controller.close()
        controller = nil
        Settings.resetTestConfiguration()
        defaults.removePersistentTestDomain(forName: suite)
        defaults = nil
        super.tearDown()
    }

    private func find<T: NSView>(_ suffix: String) throws -> T {
        func search(_ view: NSView) -> T? {
            if view.identifier?.rawValue == "settings.process-whitelist.\(suffix)" { return view as? T }
            return view.subviews.lazy.compactMap(search).first
        }
        return try XCTUnwrap(search(try XCTUnwrap(controller.window?.contentView)))
    }

    private func enter(_ value: String, mode: ProcessWhitelistRule.MatchMode = .exact) throws {
        let popup: NSPopUpButton = try find("mode")
        popup.selectItem(at: try XCTUnwrap(ProcessWhitelistRule.MatchMode.allCases.firstIndex(of: mode)))
        NSApp.sendAction(try XCTUnwrap(popup.action), to: popup.target, from: popup)
        let input: NSTextField = try find("pattern")
        input.stringValue = value
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: input))
    }

    func testAddPersistsEachMatchTypeAndClearsTheEditor() throws {
        let add: NSButton = try find("add")
        let table: NSTableView = try find("rules")
        let input: NSTextField = try find("pattern")
        XCTAssertFalse(add.isEnabled)
        for (index, rule) in [
            ProcessWhitelistRule(pattern: "WindowServer", mode: .exact),
            ProcessWhitelistRule(pattern: "python*", mode: .wildcard),
            ProcessWhitelistRule(pattern: "^Code Helper.*$", mode: .regex),
        ].enumerated() {
            try enter(rule.pattern, mode: rule.mode)
            XCTAssertTrue(add.isEnabled)
            add.performClick(nil)
            XCTAssertEqual(Settings.processWhitelist.last, rule)
            XCTAssertEqual(table.numberOfRows, index + 1)
            XCTAssertEqual(input.stringValue, "")
            XCTAssertFalse(add.isEnabled)
        }
        Settings.configureForTest(defaults: UserDefaults(suiteName: suite)!)
        XCTAssertEqual(Settings.processWhitelist.count, 3, "Saved rules survive a new defaults instance")
    }

    func testInvalidRegexAndBlankPatternCannotBeAddedAndValidationRecovers() throws {
        let add: NSButton = try find("add")
        let validation: NSTextField = try find("validation")
        try enter("[", mode: .regex)
        XCTAssertFalse(add.isEnabled)
        XCTAssertEqual(validation.stringValue, "Invalid regular expression.")
        add.performClick(nil)
        XCTAssertEqual(Settings.processWhitelist, [])
        try enter(" ", mode: .exact)
        XCTAssertFalse(add.isEnabled)
        XCTAssertEqual(validation.stringValue, "Enter a process name or pattern.")
        try enter("[", mode: .exact)
        XCTAssertTrue(add.isEnabled, "Regex syntax is literal in Exact mode")
        XCTAssertEqual(validation.stringValue, "")
        add.performClick(nil)
        XCTAssertEqual(Settings.processWhitelist, [ProcessWhitelistRule(pattern: "[", mode: .exact)])
    }

    func testExternalAddsUpdateTheListAndDuplicateValidationWithoutLosingInput() throws {
        try enter("python*", mode: .wildcard)
        let rule = ProcessWhitelistRule(pattern: "python*", mode: .wildcard)
        Settings.processWhitelist = [rule]
        let table: NSTableView = try find("rules")
        let add: NSButton = try find("add")
        let input: NSTextField = try find("pattern")
        let validation: NSTextField = try find("validation")
        XCTAssertEqual(table.numberOfRows, 1)
        XCTAssertEqual(input.stringValue, rule.pattern)
        XCTAssertFalse(add.isEnabled)
        XCTAssertEqual(validation.stringValue, "This rule is already in the whitelist.")
        add.performClick(nil)
        XCTAssertEqual(Settings.processWhitelist, [rule])
        Settings.processWhitelist = []
        XCTAssertEqual(table.numberOfRows, 0)
        XCTAssertTrue(add.isEnabled)
        XCTAssertEqual(validation.stringValue, "")
    }

    func testExternalReorderingKeepsSelectionByRuleAndRemovalRestoresOnlyThatRule() throws {
        let first = ProcessWhitelistRule(pattern: "WindowServer", mode: .exact)
        let second = ProcessWhitelistRule(pattern: "python*", mode: .wildcard)
        Settings.processWhitelist = [first, second]
        let table: NSTableView = try find("rules")
        let remove: NSButton = try find("remove")
        XCTAssertFalse(remove.isEnabled)
        table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        XCTAssertTrue(remove.isEnabled)
        let third = ProcessWhitelistRule(pattern: "Mail", mode: .exact)
        Settings.processWhitelist = [third, first, second]
        XCTAssertEqual(table.selectedRow, 2)
        remove.performClick(nil)
        XCTAssertEqual(Settings.processWhitelist, [third, first])
        XCTAssertEqual(table.numberOfRows, 2)
        XCTAssertEqual(table.selectedRow, -1)
        XCTAssertFalse(remove.isEnabled)
    }

    func testHelpExplainsWildcardAndRegexAnchoring() throws {
        let help: NSTextField = try find("help")
        try enter("worker", mode: .wildcard)
        XCTAssertTrue(help.stringValue.contains("* means any text"))
        XCTAssertTrue(help.stringValue.contains("? means one character"))
        try enter("worker", mode: .regex)
        XCTAssertTrue(help.stringValue.contains("searches within"))
        XCTAssertTrue(help.stringValue.contains("^ and $"))
    }

    func testThemeChangesKeepWindowRulesAndUnfinishedInput() throws {
        Settings.processWhitelist = [ProcessWhitelistRule(pattern: "Mail", mode: .exact)]
        try enter("python*", mode: .wildcard)
        let window = try XCTUnwrap(controller.window)
        let input: NSTextField = try find("pattern")
        let table: NSTableView = try find("rules")
        for scheme: Settings.ColorScheme in [.dark, .light, .system] {
            Settings.colorScheme = scheme
            XCTAssertTrue(controller.window === window)
            let currentInput: NSTextField = try find("pattern")
            XCTAssertTrue(currentInput === input)
            XCTAssertEqual(window.appearance?.name, scheme.appearance?.name)
            XCTAssertEqual(input.stringValue, "python*")
            XCTAssertEqual(table.numberOfRows, 1)
        }
    }

    func testWhitelistKeyboardEntryRevealsTheEntireProcessRow() throws {
        let dependencies = SettingsWindowDependencies(
            loginItemState: { .notRegistered }, refreshLoginItem: { $0(.notRegistered) },
            setLoginItemEnabled: { _, _ in XCTFail("Focus must not change login items") },
            systemBatteryIconHidden: { false }, helperAvailable: { true },
            refreshSystemBatteryIcon: { $0(false) },
            setSystemBatteryIconHidden: { _, _ in XCTFail("Focus must not change system settings") },
            systemBatteryIconDidChange: Notification.Name(UUID().uuidString),
            currentVersion: { "5.0.0" },
            checkForUpdates: { _ in XCTFail("Focus must not query updates") },
            openUpdateURL: { _ in XCTFail("Focus must not open a browser"); return false },
            increaseContrast: { false }, announceAccessibility: { _ in }
        )
        let sections = SettingsWindowController.defaultSections(dependencies: dependencies)
            .filter { $0.identifier == "modules" }
        let settings = SettingsWindowController(sections: sections, dependencies: dependencies, frameAutosaveName: nil)
        defer { settings.close() }
        let window = try XCTUnwrap(settings.windowForTest)
        let content = try XCTUnwrap(window.contentView)
        content.layoutSubtreeIfNeeded()
        func descendant(_ identifier: String, in view: NSView) -> NSView? {
            if view.identifier?.rawValue == identifier { return view }
            return view.subviews.lazy.compactMap { descendant(identifier, in: $0) }.first
        }
        let whitelist = try XCTUnwrap(descendant("settings.modules.process-whitelist", in: content) as? NSButton)
        let count = try XCTUnwrap(descendant("settings.modules.top-process-count", in: content))
        let compact = try XCTUnwrap(descendant("settings.modules.top-processes-compact", in: content))
        let previous = try XCTUnwrap(descendant("settings.modules.reorder.runtime", in: content))
        let row = try XCTUnwrap(descendant("settings.modules.row.topProcesses", in: content))
        let scroll = try XCTUnwrap(descendant("settings.modules.scroll", in: content) as? NSScrollView)
        let document = try XCTUnwrap(scroll.documentView)
        XCTAssertTrue(previous.nextKeyView === whitelist)
        XCTAssertTrue(whitelist.nextKeyView === count)
        XCTAssertTrue(count.nextKeyView === compact)
        scroll.contentView.scroll(to: .zero)
        scroll.reflectScrolledClipView(scroll.contentView)
        let rowRect = row.convert(row.bounds, to: document)
        XCTAssertFalse(scroll.documentVisibleRect.contains(rowRect), "The last row begins partially below the viewport")
        let offset = scroll.contentView.bounds.origin
        XCTAssertTrue(window.makeFirstResponder(whitelist))
        content.layoutSubtreeIfNeeded()
        XCTAssertTrue(window.firstResponder === whitelist)
        XCTAssertGreaterThan(scroll.contentView.bounds.origin.y, offset.y)
        XCTAssertTrue(scroll.documentVisibleRect.insetBy(dx: -0.5, dy: -0.5).contains(rowRect),
                      "Focusing Whitelist reveals both its action and the process display settings")
        XCTAssertFalse(window.isVisible, "The focus regression uses a hidden window")
    }
}
