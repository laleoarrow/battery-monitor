import AppKit

enum BatteryIcon {
    static let width: CGFloat = 25
    static let height: CGFloat = 13

    /// Geometry never changes — only the fill colour does. `pressed` forces
    /// template rendering because a coloured image does not invert under the
    /// menu bar's selection highlight, and would sit unreadable on top of it.
    static func image(for snapshot: PowerSnapshot, mode: EnergyMode, pressed: Bool) -> NSImage {
        let tint = color(for: snapshot, mode: mode)
        let useTemplate = pressed || tint == nil

        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            let stroke = useTemplate ? NSColor.black : tint!
            draw(percent: snapshot.percent, plugged: snapshot.plugged, color: stroke)
            return true
        }

        if pressed {
            image.isTemplate = true
        } else if tint == nil {
            image.isTemplate = true
        } else {
            image.isTemplate = false
        }
        return image
    }

    /// Priority: low power mode, then low battery, then charging. First hit wins.
    private static func color(for snapshot: PowerSnapshot, mode: EnergyMode) -> NSColor? {
        if mode == .low { return .systemYellow }
        if snapshot.percent <= 20 { return .systemRed }
        if snapshot.state == .charging { return .systemGreen }
        return nil
    }

    private static func draw(percent: Int, plugged: Bool, color: NSColor) {
        // Proportions traced against the system battery: a fuller shell with a
        // solid outline. The earlier glyph was narrower and drawn at 0.38 alpha,
        // which read as thin and washed out next to it.
        let shell = NSRect(x: 0.5, y: 1.1, width: 21.6, height: 10.8)
        let body = NSBezierPath(roundedRect: shell, xRadius: 3.4, yRadius: 3.4)
        body.lineWidth = 1.0
        color.withAlphaComponent(0.55).setStroke()
        body.stroke()

        let cap = NSBezierPath()
        cap.move(to: NSPoint(x: 23.0, y: 4.6))
        cap.curve(to: NSPoint(x: 23.0, y: 8.4),
                  controlPoint1: NSPoint(x: 24.5, y: 5.1),
                  controlPoint2: NSPoint(x: 24.5, y: 7.9))
        cap.close()
        color.withAlphaComponent(0.55).setFill()
        cap.fill()

        let clamped = CGFloat(min(max(percent, 0), 100)) / 100
        let fill = NSRect(x: 2.0, y: 2.6, width: 18.6 * clamped, height: 7.8)
        color.setFill()
        NSBezierPath(roundedRect: fill, xRadius: 2.0, yRadius: 2.0).fill()

        guard plugged else { return }
        let bolt = NSBezierPath()
        bolt.move(to: NSPoint(x: 13.4, y: 11.6))
        bolt.line(to: NSPoint(x: 8.3, y: 5.5))
        bolt.line(to: NSPoint(x: 11.2, y: 5.5))
        bolt.line(to: NSPoint(x: 9.7, y: 1.4))
        bolt.line(to: NSPoint(x: 14.8, y: 7.5))
        bolt.line(to: NSPoint(x: 11.9, y: 7.5))
        bolt.close()

        // Knock a transparent ring around the bolt rather than drawing it in a
        // lighter colour. A template image carries only alpha, so a white bolt
        // on a black fill is the same opaque mass and vanishes entirely.
        NSGraphicsContext.current?.compositingOperation = .destinationOut
        NSColor.black.setStroke()
        bolt.lineWidth = 1.7
        bolt.lineJoinStyle = .round
        bolt.stroke()
        NSGraphicsContext.current?.compositingOperation = .sourceOver

        // Filled in the icon colour so it stays visible over the empty part of
        // the shell at low charge, where there is no fill to cut through.
        color.setFill()
        bolt.fill()
    }
}
