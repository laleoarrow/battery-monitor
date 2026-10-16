import Foundation
import XCTest
@testable import Wattson

final class HistoryChartTests: XCTestCase {
    private func geometry(_ values: [Double], times: [Double]? = nil, now: Double? = nil) -> HistoryChartGeometry {
        let times = times ?? values.indices.map { Double($0) * 2 }
        return HistoryChartGeometry(samples: values,
            timing: .init(sampledAt: times, referenceTime: now ?? times.last ?? 0), ceiling: 100)
    }

    func testSingleSampleDoesNotInventAHistory() {
        let graph = geometry([25])
        XCTAssertEqual(graph.points.count, 1)
        XCTAssertTrue(graph.segments.isEmpty)
        XCTAssertEqual(graph.points[0].x, 1)
    }

    func testShortHistoryUsesItsRealDuration() {
        let graph = geometry([10, 20, 30], times: [10, 12, 14])
        XCTAssertEqual(graph.points[0].x, 1 - 4.0 / 120, accuracy: 1e-12)
        XCTAssertEqual(graph.points[2].x, 1)
    }

    func testIrregularSamplingPreservesTimeSpacing() {
        let graph = geometry([10, 20, 30], times: [0, 1, 5])
        XCTAssertEqual((graph.points[2].x - graph.points[1].x) /
            (graph.points[1].x - graph.points[0].x), 4, accuracy: 1e-10)
    }

    func testPeakAndTroughHaveHorizontalTangents() {
        let graph = geometry([10, 90, 10, 70])
        XCTAssertEqual(graph.segments.count, 3)
        XCTAssertEqual(graph.segments[0].control2.y, 0.9, accuracy: 1e-12)
        XCTAssertEqual(graph.segments[1].control1.y, 0.9, accuracy: 1e-12)
        XCTAssertEqual(graph.segments[1].control2.y, 0.1, accuracy: 1e-12)
        XCTAssertEqual(graph.segments[2].control1.y, 0.1, accuracy: 1e-12)
    }

    func testCurvePassesThroughEverySample() {
        let graph = geometry([10, 58.1, 20, 25])
        for (index, segment) in graph.segments.enumerated() {
            XCTAssertEqual(segment.start, graph.points[index])
            XCTAssertEqual(segment.end, graph.points[index + 1])
            XCTAssertEqual(segment.value(at: 0), segment.start.y, accuracy: 1e-12)
            XCTAssertEqual(segment.value(at: 1), segment.end.y, accuracy: 1e-12)
        }
        XCTAssertEqual(graph.points.map(\.y).max()!, 0.581, accuracy: 1e-12)
    }

    func testPlateauStaysFlat() {
        let graph = geometry([0, 40, 40, 40, 0])
        for segment in graph.segments[1...2] {
            for t in stride(from: 0.0, through: 1.0, by: 0.05) {
                XCTAssertEqual(segment.value(at: t), 0.4, accuracy: 1e-12)
            }
        }
    }

    func testNoOvershootAcrossDeterministicStressSequences() {
        var state: UInt64 = 719
        for _ in 0..<300 {
            var times: [Double] = [0]
            var values: [Double] = []
            for index in 0..<60 {
                state = state &* 6364136223846793005 &+ 1
                values.append(Double((state >> 32) % 10001) / 100)
                if index > 0 { times.append(times.last! + 0.5 + Double(state % 500) / 100) }
            }
            let graph = geometry(values, times: times)
            for s in graph.segments {
                let lo = min(s.start.y, s.end.y), hi = max(s.start.y, s.end.y)
                for t in stride(from: 0.0, through: 1.0, by: 0.025) {
                    let y = s.value(at: t)
                    XCTAssertTrue(y.isFinite && y >= lo - 1e-12 && y <= hi + 1e-12)
                }
            }
        }
    }

    func testInternalTangentsMatchForUnequalTimeSteps() {
        let graph = geometry([10, 20, 65, 80], times: [0, 0.5, 4, 6])
        for index in 1..<graph.segments.count {
            let a = graph.segments[index - 1], b = graph.segments[index]
            let incoming = (a.end.y - a.control2.y) / (a.end.x - a.control2.x)
            let outgoing = (b.control1.y - b.start.y) / (b.control1.x - b.start.x)
            XCTAssertEqual(incoming, outgoing, accuracy: 1e-9)
        }
    }

