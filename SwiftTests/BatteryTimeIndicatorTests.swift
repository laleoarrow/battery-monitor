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

    func testNormalFullPausedAndMixedSupplyStatesNeverReportFailure() {
        for source: BatteryTimeEstimateSource? in [.system, .batteryGauge, nil] {
            for estimate in [BatteryTimeEstimate.full, .notCharging] {
                let snapshot = PowerSnapshot(plugged: true, adapterW: 20, systemW: 20,
                                             batteryTimeEstimate: estimate,
                                             batteryTimeEstimateSource: source)
                XCTAssertEqual(BatteryTimeIndicatorView.status(for: snapshot, degraded: false),
                               source == .system ? .system : .fallback)
            }
            let mixed = PowerSnapshot(plugged: true, adapterW: 20, batteryW: -10, systemW: 30,
                                      batteryTimeEstimate: .notCharging,
                                      batteryTimeEstimateSource: source)
            XCTAssertEqual(BatteryTimeIndicatorView.status(for: mixed, degraded: false),
                           source == .system ? .system : .fallback)
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

    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }

    private func layers(_ layer: CALayer?) -> [CALayer] {
        guard let layer else { return [] }
        return [layer] + (layer.sublayers ?? []).flatMap { layers($0) }
    }
}
