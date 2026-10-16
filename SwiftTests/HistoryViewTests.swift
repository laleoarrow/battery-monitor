import AppKit
import XCTest
@testable import Wattson

/// Native renderer tests. Run in the existing isolated macOS test environment.
final class HistoryViewTests: XCTestCase {
    private func view() -> HistoryView {
        _ = NSApplication.shared
        let view = HistoryView()
        view.frame = NSRect(x: 0, y: 0, width: PopoverStyle.contentWidth, height: HistoryView.preferredHeight)
        view.layoutSubtreeIfNeeded()
        return view
    }

    func testNativePathUsesCurvesAndPreservesEndpoints() throws {
        let view = view()
        view.update(samples: [10, 58.1, 15], peak: 58.1, color: .systemBlue,
                    timing: .init(sampledAt: [0, 2, 4], referenceTime: 4))
        let path = try XCTUnwrap(view.chartPathForTest)
        var types: [CGPathElementType] = []
        path.applyWithBlock { types.append($0.pointee.type) }
        XCTAssertEqual(types, [.moveToPoint, .addCurveToPoint, .addCurveToPoint])
        XCTAssertEqual(path.currentPoint.x, PopoverStyle.contentWidth, accuracy: 1e-8)
        XCTAssertEqual(path.currentPoint.y, CGFloat(1 - 15 / view.chartCeilingForTest) * HistoryView.chartHeight,
                       accuracy: 1e-8)
        XCTAssertFalse(view.hasChartAnimationForTest)
    }

    func testUnchangedPresentationDoesNotRenderAgain() {
        let view = view()
        let timing = HistoryChartTiming(sampledAt: [0, 2], referenceTime: 2)
        view.update(samples: [10, 20], peak: 20, color: .systemBlue, timing: timing)
        let renders = view.renderCountForTest
        view.update(samples: [10, 20], peak: 20, color: .systemBlue, timing: timing)
        XCTAssertEqual(view.renderCountForTest, renders)
    }

    func testDetachedOrInactiveViewNeverStartsMotion() {
        let view = view()
        view.setAnimationsEnabled(true)
        view.setPresentationActive(true)
        view.update(samples: [10, 20], peak: 20, color: .systemBlue,
                    timing: .init(sampledAt: [0, 2], referenceTime: 2))
        view.update(samples: [10, 20, 15], peak: 20, color: .systemBlue,
                    timing: .init(sampledAt: [0, 2, 4], referenceTime: 4))
        XCTAssertFalse(view.hasChartAnimationForTest)
        view.setPresentationActive(false)
        view.setAnimationsEnabled(false)
        view.isHidden = true
        XCTAssertFalse(view.hasChartAnimationForTest)
    }

    func testEmptyAndMalformedDataClearTheCurve() {
        let view = view()
        view.update(samples: [10, 20], peak: 20, color: .systemBlue)
        XCTAssertNotNil(view.chartPathForTest)
        view.update(samples: [], peak: 0, color: .systemBlue)
        XCTAssertNil(view.chartPathForTest)
        view.update(samples: [10, 20], peak: 20, color: .systemBlue,
                    timing: .init(sampledAt: [1], referenceTime: 2))
        XCTAssertNil(view.chartPathForTest)
    }

    func testDetachedScaleExpansionSettlesAtTheOriginalSampleAndFixedBaseline() throws {
        let view = view()
        view.update(samples: [10, 20], peak: 20, color: .systemBlue,
                    timing: .init(sampledAt: [0, 2], referenceTime: 2))
        let oldCeiling = view.chartCeilingForTest
        view.update(samples: [10, 20, 100], peak: 100, color: .systemBlue,
                    timing: .init(sampledAt: [0, 2, 4], referenceTime: 4))
        XCTAssertGreaterThan(view.chartCeilingForTest, oldCeiling)
        let path = try XCTUnwrap(view.chartPathForTest)
        XCTAssertEqual(path.currentPoint.x, PopoverStyle.contentWidth, accuracy: 1e-8)
        XCTAssertEqual(path.currentPoint.y,
            HistoryView.chartHeight * CGFloat(1 - 100 / view.chartCeilingForTest), accuracy: 1e-8)
        let clip = try XCTUnwrap(view.layer?.sublayers?.first(where: { $0.masksToBounds }))
        let plot = try XCTUnwrap(clip.sublayers?.first(where: {
            $0.sublayers?.contains(where: { $0 is CAGradientLayer }) == true
        }))
        XCTAssertEqual(plot.anchorPoint, CGPoint(x: 0, y: 1))
        XCTAssertEqual(plot.position, CGPoint(x: 0, y: HistoryView.chartHeight))
        XCTAssertTrue(CATransform3DIsIdentity(plot.transform))
        XCTAssertFalse(view.hasChartAnimationForTest)
    }

