import AppKit
import XCTest
@testable import Wattson

final class BatteryTimeIndicatorTests: XCTestCase {
    func testNumericEstimatesDistinguishSystemAndFallbackSources() {
        for plugged in [false, true] {
            for minutes in [0, 42, 265] {
                for source: BatteryTimeEstimateSource? in [.system, .batteryGauge, .observedDischarge, nil] {
                    let snapshot = PowerSnapshot(
                        plugged: plugged, batteryW: plugged ? 12 : -12,
                        batteryTimeEstimate: plugged ? .charging(minutes) : .remaining(minutes),
                        batteryTimeEstimateSource: source
                    )
                    XCTAssertEqual(BatteryTimeIndicatorView.status(for: snapshot, degraded: false),
                                   source == .system ? .system : .fallback)
                    XCTAssertEqual(BatteryTimeIndicatorView.status(for: snapshot, degraded: true),
                                   .unavailable)
                }
            }
        }
    }

    func testCalculatingTakesPrecedenceOverSourceUntilMinutesAreAvailable() {
        for plugged in [false, true] {
            for source: BatteryTimeEstimateSource? in [.system, .batteryGauge, .observedDischarge, nil] {
                let snapshot = PowerSnapshot(
                    plugged: plugged, batteryW: plugged ? 12 : -12,
                    batteryTimeEstimate: plugged ? .charging(nil) : .remaining(nil),
                    batteryTimeEstimateSource: source
                )
                XCTAssertEqual(BatteryTimeIndicatorView.status(for: snapshot, degraded: false),
                               .calculating)
                XCTAssertEqual(BatteryTimeIndicatorView.status(for: snapshot, degraded: true),
                               .unavailable)
            }
        }
    }

    func testFullHasItsOwnStateWhilePausedAndMixedSupplyKeepSourceSemantics() {
        for source: BatteryTimeEstimateSource? in [.system, .batteryGauge, .observedDischarge, nil] {
            for estimate in [BatteryTimeEstimate.full, .notCharging] {
                let snapshot = PowerSnapshot(plugged: true, adapterW: 20, systemW: 20,
                                             batteryTimeEstimate: estimate,
                                             batteryTimeEstimateSource: source)
                XCTAssertEqual(BatteryTimeIndicatorView.status(for: snapshot, degraded: false),
                               estimate == .full ? .full : (source == .system ? .system : .fallback))
                XCTAssertEqual(BatteryTimeIndicatorView.status(for: snapshot, degraded: true),
                               .unavailable)
            }
            for estimate in [BatteryTimeEstimate.full, .notCharging] {
                let mixed = PowerSnapshot(plugged: true, adapterW: 20, batteryW: -10, systemW: 30,
                                          batteryTimeEstimate: estimate,
                                          batteryTimeEstimateSource: source)
                XCTAssertEqual(BatteryTimeIndicatorView.status(for: mixed, degraded: false),
                               source == .system ? .system : .fallback,
                               "Mixed supply cannot show full-charge motion even with a stale full estimate")
            }
        }
        XCTAssertEqual(BatteryTimeIndicatorView.status(
            for: PowerSnapshot(plugged: true, adapterW: 20, batteryW: -10, systemW: 30),
            degraded: false), .fallback)
    }

    func testMissingInvalidAndWrongDirectionReadingsCannotShowAHealthySource() {
        for plugged in [false, true] {
            let invalid: [BatteryTimeEstimate?] = plugged
                ? [nil, .charging(-1), .remaining(20), .remaining(nil)]
                : [nil, .remaining(-1), .charging(20), .charging(nil), .full, .notCharging]
            for estimate in invalid {
                let snapshot = PowerSnapshot(plugged: plugged, batteryW: plugged ? 12 : -12,
                                             batteryTimeEstimate: estimate,
                                             batteryTimeEstimateSource: .system)
                XCTAssertEqual(BatteryTimeIndicatorView.status(for: snapshot, degraded: false),
                               .unavailable)
            }
        }
    }

