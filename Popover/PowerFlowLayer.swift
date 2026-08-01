import AppKit

/// Four power states collapse to two geometries. The only thing that moves the
/// nodes is whether the battery is discharging.
enum FlowLayout {
    case adapterLed   // adapter left-centre, system top-right, battery bottom-right
    case batteryLed   // adapter top-left, battery bottom-left, system centre-right
}

/// The single cubic every pipe is built from. Keeping the control points
/// explicit lets particles be seated analytically along the curve instead of
/// depending on an animation having started.
struct PipeGeometry {
    var start: CGPoint
    var control1: CGPoint
    var control2: CGPoint
    var end: CGPoint

    var path: CGPath {
        let path = CGMutablePath()
        path.move(to: start)
        path.addCurve(to: end, control1: control1, control2: control2)
        return path
    }

    func point(at t: CGFloat) -> CGPoint {
        let u = 1 - t
        return CGPoint(
            x: u * u * u * start.x + 3 * u * u * t * control1.x + 3 * u * t * t * control2.x + t * t * t * end.x,
            y: u * u * u * start.y + 3 * u * u * t * control1.y + 3 * u * t * t * control2.y + t * t * t * end.y
        )
    }
}

/// 36pt rounded well with an icon, a caption and a value. The well matters:
/// pipe ends are tucked under it, which is what hides the seam where two pipes
/// meet at one node.
final class FlowNodeView: NSView {
    static let boxSize: CGFloat = VisualEncoding.nodeSize   // 36
    static let stackWidth: CGFloat = 92

    private let box = NSView()
    private let icon = NSImageView()
    private let caption = NSTextField(labelWithString: "")
    private let value = NSTextField(labelWithString: "")

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        wantsLayer = true

        box.wantsLayer = true
        box.layer?.backgroundColor = PopoverStyle.well.cgColor
        box.layer?.borderColor = PopoverStyle.wellBorder.cgColor
        box.layer?.borderWidth = 0.5
        box.layer?.cornerRadius = 11
        box.layer?.cornerCurve = .continuous
        addSubview(box)

        icon.imageScaling = .scaleProportionallyUpOrDown
        box.addSubview(icon)

        caption.font = .systemFont(ofSize: 11, weight: .regular)
        caption.textColor = PopoverStyle.secondaryText
        caption.alignment = .center
        addSubview(caption)

        value.font = PopoverStyle.mono(12.5)
        value.textColor = PopoverStyle.primaryText
        value.alignment = .center
        addSubview(value)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        let size = Self.boxSize
        box.frame = NSRect(x: (bounds.width - size) / 2, y: 0, width: size, height: size)
        icon.frame = NSRect(x: 9, y: 9, width: size - 18, height: size - 18)
        caption.frame = NSRect(x: 0, y: size + 5, width: bounds.width, height: 14)
        value.frame = NSRect(x: 0, y: size + 20, width: bounds.width, height: 16)
    }

    func configure(symbol: String, caption text: String, value valueText: String, tint: NSColor) {
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: text)
        icon.contentTintColor = tint
        caption.stringValue = text
        value.stringValue = valueText
        box.layer?.borderColor = tint.withAlphaComponent(0.34).cgColor
    }

    /// Idle and disconnected nodes stay on screen at reduced opacity. Removing
    /// them makes the frame jump and hides the fact that the component is still
    /// physically there.
    func setPresence(_ alpha: CGFloat) { alphaValue = alpha }

    func setBreathing(_ on: Bool, color: NSColor) {
        box.layer?.removeAnimation(forKey: "breathe")
        guard on else { return }
        let pulse = CABasicAnimation(keyPath: "borderColor")
        pulse.fromValue = color.withAlphaComponent(0.18).cgColor
        pulse.toValue = color.withAlphaComponent(0.85).cgColor
        pulse.duration = 3.2
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        box.layer?.add(pulse, forKey: "breathe")
    }
}

