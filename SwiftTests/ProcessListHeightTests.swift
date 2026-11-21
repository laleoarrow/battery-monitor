import AppKit
import XCTest
@testable import Wattson

final class ProcessListHeightTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suite = testDefaultsSuite("ProcessListHeight")
        defaults = UserDefaults(suiteName: suite)!
        Settings.configureForTest(defaults: defaults)
        Settings.topProcessCount = 10
    }

    override func tearDown() {
        Settings.resetTestConfiguration()
        defaults.removePersistentTestDomain(forName: suite)
        defaults = nil
        super.tearDown()
    }

    func testShortSampleRemovesUnusedRowsAndOnlyCountChangesResize() throws {
        let content = makeContent()
        let list = try XCTUnwrap(content.moduleViewForTest(.topProcesses) as? TopProcessesView)
        let fullHeight = content.preferredHeight
        var heights: [CGFloat] = []
        content.heightDidChange = { [weak content] height in
            heights.append(height)
            content?.setViewportHeight(height)
        }

        content.updateTopProcesses(.ready(processes(9)))
        XCTAssertEqual(list.frame.height, 432)
        XCTAssertEqual(content.preferredHeight, fullHeight - 44)
        XCTAssertEqual(heights, [fullHeight - 44])
        try assertLastRowFits(list)

        content.updateTopProcesses(.ready(processes(9, score: 20)))
        XCTAssertEqual(heights.count, 1)
        content.updateTopProcesses(.ready(processes(10)))
        XCTAssertEqual(list.frame.height, 476)
        XCTAssertEqual(heights, [fullHeight - 44, fullHeight])
        try assertLastRowFits(list)
    }

    func testWhitelistShrinksRestoresAndCentersEmptyStateInOneRow() throws {
        let content = makeContent()
        let list = try XCTUnwrap(content.moduleViewForTest(.topProcesses) as? TopProcessesView)
        content.updateTopProcesses(.ready(processes(10)))
        let fullHeight = content.preferredHeight
        Settings.processWhitelist = [.init(pattern: "Worker 1", mode: .exact)]
        XCTAssertEqual(list.processRowsForTest.count, 9)
        XCTAssertEqual(list.frame.height, 432)
        XCTAssertEqual(content.preferredHeight, fullHeight - 44)
        try assertLastRowFits(list)

        Settings.processWhitelist = [.init(pattern: "*", mode: .wildcard)]
        XCTAssertEqual(list.frame.height, 80)
        let status = try XCTUnwrap(list.subviews.compactMap { $0 as? NSTextField }
            .first { !$0.isHidden && $0.stringValue == "All processes are whitelisted" })
        XCTAssertTrue(list.bounds.contains(status.frame))
        XCTAssertEqual(status.frame.midY, 50)

        Settings.processWhitelist = []
        XCTAssertEqual(list.processRowsForTest.count, 10)
        XCTAssertEqual(list.frame.height, 476)
        XCTAssertEqual(content.preferredHeight, fullHeight)
        Settings.topProcessesCompact = true
        XCTAssertEqual(list.frame.height, 316)
        Settings.processWhitelist = [.init(pattern: "Worker 1", mode: .exact)]
        XCTAssertEqual(list.frame.height, 288)
        try assertLastRowFits(list)
    }

    func testWhitelistActionResizesImmediately() throws {
        let content = makeContent()
        let list = try XCTUnwrap(content.moduleViewForTest(.topProcesses) as? TopProcessesView)
        content.updateTopProcesses(.ready(processes(10)))
        let row = try XCTUnwrap(list.processRowsForTest.first)
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: .zero,
            modifierFlags: .command, timestamp: 0, windowNumber: 0, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 1))
        row.mouseDown(with: event)
        let action = try XCTUnwrap(list.forceQuitButtonsForTest.first)
        XCTAssertFalse(action.isHidden)
        action.performClick(nil)
        XCTAssertEqual(Settings.processWhitelist, [.init(pattern: "Worker 1", mode: .exact)])
        XCTAssertEqual(list.processRowsForTest.count, 9)
        XCTAssertEqual(list.frame.height, 432)
        try assertLastRowFits(list)
    }

    func testHiddenModuleUsesLatestSampleWhenShownWithoutActivePresentation() throws {
        let content = makeContent()
        let list = try XCTUnwrap(content.moduleViewForTest(.topProcesses) as? TopProcessesView)
        content.updateTopProcesses(.ready(processes(10)))
        Settings.setModule(.topProcesses, visible: false)
        let hiddenHeight = content.preferredHeight
        content.updateTopProcesses(.ready(processes(4)))
        XCTAssertEqual(content.preferredHeight, hiddenHeight)
        Settings.setModule(.topProcesses, visible: true)
        XCTAssertEqual(list.processRowsForTest.count, 4)
        XCTAssertEqual(list.frame.height, 212)
        XCTAssertEqual(content.preferredHeight, hiddenHeight + 212)
        try assertLastRowFits(list)
    }

    func testShrinkingAtBottomClampsOffsetAndKeepsFooterReachable() throws {
        let content = makeContent(viewport: 600)
        content.updateTopProcesses(.ready(processes(10)))
        let scroll = content.scrollViewForTest
        let document = try XCTUnwrap(scroll.documentView)
        scroll.contentView.scroll(to: .init(x: 0, y: document.frame.height - scroll.contentView.bounds.height))
        scroll.reflectScrolledClipView(scroll.contentView)
        let offset = scroll.contentView.bounds.minY
        Settings.processWhitelist = [.init(pattern: "Worker 1", mode: .exact)]
        XCTAssertEqual(scroll.contentView.bounds.minY, offset - 44, accuracy: 0.5)
        XCTAssertEqual(scroll.documentVisibleRect.maxY, document.bounds.maxY, accuracy: 0.5)
        let footer = try XCTUnwrap(document.subviews.flatMap(\.subviews).compactMap { $0 as? PopoverFooterView }.first)
        XCTAssertTrue(scroll.documentVisibleRect.contains(footer.convert(footer.bounds, to: document)))
    }

    private func makeContent(viewport: CGFloat? = nil) -> PopoverContentViewController {
        let content = PopoverContentViewController()
        content.setViewportHeight(viewport ?? content.preferredHeight)
        content.heightDidChange = { [weak content] height in
            content?.setViewportHeight(viewport ?? height)
        }
        return content
    }

    private func processes(_ count: Int, score: Double = 10) -> [EnergyProcess] {
        (1...count).map { EnergyProcess(pid: Int32($0), name: "Worker \($0)",
            energyImpact: score, cpuPercent: score, idleWakeupsPerSecond: 0) }
    }

    private func assertLastRowFits(_ list: TopProcessesView, file: StaticString = #filePath, line: UInt = #line) throws {
        let row = try XCTUnwrap(list.processRowsForTest.last, file: file, line: line)
        XCTAssertEqual(list.bounds.maxY - row.frame.maxY, 8, file: file, line: line)
        XCTAssertTrue(list.bounds.contains(row.frame), file: file, line: line)
    }
}
