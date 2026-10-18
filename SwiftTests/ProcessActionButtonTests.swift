import AppKit
import XCTest
@testable import Wattson

final class ProcessActionButtonTests: XCTestCase {
    private final class Target: NSObject {
        var presses = 0
        @objc func press(_ sender: NSButton) { presses += 1 }
    }

    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
    }

    func testCapsuleKeepsItsAssignedFrameAndNativeAction() {
        let frame = NSRect(x: 300, y: 4, width: 38, height: 16)
        let button = ProcessActionButton(frame: frame)
        let target = Target()
        button.target = target
        button.action = #selector(Target.press(_:))
        button.performClick(nil)
        XCTAssertEqual(target.presses, 1)
        XCTAssertEqual(button.frame, frame)
        XCTAssertEqual(button.imagePosition, .imageOnly)
        XCTAssertEqual(button.controlSize, .mini)
        XCTAssertNotNil(button.image)
        XCTAssertEqual(button.keyEquivalent, "")
        if #available(macOS 26.0, *) {
            XCTAssertEqual(button.bezelStyle, .glass)
            XCTAssertEqual(button.borderShape, .capsule)
        }
    }

    func testDisabledCapsuleDoesNotDispatchAndCanBeReenabled() {
        let button = ProcessActionButton(frame: NSRect(x: 0, y: 0, width: 38, height: 16))
        let target = Target()
        button.target = target
        button.action = #selector(Target.press(_:))
        button.isEnabled = false
        button.performClick(nil)
        XCTAssertEqual(target.presses, 0)
        button.isEnabled = true
        button.performClick(nil)
        XCTAssertEqual(target.presses, 1)
    }

    func testAppearanceRefreshPreservesCallerControlConfiguration() {
        let button = ProcessActionButton(frame: NSRect(x: 300, y: 4, width: 38, height: 16))
        let target = Target()
        button.target = target
        button.action = #selector(Target.press(_:))
        button.toolTip = "Force Quit"
        button.setAccessibilityLabel("Force Quit Safari")
        for appearanceName in [NSAppearance.Name.aqua, .darkAqua,
                               .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua] {
            button.appearance = NSAppearance(named: appearanceName)
            button.refreshAppearance()
            XCTAssertTrue(button.target === target)
            XCTAssertEqual(button.action, #selector(Target.press(_:)))
            XCTAssertEqual(button.toolTip, "Force Quit")
            XCTAssertEqual(button.accessibilityLabel(), "Force Quit Safari")
            XCTAssertEqual(button.frame, NSRect(x: 300, y: 4, width: 38, height: 16))
            XCTAssertNotNil(button.image)
        }
    }

    func testTintRefreshIsIdempotentAndResolvesInTheButtonsAppearance() throws {
        try withAppearanceOptions(reducedTransparency: false, increasedContrast: false) {
            let button = ProcessActionButton(frame: NSRect(x: 0, y: 0, width: 38, height: 16))
            button.setTintColor(PopoverStyle.green)
            var glyphs: [NSColor] = []
            for (name, other): (NSAppearance.Name, NSAppearance.Name) in [(.aqua, .darkAqua), (.darkAqua, .aqua)] {
                NSAppearance(named: other)!.performAsCurrentDrawingAppearance {
                    button.appearance = NSAppearance(named: name)
                    button.viewDidChangeEffectiveAppearance()
                }
                try assertColor(button.tintColor, matches: PopoverStyle.green, in: button.effectiveAppearance)
                try assertColor(try XCTUnwrap(button.bezelColor), matches: button.tintColor,
                                in: button.effectiveAppearance)
                glyphs.append(try rgb(try XCTUnwrap(button.contentTintColor)))
                let image = button.image
                button.needsDisplay = false
                button.setTintColor(PopoverStyle.green)
                XCTAssertTrue(button.image === image)
                XCTAssertFalse(button.needsDisplay)
                XCTAssertEqual(button.frame.size, NSSize(width: 38, height: 16))
                XCTAssertTrue(button.layer?.animationKeys()?.isEmpty ?? true)
                if #available(macOS 26.0, *) { XCTAssertEqual(button.tintProminence, .secondary) }
            }
            XCTAssertLessThan(luminance(glyphs[0]), 0.1)
            XCTAssertGreaterThan(luminance(glyphs[1]), 0.8)
        }
    }

    func testEnabledGlassSurfaceFollowsTheSuppliedColorFamily() throws {
        try withAppearanceOptions(reducedTransparency: false, increasedContrast: false) {
            let button = ProcessActionButton(frame: NSRect(x: 0, y: 0, width: 38, height: 16))
            for name: NSAppearance.Name in [.aqua, .darkAqua] {
                button.appearance = NSAppearance(named: name)
                button.setTintColor(NSColor(rgb: 0x18783A))
                button.refreshAppearance()
                let green = try surfacePixel(button)
                button.setTintColor(NSColor(rgb: 0x0064CF))
                let blue = try surfacePixel(button)
                button.setTintColor(NSColor(rgb: 0x777777))
                let neutral = try surfacePixel(button)
                XCTAssertGreaterThan(green.greenComponent, green.redComponent + 0.06)
                XCTAssertGreaterThan(green.greenComponent, green.blueComponent + 0.06)
                XCTAssertGreaterThan(blue.blueComponent, blue.redComponent + 0.06)
                XCTAssertGreaterThan(blue.blueComponent, blue.greenComponent + 0.06)
                XCTAssertEqual(neutral.redComponent, neutral.greenComponent, accuracy: 0.02)
                XCTAssertEqual(neutral.greenComponent, neutral.blueComponent, accuracy: 0.02)
            }
        }
    }

    func testOpaqueAccessibilitySurfacesKeepTheExactTintAndLegibleGlyph() throws {
        for (reduced, contrast) in [(true, false), (false, true)] {
            try withAppearanceOptions(reducedTransparency: reduced, increasedContrast: contrast) {
                let button = ProcessActionButton(frame: NSRect(x: 0, y: 0, width: 38, height: 16))
                for name: NSAppearance.Name in [.aqua, .darkAqua] {
                    button.appearance = NSAppearance(named: name)
                    for tint in [PopoverStyle.green, PopoverStyle.blue, PopoverStyle.neutral] {
                        button.setTintColor(tint)
                        button.refreshAppearance()
                        let fill = try surfacePixel(button)
                        try assertColor(fill, matches: tint, in: button.effectiveAppearance, accuracy: 0.015)
                        XCTAssertEqual(fill.alphaComponent, 1)
                        let glyph = try rgb(try XCTUnwrap(button.contentTintColor))
                        let ratio = (max(luminance(glyph), luminance(fill)) + 0.05)
                            / (min(luminance(glyph), luminance(fill)) + 0.05)
                        XCTAssertGreaterThanOrEqual(ratio, 4.5)
                        XCTAssertNil(button.bezelColor)
                        if #available(macOS 26.0, *) { XCTAssertEqual(button.tintProminence, .none) }
                    }
                }
            }
        }
    }

    func testDisabledSurfaceAndGlyphRemainNeutralAcrossTintChanges() throws {
        try withAppearanceOptions(reducedTransparency: false, increasedContrast: false) {
            let button = ProcessActionButton(frame: NSRect(x: 0, y: 0, width: 38, height: 16))
            button.isEnabled = false
            for name: NSAppearance.Name in [.aqua, .darkAqua] {
                button.appearance = NSAppearance(named: name)
                button.setTintColor(PopoverStyle.green)
                button.refreshAppearance()
                let first = try surfacePixel(button)
                button.setTintColor(PopoverStyle.blue)
                try assertColor(try surfacePixel(button), matches: first, in: button.effectiveAppearance)
                try assertColor(try XCTUnwrap(button.contentTintColor), matches: .secondaryLabelColor,
                                in: button.effectiveAppearance)
                XCTAssertNil(button.bezelColor)
                XCTAssertNotNil(button.image)
            }
        }
    }

    private func withAppearanceOptions(reducedTransparency: Bool, increasedContrast: Bool,
                                       _ body: () throws -> Void) rethrows {
        let options = ["WATTSON_FORCE_REDUCE_TRANSPARENCY": reducedTransparency,
                       "WATTSON_FORCE_INCREASE_CONTRAST": increasedContrast]
        let prior = options.keys.map { ($0, ProcessInfo.processInfo.environment[$0]) }
        defer {
            for (key, value) in prior {
                if let value { setenv(key, value, 1) } else { unsetenv(key) }
            }
        }
        for (key, value) in options { setenv(key, value ? "1" : "0", 1) }
        try body()
    }

    private func surfacePixel(_ button: ProcessActionButton) throws -> NSColor {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 38, pixelsHigh: 16,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current?.cgContext.clear(button.bounds)
        button.effectiveAppearance.performAsCurrentDrawingAppearance {
            (button.cell as? NSButtonCell)?.drawBezel(withFrame: button.bounds, in: button)
        }
        return try rgb(try XCTUnwrap(bitmap.colorAt(x: 30, y: 8)))
    }

    private func rgb(_ color: NSColor) throws -> NSColor {
        try XCTUnwrap(color.usingColorSpace(.sRGB))
    }

    private func luminance(_ color: NSColor) -> CGFloat {
        let linear = [color.redComponent, color.greenComponent, color.blueComponent].map {
            $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4)
        }
        return linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722
    }

    private func assertColor(_ actual: NSColor, matches expected: NSColor, in appearance: NSAppearance,
                             accuracy: CGFloat = 0.001, file: StaticString = #filePath,
                             line: UInt = #line) throws {
        var actual = actual
        var expected = expected
        appearance.performAsCurrentDrawingAppearance {
            actual = NSColor(cgColor: actual.cgColor)!
            expected = NSColor(cgColor: expected.cgColor)!
        }
        actual = try rgb(actual)
        expected = try rgb(expected)
        for (actual, expected) in zip([actual.redComponent, actual.greenComponent, actual.blueComponent, actual.alphaComponent],
                                      [expected.redComponent, expected.greenComponent, expected.blueComponent, expected.alphaComponent]) {
            XCTAssertEqual(actual, expected, accuracy: accuracy, file: file, line: line)
        }
    }
}
