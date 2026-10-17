import AppKit

@main enum RenderModuleIcons {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else { exit(64) }
        let destination = URL(fileURLWithPath: CommandLine.arguments[1])
        let width = 1400, height = 660
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        defer { NSGraphicsContext.restoreGraphicsState() }
        let names = ["Energy Flow", "Ring Gauge", "Power Lanes", "Power History", "Battery Time"]
        for (row, dark) in [true, false].enumerated() {
            let y: CGFloat = CGFloat(1 - row) * 330
            let background = dark ? NSColor(srgbRed: 0.12, green: 0.125, blue: 0.135, alpha: 1)
                : NSColor(srgbRed: 0.96, green: 0.96, blue: 0.97, alpha: 1)
            let ink = dark ? NSColor(srgbRed: 0.914, green: 0.914, blue: 0.914, alpha: 1)
                : NSColor(srgbRed: 0.141, green: 0.141, blue: 0.149, alpha: 1)
            let blue = dark ? NSColor(srgbRed: 10/255, green: 132/255, blue: 1, alpha: 1)
                : NSColor(srgbRed: 0, green: 122/255, blue: 1, alpha: 1)
            background.setFill()
            NSRect(x: 0, y: y, width: CGFloat(width), height: 330).fill()
            for (index, module) in Settings.Module.allCases.enumerated() {
                let center = CGFloat(index) * 280 + 140
                let large = ModuleIconArtwork.image(for: module, side: 120, ink: ink,
                                                    accent: blue, increasedContrast: false)
                large.draw(in: NSRect(x: center - 60, y: y + 137, width: 120, height: 120))
                let small = ModuleIconArtwork.image(for: module, side: 20, ink: ink,
                                                    accent: blue, increasedContrast: false)
                small.draw(in: NSRect(x: center - 10, y: y + 71, width: 20, height: 20))
                let text = names[index] as NSString
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 19, weight: .medium), .foregroundColor: ink,
                ]
                let size = text.size(withAttributes: attributes)
                text.draw(at: NSPoint(x: center - size.width / 2, y: y + 26), withAttributes: attributes)
            }
        }
        guard let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
        try png.write(to: destination.appendingPathComponent("vector-preview.png"), options: .atomic)
        print("Rendered the production vector artwork offscreen; no application window or preferences were used.")
    }
}
