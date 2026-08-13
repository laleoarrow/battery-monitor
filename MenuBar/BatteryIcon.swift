import AppKit

enum BatteryIcon {
    static let width: CGFloat = 23
    static let height: CGFloat = 14

    enum TintRole: Equatable {
        case template
        case lowPower
        case lowBattery
        case charging
    }

    /// Only these values can change the pixels in the menu-bar glyph. Live
    /// wattage, temperature and cycle-count samples deliberately do not, so a
    /// 1 Hz presentation refresh can keep the existing NSImage.
    struct RenderKey: Equatable {
        let percent: Int
        let showsBolt: Bool
        let style: Settings.MenuBarIconStyle
        let tintRole: TintRole
        let appearanceName: String
        let increasedContrast: Bool
    }

    static func renderKey(
        for snapshot: PowerSnapshot,
        mode: EnergyMode,
        pressed: Bool,
        style: Settings.MenuBarIconStyle,
        appearance: NSAppearance,
        increasedContrast: Bool
    ) -> RenderKey {
        let percent = min(max(snapshot.percent, 0), 100)
        if style == .native {
            // Public SF Symbols are template artwork. Wattson-specific tint,
            // appearance and pressed-state inputs therefore cannot alter them.
            let showsBolt = snapshot.state == .charging
            return RenderKey(
                percent: showsBolt ? 100 : nativeStaticLevel(for: percent),
                showsBolt: showsBolt,
                style: style,
                tintRole: .template,
                appearanceName: "",
                increasedContrast: false
            )
        }

        let tintRole: TintRole
        if pressed {
            tintRole = .template
        } else if mode == .low {
            tintRole = .lowPower
        } else if snapshot.percent <= 20 {
            tintRole = .lowBattery
        } else if snapshot.state == .charging {
            tintRole = .charging
        } else {
            tintRole = .template
        }
        return RenderKey(
            percent: percent,
            showsBolt: snapshot.plugged,
            style: style,
            tintRole: tintRole,
            appearanceName: appearance.name.rawValue,
            increasedContrast: increasedContrast
        )
    }

    /// Geometry never changes — only the fill colour does. `pressed` forces
    /// template rendering because a coloured image does not invert under the
    /// menu bar's selection highlight, and would sit unreadable on top of it.
    static func image(
        for snapshot: PowerSnapshot,
        mode: EnergyMode,
        pressed: Bool,
        style: Settings.MenuBarIconStyle
    ) -> NSImage {
        if style == .native {
            return nativeImage(for: snapshot)
        }

        let tint = color(for: snapshot, mode: mode)
        let useTemplate = pressed || tint == nil

        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            let stroke = useTemplate ? NSColor.black : tint!
            NSGraphicsContext.current?.cgContext.scaleBy(x: width / 22, y: height / 13)
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

    /// Uses Apple's public SF battery artwork at the nearest supported level.
    /// Battery symbols do not actually honor SF Symbols' variable-value API,
    /// so explicit static names avoid a misleading always-full glyph.
    private static func nativeImage(for snapshot: PowerSnapshot) -> NSImage {
        let percent = min(max(snapshot.percent, 0), 100)
        let level = nativeStaticLevel(for: percent)
        let charging = snapshot.state == .charging
        let canonicalName = nativeSymbolName(percent: percent, charging: charging)
        let aliasName = charging ? "battery.100.bolt" : "battery.\(level)"
        let symbol = NSImage(
            systemSymbolName: canonicalName,
            accessibilityDescription: nil
        ) ?? NSImage(
            systemSymbolName: aliasName,
            accessibilityDescription: nil
        )

        let configuration = NSImage.SymbolConfiguration(
            pointSize: 13,
            weight: .regular
        )
        if let configured = symbol?.withSymbolConfiguration(configuration) {
            configured.isTemplate = true
            return configured
        }
        return nativeFallbackImage(for: snapshot)
    }

    static func nativeStaticSymbolName(for percent: Int) -> String {
        let level = nativeStaticLevel(for: percent)
        return "battery.\(level)percent"
    }

    static func nativeSymbolName(percent: Int, charging: Bool) -> String {
        charging ? "battery.100percent.bolt" : nativeStaticSymbolName(for: percent)
    }

    private static func nativeStaticLevel(for percent: Int) -> Int {
        switch percent {
        case ...12: return 0
        case ...37: return 25
        case ...62: return 50
        case ...87: return 75
        default: return 100
        }
    }

    /// Safe fallback for an unexpectedly missing SF Symbol. This reuses the
    /// same macOS-derived proportions as Wattson's existing vector path, but
    /// deliberately drops all semantic colour so AppKit owns menu-bar tinting.
    private static func nativeFallbackImage(for snapshot: PowerSnapshot) -> NSImage {
        let charging = snapshot.state == .charging
        let percent = charging ? 100 : nativeStaticLevel(for: snapshot.percent)
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            NSGraphicsContext.current?.cgContext.scaleBy(x: width / 22, y: height / 13)
            draw(percent: percent, plugged: charging, color: .black)
            return true
        }
        image.isTemplate = true
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
