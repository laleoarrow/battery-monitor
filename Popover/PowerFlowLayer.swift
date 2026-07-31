import AppKit
import QuartzCore

private enum FlowLayout {
    case adapterLed
    case batteryLed
}

private enum NodeActivity {
    case active
    case idle
    case discharging
    case disconnected
}

private struct FlowPositions {
    let adapter: CGPoint
    let battery: CGPoint
    let system: CGPoint
}

private struct PipeConfiguration {
    let start: CGPoint
    let end: CGPoint
    let watts: Double
    let color: NSColor
    let active: Bool
}

private final class PipeLayers {
    let track = CAShapeLayer()
    let pulse = CAShapeLayer()
    let mask = CAShapeLayer()
    let particles = CAEmitterLayer()

    init() {
        track.fillColor = nil
        track.lineCap = .butt

        pulse.fillColor = nil
        pulse.lineCap = .round
        pulse.lineDashPattern = [12, 18]

        mask.fillColor = nil
        mask.strokeColor = NSColor.black.cgColor
        mask.lineCap = .butt
        pulse.mask = mask

        particles.emitterShape = .point
        particles.emitterMode = .points
        particles.masksToBounds = false
    }

    func install(in root: CALayer) {
        root.addSublayer(track)
        root.addSublayer(pulse)
        root.addSublayer(particles)
    }

    func setFrame(_ frame: CGRect) {
        track.frame = frame
        pulse.frame = frame
        mask.frame = frame
        particles.frame = frame
    }

    func stopAnimations() {
        track.removeAllAnimations()
        pulse.removeAllAnimations()
        mask.removeAllAnimations()
        particles.removeAllAnimations()
        particles.sublayers?.forEach {
            $0.removeAllAnimations()
            $0.removeFromSuperlayer()
        }
    }
}

private final class PowerNodeView: NSView {
    private let imageView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let halo = CAShapeLayer()

    override var isFlipped: Bool { true }

    init(title: String, symbol: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: 72, height: 56))
        wantsLayer = true

        halo.fillColor = NSColor.systemBlue.withAlphaComponent(0.25).cgColor
        halo.path = CGPath(ellipseIn: CGRect(x: 18, y: 0, width: 36, height: 36), transform: nil)
        layer?.addSublayer(halo)

        imageView.frame = NSRect(x: 18, y: 0, width: 36, height: 36)
        imageView.imageScaling = .scaleProportionallyDown
        imageView.contentTintColor = .labelColor
        addSubview(imageView)

        titleLabel.frame = NSRect(x: 0, y: 39, width: 72, height: 16)
        titleLabel.alignment = .center
        titleLabel.font = .systemFont(ofSize: 10, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.stringValue = title
        addSubview(titleLabel)
        setSymbol(symbol)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setSymbol(_ name: String) {
        let config = NSImage.SymbolConfiguration(pointSize: 24, weight: .medium)
        imageView.image = NSImage(systemSymbolName: name, accessibilityDescription: titleLabel.stringValue)?
            .withSymbolConfiguration(config)
    }

    func setTint(_ color: NSColor) {
        imageView.contentTintColor = color
    }

    func setActivity(_ activity: NodeActivity, animated: Bool) {
        stopAnimations()
        halo.opacity = 0

        switch activity {
        case .active:
            alphaValue = 1
        case .idle:
            alphaValue = 0.60
            guard animated else { return }
            halo.opacity = 0.48
            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 0.90
            scale.toValue = 1.55
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.48
            fade.toValue = 0
            let group = CAAnimationGroup()
            group.animations = [scale, fade]
            group.duration = 3.2
            group.repeatCount = .infinity
            group.timingFunction = CAMediaTimingFunction(name: .easeOut)
            halo.add(group, forKey: "idleBreathing")
        case .discharging:
            alphaValue = 1
            guard animated else { return }
            imageView.wantsLayer = true
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 1
            pulse.toValue = 0.62
            pulse.duration = 1.3
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            imageView.layer?.add(pulse, forKey: "batteryDischarging")
        case .disconnected:
            alphaValue = 0.28
        }
    }

    func stopAnimations() {
        layer?.removeAllAnimations()
        halo.removeAllAnimations()
        imageView.layer?.removeAllAnimations()
    }
}

private struct SeededGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func nextUnit() -> CGFloat {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat((state >> 11) & 0x1F_FFFF) / CGFloat(0x1F_FFFF)
    }
}

final class PowerFlowView: NSView {
    private static let particleSeed: UInt64 = 0x57415454534F4E
    private static let nodeSize = VisualEncoding.nodeSize
    private static let adapterLedPositions = FlowPositions(
        adapter: CGPoint(x: 44, y: 66),
        battery: CGPoint(x: 284, y: 96),
        system: CGPoint(x: 284, y: 38)
    )
    private static let batteryLedPositions = FlowPositions(
        adapter: CGPoint(x: 44, y: 38),
        battery: CGPoint(x: 44, y: 96),
        system: CGPoint(x: 284, y: 66)
    )