    func testGapDoesNotBecomeASmoothInventedReading() {
        let graph = geometry([10, 15, 80, 90], times: [0, 2, 20, 22])
        XCTAssertEqual(graph.runs.count, 2)
        XCTAssertEqual(graph.segments.count, 2)
    }

    func testInvalidTimingFailsClosed() {
        for times in [[0, 0], [2, 1], [0, Double.nan], [0]] {
            XCTAssertTrue(geometry([10, 20], times: times, now: 4).points.isEmpty)
        }
        XCTAssertTrue(geometry([10, 20], times: [0, 2], now: 1).points.isEmpty)
    }

    func testDepartingPointCanBeClippedDrawingContextOnly() {
        let timing = HistoryChartTiming(sampledAt: [0, 2, 4], referenceTime: 121)
        let normal = HistoryChartGeometry(samples: [10, 20, 30], timing: timing, ceiling: 100)
        let drawing = HistoryChartGeometry(samples: [10, 20, 30], timing: timing, ceiling: 100,
                                           leadingContextCount: 1)
        XCTAssertEqual(normal.points.count, 2)
        XCTAssertEqual(drawing.points.count, 3)
        XCTAssertLessThan(drawing.points[0].x, 0)
        XCTAssertEqual(Array(drawing.points.dropFirst()), normal.points)
        XCTAssertEqual(drawing.points.last, normal.points.last)
    }

    func testDepartingPeakRetainsItsRawHeightWhenTheViewportScaleContracts() {
        let graph = HistoryChartGeometry(samples: [100, 10, 20],
            timing: .init(sampledAt: [0, 2, 4], referenceTime: 121), ceiling: 40,
            leadingContextCount: 1)
        XCTAssertEqual(graph.points[0].y, 2.5)
        XCTAssertLessThan(graph.points[0].x, 0)
        XCTAssertEqual(graph.points.dropFirst().map(\.y), [0.25, 0.5])
        for segment in graph.segments {
            for t in stride(from: 0.0, through: 1, by: 0.05) {
                XCTAssertGreaterThanOrEqual(segment.value(at: t), min(segment.start.y, segment.end.y) - 1e-12)
                XCTAssertLessThanOrEqual(segment.value(at: t), max(segment.start.y, segment.end.y) + 1e-12)
            }
        }
    }

    func testNonFiniteSampleBreaksTheLine() {
        let graph = geometry([10, 20, .nan, 40, 50])
        XCTAssertEqual(graph.runs.count, 2)
        XCTAssertEqual(graph.segments.count, 2)
    }

    func testScaleHoldsSmallChangesAndOnlyShrinksAfterDelay() {
        var scale = HistoryChartScale()
        let first = scale.update(peak: 58.1, at: 0)
        XCTAssertGreaterThanOrEqual(first, 58.1 * 1.14)
        XCTAssertEqual(scale.update(peak: 58.2, at: 2), first)
        XCTAssertEqual(scale.update(peak: 20, at: 4), first)
        XCTAssertEqual(scale.update(peak: 20, at: 11.99), first)
        XCTAssertLessThan(scale.update(peak: 20, at: 12), first)
    }

    func testScaleExpansionAndReset() {
        var scale = HistoryChartScale()
        _ = scale.update(peak: 10, at: 0)
        XCTAssertGreaterThanOrEqual(scale.update(peak: 200, at: 2), 200 * 1.14)
        scale.reset()
        XCTAssertEqual(scale.update(peak: 0, at: 3), 8)
        XCTAssertTrue(scale.update(peak: Double.greatestFiniteMagnitude, at: 4).isFinite)
    }

    func testScaleRecoveryCancelsPendingShrink() {
        var scale = HistoryChartScale()
        let initial = scale.update(peak: 90, at: 0)
        _ = scale.update(peak: 10, at: 2)
        _ = scale.update(peak: 90, at: 9)
        XCTAssertEqual(scale.update(peak: 10, at: 11), initial)
        XCTAssertEqual(scale.update(peak: 10, at: 18.99), initial)
        XCTAssertLessThan(scale.update(peak: 10, at: 19), initial)
    }

