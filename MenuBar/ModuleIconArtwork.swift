// Generated from design/settings/{module,sidebar}-icons-vector/*.svg. Edit the SVG masters.
// Regenerate with: python3 design/settings/module-icons-vector/generate-swift.py
import AppKit

enum ModuleIconArtwork {
    enum SidebarIcon: CaseIterable { case general, display, modules }

    static func image(for module: Settings.Module, side: CGFloat, ink: NSColor,
                      accent: NSColor, increasedContrast: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            let transform = NSAffineTransform()
            transform.translateX(by: rect.minX, yBy: rect.maxY)
            transform.scaleX(by: rect.width / 24, yBy: -rect.height / 24)
            transform.concat()
            let contrastScale: CGFloat = increasedContrast ? 1.2 : 1
            switch module {
            case .flow:
                do {
                    let path = CGMutablePath()
                    path.move(to: NSPoint(x: 2.2, y: 4))
                    path.addLine(to: NSPoint(x: 2.2, y: 7.6))
                    path.addCurve(to: NSPoint(x: 13.1, y: 21), control1: NSPoint(x: 9.4, y: 7.6), control2: NSPoint(x: 13.1, y: 12.9))
                    drawGradient(path, strokeWidth: 1.65 * contrastScale,
                                 colors: [accent.withAlphaComponent((increasedContrast ? 1 : 0)).cgColor, accent.withAlphaComponent((increasedContrast ? 1 : 0.3)).cgColor, accent.withAlphaComponent((increasedContrast ? 1 : 1)).cgColor],
                                 locations: [0, 0.32, 1], start: NSPoint(x: 2.2, y: 4), end: NSPoint(x: 2.2, y: 8.4))
                }
                do {
                    let path = NSBezierPath()
                    path.move(to: NSPoint(x: 7.3, y: 13.1))
                    path.line(to: NSPoint(x: 7.3, y: 20.1))
                    path.move(to: NSPoint(x: 4.8, y: 17.6))
                    path.line(to: NSPoint(x: 7.3, y: 20.1))
                    path.line(to: NSPoint(x: 9.8, y: 17.6))
                    accent.setStroke()
                    path.lineWidth = 1.75 * contrastScale
                    path.lineCapStyle = .round
                    path.lineJoinStyle = .round
                    path.stroke()
                }
                do {
                    let path = NSBezierPath()
                    path.move(to: NSPoint(x: 18.7, y: 15))
                    path.line(to: NSPoint(x: 18.7, y: 2.8))
                    path.move(to: NSPoint(x: 15.9, y: 5.7))
                    path.line(to: NSPoint(x: 18.7, y: 2.8))
                    path.line(to: NSPoint(x: 21.5, y: 5.7))
                    ink.setStroke()
                    path.lineWidth = 1.5 * contrastScale
                    path.lineCapStyle = .round
                    path.lineJoinStyle = .round
                    path.stroke()
                }
            case .ring:
                do {
                    let path = NSBezierPath(ovalIn: NSRect(x: 1.65, y: 1.65, width: 20.7, height: 20.7))
                    ink.setStroke()
                    path.lineWidth = 1.35 * contrastScale
                    path.lineCapStyle = .round
                    path.lineJoinStyle = .round
                    path.stroke()
                }
                do {
                    if !increasedContrast {
                        let path = CGMutablePath()
                        path.move(to: NSPoint(x: 3.03664, y: 6.825))
                        path.addCurve(to: NSPoint(x: 10.64905, y: 1.73855), control1: NSPoint(x: 4.64549, y: 4.03838), control2: NSPoint(x: 7.45887, y: 2.15854))
                        path.addCurve(to: NSPoint(x: 19.31856, y: 4.68144), control1: NSPoint(x: 13.83923, y: 1.31855), control2: NSPoint(x: 17.04329, y: 2.40618))
                        drawGradient(path, strokeWidth: 1.35 * contrastScale,
                                     colors: [accent.withAlphaComponent((increasedContrast ? 1 : 0.12)).cgColor, accent.withAlphaComponent((increasedContrast ? 1 : 1)).cgColor],
                                     locations: [0, 1], start: NSPoint(x: 3.0366, y: 6.825), end: NSPoint(x: 19.31856, y: 4.68144))
                    }
                }
                do {
                    let path = NSBezierPath()
                    path.move(to: NSPoint(x: 5.44, y: 8.8))
                    path.line(to: NSPoint(x: 6.03, y: 9.09))
                    path.move(to: NSPoint(x: 7.71, y: 6.12))
                    path.line(to: NSPoint(x: 8.1, y: 6.65))
                    path.move(to: NSPoint(x: 11, y: 4.78))
                    path.line(to: NSPoint(x: 11.09, y: 5.43))
                    path.move(to: NSPoint(x: 14.5, y: 5.14))
                    path.line(to: NSPoint(x: 14.27, y: 5.76))
                    path.move(to: NSPoint(x: 17.42, y: 7.12))
                    path.line(to: NSPoint(x: 16.93, y: 7.56))
                    path.move(to: NSPoint(x: 19.08, y: 10.23))
                    path.line(to: NSPoint(x: 18.44, y: 10.39))
                    ink.setStroke()
                    path.lineWidth = 1.25 * contrastScale
                    path.lineCapStyle = .round
                    path.lineJoinStyle = .round
                    path.stroke()
                }
                do {
                    let path = NSBezierPath()
                    path.move(to: NSPoint(x: 10.9, y: 10.7))
                    path.curve(to: NSPoint(x: 17.15, y: 6.85), controlPoint1: NSPoint(x: 12.4, y: 9.89), controlPoint2: NSPoint(x: 14.8, y: 8.24))
                    path.curve(to: NSPoint(x: 13.3, y: 13.1), controlPoint1: NSPoint(x: 15.76, y: 9.2), controlPoint2: NSPoint(x: 14.11, y: 11.6))
                    path.close()
                    accent.setFill()
                    path.fill()
                }
                do {
                    let path = NSBezierPath(ovalIn: NSRect(x: 10.12, y: 10.12, width: 3.76, height: 3.76))
                    accent.setFill()
                    path.fill()
                }
            case .lanes:
                do {
                    let path = NSBezierPath(roundedRect: NSRect(x: 2.2, y: 12.2, width: 4.2, height: 9.8), xRadius: 0.85, yRadius: 0.85)
                    ink.setStroke()
                    path.lineWidth = 1.15 * contrastScale
                    path.lineCapStyle = .round
                    path.lineJoinStyle = .round
                    path.stroke()
                }
                do {
                    let path = CGMutablePath()
                    path.addRoundedRect(in: CGRect(x: 9.6, y: 8.2, width: 4.2, height: 13.8), cornerWidth: 0.85, cornerHeight: 0.85)
                    drawGradient(path, strokeWidth: nil,
                                 colors: [accent.withAlphaComponent((increasedContrast ? 1 : 1)).cgColor, accent.withAlphaComponent((increasedContrast ? 1 : 0.38)).cgColor],
                                 locations: [0, 1], start: NSPoint(x: 0, y: 8.2), end: NSPoint(x: 0, y: 22))
                    stroke(path, color: ink, width: 1.15 * contrastScale)
                }
                do {
                    let path = CGMutablePath()
                    path.addRoundedRect(in: CGRect(x: 17, y: 3.2, width: 4.2, height: 18.8), cornerWidth: 0.85, cornerHeight: 0.85)
                    drawGradient(path, strokeWidth: nil,
                                 colors: [accent.withAlphaComponent((increasedContrast ? 1 : 1)).cgColor, accent.withAlphaComponent((increasedContrast ? 1 : 0.38)).cgColor],
                                 locations: [0, 1], start: NSPoint(x: 0, y: 3.2), end: NSPoint(x: 0, y: 22))
                    stroke(path, color: ink, width: 1.15 * contrastScale)
                }
            case .history:
                do {
                    let path = CGMutablePath()
                    path.move(to: NSPoint(x: 3.1, y: 16.2))
                    path.addLine(to: NSPoint(x: 9, y: 11.1))
                    path.addLine(to: NSPoint(x: 14.4, y: 14.6))
                    path.addLine(to: NSPoint(x: 21, y: 7.2))
                    path.addLine(to: NSPoint(x: 22, y: 7.2))
                    path.addLine(to: NSPoint(x: 22, y: 21.5))
                    path.addLine(to: NSPoint(x: 3.1, y: 21.5))
                    path.closeSubpath()
                    drawGradient(path, strokeWidth: nil,
                                 colors: [accent.withAlphaComponent(0.24).cgColor, accent.withAlphaComponent(0.1).cgColor, accent.withAlphaComponent(0).cgColor],
                                 locations: [0, 0.55, 1], start: NSPoint(x: 0, y: 7.2), end: NSPoint(x: 0, y: 21.5))
                }
                do {
                    let path = NSBezierPath()
                    path.move(to: NSPoint(x: 2, y: 2.5))
                    path.line(to: NSPoint(x: 2, y: 21.5))
                    path.line(to: NSPoint(x: 22, y: 21.5))
                    ink.setStroke()
                    path.lineWidth = 1.4 * contrastScale
                    path.lineCapStyle = .round
                    path.lineJoinStyle = .round
                    path.stroke()
                }
                do {
                    let path = NSBezierPath()
                    path.move(to: NSPoint(x: 3.1, y: 16.2))
                    path.line(to: NSPoint(x: 9, y: 11.1))
                    path.line(to: NSPoint(x: 14.4, y: 14.6))
                    path.line(to: NSPoint(x: 21, y: 7.2))
                    accent.setStroke()
                    path.lineWidth = 1.55 * contrastScale
                    path.lineCapStyle = .round
                    path.lineJoinStyle = .round
                    path.stroke()
                }
                do {
                    let path = NSBezierPath(ovalIn: NSRect(x: 7.1, y: 9.2, width: 3.8, height: 3.8))
                    accent.setFill()
                    path.fill()
                }
                do {
                    let path = NSBezierPath(ovalIn: NSRect(x: 8.2, y: 10.3, width: 1.6, height: 1.6))
                    ink.setFill()
                    path.fill()
                }
                do {
                    let path = NSBezierPath(ovalIn: NSRect(x: 12.5, y: 12.7, width: 3.8, height: 3.8))
                    accent.setFill()
                    path.fill()
                }
                do {
                    let path = NSBezierPath(ovalIn: NSRect(x: 13.6, y: 13.8, width: 1.6, height: 1.6))
                    ink.setFill()
                    path.fill()
                }
                do {
                    let path = NSBezierPath(ovalIn: NSRect(x: 19.1, y: 5.3, width: 3.8, height: 3.8))
                    accent.setFill()
                    path.fill()
                }
                do {
                    let path = NSBezierPath(ovalIn: NSRect(x: 20.2, y: 6.4, width: 1.6, height: 1.6))
                    ink.setFill()
                    path.fill()
                }
            case .runtime:
                do {
                    let path = NSBezierPath(ovalIn: NSRect(x: 1.65, y: 1.65, width: 20.7, height: 20.7))
                    ink.setStroke()
                    path.lineWidth = 1.35 * contrastScale
                    path.lineCapStyle = .round
                    path.lineJoinStyle = .round
                    path.stroke()
                }
                do {
                    if !increasedContrast {
                        let path = CGMutablePath()
                        path.move(to: NSPoint(x: 12, y: 12.3))
                        path.addLine(to: NSPoint(x: 12, y: 5.6))
                        path.addCurve(to: NSPoint(x: 18.7, y: 12.3), control1: NSPoint(x: 15.70031, y: 5.6), control2: NSPoint(x: 18.7, y: 8.59969))
                        path.closeSubpath()
                        drawGradient(path, strokeWidth: nil,
                                     colors: [accent.withAlphaComponent(0).cgColor, accent.withAlphaComponent(0.1).cgColor, accent.withAlphaComponent(0.22).cgColor],
                                     locations: [0, 0.55, 1], start: NSPoint(x: 12, y: 5.6), end: NSPoint(x: 18.7, y: 12.3))
                    }
                }
                do {
                    let path = NSBezierPath()
                    path.move(to: NSPoint(x: 12, y: 5.6))
                    path.line(to: NSPoint(x: 12, y: 12.3))
                    path.line(to: NSPoint(x: 18, y: 12.3))
                    accent.setStroke()
                    path.lineWidth = 1.95 * contrastScale
                    path.lineCapStyle = .round
                    path.lineJoinStyle = .round
                    path.stroke()
                }
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    static func sidebarImage(for icon: SidebarIcon, side: CGFloat, ink: NSColor,
                             accent: NSColor, increasedContrast: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            let transform = NSAffineTransform()
            transform.translateX(by: rect.minX, yBy: rect.maxY)
            transform.scaleX(by: rect.width / 24, yBy: -rect.height / 24)
            transform.concat()
            let contrastScale: CGFloat = increasedContrast ? 1.2 : 1
            switch icon {
            case .general:
                do {
                    let path = NSBezierPath()
                    path.move(to: NSPoint(x: 2.8, y: 5))
                    path.line(to: NSPoint(x: 21.2, y: 5))
                    path.move(to: NSPoint(x: 2.8, y: 12))
                    path.line(to: NSPoint(x: 21.2, y: 12))
                    path.move(to: NSPoint(x: 2.8, y: 19))
                    path.line(to: NSPoint(x: 21.2, y: 19))
                    ink.setStroke()
                    path.lineWidth = 1.35 * contrastScale
                    path.lineCapStyle = .round
                    path.lineJoinStyle = .round
                    path.stroke()
                }
                do {
                    let path = CGMutablePath()
                    path.move(to: NSPoint(x: 2.8, y: 5))
                    path.addLine(to: NSPoint(x: 7.2, y: 5))
                    path.move(to: NSPoint(x: 2.8, y: 12))
                    path.addLine(to: NSPoint(x: 16.8, y: 12))
                    path.move(to: NSPoint(x: 2.8, y: 19))
                    path.addLine(to: NSPoint(x: 11.4, y: 19))
                    drawGradient(path, strokeWidth: 1.45 * contrastScale,
                                 colors: [accent.withAlphaComponent((increasedContrast ? 1 : 0.12)).cgColor, accent.withAlphaComponent((increasedContrast ? 1 : 1)).cgColor],
                                 locations: [0, 1], start: NSPoint(x: 2.8, y: 0), end: NSPoint(x: 18, y: 0))
                }
                do {
                    let path = NSBezierPath(ovalIn: NSRect(x: 4.95, y: 2.75, width: 4.5, height: 4.5))
                    accent.setFill()
                    path.fill()
                    ink.setStroke()
                    path.lineWidth = 1.2 * contrastScale
                    path.lineCapStyle = .round
                    path.lineJoinStyle = .round
                    path.stroke()
                }
                do {
                    let path = NSBezierPath(ovalIn: NSRect(x: 14.55, y: 9.75, width: 4.5, height: 4.5))
                    accent.setFill()
                    path.fill()
                    ink.setStroke()
                    path.lineWidth = 1.2 * contrastScale
                    path.lineCapStyle = .round
                    path.lineJoinStyle = .round
                    path.stroke()
                }
                do {
                    let path = NSBezierPath(ovalIn: NSRect(x: 9.15, y: 16.75, width: 4.5, height: 4.5))
                    accent.setFill()
                    path.fill()
                    ink.setStroke()
                    path.lineWidth = 1.2 * contrastScale
                    path.lineCapStyle = .round
                    path.lineJoinStyle = .round
                    path.stroke()
                }
            case .display:
                do {
                    if !increasedContrast {
                        let path = CGMutablePath()
                        path.addRoundedRect(in: CGRect(x: 3.4, y: 8.3, width: 17.2, height: 11.1), cornerWidth: 1.6, cornerHeight: 1.6)
                        drawGradient(path, strokeWidth: nil,
                                     colors: [accent.withAlphaComponent(0.03).cgColor, accent.withAlphaComponent(0.24).cgColor],
                                     locations: [0, 1], start: NSPoint(x: 0, y: 8.3), end: NSPoint(x: 0, y: 19.4))
                    }
                }
                do {
                    let path = NSBezierPath(roundedRect: NSRect(x: 2.7, y: 3.8, width: 18.6, height: 16.4), xRadius: 2.4, yRadius: 2.4)
                    ink.setStroke()
                    path.lineWidth = 1.35 * contrastScale
                    path.lineCapStyle = .round
                    path.lineJoinStyle = .round
                    path.stroke()
                }
                do {
                    let path = NSBezierPath()
                    path.move(to: NSPoint(x: 3.1, y: 8.3))
                    path.line(to: NSPoint(x: 20.9, y: 8.3))
                    ink.setStroke()
                    path.lineWidth = 1.1 * contrastScale
                    path.lineCapStyle = .round
                    path.lineJoinStyle = .round
                    path.stroke()
                }
                do {
                    let path = NSBezierPath()
                    path.move(to: NSPoint(x: 5.4, y: 6.1))
                    path.line(to: NSPoint(x: 8.2, y: 6.1))
                    accent.setStroke()
                    path.lineWidth = 1.45 * contrastScale
                    path.lineCapStyle = .round
                    path.lineJoinStyle = .round
                    path.stroke()
                }
            case .modules:
                do {
                    let path = NSBezierPath(roundedRect: NSRect(x: 3, y: 3, width: 7, height: 7), xRadius: 1.5, yRadius: 1.5)
                    ink.setStroke()
                    path.lineWidth = 1.35 * contrastScale
                    path.lineCapStyle = .round
                    path.lineJoinStyle = .round
                    path.stroke()
                }
                do {
                    let path = CGMutablePath()
                    path.addRoundedRect(in: CGRect(x: 14, y: 3, width: 7, height: 7), cornerWidth: 1.5, cornerHeight: 1.5)
                    drawGradient(path, strokeWidth: nil,
                                 colors: [accent.withAlphaComponent((increasedContrast ? 1 : 1)).cgColor, accent.withAlphaComponent((increasedContrast ? 1 : 0.38)).cgColor],
                                 locations: [0, 1], start: NSPoint(x: 0, y: 3), end: NSPoint(x: 0, y: 10))
                    stroke(path, color: ink, width: 1.35 * contrastScale)
                }
                do {
                    let path = NSBezierPath(roundedRect: NSRect(x: 3, y: 14, width: 7, height: 7), xRadius: 1.5, yRadius: 1.5)
                    ink.setStroke()
                    path.lineWidth = 1.35 * contrastScale
                    path.lineCapStyle = .round
                    path.lineJoinStyle = .round
                    path.stroke()
                }
                do {
                    let path = NSBezierPath(roundedRect: NSRect(x: 14, y: 14, width: 7, height: 7), xRadius: 1.5, yRadius: 1.5)
                    ink.setStroke()
                    path.lineWidth = 1.35 * contrastScale
                    path.lineCapStyle = .round
                    path.lineJoinStyle = .round
                    path.stroke()
                }
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func drawGradient(_ path: CGPath, strokeWidth: CGFloat?,
                                     colors: [CGColor], locations: [CGFloat],
                                     start: CGPoint, end: CGPoint) {
        guard let context = NSGraphicsContext.current?.cgContext,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray,
                                        locations: locations) else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.addPath(path)
        if let strokeWidth {
            context.setLineWidth(strokeWidth)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.replacePathWithStrokedPath()
        }
        context.clip()
        context.drawLinearGradient(gradient, start: start, end: end,
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    private static func stroke(_ path: CGPath, color: NSColor, width: CGFloat) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.addPath(path)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(width)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.strokePath()
    }
}
