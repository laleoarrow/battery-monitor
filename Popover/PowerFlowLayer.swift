import AppKit

/// Four power states normally collapse to two geometries. A measured device
/// output adds one on-battery split without changing the node or pipe count.
enum FlowLayout {
    case adapterLed   // adapter left-centre, system top-right, battery bottom-right
    case batteryLed   // adapter top-left, battery bottom-left, system centre-right
    case batteryOutputSplit // battery left-centre, Mac top-right, device bottom-right
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
    private static let nodeIconCanvasSize: CGFloat = 32
    private static let nodeSymbolDrawExtent: CGFloat = 28
    private static let batterySymbolDrawExtent: CGFloat = 24.5
    private static let powerIconConfiguration =
        NSImage.SymbolConfiguration(pointSize: 21, weight: .regular)
    private static let nodeIconStrokeWidth: CGFloat = 1.6
    private static let restoredAdapterRotation = CGFloat.pi / 4
    private static let restoredAdapterImage = rotatedAdapterImage(addsSlash: false)
    private static let restoredDisconnectedAdapterImage =
        rotatedAdapterImage(addsSlash: true)
    private static let restoredChargingBatteryImage = chargingBatteryImage()
    private static let restoredSystemImage = systemChipImage()
    /// Byte-for-byte copy of design/icon/device-output-port-template.png,
    /// extracted from the selected design rather than recreated in code.
    private static let deviceOutputPortTemplateImage: NSImage? = {
        let base64 = """
        iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAQAAAAAYLlVAAAAB3RJTUUH6ggYDwsq7cXx1QAAApNJ
        REFUaN7tlr1rFEEYh591l93cJZETAomFwYAQsQgWKTSCIKSwTaOCYGUhiFpZpcp/IArBKhBI60cn
        IklhY1CLCCnEIiomYjDKXe5yt3e3cz+LDDERL2H3wMZ5ttidnXnf+b3vfILD4XA4HA6Hw/G/4x3c
        RBP0kwABIQZDQgD4hOQx1AFo2DdAjSqQB754LzvUp27NKVasptLT1Kpmda2DDGiQR4yyzhJVQgJ8
        AIzNRw8BdWoA1AGDDzQw5GwG4CjHeOZdyRZ9l95LWtR1Dfy1vq14eQp0WIMa0k0tS7qdTcCkpGWN
        ZDL+7WVGTcXqa1ffPoouysA97y7oCJfpIQLAAD45++1j8KkAEJIH6tRIAMMn7wnoHPNE3PHup1V+
        UdKqxgG0kGEKStI4qFslSbPt+jnUVkEdCCiCznABECIhQSmiOA3eFgbobdckaGtcBjvrfTtYG7YU
        Ysjj2+ETYPb42cDQv6tsdnykElADDBGwDsBzHmAICWngkyckT0iDKgZjt6UCeb4yT4FpRoAPAKzT
        Z+dPGjQk6bPOA+idYo2msh5QLGkIQC8kLaTPQGNX4m4x5r1NI8D7prOMeR8ByAHF9Bk4IamiqdSG
        f/oZ0YqUwY8CtSStbA9CBwLmJEkns5hOSSrpja5m7rxbk4olzbRvs/9h9JgJNvnBa4qU7SHUwGCA
        hIiQ7UUGBkOITy8hDYoUqXKcU4zRzxrD3lbWGB7qu0pqSYrVVFOxfSqqKFZLTfu3op+K1dqzD7bU
        UkmL+58mB15IdINLFAgpEpGz8UYkGCJyO2vFpwbkiMjh02D7OF7iKdPeZkcCQB7DFChjCDH4+HZb
        8W0ZfAJ7R0iIrKQQeOWtZUy9w+FwOBwOh8Ph+Hf8Am/+sFQHMOr3AAAAAElFTkSuQmCC
        """
        guard let data = Data(
            base64Encoded: base64,
            options: .ignoreUnknownCharacters
        ), let source = NSImage(data: data) else { return nil }

        // The source PNG intentionally keeps transparent extraction padding.
        // Crop only that padding while rendering its real pixels into the same
        // 32-point template canvas used by the other node icons. At 16 points
        // the visible port is 14 x 6.65 points, matching the selected design.
        let image = NSImage(size: NSSize(width: 32, height: 32), flipped: false) { _ in
            source.draw(
                in: NSRect(x: 2, y: 9.35, width: 28, height: 13.3),
                from: NSRect(x: 11, y: 23, width: 40, height: 19),
                operation: .sourceOver,
                fraction: 1
            )
            return true
        }
        image.isTemplate = true
        return image
    }()
    private static let normalizedBatteryImages: [String: NSImage] = {
        let symbols = ["battery.25", "battery.50", "battery.75", "battery.100"]
        return Dictionary(uniqueKeysWithValues: symbols.compactMap { symbol in
            nodeSymbolImage(
                named: symbol,
                accessibilityDescription: "Battery",
                drawExtent: batterySymbolDrawExtent
            ).map {
                (symbol, $0)
            }
        })
    }()

    private let box = NSView()
    private let icon = NSImageView()
    private let caption = NSTextField(labelWithString: "")
    private let value = NSTextField(labelWithString: "")
    private var breathingColor: NSColor?
#if DEBUG
    private(set) var breathingInstallationsForTest = 0
#endif

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

        icon.imageScaling = .scaleProportionallyDown
        icon.setAccessibilityElement(false)
        icon.cell?.setAccessibilityElement(false)
        box.addSubview(icon)