    private let titleLabel = NSTextField(labelWithString: "能量流")
    private let adapterNode = PowerNodeView(title: "适配器", symbol: "powerplug")
    private let batteryNode = PowerNodeView(title: "电池", symbol: "battery.100")
    private let systemNode = PowerNodeView(title: "系统", symbol: "desktopcomputer")
    private lazy var nodeViews = [adapterNode, batteryNode, systemNode]
    private lazy var pipeLayers: [PipeLayers] = (0..<2).map { _ in PipeLayers() }
    private let idleConnection = CAShapeLayer()

    private var currentSnapshot = PowerSnapshot()
    private var animationsEnabled = false
    private var hasSnapshot = false

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        PopoverStyle.configureModule(self)

        titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        addSubview(titleLabel)

        pipeLayers.forEach { $0.install(in: layer!) }
        idleConnection.fillColor = nil
        idleConnection.strokeColor = NSColor.tertiaryLabelColor.cgColor
        idleConnection.lineWidth = 1.4
        idleConnection.lineDashPattern = [3, 6]
        idleConnection.lineCap = .butt
        idleConnection.opacity = 0
        layer?.addSublayer(idleConnection)
        nodeViews.forEach(addSubview)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        titleLabel.frame = NSRect(x: 12, y: 8, width: 100, height: 16)
        pipeLayers.forEach { $0.setFrame(bounds) }
        idleConnection.frame = bounds
        if hasSnapshot {
            render(currentSnapshot, animated: false)
        }
    }

    func update(snapshot: PowerSnapshot, animated: Bool) {
        currentSnapshot = snapshot
        hasSnapshot = true
        render(snapshot, animated: animated && animationsEnabled)
    }

    func setAnimationsEnabled(_ enabled: Bool) {
        animationsEnabled = enabled
        if enabled {
            guard hasSnapshot else { return }
            render(currentSnapshot, animated: false)
        } else {
            pipeLayers.forEach { $0.stopAnimations() }
            nodeViews.forEach { $0.stopAnimations() }
            idleConnection.removeAllAnimations()
        }
    }

    private func render(_ snapshot: PowerSnapshot, animated: Bool) {
        guard bounds.width > 0 else { return }
        let layout: FlowLayout = snapshot.batteryW < -PowerSnapshot.epsilon ? .batteryLed : .adapterLed
        let positions = positions(for: layout)
        positionNodes(positions, animated: animated)
        configureNodes(snapshot, animated: animationsEnabled)

        let configurations = pipeConfigurations(snapshot, layout: layout, positions: positions)
        for (index, configuration) in configurations.enumerated() {
            apply(configuration, to: pipeLayers[index], totalInputW: snapshot.totalInputW, animated: animated)
        }

        let idlePath = pipePath(start: positions.adapter, end: positions.battery)
        applyPath(idlePath, to: idleConnection, animated: animated)
        idleConnection.opacity = snapshot.state == .pluggedIdle ? 0.55 : 0
    }

    private func positions(for layout: FlowLayout) -> FlowPositions {
        switch layout {
        case .adapterLed: return Self.adapterLedPositions
        case .batteryLed: return Self.batteryLedPositions
        }
    }

    private func positionNodes(_ positions: FlowPositions, animated: Bool) {
        let pairs = [
            (adapterNode, positions.adapter),
            (batteryNode, positions.battery),
            (systemNode, positions.system),
        ]
        let changes = {
            for (view, center) in pairs {
                view.animator().setFrameOrigin(NSPoint(x: center.x - 36, y: center.y - Self.nodeSize / 2))
            }
        }
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.34
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                changes()
            }
        } else {
            for (view, center) in pairs {
                view.setFrameOrigin(NSPoint(x: center.x - 36, y: center.y - Self.nodeSize / 2))
            }
        }
    }

    private func configureNodes(_ snapshot: PowerSnapshot, animated: Bool) {
        let batterySymbol: String
        if snapshot.state == .charging {
            batterySymbol = "battery.100.bolt"
        } else if snapshot.percent <= 25 {
            batterySymbol = "battery.25"
        } else if snapshot.percent <= 50 {
            batterySymbol = "battery.50"
        } else if snapshot.percent <= 75 {
            batterySymbol = "battery.75"
        } else {
            batterySymbol = "battery.100"
        }
        batteryNode.setSymbol(batterySymbol)

        let color = PopoverStyle.stateColor(snapshot.state)
        if snapshot.state == .mixedSupply {
            adapterNode.setTint(.systemBlue)
            batteryNode.setTint(.systemOrange)
            systemNode.setTint(.labelColor)
        } else {
            adapterNode.setTint(snapshot.state == .onBattery ? .secondaryLabelColor : color)
            batteryNode.setTint(color)
            systemNode.setTint(color)
        }

        switch snapshot.state {
        case .charging:
            adapterNode.setActivity(.active, animated: animated)
            batteryNode.setActivity(.active, animated: animated)
            systemNode.setActivity(.active, animated: animated)
        case .pluggedIdle:
            adapterNode.setActivity(.active, animated: animated)
            batteryNode.setActivity(.idle, animated: animated)
            systemNode.setActivity(.active, animated: animated)
        case .onBattery:
            adapterNode.setActivity(.disconnected, animated: animated)
            batteryNode.setActivity(.discharging, animated: animated)
            systemNode.setActivity(.active, animated: animated)
        case .mixedSupply:
            adapterNode.setActivity(.active, animated: animated)
            batteryNode.setActivity(.active, animated: animated)
            systemNode.setActivity(.active, animated: animated)
        }
    }

    private func pipeConfigurations(
        _ snapshot: PowerSnapshot,
        layout: FlowLayout,
        positions: FlowPositions
    ) -> [PipeConfiguration] {
        let adapterActive = snapshot.state != .onBattery
        let batteryActive = snapshot.state == .charging || snapshot.state == .onBattery || snapshot.state == .mixedSupply
        let adapterWatts = snapshot.state == .mixedSupply ? snapshot.adapterW : snapshot.systemW
        let batteryWatts = abs(snapshot.batteryW)
        let adapterThickness = adapterActive ? VisualEncoding.thickness(adapterWatts) : 0
        let batteryThickness = batteryActive ? VisualEncoding.thickness(batteryWatts) : 0

        let adapterColor: NSColor = snapshot.state == .charging ? .systemGreen : .systemBlue
        let batteryColor: NSColor = snapshot.state == .mixedSupply ? .systemOrange : PopoverStyle.stateColor(snapshot.state)

        switch layout {
        case .adapterLed:
            let starts = junctionCenters(
                cy: positions.adapter.y,
                upperThickness: adapterThickness,
                lowerThickness: batteryThickness
            )
            return [
                PipeConfiguration(start: CGPoint(x: positions.adapter.x, y: starts.upper), end: positions.system, watts: adapterWatts, color: adapterColor, active: adapterActive),
                PipeConfiguration(start: CGPoint(x: positions.adapter.x, y: starts.lower), end: positions.battery, watts: batteryWatts, color: batteryColor, active: batteryActive),
            ]
        case .batteryLed:
            let ends = junctionCenters(
                cy: positions.system.y,
                upperThickness: adapterThickness,
                lowerThickness: batteryThickness
            )
            return [
                PipeConfiguration(start: positions.adapter, end: CGPoint(x: positions.system.x, y: ends.upper), watts: snapshot.adapterW, color: .systemBlue, active: adapterActive),
                PipeConfiguration(start: positions.battery, end: CGPoint(x: positions.system.x, y: ends.lower), watts: batteryWatts, color: batteryColor, active: batteryActive),
            ]
        }
    }

    private func junctionCenters(
        cy: CGFloat,
        upperThickness: CGFloat,
        lowerThickness: CGFloat
    ) -> (upper: CGFloat, lower: CGFloat) {
        (
            upper: cy - lowerThickness / 2,
            lower: cy + upperThickness / 2
        )
    }

    private func pipePath(start: CGPoint, end: CGPoint) -> CGPath {
        let path = CGMutablePath()
        let inset: CGFloat = Self.nodeSize / 2 - 4
        let direction: CGFloat = end.x >= start.x ? 1 : -1
        let adjustedStart = CGPoint(x: start.x + direction * inset, y: start.y)
        let adjustedEnd = CGPoint(x: end.x - direction * inset, y: end.y)
        let distance = adjustedEnd.x - adjustedStart.x
        let control1 = CGPoint(x: adjustedStart.x + distance * 0.42, y: adjustedStart.y)
        let control2 = CGPoint(x: adjustedStart.x + distance * 0.58, y: adjustedEnd.y)
        let start = adjustedStart
        let end = adjustedEnd
        path.move(to: start)
        path.addCurve(to: end, control1: control1, control2: control2)
        return path
    }

    private func apply(
        _ configuration: PipeConfiguration,
        to layers: PipeLayers,
        totalInputW: Double,
        animated: Bool
    ) {
        let path = pipePath(start: configuration.start, end: configuration.end)
        let thickness = configuration.active ? VisualEncoding.thickness(configuration.watts) : 0

        applyPath(path, to: layers.track, animated: animated)
        applyPath(path, to: layers.pulse, animated: animated)
        applyPath(path, to: layers.mask, animated: animated)
        applyWidth(thickness, to: layers.track, animated: animated)
        applyWidth(thickness, to: layers.pulse, animated: animated)
        applyWidth(thickness, to: layers.mask, animated: animated)

        layers.track.strokeColor = configuration.color.withAlphaComponent(0.20).cgColor
        layers.pulse.strokeColor = configuration.color.cgColor
        layers.track.opacity = configuration.active ? 1 : 0
        layers.pulse.opacity = configuration.active ? 0.92 : 0
        layers.particles.opacity = configuration.active ? 1 : 0

        guard configuration.active else {
            layers.pulse.removeAnimation(forKey: "flow")
            layers.particles.sublayers?.forEach {
                $0.removeAllAnimations()
                $0.removeFromSuperlayer()
            }
            return
        }
        guard animationsEnabled else {
            return
        }
        animatePulse(layers.pulse, totalInputW: totalInputW)
        rebuildParticles(
            in: layers.particles,
            path: path,
            thickness: thickness,
            totalInputW: totalInputW
        )
    }

    private func applyPath(_ path: CGPath, to layer: CAShapeLayer, animated: Bool) {
        let oldPath = layer.presentation()?.path ?? layer.path
        layer.path = path
        guard animated, let oldPath else { return }
        let animation = CABasicAnimation(keyPath: "path")
        animation.fromValue = oldPath
        animation.toValue = path
        animation.duration = 0.34
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(animation, forKey: "pathMorph")
    }

    private func applyWidth(_ width: CGFloat, to layer: CAShapeLayer, animated: Bool) {
        let oldWidth = layer.presentation()?.lineWidth ?? layer.lineWidth
        layer.lineWidth = width
        guard animated else { return }
        let animation = CABasicAnimation(keyPath: "lineWidth")
        animation.fromValue = oldWidth
        animation.toValue = width
        animation.duration = 0.34
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(animation, forKey: "widthMorph")
    }

    private func animatePulse(_ pulse: CAShapeLayer, totalInputW: Double) {
        if pulse.animation(forKey: "flow") == nil {
            let flow = CABasicAnimation(keyPath: "lineDashPhase")
            flow.fromValue = 0
            flow.toValue = -30
            flow.duration = 2.4
            flow.repeatCount = .infinity
            flow.timingFunction = CAMediaTimingFunction(name: .linear)
            pulse.add(flow, forKey: "flow")
        }
        PopoverStyle.setAnimationSpeed(pulse, multiplier: VisualEncoding.multiplier(totalInputW))
    }

    private func rebuildParticles(
        in emitter: CAEmitterLayer,
        path: CGPath,
        thickness: CGFloat,
        totalInputW: Double
    ) {
        emitter.sublayers?.forEach { $0.removeFromSuperlayer() }
        var rng = SeededGenerator(seed: Self.particleSeed)
        let normalized = VisualEncoding.t(totalInputW)
        let over = VisualEncoding.over(totalInputW)
        let count = Int(round(2 + normalized * 6 + over * 5))
        let saturated = totalInputW >= Double(VisualEncoding.wRef)
        let particleColor = saturated ? NSColor(rgb: 0xDBEAFF) : .white
        let duration = 2.4
        let spread = thickness * 0.36
        PopoverStyle.setAnimationSpeed(emitter, multiplier: VisualEncoding.multiplier(totalInputW))
        let emitterTime = emitter.convertTime(CACurrentMediaTime(), from: nil)

        for _ in 0..<count {
            let offset = (rng.nextUnit() * 2 - 1) * spread
            let radiusRange: ClosedRange<CGFloat> = saturated ? 1.30...3.20 : 0.85...2.25
            let radius = radiusRange.lowerBound + rng.nextUnit() * (radiusRange.upperBound - radiusRange.lowerBound)
            let particle = CALayer()
            particle.bounds = CGRect(x: 0, y: 0, width: radius * 2, height: radius * 2)
            particle.cornerRadius = radius
            particle.backgroundColor = particleColor.cgColor
            particle.shadowColor = particleColor.cgColor
            particle.shadowOpacity = saturated ? 0.92 : 0.66
            particle.shadowRadius = saturated ? 4 + radius * 1.9 : 2 + radius
            particle.shadowOffset = .zero
            emitter.addSublayer(particle)

            var transform = CGAffineTransform(translationX: 0, y: offset)
            let shiftedPath = path.copy(using: &transform) ?? path
            let motion = CAKeyframeAnimation(keyPath: "position")
            motion.path = shiftedPath
            motion.calculationMode = .paced
            motion.duration = duration * Double(0.84 + rng.nextUnit() * 0.34)
            motion.beginTime = emitterTime - motion.duration * Double(rng.nextUnit())
            motion.repeatCount = .infinity
            motion.isRemovedOnCompletion = false
            particle.add(motion, forKey: "particleMotion")
        }
    }
}
