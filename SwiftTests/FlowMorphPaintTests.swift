import AppKit
import XCTest
@testable import Wattson

final class FlowMorphPaintTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 328, height: 224)
    private let positions: [CGFloat] = [0, 0.10, 0.13, 0.18, 0.21, 0.25, 0.29, 0.32, 0.40, 0.42,
                                        0.50, 0.60, 0.63, 0.68, 0.71, 0.75, 0.79, 0.82, 0.90, 0.92, 1]

    // Preserve the pre-sharing per-pipe calculation as the equivalence oracle.
    private func legacyColors(color: NSColor, themeMix: CGFloat) -> [CGColor] {
        let ordinaryLocations: [CGFloat] = [0, 0.13, 0.21, 0.29, 0.42, 0.50, 0.63, 0.71, 0.79, 0.92, 1]
        let ordinaryAlpha: [CGFloat] = [0, 0.30, 1, 0.30, 0, 0, 0.30, 1, 0.30, 0, 0]
        let mixedLocations: [CGFloat] = [0, 0.10, 0.18, 0.25, 0.32, 0.40, 0.50, 0.60, 0.68, 0.75, 0.82, 0.90, 1]
        let mixedAlpha: [CGFloat] = [0, 0.25, 0.66, 1, 0.66, 0.25, 0, 0.25, 0.66, 1, 0.66, 0.25, 0]
        func alpha(at value: CGFloat, locations: [CGFloat], values: [CGFloat]) -> CGFloat {
            guard let right = locations.firstIndex(where: { $0 >= value }), right > 0 else { return values[0] }
            let fraction = (value - locations[right - 1]) / (locations[right] - locations[right - 1])
            return values[right - 1] + (values[right] - values[right - 1]) * fraction
        }
        let mix = min(1, max(0, themeMix))
        return positions.map { location in
            let old = alpha(at: location, locations: ordinaryLocations, values: ordinaryAlpha)
            let new = alpha(at: location, locations: mixedLocations, values: mixedAlpha)
            return color.withAlphaComponent(old + (new - old) * mix).cgColor
        }
    }

    private func assertColors(_ actual: [Any]?, equalTo expected: [CGColor],
                              file: StaticString = #filePath, line: UInt = #line) {
        guard let colors = actual as? [CGColor] else {
            XCTFail("Expected resolved CGColors", file: file, line: line)
            return
        }
        XCTAssertEqual(colors.count, expected.count, file: file, line: line)
        for (actual, expected) in zip(colors, expected) {
            XCTAssertEqual(actual.colorSpace, expected.colorSpace, file: file, line: line)
            XCTAssertEqual(actual.components, expected.components, file: file, line: line)
        }
    }

    func testAllStopsExactlyMatchLegacyProfilesInBothAppearances() throws {
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = try XCTUnwrap(NSAppearance(named: name))
            appearance.performAsCurrentDrawingAppearance {
                let blended = PopoverStyle.neutral.blended(withFraction: 0.375, of: PopoverStyle.blue)!
                for color in [PopoverStyle.blue, PopoverStyle.green, PopoverStyle.neutral, PopoverStyle.red, blended] {
                    for mix: CGFloat in [-1, 0, 0.5, 1, 2] {
                        let paint = FlowMorphPaint(color: color, themeMix: mix)
                        self.assertColors(paint.colors, equalTo: self.legacyColors(color: color, themeMix: mix))
                        XCTAssertEqual(FlowMorphPaint.locations, self.positions.map { NSNumber(value: Double($0)) })
                    }
                }
            }
        }
    }

    func testNewPaintResolvesCurrentAppearanceWithoutChangingEarlierPaint() throws {
        let light = try XCTUnwrap(NSAppearance(named: .aqua))
        let dark = try XCTUnwrap(NSAppearance(named: .darkAqua))
        var lightPaint: FlowMorphPaint!
        var darkPaint: FlowMorphPaint!
        var lightColors: [CGColor] = []
        light.performAsCurrentDrawingAppearance {
            lightPaint = FlowMorphPaint(color: PopoverStyle.blue, themeMix: 0.5)
            lightColors = self.legacyColors(color: PopoverStyle.blue, themeMix: 0.5)
        }
        dark.performAsCurrentDrawingAppearance {
            darkPaint = FlowMorphPaint(color: PopoverStyle.blue, themeMix: 0.5)
            self.assertColors(darkPaint.colors, equalTo: self.legacyColors(color: PopoverStyle.blue, themeMix: 0.5))
        }
        assertColors(lightPaint.colors, equalTo: lightColors)
        let darkColors = try XCTUnwrap(darkPaint.colors as? [CGColor])
        XCTAssertNotEqual(lightColors[5].components, darkColors[5].components)
    }

    func testSharedPaintUpdatesCollapsedEdgesWithoutChangingTheirClocks() throws {
        let pipes = FlowEdgeRole.allCases.map { _ in PipeBundle() }
        defer { pipes.forEach { $0.stopFlow() } }
        let curve = PipeGeometry(start: .zero, control1: CGPoint(x: 30, y: 0),
                                 control2: CGPoint(x: 70, y: 0), end: CGPoint(x: 100, y: 0))
        let collapsed = PipeGeometry(start: .zero, control1: .zero, control2: .zero, end: .zero)
        let now = CACurrentMediaTime()
        for pipe in pipes {
            pipe.startFlow(multiplier: 1.75, width: bounds.width,
                           sharedPhase: (time: now - 0.1, offset: 0.6))
        }
        let gradients = try pipes.map { pipe in
            try XCTUnwrap(pipe.geometryLayersForTest.compactMap { $0 as? CAGradientLayer }.first)
        }
        let clocks = gradients.map { ($0.beginTime, $0.timeOffset, $0.speed) }
        let motions = try gradients.map { try XCTUnwrap($0.animation(forKey: "flow") as? CABasicAnimation) }
        for mix: CGFloat in [0, 0.5, 1] {
            let builds = FlowMorphPaint.buildsForTest
            let paint = FlowMorphPaint(color: PopoverStyle.blue, themeMix: mix)
            for (index, pipe) in pipes.enumerated() {
                pipe.applyMorphPose(pose: FlowEdgePose(geometry: index == 0 ? collapsed : curve,
                    startWidth: 12, endWidth: 12, verticalTaper: mix), paint: paint, bounds: bounds)
            }
            XCTAssertEqual(FlowMorphPaint.buildsForTest, builds + 1)
            XCTAssertEqual(pipes[0].container.opacity, 0)
            for index in gradients.indices {
                let gradient = gradients[index]
                assertColors(gradient.colors, equalTo: legacyColors(color: PopoverStyle.blue, themeMix: mix))
                XCTAssertEqual(gradient.locations, FlowMorphPaint.locations)
                XCTAssertEqual(gradient.beginTime, clocks[index].0)
                XCTAssertEqual(gradient.timeOffset, clocks[index].1)
                XCTAssertEqual(gradient.speed, clocks[index].2)
                let motion = try XCTUnwrap(gradient.animation(forKey: "flow") as? CABasicAnimation)
                XCTAssertEqual(motion.beginTime, motions[index].beginTime)
                XCTAssertEqual(motion.timeOffset, motions[index].timeOffset)
                XCTAssertEqual(motion.duration, motions[index].duration)
            }
        }
    }

    func testRenderMorphBuildsOnePaintPerTickInItsEffectiveAppearance() throws {
        _ = NSApplication.shared
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = try XCTUnwrap(NSAppearance(named: name))
            let otherAppearance = try XCTUnwrap(NSAppearance(named: name == .aqua ? .darkAqua : .aqua))
            let flow = PowerFlowView()
            flow.frame = bounds
            flow.appearance = appearance
            let window = NSWindow(contentRect: bounds, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = flow
            defer {
                flow.setAnimationsEnabled(false)
                window.contentView = nil
            }
            flow.layoutSubtreeIfNeeded()
            flow.update(snapshot: PowerSnapshot(percent: 70, batteryW: -39.7, systemW: 39.7), animated: false)
            flow.setAnimationsEnabled(true)
            let builds = FlowMorphPaint.buildsForTest
            flow.update(snapshot: PowerSnapshot(percent: 70, plugged: true, adapterW: 30,
                batteryW: -9.7, systemW: 39.7, deviceOutputW: 12.2), animated: true)
            XCTAssertEqual(FlowMorphPaint.buildsForTest, builds + 1)
            XCTAssertEqual(flow.transitionDurationForTest, 0.32)
            for progress: CGFloat in [0.05, 0.5, 0.85, 0.95] {
                let beforeTick = FlowMorphPaint.buildsForTest
                otherAppearance.performAsCurrentDrawingAppearance {
                    flow.advanceTransitionForTest(progress: progress)
                }
                XCTAssertEqual(FlowMorphPaint.buildsForTest, beforeTick + 1)
                let gradients = flow.pipeGeometryLayersForTest.compactMap { $0 as? CAGradientLayer }
                XCTAssertEqual(gradients.count, 5)
                appearance.performAsCurrentDrawingAppearance {
                    let eased = progress * progress * (3 - 2 * progress)
                    let color = PopoverStyle.neutral.blended(withFraction: eased, of: PopoverStyle.blue)!
                    let expected = self.legacyColors(color: color, themeMix: eased)
                    gradients.forEach { self.assertColors($0.colors, equalTo: expected) }
                }
            }
            let beforeHandoff = FlowMorphPaint.buildsForTest
            flow.advanceTransitionForTest(progress: 1)
            XCTAssertEqual(FlowMorphPaint.buildsForTest, beforeHandoff)
            XCTAssertFalse(flow.transitionIsAnimatingForTest)
        }
    }
}