/// One pipe: a dark trough, sparse round-capped pulses tinted by a horizontal
/// fade so they dim toward both ends, and sparks scattered across the
/// cross-section.
final class PipeBundle {
    let container = CALayer()

    private let trough = CAShapeLayer()
    private let pulse = CAShapeLayer()
    private let fade = CAGradientLayer()
    private var particles: [CALayer] = []
    private var geometry = PipeGeometry(start: .zero, control1: .zero, control2: .zero, end: .zero)

    init() {
        trough.fillColor = nil
        trough.lineCap = .butt          // flush where two pipes meet under a node
        trough.strokeColor = PopoverStyle.trough.cgColor
        container.addSublayer(trough)

        pulse.fillColor = nil
        pulse.lineCap = .round          // each pulse is a rounded capsule
        pulse.lineDashPattern = [34, 40]
        container.addSublayer(pulse)

        // Fades the run at both ends so pulses arrive and leave rather than
        // being clipped. Masks the whole container, which is far more reliable
        // than trying to mask a gradient with a dashed stroke.
        fade.startPoint = CGPoint(x: 0, y: 0.5)
        fade.endPoint = CGPoint(x: 1, y: 0.5)
        fade.colors = [NSColor.black.withAlphaComponent(0.25).cgColor,
                       NSColor.black.cgColor,
                       NSColor.black.cgColor,
                       NSColor.black.withAlphaComponent(0.25).cgColor]
        fade.locations = [0, 0.12, 0.88, 1]
    }

    func apply(geometry newGeometry: PipeGeometry, thickness: CGFloat, color: NSColor,
               bounds: CGRect, animated: Bool) {
        geometry = newGeometry
        let path = newGeometry.path

        let update = {
            self.trough.path = path
            self.trough.lineWidth = thickness
            self.trough.frame = bounds

            self.pulse.path = path
            self.pulse.lineWidth = thickness
            self.pulse.frame = bounds

            self.pulse.strokeColor = color.cgColor
            self.fade.frame = bounds
            self.container.mask = self.fade
            self.container.opacity = thickness > 0.5 ? 1 : 0
        }

        if animated {
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.45)
            update()
            CATransaction.commit()
        } else {
            PopoverStyle.setWithoutAnimation(update)
        }
    }

    func startFlow(period: CFTimeInterval) {
        guard pulse.animation(forKey: "flow") == nil else { return }
        let drift = CABasicAnimation(keyPath: "lineDashPhase")
        drift.fromValue = 0
        drift.toValue = -74           // one full dash period
        drift.duration = period
        drift.repeatCount = .infinity
        drift.isRemovedOnCompletion = false
        pulse.add(drift, forKey: "flow")
    }

    func stopFlow() {
        pulse.removeAllAnimations()
        particles.forEach { $0.removeAllAnimations() }
    }

    /// Particles ride the pipe at every power level, not just past saturation.
    /// Each takes a deterministic offset across the cross-section — putting them
    /// all on the centreline reads as a conveyor belt, not a current.
    func rebuildParticles(count: Int, thickness: CGFloat, color: NSColor,
                          period: CFTimeInterval, seed: UInt64, hot: Bool, animating: Bool) {
        particles.forEach { $0.removeFromSuperlayer() }
        particles.removeAll()
        guard count > 0, thickness > 0.5 else { return }

        var rng = SeededRNG(seed: seed)
        let tint = hot ? PopoverStyle.saturationParticle : NSColor.white
        let basePath = geometry.path

        for index in 0..<count {
            let offset = (rng.nextUnit() * 2 - 1) * thickness * 0.36
            let radius = (hot ? 1.3 : 0.85) + rng.nextUnit() * (hot ? 1.9 : 1.4)
            let duration = period * (1.4 + rng.nextUnit() * 1.1)
            let delay = rng.nextUnit() * duration

            let dot = CALayer()
            dot.bounds = CGRect(x: 0, y: 0, width: radius * 2, height: radius * 2)
            dot.cornerRadius = radius
            dot.backgroundColor = tint.cgColor
            dot.shadowColor = tint.cgColor
            dot.shadowOpacity = hot ? 0.95 : 0.6
            dot.shadowRadius = hot ? 4 + radius * 1.9 : 2 + radius
            dot.shadowOffset = .zero

            // Seat every dot on the curve up front, so they are visible even
            // when animations are off.
            let seat = geometry.point(at: (CGFloat(index) + 0.5) / CGFloat(count))
            PopoverStyle.setWithoutAnimation {
                dot.position = CGPoint(x: seat.x, y: seat.y + offset)
                dot.opacity = 1
            }
            container.addSublayer(dot)
            particles.append(dot)

            guard animating else { continue }
            var shift = CGAffineTransform(translationX: 0, y: offset)
            guard let ridePath = basePath.copy(using: &shift) else { continue }

            let ride = CAKeyframeAnimation(keyPath: "position")
            ride.path = ridePath
            ride.duration = duration
            ride.repeatCount = .infinity
            ride.calculationMode = .paced
            ride.timeOffset = delay
            ride.isRemovedOnCompletion = false

            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 1, 1, 0]
            fade.keyTimes = [0, 0.09, 0.86, 1]
            fade.duration = duration
            fade.repeatCount = .infinity
            fade.timeOffset = delay
            fade.isRemovedOnCompletion = false

            dot.add(ride, forKey: "ride")
            dot.add(fade, forKey: "fade")
        }
    }
}

