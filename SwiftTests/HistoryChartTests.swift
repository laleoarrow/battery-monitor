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
                                           leadingContext: true)
        XCTAssertEqual(normal.points.count, 2)
        XCTAssertEqual(drawing.points.count, 3)
        XCTAssertLessThan(drawing.points[0].x, 0)
        XCTAssertEqual(Array(drawing.points.dropFirst()), normal.points)
        XCTAssertEqual(drawing.points.last, normal.points.last)
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
