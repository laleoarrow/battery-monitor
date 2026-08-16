import AppKit

enum BatteryIcon {
    static let width: CGFloat = 23
    static let height: CGFloat = 14
    static let nativeWidth: CGFloat = 25
    static let nativeHeight: CGFloat = 14

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
            let nativeTintRole: TintRole = !pressed && mode == .low ? .lowPower : .template
            return RenderKey(
                percent: percent,
                showsBolt: snapshot.plugged,
                style: style,
                tintRole: nativeTintRole,
                appearanceName: nativeTintRole == .template ? "" : appearance.name.rawValue,
                increasedContrast: nativeTintRole == .template ? false : increasedContrast
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
            return nativeImage(for: snapshot, mode: mode, pressed: pressed)
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

    private enum NativeAdornment {
        case none
        case bolt
    }

    private static let nativeSystemAssets: (
        outline: NSImage,
        cap: NSImage,
        bolt: NSImage,
        boltMask: NSImage
    )? = {
        guard
            let bundle = Bundle(
                path: "/System/Library/CoreServices/ControlCenter.app"
            ),
            let outline = bundle.image(
                forResource: NSImage.Name("battery-outline")
            ),
            let cap = bundle.image(
                forResource: NSImage.Name("battery-cap")
            ),
            let bolt = bundle.image(
                forResource: NSImage.Name("battery-bolt")
            ),
            let boltMask = bundle.image(
                forResource: NSImage.Name("battery-bolt-mask")
            )
        else { return nil }
        return (outline, cap, bolt, boltMask)
    }()

    /// Control Center's menu extra is not an SF Symbol. It composes separate
    /// system-owned outline, cap and power-state masks around an exact fill.
    /// Loading those resources from the running OS keeps this presentation in
    /// step with macOS instead of shipping a copied approximation.
    private static func nativeImage(
        for snapshot: PowerSnapshot,
        mode: EnergyMode,
        pressed: Bool
    ) -> NSImage {
        let percent = min(max(snapshot.percent, 0), 100)
        let fillColor = nativeFillColor(mode: mode, pressed: pressed)
        let adornment: NativeAdornment = snapshot.plugged ? .bolt : .none
        guard let assets = nativeSystemAssets else {
            return nativeFallbackImage(for: snapshot, mode: mode, pressed: pressed)
        }

        let image = NSImage(
            size: NSSize(width: nativeWidth, height: nativeHeight), flipped: false
        ) { _ in
            guard let context = NSGraphicsContext.current else { return false }
            context.saveGraphicsState()

            let foregroundColor = fillColor == nil ? NSColor.black : NSColor.labelColor
            (fillColor ?? NSColor.black).setFill()
            let fillWidth = 19 * CGFloat(percent) / 100
            NSBezierPath(
                roundedRect: NSRect(x: 2, y: 3, width: fillWidth, height: 8),
                xRadius: min(2, fillWidth / 2),
                yRadius: 2
            ).fill()
            drawNativeAsset(
                assets.outline,
                in: NSRect(x: 0, y: 1, width: 23, height: 12),
                color: foregroundColor
            )
            drawNativeAsset(
                assets.cap,
                in: NSRect(x: 23, y: 1, width: 2, height: 12),
                color: foregroundColor
            )

            switch adornment {
            case .none:
                break
            case .bolt:
                let frame = NSRect(x: 6, y: 0, width: 11, height: 14)
                assets.boltMask.draw(
                    in: frame, from: .zero, operation: .destinationOut, fraction: 1
                )
                drawNativeAsset(assets.bolt, in: frame, color: foregroundColor)
            }
            context.restoreGraphicsState()
            return true
        }
        image.isTemplate = fillColor == nil
        return image
    }

    private static func nativeFillColor(mode: EnergyMode, pressed: Bool) -> NSColor? {
        guard !pressed, mode == .low else { return nil }
        return NSColor.systemYellow
    }

    private static func drawNativeAsset(
        _ asset: NSImage,
        in frame: NSRect,
        color: NSColor
    ) {
        guard let context = NSGraphicsContext.current else { return }
        context.saveGraphicsState()
        context.cgContext.beginTransparencyLayer(auxiliaryInfo: nil)
        asset.draw(
            in: frame, from: .zero, operation: .sourceOver, fraction: 1
        )
        context.compositingOperation = .sourceIn
        color.setFill()
        NSBezierPath(rect: frame).fill()
        context.cgContext.endTransparencyLayer()
        context.restoreGraphicsState()
    }

    /// Safe vector fallback for an unexpectedly missing Control Center asset.
    private static func nativeFallbackImage(
        for snapshot: PowerSnapshot,
        mode: EnergyMode,
        pressed: Bool
    ) -> NSImage {
        let fillColor = nativeFillColor(mode: mode, pressed: pressed)
        let adornment: NativeAdornment = snapshot.plugged ? .bolt : .none
        let image = NSImage(
            size: NSSize(width: nativeWidth, height: nativeHeight), flipped: false
        ) { _ in
            let foregroundColor = fillColor == nil ? NSColor.black : NSColor.labelColor
            drawNativeFallback(
                percent: snapshot.percent,
                adornment: adornment,
                foregroundColor: foregroundColor,
                fillColor: fillColor
            )
            return true
        }
        image.isTemplate = fillColor == nil
        return image
    }

    private static func drawNativeFallback(
        percent: Int,
        adornment: NativeAdornment,
        foregroundColor: NSColor,
        fillColor: NSColor?
    ) {
        let shell = NSRect(x: 0.5, y: 1.5, width: 22, height: 11)
        let body = NSBezierPath(roundedRect: shell, xRadius: 3.5, yRadius: 3.5)
        body.lineWidth = 1
        foregroundColor.setStroke()
        body.stroke()

        let cap = NSBezierPath()
        cap.move(to: NSPoint(x: 23, y: 5))
        cap.curve(
            to: NSPoint(x: 23, y: 9),
            controlPoint1: NSPoint(x: 25, y: 5.5),
            controlPoint2: NSPoint(x: 25, y: 8.5)
        )
        cap.close()
        foregroundColor.setFill()
        cap.fill()

        let clamped = CGFloat(min(max(percent, 0), 100)) / 100
        let fillWidth = 19 * clamped
        (fillColor ?? foregroundColor).setFill()
        NSBezierPath(
            roundedRect: NSRect(x: 2, y: 3, width: fillWidth, height: 8),
            xRadius: min(2, fillWidth / 2),
            yRadius: 2
        ).fill()

        let mark: NSBezierPath
        switch adornment {
        case .none:
            return
        case .bolt:
            mark = NSBezierPath()
            mark.move(to: NSPoint(x: 12.5, y: 13.5))
            mark.line(to: NSPoint(x: 6.5, y: 7))
            mark.line(to: NSPoint(x: 10, y: 7))
            mark.line(to: NSPoint(x: 9, y: 0.5))
            mark.line(to: NSPoint(x: 15.5, y: 7.5))
            mark.line(to: NSPoint(x: 12, y: 7.5))
            mark.close()
        }

        NSGraphicsContext.current?.compositingOperation = .destinationOut
        NSColor.black.setStroke()
        mark.lineWidth = 1.8
        mark.lineJoinStyle = .round
        mark.stroke()
        NSGraphicsContext.current?.compositingOperation = .sourceOver
        foregroundColor.setFill()
        mark.fill()
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