    func testSameSamplesCanFinishScaleHysteresisWhileTheirTimesAge() {
        let view = view()
        view.update(samples: [100, 10, 20], peak: 100, color: .systemBlue,
                    timing: .init(sampledAt: [0, 2, 4], referenceTime: 4))
        let highCeiling = view.chartCeilingForTest
        for now in stride(from: 6.0, through: 14, by: 2) {
            view.update(samples: [10, 20], peak: 20, color: .systemBlue,
                        timing: .init(sampledAt: [2, 4], referenceTime: now))
            if now < 14 { XCTAssertEqual(view.chartCeilingForTest, highCeiling) }
        }
        XCTAssertLessThan(view.chartCeilingForTest, highCeiling)
        XCTAssertFalse(view.hasChartAnimationForTest)
    }

    func testConsecutiveFullRingUpdatesKeepThePreviousLeftBoundaryInterval() throws {
        let view = view()
        func update(_ start: Int) {
            let times = (start..<(start + 60)).map { Double($0) * 2 }
            let values = times.map { $0 == 0 ? 100.0 : 10.0 }
            view.update(samples: values, peak: values.max()!, color: .systemBlue,
                        timing: .init(sampledAt: times, referenceTime: times.last!))
        }
        func firstCubic() throws -> [CGPoint] {
            var points: [CGPoint] = []
            try XCTUnwrap(view.chartPathForTest).applyWithBlock {
                let element = $0.pointee
                if element.type == .moveToPoint, points.isEmpty { points.append(element.points[0]) }
                else if element.type == .addCurveToPoint, points.count == 1 {
                    points.append(contentsOf: (0..<3).map { element.points[$0] })
                }
            }
            XCTAssertEqual(points.count, 4)
            return points
        }
        update(0)
        update(1)
        let before = try firstCubic()
        update(2)
        let after = try firstCubic()
        let shift = PopoverStyle.contentWidth * 2 / 120
        for (old, new) in zip(before, after) {
            XCTAssertEqual(new.x + shift, old.x, accuracy: 1e-8)
            XCTAssertEqual(new.y, old.y, accuracy: 1e-8)
        }
        XCTAssertLessThan(after[0].x, 0)
        let clip = try XCTUnwrap(view.layer?.sublayers?.first(where: { $0.masksToBounds }))
        let gradient = try XCTUnwrap(clip.sublayers?.flatMap { $0.sublayers ?? [] }
            .compactMap { $0 as? CAGradientLayer }.first)
        let mask = try XCTUnwrap(gradient.mask as? CAShapeLayer)
        XCTAssertEqual(gradient.frame.minX, after[0].x, accuracy: 1e-8)
        XCTAssertEqual(gradient.frame.maxX, PopoverStyle.contentWidth, accuracy: 1e-8)
        XCTAssertEqual(mask.frame, gradient.bounds)
        var fillStart: CGPoint?
        mask.path?.applyWithBlock {
            if $0.pointee.type == .moveToPoint, fillStart == nil { fillStart = $0.pointee.points[0] }
        }
        let fill = try XCTUnwrap(fillStart)
        XCTAssertEqual(fill.x + gradient.frame.minX, after[0].x, accuracy: 1e-8)
        XCTAssertEqual(fill.y, after[0].y, accuracy: 1e-8)
    }