    func testRuntimeIndicatorUpdatesInPlaceAndExplainsStateWithoutMotion() throws {
        let runtime = PopoverRuntimeView()
        let indicator = try XCTUnwrap(descendants(runtime).compactMap { $0 as? BatteryTimeIndicatorView }.first)
        let sequence: [(BatteryTimeEstimate?, BatteryTimeEstimateSource?, BatteryTimeIndicatorView.Status)] = [
            (.remaining(150), .system, .system),
            (.remaining(150), .batteryGauge, .fallback),
            (.remaining(150), .observedDischarge, .fallback),
            (.remaining(nil), .system, .calculating),
            (nil, nil, .unavailable),
            (.remaining(150), .system, .system),
        ]
        for (estimate, source, status) in sequence {
            let snapshot = PowerSnapshot(batteryW: -12, systemW: 12,
                                         batteryTimeEstimate: estimate, batteryTimeEstimateSource: source)
            runtime.update(snapshot: snapshot, degraded: false)
            runtime.layoutSubtreeIfNeeded()
            XCTAssertEqual(indicator.status, status)
            XCTAssertTrue(descendants(runtime).contains { $0 === indicator })
            XCTAssertTrue(runtime.bounds.contains(indicator.frame))
            XCTAssertFalse(try XCTUnwrap(indicator.toolTip).isEmpty)
            XCTAssertEqual(indicator.accessibilityHelp(), indicator.toolTip)
            XCTAssertTrue(layers(indicator.layer).allSatisfy { ($0.animationKeys() ?? []).isEmpty },
                          "An unattached indicator must not start background animation")
        }
        runtime.update(snapshot: PowerSnapshot(batteryTimeEstimate: .remaining(150),
                                              batteryTimeEstimateSource: .system), degraded: true)
        XCTAssertEqual(indicator.status, .unavailable)
        runtime.update(snapshot: PowerSnapshot(plugged: true, batteryTimeEstimate: .full,
                                              batteryTimeEstimateSource: .system), degraded: false)
        XCTAssertEqual(indicator.status, .full)
        XCTAssertTrue(descendants(runtime).contains { $0 === indicator })
        XCTAssertTrue((indicator.accessibilityValue() as? String ?? "").localizedCaseInsensitiveContains("full"))
        XCTAssertTrue(layers(indicator.layer).allSatisfy { ($0.animationKeys() ?? []).isEmpty })
    }

    func testPlanetResolvesItsOwnAppearanceAndFailureColorWithoutMoving() throws {
        let indicator = BatteryTimeIndicatorView()
        let snapshot = PowerSnapshot(plugged: true, batteryW: 12,
                                     batteryTimeEstimate: .charging(42), batteryTimeEstimateSource: .system)
        indicator.update(snapshot: snapshot, degraded: false)
        indicator.layoutSubtreeIfNeeded()
        let planet = try XCTUnwrap(layers(indicator.layer).compactMap { $0 as? CAGradientLayer }
            .first { $0.name == "planet" })
        let frame = planet.frame
        var palettes: [[CGColor]] = []
        for name: NSAppearance.Name in [.aqua, .darkAqua, .aqua] {
            indicator.appearance = try XCTUnwrap(NSAppearance(named: name))
            indicator.viewDidChangeEffectiveAppearance()
            palettes.append(try XCTUnwrap(planet.colors as? [CGColor]))
            XCTAssertEqual(planet.frame, frame)
            XCTAssertEqual(indicator.status, .system)
        }
        XCTAssertNotEqual(palettes[0], palettes[1])
        XCTAssertEqual(palettes[0], palettes[2])
        indicator.update(snapshot: snapshot, degraded: true)
        let failureColors = try XCTUnwrap(planet.colors as? [CGColor])
        XCTAssertNotEqual(failureColors, palettes[2])
        XCTAssertTrue(failureColors.contains { value in
            guard let color = NSColor(cgColor: value)?.usingColorSpace(.sRGB) else { return false }
            return color.redComponent > color.greenComponent && color.redComponent > color.blueComponent
        })
    }

    func testPlanetUsesTheSameStatePaletteAsTheOtherInstruments() throws {
        let indicator = BatteryTimeIndicatorView()
        let cases: [(PowerSnapshot, NSColor)] = [
            (PowerSnapshot(batteryW: -12, batteryTimeEstimate: .remaining(42),
                           batteryTimeEstimateSource: .system), PopoverStyle.neutral),
            (PowerSnapshot(plugged: true, batteryW: 12, batteryTimeEstimate: .charging(42),
                           batteryTimeEstimateSource: .system), PopoverStyle.green),
            (PowerSnapshot(plugged: true, batteryTimeEstimate: .full,
                           batteryTimeEstimateSource: .system), PopoverStyle.blue),
            (PowerSnapshot(plugged: true, batteryW: -12, batteryTimeEstimate: .notCharging,
                           batteryTimeEstimateSource: .system), PopoverStyle.blue),
        ]
        let planet = try XCTUnwrap(layers(indicator.layer).compactMap { $0 as? CAGradientLayer }
            .first { $0.name == "planet" })
        for name: NSAppearance.Name in [.aqua, .darkAqua] {
            indicator.appearance = try XCTUnwrap(NSAppearance(named: name))
            for (snapshot, expected) in cases {
                indicator.update(snapshot: snapshot, degraded: false)
                let colors = try XCTUnwrap(planet.colors as? [CGColor])
                var resolved: CGColor?
                indicator.effectiveAppearance.performAsCurrentDrawingAppearance {
                    resolved = expected.usingColorSpace(.sRGB)?.cgColor
                }
                XCTAssertEqual(colors[1], try XCTUnwrap(resolved))
            }
        }
    }

