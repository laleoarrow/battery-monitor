import AppKit
import XCTest
@testable import Wattson

final class BatteryIcon27Tests: XCTestCase {
    private let appearance = NSAppearance(named: .darkAqua)!

    private func key(
        _ snapshot: PowerSnapshot,
        style: Settings.MenuBarIconStyle = .native27,
        showsPercentage: Bool = true,
        mode: EnergyMode = .auto,
        pressed: Bool = false
    ) -> BatteryIcon.RenderKey {
        BatteryIcon.renderKey(
            for: snapshot, mode: mode, pressed: pressed, style: style,
            showsPercentage: showsPercentage,
            appearance: appearance, increasedContrast: false
        )
    }

    private func pixels(
        _ snapshot: PowerSnapshot,
        style: Settings.MenuBarIconStyle = .native27,
        showsPercentage: Bool = true,
        mode: EnergyMode = .auto,
        pressed: Bool = false
    ) throws -> Data {
        try XCTUnwrap(BatteryIcon.image(
            for: snapshot, mode: mode, pressed: pressed, style: style,
            showsPercentage: showsPercentage
        ).tiffRepresentation)
    }

    func testChargingUsesBoltAndEveryOtherConnectedStateUsesPlug() {
        XCTAssertEqual(BatteryIcon27.adornment(for: PowerSnapshot(
            percent: 40, plugged: true, batteryW: 10
        )), .bolt)
        for watts in [0.0, -10.0, PowerSnapshot.epsilon] {
            XCTAssertEqual(BatteryIcon27.adornment(for: PowerSnapshot(
                percent: 100, plugged: true, batteryW: watts
            )), .plug)
        }
        XCTAssertEqual(BatteryIcon27.adornment(for: PowerSnapshot(
            percent: 40, plugged: false, batteryW: 10
        )), .none)
    }

    func testReportedChargingStateControlsAdornmentAndWattsonTint() {
        let cases: [(Double, BatteryTimeEstimate, BatteryTimeEstimateSource?, Bool)] = [
            (0, .charging(nil), .system, true),
            (0.1, .charging(12), .system, true),
            (0, .charging(12), .batteryGauge, true),
            (10, .full, .system, false),
            (10, .notCharging, .system, false),
            (-10, .charging(12), .system, false),
            (0, .charging(12), nil, false),
            (0, .charging(12), .observedDischarge, false),
        ]
        for (watts, estimate, source, charging) in cases {
            let snapshot = PowerSnapshot(
                percent: 80, plugged: true, batteryW: watts,
                batteryTimeEstimate: estimate, batteryTimeEstimateSource: source
            )
            XCTAssertEqual(BatteryIcon27.adornment(for: snapshot), charging ? .bolt : .plug)
            XCTAssertEqual(key(snapshot).showsBolt, charging)
            XCTAssertEqual(key(snapshot, style: .wattson).tintRole, charging ? .charging : .template)
            XCTAssertEqual(key(snapshot, style: .wattson, mode: .low).tintRole, .lowPower)
            XCTAssertEqual(key(snapshot, style: .wattson, pressed: true).tintRole, .template)
            // The macOS 26 artwork uses its bolt for every connected state.
            XCTAssertTrue(key(snapshot, style: .native).showsBolt)
        }
    }

    func testReportedChargingChangesInvalidateGlyphAndTintWithoutWattChanges() throws {
        let charging = PowerSnapshot(
            percent: 80, plugged: true, batteryW: 0,
            batteryTimeEstimate: .charging(nil), batteryTimeEstimateSource: .system
        )
        var paused = charging
        paused.batteryTimeEstimate = .notCharging
        for style in [Settings.MenuBarIconStyle.native27, .wattson] {
            XCTAssertNotEqual(key(charging, style: style), key(paused, style: style))
            XCTAssertNotEqual(try pixels(charging, style: style), try pixels(paused, style: style))
        }
        XCTAssertEqual(key(charging, style: .native), key(paused, style: .native))
    }

    func testBoundaryPercentagesUseOneFixedResolutionIndependentCanvas() throws {
        for percent in [0, 1, 99, 100] {
            for plugged in [false, true] {
                for showsPercentage in [false, true] {
                    let image = BatteryIcon.image(
                        for: PowerSnapshot(percent: percent, plugged: plugged, batteryW: 5),
                        mode: .auto, pressed: false, style: .native27,
                        showsPercentage: showsPercentage
                    )
                    XCTAssertEqual(image.size, NSSize(width: 25, height: 16))
                    XCTAssertTrue(image.isTemplate)
                    let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
                    XCTAssertGreaterThan(bitmap.pixelsWide, 0)
                    XCTAssertGreaterThan(bitmap.pixelsHigh, 0)
                }
            }
        }
    }