final class PowerFlowView: PopoverSection {
    static let plotHeight: CGFloat = 176
    static let preferredHeight: CGFloat = plotHeight + PopoverStyle.sectionPadding * 2

    private static let leftX: CGFloat = 40
    private static let rightX: CGFloat = 288
    private static let topY: CGFloat = 38
    private static let midY: CGFloat = 77
    private static let bottomY: CGFloat = 116
    private static let startX: CGFloat = 53
    private static let endX: CGFloat = 275

    static let adapterLedPositions: [CGPoint] = [
        CGPoint(x: leftX, y: midY),     // adapter
        CGPoint(x: rightX, y: bottomY), // battery
        CGPoint(x: rightX, y: topY),    // system
    ]

    static let batteryLedPositions: [CGPoint] = [
        CGPoint(x: leftX, y: topY),     // adapter
        CGPoint(x: leftX, y: bottomY),  // battery
        CGPoint(x: rightX, y: midY),    // system
    ]

    /// Must be flipped: every node and pipe coordinate below is written with
    /// y growing downward. A plain NSView mirrors the whole diagram.
    private final class FlippedPlot: NSView {
        override var isFlipped: Bool { true }
    }

    private let plot = FlippedPlot()
    private let adapterNode = FlowNodeView()
    private let batteryNode = FlowNodeView()
    private let systemNode = FlowNodeView()
    private let idleConnection = CAShapeLayer()
    private let bundles = (0..<2).map { _ in PipeBundle() }

    private var animationsEnabled = false
    private var latest = PowerSnapshot()

    init() {
        super.init(height: Self.preferredHeight)
        plot.wantsLayer = true
        addSubview(plot)

        idleConnection.fillColor = nil
        idleConnection.lineWidth = 1.4
        idleConnection.lineDashPattern = [3, 6]
        idleConnection.strokeColor = NSColor(rgb: 0x5A5A66, alpha: 0.55).cgColor
        plot.layer?.addSublayer(idleConnection)
        bundles.forEach { plot.layer?.addSublayer($0.container) }

        [adapterNode, batteryNode, systemNode].forEach(plot.addSubview)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        plot.frame = NSRect(x: 0, y: PopoverStyle.sectionPadding,
                            width: bounds.width, height: Self.plotHeight)
        PopoverStyle.setWithoutAnimation {
            self.bundles.forEach { $0.container.frame = self.plot.bounds }
            self.idleConnection.frame = self.plot.bounds
        }
        // Recompute with real bounds. `update` can land before the first layout
        // pass, and everything derived from bounds — pipe geometry, the fade
        // mask — is nonsense until the plot has a size.
        update(snapshot: latest, animated: false)
    }

