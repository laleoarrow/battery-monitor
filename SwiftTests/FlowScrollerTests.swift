import AppKit
import XCTest
@testable import Wattson

final class FlowScrollerTests: XCTestCase {
    func testKnobArtTracksNativeMetricsAndStaysInsideItsClip() throws {
        let scroller = makeScroller()
        let capsule = try XCTUnwrap(scroller.layer?.sublayers?.first { $0.name == "flow-knob" })
        XCTAssertTrue(capsule.masksToBounds)
        XCTAssertTrue(scroller.layer?.masksToBounds == true)
        for proportion: CGFloat in [0.08, 0.3, 0.8] {
            scroller.knobProportion = proportion
            for value in [0.0, 0.24, 0.7, 1.0] {
                scroller.doubleValue = value
                let native = scroller.rect(for: .knob)
                XCTAssertFalse(native.isEmpty)
                XCTAssertFalse(capsule.isHidden)
                XCTAssertEqual(capsule.frame.width, 6)
                XCTAssertEqual(capsule.frame.midX, native.midX)
                XCTAssertEqual(capsule.frame.minY, native.minY)
                XCTAssertEqual(capsule.frame.height, native.height)
                XCTAssertTrue(scroller.bounds.contains(capsule.frame))
            }
        }
        scroller.knobProportion = 1
        XCTAssertTrue(capsule.isHidden, "A complete document has no position indicator")
    }

    func testFlowUsesExistingStatePaletteAndRefreshesAppearanceWithoutMoving() throws {
        let scroller = makeScroller()
        let capsule = try XCTUnwrap(scroller.layer?.sublayers?.compactMap { $0 as? CAGradientLayer }.first)
        let frame = capsule.frame
        var colors: [[CGColor]] = []
        for name: NSAppearance.Name in [.aqua, .darkAqua, .aqua] {
            scroller.appearance = try XCTUnwrap(NSAppearance(named: name))
            scroller.update(snapshot: PowerSnapshot(plugged: true, batteryW: 12))
            colors.append(try XCTUnwrap(capsule.colors as? [CGColor]))
            XCTAssertEqual(capsule.frame, frame)
            scroller.effectiveAppearance.performAsCurrentDrawingAppearance {
                XCTAssertEqual(colors.last?[1], PopoverStyle.green.usingColorSpace(.sRGB)?.cgColor)
            }
        }
        XCTAssertNotEqual(colors[0], colors[1])
        XCTAssertEqual(colors[0], colors[2])
        for (snapshot, expected) in [
            (PowerSnapshot(plugged: true, adapterW: 20, systemW: 20), PopoverStyle.blue),
            (PowerSnapshot(batteryW: -12, systemW: 12), PopoverStyle.neutral),
            (PowerSnapshot(plugged: true, adapterW: 20, batteryW: -10, systemW: 30), PopoverStyle.blue),
        ] {
            scroller.update(snapshot: snapshot)
            scroller.effectiveAppearance.performAsCurrentDrawingAppearance {
                XCTAssertEqual((capsule.colors as? [CGColor])?[1], expected.usingColorSpace(.sRGB)?.cgColor)
            }
        }
    }

    func testAnimationGroupsHaveUnevenSpacingAndOnlyInvisibleReturnJumps() throws {
        for flipped in [false, true] {
            let groups = (0..<5).map { FlowScroller.flowAnimation(height: 100, flipped: flipped, pointIndex: $0) }
            let offsets = groups.map { $0.timeOffset / $0.duration }.sorted()
            let gaps = zip(offsets, offsets.dropFirst()).map { $1 - $0 }
                + [1 + offsets[0] - offsets[4]]
            XCTAssertGreaterThan(try XCTUnwrap(gaps.max()) - XCTUnwrap(gaps.min()), 0.15)
            var resets = 0
            for group in groups {
                XCTAssertEqual(group.duration, 3.4)
                XCTAssertEqual(group.repeatCount, .infinity)
                let movement = try XCTUnwrap(group.animations?.compactMap { $0 as? CABasicAnimation }
                    .first { $0.keyPath == "position.y" })
                let fade = try XCTUnwrap(group.animations?.compactMap { $0 as? CAKeyframeAnimation }
                    .first { $0.keyPath == "opacity" })
                let from = try XCTUnwrap(movement.fromValue as? Double)
                let to = try XCTUnwrap(movement.toValue as? Double)
                XCTAssertEqual(flipped ? to - from : from - to, 100)
                XCTAssertEqual(movement.duration, group.duration)
                XCTAssertEqual(fade.duration, group.duration)
                let times = try XCTUnwrap(fade.keyTimes).map(\.doubleValue)
                let values = try XCTUnwrap(fade.values as? [NSNumber]).map(\.doubleValue)
                func alpha(_ phase: Double) -> Double {
                    let index = (1..<times.count).first { phase <= times[$0] } ?? times.count - 1
                    let fraction = (phase - times[index - 1]) / (times[index] - times[index - 1])
                    return values[index - 1] + fraction * (values[index] - values[index - 1])
                }
                var previous = 0.0
                for step in 0...520 {
                    let time = Double(step) / 100 + group.timeOffset
                    let phase = time.truncatingRemainder(dividingBy: group.duration) / group.duration
                    if step > 0 && phase < previous {
                        resets += 1
                        XCTAssertEqual(alpha(previous), 0, accuracy: 0.001)
                        XCTAssertEqual(alpha(phase), 0, accuracy: 0.001)
                    }
                    previous = phase
                }
            }
            XCTAssertGreaterThanOrEqual(resets, 5)
        }
    }

    func testDetachedOrHiddenScrollerDoesNotRunAnimations() throws {
        let scroller = makeScroller()
        scroller.setAnimationsEnabled(true)
        scroller.setPresentationActive(true)
        let capsule = try XCTUnwrap(scroller.layer?.sublayers?.first { $0.name == "flow-knob" })
        let points = try XCTUnwrap(capsule.sublayers)
        XCTAssertEqual(points.count, 5)
        XCTAssertTrue(points.allSatisfy { ($0.animationKeys() ?? []).isEmpty })
        scroller.isHidden = true
        scroller.synchronizeKnob()
        XCTAssertTrue(points.allSatisfy { ($0.animationKeys() ?? []).isEmpty })
        scroller.isHidden = false
        scroller.setPresentationActive(false)
        XCTAssertTrue(points.allSatisfy { ($0.animationKeys() ?? []).isEmpty })
    }

    private func makeScroller() -> FlowScroller {
        _ = NSApplication.shared
        let width = NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
        let scroller = FlowScroller(frame: NSRect(x: 0, y: 0, width: width, height: 300))
        scroller.scrollerStyle = .legacy
        scroller.isEnabled = true
        scroller.knobProportion = 0.3
        scroller.doubleValue = 0
        scroller.layoutSubtreeIfNeeded()
        scroller.synchronizeKnob()
        return scroller
    }
}
