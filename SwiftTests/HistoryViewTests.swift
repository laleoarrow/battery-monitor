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
        let plot = try XCTUnwrap(clip.sublayers?.first)
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
        let gradient = try XCTUnwrap(clip.sublayers?.first?.sublayers?.compactMap { $0 as? CAGradientLayer }.first)
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
        let gradient = try XCTUnwrap(clip.sublayers?.first?.sublayers?.compactMap { $0 as? CAGradientLayer }.first)
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
}
