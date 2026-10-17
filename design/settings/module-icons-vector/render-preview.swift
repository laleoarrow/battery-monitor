import AppKit

@main enum RenderModuleIcons {
    static func main() throws {
        guard CommandLine.arguments.count == 4 else { exit(64) }
        let destination = URL(fileURLWithPath: CommandLine.arguments[1])
        let width = Settings.Module.allCases.count * 280, height = 660
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        defer { NSGraphicsContext.restoreGraphicsState() }
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
                let text = module.title as NSString
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 19, weight: .medium), .foregroundColor: ink,
                ]
                let size = text.size(withAttributes: attributes)
                text.draw(at: NSPoint(x: center - size.width / 2, y: y + 26), withAttributes: attributes)
            }
        }
        guard let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
        try png.write(to: destination.appendingPathComponent("vector-preview.png"), options: .atomic)
        try renderSidebar(to: URL(fileURLWithPath: CommandLine.arguments[2]))
        try renderGeneral(to: URL(fileURLWithPath: CommandLine.arguments[3]))
        print("Rendered the production vector artwork offscreen; no application window or preferences were used.")
    }

    static func renderSidebar(to destination: URL) throws {
        let width = 900, height = 780
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        defer { NSGraphicsContext.restoreGraphicsState() }
        let names = ["General", "Display", "Modules"]
        for row in 0..<3 {
            let y = CGFloat(2 - row) * 260
            let dark = row != 1
            let selected = row == 2
            let background = dark ? NSColor(srgbRed: 0.12, green: 0.125, blue: 0.135, alpha: 1)
                : NSColor(srgbRed: 0.96, green: 0.96, blue: 0.97, alpha: 1)
            let ink = selected ? .white : dark ? NSColor(srgbRed: 0.914, green: 0.914, blue: 0.914, alpha: 1)
                : NSColor(srgbRed: 0.141, green: 0.141, blue: 0.149, alpha: 1)
            let accent = selected ? .white : dark ? NSColor(srgbRed: 10/255, green: 132/255, blue: 1, alpha: 1)
                : NSColor(srgbRed: 0, green: 122/255, blue: 1, alpha: 1)
            background.setFill()
            NSRect(x: 0, y: y, width: CGFloat(width), height: 260).fill()
            for (index, icon) in ModuleIconArtwork.SidebarIcon.allCases.enumerated() {
                let center = CGFloat(index) * 300 + 150
                if selected {
                    NSColor(srgbRed: 0.035, green: 0.36, blue: 0.82, alpha: 1).setFill()
                    NSBezierPath(roundedRect: NSRect(x: center - 128, y: y + 15,
                                                     width: 256, height: 230),
                                 xRadius: 18, yRadius: 18).fill()
                }
                ModuleIconArtwork.sidebarImage(for: icon, side: 96, ink: ink,
                    accent: accent, increasedContrast: false)
                    .draw(in: NSRect(x: center - 48, y: y + 121, width: 96, height: 96))
                ModuleIconArtwork.sidebarImage(for: icon, side: 18, ink: ink,
                    accent: accent, increasedContrast: false)
                    .draw(in: NSRect(x: center - 9, y: y + 72, width: 18, height: 18))
                let text = names[index] as NSString
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 19, weight: .medium), .foregroundColor: ink,
                ]
                let size = text.size(withAttributes: attributes)
                text.draw(at: NSPoint(x: center - size.width / 2, y: y + 33), withAttributes: attributes)
            }
        }
        guard let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
        try png.write(to: destination.appendingPathComponent("sidebar-vector-preview.png"), options: .atomic)
    }
    static func renderGeneral(to destination: URL) throws {
        let width = 1400, height = 660
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        defer { NSGraphicsContext.restoreGraphicsState() }
        let names = ["Launch at Login", "System Battery Icon", "Check for Updates", "Automatic Updates", "Send Feedback"]
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
            for (index, icon) in ModuleIconArtwork.GeneralIcon.allCases.enumerated() {
                let center = CGFloat(index) * 280 + 140
                let large = ModuleIconArtwork.generalImage(for: icon, side: 120, ink: ink,
                                                    accent: blue, increasedContrast: false)
                large.draw(in: NSRect(x: center - 60, y: y + 137, width: 120, height: 120))
                let small = ModuleIconArtwork.generalImage(for: icon, side: 20, ink: ink,
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
        try png.write(to: destination.appendingPathComponent("general-vector-preview.png"), options: .atomic)
    }

}