    func testFullOrbitsCrossInFrontOfAndBehindTheOpaquePlanet() {
        var windings: [Double] = []
        for orbit in 0..<2 {
            let period = FullChargeOrbitGeometry.periods[orbit]
            let samples = (0...1200).map {
                FullChargeOrbitGeometry.sample(orbit: orbit, time: period * Double($0) / 1200)
            }
            let radius = FullChargeOrbitGeometry.planetRadius
            XCTAssertTrue(samples.contains { hypot($0.point.x, $0.point.y) < radius && $0.depth > radius },
                          "Each star must pass across the front face, not merely around its perimeter")
            XCTAssertTrue(samples.contains { hypot($0.point.x, $0.point.y) < radius && $0.depth < -radius },
                          "Each star must also travel behind the opaque planet")
            for sample in samples {
                let projectedRadius = hypot(sample.point.x, sample.point.y)
                let radius3D = hypot(projectedRadius / sample.scale, sample.depth)
                XCTAssertEqual(radius3D, orbit == 0 ? 8.4 : 7.4, accuracy: 0.000_001)
                XCTAssertGreaterThan(sample.scale, 0)
                XCTAssertLessThan(projectedRadius, 10)
            }
            let angles = samples.map { atan2(Double($0.point.y), Double($0.point.x)) }
            let winding = zip(angles, angles.dropFirst()).reduce(0.0) { sum, pair in
                var delta = pair.1 - pair.0
                if delta > .pi { delta -= 2 * .pi }
                if delta < -.pi { delta += 2 * .pi }
                return sum + delta
            }
            XCTAssertEqual(abs(winding), 2 * .pi, accuracy: 0.000_001)
            windings.append(winding)
        }
        XCTAssertLessThan(windings[0] * windings[1], 0, "The two stars travel in opposite directions")
        XCTAssertNotEqual(FullChargeOrbitGeometry.periods[0], FullChargeOrbitGeometry.periods[1])
    }

    func testFullOrbitLoopsJoinWithoutPositionOrSpeedJumps() {
        for orbit in 0..<2 {
            let period = FullChargeOrbitGeometry.periods[orbit]
            let first = FullChargeOrbitGeometry.sample(orbit: orbit, time: 0)
            let last = FullChargeOrbitGeometry.sample(orbit: orbit, time: period)
            XCTAssertEqual(first.point.x, last.point.x, accuracy: 0.000_001)
            XCTAssertEqual(first.point.y, last.point.y, accuracy: 0.000_001)
            XCTAssertEqual(first.depth, last.depth, accuracy: 0.000_001)
            XCTAssertEqual(first.scale, last.scale, accuracy: 0.000_001)
            let step = 0.001
            let before = FullChargeOrbitGeometry.sample(orbit: orbit, time: period - step)
            let after = FullChargeOrbitGeometry.sample(orbit: orbit, time: step)
            XCTAssertEqual((last.point.x - before.point.x) / step,
                           (after.point.x - first.point.x) / step, accuracy: 0.02)
            XCTAssertEqual((last.point.y - before.point.y) / step,
                           (after.point.y - first.point.y) / step, accuracy: 0.02)
            XCTAssertEqual((last.depth - before.depth) / step,
                           (after.depth - first.depth) / step, accuracy: 0.02)
        }
    }