    func testScrollRequiresMatchingRetainedSamples() {
        let old = HistoryChartTiming(sampledAt: [0, 2, 4], referenceTime: 4)
        let next = HistoryChartTiming(sampledAt: [2, 4, 6], referenceTime: 6)
        XCTAssertEqual(HistoryChartTiming.scrollFraction(from: old, samples: [10, 20, 30],
            to: next, samples: [20, 30, 40])!, 2.0 / 120, accuracy: 1e-12)
        XCTAssertNil(HistoryChartTiming.scrollFraction(from: old, samples: [10, 20, 30],
            to: next, samples: [99, 30, 40]))
        XCTAssertNil(HistoryChartTiming.scrollFraction(from: old, samples: [10, 20, 30],
            to: .init(sampledAt: [20, 22], referenceTime: 22), samples: [1, 2]))
        XCTAssertNil(HistoryChartTiming.scrollFraction(from: old, samples: [10, 20, 30],
            to: old, samples: [10, 20, 30]))
    }

    func testHistoryKeepsCadenceReferenceUntilSamplingGap() {
        var now = 0.0
        let history = PowerHistory(clock: { now })
        history.append(10)
        now = 2
        history.append(20)
        let initial = history.chartPresentation
        let count = history.presentationMaterializationCountForTest

        now = 8
        XCTAssertEqual(history.chartPresentation.timing, initial.timing)
        now = 8.001
        let paused = history.chartPresentation
        XCTAssertEqual(paused.samples, initial.samples)
        XCTAssertEqual(paused.timing.sampledAt, initial.timing.sampledAt)
        XCTAssertEqual(paused.timing.referenceTime, now)
        XCTAssertEqual(history.presentationMaterializationCountForTest, count)
    }

    func testScrollRejectsMoreDeparturesThanRendererCanPreserve() {
        let old = HistoryChartTiming(sampledAt: [0, 2, 4, 6], referenceTime: 6)
        let next = HistoryChartTiming(sampledAt: [4, 6, 8], referenceTime: 8)
        XCTAssertNil(HistoryChartTiming.scrollFraction(from: old, samples: [10, 20, 30, 40],
            to: next, samples: [30, 40, 50]))
    }

    func testScrollRequiresPreviousEndpointAtTheRightEdge() {
        let next = HistoryChartTiming(sampledAt: [0, 2, 4], referenceTime: 4)
        XCTAssertNil(HistoryChartTiming.scrollFraction(
            from: .init(sampledAt: [0, 2], referenceTime: 3), samples: [10, 20],
            to: next, samples: [10, 20, 30]))
        XCTAssertNil(HistoryChartTiming.scrollFraction(
            from: .init(sampledAt: [0, 2], referenceTime: 1.99), samples: [10, 20],
            to: next, samples: [10, 20, 30]))
        XCTAssertEqual(HistoryChartTiming.scrollFraction(
            from: .init(sampledAt: [0, 2], referenceTime: 2), samples: [10, 20],
            to: next, samples: [10, 20, 30]), 2.0 / 120)
        XCTAssertEqual(HistoryChartTiming.scrollFraction(
            from: .init(sampledAt: [0, 2], referenceTime: 2.05), samples: [10, 20],
            to: next, samples: [10, 20, 30]), (4 - 2.05) / 120)
    }

    func testViewportMatchesStationaryAndAgingHistoryWithoutInventingReadings() throws {
        let old = HistoryChartTiming(sampledAt: [0, 2, 4], referenceTime: 4)
        let values = [10.0, 20, 30]
        XCTAssertEqual(HistoryChartTiming.viewportFraction(from: old, samples: values,
            to: old, samples: values), 0)
        XCTAssertEqual(HistoryChartTiming.viewportFraction(from: old, samples: values,
            to: .init(sampledAt: old.sampledAt, referenceTime: 6), samples: values), 2.0 / 120)
        XCTAssertNil(HistoryChartTiming.viewportFraction(from: old, samples: values,
            to: .init(sampledAt: [0, 2, 11], referenceTime: 11), samples: values))
        XCTAssertNil(HistoryChartTiming.viewportFraction(from: old, samples: values,
            to: old, samples: [10, 99, 30]))
    }