        caption.font = .systemFont(ofSize: 11, weight: .regular)
        caption.textColor = PopoverStyle.secondaryText
        caption.alignment = .center
        caption.setAccessibilityElement(false)
        caption.cell?.setAccessibilityElement(false)
        addSubview(caption)

        value.font = PopoverStyle.mono(12.5)
        value.textColor = PopoverStyle.primaryText
        value.alignment = .center
        value.setAccessibilityElement(true)
        value.setAccessibilityRole(.staticText)
        addSubview(value)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        let size = Self.boxSize
        box.frame = NSRect(x: (bounds.width - size) / 2, y: 0, width: size, height: size)
        icon.frame = box.bounds
        caption.frame = NSRect(x: 0, y: size + 5, width: bounds.width, height: 14)
        value.frame = NSRect(x: 0, y: size + 20, width: bounds.width, height: 16)
    }

    func configure(symbol: String, caption text: String, value valueText: String, tint: NSColor) {
        icon.image = Self.nodeIconImage(symbol: symbol, accessibilityDescription: text)
        needsLayout = true
        icon.contentTintColor = tint
        caption.stringValue = text
        value.stringValue = valueText
        value.setAccessibilityLabel(text)
        value.setAccessibilityValue(valueText)
        box.layer?.borderColor = tint.withAlphaComponent(0.34).cgColor
    }

    fileprivate static func nodeIconImage(
        symbol: String,
        accessibilityDescription: String
    ) -> NSImage? {
        switch symbol {
        case "cpu":
            return restoredSystemImage
        case "powerplug":
            return restoredAdapterImage
        case "powerplug.slash":
            return restoredDisconnectedAdapterImage
        case "battery.100.bolt":
            return restoredChargingBatteryImage
        case "device.output.port":
            return deviceOutputPortTemplateImage
        case "cable.connector.horizontal":
            return nodeSymbolImage(
                named: "cable.connector.horizontal",
                accessibilityDescription: accessibilityDescription
            ) ?? nodeIconImage(
                symbol: "cable.connector",
                accessibilityDescription: accessibilityDescription
            )
        case "cable.connector":
            return nodeSymbolImage(
                named: "cable.connector",
                accessibilityDescription: accessibilityDescription
            ) ?? nodeSymbolImage(
                named: "bolt.horizontal.circle",
                accessibilityDescription: accessibilityDescription
            )
        default:
            return normalizedBatteryImages[symbol]
                ?? nodeSymbolImage(
                    named: symbol,
                    accessibilityDescription: accessibilityDescription
                )
        }
    }

    private static func rotatedAdapterImage(addsSlash: Bool) -> NSImage? {
        nodeSymbolImage(
            named: "powerplug",
            accessibilityDescription: "Adapter",
            rotation: restoredAdapterRotation,
            addsSlash: addsSlash,
            centerOffset: CGPoint(x: -0.75, y: 0.25)
        )
    }

    private static func nodeSymbolImage(
        named symbol: String,
        accessibilityDescription: String,
        rotation: CGFloat = 0,
        addsSlash: Bool = false,
        drawExtent: CGFloat = nodeSymbolDrawExtent,
        centerOffset: CGPoint = .zero
    ) -> NSImage? {
        guard let source = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: accessibilityDescription
        )?.withSymbolConfiguration(Self.powerIconConfiguration) else { return nil }

        let canvasSize = NSSize(width: nodeIconCanvasSize, height: nodeIconCanvasSize)
        let sourceMax = max(source.size.width, source.size.height)
        let scale = min(1, drawExtent / sourceMax)
        let drawSize = NSSize(
            width: source.size.width * scale,
            height: source.size.height * scale
        )
        let image = NSImage(size: canvasSize, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.saveGState()
            context.translateBy(
                x: rect.midX + centerOffset.x,
                y: rect.midY + centerOffset.y
            )
            context.rotate(by: rotation)
            source.draw(
                in: NSRect(
                    x: -drawSize.width / 2,
                    y: -drawSize.height / 2,
                    width: drawSize.width,
                    height: drawSize.height
                )
            )
            context.restoreGState()
            if addsSlash {
                context.setStrokeColor(NSColor.black.cgColor)
                context.setLineWidth(nodeIconStrokeWidth)
                context.setLineCap(.round)
                context.move(to: CGPoint(x: 10, y: 22))
                context.addLine(to: CGPoint(x: 22, y: 10))
                context.strokePath()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func systemChipImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 32, height: 32), flipped: false) { _ in
            NSColor.black.setStroke()
            let chip = NSBezierPath(
                roundedRect: NSRect(x: 9.5, y: 9.5, width: 13, height: 13),
                xRadius: 2.6,
                yRadius: 2.6
            )
            chip.appendRoundedRect(
                NSRect(x: 12.5, y: 12.5, width: 7, height: 7),
                xRadius: 1.4,
                yRadius: 1.4
            )
            for coordinate in [12.0, 16.0, 20.0] {
                chip.move(to: NSPoint(x: coordinate, y: 7))
                chip.line(to: NSPoint(x: coordinate, y: 9.5))
                chip.move(to: NSPoint(x: coordinate, y: 22.5))
                chip.line(to: NSPoint(x: coordinate, y: 25))
                chip.move(to: NSPoint(x: 7, y: coordinate))
                chip.line(to: NSPoint(x: 9.5, y: coordinate))
                chip.move(to: NSPoint(x: 22.5, y: coordinate))
                chip.line(to: NSPoint(x: 25, y: coordinate))
            }
            chip.lineWidth = nodeIconStrokeWidth
            chip.lineCapStyle = .round
            chip.lineJoinStyle = .round
            chip.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func chargingBatteryImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 32, height: 32), flipped: false) { _ in
            NSColor.black.setStroke()
            let shell = NSBezierPath()
            shell.move(to: NSPoint(x: 13, y: 23))
            shell.line(to: NSPoint(x: 9.75, y: 23))
            shell.curve(
                to: NSPoint(x: 7, y: 20.25),
                controlPoint1: NSPoint(x: 8.1, y: 23),
                controlPoint2: NSPoint(x: 7, y: 21.9)
            )
            shell.line(to: NSPoint(x: 7, y: 11.75))
            shell.curve(
                to: NSPoint(x: 9.75, y: 9),
                controlPoint1: NSPoint(x: 7, y: 10.1),
                controlPoint2: NSPoint(x: 8.1, y: 9)
            )
            shell.line(to: NSPoint(x: 13, y: 9))
            shell.move(to: NSPoint(x: 19, y: 23))
            shell.line(to: NSPoint(x: 22.25, y: 23))
            shell.curve(
                to: NSPoint(x: 25, y: 20.25),
                controlPoint1: NSPoint(x: 23.9, y: 23),
                controlPoint2: NSPoint(x: 25, y: 21.9)
            )
            shell.line(to: NSPoint(x: 25, y: 11.75))
            shell.curve(
                to: NSPoint(x: 22.25, y: 9),
                controlPoint1: NSPoint(x: 25, y: 10.1),
                controlPoint2: NSPoint(x: 23.9, y: 9)
            )
            shell.line(to: NSPoint(x: 19, y: 9))
            shell.lineWidth = nodeIconStrokeWidth
            shell.lineCapStyle = .round
            shell.lineJoinStyle = .round
            shell.stroke()

            NSColor.black.setFill()
            let chargingMark = NSBezierPath()
            chargingMark.move(to: NSPoint(x: 16.9, y: 22.5))
            chargingMark.line(to: NSPoint(x: 12.5, y: 15.5))
            chargingMark.line(to: NSPoint(x: 15.5, y: 15.5))
            chargingMark.line(to: NSPoint(x: 14.9, y: 10))
            chargingMark.line(to: NSPoint(x: 20, y: 16.5))
            chargingMark.line(to: NSPoint(x: 17, y: 16.5))
            chargingMark.close()
            chargingMark.fill()
            return true
        }
        image.isTemplate = true
        return image
    }

