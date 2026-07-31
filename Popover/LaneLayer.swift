import AppKit
import QuartzCore

final class LaneView: NSView {
    private let titleLabel = NSTextField(labelWithString: "功率泳道")
    private let systemTitle = NSTextField(labelWithString: "系统消耗")
    private let systemValue = NSTextField(labelWithString: "0.0 W")
    private let batteryTitle = NSTextField(labelWithString: "电池静止")
    private let batteryValue = NSTextField(labelWithString: "0.0 W")
    private let tracks = [CAShapeLayer(), CAShapeLayer()]
    private let sweeps = [CAShapeLayer(), CAShapeLayer()]
    private var snapshot = PowerSnapshot()
    private var animationsEnabled = false

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        PopoverStyle.configureModule(self)

        titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        addSubview(titleLabel)

        for label in [systemTitle, batteryTitle] {
            label.font = .systemFont(ofSize: 11, weight: .medium)
            label.textColor = .secondaryLabelColor
            addSubview(label)
        }
        for label in [systemValue, batteryValue] {
            label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            label.alignment = .right
            label.textColor = .labelColor
            addSubview(label)
        }

        for index in 0..<2 {
            let track = tracks[index]
            track.fillColor = nil
            track.strokeColor = NSColor.separatorColor.withAlphaComponent(0.45).cgColor
            track.lineWidth = 6
            track.lineCap = .round
            layer?.addSublayer(track)

            let sweep = sweeps[index]
            sweep.fillColor = nil
            sweep.lineWidth = 4
            sweep.lineCap = .round
            layer?.addSublayer(sweep)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        titleLabel.frame = NSRect(x: 12, y: 8, width: 100, height: 16)
        systemTitle.frame = NSRect(x: 12, y: 32, width: 76, height: 16)
        batteryTitle.frame = NSRect(x: 12, y: 64, width: 76, height: 16)
        systemValue.frame = NSRect(x: 254, y: 29, width: 62, height: 18)
        batteryValue.frame = NSRect(x: 254, y: 61, width: 62, height: 18)

        let ys: [CGFloat] = [40, 72]
        for index in 0..<2 {
            let trackPath = CGMutablePath()
            trackPath.move(to: CGPoint(x: 92, y: ys[index]))
            trackPath.addLine(to: CGPoint(x: 246, y: ys[index]))
            tracks[index].path = trackPath
            tracks[index].frame = bounds

            let sweepPath = CGMutablePath()
            sweepPath.move(to: CGPoint(x: 92, y: ys[index]))
            sweepPath.addLine(to: CGPoint(x: 126, y: ys[index]))
            sweeps[index].path = sweepPath
            sweeps[index].frame = bounds
        }
    }

    func update(snapshot: PowerSnapshot) {
        self.snapshot = snapshot
        let color = PopoverStyle.stateColor(snapshot.state)
        let primaryColor: NSColor = snapshot.state == .mixedSupply ? .systemBlue : color
        systemValue.stringValue = PopoverStyle.watts(snapshot.systemW)
        batteryTitle.stringValue = batteryLabel(snapshot.state)
        batteryValue.stringValue = PopoverStyle.watts(abs(snapshot.batteryW))
        systemValue.textColor = primaryColor
        batteryValue.textColor = snapshot.state == .mixedSupply ? .systemOrange : color
        sweeps[0].strokeColor = primaryColor.cgColor
        sweeps[1].strokeColor = (snapshot.state == .mixedSupply ? NSColor.systemOrange : color).cgColor
        sweeps[1].opacity = abs(snapshot.batteryW) <= PowerSnapshot.epsilon ? 0 : 1
        needsLayout = true
        layoutSubtreeIfNeeded()
        if animationsEnabled {
            startSweeps(totalInputW: snapshot.totalInputW)
        }
    }

    func setAnimationsEnabled(_ enabled: Bool) {
        animationsEnabled = enabled
        if enabled {
            startSweeps(totalInputW: snapshot.totalInputW)
        } else {
            sweeps.forEach { $0.removeAllAnimations() }
        }
    }

    private func startSweeps(totalInputW: Double) {
        for (index, sweep) in sweeps.enumerated() {
            guard sweep.opacity > 0 else {
                sweep.removeAnimation(forKey: "sweep")
                continue
            }
            if sweep.animation(forKey: "sweep") == nil {
                let motion = CABasicAnimation(keyPath: "transform.translation.x")
                motion.fromValue = 0
                motion.toValue = 120
                motion.duration = 2.4
                motion.timeOffset = Double(index) * 0.37
                motion.repeatCount = .infinity
                motion.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                sweep.add(motion, forKey: "sweep")
            }
            PopoverStyle.setAnimationSpeed(sweep, multiplier: VisualEncoding.multiplier(totalInputW))
        }
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