    func testViewportScaleExpansionAndContractionKeepSharedSamplesAtTheirOldPositions() throws {
        for (oldCeiling, newCeiling) in [(40.0, 100.0), (100.0, 40.0)] {
            let viewport = try XCTUnwrap(HistoryChartViewport(oldCeiling: oldCeiling,
                newCeiling: newCeiling, fraction: 2.0 / 120, width: 300))
            XCTAssertEqual(viewport.translationX, 5, accuracy: 1e-12)
            XCTAssertEqual(viewport.scaleY, newCeiling / oldCeiling, accuracy: 1e-12)
            for value in [0.0, 10, 25] {
                let newY = 64 * (1 - value / newCeiling)
                XCTAssertEqual(64 + (newY - 64) * viewport.scaleY,
                               64 * (1 - value / oldCeiling), accuracy: 1e-12)
            }
        }
    }

    func testViewportRetargetComposesTheActualPresentationRatherThanItsPreviousTarget() throws {
        let viewport = try XCTUnwrap(HistoryChartViewport(oldCeiling: 100,
            newCeiling: 40, fraction: 2.0 / 120, width: 300,
            presentedTranslationX: 3.5, presentedScaleY: 1.8))
        XCTAssertEqual(viewport.translationX, 8.5, accuracy: 1e-12)
        XCTAssertEqual(viewport.scaleY, 0.72, accuracy: 1e-12)
        for value in [0.0, 10, 30] {
            let oldY = 64 * (1 - value / 100)
            let newY = 64 * (1 - value / 40)
            XCTAssertEqual(64 + (newY - 64) * viewport.scaleY,
                           64 + (oldY - 64) * 1.8, accuracy: 1e-12)
        }
    }

    func testViewportRejectsInvalidAffineInputs() {
        for (old, new, fraction, width, tx, sy) in [
            (0.0, 10.0, 0.0, 300.0, 0.0, 1.0),
            (10, .infinity, 0, 300, 0, 1),
            (10, 20, .nan, 300, 0, 1),
            (10, 20, 0, 0, 0, 1),
            (10, 20, 0, 300, .nan, 1),
            (10, 20, 0, 300, 0, 0),
        ] {
            XCTAssertNil(HistoryChartViewport(oldCeiling: old, newCeiling: new,
                fraction: fraction, width: width, presentedTranslationX: tx, presentedScaleY: sy))
        }
    }

    func testGradientBandStaysAtTheVisibleChartTopDuringScaleChanges() throws {
        for (old, new) in [(350.0, 50.0), (350.0, 15.0), (55.0, 250.0)] {
            let viewport = try XCTUnwrap(HistoryChartViewport(oldCeiling: old, newCeiling: new,
                fraction: 2.0 / 120, width: 328))
            for q in [0.0, 0.25, 0.5, 0.9, 1] {
                let sy = 1 + (viewport.scaleY - 1) * (1 - q)
                let normalized = viewport.gradientStartY(at: q, fromScreenY: 0,
                    frameMinY: -96, frameHeight: 160, plotHeight: 64)
                let screen = HistoryChartViewport.gradientScreenStartY(startPointY: normalized,
                    frameMinY: -96, frameHeight: 160, scaleY: sy, plotHeight: 64)
                XCTAssertEqual(screen, 0, accuracy: 1e-10)
            }
        }
    }

    func testGradientAlphaBeginsAtTheOldViewportAndFinishesAtTheNewViewport() throws {
        let viewport = try XCTUnwrap(HistoryChartViewport(oldCeiling: 350, newCeiling: 50,
            fraction: 2.0 / 120, width: 328))
        func alpha(at progress: Double) -> Double {
            let start = viewport.gradientStartY(at: progress, fromScreenY: 0,
                frameMinY: 0, frameHeight: 64, plotHeight: 64) * 64
            let sampleY = 64 * (1 - 43.0 / 50)
            return 0.38 + (0.03 - 0.38) * (sampleY - start) / (64 - start)
        }
        XCTAssertEqual(alpha(at: 0), 0.073, accuracy: 1e-12)
        XCTAssertEqual(alpha(at: 1), 0.331, accuracy: 1e-12)
        XCTAssertLessThan(alpha(at: 0.25), alpha(at: 0.5))
        XCTAssertLessThan(alpha(at: 0.5), alpha(at: 0.9))
    }