#if DEBUG
    static func iconImageForTest(symbol: String) -> NSImage? {
        nodeIconImage(symbol: symbol, accessibilityDescription: symbol)
    }

    var presentationForTest: (caption: String, value: String) {
        (caption.stringValue, value.stringValue)
    }

    var contentFitsBoundsForTest: Bool {
        let captionSize = caption.attributedStringValue.size()
        let valueSize = value.attributedStringValue.size()
        let captionFits = bounds.contains(caption.frame)
            && captionSize.width <= caption.bounds.width + 0.5
            && captionSize.height <= caption.bounds.height + 0.5
        let valueFits = bounds.contains(value.frame)
            && valueSize.width <= value.bounds.width + 0.5
            && valueSize.height <= value.bounds.height + 0.5
        return captionFits && valueFits && bounds.contains(box.frame)
    }
#endif

    /// Idle and disconnected nodes stay on screen at reduced opacity. Removing
    /// them makes the frame jump and hides the fact that the component is still
    /// physically there.
    func setPresence(_ alpha: CGFloat) { alphaValue = alpha }

    func setBreathing(_ on: Bool, color: NSColor) {
        guard on else {
            stopBreathing()
            return
        }
        if let breathingColor,
           breathingColor.isEqual(color),
           box.layer?.animation(forKey: "breathe") != nil {
            return
        }
        stopBreathing()
        breathingColor = color
        let pulse = CABasicAnimation(keyPath: "borderColor")
        pulse.fromValue = color.withAlphaComponent(0.18).cgColor
        pulse.toValue = color.withAlphaComponent(0.85).cgColor
        pulse.duration = 3.2
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        box.layer?.add(pulse, forKey: "breathe")
#if DEBUG
        breathingInstallationsForTest += 1
#endif
    }

    func stopBreathing() {
        box.layer?.removeAnimation(forKey: "breathe")
        breathingColor = nil
    }

#if DEBUG
    var breathingAnimationCountForTest: Int {
        box.layer?.animation(forKey: "breathe") == nil ? 0 : 1
    }
#endif
}

/// One pipe: a solid trough with a soft-cored light sweeping its full length,
/// plus sparks scattered across the cross-section.
///
/// The light is a gradient masked by the stroked path, not a dashed stroke.
/// Dashes give hard edges, and an earlier attempt to soften them by fading the
/// whole container also faded the trough — the pipe appeared to stop short of
/// its node. Nothing fades here; the ends are tucked under the node wells.
final class PipeBundle {
    let container = CALayer()

    private let trough = CAShapeLayer()
    private let flowHost = CALayer()
    private let flowMask = CAShapeLayer()
    private let gradient = CAGradientLayer()

    private var particles: [CALayer] = []
    private var particleOffsets: [CGFloat] = []
    private var particleCount = -1
    private var particlesAreHot = false
    private var particlesAreAnimating = false
    private var particleTopology = ""
    private var geometry = PipeGeometry(start: .zero, control1: .zero, control2: .zero, end: .zero)

