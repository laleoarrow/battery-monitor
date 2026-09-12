import AppKit

/// Geometry from the approved prototype. One adaptive surface divided by
/// hairlines — not four bordered cards, which stack edges and paddings on top
/// of each other and read as clutter.
enum PopoverStyle {
    static let width: CGFloat = 360
    static let sectionPadding: CGFloat = 13
    static let sideInset: CGFloat = 16
    static let contentWidth: CGFloat = width - 2 * sideInset

    static let surface = NSColor.windowBackgroundColor
    static let separator = adaptive(light: 0xD2D2D8, dark: 0x2C2C31,
                                    contrastLight: 0x73737B, contrastDark: 0x8E8E95)
    static let well = adaptive(light: 0xE4E4E9, dark: 0x2A2A30)
    static let wellBorder = adaptive(light: 0xB4B4BC, dark: 0x3A3A42,
                                     contrastLight: 0x63636B, contrastDark: 0xA0A0A8)
    static let trough = adaptive(light: 0xC4C4CE, dark: 0x3A3A44,
                                 contrastLight: 0x8C8C96, contrastDark: 0x777783)
    static let ringTrack = adaptive(light: 0xD7D7DE, dark: 0x2E2E35)

    static let primaryText = NSColor.labelColor
    static let secondaryText = NSColor.secondaryLabelColor
    static let tertiaryText = NSColor.secondaryLabelColor

    // Preserve the power-state meanings. Deeper light-mode colors keep small
    // readings legible without changing geometry or adding decorative fills.
    static let green = adaptive(light: 0x18783A, dark: 0x30D158)
    static let blue = adaptive(light: 0x0064CF, dark: 0x0A84FF)
    static let amber = adaptive(light: 0x9B5700, dark: 0xFF9F0A)
    static let neutral = adaptive(light: 0x565662, dark: 0xC7C7CC)
    static let red = adaptive(light: 0xC72528, dark: 0xFF453A)

    /// Real arcs are blue-white, and yellow is already spoken for by the menu
    /// bar icon's low-power state.
    static let saturationParticle = NSColor(rgb: 0xDBEAFF)

    static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    static func isHighContrast(_ appearance: NSAppearance) -> Bool {
#if DEBUG
        if let forced = ProcessInfo.processInfo.environment["WATTSON_FORCE_INCREASE_CONTRAST"] {
            return forced == "1"
        }
#endif
        if NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast { return true }
        let match = appearance.bestMatch(from: [
            .aqua, .darkAqua, .accessibilityHighContrastAqua,
            .accessibilityHighContrastDarkAqua,
        ])
        return match == .accessibilityHighContrastAqua
            || match == .accessibilityHighContrastDarkAqua
    }

    private static func adaptive(light: UInt32, dark: UInt32,
                                 contrastLight: UInt32? = nil,
                                 contrastDark: UInt32? = nil) -> NSColor {
        let lightColor = NSColor(rgb: light)
        let darkColor = NSColor(rgb: dark)
        let lightContrast = NSColor(rgb: contrastLight ?? light)
        let darkContrast = NSColor(rgb: contrastDark ?? dark)
        return NSColor(name: nil) { appearance in
            if isHighContrast(appearance) {
                return isDark(appearance) ? darkContrast : lightContrast
            }
            return isDark(appearance) ? darkColor : lightColor
        }
    }

    static func stateColor(_ state: PowerState) -> NSColor {
        switch state {
        case .charging: return green
        case .pluggedIdle: return blue
        case .onBattery: return neutral
        case .mixedSupply: return amber
        }
    }

    static func stateTitle(_ snapshot: PowerSnapshot) -> String {
        switch snapshot.state {
        case .charging: return "Charging"
        case .pluggedIdle:
            return snapshot.percent >= 100 ? "Plugged In · Full" : "Plugged In · Not Charging"
        case .onBattery: return "On Battery"
        case .mixedSupply: return "Mixed Power · Adapter Limited"
        }
    }

    static func batteryFlowLabel(_ snapshot: PowerSnapshot) -> String {
        switch snapshot.state {
        case .charging: return "To Battery"
        case .pluggedIdle: return snapshot.percent >= 100 ? "Full" : "Idle"
        case .onBattery: return "Battery Output"
        case .mixedSupply: return "Battery Assist"
        }
    }

    static func watts(_ value: Double) -> String {
        String(format: "%.1f W", max(value, 0))
    }

    static func mono(_ size: CGFloat, _ weight: NSFont.Weight = .medium) -> NSFont {
        .monospacedDigitSystemFont(ofSize: size, weight: weight)
    }

    static func setWithoutAnimation(_ updates: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updates()
        CATransaction.commit()
    }

    /// Change a layer's timeline rate without changing its current local time,
    /// so continuous animations do not jump on the 1 Hz data refresh.
    static func setAnimationSpeed(_ layer: CALayer, multiplier: CGFloat) {
        let target = Float(multiplier)
        guard abs(layer.speed - target) > 0.005 else { return }
        let mediaTime = CACurrentMediaTime()
        let localTime = layer.convertTime(mediaTime, from: nil)
        let parentTime = layer.superlayer?.convertTime(mediaTime, from: nil) ?? mediaTime
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.speed = target
        layer.timeOffset = localTime
        layer.beginTime = parentTime
        CATransaction.commit()
    }
}

/// A section of the single popover surface. Carries a top hairline instead of
/// a card border.
class PopoverSection: NSView {
    private let topLine = CALayer()

    override var isFlipped: Bool { true }

    init(height: CGFloat, showsSeparator: Bool = true) {
        super.init(frame: NSRect(x: 0, y: 0, width: PopoverStyle.contentWidth, height: height))
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        if showsSeparator {
            topLine.backgroundColor = PopoverStyle.separator.cgColor
            layer?.addSublayer(topLine)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
    }

    /// CGColors are resolved values, unlike NSTextField's dynamic NSColors.
    /// Refresh them in this view's appearance, not the application's global one.
    func refreshAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            PopoverStyle.setWithoutAnimation {
                self.topLine.backgroundColor = PopoverStyle.separator.cgColor
            }
        }
    }

    override func layout() {
        super.layout()
        PopoverStyle.setWithoutAnimation {
            self.topLine.frame = CGRect(x: 0, y: 0, width: self.bounds.width, height: 0.5)
        }
    }

    func label(_ text: String, size: CGFloat, color: NSColor, mono: Bool = false,
               align: NSTextAlignment = .left) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = mono ? PopoverStyle.mono(size) : .systemFont(ofSize: size, weight: .regular)
        field.textColor = color
        field.alignment = align
        addSubview(field)
        return field
    }
}

extension NSColor {
    convenience init(rgb: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: alpha
        )
    }
}

/// Deterministic so particle offsets stay put across redraws. A live RNG would
/// make every 1 Hz refresh jump the whole particle field.
struct SeededRNG {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &* 6364136223846793005 &+ 1442695040888963407
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    mutating func nextUnit() -> CGFloat {
        CGFloat(next() % 100_000) / 100_000
    }
}