    private func layoutMode(for snapshot: PowerSnapshot) -> FlowLayout {
        snapshot.batteryW < -PowerSnapshot.epsilon ? .batteryLed : .adapterLed
    }

    /// Node coordinates depend on the layout alone, never on whether a given
    /// node takes part. Filling the gap left by a disconnected adapter puts the
    /// battery box straight on top of the adapter's caption.
    private func positions(for layout: FlowLayout) -> [CGPoint] {
        switch layout {
        case .adapterLed: return Self.adapterLedPositions
        case .batteryLed: return Self.batteryLedPositions
        }
    }

    private func applyPositions(for layout: FlowLayout) {
        for (node, point) in zip([adapterNode, batteryNode, systemNode], positions(for: layout)) {
            node.frame = NSRect(x: point.x - FlowNodeView.stackWidth / 2,
                                y: point.y - FlowNodeView.boxSize / 2,
                                width: FlowNodeView.stackWidth,
                                height: FlowNodeView.boxSize + 38)
        }
    }

    /// Every path uses the same cubic and the same number of control points,
    /// which is what lets CAShapeLayer interpolate between topologies instead
    /// of snapping.
    private func pipeGeometry(from startY: CGFloat, to endY: CGFloat) -> PipeGeometry {
        PipeGeometry(start: CGPoint(x: Self.startX, y: startY),
                     control1: CGPoint(x: 138, y: startY),
                     control2: CGPoint(x: 190, y: endY),
                     end: CGPoint(x: Self.endX, y: endY))
    }

    func update(snapshot: PowerSnapshot, animated: Bool) {
        latest = snapshot
        let layout = layoutMode(for: snapshot)
        applyPositions(for: layout)

        let color = PopoverStyle.stateColor(snapshot.state)
        let total = snapshot.totalInputW
        let period = 2.4 / Double(VisualEncoding.multiplier(total))
        let hot = total >= Double(VisualEncoding.wRef)
        let count = Int((2 + VisualEncoding.t(total) * 6 + VisualEncoding.over(total) * 5).rounded())

        configureNodes(snapshot: snapshot, color: color)

        switch layout {
        case .adapterLed:
            let charging = snapshot.batteryW > PowerSnapshot.epsilon
            let upperThickness = VisualEncoding.thickness(snapshot.systemW)
            let lowerThickness = charging ? VisualEncoding.thickness(abs(snapshot.batteryW)) : 0
            let cy = Self.midY

            // Tangency: the two pipes share an edge at the node centre, so a
            // split reads as one stream dividing rather than two sockets.
            let upperStart = charging ? cy - lowerThickness / 2 : cy
            let lowerStart = cy + upperThickness / 2

            configure(bundles[0], geometry: pipeGeometry(from: upperStart, to: Self.topY),
                      thickness: upperThickness, color: color, period: period,
                      particles: count, hot: hot, seed: 11, animated: animated)
            configure(bundles[1], geometry: pipeGeometry(from: lowerStart, to: Self.bottomY),
                      thickness: lowerThickness, color: color, period: period,
                      particles: charging ? count : 0, hot: hot, seed: 29, animated: animated)

            idleConnection.path = charging ? nil : pipeGeometry(from: cy, to: Self.bottomY).path

        case .batteryLed:
            let adapterActive = snapshot.adapterW > PowerSnapshot.epsilon
            let upperThickness = adapterActive ? VisualEncoding.thickness(snapshot.adapterW) : 0
            let lowerThickness = VisualEncoding.thickness(abs(snapshot.batteryW))
            let cy = Self.midY

            let upperEnd = cy - lowerThickness / 2
            let lowerEnd = adapterActive ? cy + upperThickness / 2 : cy

            configure(bundles[0], geometry: pipeGeometry(from: Self.topY, to: upperEnd),
                      thickness: upperThickness, color: PopoverStyle.blue, period: period,
                      particles: adapterActive ? count : 0, hot: hot, seed: 11, animated: animated)
            configure(bundles[1], geometry: pipeGeometry(from: Self.bottomY, to: lowerEnd),
                      thickness: lowerThickness,
                      color: adapterActive ? PopoverStyle.amber : color, period: period,
                      particles: count, hot: hot, seed: 29, animated: animated)

            idleConnection.path = nil
        }

        PopoverStyle.setWithoutAnimation {
            self.idleConnection.opacity = self.idleConnection.path == nil ? 0 : 1
        }
    }