    init() {
        trough.fillColor = nil
        trough.lineCap = .butt          // flush where two pipes meet under a node
        trough.strokeColor = PopoverStyle.trough.cgColor
        container.addSublayer(trough)

        flowMask.fillColor = nil
        flowMask.lineCap = .round
        flowMask.strokeColor = NSColor.black.cgColor
        flowHost.mask = flowMask

        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        flowHost.addSublayer(gradient)
        container.addSublayer(flowHost)
    }

    func apply(geometry newGeometry: PipeGeometry, thickness: CGFloat, color: NSColor,
               bounds: CGRect, animated: Bool) {
        geometry = newGeometry
        let path = newGeometry.path

        let update = {
            self.trough.path = path
            self.trough.lineWidth = thickness
            self.trough.frame = bounds

            self.flowHost.frame = bounds
            self.flowMask.frame = bounds
            self.flowMask.path = path
            self.flowMask.lineWidth = thickness

            // Twice the width so shifting by exactly one width loops with no
            // seam. Each pulse has a bright core inside a softer body, which is
            // what separates a moving light from a moving block.
            self.gradient.frame = CGRect(x: -bounds.width, y: 0,
                                         width: bounds.width * 2, height: bounds.height)
            // Strictly periodic with period 0.5, so shifting by exactly one
            // view width lands the pattern back on itself. The earlier stops
            // were not: alpha differed by 0.14 across the wrap, which showed up
            // as a seam once per cycle.
            let clear = color.withAlphaComponent(0).cgColor
            let soft = color.withAlphaComponent(0.30).cgColor
            let core = color.cgColor
            self.gradient.colors = [clear, soft, core, soft, clear,
                                    clear, soft, core, soft, clear, clear]
            self.gradient.locations = [0, 0.13, 0.21, 0.29, 0.42,
                                       0.50, 0.63, 0.71, 0.79, 0.92, 1].map { NSNumber(value: $0) }
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

    func startFlow(multiplier: CGFloat, width: CGFloat) {
        if gradient.animation(forKey: "flow") == nil {
            let drift = CABasicAnimation(keyPath: "position.x")
            drift.byValue = width
            drift.duration = VisualEncoding.motionPeriod
            drift.repeatCount = .infinity
            drift.isRemovedOnCompletion = false
            gradient.add(drift, forKey: "flow")
        }
        // Retime rather than restart, so a data refresh never jolts the light.
        PopoverStyle.setAnimationSpeed(gradient, multiplier: multiplier)
    }

    func stopFlow() {
        gradient.removeAllAnimations()
        particles.forEach { $0.removeAllAnimations() }
        // The bookkeeping has to match what was just done to the layers.
        // Leaving this true made the pool believe it was still animating, so
        // reopening the popover skipped the rebuild and the sparks stayed dead.
        particlesAreAnimating = false
    }

    /// Particles ride the pipe at every power level, not just past saturation.
    /// Each takes a deterministic offset across the cross-section — putting them
    /// all on the centreline reads as a conveyor belt, not a current.
    ///
    /// The pool is only rebuilt when the count or the hot/cold styling actually
    /// changes. Tearing it down on every 1 Hz refresh reset every particle to
    /// its seeded position once a second, which is what produced the stutter.
    func rebuildParticles(count: Int, thickness: CGFloat, color: NSColor,
                          period: CFTimeInterval, seed: UInt64, hot: Bool,
                          animating: Bool, topology: String) {
        let requested = thickness > 0.5 ? count : 0

        // Hysteresis. The count is a rounded function of a continuously drifting
        // reading, so it oscillates across a boundary — 43 W wants five sparks
        // and 45 W wants six, and the pool rebuilt on every crossing. One spark
        // either way is invisible; churning the pool at 1 Hz is not.
        let wanted: Int
        if particleCount < 0 || requested == 0 || particleCount == 0 {
            wanted = requested
        } else {
            wanted = abs(requested - particleCount) >= 2 ? requested : particleCount
        }

        // Everything the pool is built from has to be in this key. Guarding on
        // the count alone meant particles kept the animations — or the curve —
        // they were born with: reopening the popover left them frozen, and a
        // topology change left them riding the old path.
        // Only discrete facts belong in this guard. Keying on the curve's
        // coordinates or on thickness meant keying on a continuously drifting
        // reading: whatever the quantisation, the value oscillates across its
        // own boundary and the pool churns at 1 Hz. Topology is discrete, and
        // sub-point drift in the path is not visible.
        guard wanted != particleCount
            || hot != particlesAreHot
            || animating != particlesAreAnimating
            || topology != particleTopology
        else {
            retargetParticlesToCurrentGeometry()
            retimeParticles(period: period)
            return
        }
        particleCount = wanted
        particlesAreHot = hot
        particlesAreAnimating = animating
        particleTopology = topology

        particles.forEach { $0.removeFromSuperlayer() }
        particles.removeAll()
        particleOffsets.removeAll()
        guard wanted > 0 else { return }

        var rng = SeededRNG(seed: seed)
        let tint = hot ? PopoverStyle.saturationParticle : NSColor.white
        let basePath = geometry.path

        for index in 0..<wanted {
            let offset = (rng.nextUnit() * 2 - 1) * thickness * 0.36
            let radius = (hot ? 1.3 : 0.85) + rng.nextUnit() * (hot ? 1.9 : 1.4)
            let spread = 1.4 + rng.nextUnit() * 1.1
            let delay = rng.nextUnit()

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
            let seat = geometry.point(at: (CGFloat(index) + 0.5) / CGFloat(wanted))
            PopoverStyle.setWithoutAnimation {
                dot.position = CGPoint(x: seat.x, y: seat.y + offset)
                dot.opacity = 1
            }
            container.addSublayer(dot)
            particles.append(dot)
            particleOffsets.append(offset)

            guard animating else { continue }
            var shift = CGAffineTransform(translationX: 0, y: offset)
            guard let ridePath = basePath.copy(using: &shift) else { continue }

            // Fixed durations; speed comes from the layer timeline so a refresh
            // can retime without rebuilding.
            let duration = 2.4 * spread
            let animationStart = dot.convertTime(CACurrentMediaTime(), from: nil)

            let ride = CAKeyframeAnimation(keyPath: "position")
            ride.path = ridePath
            ride.duration = duration
            ride.beginTime = animationStart
            ride.repeatCount = .infinity
            ride.calculationMode = .paced
            ride.timeOffset = delay * duration
            ride.isRemovedOnCompletion = false

            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 1, 1, 0]
            fade.keyTimes = [0, 0.09, 0.86, 1]
            fade.duration = duration
            fade.beginTime = animationStart
            fade.repeatCount = .infinity
            fade.timeOffset = delay * duration
            fade.isRemovedOnCompletion = false

            dot.add(ride, forKey: "ride")
            dot.add(fade, forKey: "fade")
        }
        retimeParticles(period: period)
    }

    /// Keep the existing particle layers and their timelines, but move their
    /// model positions and ride paths onto the latest curve. Power telemetry
    /// can move a split point without changing topology; leaving the original
    /// path in place made the sparks drift beside the pipe.
    private func retargetParticlesToCurrentGeometry() {
        guard particles.count == particleOffsets.count, !particles.isEmpty else { return }
        let basePath = geometry.path
        let count = CGFloat(particles.count)

        for (index, pair) in zip(particles, particleOffsets).enumerated() {
            let (dot, offset) = pair
            let seat = geometry.point(at: (CGFloat(index) + 0.5) / count)
            PopoverStyle.setWithoutAnimation {
                dot.position = CGPoint(x: seat.x, y: seat.y + offset)
            }

            guard let previousRide = dot.animation(forKey: "ride") as? CAKeyframeAnimation else { continue }
            var shift = CGAffineTransform(translationX: 0, y: offset)
            guard let ridePath = basePath.copy(using: &shift) else { continue }

            let ride = CAKeyframeAnimation(keyPath: "position")
            ride.path = ridePath
            ride.duration = previousRide.duration
            ride.beginTime = previousRide.beginTime
            ride.timeOffset = previousRide.timeOffset
            ride.speed = previousRide.speed
            ride.repeatCount = previousRide.repeatCount
            ride.repeatDuration = previousRide.repeatDuration
            ride.autoreverses = previousRide.autoreverses
            ride.calculationMode = previousRide.calculationMode
            ride.timingFunction = previousRide.timingFunction
            ride.fillMode = previousRide.fillMode
            ride.isRemovedOnCompletion = previousRide.isRemovedOnCompletion

            // The original animation is immutable once attached. Recreate its
            // timing exactly and replace only the path, preserving the phase.
            dot.add(ride, forKey: "ride")
        }
    }

    private func retimeParticles(period: CFTimeInterval) {
        let multiplier = CGFloat(2.4 / period)
        particles.forEach { PopoverStyle.setAnimationSpeed($0, multiplier: multiplier) }
    }

#if DEBUG
    func flowMetricsForTest() -> (duration: CFTimeInterval, layerSpeed: Float)? {
        guard let motion = gradient.animation(forKey: "flow") as? CABasicAnimation else { return nil }
        return (motion.duration, gradient.speed)
    }

    var thicknessForTest: CGFloat { trough.lineWidth }
#endif
}

final class PowerFlowView: PopoverSection {
    private final class DeviceOutputReadout: NSTextField {
        var spokenValue: String?

