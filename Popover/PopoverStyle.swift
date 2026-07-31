import AppKit

enum PopoverStyle {
    static let width: CGFloat = 360
    static let contentWidth: CGFloat = 328

    static func stateColor(_ state: PowerState) -> NSColor {
        switch state {
        case .charging: return .systemGreen
        case .pluggedIdle: return .systemBlue
        case .onBattery: return .systemTeal
        case .mixedSupply: return .systemOrange
        }
    }

    static func stateTitle(_ state: PowerState) -> String {
        switch state {
        case .charging: return "正在充电"
        case .pluggedIdle: return "电源适配器"
        case .onBattery: return "使用电池"
        case .mixedSupply: return "混合供电"
        }
    }

    static func batteryFlowLabel(_ state: PowerState) -> String {
        switch state {
        case .charging: return "充入电池"
        case .pluggedIdle: return "电池静止"
        case .onBattery: return "电池输出"
        case .mixedSupply: return "电池补差"
        }
    }

    static func moduleBackground() -> CGColor {
        NSColor.controlBackgroundColor.withAlphaComponent(0.52).cgColor
    }

    static func configureModule(_ view: NSView) {
        view.wantsLayer = true
        view.layer?.backgroundColor = moduleBackground()
        view.layer?.cornerRadius = 12
        view.layer?.masksToBounds = true
    }

    static func watts(_ value: Double) -> String {
        String(format: "%.1f W", max(value, 0))
    }

    static func setWithoutAnimation(_ updates: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updates()
        CATransaction.commit()
    }

    /// Change a layer's timeline rate without changing its current local time.
    /// This keeps continuous animations from jumping on the 1 Hz data refresh.
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

extension NSColor {
    convenience init(rgb: UInt32, alpha: CGFloat = 1) {
        self.init(
            calibratedRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: alpha
        )
    }
}