    func testDrawingContextRemainsBoundedAcrossRepeatedFullRingUpdates() {
        let view = view()
        for start in 0..<400 {
            let times = (start..<(start + 60)).map { Double($0) * 2 }
            view.update(samples: Array(repeating: 10, count: 60), peak: 10, color: .systemBlue,
                        timing: .init(sampledAt: times, referenceTime: times.last!))
            var anchors = 0
            view.chartPathForTest?.applyWithBlock {
                if $0.pointee.type == .moveToPoint || $0.pointee.type == .addCurveToPoint { anchors += 1 }
            }
            XCTAssertLessThanOrEqual(anchors, 64)
        }
    }

    func testContractingScaleKeepsFillForATallInteriorContextPoint() throws {
        let view = view()
        for start in 0...5 {
            let times = (start..<(start + 60)).map { Double($0) * 2 }
            let values = times.map { $0 == 0 ? 300.0 : ($0 == 6 ? 100.0 : 10.0) }
            view.update(samples: values, peak: values.max()!, color: .systemBlue,
                        timing: .init(sampledAt: times, referenceTime: times.last!))
        }
        XCTAssertEqual(view.chartCeilingForTest, 15)
        let path = try XCTUnwrap(view.chartPathForTest)
        let clip = try XCTUnwrap(view.layer?.sublayers?.first(where: { $0.masksToBounds }))
        let gradient = try XCTUnwrap(clip.sublayers?.flatMap { $0.sublayers ?? [] }
            .compactMap { $0 as? CAGradientLayer }.first)
        let mask = try XCTUnwrap(gradient.mask as? CAShapeLayer)
        let fill = try XCTUnwrap(mask.path)
        let top = HistoryView.chartHeight * CGFloat(1 - 100.0 / 15)
        XCTAssertEqual(gradient.frame.minY, top, accuracy: 1e-8)
        XCTAssertEqual(gradient.frame.maxY, HistoryView.chartHeight, accuracy: 1e-8)
        XCTAssertEqual(path.boundingBoxOfPath.minY, top, accuracy: 1e-8)
        XCTAssertEqual(fill.boundingBoxOfPath.minY + gradient.frame.minY, top, accuracy: 1e-8)
        XCTAssertEqual(gradient.frame.minY + gradient.startPoint.y * gradient.frame.height, 0, accuracy: 1e-8)
        XCTAssertEqual(gradient.frame.minY + gradient.endPoint.y * gradient.frame.height,
                       HistoryView.chartHeight, accuracy: 1e-8)
    }

    func testStrokeLivesOutsideTheScaledFillAndKeepsItsPhysicalWidth() throws {
        let view = view()
        for (times, values) in [([0.0, 2], [40.0, 45]), ([0, 2, 4], [40, 45, 300])] {
            view.update(samples: values, peak: values.max()!, color: .systemBlue,
                        timing: .init(sampledAt: times, referenceTime: times.last!))
        }
        let clip = try XCTUnwrap(view.layer?.sublayers?.first(where: { $0.masksToBounds }))
        let line = try XCTUnwrap(clip.sublayers?.compactMap { $0 as? CAShapeLayer }.first)
        let viewport = try XCTUnwrap(clip.sublayers?.first(where: {
            $0.sublayers?.contains(where: { $0 is CAGradientLayer }) == true
        }))
        XCTAssertTrue(line.superlayer === clip)
        XCTAssertFalse(line.superlayer === viewport)
        XCTAssertEqual(line.lineWidth, 1.6)
        XCTAssertTrue(CATransform3DIsIdentity(line.transform))
        XCTAssertTrue(CATransform3DIsIdentity(clip.transform))
        XCTAssertEqual(line.path, view.chartPathForTest)
    }