        override func accessibilityValue() -> String? {
            spokenValue ?? super.accessibilityValue()
        }
    }

    static let plotHeight: CGFloat = 176
    private static let deviceOutputReadoutHeight: CGFloat = 17
    private static let deviceOutputReadoutSlotHeight: CGFloat = 22
    private static let deviceOutputWellSize: CGFloat = 26
    private static let deviceOutputIconSize: CGFloat = 16
    private static let deviceOutputAccessoryGap: CGFloat = 8
    static let preferredHeight: CGFloat =
        plotHeight + deviceOutputReadoutSlotHeight + PopoverStyle.sectionPadding * 2
    /// Enter the stronger particle style at saturation, but do not leave it for
    /// ordinary 1 Hz telemetry noise around 100 W. Without this band, 99.9 /
    /// 100.1 W rebuilt every particle and its animations on alternating samples.
    private static let particlesStayHotAbove = Double(VisualEncoding.wRef) - 5

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
    private let pluggedDeviceOutputWell = NSView()
    private let pluggedDeviceOutputIcon = NSImageView()
    private let pluggedDeviceOutputReadout = DeviceOutputReadout(labelWithString: "")
    private let idleConnection = CAShapeLayer()
    private let bundles = (0..<2).map { _ in PipeBundle() }

    private var animationsEnabled = false
    private var latest = PowerSnapshot()
    private var particlesAreHot = false

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

