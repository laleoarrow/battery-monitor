import AppKit
import XCTest
@testable import Wattson

final class PowerSymbolArtworkTests: XCTestCase {
    private func pixels(_ image: NSImage) throws -> NSBitmapImageRep {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 128, pixelsHigh: 128,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        bitmap.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        defer { NSGraphicsContext.restoreGraphicsState() }
        image.draw(in: NSRect(origin: .zero, size: image.size))
        return bitmap
    }

    private func bluePixels(_ image: NSImage) throws -> Int {
        let bitmap = try pixels(image)
        return (0..<128).reduce(0) { total, y in
            total + (0..<128).filter { x in
                guard let color = bitmap.colorAt(x: x, y: y), color.alphaComponent > 0.08 else { return false }
                return color.blueComponent - color.redComponent > 0.25
                    && color.blueComponent - color.greenComponent > 0.1
            }.count
        }
    }

    func testBatteryCapacityBandsAndChargingMarkRemainDistinct() throws {
        XCTAssertEqual([0, 24, 25, 49, 50, 74, 75, 100].map(PowerIconImageView.batterySymbol),
                       ["battery.25", "battery.25", "battery.50", "battery.50",
                        "battery.75", "battery.75", "battery.100", "battery.100"])
        let levels = try ["battery.25", "battery.50", "battery.75", "battery.100"].map {
            try XCTUnwrap(PowerIconImageView.image(for: $0, ink: .gray, accent: .systemBlue))
        }
        let counts = try levels.map(bluePixels)
        for index in 1..<counts.count { XCTAssertGreaterThan(counts[index], counts[index - 1]) }
        let charging = try XCTUnwrap(PowerIconImageView.image(for: "battery.100.bolt", ink: .gray, accent: .systemBlue))
        XCTAssertNotEqual(charging.tiffRepresentation, levels.last?.tiffRepresentation)
        let connected = try XCTUnwrap(PowerIconImageView.image(for: "powerplug"))
        let disconnected = try XCTUnwrap(PowerIconImageView.image(for: "powerplug.slash"))
        XCTAssertNotEqual(connected.tiffRepresentation, disconnected.tiffRepresentation)
        XCTAssertNil(PowerIconImageView.image(for: "device.output.port"))
        XCTAssertTrue(try XCTUnwrap(FlowNodeView.iconImageForTest(symbol: "device.output.port")).isTemplate)
    }

    func testCacheReusesTelemetryOnlyArtworkAndRefreshesResolvedColors() throws {
        let icon = PowerIconImageView()
        icon.appearance = NSAppearance(named: .aqua)
        XCTAssertTrue(icon.configurePowerIcon(symbol: "cpu", description: "System",
                                             accent: PopoverStyle.blue, side: 32, inset: 4))
        let first = try XCTUnwrap(icon.image)
        XCTAssertEqual(icon.renderCountForTest, 1)
        icon.configurePowerIcon(symbol: "cpu", description: "System Total",
                                accent: PopoverStyle.blue, side: 32, inset: 4)
        XCTAssertTrue(icon.image === first)
        XCTAssertEqual(icon.image?.accessibilityDescription, "System Total")
        XCTAssertEqual(icon.renderCountForTest, 1)
        icon.configurePowerIcon(symbol: "cpu", description: "System",
                                accent: PopoverStyle.green, side: 32, inset: 4)
        XCTAssertEqual(icon.renderCountForTest, 2)
        XCTAssertNotEqual(icon.image?.tiffRepresentation, first.tiffRepresentation)
        let light = icon.image?.tiffRepresentation
        icon.appearance = NSAppearance(named: .darkAqua)
        icon.configurePowerIcon(symbol: "cpu", description: "System",
                                accent: PopoverStyle.green, side: 32, inset: 4)
        XCTAssertEqual(icon.renderCountForTest, 3)
        XCTAssertNotEqual(icon.image?.tiffRepresentation, light)
        XCTAssertFalse(icon.configurePowerIcon(symbol: "device.output.port", description: "Device Output",
                                              accent: PopoverStyle.green, side: 32, inset: 4))
        icon.configurePowerIcon(symbol: "cpu", description: "System",
                                accent: PopoverStyle.green, side: 32, inset: 4)
        XCTAssertEqual(icon.renderCountForTest, 4)
    }