    func testGradientRetargetUsesTheActualPresentedBandAndFrame() throws {
        let shownY = HistoryChartViewport.gradientScreenStartY(startPointY: 0.3,
            frameMinY: -96, frameHeight: 160, scaleY: 0.7, plotHeight: 64)
        XCTAssertEqual(shownY, -14.4, accuracy: 1e-12)
        let viewport = try XCTUnwrap(HistoryChartViewport(oldCeiling: 100, newCeiling: 40,
            fraction: 2.0 / 120, width: 328, presentedScaleY: 0.7))
        for q in [0.0, 0.25, 0.5, 0.9, 1] {
            let sy = 1 + (viewport.scaleY - 1) * (1 - q)
            let normalized = viewport.gradientStartY(at: q, fromScreenY: shownY,
                frameMinY: -320, frameHeight: 384, plotHeight: 64)
            let actual = HistoryChartViewport.gradientScreenStartY(startPointY: normalized,
                frameMinY: -320, frameHeight: 384, scaleY: sy, plotHeight: 64)
            XCTAssertEqual(actual, shownY * (1 - q), accuracy: 1e-10)
        }
    }

    func testBoundedGradientKeyframesKeepTheInterpolatedScreenBandWithinQuarterPoint() throws {
        let viewport = try XCTUnwrap(HistoryChartViewport(oldCeiling: 350, newCeiling: 15,
            fraction: 2.0 / 120, width: 328))
        for frame in 0..<256 {
            let q0 = Double(frame) / 256, q1 = Double(frame + 1) / 256, q = (q0 + q1) / 2
            let a = viewport.gradientStartY(at: q0, fromScreenY: 0,
                frameMinY: 0, frameHeight: 64, plotHeight: 64)
            let b = viewport.gradientStartY(at: q1, fromScreenY: 0,
                frameMinY: 0, frameHeight: 64, plotHeight: 64)
            let sy = 1 + (viewport.scaleY - 1) * (1 - q)
            let actual = HistoryChartViewport.gradientScreenStartY(startPointY: (a + b) / 2,
                frameMinY: 0, frameHeight: 64, scaleY: sy, plotHeight: 64)
            XCTAssertLessThan(abs(actual), 0.25)
        }
    }

    func testAlignedControlsPreserveTheActuallyDisplayedFormerTerminalCubic() throws {
        let old = HistoryChartGeometry(samples: [0, 0, 100],
            timing: .init(sampledAt: [0, 2, 4], referenceTime: 4), ceiling: 200)
        let target = HistoryChartGeometry(samples: [0, 0, 100, 150],
            timing: .init(sampledAt: [0, 2, 4, 6], referenceTime: 6), ceiling: 200)
        let start = try XCTUnwrap(target.alignedStart(from: old, presentedSegments: old.segments,
            fraction: 2.0 / 120, oldCeiling: 200, newCeiling: 200))
        let x = 1 - 3.0 / 120
        XCTAssertEqual(try XCTUnwrap(start.value(at: x)), 31.25 / 200, accuracy: 1e-10)
        XCTAssertEqual(try XCTUnwrap(target.value(at: x)), 41.6666666667 / 200, accuracy: 1e-10)
        XCTAssertEqual(start.segmentIDs, target.segmentIDs)
        for (a, b) in zip(start.segments, target.segments) {
            XCTAssertEqual(a.start, b.start)
            XCTAssertEqual(a.end, b.end)
        }
    }

    func testAlignedControlsPreserveTheTailWhenANewSampleReversesTheSlope() throws {
        let old = HistoryChartGeometry(samples: [0, 0, 100],
            timing: .init(sampledAt: [0, 2, 4], referenceTime: 4), ceiling: 100)
        let target = HistoryChartGeometry(samples: [0, 0, 100, 0],
            timing: .init(sampledAt: [0, 2, 4, 6], referenceTime: 6), ceiling: 100)
        let start = try XCTUnwrap(target.alignedStart(from: old, presentedSegments: old.segments,
            fraction: 2.0 / 120, oldCeiling: 100, newCeiling: 100))
        let x = 1 - 3.0 / 120
        XCTAssertEqual(try XCTUnwrap(start.value(at: x)), 0.3125, accuracy: 1e-10)
        XCTAssertEqual(try XCTUnwrap(target.value(at: x)), 0.5, accuracy: 1e-10)
    }

    func testSeveralDepartingContextPointsKeepTheirRawValuesAndTimestampPairs() {
        let graph = HistoryChartGeometry(samples: [100, 90, 80, 10],
            timing: .init(sampledAt: [0, 2, 4, 6], referenceTime: 124), ceiling: 40,
            leadingContextCount: 3)
        XCTAssertEqual(graph.points.map(\.y), [2.5, 2.25, 2, 0.25])
        XCTAssertEqual(graph.segmentIDs, [
            .init(startTime: 0, endTime: 2), .init(startTime: 2, endTime: 4), .init(startTime: 4, endTime: 6),
        ])
        XCTAssertEqual(graph.points[0].x, -4.0 / 120, accuracy: 1e-12)
    }

