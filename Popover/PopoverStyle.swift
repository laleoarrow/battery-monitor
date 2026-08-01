import AppKit

/// Values transcribed from the approved prototype. One dark surface divided by
/// hairlines — not four bordered cards, which stack edges and paddings on top
/// of each other and read as clutter.
enum PopoverStyle {
    static let width: CGFloat = 360
    static let contentWidth: CGFloat = 328
    static let sectionPadding: CGFloat = 13
    static let sideInset: CGFloat = 16

    static let surface = NSColor(rgb: 0x1C1C20)
    static let surfaceBorder = NSColor(rgb: 0x37373D)
    static let separator = NSColor(rgb: 0x2C2C31)
    static let well = NSColor(rgb: 0x2A2A30)
    static let wellBorder = NSColor(rgb: 0x3A3A42)
    static let trough = NSColor(rgb: 0x3A3A44)
    static let ringTrack = NSColor(rgb: 0x2E2E35)

    static let primaryText = NSColor(rgb: 0xEDEDEF)
    static let secondaryText = NSColor(rgb: 0x8E8E95)
    static let tertiaryText = NSColor(rgb: 0x6E6E76)

    static let green = NSColor(rgb: 0x30D158)
    static let blue = NSColor(rgb: 0x0A84FF)
    static let amber = NSColor(rgb: 0xFF9F0A)
    static let neutral = NSColor(rgb: 0xC7C7CC)
    static let red = NSColor(rgb: 0xFF453A)

    /// Real arcs are blue-white, and yellow is already spoken for by the menu
    /// bar icon's low-power state.
    static let saturationParticle = NSColor(rgb: 0xDBEAFF)

    static func stateColor(_ state: PowerState) -> NSColor {
        switch state {
        case .charging: return green
        case .pluggedIdle: return blue
        case .onBattery: return neutral
        case .mixedSupply: return amber
        }
    }

    static func stateTitle(_ state: PowerState) -> String {
        switch state {
        case .charging: return "充电中"
        case .pluggedIdle: return "插电已满"
        case .onBattery: return "电池供电"
        case .mixedSupply: return "混合供电 · 充电器功率不足"
        }
    }

    static func batteryFlowLabel(_ state: PowerState) -> String {
        switch state {
        case .charging: return "充入电池"
        case .pluggedIdle: return "已充满"
        case .onBattery: return "电池输出"
        case .mixedSupply: return "电池补差"
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
