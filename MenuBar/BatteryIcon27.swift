import AppKit

/// The macOS 27 reference uses a filled body and optional inset digits. The
/// composition is reference-derived; adornment assets belong to the running OS.
enum BatteryIcon27 {
    static let width: CGFloat = 25
    static let height: CGFloat = 16

    enum Adornment: Equatable {
        case none, bolt, plug
    }

    static func adornment(for snapshot: PowerSnapshot) -> Adornment {
        guard snapshot.plugged else { return .none }
        return snapshot.isChargingPresentation ? .bolt : .plug
    }

    private static let systemAssets: (
        bolt: NSImage, boltMask: NSImage, plug: NSImage, plugMask: NSImage
    )? = {
        guard
            let bundle = Bundle(path: "/System/Library/CoreServices/ControlCenter.app"),
            let bolt = bundle.image(forResource: NSImage.Name("battery-bolt-large")),
            let boltMask = bundle.image(forResource: NSImage.Name("battery-bolt-mask-large")),
            let plug = bundle.image(forResource: NSImage.Name("battery-plug-large")),
            let plugMask = bundle.image(forResource: NSImage.Name("battery-plug-mask-large"))
        else { return nil }
        return (bolt, boltMask, plug, plugMask)
    }()

    static func image(
        for snapshot: PowerSnapshot,
        mode: EnergyMode,
        pressed: Bool,
        showsPercentage: Bool
    ) -> NSImage {
        let percent = min(max(snapshot.percent, 0), 100)
        let adornment = adornment(for: snapshot)
        let isLowPower = !pressed && mode == .low
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            guard let context = NSGraphicsContext.current else { return false }
            context.saveGraphicsState()
            defer { context.restoreGraphicsState() }

            let foreground: NSColor = isLowPower ? .labelColor : .black
            let body = NSRect(x: 0, y: 2, width: 23, height: 12)
            let bodyPath = NSBezierPath(roundedRect: body, xRadius: 3.5, yRadius: 3.5)
            foreground.withAlphaComponent(0.3).setFill()
            bodyPath.fill()
            foreground.withAlphaComponent(0.5).setFill()
            NSBezierPath(
                roundedRect: NSRect(x: 23, y: 6, width: 2, height: 4),
                xRadius: 1, yRadius: 1
            ).fill()

            context.saveGraphicsState()
            bodyPath.addClip()
            (isLowPower ? NSColor.systemYellow : foreground).setFill()
            NSBezierPath(rect: NSRect(
                x: body.minX, y: body.minY,
                width: body.width * CGFloat(percent) / 100, height: body.height
            )).fill()
            context.restoreGraphicsState()

            if showsPercentage {
                drawPercentage(percent, adornment: adornment, in: body)
            } else {
                drawLargeAdornment(adornment, foreground: foreground)
            }
            return true
        }
        image.isTemplate = !isLowPower
        return image
    }

    private static func drawPercentage(_ percent: Int, adornment: Adornment, in body: NSRect) {
        let numberArea = adornment == .none
            ? body : NSRect(x: body.minX, y: body.minY, width: 17.5, height: body.height)
        let text = NSAttributedString(string: String(percent), attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 8.5, weight: .semibold),
            .foregroundColor: NSColor.black,
        ])
        let size = text.size()
        NSGraphicsContext.current?.compositingOperation = .destinationOut
        text.draw(at: NSPoint(
            x: numberArea.midX - size.width / 2,
            y: numberArea.midY - size.height / 2
        ))
        if adornment != .none {
            // A small cutout preserves the inset number's width, including 100.
            drawAdornment(
                adornment, in: NSRect(x: 18.2, y: 4.8, width: 3.8, height: 6.4),
                color: .black, operation: .destinationOut
            )
        }
        NSGraphicsContext.current?.compositingOperation = .sourceOver
    }

    private static func drawLargeAdornment(_ adornment: Adornment, foreground: NSColor) {
        guard adornment != .none, let context = NSGraphicsContext.current else { return }
        let frame = NSRect(x: (23 - 12.5714) / 2, y: 0, width: 12.5714, height: 16)
        if let assets = systemAssets {
            let mask = adornment == .bolt ? assets.boltMask : assets.plugMask
            mask.draw(in: frame, from: .zero, operation: .destinationOut, fraction: 1)
        } else {
            context.saveGraphicsState()
            context.compositingOperation = .destinationOut
            let path = fallbackAdornment(adornment, in: frame)
            path.lineWidth = 1.8
            path.lineJoinStyle = .round
            NSColor.black.setStroke()
            path.stroke()
            context.restoreGraphicsState()
        }
        drawAdornment(adornment, in: frame, color: foreground, operation: .sourceOver)
    }

    private static func drawAdornment(
        _ adornment: Adornment,
        in frame: NSRect,
        color: NSColor,
        operation: NSCompositingOperation
    ) {
        guard let context = NSGraphicsContext.current else { return }
        context.saveGraphicsState()
        defer { context.restoreGraphicsState() }
        if let assets = systemAssets {
            let asset = adornment == .bolt ? assets.bolt : assets.plug
            context.compositingOperation = operation
            context.cgContext.beginTransparencyLayer(auxiliaryInfo: nil)
            asset.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1)
            context.compositingOperation = .sourceIn
            color.setFill()
            NSBezierPath(rect: frame).fill()
            context.cgContext.endTransparencyLayer()
        } else {
            context.compositingOperation = operation
            color.setFill()
            fallbackAdornment(adornment, in: frame).fill()
        }
    }

    /// Older systems have no macOS 27 catalog entries. These small vector marks
    /// keep the optional style available without bundling Apple's artwork.
    private static func fallbackAdornment(_ adornment: Adornment, in frame: NSRect) -> NSBezierPath {
        let path = NSBezierPath()
        switch adornment {
        case .none:
            return path
        case .bolt:
            path.move(to: NSPoint(x: 0.63, y: 1))
            path.line(to: NSPoint(x: 0.08, y: 0.43))
            path.line(to: NSPoint(x: 0.43, y: 0.43))
            path.line(to: NSPoint(x: 0.31, y: 0))
            path.line(to: NSPoint(x: 0.94, y: 0.59))
            path.line(to: NSPoint(x: 0.57, y: 0.59))
            path.close()
        case .plug:
            path.append(NSBezierPath(
                roundedRect: NSRect(x: 0.2, y: 0.3, width: 0.6, height: 0.46),
                xRadius: 0.18, yRadius: 0.18
            ))
            for x in [CGFloat(0.31), 0.59] {
                path.append(NSBezierPath(rect: NSRect(x: x, y: 0.7, width: 0.1, height: 0.3)))
            }
            path.append(NSBezierPath(rect: NSRect(x: 0.45, y: 0, width: 0.1, height: 0.4)))
        }
        var transform = AffineTransform()
        transform.translate(x: frame.minX, y: frame.minY)
        transform.scale(x: frame.width, y: frame.height)
        path.transform(using: transform)
        return path
    }
}