    func testFullTrailsFollowHistoricalMotionOnTheCorrectSideOfThePlanet() {
        for orbit in 0..<2 {
            let period = FullChargeOrbitGeometry.periods[orbit]
            for fraction in [0.0, 0.25, 0.5, 0.75] {
                let time = period * fraction
                let middle = FullChargeOrbitGeometry.sample(
                    orbit: orbit, time: time - FullChargeOrbitGeometry.tailDuration / 2)
                let front = FullChargeOrbitGeometry.trailPath(orbit: orbit, time: time, front: true)
                let back = FullChargeOrbitGeometry.trailPath(orbit: orbit, time: time, front: false)
                let visibleSide = middle.depth >= 0 ? front : back
                let otherSide = middle.depth >= 0 ? back : front
                XCTAssertTrue(visibleSide.contains(middle.point),
                              "The continuous ribbon must cover its historical centerline")
                XCTAssertFalse(otherSide.contains(middle.point),
                               "A historical point must not leak into the opposite depth layer")
            }
            for front in [false, true] {
                let first = pathPoints(FullChargeOrbitGeometry.trailPath(orbit: orbit, time: 0, front: front))
                let last = pathPoints(FullChargeOrbitGeometry.trailPath(orbit: orbit, time: period, front: front))
                XCTAssertEqual(first.count, last.count)
                for (a, b) in zip(first, last) {
                    XCTAssertEqual(a.x, b.x, accuracy: 0.000_001)
                    XCTAssertEqual(a.y, b.y, accuracy: 0.000_001)
                }
            }
        }
    }

    func testFullOrbitStarsTrailsAndRingsFollowEverySuppliedThemeColor() throws {
        let host = CALayer()
        let orbit = FullChargeOrbit(host: host)
        orbit.layout(in: CGRect(x: 0, y: 0, width: 20, height: 20))
        orbit.setVisible(true)
        let themes = [
            NSColor(srgbRed: 0.1, green: 0.7, blue: 0.25, alpha: 1),
            NSColor(srgbRed: 1, green: 0.6, blue: 0.1, alpha: 1),
            NSColor(srgbRed: 0.65, green: 0.3, blue: 0.9, alpha: 1),
            NSColor(srgbRed: 0.55, green: 0.55, blue: 0.55, alpha: 1),
        ]
        func paintColors() -> [CGColor] {
            (host.sublayers ?? []).flatMap { layer -> [CGColor] in
                if let gradient = layer as? CAGradientLayer {
                    return (gradient.colors as? [CGColor] ?? [])
                        + (gradient.sublayers ?? []).compactMap { $0.backgroundColor }
                }
                if let shape = layer as? CAShapeLayer, let color = shape.strokeColor { return [color] }
                return []
            }
        }
        var previous: [CGColor]?
        for theme in themes {
            orbit.updateColors(base: theme, highContrast: false, reduceTransparency: false)
            let colors = paintColors()
            XCTAssertFalse(colors.isEmpty)
            if let previous {
                XCTAssertEqual(previous.count, colors.count)
                XCTAssertTrue(zip(previous, colors).allSatisfy { $0 != $1 },
                              "Every painted star, ring and trail must change with the supplied theme")
            }
            let reference = [theme.redComponent, theme.greenComponent, theme.blueComponent]
            for value in colors {
                let resolved = try XCTUnwrap(NSColor(cgColor: value)?.usingColorSpace(.sRGB))
                let channels = [resolved.redComponent, resolved.greenComponent, resolved.blueComponent]
                for a in 0..<3 {
                    for b in (a + 1)..<3 {
                        if reference[a] == reference[b] {
                            XCTAssertEqual(channels[a], channels[b], accuracy: 0.000_001)
                        } else {
                            XCTAssertGreaterThan((channels[a] - channels[b]) * (reference[a] - reference[b]), 0)
                        }
                    }
                }
            }
            previous = colors
        }
        orbit.updateColors(base: themes[0], highContrast: true, reduceTransparency: true)
        let heads = (host.sublayers ?? []).filter { $0.name?.hasSuffix("-head") == true }
        XCTAssertEqual(heads.count, 2)
        XCTAssertTrue(heads.allSatisfy { head in
            guard let core = head.sublayers?.first?.backgroundColor else { return false }
            return core.alpha == 1
        }, "Reducing transparency keeps both solid star cores visible")
    }

    private func pathPoints(_ path: CGPath) -> [CGPoint] {
        var result: [CGPoint] = []
        path.applyWithBlock { pointer in
            let element = pointer.pointee
            let count: Int
            switch element.type {
            case .moveToPoint, .addLineToPoint: count = 1
            case .addQuadCurveToPoint: count = 2
            case .addCurveToPoint: count = 3
            case .closeSubpath: count = 0
            @unknown default: count = 0
            }
            result.append(contentsOf: (0..<count).map { element.points[$0] })
        }
        return result
    }

    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }

    private func layers(_ layer: CALayer?) -> [CALayer] {
        guard let layer else { return [] }
        return [layer] + (layer.sublayers ?? []).flatMap { layers($0) } + layers(layer.mask)
    }
}
