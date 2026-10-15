import CoreGraphics
import XCTest
@testable import Wattson

final class GlassPopoverShapeTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 360, height: 412)

    func testOutlineContainsTheArrowAndBodyWithoutFillingItsTopCorners() {
        let path = GlassPopoverShape(arrowX: 180).path(in: bounds).cgPath
        XCTAssertEqual(path.boundingBoxOfPath, bounds)
        // The arrow reaches the top of the material; the body begins 12pt below it.
        XCTAssertTrue(path.contains(CGPoint(x: 180, y: 0.5)))
        XCTAssertFalse(path.contains(CGPoint(x: 188, y: 0.5)))
        XCTAssertFalse(path.contains(CGPoint(x: 140, y: 11.5)))
        XCTAssertTrue(path.contains(CGPoint(x: 140, y: 12.5)))
        XCTAssertTrue(path.contains(CGPoint(x: 0.5, y: 52)))
        XCTAssertTrue(path.contains(CGPoint(x: 359.5, y: 52)))
        XCTAssertFalse(path.contains(CGPoint(x: 1, y: 13)))
        XCTAssertFalse(path.contains(CGPoint(x: 359, y: 13)))
        XCTAssertFalse(path.contains(CGPoint(x: 1, y: 411)))
        XCTAssertFalse(path.contains(CGPoint(x: 359, y: 411)))
        XCTAssertTrue(path.contains(CGPoint(x: 180, y: 411.5)))
    }

    func testArrowClampsBeforeRoundedCornersAndKeepsAContinuousFilledJoin() {
        let cases: [(CGFloat, CGFloat)] = [(-500, 38), (180, 180), (900, 322)]
        for (desired, expected) in cases {
            XCTAssertEqual(GlassPopoverShape.clampedArrowX(desired, width: bounds.width), expected)
            let path = GlassPopoverShape(arrowX: desired).path(in: bounds).cgPath
            XCTAssertTrue(path.contains(CGPoint(x: expected, y: 0.5)))
            XCTAssertTrue(path.contains(CGPoint(x: expected, y: 11.5)))
            XCTAssertTrue(path.contains(CGPoint(x: expected, y: 12.5)))
            XCTAssertFalse(path.contains(CGPoint(x: expected + 14, y: 11.5)))
            XCTAssertFalse(path.contains(CGPoint(x: expected - 14, y: 11.5)))
            XCTAssertEqual(path.boundingBoxOfPath, bounds)
        }
    }

    func testAppKitPathFlipsTheSameOutlineIncludingNonzeroBoundsOrigin() {
        let translated = bounds.offsetBy(dx: 25, dy: -80)
        let shape = GlassPopoverShape(arrowX: 90)
        let swiftUI = shape.path(in: translated).cgPath
        let appKit = shape.appKitPath(in: translated)
        XCTAssertEqual(appKit.boundingBoxOfPath, translated)
        let samples = [CGPoint(x: 115, y: -79.5), CGPoint(x: 120, y: -79.5),
                       CGPoint(x: 65, y: -67.5), CGPoint(x: 26, y: -67),
                       CGPoint(x: 26, y: 331), CGPoint(x: 115, y: 120)]
        for point in samples {
            let flipped = CGPoint(x: point.x, y: translated.minY + translated.maxY - point.y)
            XCTAssertEqual(appKit.contains(flipped), swiftUI.contains(point))
        }
        XCTAssertTrue(appKit.contains(CGPoint(x: 115, y: translated.maxY - 0.5)))
        XCTAssertFalse(appKit.contains(CGPoint(x: 155, y: translated.maxY - 0.5)))
    }
}
