import AppKit
import Foundation

// Wattson = Watt + Watson. The mark is a single W whose centre peak is cut by a
// bolt, so the letter and the lightning are one figure rather than two stacked
// symbols.

let colorBackTop = NSColor(srgbRed: 0.145, green: 0.145, blue: 0.169, alpha: 1)
let colorBackBottom = NSColor(srgbRed: 0.055, green: 0.055, blue: 0.070, alpha: 1)
let colorMarkTop = NSColor(srgbRed: 0.235, green: 0.859, blue: 0.396, alpha: 1)   // 30D158
let colorMarkBottom = NSColor(srgbRed: 0.086, green: 0.616, blue: 0.290, alpha: 1)

func wPath(in side: CGFloat) -> NSBezierPath {
    let s = side / 1024
    // AppKit draws with y growing upward. Written the other way the W comes
    // out as an M.
    let points = [
        CGPoint(x: 244 * s, y: 706 * s),
        CGPoint(x: 400 * s, y: 318 * s),
        CGPoint(x: 512 * s, y: 536 * s),
        CGPoint(x: 624 * s, y: 318 * s),
        CGPoint(x: 780 * s, y: 706 * s),
    ]
    let path = NSBezierPath()
    path.move(to: points[0])
    for point in points.dropFirst() { path.line(to: point) }
    path.lineWidth = 104 * s
    path.lineJoinStyle = .miter
    path.lineCapStyle = .round
    path.miterLimit = 6
    return path
}

func boltPath(in side: CGFloat) -> NSBezierPath {
    let s = side / 1024
    let pts: [CGPoint] = [
        CGPoint(x: 551, y: 707), CGPoint(x: 437, y: 517), CGPoint(x: 500, y: 517),
        CGPoint(x: 473, y: 355), CGPoint(x: 587, y: 545), CGPoint(x: 524, y: 545),
    ].map { CGPoint(x: $0.x * s, y: $0.y * s) }
    let path = NSBezierPath()
    path.move(to: pts[0])
    for point in pts.dropFirst() { path.line(to: point) }
    path.close()
    return path
}

func render(side: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: side, height: side))
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else { image.unlockFocus(); return image }
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    let inset = side * 0.0977          // macOS icons leave a margin inside the canvas
    let rect = NSRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
    let radius = rect.width * 0.2246
    let squircle = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    ctx.saveGState()
    squircle.addClip()
    NSGradient(starting: colorBackBottom, ending: colorBackTop)?
        .draw(in: rect, angle: 90)
    // Faint top edge highlight, the way system icons catch light.
    NSColor.white.withAlphaComponent(0.07).setFill()
    NSBezierPath(rect: NSRect(x: rect.minX, y: rect.maxY - rect.height * 0.012,
                              width: rect.width, height: rect.height * 0.012)).fill()
    ctx.restoreGState()

    // The W in green.
    let mark = wPath(in: side)
    ctx.saveGState()
    squircle.addClip()
    ctx.setLineWidth(mark.lineWidth)
    ctx.setLineJoin(.miter)
    ctx.setLineCap(.round)
    ctx.setMiterLimit(6)
    ctx.addPath(mark.cgPath)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    NSGradient(starting: colorMarkBottom, ending: colorMarkTop)?.draw(in: rect, angle: 90)
    ctx.restoreGState()

    // Punch a gap through the centre peak, then set the bolt inside it. The
    // gap is what makes the letter and the lightning read as one figure
    // instead of a symbol dropped on top of a letter.
    let bolt = boltPath(in: side)
    ctx.saveGState()
    squircle.addClip()
    let gapWidth = side / 1024 * 34
    ctx.setLineWidth(gapWidth)
    ctx.setLineJoin(.round)
    NSGradient(starting: colorBackBottom, ending: colorBackTop)?.draw(in: NSRect.zero, angle: 90)
    colorBackBottom.setStroke()
    colorBackBottom.setFill()
    bolt.lineWidth = gapWidth
    bolt.lineJoinStyle = .round
    bolt.stroke()
    bolt.fill()
    ctx.restoreGState()

    ctx.saveGState()
    squircle.addClip()
    ctx.addPath(bolt.cgPath)
    ctx.clip()
    NSGradient(starting: colorMarkBottom, ending: colorMarkTop)?.draw(in: rect, angle: 90)
    ctx.restoreGState()

    image.unlockFocus()
    return image
}

extension NSBezierPath {
    var cgPath: CGPath {
        let path = CGMutablePath()
        var points = [NSPoint](repeating: .zero, count: 3)
        for index in 0..<elementCount {
            switch element(at: index, associatedPoints: &points) {
            case .moveTo: path.move(to: points[0])
            case .lineTo: path.addLine(to: points[0])
            case .curveTo: path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .closePath: path.closeSubpath()
            default: break
            }
        }
        return path
    }
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for (name, side) in [("icon_512x512@2x", 1024.0), ("icon_512x512", 512.0), ("icon_256x256@2x", 512.0),
                     ("icon_256x256", 256.0), ("icon_128x128@2x", 256.0), ("icon_128x128", 128.0),
                     ("icon_32x32@2x", 64.0), ("icon_32x32", 32.0), ("icon_16x16@2x", 32.0), ("icon_16x16", 16.0)] {
    let img = render(side: CGFloat(side))
    guard let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { continue }
    try? png.write(to: out.appendingPathComponent("\(name).png"))
}
print("ICONSET_WRITTEN")
