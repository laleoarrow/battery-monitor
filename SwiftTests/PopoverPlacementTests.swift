import CoreGraphics
import XCTest
@testable import Wattson

final class PopoverPlacementTests: XCTestCase {
    private let fullSize = CGSize(width: 360, height: 715)
    private let main = PopoverPlacement.Display(
        frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
        visibleFrame: CGRect(x: 0, y: 48, width: 1440, height: 828)
    )

    func testTallScreenPreservesNaturalSize() throws {
        let anchor = CGRect(x: 1200, y: 876, width: 24, height: 24)
        let result = try XCTUnwrap(PopoverPlacement.resolve(
            anchor: anchor, displays: [main], naturalSize: fullSize
        ))
        XCTAssertEqual(result.contentSize, fullSize)
        XCTAssertEqual(result.anchorFrame, anchor)
    }

    func testShortScreenClampsViewportWithoutScalingInstruments() throws {
        let screen = PopoverPlacement.Display(
            frame: CGRect(x: 0, y: 0, width: 1024, height: 600),
            visibleFrame: CGRect(x: 0, y: 40, width: 1024, height: 536)
        )
        let anchor = CGRect(x: 900, y: 576, width: 24, height: 24)
        let result = try XCTUnwrap(PopoverPlacement.resolve(
            anchor: anchor, displays: [screen], naturalSize: fullSize
        ))
        XCTAssertEqual(result.contentSize, CGSize(width: 360, height: 512))
        let compact = try XCTUnwrap(PopoverPlacement.resolve(
            anchor: anchor, displays: [screen], naturalSize: CGSize(width: 360, height: 154)
        ))
        XCTAssertEqual(compact.contentSize.height, 154)
    }

    func testAnchorChoosesLeftDisplayWithNegativeCoordinates() throws {
        let left = PopoverPlacement.Display(
            frame: CGRect(x: -1024, y: 0, width: 1024, height: 600),
            visibleFrame: CGRect(x: -1024, y: 40, width: 1024, height: 536)
        )
        let anchor = CGRect(x: -200, y: 576, width: 24, height: 24)
        let result = try XCTUnwrap(PopoverPlacement.resolve(
            anchor: anchor, displays: [main, left], naturalSize: fullSize
        ))
        XCTAssertEqual(result.contentSize.height, 512)
        XCTAssertEqual(result.anchorFrame, anchor)
    }

    func testDisplayBelowPrimaryAllowsNegativeY() throws {
        let below = PopoverPlacement.Display(
            frame: CGRect(x: 0, y: -900, width: 1440, height: 900),
            visibleFrame: CGRect(x: 0, y: -852, width: 1440, height: 828)
        )
        let anchor = CGRect(x: 1200, y: -24, width: 24, height: 24)
        let result = try XCTUnwrap(PopoverPlacement.resolve(
            anchor: anchor, displays: [main, below], naturalSize: fullSize
        ))
        XCTAssertEqual(result.contentSize, fullSize)
        XCTAssertEqual(result.anchorFrame, anchor)
    }

    func testCrossDisplayAnchorUsesLargestIntersectionAndClipsPositioningRect() throws {
        let left = PopoverPlacement.Display(
            frame: CGRect(x: -1440, y: 0, width: 1440, height: 900),
            visibleFrame: CGRect(x: -1440, y: 48, width: 1440, height: 828)
        )
        let result = try XCTUnwrap(PopoverPlacement.resolve(
            anchor: CGRect(x: -10, y: 876, width: 40, height: 24),
            displays: [left, main], naturalSize: fullSize
        ))
        XCTAssertEqual(result.anchorFrame, CGRect(x: 0, y: 876, width: 30, height: 24))
    }

    func testOffscreenMissingAndInvalidAnchorsFailClosed() {
        for anchor in [
            CGRect(x: 9999, y: 876, width: 24, height: 24),
            CGRect(x: 1440, y: 876, width: 24, height: 24),
            CGRect.zero,
            CGRect(x: CGFloat.nan, y: 876, width: 24, height: 24),
        ] {
            XCTAssertNil(PopoverPlacement.resolve(
                anchor: anchor, displays: [main], naturalSize: fullSize
            ))
        }
        XCTAssertNil(PopoverPlacement.resolve(
            anchor: CGRect(x: 1200, y: 876, width: 24, height: 24),
            displays: [], naturalSize: fullSize
        ))
    }

    func testNoUsableSpaceOrInvalidContentSizeFailsClosed() {
        let anchor = CGRect(x: 1200, y: 50, width: 24, height: 24)
        XCTAssertNil(PopoverPlacement.resolve(
            anchor: anchor, displays: [main], naturalSize: fullSize
        ))
        for size in [CGSize.zero, CGSize(width: 360, height: CGFloat.infinity),
                     CGSize(width: 2000, height: 715)] {
            XCTAssertNil(PopoverPlacement.resolve(
                anchor: CGRect(x: 1200, y: 876, width: 24, height: 24),
                displays: [main], naturalSize: size
            ))
        }
    }

    func testGlassPanelPreservesContentAndOpticalMarginAtBothScreenEdges() throws {
        for x: CGFloat in [0, 1200, 1416] {
            let placement = try XCTUnwrap(PopoverPlacement.resolve(
                anchor: CGRect(x: x, y: 876, width: 24, height: 24),
                displays: [main], naturalSize: fullSize))
            let frame = try XCTUnwrap(placement.glassPanelFrame(margin: 10))
            XCTAssertTrue(main.visibleFrame.contains(frame))
            XCTAssertEqual(frame.size, CGSize(width: 380, height: 735))
            XCTAssertEqual(frame.maxY, 872)
            XCTAssertEqual(frame.insetBy(dx: 10, dy: 10).size, fullSize)
        }
    }

    func testGlassPanelUsesNegativeDisplayCoordinatesAndClampedShortViewport() throws {
        for origin in [CGPoint(x: -1024, y: 0), CGPoint(x: 0, y: -600)] {
            let display = PopoverPlacement.Display(
                frame: CGRect(origin: origin, size: CGSize(width: 1024, height: 600)),
                visibleFrame: CGRect(x: origin.x, y: origin.y + 40, width: 1024, height: 536))
            let placement = try XCTUnwrap(PopoverPlacement.resolve(
                anchor: CGRect(x: origin.x + 980, y: origin.y + 576, width: 24, height: 24),
                displays: [main, display], naturalSize: fullSize))
            let frame = try XCTUnwrap(placement.glassPanelFrame(margin: 10))
            XCTAssertTrue(display.visibleFrame.contains(frame))
            XCTAssertEqual(frame.height, 532)
            XCTAssertEqual(frame.minY, display.visibleFrame.minY)
            XCTAssertEqual(frame.maxX, display.visibleFrame.maxX)
        }
    }

    func testGlassPanelRejectsInsufficientMarginAndInvalidMargin() throws {
        let narrow = PopoverPlacement.Display(
            frame: CGRect(x: 0, y: 0, width: 370, height: 900),
            visibleFrame: CGRect(x: 0, y: 40, width: 370, height: 836))
        let placement = try XCTUnwrap(PopoverPlacement.resolve(
            anchor: CGRect(x: 300, y: 876, width: 24, height: 24),
            displays: [narrow], naturalSize: fullSize))
        XCTAssertNil(placement.glassPanelFrame(margin: 10))
        for margin: CGFloat in [-1, .infinity, .nan, 300] {
            XCTAssertNil(placement.glassPanelFrame(margin: margin))
        }
    }
}
