import AppKit
import XCTest
@testable import Wattson

final class FlowNodeIconTests: XCTestCase {
    private struct InkMetrics {
        let extent: CGFloat
        let center: CGPoint
        let margin: CGFloat
    }

    private func metrics(for symbol: String) throws -> InkMetrics {
        let image = try XCTUnwrap(FlowNodeView.iconImageForTest(symbol: symbol))
        XCTAssertEqual(image.size, NSSize(width: 32, height: 32))

        let scale = 4
        let pixels = 32 * scale
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixels,
            pixelsHigh: pixels,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        bitmap.size = NSSize(width: 32, height: 32)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(x: 0, y: 0, width: 32, height: 32))
        NSGraphicsContext.restoreGraphicsState()

        var minX = pixels
        var minY = pixels
        var maxX = -1
        var maxY = -1
        for y in 0..<pixels {
            for x in 0..<pixels where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.06 {
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }
        XCTAssertGreaterThanOrEqual(maxX, minX)
        XCTAssertGreaterThanOrEqual(maxY, minY)

        let divisor = CGFloat(scale)
        let width = CGFloat(maxX - minX + 1) / divisor
        let height = CGFloat(maxY - minY + 1) / divisor
        let center = CGPoint(
            x: CGFloat(minX + maxX + 1) / (2 * divisor),
            y: CGFloat(minY + maxY + 1) / (2 * divisor)
        )
        let margin = CGFloat(min(minX, minY, pixels - 1 - maxX, pixels - 1 - maxY)) / divisor
        return InkMetrics(extent: max(width, height), center: center, margin: margin)
    }

    func testAllPowerNodeGlyphsShareOneOpticalScale() throws {
        let symbols = [
            "powerplug", "powerplug.slash", "cpu",
            "battery.25", "battery.50", "battery.75", "battery.100",
            "battery.100.bolt",
        ]
        let allMetrics = try symbols.map(metrics)

        for (symbol, metric) in zip(symbols, allMetrics) {
            XCTAssertGreaterThanOrEqual(metric.extent, 20.5, symbol)
            XCTAssertLessThanOrEqual(metric.extent, 24.5, symbol)
            XCTAssertEqual(metric.center.x, 16, accuracy: 0.75, symbol)
            XCTAssertEqual(metric.center.y, 16, accuracy: 0.75, symbol)
            XCTAssertGreaterThanOrEqual(metric.margin, 2, symbol)
        }
        let extents = allMetrics.map(\.extent)
        XCTAssertLessThanOrEqual(try XCTUnwrap(extents.max()) / XCTUnwrap(extents.min()), 1.18)
    }
}