    func testOutOfRangePercentClampsBothRenderingAndCacheKey() throws {
        for (outside, boundary) in [(-1, 0), (101, 100), (Int.min, 0), (Int.max, 100)] {
            let invalid = PowerSnapshot(percent: outside, plugged: true, batteryW: 1)
            let valid = PowerSnapshot(percent: boundary, plugged: true, batteryW: 1)
            XCTAssertEqual(key(invalid), key(valid))
            XCTAssertEqual(try pixels(invalid), try pixels(valid))
        }
    }

    func testOnlyInsetPercentageChangesGlyphCacheWhenPercentageToggles() throws {
        let snapshot = PowerSnapshot(percent: 42, plugged: true, batteryW: 5)
        XCTAssertNotEqual(key(snapshot), key(snapshot, showsPercentage: false))
        XCTAssertNotEqual(try pixels(snapshot), try pixels(snapshot, showsPercentage: false))
        for style in [Settings.MenuBarIconStyle.wattson, .native] {
            XCTAssertEqual(key(snapshot, style: style), key(snapshot, style: style, showsPercentage: false))
            XCTAssertEqual(
                try pixels(snapshot, style: style),
                try pixels(snapshot, style: style, showsPercentage: false)
            )
        }
    }

    func testPlugAndBoltHaveDistinctKeysAndPixelsButMixedSupplyKeepsPlug() throws {
        let idle = PowerSnapshot(percent: 42, plugged: true, batteryW: 0)
        let charging = PowerSnapshot(percent: 42, plugged: true, batteryW: 2)
        let mixed = PowerSnapshot(percent: 42, plugged: true, batteryW: -2)
        XCTAssertNotEqual(key(idle), key(charging))
        XCTAssertEqual(key(idle), key(mixed))
        for showsPercentage in [false, true] {
            XCTAssertNotEqual(
                try pixels(idle, showsPercentage: showsPercentage),
                try pixels(charging, showsPercentage: showsPercentage)
            )
            XCTAssertEqual(
                try pixels(idle, showsPercentage: showsPercentage),
                try pixels(mixed, showsPercentage: showsPercentage)
            )
        }
    }

    func testMacOS27StyleHasDistinctPixelsFromMacOS26() throws {
        let snapshot = PowerSnapshot(percent: 75, plugged: false)
        XCTAssertNotEqual(
            try pixels(snapshot, showsPercentage: false),
            try pixels(snapshot, style: .native, showsPercentage: false)
        )
    }

    func testLowPowerColorsOnlyTheFillAndPressRestoresTemplate() throws {
        let snapshot = PowerSnapshot(percent: 42, plugged: false)
        for showsPercentage in [false, true] {
            let image = BatteryIcon.image(
                for: snapshot, mode: .low, pressed: false, style: .native27,
                showsPercentage: showsPercentage
            )
            XCTAssertFalse(image.isTemplate)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
            var yellow = 0
            var neutral = 0
            for y in 0..<bitmap.pixelsHigh {
                for x in 0..<bitmap.pixelsWide {
                    guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                          color.alphaComponent > 0.2 else { continue }
                    if color.redComponent > 0.7 && color.greenComponent > 0.5 && color.blueComponent < 0.35 {
                        yellow += 1
                    } else if max(color.redComponent, color.greenComponent, color.blueComponent)
                        - min(color.redComponent, color.greenComponent, color.blueComponent) < 0.12 {
                        neutral += 1
                    }
                }
            }
            XCTAssertGreaterThan(yellow, 0)
            XCTAssertGreaterThan(neutral, 0)
            XCTAssertTrue(BatteryIcon.image(
                for: snapshot, mode: .low, pressed: true, style: .native27,
                showsPercentage: showsPercentage
            ).isTemplate)
            XCTAssertEqual(key(snapshot, mode: .low, pressed: true).tintRole, .template)
        }
    }

    func testInsetNumberAvoidsDuplicatingTheStatusTitle() {
        let snapshot = PowerSnapshot(percent: 42)
        for style in Settings.MenuBarIconStyle.allCases {
            let presentation = StatusButtonPresentation(
                snapshot: snapshot, showsPercentage: true, degraded: true, style: style
            )
            XCTAssertEqual(presentation.title, style == .native27 ? "" : "42% ")
            XCTAssertEqual(presentation.showsPercentage, style != .native27)
            XCTAssertEqual(presentation.alpha, 0.45)
            XCTAssertEqual(StatusButtonPresentation(
                snapshot: snapshot, showsPercentage: false, degraded: false, style: style
            ).title, "")
        }
    }

    func testUnchangedTelemetryDoesNotInvalidateNewStylePixels() {
        let baseline = PowerSnapshot(percent: 42, plugged: true, adapterW: 50, batteryW: 10, systemW: 40)
        let changed = PowerSnapshot(percent: 42, plugged: true, adapterW: 80, batteryW: 20, systemW: 60)
        XCTAssertEqual(key(baseline), key(changed))
        XCTAssertEqual(key(baseline, mode: .low), key(changed, mode: .low))
        XCTAssertNotEqual(key(baseline), key(baseline, mode: .low))
    }
}
