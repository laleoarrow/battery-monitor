import AppKit
import Foundation

// The mark is the product's own hero visual shrunk down: a pipe carrying a
// travelling light, with sparks riding it. A letterform with a bolt would say
// nothing a hundred other utilities do not already say; this says exactly what
// the app draws.

private let backTop = NSColor(srgbRed: 0.129, green: 0.129, blue: 0.149, alpha: 1)
private let backBottom = NSColor(srgbRed: 0.043, green: 0.043, blue: 0.055, alpha: 1)
private let troughColor = NSColor(srgbRed: 0.176, green: 0.180, blue: 0.204, alpha: 1)
private let flowCold = NSColor(srgbRed: 0.039, green: 0.518, blue: 1.0, alpha: 1)    // 0A84FF
private let flowWarm = NSColor(srgbRed: 0.188, green: 0.820, blue: 0.345, alpha: 1)  // 30D158
private let sparkTint = NSColor(srgbRed: 0.898, green: 0.949, blue: 1.0, alpha: 1)   // E5F2FF

/// One cubic — the same shape the popover draws — scaled to the canvas.
private struct Curve {
    var start: CGPoint, c1: CGPoint, c2: CGPoint, end: CGPoint

    func scaled(_ s: CGFloat) -> Curve {
        Curve(start: CGPoint(x: start.x * s, y: start.y * s),
              c1: CGPoint(x: c1.x * s, y: c1.y * s),
              c2: CGPoint(x: c2.x * s, y: c2.y * s),
              end: CGPoint(x: end.x * s, y: end.y * s))
    }

    var path: NSBezierPath {
        let p = NSBezierPath()
        p.move(to: start)
        p.curve(to: end, controlPoint1: c1, controlPoint2: c2)
        return p
    }

    func point(at t: CGFloat) -> CGPoint {
        let u = 1 - t
        return CGPoint(
            x: u*u*u*start.x + 3*u*u*t*c1.x + 3*u*t*t*c2.x + t*t*t*end.x,
            y: u*u*u*start.y + 3*u*u*t*c1.y + 3*u*t*t*c2.y + t*t*t*end.y
        )
    }
}

private let baseCurve = Curve(
    start: CGPoint(x: 240, y: 352),
    c1: CGPoint(x: 452, y: 352),
    c2: CGPoint(x: 566, y: 690),
    end: CGPoint(x: 784, y: 690)
)

private func squircle(in rect: NSRect) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.2246, yRadius: rect.width * 0.2246)
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

func render(side: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: side, height: side))
    image.lockFocus()
    defer { image.unlockFocus() }
    guard let ctx = NSGraphicsContext.current?.cgContext else { return image }
    ctx.setShouldAntialias(true)

    let scale = side / 1024
    let inset = side * 0.0977
    let rect = NSRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
    let clip = squircle(in: rect)

    ctx.saveGState()
    clip.addClip()
    NSGradient(starting: backBottom, ending: backTop)?.draw(in: rect, angle: 90)
    NSColor.white.withAlphaComponent(0.06).setFill()
    NSBezierPath(rect: NSRect(x: rect.minX, y: rect.maxY - rect.height * 0.010,
                              width: rect.width, height: rect.height * 0.010)).fill()
    ctx.restoreGState()

    let curve = baseCurve.scaled(scale)
    let lineWidth = 134 * scale

    ctx.saveGState()
    clip.addClip()
    let trough = curve.path
    trough.lineWidth = lineWidth
    trough.lineCapStyle = .round
    troughColor.setStroke()
    trough.stroke()
    ctx.restoreGState()

    // The light is clipped to the trough, so it reads as something moving
    // inside the pipe rather than a second pipe laid on top of it.
    ctx.saveGState()
    clip.addClip()
    ctx.setLineWidth(lineWidth)
    ctx.setLineCap(.round)
    ctx.addPath(curve.path.cgPath)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    NSGradient(colorsAndLocations:
        (flowCold.withAlphaComponent(0.22), 0.0),
        (flowCold, 0.32),
        (flowWarm, 0.66),
        (flowWarm.withAlphaComponent(0.22), 1.0)
    )?.draw(in: rect, angle: 42)
    ctx.restoreGState()

    // Sparks riding the curve. This is the app's signature and the reason the
    // mark is more than a pipe.
    ctx.saveGState()
    clip.addClip()
    for (t, radius) in [(0.17, 13.0), (0.41, 23.0), (0.64, 17.0), (0.87, 10.0)] {
        let centre = curve.point(at: CGFloat(t))
        let r = CGFloat(radius) * scale
        let halo = r * 3.6

        // CoreGraphics rather than NSGradient: NSGradient interpolates toward a
        // transparent stop in a non-premultiplied space, so the falloff came
        // out as a grey disc instead of fading to nothing.
        if let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [sparkTint.withAlphaComponent(0.55).cgColor,
                     sparkTint.withAlphaComponent(0).cgColor] as CFArray,
            locations: [0, 1]
        ) {
            ctx.saveGState()
            ctx.drawRadialGradient(gradient, startCenter: centre, startRadius: 0,
                                   endCenter: centre, endRadius: halo, options: [])
            ctx.restoreGState()
        }

        sparkTint.setFill()
        NSBezierPath(ovalIn: NSRect(x: centre.x - r, y: centre.y - r,
                                    width: r * 2, height: r * 2)).fill()
    }
    ctx.restoreGState()

    return image
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
let sizes: [(String, CGFloat)] = [
    ("icon_512x512@2x", 1024), ("icon_512x512", 512), ("icon_256x256@2x", 512),
    ("icon_256x256", 256), ("icon_128x128@2x", 256), ("icon_128x128", 128),
    ("icon_32x32@2x", 64), ("icon_32x32", 32), ("icon_16x16@2x", 32), ("icon_16x16", 16),
]
for (name, side) in sizes {
    let image = render(side: side)
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { continue }
    try? png.write(to: out.appendingPathComponent("\(name).png"))
}
print("ICONSET_WRITTEN")
