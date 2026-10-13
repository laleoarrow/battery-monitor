import AppKit
import XCTest
@testable import Wattson

/// Retained production Settings in hidden windows; material pixels are checked
/// separately with real compositor captures in the disposable GUI VM.
final class SettingsGlassOpticalMarginTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
        suite = "Wattson.SettingsGlassOpticalMargin.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        Settings.configureForTest(defaults: defaults)
    }

    override func tearDown() {
        Settings.resetTestConfiguration()
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        super.tearDown()
    }

    private var dependencies: SettingsWindowDependencies {
        SettingsWindowDependencies(
            loginItemState: { .notRegistered },
            refreshLoginItem: { $0(.notRegistered) },
            setLoginItemEnabled: { _, _ in XCTFail("Layout must not change login items") },
            systemBatteryIconHidden: { false },
            helperAvailable: { true },
            refreshSystemBatteryIcon: { $0(false) },
            setSystemBatteryIconHidden: { _, _ in XCTFail("Layout must not change the battery icon") },
            systemBatteryIconDidChange: Notification.Name(UUID().uuidString),
            currentVersion: { "4.3.1" },
            checkForUpdates: { _ in XCTFail("Layout must not query updates") },
            openUpdateURL: { _ in XCTFail("Layout must not open a browser"); return false },
            increaseContrast: { false },
            announceAccessibility: { _ in }
        )
    }

    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }

    private func find<T: NSView>(_ identifier: String, in view: NSView) throws -> T {
        try XCTUnwrap(descendants(view).first {
            $0.identifier?.rawValue == identifier || $0.accessibilityIdentifier() == identifier
        } as? T)
    }

    func testGlassGroupsKeepOpticalEdgesInsideClipWhenFeedbackReceivesFocus() throws {
        guard #available(macOS 26.0, *) else { throw XCTSkip("Native Liquid Glass needs macOS 26") }
        Settings.liquidGlassEnabled = true
        let controller = SettingsWindowController(dependencies: dependencies, frameAutosaveName: nil)
        let window = try XCTUnwrap(controller.windowForTest)
        let content = try XCTUnwrap(window.contentView)
        content.layoutSubtreeIfNeeded()
        let scroll: NSScrollView = try find("settings.general.scroll", in: content)
        XCTAssertFalse(scroll.drawsBackground)
        XCTAssertFalse(scroll.contentView.drawsBackground)
        XCTAssertEqual(scroll.backgroundColor.alphaComponent, 0)
        XCTAssertEqual(scroll.contentView.backgroundColor.alphaComponent, 0)
        let split = try XCTUnwrap(window.contentViewController?.children.compactMap {
            $0 as? NSSplitViewController
        }.first)
        let detail = try XCTUnwrap(split.splitViewItems.last?.viewController.view)
        let viewport = scroll.convert(scroll.bounds, to: detail)
        XCTAssertEqual(viewport.minX, detail.safeAreaLayoutGuide.frame.minX, accuracy: 0.5)
        XCTAssertEqual(viewport.maxX, detail.bounds.maxX, accuracy: 0.5)
        XCTAssertEqual(viewport.minY, detail.bounds.minY, accuracy: 0.5)
        let document = try XCTUnwrap(scroll.documentView)
        let feedback: NSView = try find("settings.general.feedback", in: content)
        let button: NSButton = try find("settings.general.feedback.button", in: content)
        let glasses = descendants(document).compactMap { $0 as? NSGlassEffectView }
            .filter { $0.identifier?.rawValue == "settings.control-group.glass" }
        XCTAssertEqual(glasses.count, 3)
        for glass in glasses {
            let optical = glass.convert(glass.bounds, to: document).insetBy(dx: -20, dy: -20)
            XCTAssertGreaterThanOrEqual(optical.minX, document.bounds.minX - 0.5)
            XCTAssertLessThanOrEqual(optical.maxX, document.bounds.maxX + 0.5)
        }
        scroll.contentView.scroll(to: .zero)
        XCTAssertTrue(window.makeFirstResponder(button))
        let optical = feedback.convert(feedback.bounds, to: document).insetBy(dx: -20, dy: -20)
        XCTAssertTrue(scroll.documentVisibleRect.insetBy(dx: -0.5, dy: -0.5).contains(optical))
        let feedbackGlass = try XCTUnwrap(descendants(feedback).compactMap { $0 as? NSGlassEffectView }.first)
        var ancestor = feedbackGlass.superview
        while let host = ancestor {
            if host.clipsToBounds {
                let opticalInHost = feedbackGlass.convert(
                    feedbackGlass.bounds.insetBy(dx: -20, dy: -20), to: host
                )
                XCTAssertTrue(host.bounds.insetBy(dx: -0.5, dy: -0.5).contains(opticalInHost),
                    host.identifier?.rawValue ?? String(describing: type(of: host)))
            }
            ancestor = host.superview
        }
        XCTAssertTrue(scroll.contentView.clipsToBounds)
        XCTAssertFalse(window.isVisible)
    }

    func testClassicGeneralRetainsGroupGeometryAndOperationalRowHeights() throws {
        Settings.liquidGlassEnabled = false
        let controller = SettingsWindowController(dependencies: dependencies, frameAutosaveName: nil)
        let window = try XCTUnwrap(controller.windowForTest)
        let content = try XCTUnwrap(window.contentView)
        content.layoutSubtreeIfNeeded()
        let list: NSBox = try find("settings.general.list", in: content)
        let rows = descendants(list).filter {
            $0.identifier?.rawValue.hasPrefix("settings.general.row.") == true
        }
        XCTAssertEqual(list.frame.width, 503, accuracy: 0.5)
        XCTAssertEqual(list.frame.height, 272, accuracy: 0.5)
        XCTAssertEqual(rows.count, 4)
        let orderedRows = rows.sorted {
            $0.convert($0.bounds, to: list).minY > $1.convert($1.bounds, to: list).minY
        }
        for (index, row) in orderedRows.enumerated() {
            let frame = row.convert(row.bounds, to: list)
            XCTAssertEqual(frame.minX, 0, accuracy: 0.5)
            XCTAssertEqual(frame.width, list.bounds.width, accuracy: 0.5)
            XCTAssertEqual(frame.height, 68, accuracy: 0.5)
            XCTAssertEqual(frame.maxY, 272 - CGFloat(index) * 68, accuracy: 0.5)
        }
        let hostFrame = controller.contentHostFrameForTest
        let listFrame = list.convert(list.bounds, to: nil)
        XCTAssertEqual(listFrame.minX, hostFrame.minX, accuracy: 0.5)
        XCTAssertEqual(listFrame.maxY, hostFrame.maxY - 40, accuracy: 0.5)
        XCTAssertFalse(window.isVisible)
    }
}