        pluggedDeviceOutputWell.wantsLayer = true
        pluggedDeviceOutputWell.layer?.backgroundColor = PopoverStyle.well.cgColor
        pluggedDeviceOutputWell.layer?.borderColor = PopoverStyle.wellBorder.cgColor
        pluggedDeviceOutputWell.layer?.borderWidth = 0.5
        pluggedDeviceOutputWell.layer?.cornerRadius = 8
        pluggedDeviceOutputWell.layer?.cornerCurve = .continuous
        pluggedDeviceOutputWell.isHidden = true
        pluggedDeviceOutputWell.setAccessibilityElement(false)
        addSubview(pluggedDeviceOutputWell)

        pluggedDeviceOutputIcon.imageScaling = .scaleProportionallyDown
        pluggedDeviceOutputIcon.setAccessibilityElement(false)
        pluggedDeviceOutputIcon.cell?.setAccessibilityElement(false)
        pluggedDeviceOutputWell.addSubview(pluggedDeviceOutputIcon)

        pluggedDeviceOutputReadout.font = PopoverStyle.mono(11, .regular)
        pluggedDeviceOutputReadout.textColor = PopoverStyle.secondaryText
        pluggedDeviceOutputReadout.alignment = .left
        pluggedDeviceOutputReadout.isHidden = true
        pluggedDeviceOutputReadout.setAccessibilityElement(false)
        addSubview(pluggedDeviceOutputReadout)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        plot.frame = NSRect(x: 0, y: PopoverStyle.sectionPadding,
                            width: bounds.width, height: Self.plotHeight)
        layoutPluggedDeviceOutputAccessory()
        PopoverStyle.setWithoutAnimation {
            self.bundles.forEach { $0.container.frame = self.plot.bounds }
            self.idleConnection.frame = self.plot.bounds
        }
        // Recompute with real bounds. `update` can land before the first layout
        // pass, and everything derived from bounds — pipe geometry, the fade
        // mask — is nonsense until the plot has a size.
        update(snapshot: latest, animated: false)
    }

    private func layoutPluggedDeviceOutputAccessory() {
        let textWidth = ceil(pluggedDeviceOutputReadout.fittingSize.width)
        let groupWidth = Self.deviceOutputWellSize
            + Self.deviceOutputAccessoryGap
            + textWidth
        let groupX = floor((bounds.width - groupWidth) / 2)
        let readoutY = PopoverStyle.sectionPadding + Self.plotHeight + 3
        let readoutMidY = readoutY + Self.deviceOutputReadoutHeight / 2

        pluggedDeviceOutputWell.frame = NSRect(
            x: groupX,
            y: readoutMidY - Self.deviceOutputWellSize / 2,
            width: Self.deviceOutputWellSize,
            height: Self.deviceOutputWellSize
        )
        pluggedDeviceOutputIcon.frame = NSRect(
            x: (Self.deviceOutputWellSize - Self.deviceOutputIconSize) / 2,
            y: (Self.deviceOutputWellSize - Self.deviceOutputIconSize) / 2,
            width: Self.deviceOutputIconSize,
            height: Self.deviceOutputIconSize
        )
        pluggedDeviceOutputReadout.frame = NSRect(
            x: pluggedDeviceOutputWell.frame.maxX + Self.deviceOutputAccessoryGap,
            y: readoutY,
            width: textWidth,
            height: Self.deviceOutputReadoutHeight
        )
    }

    private func batteryOutputSplitDeviceW(for snapshot: PowerSnapshot) -> Double? {
        guard snapshot.state == .onBattery,
              snapshot.batteryW < -PowerSnapshot.epsilon,
              let deviceOutputW = snapshot.coherentDeviceOutputW,
              deviceOutputW > 0 else { return nil }
        return deviceOutputW
    }

    private func layoutMode(for snapshot: PowerSnapshot) -> FlowLayout {
        if batteryOutputSplitDeviceW(for: snapshot) != nil {
            return .batteryOutputSplit
        }
        return snapshot.batteryW < -PowerSnapshot.epsilon ? .batteryLed : .adapterLed
    }

