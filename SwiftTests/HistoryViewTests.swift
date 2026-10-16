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
}
