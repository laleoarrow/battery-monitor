import AppKit

enum BatteryIcon {
    static let width: CGFloat = 22
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
        // Proportions taken from the system's own assets in
        // BatteryCenterUI.framework: outline 19x10, cap 2x10, bolt 9x12.
        // The bolt being taller than the shell is the point — it overflows the
        // outline top and bottom, which is what gives the system glyph its
        // weight. Drawing it inside the shell reads as undersized.
        let shell = NSRect(x: 0.5, y: 1.5, width: 18.0, height: 10.0)
        let body = NSBezierPath(roundedRect: shell, xRadius: 3.2, yRadius: 3.2)
        body.lineWidth = 1.0
        color.withAlphaComponent(0.5).setStroke()
        body.stroke()

        let cap = NSBezierPath()
        cap.move(to: NSPoint(x: 19.4, y: 4.6))
        cap.curve(to: NSPoint(x: 19.4, y: 8.4),
                  controlPoint1: NSPoint(x: 21.2, y: 5.2),
                  controlPoint2: NSPoint(x: 21.2, y: 7.8))
        cap.close()
        color.withAlphaComponent(0.5).setFill()
        cap.fill()

        let clamped = CGFloat(min(max(percent, 0), 100)) / 100
        let fill = NSRect(x: 2.0, y: 3.0, width: 15.0 * clamped, height: 7.0)
        color.setFill()
        NSBezierPath(roundedRect: fill, xRadius: 1.8, yRadius: 1.8).fill()

        guard plugged else { return }
        // 9 wide x 12 tall, centred on the shell and deliberately taller than it.
        let bolt = NSBezierPath()
        bolt.move(to: NSPoint(x: 11.2, y: 12.6))
        bolt.line(to: NSPoint(x: 5.2, y: 6.3))
        bolt.line(to: NSPoint(x: 8.6, y: 6.3))
        bolt.line(to: NSPoint(x: 7.4, y: 0.4))
        bolt.line(to: NSPoint(x: 14.2, y: 6.9))
        bolt.line(to: NSPoint(x: 10.8, y: 6.9))
        bolt.close()

        // Knock a transparent ring around the bolt rather than drawing it in a
        // lighter colour. A template image carries only alpha, so a white bolt
        // on a black fill is the same opaque mass and vanishes entirely.
        NSGraphicsContext.current?.compositingOperation = .destinationOut
        NSColor.black.setStroke()
        bolt.lineWidth = 1.8
        bolt.lineJoinStyle = .round
        bolt.stroke()
        NSGraphicsContext.current?.compositingOperation = .sourceOver

        color.setFill()
        bolt.fill()
    }
}
