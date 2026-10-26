import AppKit
import XCTest
@testable import Wattson

final class FooterHoverIntegrationTests: XCTestCase {
    private var suiteName = ""
    private var previousMotion: String?

    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
        suiteName = testDefaultsSuite("FooterHover")
        Settings.configureForTest(defaults: UserDefaults(suiteName: suiteName)!)
        previousMotion = ProcessInfo.processInfo.environment["WATTSON_FORCE_REDUCE_MOTION"]
    }

    override func tearDown() {
        Settings.resetTestConfiguration()
        UserDefaults(suiteName: suiteName)?.removePersistentTestDomain(forName: suiteName)
        if let previousMotion { setenv("WATTSON_FORCE_REDUCE_MOTION", previousMotion, 1) }
        else { unsetenv("WATTSON_FORCE_REDUCE_MOTION") }
        super.tearDown()
    }

    private func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }

    private func footer(glass: Bool, reduceMotion: Bool, helper: Bool = true)
        -> (PopoverFooterView, FooterHoverFeedbackView) {
        Settings.liquidGlassEnabled = glass
        setenv("WATTSON_FORCE_REDUCE_MOTION", reduceMotion ? "1" : "0", 1)
        let footer = PopoverFooterView()
        footer.frame = NSRect(x: 0, y: 0, width: PopoverStyle.contentWidth, height: 78)
        footer.update(mode: .auto, helperInstalled: helper, systemBatteryIconHidden: false, tint: .systemBlue)
        footer.layoutSubtreeIfNeeded()
        return (footer, descendants(footer).compactMap { $0 as? FooterHoverFeedbackView }.first!)
    }

    func testAllPresentationsTrackOnlyTheirVisibleModeButtonsAndMenu() {
        for glass in [false, true] {
            if glass, #unavailable(macOS 26.0) { continue }
            for reduceMotion in [false, true] {
                let (footer, feedback) = footer(glass: glass, reduceMotion: reduceMotion)
                let regions = feedback.regionsForTest
                XCTAssertEqual(regions.count, 4)
                XCTAssertTrue(footer.subviews.last === feedback)
                XCTAssertEqual(feedback.frame, footer.bounds)
                XCTAssertTrue(regions[0].enabled)
                XCTAssertTrue(regions[1].enabled)
                XCTAssertTrue(regions[3].enabled)
                for region in regions {
                    XCTAssertTrue(footer.bounds.contains(region.rect))
                    XCTAssertNil(feedback.hitTest(NSPoint(x: region.rect.midX, y: region.rect.midY)))
                }
                XCTAssertEqual(regions[0].rect.height, glass ? 38 : 30)
                XCTAssertEqual(regions[0].rect.width, regions[1].rect.width, accuracy: 0.001)
                XCTAssertEqual(regions[3].rect.size, glass ? NSSize(width: 38, height: 38)
                                                       : NSSize(width: 22, height: 20))
                let expectedGap: CGFloat = glass && reduceMotion ? 6 : 0
                XCTAssertEqual(regions[1].rect.minX - regions[0].rect.maxX, expectedGap, accuracy: 0.001)
                XCTAssertGreaterThan(regions[0].rect.minY, 30, "The checkbox row must not gain a hover region")
            }
        }
    }

    func testMissingHelperLeavesOnlyMenuHoverAvailable() {
        let (_, feedback) = footer(glass: false, reduceMotion: false, helper: false)
        XCTAssertEqual(feedback.regionsForTest.map(\.enabled), [false, false, false, true])
    }

    func testPendingModeRequestRemovesFeedbackUntilOwnerConfirms() {
        guard #available(macOS 26.0, *) else { return }
        let (footer, feedback) = footer(glass: true, reduceMotion: true)
        var completion: ((EnergyMode?) -> Void)?
        var requests: [EnergyMode] = []
        footer.onSelect = { mode, callback in requests.append(mode); completion = callback }
        let control = descendants(footer).compactMap { $0 as? NativeGlassModeControl }.first!
        control.selectModeForTest(.low)
        XCTAssertEqual(requests, [.low])
        XCTAssertEqual(feedback.regionsForTest.map(\.enabled), [false, false, false, true])
        completion?(.low)
        XCTAssertTrue(feedback.regionsForTest[0].enabled)
        XCTAssertTrue(feedback.regionsForTest[1].enabled)
        XCTAssertEqual(requests, [.low], "Visual feedback must never send an additional mode intent")
    }

    func testResizingAndSwitchingPresentationRebuildsMatchingRegions() {
        let (footer, feedback) = footer(glass: false, reduceMotion: false)
        footer.setFrameSize(NSSize(width: 300, height: 78))
        footer.layoutSubtreeIfNeeded()
        XCTAssertEqual(feedback.regionsForTest[0].rect.width, (300 - 46) / 3, accuracy: 0.001)
        guard #available(macOS 26.0, *) else { return }
        Settings.liquidGlassEnabled = true
        footer.layoutSubtreeIfNeeded()
        XCTAssertEqual(feedback.regionsForTest[3].rect.width, 38)
        XCTAssertEqual(feedback.regionsForTest[3].rect.maxX, 300)
        XCTAssertTrue(footer.subviews.last === feedback)
    }

    func testClassicPendingRequestKeepsFeedbackForModesThatCanSupersedeIt() {
        let (footer, feedback) = footer(glass: false, reduceMotion: true)
        var requests: [EnergyMode] = []
        footer.onSelect = { mode, _ in requests.append(mode) }
        let control = descendants(footer).compactMap { $0 as? NativeModeSegmentedControl }.first!
        control.selectModeForTest(.low)
        footer.layoutSubtreeIfNeeded()
        XCTAssertTrue(feedback.regionsForTest[0].enabled)
        XCTAssertTrue(feedback.regionsForTest[1].enabled)
        XCTAssertEqual(requests, [.low])
        control.selectModeForTest(.auto)
        XCTAssertEqual(requests, [.low, .auto])
    }
}