    /// Node coordinates depend on the layout alone, never on whether a given
    /// node takes part. Filling the gap left by a disconnected adapter puts the
    /// battery box straight on top of the adapter's caption.
    private func positions(for layout: FlowLayout) -> [CGPoint] {
        switch layout {
        case .adapterLed: return Self.adapterLedPositions
        case .batteryLed: return Self.batteryLedPositions
        case .batteryOutputSplit: return Self.adapterLedPositions
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
        configurePluggedDeviceOutputReadout(for: snapshot)

        let color = PopoverStyle.stateColor(snapshot.state)
        let total = snapshot.totalInputW
        let motionMultiplier = VisualEncoding.multiplier(total)
        // Particle timing is intentionally independent from the shared sweep
        // period. Keep its existing 2.4-second basis when motion styling moves.
        let particlePeriod = 2.4 / Double(motionMultiplier)
        let hot = particlesAreHot
            ? total >= Self.particlesStayHotAbove
            : total >= Double(VisualEncoding.wRef)
        particlesAreHot = hot
        let count = Int((2 + VisualEncoding.t(total) * 6 + VisualEncoding.over(total) * 5).rounded())

        configureNodes(snapshot: snapshot, color: color, layout: layout)

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
                      thickness: upperThickness, color: color,
                      particlePeriod: particlePeriod, motionMultiplier: motionMultiplier,
                      particles: count, hot: hot, seed: 11, animated: animated,
                      topology: "adapterLed.0")
            configure(bundles[1], geometry: pipeGeometry(from: lowerStart, to: Self.bottomY),
                      thickness: lowerThickness, color: color,
                      particlePeriod: particlePeriod, motionMultiplier: motionMultiplier,
                      particles: charging ? count : 0, hot: hot, seed: 29, animated: animated,
                      topology: "adapterLed.1.\(charging)")

            idleConnection.path = charging ? nil : pipeGeometry(from: cy, to: Self.bottomY).path

        case .batteryLed:
            let adapterActive = snapshot.adapterW > PowerSnapshot.epsilon
            let upperThickness = adapterActive ? VisualEncoding.thickness(snapshot.adapterW) : 0
            let lowerThickness = VisualEncoding.thickness(abs(snapshot.batteryW))
            let cy = Self.midY

            let upperEnd = cy - lowerThickness / 2
            let lowerEnd = adapterActive ? cy + upperThickness / 2 : cy

            configure(bundles[0], geometry: pipeGeometry(from: Self.topY, to: upperEnd),
                      thickness: upperThickness, color: PopoverStyle.blue,
                      particlePeriod: particlePeriod, motionMultiplier: motionMultiplier,
                      particles: adapterActive ? count : 0, hot: hot, seed: 11, animated: animated,
                      topology: "batteryLed.0.\(adapterActive)")
            configure(bundles[1], geometry: pipeGeometry(from: Self.bottomY, to: lowerEnd),
                      thickness: lowerThickness,
                      color: adapterActive ? PopoverStyle.amber : color,
                      particlePeriod: particlePeriod, motionMultiplier: motionMultiplier,
                      particles: count, hot: hot, seed: 29, animated: animated,
                      topology: "batteryLed.1.\(adapterActive)")

            idleConnection.path = nil

        case .batteryOutputSplit:
            let deviceOutputW = batteryOutputSplitDeviceW(for: snapshot) ?? 0
            let macLoadW = max(snapshot.systemW - deviceOutputW, 0)
            let upperThickness = VisualEncoding.thickness(macLoadW)
            let lowerThickness = VisualEncoding.thickness(deviceOutputW)
            let cy = Self.midY

            // Keep the two outgoing edges tangent under the battery well so
            // the existing two pipes read as one total splitting by sink.
            let upperStart = cy - lowerThickness / 2
            let lowerStart = cy + upperThickness / 2

            configure(bundles[0], geometry: pipeGeometry(from: upperStart, to: Self.topY),
                      thickness: upperThickness, color: color,
                      particlePeriod: particlePeriod, motionMultiplier: motionMultiplier,
                      particles: count, hot: hot, seed: 11, animated: animated,
                      topology: "batteryOutputSplit.0")
            configure(bundles[1], geometry: pipeGeometry(from: lowerStart, to: Self.bottomY),
                      thickness: lowerThickness, color: color,
                      particlePeriod: particlePeriod, motionMultiplier: motionMultiplier,
                      particles: count, hot: hot, seed: 29, animated: animated,
                      topology: "batteryOutputSplit.1")

            idleConnection.path = nil
        }

