import AppKit
import XCTest
@testable import Wattson

/// Native renderer tests. Run in the existing isolated macOS test environment.
final class HistoryViewTests: XCTestCase {
    func testDebugMotionOverrideFallsBackToSystemWhenUnspecified() {
        let key = "WATTSON_FORCE_REDUCE_MOTION"
        let previous = ProcessInfo.processInfo.environment[key]
        defer {
            if let previous { setenv(key, previous, 1) }
            else { unsetenv(key) }
        }
        setenv(key, "0", 1)
        XCTAssertFalse(HistoryView.reducesMotionForTest)
        setenv(key, "1", 1)
        XCTAssertTrue(HistoryView.reducesMotionForTest)
        unsetenv(key)
        XCTAssertEqual(HistoryView.reducesMotionForTest,
                       NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        setenv(key, "invalid", 1)
        XCTAssertEqual(HistoryView.reducesMotionForTest,
                       NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

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
        let gradient = try XCTUnwrap(clip.sublayers?.compactMap { $0 as? CAGradientLayer }.first)
        XCTAssertEqual(gradient.frame, clip.bounds)
        XCTAssertTrue(CATransform3DIsIdentity(gradient.transform))
        XCTAssertEqual(gradient.startPoint, CGPoint(x: 0.5, y: 0))
        XCTAssertEqual(gradient.endPoint, CGPoint(x: 0.5, y: 1))
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
        let gradient = try XCTUnwrap(clip.sublayers?.compactMap { $0 as? CAGradientLayer }.first)
        let mask = try XCTUnwrap(gradient.mask as? CAShapeLayer)
        XCTAssertEqual(gradient.frame.minX, 0, accuracy: 1e-8)
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
        let gradient = try XCTUnwrap(clip.sublayers?.compactMap { $0 as? CAGradientLayer }.first)
        let mask = try XCTUnwrap(gradient.mask as? CAShapeLayer)
        let fill = try XCTUnwrap(mask.path)
        let top = HistoryView.chartHeight * CGFloat(1 - 100.0 / 15)
        XCTAssertEqual(gradient.frame.minY, 0, accuracy: 1e-8)
        XCTAssertEqual(gradient.frame.maxY, HistoryView.chartHeight, accuracy: 1e-8)
        XCTAssertEqual(path.boundingBoxOfPath.minY, top, accuracy: 1e-8)
        XCTAssertEqual(fill.boundingBoxOfPath.minY + gradient.frame.minY, top, accuracy: 1e-8)
        XCTAssertEqual(gradient.frame.minY + gradient.startPoint.y * gradient.frame.height, 0, accuracy: 1e-8)
        XCTAssertEqual(gradient.frame.minY + gradient.endPoint.y * gradient.frame.height,
                       HistoryView.chartHeight, accuracy: 1e-8)
    }

    func testStrokeAndFillShareAnUnscaledViewportAndKeepPhysicalWidth() throws {
        let view = view()
        for (times, values) in [([0.0, 2], [40.0, 45]), ([0, 2, 4], [40, 45, 300])] {
            view.update(samples: values, peak: values.max()!, color: .systemBlue,
                        timing: .init(sampledAt: times, referenceTime: times.last!))
        }
        let clip = try XCTUnwrap(view.layer?.sublayers?.first(where: { $0.masksToBounds }))
        let line = try XCTUnwrap(clip.sublayers?.compactMap { $0 as? CAShapeLayer }.first)
        let gradient = try XCTUnwrap(clip.sublayers?.compactMap { $0 as? CAGradientLayer }.first)
        XCTAssertTrue(line.superlayer === clip)
        XCTAssertTrue(gradient.superlayer === clip)
        XCTAssertTrue(CATransform3DIsIdentity(gradient.transform))
        XCTAssertEqual(line.lineWidth, 1.6)
        XCTAssertTrue(CATransform3DIsIdentity(line.transform))
        XCTAssertTrue(CATransform3DIsIdentity(clip.transform))
        XCTAssertEqual(line.path, view.chartPathForTest)
    }

    func testStrokeAndFillUseIdenticalCubicEdgesAcrossScaleChangesAndGaps() throws {
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
            (graph([10, .nan, 80, 90], [0, 2, 4, 6], 6, 100),
             graph([10, .nan, 80, 90, 50], [0, 2, 4, 6, 8], 8, 100), 100, 100),
        ]
        for (old, target, oldCeiling, newCeiling) in fixtures {
            let start = try XCTUnwrap(target.alignedStart(from: old, presentedSegments: old.segments,
                fraction: 2.0 / 120, oldCeiling: oldCeiling, newCeiling: newCeiling))
            for geometry in [start, target] {
                let stroke = pathCommands(view.pathForTest(geometry))
                let fill = pathCommands(view.pathForTest(geometry, filled: true))
                    .filter { $0.0 == .moveToPoint || $0.0 == .addCurveToPoint }
                XCTAssertEqual(stroke.count, fill.count)
                XCTAssertEqual(stroke.filter { $0.0 == .moveToPoint }.count, geometry.runs.count)
                for (line, area) in zip(stroke, fill) {
                    XCTAssertEqual(line.0, area.0)
                    XCTAssertEqual(line.1, area.1)
                }
            }
            for filled in [false, true] {
                let from = pathCommands(view.pathForTest(start, filled: filled))
                let to = pathCommands(view.pathForTest(target, filled: filled))
                XCTAssertEqual(from.map { $0.0 }, to.map { $0.0 })
                XCTAssertEqual(from.map { $0.1.count }, to.map { $0.1.count })
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
