import AppKit

enum BatteryIcon {
    static let width: CGFloat = 21
    static let height: CGFloat = 12

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
        let shell = NSRect(x: 0.5, y: 0.8, width: 18.6, height: 10.4)
        let body = NSBezierPath(roundedRect: shell, xRadius: 3.1, yRadius: 3.1)
        body.lineWidth = 0.9
        color.withAlphaComponent(0.38).setStroke()
        body.stroke()

        let cap = NSBezierPath()
        cap.move(to: NSPoint(x: 19.6, y: 4.2))
        cap.curve(to: NSPoint(x: 19.6, y: 7.8),
                  controlPoint1: NSPoint(x: 20.9, y: 4.6),
                  controlPoint2: NSPoint(x: 20.9, y: 7.4))
        cap.close()
        color.withAlphaComponent(0.38).setFill()
        cap.fill()

        let clamped = CGFloat(min(max(percent, 0), 100)) / 100
        let fill = NSRect(x: 1.9, y: 2.2, width: 15.8 * clamped, height: 7.6)
        color.setFill()
        NSBezierPath(roundedRect: fill, xRadius: 1.9, yRadius: 1.9).fill()

        // The system shows the bolt whenever a power source is attached, not
        // only while current is actually flowing into the battery. At 100% on
        // the adapter it still means "you are on wall power".
        guard plugged else { return }
        let bolt = NSBezierPath()
        bolt.move(to: NSPoint(x: 11.4, y: 10.0))
        bolt.line(to: NSPoint(x: 8.4, y: 5.9))
        bolt.line(to: NSPoint(x: 10.4, y: 5.9))
        bolt.line(to: NSPoint(x: 9.4, y: 2.7))
        bolt.line(to: NSPoint(x: 12.6, y: 7.0))
        bolt.line(to: NSPoint(x: 10.5, y: 7.0))
        bolt.close()

        // Knock a transparent ring around the bolt rather than drawing it in a
        // lighter colour. A template image carries only alpha, so a white bolt
        // on a black fill is the same opaque mass and vanishes entirely.
        NSGraphicsContext.current?.compositingOperation = .destinationOut
        NSColor.black.setStroke()
        bolt.lineWidth = 1.5
        bolt.lineJoinStyle = .round
        bolt.stroke()
        NSGraphicsContext.current?.compositingOperation = .sourceOver

        // Filled in the icon colour so it stays visible over the empty part of
        // the shell at low charge, where there is no fill to cut through.
        color.setFill()
        bolt.fill()
    }
}