    func testDirectPathsMatchThePreviousBlendThenTransformRenderer() throws {
        let view = view()
        func graph(_ values: [Double], _ times: [Double], _ now: Double,
                   _ ceiling: Double, _ context: Int = 0) -> HistoryChartGeometry {
            .init(samples: values, timing: .init(sampledAt: times, referenceTime: now),
                  ceiling: ceiling, leadingContextCount: context)
        }
        let fixtures: [(HistoryChartGeometry, HistoryChartGeometry, Double, Double)] = [
            (graph([0, 0, 100], [0, 2, 4], 4, 200),
             graph([0, 0, 100, 150], [0, 2, 4, 6], 6, 200), 200, 200),
            (graph([0, 0, 100], [0, 2, 4], 4, 200),
             graph([0, 0, 100, 300], [0, 2, 4, 6], 6, 350), 200, 350),
            (graph([100, 10, 20], [0, 2, 4], 120, 200, 1),
             graph([100, 10, 20, 30], [0, 2, 4, 6], 122, 40, 2), 200, 40),
            (graph([10, 20, 80, 90], [0, 2, 20, 22], 22, 100),
             graph([10, 20, 80, 90, 60], [0, 2, 20, 22, 24], 24, 100), 100, 100),
            (graph([10, .nan, 80], [0, 2, 4], 4, 100),
             graph([10, .nan, 80, 50], [0, 2, 4, 6], 6, 100), 100, 100),
        ]
        for (old, target, oldCeiling, newCeiling) in fixtures {
            // Float-rounded presentation controls model an interrupted render;
            // alignment still uses the unchanged raw model anchors.
            let shown = old.segments.map {
                HistoryChartGeometry.Cubic(start: $0.start,
                    control1: .init(x: $0.control1.x, y: Double(Float($0.control1.y))),
                    control2: .init(x: $0.control2.x, y: Double(Float($0.control2.y))), end: $0.end)
            }
            let start = try XCTUnwrap(target.alignedStart(from: old, presentedSegments: shown,
                fraction: 2.0 / 120, oldCeiling: oldCeiling, newCeiling: newCeiling))
            for frame in 0...32 {
                let q = Double(frame) / 32
                let sy = 1 + (newCeiling / oldCeiling - 1) * (1 - q)
                let transform = CGAffineTransform(a: 1, b: 0, c: 0, d: CGFloat(sy),
                    tx: PopoverStyle.contentWidth * CGFloat(2.0 / 120 * (1 - q)) + 1.25,
                    ty: HistoryView.chartHeight * CGFloat(1 - sy))
                for filled in [false, true] {
                    let expected = legacyPath(target, start: start, progress: q,
                                              filled: filled, transform: transform)
                    let actual = view.pathForTest(target, filled: filled,
                        blendingFrom: start, at: q, transform: transform)
                    assertSameCommands(actual, expected)
                }
            }
        }
    }

    func testUnscaledStrokeEqualsInterpolationOfItsTwoEndpointPaths() throws {
        let view = view()
        let old = HistoryChartGeometry(samples: [0, 0, 100],
            timing: .init(sampledAt: [0, 2, 4], referenceTime: 4), ceiling: 200)
        let target = HistoryChartGeometry(samples: [0, 0, 100, 150],
            timing: .init(sampledAt: [0, 2, 4, 6], referenceTime: 6), ceiling: 200)
        let start = try XCTUnwrap(target.alignedStart(from: old, presentedSegments: old.segments,
            fraction: 2.0 / 120, oldCeiling: 200, newCeiling: 200))
        let shift = PopoverStyle.contentWidth * 2 / 120 + 1.25
        let from = pathCommands(view.pathForTest(start,
            transform: CGAffineTransform(translationX: shift, y: 0)))
        let to = pathCommands(view.pathForTest(target))
        XCTAssertEqual(from.count, to.count)
        for frame in 0...64 {
            let q = CGFloat(frame) / 64
            let actual = pathCommands(view.pathForTest(target, blendingFrom: start, at: Double(q),
                transform: CGAffineTransform(translationX: shift * (1 - q), y: 0)))
            XCTAssertEqual(actual.count, from.count)
            for (command, endpoints) in zip(actual, zip(from, to)) {
                XCTAssertEqual(command.0, endpoints.0.0)
                XCTAssertEqual(command.0, endpoints.1.0)
                XCTAssertEqual(command.1.count, endpoints.0.1.count)
                XCTAssertEqual(command.1.count, endpoints.1.1.count)
                for (point, pair) in zip(command.1, zip(endpoints.0.1, endpoints.1.1)) {
                    XCTAssertEqual(point.x, pair.0.x + (pair.1.x - pair.0.x) * q, accuracy: 1e-10)
                    XCTAssertEqual(point.y, pair.0.y + (pair.1.y - pair.0.y) * q, accuracy: 1e-10)
                }
            }
            // Midpoints also match Core Animation's previous piecewise linear
            // interpolation between its 33 keyframe paths.
            let q0 = floor(q * 32) / 32, q1 = min(q0 + 1 / 32, 1)
            let a = pathCommands(legacyPath(target, start: start, progress: Double(q0), filled: false,
                transform: CGAffineTransform(translationX: shift * (1 - q0), y: 0)))
            let b = pathCommands(legacyPath(target, start: start, progress: Double(q1), filled: false,
                transform: CGAffineTransform(translationX: shift * (1 - q1), y: 0)))
            let intervalProgress = (q - q0) * 32
            for (command, endpoints) in zip(actual, zip(a, b)) {
                XCTAssertEqual(command.0, endpoints.0.0)
                XCTAssertEqual(command.0, endpoints.1.0)
                XCTAssertEqual(command.1.count, endpoints.0.1.count)
                XCTAssertEqual(command.1.count, endpoints.1.1.count)
                for (point, pair) in zip(command.1, zip(endpoints.0.1, endpoints.1.1)) {
                    XCTAssertEqual(point.x, pair.0.x + (pair.1.x - pair.0.x) * intervalProgress, accuracy: 1e-10)
                    XCTAssertEqual(point.y, pair.0.y + (pair.1.y - pair.0.y) * intervalProgress, accuracy: 1e-10)
                }
            }
        }
    }