    func testRetargetedControlsUseThePresentationBlendRatherThanItsFinalTarget() throws {
        let original = HistoryChartGeometry(samples: [0, 0, 100],
            timing: .init(sampledAt: [0, 2, 4], referenceTime: 4), ceiling: 200)
        let current = HistoryChartGeometry(samples: [0, 0, 100, 150],
            timing: .init(sampledAt: [0, 2, 4, 6], referenceTime: 6), ceiling: 200)
        let currentStart = try XCTUnwrap(current.alignedStart(from: original,
            presentedSegments: original.segments, fraction: 2.0 / 120, oldCeiling: 200, newCeiling: 200))
        let next = HistoryChartGeometry(samples: [0, 0, 100, 150, 200],
            timing: .init(sampledAt: [0, 2, 4, 6, 8], referenceTime: 8), ceiling: 250)
        for progress in [0.25, 0.5, 0.9] {
            let presented = zip(currentStart.segments, current.segments).map { a, b in
                HistoryChartGeometry.Cubic(start: b.start,
                    control1: .init(x: b.control1.x, y: a.control1.y + (b.control1.y - a.control1.y) * progress),
                    control2: .init(x: b.control2.x, y: a.control2.y + (b.control2.y - a.control2.y) * progress),
                    end: b.end)
            }
            let start = try XCTUnwrap(next.alignedStart(from: current, presentedSegments: presented,
                fraction: 2.0 / 120, oldCeiling: 200, newCeiling: 250))
            XCTAssertEqual(start.segments[1].control2.y, presented[1].control2.y * 200 / 250, accuracy: 1e-12)
            XCTAssertNotEqual(start.segments[1].control2.y, current.segments[1].control2.y * 200 / 250)
            XCTAssertEqual(start.segments[1].value(at: 0.5), presented[1].value(at: 0.5) * 200 / 250,
                           accuracy: 1e-12)
        }
    }

    func testOnlyIdenticalRawTimestampPairsAndAnchorsCanSupplyControls() throws {
        let target = HistoryChartGeometry(samples: [0, 0, 100, 150],
            timing: .init(sampledAt: [0, 2, 4, 6], referenceTime: 6), ceiling: 200)
        for old in [
            HistoryChartGeometry(samples: [0, 0, 100],
                timing: .init(sampledAt: [100, 102, 104], referenceTime: 104), ceiling: 200),
            HistoryChartGeometry(samples: [0, 0, 99],
                timing: .init(sampledAt: [0, 2, 4], referenceTime: 4), ceiling: 200),
        ] {
            let start = try XCTUnwrap(target.alignedStart(from: old, presentedSegments: old.segments,
                fraction: 2.0 / 120, oldCeiling: 200, newCeiling: 200))
            XCTAssertEqual(start.segments[1].control2, target.segments[1].control2)
        }
    }

    func testPresentationAnchorRoundingCannotDiscardMatchingRawSegmentControls() throws {
        let old = HistoryChartGeometry(samples: [0, 0, 100],
            timing: .init(sampledAt: [0, 2, 4], referenceTime: 4), ceiling: 200)
        let target = HistoryChartGeometry(samples: [0, 0, 100, 150],
            timing: .init(sampledAt: [0, 2, 4, 6], referenceTime: 6), ceiling: 200)
        let rounded = old.segments.map {
            HistoryChartGeometry.Cubic(start: .init(x: $0.start.x + 1e-7, y: $0.start.y + 1e-7),
                control1: $0.control1, control2: $0.control2,
                end: .init(x: $0.end.x - 1e-7, y: $0.end.y - 1e-7))
        }
        let start = try XCTUnwrap(target.alignedStart(from: old, presentedSegments: rounded,
            fraction: 2.0 / 120, oldCeiling: 200, newCeiling: 200))
        XCTAssertEqual(try XCTUnwrap(start.value(at: 1 - 3.0 / 120)), 31.25 / 200, accuracy: 1e-10)
        XCTAssertEqual(start.segments[1].start, target.segments[1].start)
        XCTAssertEqual(start.segments[1].end, target.segments[1].end)
        for q in [0.0, 0.25, 0.5, 0.9, 1] {
            let blended = target.interpolated(from: start, at: q)
            XCTAssertEqual(blended.segments[1].value(at: 0.5),
                           start.segments[1].value(at: 0.5) * (1 - q) + target.segments[1].value(at: 0.5) * q,
                           accuracy: 1e-12)
            XCTAssertEqual(blended.segments[1].start, target.segments[1].start)
            XCTAssertEqual(blended.segments[1].end, target.segments[1].end)
        }
    }

