import AppKit
import QuartzCore

final class RingGaugeView: NSView {
    private let titleLabel = NSTextField(labelWithString: "环形仪表")
    private let percentLabel = NSTextField(labelWithString: "0%")
    private let systemTitle = NSTextField(labelWithString: "系统消耗")
    private let systemValue = NSTextField(labelWithString: "0.0 W")
    private let batteryTitle = NSTextField(labelWithString: "电池静止")
    private let batteryValue = NSTextField(labelWithString: "0.0 W")

    private let ringTrack = CAShapeLayer()
    private let chargeArc = CAShapeLayer()
    private let rotatingArc = CAShapeLayer()
    private var snapshot = PowerSnapshot()
    private var animationsEnabled = false

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        PopoverStyle.configureModule(self)

        titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        addSubview(titleLabel)

        percentLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        percentLabel.alignment = .center
        percentLabel.textColor = .labelColor
        addSubview(percentLabel)

        for label in [systemTitle, batteryTitle] {
            label.font = .systemFont(ofSize: 11, weight: .medium)
            label.textColor = .secondaryLabelColor
            addSubview(label)
        }
        for label in [systemValue, batteryValue] {
            label.font = .monospacedDigitSystemFont(ofSize: 14, weight: .medium)
            label.textColor = .labelColor
            label.alignment = .right
            addSubview(label)
        }

        for shape in [ringTrack, chargeArc, rotatingArc] {
            shape.fillColor = nil
            shape.lineCap = .round
            layer?.addSublayer(shape)
        }
        ringTrack.strokeColor = NSColor.separatorColor.withAlphaComponent(0.50).cgColor
        ringTrack.lineWidth = 7
        chargeArc.lineWidth = 7
        rotatingArc.lineWidth = 2.4
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        titleLabel.frame = NSRect(x: 12, y: 8, width: 100, height: 16)
        percentLabel.frame = NSRect(x: 19, y: 52, width: 58, height: 20)
        systemTitle.frame = NSRect(x: 108, y: 32, width: 90, height: 16)
        systemValue.frame = NSRect(x: 204, y: 29, width: 108, height: 20)
        batteryTitle.frame = NSRect(x: 108, y: 66, width: 90, height: 16)
        batteryValue.frame = NSRect(x: 204, y: 63, width: 108, height: 20)

        let center = CGPoint(x: 48, y: 62)
        let trackPath = CGMutablePath()
        trackPath.addArc(center: center, radius: 30, startAngle: -.pi / 2, endAngle: .pi * 1.5, clockwise: false)
        ringTrack.path = trackPath

        let progress = min(max(CGFloat(snapshot.percent) / 100, 0), 1)
        let chargePath = CGMutablePath()
        chargePath.addArc(center: center, radius: 30, startAngle: -.pi / 2, endAngle: -.pi / 2 + .pi * 2 * progress, clockwise: false)
        chargeArc.path = chargePath

        let spinnerPath = CGMutablePath()
        spinnerPath.addArc(center: center, radius: 23, startAngle: -.pi / 2, endAngle: .pi / 5, clockwise: false)
        rotatingArc.path = spinnerPath
        rotatingArc.bounds = bounds
        rotatingArc.anchorPoint = CGPoint(x: center.x / bounds.width, y: center.y / bounds.height)
        rotatingArc.position = center
    }

    func update(snapshot: PowerSnapshot) {
        self.snapshot = snapshot
        let color = PopoverStyle.stateColor(snapshot.state)
        let primaryColor: NSColor = snapshot.state == .mixedSupply ? .systemBlue : color
        percentLabel.stringValue = "\(snapshot.percent)" + "%"
        systemValue.stringValue = PopoverStyle.watts(snapshot.systemW)
        batteryValue.stringValue = PopoverStyle.watts(abs(snapshot.batteryW))
        batteryTitle.stringValue = batteryLabel(snapshot.state)
        systemValue.textColor = primaryColor
        batteryValue.textColor = snapshot.state == .mixedSupply ? .systemOrange : color
        chargeArc.strokeColor = color.cgColor
        rotatingArc.strokeColor = color.withAlphaComponent(0.82).cgColor
        needsLayout = true
        layoutSubtreeIfNeeded()
        if animationsEnabled {
            startRotation(totalInputW: snapshot.totalInputW)
        }
    }

    func setAnimationsEnabled(_ enabled: Bool) {
        animationsEnabled = enabled
        if enabled {
            startRotation(totalInputW: snapshot.totalInputW)
        } else {
            rotatingArc.removeAllAnimations()
        }
    }

    private func startRotation(totalInputW: Double) {
        if rotatingArc.animation(forKey: "rotation") == nil {
            let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
            rotation.fromValue = 0
            rotation.toValue = Double.pi * 2
            rotation.duration = 5.0
            rotation.repeatCount = .infinity
            rotation.timingFunction = CAMediaTimingFunction(name: .linear)
            rotatingArc.add(rotation, forKey: "rotation")
        }
        PopoverStyle.setAnimationSpeed(rotatingArc, multiplier: VisualEncoding.multiplier(totalInputW))
    }

    private func batteryLabel(_ state: PowerState) -> String {
        switch state {
        case .charging: return "充入电池"
        case .pluggedIdle: return "电池静止"
        case .onBattery: return "电池输出"
        case .mixedSupply: return "电池补差"
        }
    }
}
