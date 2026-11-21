import AppKit

/// Approved USB-C artwork, retaining the neutral shell and gradient contact.
enum DeviceOutputIcon {
    static func image(side: CGFloat = 32, ink: NSColor, accent: NSColor,
                      increasedContrast: Bool = false) -> NSImage {
        let resolvedInk = ink.usingColorSpace(.sRGB) ?? ink
        let resolvedAccent = accent.usingColorSpace(.sRGB) ?? accent
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            let inset = side / 8
            let transform = NSAffineTransform()
            transform.translateX(by: rect.minX + inset, yBy: rect.maxY - inset)
            transform.scaleX(by: (rect.width - 2 * inset) / 24,
                             yBy: -(rect.height - 2 * inset) / 24)
            transform.concat()

            if !increasedContrast {
                let cavity = CGPath(roundedRect: CGRect(x: 4.25, y: 8.25, width: 15.5, height: 7.5),
                                    cornerWidth: 3.75, cornerHeight: 3.75, transform: nil)
                fill(cavity, accent: resolvedAccent, from: 0.02, to: 0.14,
                     start: CGPoint(x: 4.25, y: 8.25), end: CGPoint(x: 19.75, y: 15.75))
            }

            let shell = NSBezierPath(roundedRect: NSRect(x: 2.5, y: 6.5, width: 19, height: 11),
                                     xRadius: 5.5, yRadius: 5.5)
            resolvedInk.setStroke()
            shell.lineWidth = increasedContrast ? 1.56 : 1.3
            shell.lineCapStyle = .round
            shell.lineJoinStyle = .round
            shell.stroke()

            let tongue = CGPath(roundedRect: CGRect(x: 6.2, y: 10.6, width: 11.6, height: 2.8),
                                cornerWidth: 0.9, cornerHeight: 0.9, transform: nil)
            fill(tongue, accent: resolvedAccent,
                 from: increasedContrast ? 1 : 0.8, to: increasedContrast ? 1 : 0.35,
                 start: CGPoint(x: 6.2, y: 10.6), end: CGPoint(x: 17.8, y: 13.4))
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "Device Output"
        return image
    }

    private static func fill(_ path: CGPath, accent: NSColor, from: CGFloat, to: CGFloat,
                             start: CGPoint, end: CGPoint) {
        guard let context = NSGraphicsContext.current?.cgContext,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let gradient = CGGradient(colorsSpace: space,
                  colors: [accent.withAlphaComponent(from).cgColor,
                           accent.withAlphaComponent(to).cgColor] as CFArray,
                  locations: [0, 1]) else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.addPath(path)
        context.clip()
        context.drawLinearGradient(gradient, start: start, end: end,
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }
}
