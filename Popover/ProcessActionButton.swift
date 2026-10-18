import AppKit

/// A small native action capsule; the module owns its shared pointer reflection.
final class ProcessActionButton: NSButton {
    private var sourceTintColor = PopoverStyle.blue
    private(set) var tintColor = PopoverStyle.blue

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        cell = ProcessActionButtonCell(textCell: "")
        setButtonType(.momentaryPushIn)
        title = ""
        imagePosition = .imageOnly
        imageScaling = .scaleNone
        controlSize = .mini
        isBordered = true
        if #available(macOS 26.0, *) {
            bezelStyle = .glass
            borderShape = .capsule
            tintProminence = .none
        } else {
            bezelStyle = .smallSquare
        }
        refreshAppearance()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isEnabled: Bool {
        didSet { refreshAppearance() }
    }

    func setTintColor(_ color: NSColor) {
        guard !sourceTintColor.isEqual(color) else { return }
        sourceTintColor = color
        refreshAppearance()
    }

    func refreshAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            tintColor = NSColor(cgColor: sourceTintColor.cgColor)!
            let glyph: NSColor
            if !isEnabled {
                glyph = .secondaryLabelColor
            } else if usesOpaqueAppearance {
                let rgb = tintColor.usingColorSpace(.sRGB)!
                let components = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent].map {
                    $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4)
                }
                let luminance = components[0] * 0.2126 + components[1] * 0.7152 + components[2] * 0.0722
                glyph = luminance > 0.179 ? .black : .white
            } else {
                glyph = PopoverStyle.isDark(effectiveAppearance)
                    ? tintColor.blended(withFraction: 0.88, of: .white)!
                    : tintColor.blended(withFraction: 0.68, of: .black)!
            }
            bezelColor = isEnabled && !usesOpaqueAppearance ? tintColor : nil
            if #available(macOS 26.0, *) {
                tintProminence = isEnabled && !usesOpaqueAppearance ? .secondary : .none
            }
            contentTintColor = glyph
            image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Force Quit")?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
                    .applying(.init(paletteColors: [glyph])))
        }
        needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
    }

    private var usesOpaqueAppearance: Bool {
        let reduceTransparency: Bool
#if DEBUG
        if let forced = ProcessInfo.processInfo.environment["WATTSON_FORCE_REDUCE_TRANSPARENCY"] {
            reduceTransparency = forced == "1"
        } else {
            reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        }
#else
        reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
#endif
        return reduceTransparency || PopoverStyle.isHighContrast(effectiveAppearance)
    }

    fileprivate func drawSurface(in frame: NSRect) {
        let path = NSBezierPath(roundedRect: frame.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: frame.height / 2, yRadius: frame.height / 2)
        let dark = PopoverStyle.isDark(effectiveAppearance)
        if !isEnabled || usesOpaqueAppearance {
            (isEnabled ? tintColor : PopoverStyle.well).setFill()
            path.fill()
            (isEnabled ? NSColor.labelColor : PopoverStyle.wellBorder).setStroke()
            path.lineWidth = 1
            path.stroke()
            return
        }
        let nativeGlass: Bool
        if #available(macOS 26.0, *) { nativeGlass = true } else { nativeGlass = false }
        let pressed = cell?.isHighlighted == true
        let start = tintColor.blended(withFraction: pressed ? 0.42 : 0.58, of: .white)!
            .withAlphaComponent(nativeGlass ? 0.30 : 1)
        let end = tintColor.withAlphaComponent(nativeGlass ? (pressed ? 0.50 : 0.42) : 1)
        NSGradient(starting: start, ending: end)?.draw(in: path, angle: 0)
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        let reflection = NSRect(x: frame.minX, y: frame.maxY - frame.height * 0.48,
                                width: frame.width, height: frame.height * 0.48)
        NSGradient(starting: .white.withAlphaComponent(0),
                   ending: .white.withAlphaComponent(dark ? 0.16 : 0.24))?
            .draw(in: reflection, angle: 90)
        NSGraphicsContext.restoreGraphicsState()
        NSColor.white.withAlphaComponent(dark ? 0.22 : 0.46).setStroke()
        path.lineWidth = 0.6
        path.stroke()
    }

    fileprivate var drawsNativeBezel: Bool {
        if #available(macOS 26.0, *) { return isEnabled && !usesOpaqueAppearance }
        return false
    }
}

private final class ProcessActionButtonCell: NSButtonCell {
    override func drawBezel(withFrame frame: NSRect, in controlView: NSView) {
        guard let button = controlView as? ProcessActionButton else { return }
        if button.drawsNativeBezel { super.drawBezel(withFrame: frame, in: controlView) }
        button.drawSurface(in: frame)
    }
}