    private func legacyPath(_ geometry: HistoryChartGeometry, start: HistoryChartGeometry,
                            progress: Double, filled: Bool, transform: CGAffineTransform) -> CGPath {
        func point(_ p: HistoryChartGeometry.Point) -> CGPoint {
            CGPoint(x: CGFloat(p.x) * PopoverStyle.contentWidth,
                    y: CGFloat(1 - p.y) * HistoryView.chartHeight)
        }
        let controls = zip(start.segments, geometry.segments).map { a, b in
            func blend(_ a: HistoryChartGeometry.Point, _ b: HistoryChartGeometry.Point) -> HistoryChartGeometry.Point {
                .init(x: a.x + (b.x - a.x) * progress, y: a.y + (b.y - a.y) * progress)
            }
            return (blend(a.control1, b.control1), blend(a.control2, b.control2))
        }
        let result = CGMutablePath()
        var index = 0
        for run in geometry.runs {
            let subpath = CGMutablePath()
            subpath.move(to: point(run.first!))
            for end in run.dropFirst() {
                subpath.addCurve(to: point(end), control1: point(controls[index].0),
                                 control2: point(controls[index].1))
                index += 1
            }
            if filled {
                subpath.addLine(to: CGPoint(x: CGFloat(run.last!.x) * PopoverStyle.contentWidth,
                                           y: HistoryView.chartHeight))
                subpath.addLine(to: CGPoint(x: CGFloat(run.first!.x) * PopoverStyle.contentWidth,
                                           y: HistoryView.chartHeight))
                subpath.closeSubpath()
            }
            result.addPath(subpath, transform: transform)
        }
        return result
    }

    private func assertSameCommands(_ actual: CGPath, _ expected: CGPath,
                                    file: StaticString = #filePath, line: UInt = #line) {
        let actual = pathCommands(actual), expected = pathCommands(expected)
        XCTAssertEqual(actual.count, expected.count, file: file, line: line)
        for (a, b) in zip(actual, expected) {
            XCTAssertEqual(a.0, b.0, file: file, line: line)
            XCTAssertEqual(a.1.count, b.1.count, file: file, line: line)
            for (a, b) in zip(a.1, b.1) {
                XCTAssertEqual(a.x, b.x, accuracy: 1e-10, file: file, line: line)
                XCTAssertEqual(a.y, b.y, accuracy: 1e-10, file: file, line: line)
            }
        }
    }

    private func pathCommands(_ path: CGPath) -> [(CGPathElementType, [CGPoint])] {
        var result: [(CGPathElementType, [CGPoint])] = []
        path.applyWithBlock {
            let element = $0.pointee
            let count = element.type == .closeSubpath ? 0 : (element.type == .addCurveToPoint ? 3 : 1)
            result.append((element.type, (0..<count).map { element.points[$0] }))
        }
        return result
    }
}