    func testConnectedAndDisconnectedShareTheSelectedPlugGeometry() throws {
        let connected = try XCTUnwrap(PowerIconImageView.image(
            for: "powerplug", ink: .black, accent: .black, increasedContrast: true))
        let disconnected = try XCTUnwrap(PowerIconImageView.image(
            for: "powerplug.slash", ink: .black, accent: .black, increasedContrast: true))
        XCTAssertEqual(connected.tiffRepresentation, disconnected.tiffRepresentation)
    }

    func testAllStatesUseColoredVectorsInBothPlacementsAndAppearances() throws {
        let snapshots = [
            PowerSnapshot(percent: 58, plugged: true, adapterW: 65, batteryW: 25, systemW: 40),
            PowerSnapshot(percent: 100, plugged: true, adapterW: 29, batteryW: 0, systemW: 29),
            PowerSnapshot(percent: 61, plugged: false, batteryW: -29, systemW: 29),
            PowerSnapshot(percent: 44, plugged: true, adapterW: 30, batteryW: -12, systemW: 42),
            PowerSnapshot(percent: 9, plugged: false, batteryW: -18, systemW: 18),
            PowerSnapshot(percent: 45, plugged: false, batteryW: -12, systemW: 12, lowPowerMode: true),
        ]
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let flow = PowerFlowView()
            let lanes = LaneView()
            flow.appearance = NSAppearance(named: name)
            lanes.appearance = NSAppearance(named: name)
            for snapshot in snapshots {
                flow.update(snapshot: snapshot, animated: false)
                lanes.update(snapshot: snapshot)
                let images = try (flow.nodeIconImagesForTest + lanes.iconImagesForTest).map { try XCTUnwrap($0) }
                XCTAssertTrue(images.allSatisfy { !$0.isTemplate })
                XCTAssertTrue(images.prefix(3).allSatisfy { $0.size == NSSize(width: 32, height: 32) })
                XCTAssertTrue(images.suffix(2).allSatisfy { $0.size == NSSize(width: 16, height: 16) })
                if snapshot.state == .mixedSupply {
                    for index in [0, 2, 3] { XCTAssertGreaterThan(try bluePixels(images[index]), 0) }
                    for index in [1, 4] { XCTAssertEqual(try bluePixels(images[index]), 0) }
                }
                if snapshot.state == .pluggedIdle {
                    let expected = try XCTUnwrap(PowerIconImageView.image(
                        for: "battery.100", side: 16, inset: 0,
                        ink: resolved(PopoverStyle.neutral, name), accent: resolved(PopoverStyle.blue, name),
                        increasedContrast: PopoverStyle.isHighContrast(try XCTUnwrap(NSAppearance(named: name)))))
                    XCTAssertEqual(images[4].tiffRepresentation, expected.tiffRepresentation)
                }
                let counts = flow.nodeIconRenderCountsForTest + lanes.iconRenderCountsForTest
                flow.update(snapshot: snapshot, animated: false)
                lanes.update(snapshot: snapshot)
                XCTAssertEqual(flow.nodeIconRenderCountsForTest + lanes.iconRenderCountsForTest, counts)
            }
        }
    }

    private func resolved(_ color: NSColor, _ name: NSAppearance.Name) -> NSColor {
        var value = color
        NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
            value = color.usingColorSpace(.sRGB) ?? color
        }
        return value
    }

    func testContrastKeepsFunctionalMarksAndChangesDecorativeFills() throws {
        for symbol in ["cpu", "powerplug", "powerplug.slash", "battery.50", "battery.100.bolt"] {
            let normal = try XCTUnwrap(PowerIconImageView.image(for: symbol, ink: .gray, accent: .systemBlue))
            let contrast = try XCTUnwrap(PowerIconImageView.image(for: symbol, ink: .gray, accent: .systemBlue,
                                                                increasedContrast: true))
            let bitmap = try pixels(contrast)
            let visible = (0..<128).reduce(0) { total, y in
                total + (0..<128).filter { (bitmap.colorAt(x: $0, y: y)?.alphaComponent ?? 0) > 0.08 }.count
            }
            XCTAssertGreaterThan(visible, 100)
            if symbol == "powerplug.slash" {
                XCTAssertEqual(try bluePixels(contrast), 0)
            } else {
                XCTAssertGreaterThan(try bluePixels(contrast), 0)
            }
            XCTAssertNotEqual(normal.tiffRepresentation, contrast.tiffRepresentation)
        }
    }
}
