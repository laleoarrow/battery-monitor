import AppKit
import XCTest
@testable import Wattson

final class ScrollbarIntegrationTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
        suite = testDefaultsSuite("ScrollbarIntegration")
        defaults = UserDefaults(suiteName: suite)!
        Settings.configureForTest(defaults: defaults)
    }

    override func tearDown() {
        Settings.resetTestConfiguration()
        defaults.removePersistentTestDomain(forName: suite)
        defaults = nil
        super.tearDown()
    }

    func testStylesKeepDocumentGeometryAndReadingPositionInBothSystemStyles() throws {
        for systemStyle in [NSScroller.Style.legacy, .overlay] {
            let controller = PopoverContentViewController()
            controller.setViewportHeight(240)
            let scroll = controller.scrollViewForTest
            scroll.scrollerStyle = systemStyle
            scroll.tile()
            controller.view.layoutSubtreeIfNeeded()
            let document = try XCTUnwrap(scroll.documentView)
            let native = try XCTUnwrap(scroll.verticalScroller)
            let size = document.frame.size
            let frames = PopoverModule.allCases.map { controller.moduleViewForTest($0).frame }
            scroll.contentView.scroll(to: NSPoint(x: 0, y: 123))
            scroll.reflectScrolledClipView(scroll.contentView)
            for style in Settings.ScrollbarStyle.allCases {
                Settings.scrollbarStyle = style
                controller.view.layoutSubtreeIfNeeded()
                XCTAssertEqual(scroll.scrollerStyle, systemStyle)
                XCTAssertEqual(document.frame.size, size, "\(systemStyle): \(style)")
                XCTAssertEqual(PopoverModule.allCases.map { controller.moduleViewForTest($0).frame }, frames)
                XCTAssertEqual(scroll.contentView.bounds.minY, 123, accuracy: 0.01)
                XCTAssertTrue(scroll.hasVerticalScroller, "Retain the native gutter even when hidden")
                XCTAssertTrue(scroll.verticalScroller === native, "Switching must keep the native scroller instance")
                XCTAssertEqual(controller.flowScrollbarForTest.isHidden, style != .flow)
                if style == .simple {
                    XCTAssertTrue(native.isAccessibilityElement())
                    XCTAssertTrue(scroll.accessibilityVerticalScrollBar() as? NSScroller === scroll.verticalScroller)
                } else {
                    XCTAssertEqual(native.alphaValue, 0)
                    native.alphaValue = 1 // A system overlay flash must stay hidden.
                    XCTAssertEqual(native.alphaValue, 0)
                    XCTAssertNil(scroll.verticalScroller?.hitTest(NSPoint(x: 5, y: 10)))
                    if style == .hidden {
                        XCTAssertNil(scroll.accessibilityVerticalScrollBar())
                    } else {
                        XCTAssertTrue(scroll.accessibilityVerticalScrollBar() as? NSScroller === controller.flowScrollbarForTest)
                    }
                }
            }
        }
    }

    func testFlowActionReachesBothEndsAndTallViewportRemovesControl() throws {
        let controller = PopoverContentViewController()
        controller.setViewportHeight(240)
        let scroll = controller.scrollViewForTest
        let flow = controller.flowScrollbarForTest
        flow.doubleValue = 1
        XCTAssertTrue(flow.sendAction(flow.action, to: flow.target))
        XCTAssertEqual(scroll.contentView.bounds.minY, controller.preferredHeight - 240, accuracy: 0.01)
        flow.doubleValue = 0
        XCTAssertTrue(flow.sendAction(flow.action, to: flow.target))
        XCTAssertEqual(scroll.contentView.bounds.minY, 0, accuracy: 0.01)
        controller.setViewportHeight(controller.preferredHeight)
        XCTAssertFalse(scroll.hasVerticalScroller)
        XCTAssertTrue(flow.isHidden)
        XCTAssertEqual(scroll.contentView.bounds.minY, 0, accuracy: 0.01)
    }

    func testScrollbarsStayInsideRoundedEndsWithoutChangingViewportOrScrollRange() throws {
        for systemStyle in [NSScroller.Style.legacy, .overlay] {
            let controller = PopoverContentViewController()
            controller.setViewportHeight(240)
            let scroll = controller.scrollViewForTest
            scroll.scrollerStyle = systemStyle
            scroll.tile()
            controller.view.layoutSubtreeIfNeeded()
            let document = try XCTUnwrap(scroll.documentView)
            let native = try XCTUnwrap(scroll.verticalScroller)
            let flow = controller.flowScrollbarForTest
            let safeBounds = scroll.bounds.insetBy(dx: 0, dy: GlassPopoverShape.cornerRadius)
            let documentSize = document.frame.size
            let contentSize = scroll.contentSize
            let moduleFrames = PopoverModule.allCases.map { controller.moduleViewForTest($0).frame }
            XCTAssertEqual(contentSize.height, 240)

            for style in [Settings.ScrollbarStyle.flow, .simple] {
                Settings.scrollbarStyle = style
                for _ in 0..<3 {
                    scroll.tile()
                    scroll.reflectScrolledClipView(scroll.contentView)
                    for scroller in [native, flow] {
                        let frame = scroller.convert(scroller.bounds, to: scroll)
                        XCTAssertEqual(frame.minY, safeBounds.minY, accuracy: 0.5, "\(systemStyle): \(style)")
                        XCTAssertEqual(frame.maxY, safeBounds.maxY, accuracy: 0.5, "\(systemStyle): \(style)")
                    }
                    XCTAssertEqual(scroll.contentSize, contentSize)
                    XCTAssertEqual(document.frame.size, documentSize)
                    XCTAssertEqual(PopoverModule.allCases.map { controller.moduleViewForTest($0).frame }, moduleFrames)
                }
                for fraction in [0.0, 1.0] {
                    flow.doubleValue = fraction
                    XCTAssertTrue(flow.sendAction(flow.action, to: flow.target))
                    let maximum = document.frame.height - contentSize.height
                    XCTAssertEqual(scroll.contentView.bounds.minY, fraction * maximum, accuracy: 0.5)
                    for scroller in [native, flow] {
                        let knob = scroller.convert(scroller.rect(for: .knob), to: scroll)
                        XCTAssertFalse(knob.isEmpty)
                        XCTAssertTrue(safeBounds.contains(knob), "\(systemStyle): \(style): \(knob)")
                    }
                    let capsule = try XCTUnwrap(flow.layer?.sublayers?.first { $0.name == "flow-knob" })
                    XCTAssertTrue(safeBounds.contains(flow.convert(capsule.frame, to: scroll)))
                }
            }
        }
    }
}
