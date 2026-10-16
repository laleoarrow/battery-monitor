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
            XCTAssertEqual(frame.size, CGSize(width: 380, height: 747))
            XCTAssertEqual(frame.maxY - 10, 872) // Arrow tip, 4pt below the anchor.
            let body = CGRect(x: frame.minX + 10, y: frame.minY + 10,
                              width: fullSize.width, height: fullSize.height)
            XCTAssertEqual(body.maxY, 860) // Body ends 12pt below the tip.
            XCTAssertEqual(body.size, fullSize)
            XCTAssertGreaterThanOrEqual(frame.minX, main.visibleFrame.minX)
            XCTAssertLessThanOrEqual(frame.maxX, main.visibleFrame.maxX)
            XCTAssertGreaterThanOrEqual(frame.minY, main.visibleFrame.minY)
        }
    }

    func testGlassPanelUsesNegativeDisplayCoordinatesAndClampedShortViewport() throws {
        for origin in [CGPoint(x: -1024, y: 0), CGPoint(x: 0, y: -600)] {
            let display = PopoverPlacement.Display(
                frame: CGRect(origin: origin, size: CGSize(width: 1024, height: 600)),
                visibleFrame: CGRect(x: origin.x, y: origin.y + 40, width: 1024, height: 536))
            let placement = try XCTUnwrap(PopoverPlacement.resolve(
                anchor: CGRect(x: origin.x + 980, y: origin.y + 576, width: 24, height: 24),
                displays: [main, display], naturalSize: fullSize, glassMargin: 10))
            let frame = try XCTUnwrap(placement.glassPanelFrame(margin: 10))
            XCTAssertEqual(placement.contentSize, CGSize(width: 360, height: 510))
            XCTAssertEqual(frame.height, 542)
            XCTAssertEqual(frame.minY, display.visibleFrame.minY)
            XCTAssertEqual(frame.maxX, display.visibleFrame.maxX)
            XCTAssertEqual(frame.maxY - 10, origin.y + 572)
            XCTAssertEqual(frame.minY + 10 + placement.contentSize.height, origin.y + 560)
            XCTAssertGreaterThanOrEqual(frame.minX, display.visibleFrame.minX)
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

    func testGlassMarginClampsShortViewportsBeforePlacingThePanel() throws {
        for origin in [CGPoint.zero, CGPoint(x: -1024, y: 0), CGPoint(x: 0, y: -600)] {
            let display = PopoverPlacement.Display(
                frame: CGRect(origin: origin, size: CGSize(width: 1024, height: 600)),
                visibleFrame: CGRect(x: origin.x, y: origin.y + 40, width: 1024, height: 536))
            let anchor = CGRect(x: origin.x + 980, y: origin.y + 576, width: 24, height: 24)
            for margin: CGFloat in [10, 32] {
                let placement = try XCTUnwrap(PopoverPlacement.resolve(
                    anchor: anchor, displays: [display], naturalSize: fullSize, glassMargin: margin))
                let frame = try XCTUnwrap(placement.glassPanelFrame(margin: margin))
                XCTAssertEqual(placement.contentSize, CGSize(width: 360, height: 520 - margin))
                XCTAssertEqual(frame.height, 532 + margin)
                XCTAssertEqual(frame.minY, display.visibleFrame.minY)
                XCTAssertEqual(frame.maxY - margin, anchor.minY - 4)
                XCTAssertEqual(frame.minY + margin + placement.contentSize.height, anchor.minY - 16)
                XCTAssertGreaterThanOrEqual(frame.minX, display.visibleFrame.minX)
                XCTAssertLessThanOrEqual(frame.maxX, display.visibleFrame.maxX)
            }
        }
    }

    func testGlassMarginsPreserveNaturalContentAndScreenEdgePlacement() throws {
        for x: CGFloat in [0, 1200, 1416] {
            for margin: CGFloat in [10, 32] {
                let placement = try XCTUnwrap(PopoverPlacement.resolve(
                    anchor: CGRect(x: x, y: 876, width: 24, height: 24),
                    displays: [main], naturalSize: fullSize, glassMargin: margin))
                let frame = try XCTUnwrap(placement.glassPanelFrame(margin: margin))
                XCTAssertEqual(placement.contentSize, fullSize)
                XCTAssertEqual(frame.width - 2 * margin, fullSize.width)
                XCTAssertEqual(frame.height - 2 * margin - 12, fullSize.height)
                XCTAssertGreaterThanOrEqual(frame.minX, main.visibleFrame.minX)
                XCTAssertLessThanOrEqual(frame.maxX, main.visibleFrame.maxX)
                XCTAssertGreaterThanOrEqual(frame.minY, main.visibleFrame.minY)
                XCTAssertEqual(frame.maxY - margin, 872)
                XCTAssertEqual(frame.minY + margin + fullSize.height, 860)
            }
        }
    }

    func testGlassArrowTipUsesVisibleTopWhenAnchorExtendsIntoMenuBar() throws {
        let placement = try XCTUnwrap(PopoverPlacement.resolve(
            anchor: CGRect(x: 1200, y: 884, width: 24, height: 16),
            displays: [main], naturalSize: fullSize, glassMargin: 32))
        let frame = try XCTUnwrap(placement.glassPanelFrame(margin: 32))
        XCTAssertEqual(PopoverPlacement.glassArrowHeight, 12)
        XCTAssertEqual(frame.maxY - 32, 872)
        XCTAssertEqual(frame.minY + 32 + placement.contentSize.height, 860)
        XCTAssertGreaterThanOrEqual(frame.minY, main.visibleFrame.minY)
    }

    func testGlassDynamicHeightsKeepArrowAnchoredWithoutChangingContentWidth() throws {
        for margin: CGFloat in [10, 32] {
            for naturalHeight: CGFloat in [154, 715, 900] {
                let placement = try XCTUnwrap(PopoverPlacement.resolve(
                    anchor: CGRect(x: 1416, y: 876, width: 24, height: 24),
                    displays: [main], naturalSize: CGSize(width: 360, height: naturalHeight),
                    glassMargin: margin))
                let frame = try XCTUnwrap(placement.glassPanelFrame(margin: margin))
                XCTAssertEqual(placement.contentSize.width, 360)
                XCTAssertEqual(placement.contentSize.height, min(naturalHeight, 812 - margin))
                XCTAssertEqual(frame.maxY - margin, 872)
                XCTAssertEqual(frame.minY + margin + placement.contentSize.height, 860)
                XCTAssertEqual(frame.maxX, main.visibleFrame.maxX)
                XCTAssertGreaterThanOrEqual(frame.minY, main.visibleFrame.minY)
            }
        }
    }

    func testGlassRequiresSpaceForArrowAndBottomMarginBeforeShowingContent() throws {
        for margin: CGFloat in [10, 32] {
            let visibleHeight = margin + 16
            let display = PopoverPlacement.Display(
                frame: CGRect(x: 0, y: 0, width: 1024, height: 40 + visibleHeight + 24),
                visibleFrame: CGRect(x: 0, y: 40, width: 1024, height: visibleHeight))
            let anchor = CGRect(x: 900, y: display.visibleFrame.maxY, width: 24, height: 24)
            XCTAssertNotNil(PopoverPlacement.resolve(
                anchor: anchor, displays: [display], naturalSize: fullSize))
            XCTAssertNil(PopoverPlacement.resolve(
                anchor: anchor, displays: [display], naturalSize: fullSize, glassMargin: margin))
            let placement = try XCTUnwrap(PopoverPlacement.resolve(
                anchor: anchor, displays: [display], naturalSize: fullSize, glassMargin: margin - 1))
            let frame = try XCTUnwrap(placement.glassPanelFrame(margin: margin - 1))
            XCTAssertEqual(placement.contentSize.height, 1)
            XCTAssertEqual(frame.minY, display.visibleFrame.minY)
        }
    }

    func testResolveRejectsInvalidOrUnusableGlassMarginsWithoutChangingClassic() throws {
        let anchor = CGRect(x: 300, y: 876, width: 24, height: 24)
        for margin: CGFloat in [-1, .infinity, .nan, .greatestFiniteMagnitude] {
            XCTAssertNil(PopoverPlacement.resolve(
                anchor: anchor, displays: [main], naturalSize: fullSize, glassMargin: margin))
        }
        let narrow = PopoverPlacement.Display(
            frame: CGRect(x: 0, y: 0, width: 400, height: 900),
            visibleFrame: CGRect(x: 0, y: 40, width: 400, height: 836))
        XCTAssertNotNil(PopoverPlacement.resolve(anchor: anchor, displays: [narrow], naturalSize: fullSize))
        XCTAssertNotNil(PopoverPlacement.resolve(
            anchor: anchor, displays: [narrow], naturalSize: fullSize, glassMargin: 10))
        XCTAssertNil(PopoverPlacement.resolve(
            anchor: anchor, displays: [narrow], naturalSize: fullSize, glassMargin: 32))
    }

    func testHidingArrowMovesNaturalBodyUpWithoutChangingItsContentSize() throws {
        for x: CGFloat in [0, 1200, 1416] {
            for margin: CGFloat in [10, 32] {
                let anchor = CGRect(x: x, y: 876, width: 24, height: 24)
                let shown = try XCTUnwrap(PopoverPlacement.resolve(
                    anchor: anchor, displays: [main], naturalSize: fullSize,
                    glassMargin: margin))
                let hidden = try XCTUnwrap(PopoverPlacement.resolve(
                    anchor: anchor, displays: [main], naturalSize: fullSize,
                    glassMargin: margin, showsArrow: false))
                let shownFrame = try XCTUnwrap(shown.glassPanelFrame(margin: margin))
                let hiddenFrame = try XCTUnwrap(hidden.glassPanelFrame(margin: margin))
                XCTAssertEqual(hidden.contentSize, fullSize)
                XCTAssertEqual(hiddenFrame.maxY, shownFrame.maxY)
                XCTAssertEqual(hiddenFrame.minX, shownFrame.minX)
                XCTAssertEqual(hiddenFrame.height, shownFrame.height - 12)
                XCTAssertEqual(hiddenFrame.minY, shownFrame.minY + 12)
                XCTAssertEqual(hiddenFrame.minY + margin + fullSize.height, anchor.minY - 4)
                XCTAssertEqual(hidden.arrowHeight, 0)
            }
        }
    }

    func testHidingArrowReturnsHeightToShortViewportOnNegativeDisplays() throws {
        for origin in [CGPoint.zero, CGPoint(x: -1024, y: -600)] {
            let display = PopoverPlacement.Display(
                frame: CGRect(origin: origin, size: CGSize(width: 1024, height: 600)),
                visibleFrame: CGRect(x: origin.x, y: origin.y + 40, width: 1024, height: 536))
            let anchor = CGRect(x: origin.x + 980, y: origin.y + 576, width: 24, height: 24)
            for margin: CGFloat in [10, 32] {
                let shown = try XCTUnwrap(PopoverPlacement.resolve(
                    anchor: anchor, displays: [display], naturalSize: fullSize, glassMargin: margin))
                let hidden = try XCTUnwrap(PopoverPlacement.resolve(
                    anchor: anchor, displays: [display], naturalSize: fullSize,
                    glassMargin: margin, showsArrow: false))
                XCTAssertEqual(hidden.contentSize.height, shown.contentSize.height + 12)
                XCTAssertEqual(hidden.glassPanelFrame(margin: margin), shown.glassPanelFrame(margin: margin))
                let classicShown = try XCTUnwrap(PopoverPlacement.resolve(
                    anchor: anchor, displays: [display], naturalSize: fullSize))
                let classicHidden = try XCTUnwrap(PopoverPlacement.resolve(
                    anchor: anchor, displays: [display], naturalSize: fullSize, showsArrow: false))
                XCTAssertEqual(classicHidden.contentSize, classicShown.contentSize)
            }
        }
    }
}