    private func configure(_ bundle: PipeBundle, geometry: PipeGeometry, thickness: CGFloat,
                           color: NSColor, period: CFTimeInterval, particles: Int,
                           hot: Bool, seed: UInt64, animated: Bool) {
        bundle.apply(geometry: geometry, thickness: thickness, color: color,
                     bounds: plot.bounds, animated: animated)
        bundle.rebuildParticles(count: particles, thickness: thickness, color: color,
                                period: period, seed: seed, hot: hot, animating: animationsEnabled)
        if animationsEnabled { bundle.startFlow(period: period) }
    }

    private func configureNodes(snapshot: PowerSnapshot, color: NSColor) {
        let batterySymbol: String
        switch snapshot.percent {
        case ..<25: batterySymbol = "battery.25"
        case ..<50: batterySymbol = "battery.50"
        case ..<75: batterySymbol = "battery.75"
        default: batterySymbol = "battery.100"
        }

        systemNode.configure(symbol: "cpu", caption: "系统",
                             value: PopoverStyle.watts(snapshot.systemW), tint: PopoverStyle.neutral)
        systemNode.setPresence(1)
        systemNode.setBreathing(false, color: color)
        adapterNode.setBreathing(false, color: color)

        switch snapshot.state {
        case .charging:
            adapterNode.configure(symbol: "powerplug", caption: "适配器",
                                  value: PopoverStyle.watts(snapshot.adapterW), tint: color)
            adapterNode.setPresence(1)
            batteryNode.configure(symbol: "battery.100.bolt", caption: "充入电池",
                                  value: PopoverStyle.watts(snapshot.batteryW), tint: color)
            batteryNode.setPresence(1)
            batteryNode.setBreathing(false, color: color)

        case .pluggedIdle:
            adapterNode.configure(symbol: "powerplug", caption: "适配器",
                                  value: PopoverStyle.watts(snapshot.adapterW), tint: color)
            adapterNode.setPresence(1)
            batteryNode.configure(symbol: batterySymbol, caption: "电池 已满",
                                  value: "\(snapshot.percent) %", tint: color)
            batteryNode.setPresence(0.6)
            batteryNode.setBreathing(true, color: color)

        case .onBattery:
            adapterNode.configure(symbol: "powerplug.slash", caption: "适配器",
                                  value: "未连接", tint: PopoverStyle.neutral)
            adapterNode.setPresence(0.28)
            batteryNode.configure(symbol: batterySymbol, caption: "电池 \(snapshot.percent)%",
                                  value: PopoverStyle.watts(abs(snapshot.batteryW)), tint: color)
            batteryNode.setPresence(1)
            batteryNode.setBreathing(false, color: color)

        case .mixedSupply:
            adapterNode.configure(symbol: "powerplug", caption: "适配器",
                                  value: PopoverStyle.watts(snapshot.adapterW), tint: PopoverStyle.blue)
            adapterNode.setPresence(1)
            batteryNode.configure(symbol: batterySymbol, caption: "电池补差",
                                  value: PopoverStyle.watts(abs(snapshot.batteryW)), tint: PopoverStyle.amber)
            batteryNode.setPresence(1)
            batteryNode.setBreathing(false, color: color)
        }
    }

    func setAnimationsEnabled(_ enabled: Bool) {
        animationsEnabled = enabled
        if enabled {
            update(snapshot: latest, animated: false)
        } else {
            bundles.forEach { $0.stopFlow() }
        }
    }
}