    func testMatchedControlBlendsRemainInsideEachRawSamplePair() throws {
        var state: UInt64 = 8719
        for _ in 0..<40 {
            let values: [Double] = (0..<20).map { _ in
                state = state &* 6364136223846793005 &+ 1
                return Double((state >> 32) % 10001) / 100
            }
            let old = HistoryChartGeometry(samples: Array(values.dropLast()),
                timing: .init(sampledAt: (0..<19).map { Double($0) * 2 }, referenceTime: 36), ceiling: 100)
            let target = HistoryChartGeometry(samples: values,
                timing: .init(sampledAt: (0..<20).map { Double($0) * 2 }, referenceTime: 38), ceiling: 150)
            let start = try XCTUnwrap(target.alignedStart(from: old, presentedSegments: old.segments,
                fraction: 2.0 / 120, oldCeiling: 100, newCeiling: 150))
            for (a, b) in zip(start.segments, target.segments) {
                for q in stride(from: 0.0, through: 1, by: 0.1) {
                    for t in stride(from: 0.0, through: 1, by: 0.05) {
                        let y = a.value(at: t) * (1 - q) + b.value(at: t) * q
                        XCTAssertGreaterThanOrEqual(y, min(b.start.y, b.end.y) - 1e-12)
                        XCTAssertLessThanOrEqual(y, max(b.start.y, b.end.y) + 1e-12)
                    }
                }
            }
        }
    }

    func testPausedSamplingMovesCachedHistoryToItsActualAge() {
        var now = 0.0
        let history = PowerHistory(clock: { now })
        history.append(10)
        now = 2
        history.append(20)
        let initial = history.chartPresentation
        let count = history.presentationMaterializationCountForTest

        // Degraded sampling still presents history, but adds no new readings.
        now = 119
        let aged = history.chartPresentation
        XCTAssertEqual(aged.samples, initial.samples)
        XCTAssertEqual(aged.timing.sampledAt, initial.timing.sampledAt)
        XCTAssertEqual(aged.timing.referenceTime, now)
        XCTAssertEqual(history.presentationMaterializationCountForTest, count)
        let geometry = HistoryChartGeometry(samples: aged.samples, timing: aged.timing, ceiling: 100)
        XCTAssertEqual(geometry.points.count, 2)
        XCTAssertEqual(geometry.points.last!.x, 3.0 / 120, accuracy: 1e-12)
        XCTAssertNil(HistoryChartTiming.scrollFraction(from: initial.timing, samples: initial.samples,
            to: aged.timing, samples: aged.samples))

        now = 122
        XCTAssertTrue(history.chartPresentation.samples.isEmpty)
    }

    func testHistoryTimingCacheRingAndExpiry() {
        var now = 0.0
        let history = PowerHistory(clock: { now })
        for i in 0..<65 { now = Double(i); history.append(Double(i)) }
        let frame = history.chartPresentation
        XCTAssertEqual(frame.samples, Array(5..<65).map(Double.init))
        XCTAssertEqual(frame.timing.sampledAt, frame.samples)
        XCTAssertEqual(frame.timing.referenceTime, 64)
        let count = history.presentationMaterializationCountForTest
        now = 64.5
        XCTAssertEqual(history.chartPresentation.timing, frame.timing)
        XCTAssertEqual(history.presentationMaterializationCountForTest, count)
        XCTAssertEqual(history.presentation.peak, 64)
        now = 184
        XCTAssertTrue(history.chartPresentation.samples.isEmpty)
        XCTAssertTrue(history.chartPresentation.timing.sampledAt.isEmpty)
        history.reset()
        now = 185
        history.append(3)
        XCTAssertEqual(history.chartPresentation.timing.sampledAt, [185])
    }
}