        PopoverStyle.setWithoutAnimation {
            self.idleConnection.opacity = self.idleConnection.path == nil ? 0 : 1
        }
    }

    /// Plugged topologies already spend the fixed three nodes on source,
    /// battery and System Total. Show measured downstream output as a compact
    /// breakdown of that total without adding a fourth node or another pipe.
    private func configurePluggedDeviceOutputReadout(for snapshot: PowerSnapshot) {
        guard snapshot.state != .onBattery,
              let deviceOutputW = snapshot.coherentDeviceOutputW,
              deviceOutputW > 0 else {
            pluggedDeviceOutputReadout.stringValue = ""
            pluggedDeviceOutputReadout.spokenValue = nil
            pluggedDeviceOutputReadout.isHidden = true
            pluggedDeviceOutputReadout.setAccessibilityLabel(nil)
            pluggedDeviceOutputReadout.setAccessibilityValue(nil)
            pluggedDeviceOutputReadout.setAccessibilityElement(false)
            pluggedDeviceOutputIcon.image = nil
            pluggedDeviceOutputIcon.contentTintColor = nil
            pluggedDeviceOutputWell.isHidden = true
            return
        }

        let value = PopoverStyle.watts(deviceOutputW)
        let tint = PopoverStyle.stateColor(snapshot.state)
        pluggedDeviceOutputReadout.stringValue = "Device Output · \(value)"
        pluggedDeviceOutputReadout.spokenValue = value
        pluggedDeviceOutputReadout.isHidden = false
        pluggedDeviceOutputReadout.setAccessibilityElement(true)
        pluggedDeviceOutputReadout.setAccessibilityRole(.staticText)
        pluggedDeviceOutputReadout.setAccessibilityLabel("Device Output")
        pluggedDeviceOutputReadout.setAccessibilityValue(value)
        pluggedDeviceOutputIcon.image = FlowNodeView.nodeIconImage(
            symbol: "device.output.port",
            accessibilityDescription: "Device Output"
        )
        pluggedDeviceOutputIcon.contentTintColor = tint
        pluggedDeviceOutputWell.layer?.borderColor = tint.withAlphaComponent(0.34).cgColor
        pluggedDeviceOutputWell.isHidden = false
        layoutPluggedDeviceOutputAccessory()
    }

    private func configure(_ bundle: PipeBundle, geometry: PipeGeometry, thickness: CGFloat,
                           color: NSColor, particlePeriod: CFTimeInterval,
                           motionMultiplier: CGFloat, particles: Int,
                           hot: Bool, seed: UInt64, animated: Bool, topology: String) {
        bundle.apply(geometry: geometry, thickness: thickness, color: color,
                     bounds: plot.bounds, animated: animated)
        bundle.rebuildParticles(count: particles, thickness: thickness, color: color,
                                period: particlePeriod, seed: seed, hot: hot,
                                animating: animationsEnabled, topology: topology)
        if animationsEnabled {
            bundle.startFlow(multiplier: motionMultiplier, width: plot.bounds.width)
        }
    }

    private func configureNodes(snapshot: PowerSnapshot, color: NSColor, layout: FlowLayout) {
        let batterySymbol: String
        switch snapshot.percent {
        case ..<25: batterySymbol = "battery.25"
        case ..<50: batterySymbol = "battery.50"
        case ..<75: batterySymbol = "battery.75"
        default: batterySymbol = "battery.100"
        }

        let hasPositiveDeviceOutput = snapshot.coherentDeviceOutputW.map { $0 > 0 } ?? false
        systemNode.configure(symbol: "cpu",
                             caption: hasPositiveDeviceOutput ? "System Total" : "System",
                             value: PopoverStyle.watts(snapshot.systemW), tint: PopoverStyle.neutral)
        systemNode.setPresence(1)
        systemNode.setBreathing(false, color: color)
        adapterNode.setBreathing(false, color: color)

        switch snapshot.state {
        case .charging:
            adapterNode.configure(symbol: "powerplug", caption: "Adapter",
                                  value: PopoverStyle.watts(snapshot.adapterW), tint: color)
            adapterNode.setPresence(1)
            batteryNode.configure(symbol: "battery.100.bolt", caption: "To Battery",
                                  value: PopoverStyle.watts(snapshot.batteryW), tint: color)
            batteryNode.setPresence(1)
            batteryNode.setBreathing(false, color: color)

        case .pluggedIdle:
            adapterNode.configure(symbol: "powerplug", caption: "Adapter",
                                  value: PopoverStyle.watts(snapshot.adapterW), tint: color)
            adapterNode.setPresence(1)
            batteryNode.configure(symbol: batterySymbol, caption: "Battery · Full",
                                  value: "\(snapshot.percent) %", tint: color)
            batteryNode.setPresence(0.6)
            batteryNode.setBreathing(animationsEnabled, color: color)

        case .onBattery:
            if case .batteryOutputSplit = layout,
               let deviceOutputW = batteryOutputSplitDeviceW(for: snapshot) {
                let macLoadW = max(snapshot.systemW - deviceOutputW, 0)
                adapterNode.configure(symbol: batterySymbol, caption: "Battery \(snapshot.percent)%",
                                      value: PopoverStyle.watts(abs(snapshot.batteryW)), tint: color)
                adapterNode.setPresence(1)
                systemNode.configure(symbol: "cpu", caption: "Mac Load",
                                     value: PopoverStyle.watts(macLoadW), tint: color)
                batteryNode.configure(symbol: "device.output.port", caption: "Device Output",
                                      value: PopoverStyle.watts(deviceOutputW), tint: color)
                batteryNode.setPresence(1)
            } else {
                adapterNode.configure(symbol: "powerplug.slash", caption: "Adapter",
                                      value: "Unplugged", tint: PopoverStyle.neutral)
                adapterNode.setPresence(0.28)
                batteryNode.configure(symbol: batterySymbol, caption: "Battery \(snapshot.percent)%",
                                      value: PopoverStyle.watts(abs(snapshot.batteryW)), tint: color)
                batteryNode.setPresence(1)
            }
            batteryNode.setBreathing(false, color: color)

        case .mixedSupply:
            adapterNode.configure(symbol: "powerplug", caption: "Adapter",
                                  value: PopoverStyle.watts(snapshot.adapterW), tint: PopoverStyle.blue)
            adapterNode.setPresence(1)
            batteryNode.configure(symbol: batterySymbol, caption: "Battery Assist",
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
            [adapterNode, batteryNode, systemNode].forEach { $0.stopBreathing() }
        }
    }

#if DEBUG
    var topologyForTest: String {
        switch layoutMode(for: latest) {
        case .adapterLed: return "adapterLed"
        case .batteryLed: return "batteryLed"
        case .batteryOutputSplit: return "batteryOutputSplit"
        }
    }

    var nodePresentationsForTest: [(caption: String, value: String)] {
        [adapterNode, batteryNode, systemNode].map(\.presentationForTest)
    }

    var nodeFramesForTest: [NSRect] {
        [adapterNode, batteryNode, systemNode].map(\.frame)
    }

    var nodeContentsFitForTest: Bool {
        [adapterNode, batteryNode, systemNode].allSatisfy {
            $0.contentFitsBoundsForTest
                && $0.frame.minY >= plot.bounds.minY
                && $0.frame.maxY <= plot.bounds.maxY
        }
    }

    var branchThicknessesForTest: [CGFloat] {
        bundles.map(\.thicknessForTest)
    }

    var breathingMetricsForTest: (running: Int, installations: Int) {
        let nodes = [adapterNode, batteryNode, systemNode]
        return (
            nodes.reduce(0) { $0 + $1.breathingAnimationCountForTest },
            nodes.reduce(0) { $0 + $1.breathingInstallationsForTest }
        )
    }

    func flowMetricsForTest() -> (duration: CFTimeInterval, layerSpeed: Float)? {
        bundles.compactMap { $0.flowMetricsForTest() }.first
    }
#endif
}
