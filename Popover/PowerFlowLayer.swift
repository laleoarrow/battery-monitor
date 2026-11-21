import AppKit

/// Coherent downstream measurements add parallel sinks within the same section.
enum FlowLayout: Equatable {
    case adapterLed   // adapter left-centre, system top-right, battery bottom-right
    case batteryLed   // adapter top-left, battery bottom-left, system centre-right
    case batteryOutputSplit // battery left-centre, Mac top-right, device bottom-right
    case adapterOutputSplit // adapter left-centre, Mac / battery / device on the right
    case mixedOutputSplit   // adapter + battery merge, then split to Mac + device
}

/// The single cubic every pipe is built from. Keeping the control points
/// explicit lets particles be seated analytically along the curve instead of
/// depending on an animation having started.
struct PipeGeometry: Equatable {
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
    private static let powerIconConfiguration =
        NSImage.SymbolConfiguration(pointSize: 21, weight: .regular)
    private let box = NSView()
    private let icon = PowerIconImageView()
    private let caption = NSTextField(labelWithString: "")
    private let value = NSTextField(labelWithString: "")
    private var breathingColor: NSColor?
    private(set) var isCompact = false
    private(set) var compactFraction: CGFloat = 0
    private(set) var labelPresence: CGFloat = 1
    private var animateNextContent = false

    func setCompact(_ compact: Bool) {
        guard isCompact != compact || compactFraction != (compact ? 1 : 0) else { return }
        isCompact = compact
        compactFraction = compact ? 1 : 0
        needsLayout = true
    }

    func setCompactFraction(_ fraction: CGFloat) {
        compactFraction = fraction
        needsLayout = true
    }

    func setLabelPresence(_ alpha: CGFloat) {
        labelPresence = alpha
        caption.alphaValue = alpha
        value.alphaValue = alpha
    }

    func animateContentChange() {
        animateNextContent = true
    }

    private func fadeContent(_ view: NSView) {
        let fade = CATransition()
        fade.type = .fade
        fade.duration = 0.16
        view.wantsLayer = true
        view.layer?.add(fade, forKey: "transition")
    }

    func stopContentTransition() {
        animateNextContent = false
        [box, caption, value].forEach { $0.layer?.removeAnimation(forKey: "transition") }
    }
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
        caption.frame = NSRect(x: 0, y: size + 5 - compactFraction * 4, width: bounds.width, height: 14)
        value.frame = NSRect(x: 0, y: size + 20 - compactFraction * 4, width: bounds.width, height: 16)
    }

    func configure(symbol: String, caption text: String, value valueText: String,
                   tint: NSColor, accent: NSColor? = nil, help: String? = nil) {
        if animateNextContent {
            fadeContent(box)
            animateNextContent = false
        }
        if !icon.configurePowerIcon(symbol: symbol, description: text,
                                    accent: accent ?? tint, side: 32, inset: 4) {
            icon.image = Self.nodeIconImage(symbol: symbol, accessibilityDescription: text)
            icon.contentTintColor = tint
        }
        needsLayout = true
        caption.stringValue = text
        value.stringValue = valueText
        value.setAccessibilityLabel(text)
        value.setAccessibilityValue(valueText)
        value.setAccessibilityHelp(help)
        toolTip = help
        box.layer?.backgroundColor = PopoverStyle.well.cgColor
        box.layer?.borderColor = tint.withAlphaComponent(0.34).cgColor
    }

    fileprivate static func nodeIconImage(
        symbol: String,
        accessibilityDescription: String
    ) -> NSImage? {
        if let image = PowerIconImageView.image(for: symbol) { return image }
        switch symbol {
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
            return nodeSymbolImage(named: symbol,
                                   accessibilityDescription: accessibilityDescription)
        }
    }

    private static func nodeSymbolImage(
        named symbol: String,
        accessibilityDescription: String
    ) -> NSImage? {
        guard let source = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: accessibilityDescription
        )?.withSymbolConfiguration(Self.powerIconConfiguration) else { return nil }

        let canvasSize = NSSize(width: nodeIconCanvasSize, height: nodeIconCanvasSize)
        let sourceMax = max(source.size.width, source.size.height)
        let scale = min(1, nodeSymbolDrawExtent / sourceMax)
        let drawSize = NSSize(
            width: source.size.width * scale,
            height: source.size.height * scale
        )
        let image = NSImage(size: canvasSize, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.saveGState()
            context.translateBy(
                x: rect.midX,
                y: rect.midY
            )
            source.draw(
                in: NSRect(
                    x: -drawSize.width / 2,
                    y: -drawSize.height / 2,
                    width: drawSize.width,
                    height: drawSize.height
                )
            )
            context.restoreGState()
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

    var renderedIconForTest: NSImage? { icon.image }
    var iconRenderCountForTest: Int { icon.renderCountForTest }

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
        let resolvedColor = color.usingColorSpace(.sRGB) ?? color
        if let breathingColor,
           breathingColor.isEqual(resolvedColor),
           box.layer?.animation(forKey: "breathe") != nil {
            return
        }
        stopBreathing()
        breathingColor = resolvedColor
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

/// Fixed alpha profiles are sampled once; resolved colors belong to one frame
/// in the view's current appearance and are shared by all six pipe roles.
struct FlowMorphPaint {
    private static let positions: [CGFloat] = [0, 0.10, 0.13, 0.18, 0.21, 0.25, 0.29, 0.32, 0.40, 0.42,
                                               0.50, 0.60, 0.63, 0.68, 0.71, 0.75, 0.79, 0.82, 0.90, 0.92, 1]
    static let locations = positions.map { NSNumber(value: Double($0)) }
    private static let alphaSamples: (ordinary: [CGFloat], mixed: [CGFloat]) = {
        let ordinaryLocations: [CGFloat] = [0, 0.13, 0.21, 0.29, 0.42, 0.50, 0.63, 0.71, 0.79, 0.92, 1]
        let ordinaryAlpha: [CGFloat] = [0, 0.30, 1, 0.30, 0, 0, 0.30, 1, 0.30, 0, 0]
        let mixedLocations: [CGFloat] = [0, 0.10, 0.18, 0.25, 0.32, 0.40, 0.50, 0.60, 0.68, 0.75, 0.82, 0.90, 1]
        let mixedAlpha: [CGFloat] = [0, 0.25, 0.66, 1, 0.66, 0.25, 0, 0.25, 0.66, 1, 0.66, 0.25, 0]
        func alpha(at value: CGFloat, locations: [CGFloat], values: [CGFloat]) -> CGFloat {
            guard let right = locations.firstIndex(where: { $0 >= value }), right > 0 else { return values[0] }
            let fraction = (value - locations[right - 1]) / (locations[right] - locations[right - 1])
            return values[right - 1] + (values[right] - values[right - 1]) * fraction
        }
        return (positions.map { alpha(at: $0, locations: ordinaryLocations, values: ordinaryAlpha) },
                positions.map { alpha(at: $0, locations: mixedLocations, values: mixedAlpha) })
    }()
    let colors: [Any]
#if DEBUG
    private(set) static var buildsForTest = 0
#endif

    init(color: NSColor, themeMix: CGFloat) {
        let mix = min(1, max(0, themeMix))
        colors = Self.alphaSamples.ordinary.indices.map { index in
            let old = Self.alphaSamples.ordinary[index]
            let new = Self.alphaSamples.mixed[index]
            return color.withAlphaComponent(old + (new - old) * mix).cgColor
        }
#if DEBUG
        Self.buildsForTest += 1
#endif
    }
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
    private let clipMask = CAShapeLayer()
    private let particleHost = CALayer()
    private var centeredTheme = false
    private var usesRibbon = false

    private var particles: [CALayer] = []
    private var particleOffsets: [CGFloat] = []
    private var particleOrdinals: [Int?] = []
    private var particlesAreHot = false
    private var particlesAreAnimating = false
    private var particleTopology = ""
    private var geometry = PipeGeometry(start: .zero, control1: .zero, control2: .zero, end: .zero)
    private var particleGeometry: PipeGeometry?
#if DEBUG
    private(set) var particleGeometryUpdatesForTest = 0
    private(set) var particleRideInstallationsForTest = 0
#endif

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
        gradient.locations = [0, 0.13, 0.21, 0.29, 0.42,
                              0.50, 0.63, 0.71, 0.79, 0.92, 1].map { NSNumber(value: $0) }
        flowHost.addSublayer(gradient)
        container.addSublayer(flowHost)
        container.addSublayer(particleHost)
    }

    func apply(geometry newGeometry: PipeGeometry, thickness: CGFloat, color: NSColor,
               bounds: CGRect, animated: Bool,
               taper: (start: CGFloat, end: CGFloat)? = nil,
               clip: CGRect? = nil, centeredTheme: Bool = false) {
        geometry = newGeometry
        let shapeChanged = usesRibbon != (taper != nil)
        usesRibbon = taper != nil
        self.centeredTheme = centeredTheme
        let path: CGPath
        if let taper {
            let ribbon = CGMutablePath()
            ribbon.move(to: CGPoint(x: newGeometry.start.x, y: newGeometry.start.y - taper.start / 2))
            ribbon.addCurve(to: CGPoint(x: newGeometry.end.x, y: newGeometry.end.y - taper.end / 2),
                control1: CGPoint(x: newGeometry.control1.x, y: newGeometry.control1.y - taper.start / 2),
                control2: CGPoint(x: newGeometry.control2.x, y: newGeometry.control2.y - taper.end / 2))
            ribbon.addLine(to: CGPoint(x: newGeometry.end.x, y: newGeometry.end.y + taper.end / 2))
            ribbon.addCurve(to: CGPoint(x: newGeometry.start.x, y: newGeometry.start.y + taper.start / 2),
                control1: CGPoint(x: newGeometry.control2.x, y: newGeometry.control2.y + taper.end / 2),
                control2: CGPoint(x: newGeometry.control1.x, y: newGeometry.control1.y + taper.start / 2))
            ribbon.closeSubpath()
            path = ribbon
        } else { path = newGeometry.path }

        let update = {
            self.trough.strokeColor = taper == nil ? PopoverStyle.trough.cgColor : nil
            self.trough.fillColor = taper == nil ? nil : PopoverStyle.trough.cgColor
            self.trough.path = path
            self.trough.lineWidth = thickness
            self.trough.frame = bounds

            self.flowHost.frame = bounds
            self.flowMask.frame = bounds
            self.flowMask.path = path
            self.flowMask.lineWidth = thickness
            self.flowMask.strokeColor = taper == nil ? NSColor.black.cgColor : nil
            self.flowMask.fillColor = taper == nil ? nil : NSColor.black.cgColor
            if let clip {
                self.clipMask.frame = bounds
                self.clipMask.path = CGPath(rect: clip, transform: nil)
                self.clipMask.fillColor = NSColor.black.cgColor
                self.container.mask = self.clipMask
            } else { self.container.mask = nil }

            if centeredTheme {
                // All five ribbons sample the same periodic field. At rest its
                // visible peak is central; translating one view width repeats it.
                self.gradient.frame = CGRect(x: -bounds.width, y: 0,
                                             width: bounds.width * 2, height: bounds.height)
                self.gradient.locations = [0, 0.10, 0.18, 0.25, 0.32, 0.40, 0.50,
                                           0.60, 0.68, 0.75, 0.82, 0.90, 1]
                self.gradient.colors = [CGFloat(0), 0.25, 0.66, 1, 0.66, 0.25, 0,
                                        0.25, 0.66, 1, 0.66, 0.25, 0]
                    .map { color.withAlphaComponent($0).cgColor }
            } else {
                // Two identical pulses preserve the existing seamless sweep.
                self.gradient.frame = CGRect(x: -bounds.width, y: 0,
                                             width: bounds.width * 2, height: bounds.height)
                self.gradient.locations = [0, 0.13, 0.21, 0.29, 0.42,
                                           0.50, 0.63, 0.71, 0.79, 0.92, 1]
                let clear = color.withAlphaComponent(0).cgColor
                let soft = color.withAlphaComponent(0.30).cgColor
                let core = color.cgColor
                self.gradient.colors = [clear, soft, core, soft, clear,
                                        clear, soft, core, soft, clear, clear]
            }
            self.container.opacity = thickness > 0.5 ? 1 : 0
        }
        if shapeChanged {
            trough.removeAnimation(forKey: "path")
            flowMask.removeAnimation(forKey: "path")
        }
        if animated && !shapeChanged {
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.45)
            update()
            CATransaction.commit()
        } else { PopoverStyle.setWithoutAnimation(update) }
    }

    /// A transition samples one continuous filled contour. Resting `apply`
    /// retains the original stroke/ribbon paths and their native animations.
    func applyMorphPose(pose: FlowEdgePose, paint: FlowMorphPaint, bounds: CGRect,
                        clip: CGRect? = nil) {
        geometry = pose.geometry
        let path = CGMutablePath()
        if !pose.isCollapsed && max(pose.startWidth, pose.endWidth) > 0 {
            var upper: [CGPoint] = []
            var lower: [CGPoint] = []
            let vertical = min(1, max(0, pose.verticalTaper))
            let curve = pose.geometry
            for index in 0...64 {
                let t = CGFloat(index) / 64
                let u = 1 - t
                let point = curve.point(at: t)
                let dx = 3 * u * u * (curve.control1.x - curve.start.x)
                    + 6 * u * t * (curve.control2.x - curve.control1.x)
                    + 3 * t * t * (curve.end.x - curve.control2.x)
                let dy = 3 * u * u * (curve.control1.y - curve.start.y)
                    + 6 * u * t * (curve.control2.y - curve.control1.y)
                    + 3 * t * t * (curve.end.y - curve.control2.y)
                let length = hypot(dx, dy)
                let normal = length > 0.0001 ? CGPoint(x: -dy / length, y: dx / length)
                    : CGPoint(x: 0, y: 1)
                let blend = t * t * (3 - 2 * t)
                let halfWidth = max(0, pose.startWidth + (pose.endWidth - pose.startWidth) * blend) / 2
                let offset = CGPoint(x: normal.x * (1 - vertical) * halfWidth,
                    y: (normal.y * (1 - vertical) + vertical) * halfWidth)
                upper.append(CGPoint(x: point.x - offset.x, y: point.y - offset.y))
                lower.append(CGPoint(x: point.x + offset.x, y: point.y + offset.y))
            }
            path.addLines(between: upper + lower.reversed())
            path.closeSubpath()
        }
        PopoverStyle.setWithoutAnimation {
            self.trough.frame = bounds
            self.trough.path = path
            self.trough.lineWidth = max(pose.startWidth, pose.endWidth)
            self.trough.strokeColor = nil
            self.trough.fillColor = PopoverStyle.trough.cgColor
            self.flowHost.frame = bounds
            self.flowMask.frame = bounds
            self.flowMask.path = path
            self.flowMask.strokeColor = nil
            self.flowMask.fillColor = NSColor.black.cgColor
            if let clip {
                self.clipMask.frame = bounds
                self.clipMask.path = CGPath(rect: clip, transform: nil)
                self.clipMask.fillColor = NSColor.black.cgColor
                self.container.mask = self.clipMask
            } else { self.container.mask = nil }
            self.gradient.frame = CGRect(x: -bounds.width, y: 0,
                                         width: bounds.width * 2, height: bounds.height)
            self.gradient.locations = FlowMorphPaint.locations
            self.gradient.colors = paint.colors
            self.container.isHidden = false
            self.container.opacity = path.isEmpty ? 0 : 1
        }
    }

    func setParticlesHidden(_ hidden: Bool) {
        PopoverStyle.setWithoutAnimation { self.particleHost.opacity = hidden ? 0 : 1 }
    }

    func captureFlowPhase(now: Double) -> (time: Double, offset: Double)? {
        guard let drift = gradient.animation(forKey: "flow"), drift.duration > 0 else { return nil }
        let elapsed = (gradient.convertTime(now, from: nil) - drift.beginTime) * Double(drift.speed)
            + drift.timeOffset
        return (now, FlowMorphParticleSeed.unitPhase(elapsed / drift.duration) * drift.duration)
    }

    func presentationGeometry(fallback: PipeGeometry) -> PipeGeometry {
        guard !usesRibbon, let path = trough.presentation()?.path else { return fallback }
        var start: CGPoint?
        var result: PipeGeometry?
        path.applyWithBlock { element in
            let item = element.pointee
            if item.type == .moveToPoint { start = item.points[0] }
            if item.type == .addCurveToPoint, let start, result == nil {
                result = PipeGeometry(start: start, control1: item.points[0], control2: item.points[1], end: item.points[2])
            }
        }
        return result ?? fallback
    }

    func morphSeeds(route: FlowParticleRoute, now: Double, ordinalBase: Int = 0) -> [FlowMorphParticleSeed] {
        let path = FlowParticlePath(curves: [geometry])
        return particles.enumerated().compactMap { index, dot in
            guard let ride = dot.animation(forKey: "ride") as? CAKeyframeAnimation,
                  ride.duration > 0, dot.speed > 0, ride.speed > 0 else { return nil }
            let local = dot.convertTime(now, from: nil)
            guard local >= ride.beginTime else { return nil }
            let elapsed = (local - ride.beginTime) * Double(ride.speed) + ride.timeOffset
            let phase = FlowMorphParticleSeed.unitPhase(elapsed / ride.duration)
            let point = path.point(at: phase, offset: particleOffsets[index])
            return FlowMorphParticleSeed(route: route, ordinal: particleOrdinals[index] ?? (ordinalBase + index),
                phase: phase, epoch: now, pathLength: path.length,
                wallPeriod: ride.duration / Double(dot.speed * ride.speed),
                offset: particleOffsets[index], radius: dot.bounds.width / 2,
                color: dot.backgroundColor ?? NSColor.white.cgColor,
                shadowColor: dot.shadowColor ?? NSColor.white.cgColor,
                shadowOpacity: dot.shadowOpacity, shadowRadius: dot.shadowRadius,
                position: dot.presentation()?.position ?? point,
                opacity: FlowMorphParticles.opacity(of: dot, phase: phase, now: now))
        }
    }

    func startFlow(multiplier: CGFloat, width: CGFloat,
                   sharedPhase: (time: CFTimeInterval, offset: CFTimeInterval)? = nil) {
        if let sharedPhase {
            let period = VisualEncoding.motionPeriod
            let requested = FlowMorphParticleSeed.unitPhase(sharedPhase.offset / period) * period
            let current = captureFlowPhase(now: sharedPhase.time)?.offset
            let difference = current.map { abs($0 - requested) } ?? period
            let phaseDistance = min(difference, period - difference)
            let aligned = current != nil && phaseDistance < 0.000_001
            let sharedOrigin = gradient.animation(forKey: "flow")?.beginTime == 1
            let synchronized = sharedOrigin && aligned && gradient.speed == Float(multiplier)
            if !synchronized {
                // One captured wall time and phase drive every masked mixed
                // ribbon. Keep an already synchronized layer's activation time:
                // moving it to this commit can blank the preceding render frame.
                let parentTime = gradient.superlayer?.convertTime(sharedPhase.time, from: nil) ?? sharedPhase.time
                let localTime = gradient.convertTime(sharedPhase.time, from: nil)
                PopoverStyle.setWithoutAnimation {
                    self.gradient.speed = Float(multiplier)
                    if sharedOrigin && aligned {
                        // A real speed change keeps the existing, unwrapped
                        // local time and activation origin, including at a wrap.
                        self.gradient.timeOffset = localTime
                            - (parentTime - self.gradient.beginTime) * Double(self.gradient.speed)
                    } else {
                        self.gradient.beginTime = parentTime
                        self.gradient.timeOffset = 1 + sharedPhase.offset
                    }
                }
                // An ordinary drift uses its original local clock until it
                // first joins the shared mixed clock.
                if let drift = gradient.animation(forKey: "flow")?.copy() as? CABasicAnimation,
                   drift.beginTime != 1 {
                    drift.beginTime = 1
                    gradient.add(drift, forKey: "flow")
                }
            }
        }
        if gradient.animation(forKey: "flow") == nil {
            let drift = CABasicAnimation(keyPath: "position.x")
            drift.byValue = width
            drift.duration = VisualEncoding.motionPeriod
            drift.beginTime = sharedPhase != nil ? 1 : gradient.convertTime(CACurrentMediaTime(), from: nil)
            drift.repeatCount = .infinity
            drift.isRemovedOnCompletion = false
            gradient.add(drift, forKey: "flow")
        }
        if sharedPhase == nil {
            // Existing ordinary flow keeps its phase when telemetry changes speed.
            PopoverStyle.setAnimationSpeed(gradient, multiplier: multiplier)
        }
    }

    func stopFlow(preservingStaticDisplay: Bool = true) {
        gradient.removeAllAnimations()
        if centeredTheme {
            PopoverStyle.setWithoutAnimation { self.gradient.position.x = 0 }
        }
        particles.forEach { $0.removeAllAnimations() }
        if preservingStaticDisplay && !particles.isEmpty {
            PopoverStyle.setWithoutAnimation {
                for (index, dot) in self.particles.enumerated() {
                    let seat = self.geometry.point(at: (CGFloat(index) + 0.5) / CGFloat(self.particles.count))
                    dot.position = CGPoint(x: seat.x, y: seat.y + self.particleOffsets[index])
                    dot.opacity = 1
                }
            }
        }
        // The bookkeeping has to match what was just done to the layers.
        // Leaving this true made the pool believe it was still animating, so
        // reopening the popover skipped the rebuild and the sparks stayed dead.
        particlesAreAnimating = false
    }

    func discardGeometryAnimations() {
        [container, trough, flowHost, flowMask, clipMask].forEach { $0.removeAllAnimations() }
        // Preserve the ordinary travelling light when only its geometry is
        // reassigned. Particle rides retain their existing topology handling.
        for key in gradient.animationKeys() ?? [] where key != "flow" {
            gradient.removeAnimation(forKey: key)
        }
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
                          animating: Bool, topology: String,
                          handoff: (seeds: [FlowMorphParticleSeed], route: FlowParticleRoute, now: Double)? = nil) {
        let requested = thickness > 0.5 ? count : 0
        let existingCount = particles.count

        // Hysteresis. The count is a rounded function of a continuously drifting
        // reading, so it oscillates across a boundary — 43 W wants five sparks
        // and 45 W wants six, and the pool rebuilt on every crossing. One spark
        // either way is invisible; churning the pool at 1 Hz is not.
        let wanted: Int
        if requested == 0 || existingCount == 0 {
            wanted = requested
        } else {
            wanted = abs(requested - existingCount) >= 2 ? requested : existingCount
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
        guard wanted != existingCount
            || hot != particlesAreHot
            || animating != particlesAreAnimating
            || topology != particleTopology
            || handoff != nil
        else {
            retargetParticlesToCurrentGeometry()
            retimeParticles(period: period)
            return
        }
        // Replacing sublayers must not create an implicit container transition
        // while the section is static. Explicit ride animations remain intact.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        particlesAreHot = hot
        particlesAreAnimating = animating
        particleTopology = topology

        if handoff == nil {
            particles.forEach { $0.removeFromSuperlayer() }
            particles.removeAll()
            particleOffsets.removeAll()
            particleOrdinals.removeAll()
        } else if particles.count > wanted {
            particles.dropFirst(wanted).forEach { $0.removeAllAnimations(); $0.removeFromSuperlayer() }
            particles.removeLast(particles.count - wanted)
            particleOffsets.removeLast(particleOffsets.count - wanted)
            particleOrdinals.removeLast(particleOrdinals.count - wanted)
        }
        particleGeometry = nil
        guard wanted > 0 else { return }

        var rng = SeededRNG(seed: seed)
        let tint = hot ? PopoverStyle.saturationParticle : NSColor.white
        let basePath = geometry.path
        let handoffPath = handoff.map { _ in FlowParticlePath(curves: [geometry]) }
        let candidates: [(seed: FlowMorphParticleSeed, phase: Double)] = handoff.flatMap { handoff in
            handoffPath.map { path in
                handoff.seeds.compactMap { candidate -> (seed: FlowMorphParticleSeed, phase: Double)? in
                    guard candidate.route == handoff.route else { return nil }
                    let projection = path.project(candidate.position, offset: candidate.offset)
                    guard projection.distance <= 0.75,
                          (projection.phase > 0 && projection.phase < 1) || projection.distance < 0.001 else { return nil }
                    return (seed: candidate, phase: projection.phase)
                }.sorted { $0.seed.ordinal < $1.seed.ordinal }
            }
        } ?? []
#if DEBUG
        particleGeometryUpdatesForTest += 1
#endif

        for index in 0..<wanted {
            var offset = (rng.nextUnit() * 2 - 1) * thickness * 0.36
            var radius = (hot ? 1.3 : 0.85) + rng.nextUnit() * (hot ? 1.9 : 1.4)
            let spread = 1.4 + rng.nextUnit() * 1.1
            let delay = rng.nextUnit()
            let matched = index < candidates.count ? candidates[index] : nil
            if let matched {
                offset = matched.seed.offset
                radius = matched.seed.radius
            }

            let dot = index < particles.count ? particles[index] : CALayer()
            dot.removeAnimation(forKey: "morphArrival")
            dot.removeAnimation(forKey: "morphOpacity")
            dot.bounds = CGRect(x: 0, y: 0, width: radius * 2, height: radius * 2)
            dot.cornerRadius = radius
            dot.backgroundColor = tint.cgColor
            dot.shadowColor = tint.cgColor
            dot.shadowOpacity = hot ? 0.95 : 0.6
            dot.shadowRadius = matched?.seed.shadowRadius ?? (hot ? 4 + radius * 1.9 : 2 + radius)
            dot.shadowOffset = .zero

            // Seat every dot on the curve up front, so they are visible even
            // when animations are off.
            let seat = geometry.point(at: (CGFloat(index) + 0.5) / CGFloat(wanted))
            PopoverStyle.setWithoutAnimation {
                let position = handoff == nil ? seat : geometry.start
                dot.position = matched?.seed.position ?? CGPoint(x: position.x, y: position.y + offset)
                dot.opacity = matched?.seed.opacity ?? (handoff == nil ? 1 : 0)
            }
            if index < particles.count {
                particleOffsets[index] = offset
                particleOrdinals[index] = matched?.seed.ordinal
            } else {
                particleHost.addSublayer(dot)
                particles.append(dot)
                particleOffsets.append(offset)
                particleOrdinals.append(matched?.seed.ordinal)
            }

            guard animating else {
                dot.removeAllAnimations()
                continue
            }
            var shift = CGAffineTransform(translationX: 0, y: offset)
            guard let ridePath = basePath.copy(using: &shift) else { continue }

            // Fixed durations; speed comes from the layer timeline so a refresh
            // can retime without rebuilding.
            let duration = matched.flatMap { matched in
                handoffPath.map { path in
                    matched.seed.wallPeriod * Double(path.length / max(0.001, matched.seed.pathLength)) * (2.4 / period)
                }
            } ?? (2.4 * spread)
            let phase = matched?.phase ?? (handoff == nil ? Double(delay) : 0)
            if handoff != nil { PopoverStyle.setAnimationSpeed(dot, multiplier: CGFloat(2.4 / period)) }
            let start = (handoff?.now ?? CACurrentMediaTime())
                + (handoff != nil && matched == nil ? Double(delay) * 0.12 : 0)
            let animationStart = dot.convertTime(start, from: nil)

            let ride = CAKeyframeAnimation(keyPath: "position")
            ride.path = ridePath
            ride.duration = duration
            ride.beginTime = animationStart
            ride.repeatCount = .infinity
            ride.calculationMode = .paced
            ride.timeOffset = phase * duration
            ride.isRemovedOnCompletion = false

            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 1, 1, 0]
            fade.keyTimes = [0, 0.09, 0.86, 1]
            fade.duration = duration
            fade.beginTime = animationStart
            fade.repeatCount = .infinity
            fade.timeOffset = phase * duration
            fade.isRemovedOnCompletion = false

            dot.add(ride, forKey: "ride")
#if DEBUG
            particleRideInstallationsForTest += 1
#endif
            dot.add(fade, forKey: "fade")
            if let matched {
                FlowMorphParticles.preserveOpacity(on: dot, opacity: matched.seed.opacity,
                                                   phase: phase, now: handoff!.now)
            }
        }
        particleGeometry = geometry
        retimeParticles(period: period)
    }

    /// Keep the existing particle layers and their timelines, but move their
    /// model positions and ride paths onto the latest curve. Power telemetry
    /// can move a split point without changing topology; leaving the original
    /// path in place made the sparks drift beside the pipe.
    private func retargetParticlesToCurrentGeometry() {
        // `apply` also runs for wattage and color changes. Only rebuild ride
        // paths when their actual curve changes; keep speed retiming separate.
        guard particleGeometry != geometry,
              particles.count == particleOffsets.count, !particles.isEmpty else { return }
        let basePath = geometry.path
#if DEBUG
        particleGeometryUpdatesForTest += 1
#endif
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
#if DEBUG
            particleRideInstallationsForTest += 1
#endif
        }
        particleGeometry = geometry
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
    var centeredGradientPeakXForTest: CGFloat? {
        centeredTheme ? gradient.frame.minX + gradient.frame.width * 0.75 : nil
    }

    /// Deterministic recording of the same spatial field used by live CA motion.
    func sampleFlowForPreview(time: CFTimeInterval, multiplier: CGFloat, width: CGFloat) {
        gradient.removeAnimation(forKey: "flow")
        let cycle = (time * Double(multiplier) / VisualEncoding.motionPeriod)
            .truncatingRemainder(dividingBy: 1)
        PopoverStyle.setWithoutAnimation {
            self.gradient.position.x = width * CGFloat(cycle < 0 ? cycle + 1 : cycle)
        }
    }
    var particleLayersForTest: [CALayer] { particles }
    var geometryLayersForTest: [CALayer] { [container, trough, flowHost, flowMask, clipMask, gradient] }
#endif
}

final class PowerFlowView: PopoverSection {
    static let plotHeight: CGFloat = 224
    static let preferredHeight: CGFloat = plotHeight
    private static let particlesStayHotAbove = Double(VisualEncoding.wRef) - 5
    static let adapterLedPositions = [CGPoint(x: 40, y: 90), CGPoint(x: 288, y: 129), CGPoint(x: 288, y: 51)]
    static let batteryLedPositions = [CGPoint(x: 40, y: 51), CGPoint(x: 40, y: 129), CGPoint(x: 288, y: 90)]
    private final class FlippedPlot: NSView { override var isFlipped: Bool { true } }
    private let plot = FlippedPlot()
    private let adapterNode = FlowNodeView()
    private let batteryNode = FlowNodeView()
    private let systemNode = FlowNodeView()
    private let deviceNode = FlowNodeView()
    private var nodes: [FlowNodeView] { [adapterNode, batteryNode, systemNode, deviceNode] }
    private var visibleNodes: [FlowNodeView] { nodes.filter { !$0.isHidden } }
    private let idleConnections = [CAShapeLayer(), CAShapeLayer()]
    private let connectionGlow = USBConnectionGlow()
    private let bundles = FlowEdgeRole.allCases.map { _ in PipeBundle() }
    private let fusionParticles = EnergyFlowParticleLayer()
    private let morphParticles = FlowMorphParticles()
    private var animationsEnabled = false
    private var latest = PowerSnapshot()
    private var particlesAreHot = false
    private var sharedFlowPhase: (time: CFTimeInterval, offset: CFTimeInterval, speed: Float)?
    private var displayedScene = PowerFlowScene.make(snapshot: PowerSnapshot())
    private var displayedColor = PopoverStyle.neutral
    private var displayedTheme: CGFloat = 0
    private var transitionBounds = CGRect.zero
    private var transitionAppearance: NSAppearance.Name?
    private struct TransitionKey: Equatable {
        let layout: FlowLayout
        let state: PowerState
        let chargingState: BatteryChargingState?
        let measuredOutput: Bool
        let adapterActive: Bool
        let discharging: Bool
    }
    private var transitionKey: TransitionKey?
    private struct NumericCorrection {
        let edges: [FlowEdgePose]
        let baseline: [FlowEdgePose]
        let progress: CGFloat
        let alphaResidual: [CGFloat]
    }
    private struct Morph {
        let from: PowerFlowScene
        var to: PowerFlowScene
        let start: CFTimeInterval
        let duration: CFTimeInterval
        let fromColor: NSColor
        var toColor: NSColor
        let fromTheme: CGFloat
        let fromAlpha: [CGFloat]
        let fromCompact: [CGFloat]
        let fromDashAlpha: [Float]
        let fromLabelAlpha: [CGFloat]
        var toAlpha: [CGFloat]
        var numericCorrection: NumericCorrection? = nil
    }
    private var morph: Morph?
    private var displayedProgress: CGFloat = 0
    private var morphTimer: Timer?
    private static let transitionDuration: CFTimeInterval = 0.32
#if DEBUG
    private(set) var transitionInstallationsForTest = 0
#endif

    init() {
        super.init(height: Self.preferredHeight)
        plot.wantsLayer = true
        addSubview(plot)
        for dash in idleConnections {
            dash.fillColor = nil
            dash.lineWidth = 1.4
            dash.lineDashPattern = [3, 6]
            plot.layer?.addSublayer(dash)
        }
        plot.layer?.addSublayer(connectionGlow.container)
        bundles.forEach { plot.layer?.addSublayer($0.container) }
        plot.layer?.addSublayer(fusionParticles.container)
        plot.layer?.addSublayer(morphParticles.container)
        nodes.forEach(plot.addSubview)
        deviceNode.isHidden = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { morphTimer?.invalidate(); connectionGlow.stop() }

    override func layout() {
        super.layout()
        let changed = plot.frame != bounds || transitionBounds != bounds
        plot.frame = bounds
        PopoverStyle.setWithoutAnimation {
            self.bundles.forEach { $0.container.frame = self.plot.bounds }
            self.idleConnections.forEach { $0.frame = self.plot.bounds }
            self.fusionParticles.container.frame = self.plot.bounds
            self.morphParticles.container.frame = self.plot.bounds
        }
        if changed || transitionKey == nil { update(snapshot: latest, animated: false) }
    }

    private func layoutMode(for snapshot: PowerSnapshot) -> FlowLayout { PowerFlowScene.make(snapshot: snapshot).layout }
    private func conditionColor(_ snapshot: PowerSnapshot) -> NSColor {
        guard snapshot.plugged, snapshot.adapterW > 0 else { return PopoverStyle.neutral }
        return snapshot.batteryW > PowerSnapshot.epsilon ? PopoverStyle.green : PopoverStyle.blue
    }
    private func watts(_ value: Double) -> String { value > 0 && value < 0.1 ? "<0.1 W" : PopoverStyle.watts(value) }
    private func particleCount(_ total: Double) -> Int {
        Int((2 + VisualEncoding.t(total) * 6 + VisualEncoding.over(total) * 5).rounded())
    }
    private func applyPositions(_ scene: PowerFlowScene) {
        for index in nodes.indices {
            let node = nodes[index], point = scene.nodes[index]
            node.setCompact(scene.nodeCompact[index])
            node.frame = NSRect(x: point.x - FlowNodeView.stackWidth / 2, y: point.y - FlowNodeView.boxSize / 2,
                width: FlowNodeView.stackWidth, height: scene.nodeCompact[index] ? 68 : 74)
            node.isHidden = !scene.nodeVisible[index]
        }
    }

    func update(snapshot: PowerSnapshot, animated: Bool) {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let target = PowerFlowScene.make(snapshot: snapshot)
            let key = TransitionKey(layout: target.layout, state: snapshot.state,
                chargingState: snapshot.reportedBatteryState,
                measuredOutput: snapshot.coherentDeviceOutputW.map { $0 > 0 } ?? false,
                adapterActive: snapshot.plugged && snapshot.adapterW > 0,
                discharging: snapshot.batteryW < -PowerSnapshot.epsilon)
            let surfaceChanged = transitionBounds != bounds || transitionAppearance != effectiveAppearance.name
            let changesMeaning = transitionKey != nil && transitionKey != key
            let canMorph = !surfaceChanged && animated && animationsEnabled && window != nil && !isHiddenOrHasHiddenAncestor
            latest = snapshot
            particlesAreHot = particlesAreHot ? snapshot.totalInputW >= Self.particlesStayHotAbove
                : snapshot.totalInputW >= Double(VisualEncoding.wRef)
            if changesMeaning && canMorph {
                beginMorph(to: target)
            } else if let active = morph, canMorph && transitionKey == key {
                // Numeric samples correct only the remaining widths. Keep the
                // original easing clock and node staging moving uninterrupted.
                let alpha = nodes.map(\.alphaValue)
                configureNodes(snapshot: snapshot, color: conditionColor(snapshot), layout: target.layout)
                let targetAlpha = nodes.enumerated().map { target.nodeVisible[$0.offset] ? $0.element.alphaValue : 0 }
                if active.to.edges != target.edges || active.toAlpha != targetAlpha {
                    var retargeted = active
                    retargeted.to = target
                    retargeted.toColor = conditionColor(snapshot)
                    retargeted.toAlpha = targetAlpha
                    let baseline = PowerFlowMorph.scene(from: active.from, to: target, progress: displayedProgress)
                    retargeted.numericCorrection = NumericCorrection(edges: displayedScene.edges,
                        baseline: baseline.edges, progress: displayedProgress,
                        alphaResidual: nodes.indices.map { alpha[$0]
                            - nodePresence(index: $0, morph: retargeted, progress: displayedProgress) })
                    morph = retargeted
                }
                zip(nodes, alpha).forEach { $0.setPresence($1) }
            } else {
                if changesMeaning || surfaceChanged || morph != nil {
                    bundles.forEach { $0.discardGeometryAnimations() }
                    idleConnections.forEach { $0.removeAllAnimations() }
                }
                cancelMorph()
                renderResting(target, animated: animated && animationsEnabled && !surfaceChanged && !changesMeaning,
                              renderParticles: !isHiddenOrHasHiddenAncestor)
            }
            transitionKey = key
            transitionBounds = bounds
            transitionAppearance = effectiveAppearance.name
        }
    }

    private func beginMorph(to target: PowerFlowScene) {
        let now = CACurrentMediaTime()
        if morph == nil {
            for role in FlowEdgeRole.allCases {
                displayedScene.edges[role.rawValue].geometry = bundles[role.rawValue]
                    .presentationGeometry(fallback: displayedScene.edges[role.rawValue].geometry)
            }
        }
        let seeds = morph == nil ? captureParticleSeeds(now: now) : morphParticles.currentSeeds(now: now)
        let flowPhase = bundles.compactMap { $0.captureFlowPhase(now: now) }.first ?? (time: now, offset: 0)
        sharedFlowPhase = (now, flowPhase.offset, Float(VisualEncoding.multiplier(latest.totalInputW)))
        let fromAlpha = nodes.map { $0.isHidden ? 0 : $0.alphaValue }
        morphTimer?.invalidate()
        nodes.forEach { $0.animateContentChange() }
        configureNodes(snapshot: latest, color: conditionColor(latest), layout: target.layout)
        let toAlpha = nodes.enumerated().map { target.nodeVisible[$0.offset] ? $0.element.alphaValue : 0 }
        morph = Morph(from: displayedScene, to: target, start: now, duration: Self.transitionDuration,
            fromColor: displayedColor, toColor: conditionColor(latest), fromTheme: displayedTheme,
            fromAlpha: fromAlpha, fromCompact: nodes.map(\.compactFraction),
            fromDashAlpha: idleConnections.map(\.opacity), fromLabelAlpha: nodes.map(\.labelPresence), toAlpha: toAlpha)
        bundles.forEach {
            $0.discardGeometryAnimations(); $0.setParticlesHidden(true)
            $0.startFlow(multiplier: VisualEncoding.multiplier(latest.totalInputW), width: plot.bounds.width,
                         sharedPhase: flowPhase)
        }
        // Prepared 3D sprites describe the resting neck. Retire that local layer
        // while ordinary heads follow the moving graph; never rebuild per frame.
        if !fusionParticles.container.isHidden { fusionParticles.retireForMorph() }
        morphParticles.begin(seeds: seeds, scene: displayedScene, now: now)
        advanceMorph(now: now)
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            self?.advanceMorph(now: CACurrentMediaTime())
        }
        morphTimer = timer
        RunLoop.main.add(timer, forMode: .common)
#if DEBUG
        transitionInstallationsForTest += 1
#endif
    }

    private func advanceMorph(now: CFTimeInterval, progress forced: CGFloat? = nil) {
        effectiveAppearance.performAsCurrentDrawingAppearance { self.renderMorph(now: now, progress: forced) }
    }

    private func renderMorph(now: CFTimeInterval, progress forced: CGFloat?) {
        guard let morph else { return }
        let progress = min(1, max(0, forced ?? CGFloat((now - morph.start) / morph.duration)))
        if progress >= 0.32 && !fusionParticles.container.isHidden {
            fusionParticles.stop(preservingStaticDisplay: false)
            PopoverStyle.setWithoutAnimation { self.fusionParticles.container.isHidden = true }
        }
        if progress >= 1 {
            let target = PowerFlowScene.make(snapshot: latest)
            let handoffTime = CACurrentMediaTime()
            morphParticles.update(scene: target, now: handoffTime)
            let seeds = morphParticles.currentSeeds(now: handoffTime)
            stopMorphTimer()
            PopoverStyle.setWithoutAnimation {
                self.renderResting(target, animated: false, handoffSeeds: seeds, handoffTime: handoffTime)
                // Keep the bridge visible until the native heads have their
                // final geometry, phase and opacity installed exactly once.
                self.cancelMorph()
            }
            return
        }
        let eased = progress * progress * (3 - 2 * progress)
        var scene = PowerFlowMorph.scene(from: morph.from, to: morph.to, progress: progress)
        let correctionWeight = morph.numericCorrection.map { remainingCorrection($0, progress: progress) } ?? 0
        if let correction = morph.numericCorrection {
            applyNumericCorrection(&scene, correction: correction, weight: correctionWeight)
        }
        let color = morph.fromColor.blended(withFraction: eased, of: morph.toColor) ?? morph.toColor
        let theme = morph.fromTheme + ((morph.to.layout == .mixedOutputSplit ? 1 : 0) - morph.fromTheme) * eased
        let paint = FlowMorphPaint(color: color, themeMix: theme)
        PopoverStyle.setWithoutAnimation {
            self.applyPositions(scene)
            for index in self.nodes.indices {
                let residual = morph.numericCorrection?.alphaResidual[index] ?? 0
                let presence = self.nodePresence(index: index, morph: morph, progress: progress)
                    + residual * correctionWeight
                self.nodes[index].setPresence(min(1, max(0, presence)))
                var labelAlpha = morph.fromLabelAlpha[index] + (1 - morph.fromLabelAlpha[index]) * eased
                if index == 1 && abs(morph.from.nodes[1].x - morph.to.nodes[1].x) > 0.001 {
                    let departure = min(1, progress / PowerFlowMorph.batteryDepartureEnd)
                    let arrival = min(1, max(0, (progress - PowerFlowMorph.batteryTravelEnd)
                        / (PowerFlowMorph.arrivalEnd - PowerFlowMorph.batteryTravelEnd)))
                    labelAlpha = morph.fromLabelAlpha[index] * (1 - departure * departure * (3 - 2 * departure))
                        + arrival * arrival * (3 - 2 * arrival)
                }
                self.nodes[index].setLabelPresence(labelAlpha)
                var compactProgress = eased
                if index != 0 && abs(morph.from.nodes[1].x - morph.to.nodes[1].x) > 0.001 {
                    let staged = morph.to.nodes[1].x < morph.from.nodes[1].x
                        ? max(0, min(1, (progress - 0.5) / 0.35)) : min(1, progress / 0.3)
                    compactProgress = staged * staged * (3 - 2 * staged)
                } else if index != 0 && !morph.from.nodeVisible[3] && morph.to.nodeVisible[3] {
                    let staged = min(1, progress / 0.6)
                    compactProgress = staged * staged * (3 - 2 * staged)
                }
                let compact = morph.fromCompact[index]
                    + ((morph.to.nodeCompact[index] ? CGFloat(1) : 0) - morph.fromCompact[index]) * compactProgress
                self.nodes[index].setCompactFraction(compact)
                self.nodes[index].frame.size.height = 74 - compact * 6
            }
            for role in FlowEdgeRole.allCases {
                self.bundles[role.rawValue].applyMorphPose(pose: scene.edges[role.rawValue], paint: paint,
                    bounds: self.plot.bounds, clip: self.clip(for: role, scene: scene))
            }
            self.renderDashes(scene, color: color,
                motionAllowed: self.animationsEnabled && self.window != nil && !self.isHiddenOrHasHiddenAncestor,
                from: morph.from, to: morph.to,
                progress: progress, fromAlpha: morph.fromDashAlpha)
            self.plot.layer?.opacity = 1
        }
        morphParticles.update(scene: scene, now: now)
        displayedScene = scene
        displayedColor = color
        displayedTheme = theme
        displayedProgress = progress
    }

    private func nodePresence(index: Int, morph: Morph, progress: CGFloat) -> CGFloat {
        var amount = progress * progress * (3 - 2 * progress)
        if (index == 0 || index == 3) && !morph.to.nodeVisible[index] {
            amount = min(1, progress / PowerFlowMorph.nodeDepartureEnd)
        }
        if (index == 0 || index == 3) && morph.fromAlpha[index] == 0 {
            let arrival = min(1, max(0, (progress - PowerFlowMorph.batteryTravelEnd)
                / (PowerFlowMorph.arrivalEnd - PowerFlowMorph.batteryTravelEnd)))
            amount = arrival * arrival * (3 - 2 * arrival)
        }
        return morph.fromAlpha[index] + (morph.toAlpha[index] - morph.fromAlpha[index]) * amount
    }

    private func remainingCorrection(_ correction: NumericCorrection, progress: CGFloat) -> CGFloat {
        guard progress > correction.progress else { return 1 }
        let anchor = correction.progress * correction.progress * (3 - 2 * correction.progress)
        let current = progress * progress * (3 - 2 * progress)
        return anchor < 1 ? min(1, max(0, (1 - current) / (1 - anchor))) : 0
    }

    private func applyNumericCorrection(_ scene: inout PowerFlowScene,
                                        correction: NumericCorrection, weight: CGFloat) {
        if weight == 1 {
            scene.edges = correction.edges
            if scene.idleDevice != nil { scene.idleDevice = scene.deviceConnectionGeometry() }
            scene.mixedCommonWidth = scene.jointStart == scene.jointEnd ? 0 : scene.edges[FlowEdgeRole.common.rawValue].startWidth
            return
        }
        func point(_ value: CGPoint, _ prior: CGPoint, _ baseline: CGPoint) -> CGPoint {
            CGPoint(x: value.x + (prior.x - baseline.x) * weight,
                    y: value.y + (prior.y - baseline.y) * weight)
        }
        for index in scene.edges.indices {
            let prior = correction.edges[index], baseline = correction.baseline[index]
            var edge = scene.edges[index]
            edge.geometry = PipeGeometry(
                start: point(edge.geometry.start, prior.geometry.start, baseline.geometry.start),
                control1: point(edge.geometry.control1, prior.geometry.control1, baseline.geometry.control1),
                control2: point(edge.geometry.control2, prior.geometry.control2, baseline.geometry.control2),
                end: point(edge.geometry.end, prior.geometry.end, baseline.geometry.end))
            edge.startWidth += (prior.startWidth - baseline.startWidth) * weight
            edge.endWidth += (prior.endWidth - baseline.endWidth) * weight
            scene.edges[index] = edge
        }
        if scene.idleDevice != nil { scene.idleDevice = scene.deviceConnectionGeometry() }
        scene.mixedCommonWidth = scene.jointStart == scene.jointEnd ? 0 : scene.edges[FlowEdgeRole.common.rawValue].startWidth
    }

    private func stopMorphTimer() {
        morphTimer?.invalidate(); morphTimer = nil
        morph = nil
    }
    private func cancelMorph() {
        stopMorphTimer()
        morphParticles.clear()
        bundles.forEach { $0.setParticlesHidden(false) }
    }
    private func settleTransition(renderParticles: Bool = true) {
        guard morph != nil else { return }
        cancelMorph()
        renderResting(PowerFlowScene.make(snapshot: latest), animated: false, renderParticles: renderParticles)
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            settleTransition(renderParticles: false)
            stopMotion(preservingStaticDisplay: false)
        }
        super.viewWillMove(toWindow: newWindow)
    }
    override func viewDidHide() {
        settleTransition(renderParticles: false)
        stopMotion(preservingStaticDisplay: false)
        super.viewDidHide()
    }
    override func viewDidUnhide() {
        super.viewDidUnhide()
        if animationsEnabled { update(snapshot: latest, animated: false) }
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil && animationsEnabled { update(snapshot: latest, animated: false) }
    }
    override func viewDidChangeEffectiveAppearance() {
        settleTransition()
        super.viewDidChangeEffectiveAppearance()
        effectiveAppearance.performAsCurrentDrawingAppearance {
            self.connectionGlow.configure(geometry: self.displayedScene.idleDevice,
                color: self.conditionColor(self.latest), bounds: self.plot.bounds,
                opacity: self.idleConnections[1].opacity,
                animated: self.animationsEnabled && self.window != nil && !self.isHiddenOrHasHiddenAncestor)
        }
    }
    override func viewDidChangeBackingProperties() { settleTransition(); super.viewDidChangeBackingProperties() }

    private func clip(for role: FlowEdgeRole, scene: PowerFlowScene) -> CGRect? {
        guard scene.jointEnd.x - scene.jointStart.x > 0.01 else { return nil }
        switch role {
        case .adapterInput, .batteryInput:
            return CGRect(x: 0, y: 0, width: max(0, scene.jointStart.x), height: bounds.height)
        case .systemOutput, .batteryCharge, .deviceOutput:
            return CGRect(x: scene.jointEnd.x, y: 0, width: max(0, bounds.width - scene.jointEnd.x), height: bounds.height)
        case .common:
            return CGRect(x: scene.jointStart.x, y: 0, width: scene.jointEnd.x - scene.jointStart.x, height: bounds.height)
        }
    }
    private func renderDashes(_ scene: PowerFlowScene, color: NSColor, motionAllowed: Bool,
                              from: PowerFlowScene? = nil,
                              to: PowerFlowScene? = nil, progress: CGFloat = 1, fromAlpha: [Float]? = nil) {
        let paths = [scene.idleBattery, scene.idleDevice]
        let old = from.map { [$0.idleBattery, $0.idleDevice] } ?? paths
        let target = to.map { [$0.idleBattery, $0.idleDevice] } ?? paths
        for index in idleConnections.indices {
            let dash = idleConnections[index]
            dash.path = paths[index]?.path
            dash.strokeColor = PopoverStyle.neutral.withAlphaComponent(0.45).cgColor
            let initial = fromAlpha.map { CGFloat($0[index]) } ?? (old[index] == nil ? 0 : 1)
            let final: CGFloat = target[index] == nil ? 0 : 1
            let eased = progress * progress * (3 - 2 * progress)
            var visibility = initial + (final - initial) * eased
            if index == 0, let from, let to, abs(from.nodes[1].x - to.nodes[1].x) > 0.001 {
                visibility = old[index] == nil
                    ? min(1, max(0, (progress - PowerFlowMorph.batteryTravelEnd)
                        / (PowerFlowMorph.arrivalEnd - PowerFlowMorph.batteryTravelEnd)))
                    : initial * max(0, 1 - progress / PowerFlowMorph.batteryDepartureEnd)
            }
            if index == 1, to?.nodeVisible[3] == false {
                visibility = initial * max(0, 1 - progress / PowerFlowMorph.nodeDepartureEnd)
            }
            dash.opacity = Float(visibility)
        }
        connectionGlow.configure(geometry: scene.idleDevice, color: color, bounds: plot.bounds,
                                 opacity: idleConnections[1].opacity, animated: motionAllowed)
    }
    private func renderResting(_ scene: PowerFlowScene, animated: Bool,
                               handoffSeeds: [FlowMorphParticleSeed]? = nil, handoffTime: Double? = nil,
                               renderParticles: Bool = true) {
        let color = conditionColor(latest)
        let moving = animationsEnabled && renderParticles && window != nil && !isHiddenOrHasHiddenAncestor
        applyPositions(scene)
        nodes.forEach { $0.setLabelPresence(1) }
        configureNodes(snapshot: latest, color: color, layout: scene.layout, motionEnabled: moving)
        let now = handoffTime ?? CACurrentMediaTime()
        if scene.layout == .mixedOutputSplit && moving {
            let offset = sharedFlowPhase.map { ($0.offset + (now - $0.time) * Double($0.speed))
                .truncatingRemainder(dividingBy: VisualEncoding.motionPeriod) } ?? 0
            sharedFlowPhase = (now, offset, Float(VisualEncoding.multiplier(latest.totalInputW)))
        }
        let fusion = scene.layout == .mixedOutputSplit && latest.adapterW > 0 && latest.batteryW < -PowerSnapshot.epsilon
            && (latest.coherentDeviceOutputW ?? 0) > 0 && latest.systemW > (latest.coherentDeviceOutputW ?? 0)
        let nativeRoutes = Dictionary(uniqueKeysWithValues: routes(for: scene))
        let assignedSeeds = fusion ? nil : handoffSeeds.map { partitionHandoff($0, scene: scene, routes: nativeRoutes) }
        for role in FlowEdgeRole.allCases {
            let pose = scene.edges[role.rawValue], bundle = bundles[role.rawValue]
            let width = pose.isCollapsed ? 0 : pose.startWidth
            PopoverStyle.setWithoutAnimation { bundle.container.isHidden = pose.isCollapsed || width <= 0.5 }
            bundle.apply(geometry: pose.geometry, thickness: width, color: color,
                bounds: plot.bounds, animated: animated,
                taper: pose.verticalTaper == 1 ? (pose.startWidth, pose.endWidth) : nil,
                clip: clip(for: role, scene: scene), centeredTheme: scene.layout == .mixedOutputSplit)
            let active = width > 0.5
            let handoff = assignedSeeds.flatMap { assignments in
                nativeRoutes[role].map { (seeds: assignments[role] ?? [], route: $0, now: now) }
            }
            bundle.rebuildParticles(count: !renderParticles || fusion ? 0 : role == .common ? 2 : particleCount(latest.totalInputW),
                thickness: pose.isCollapsed ? 0 : min(pose.startWidth, pose.endWidth), color: color,
                period: 2.4 / Double(VisualEncoding.multiplier(latest.totalInputW)),
                seed: [11, 29, 47, 29, 71, 89][role.rawValue], hot: particlesAreHot,
                animating: moving && active, topology: "edge.\(role.rawValue)", handoff: handoff)
            if moving && active {
                bundle.startFlow(multiplier: VisualEncoding.multiplier(latest.totalInputW), width: plot.bounds.width,
                    sharedPhase: scene.layout == .mixedOutputSplit ? sharedFlowPhase.map { ($0.time, $0.offset) } : nil)
            } else { bundle.stopFlow() }
        }
        PopoverStyle.setWithoutAnimation {
            self.renderDashes(scene, color: color, motionAllowed: moving)
            self.fusionParticles.container.isHidden = !fusion || !renderParticles
        }
        if fusion && renderParticles {
            fusionParticles.configure(incoming: [scene.edges[0].geometry, scene.edges[1].geometry],
                outgoing: [scene.edges[2].geometry, scene.edges[4].geometry],
                jointWidth: scene.mixedCommonWidth, snapshot: latest,
                inputWidths: [scene.edges[0].startWidth, scene.edges[1].startWidth],
                outputWidths: [scene.edges[2].endWidth, scene.edges[4].endWidth],
                particleCount: particleCount(latest.totalInputW), hot: particlesAreHot,
                color: color, bounds: plot.bounds, animationsEnabled: moving,
                handoffSeeds: handoffSeeds, handoffTime: handoffTime)
        } else { fusionParticles.stop(preservingStaticDisplay: false) }
        displayedScene = scene
        displayedColor = color
        displayedTheme = scene.layout == .mixedOutputSplit ? 1 : 0
    }

    private func partitionHandoff(_ seeds: [FlowMorphParticleSeed], scene: PowerFlowScene,
                                   routes: [FlowEdgeRole: FlowParticleRoute]) -> [FlowEdgeRole: [FlowMorphParticleSeed]] {
        // A shared endpoint belongs to its downstream leg, never to both
        // native pools. Nearest projection wins away from the exact seam.
        let ordered: [FlowEdgeRole] = [.systemOutput, .batteryCharge, .deviceOutput, .common, .adapterInput, .batteryInput]
        let paths = ordered.compactMap { role -> (FlowEdgeRole, FlowParticleRoute, FlowParticlePath)? in
            let edge = scene.edges[role.rawValue]
            guard let route = routes[role], !edge.isCollapsed,
                  min(edge.startWidth, edge.endWidth) > 0.5 else { return nil }
            let path = FlowParticlePath(curves: [edge.geometry])
            return path.length > 0 ? (role, route, path) : nil
        }
        var assigned: [FlowEdgeRole: [FlowMorphParticleSeed]] = [:]
        for seed in seeds {
            var owner: FlowEdgeRole?
            var closest = CGFloat.infinity
            for (role, route, path) in paths where route == seed.route {
                let projection = path.project(seed.position, offset: seed.offset)
                guard projection.distance <= 0.75,
                      (projection.phase > 0 && projection.phase < 1) || projection.distance < 0.001 else { continue }
                if owner == nil || projection.distance < closest - 0.000_000_1 {
                    owner = role
                    closest = projection.distance
                }
            }
            if let owner { assigned[owner, default: []].append(seed) }
        }
        return assigned
    }

    private func routes(for scene: PowerFlowScene) -> [(FlowEdgeRole, FlowParticleRoute)] {
        switch scene.layout {
        case .adapterLed, .adapterOutputSplit:
            return [(.systemOutput, .adapterSystem), (.batteryCharge, .adapterBattery), (.deviceOutput, .adapterDevice)]
        case .batteryLed:
            return [(.adapterInput, .adapterSystem), (.batteryInput, .batterySystem)]
        case .batteryOutputSplit:
            return [(.systemOutput, .batterySystem), (.deviceOutput, .batteryDevice)]
        case .mixedOutputSplit:
            return [(.adapterInput, .adapterSystem), (.batteryInput, .batterySystem),
                    (.systemOutput, .adapterSystem), (.deviceOutput, .batteryDevice), (.common, .adapterSystem)]
        }
    }
    private func captureParticleSeeds(now: Double) -> [FlowMorphParticleSeed] {
        if !fusionParticles.container.isHidden { return fusionParticles.morphSeeds(now: now) }
        return routes(for: displayedScene).flatMap {
            bundles[$0.0.rawValue].morphSeeds(route: $0.1, now: now, ordinalBase: $0.0.rawValue * 1000)
        }
    }
    private func configureNodes(snapshot: PowerSnapshot, color: NSColor, layout: FlowLayout,
                                motionEnabled: Bool? = nil) {
        let batterySymbol = PowerIconImageView.batterySymbol(percent: snapshot.percent)
        [adapterNode, systemNode, deviceNode].forEach { $0.setBreathing(false, color: color) }
        let split = layout == .adapterOutputSplit || layout == .mixedOutputSplit || layout == .batteryOutputSplit
        let measuredOutput = snapshot.coherentDeviceOutputW.flatMap { $0 > 0 ? $0 : nil }
        let output = split ? measuredOutput ?? 0 : 0
        let pendingUSB = split && measuredOutput == nil
        let mac = snapshot.systemW - output
        systemNode.configure(symbol: "cpu", caption: pendingUSB ? "System Total" : split ? "Mac Load" : "System",
                             value: watts(mac), tint: PopoverStyle.neutral,
                             accent: mac > 0 ? color : PopoverStyle.neutral)
        systemNode.setPresence(mac > 0 ? 1 : 0.6)
        switch layout {
        case .adapterLed, .adapterOutputSplit:
            adapterNode.configure(symbol: "powerplug", caption: "Adapter", value: watts(snapshot.adapterW), tint: color)
            adapterNode.setPresence(snapshot.adapterW > 0 ? 1 : 0.28)
            let charging = snapshot.batteryW > PowerSnapshot.epsilon
            let caption = charging ? "To Battery"
                : snapshot.reportedBatteryState == .charging ? "Battery"
                : "Battery · \(PopoverStyle.batteryFlowLabel(snapshot))"
            batteryNode.configure(symbol: charging ? "battery.100.bolt" : batterySymbol,
                caption: caption, value: charging ? watts(snapshot.batteryW) : "\(snapshot.percent) %",
                tint: charging ? color : PopoverStyle.neutral)
            batteryNode.setPresence(charging ? 1 : 0.6)
            batteryNode.setBreathing(!charging && (motionEnabled ?? animationsEnabled), color: color)
        case .batteryLed, .mixedOutputSplit:
            batteryNode.setBreathing(false, color: color)
            let unplugged = snapshot.state == .onBattery
            adapterNode.configure(symbol: unplugged ? "powerplug.slash" : "powerplug", caption: "Adapter",
                value: unplugged ? "Unplugged" : watts(snapshot.adapterW), tint: unplugged ? PopoverStyle.neutral : color)
            adapterNode.setPresence(!unplugged && snapshot.adapterW > 0 ? 1 : 0.28)
            batteryNode.configure(symbol: batterySymbol,
                caption: unplugged ? "Battery \(snapshot.percent)%" : "Battery Assist",
                value: watts(abs(snapshot.batteryW)), tint: color)
            batteryNode.setPresence(1)
        case .batteryOutputSplit:
            batteryNode.setBreathing(false, color: color)
            batteryNode.configure(symbol: batterySymbol, caption: "Battery \(snapshot.percent)%",
                value: pendingUSB && snapshot.batteryW >= -PowerSnapshot.epsilon
                    ? "\(snapshot.percent) %" : watts(abs(snapshot.batteryW)), tint: color)
            batteryNode.setPresence(1)
        }
        if split {
            configureDevice(deviceNode, output: measuredOutput, color: color)
            deviceNode.setPresence(1)
        }
    }

    private func configureDevice(_ node: FlowNodeView, output: Double?, color: NSColor) {
        node.configure(symbol: "device.output.port", caption: output == nil ? "USB Device" : "Device Output",
            value: output.map(watts) ?? "Connected", tint: color,
            help: output == nil
                ? "USB device connected. System Total is shown without a separate device power value."
                : nil)
    }

    func setAnimationsEnabled(_ enabled: Bool) {
        guard animationsEnabled != enabled else { return }
        animationsEnabled = enabled
        if enabled { update(snapshot: latest, animated: false) }
        else {
            settleTransition()
            stopMotion()
        }
    }
    private func stopMotion(preservingStaticDisplay: Bool = true) {
        sharedFlowPhase = nil
        connectionGlow.stop()
        bundles.forEach {
            $0.discardGeometryAnimations()
            $0.stopFlow(preservingStaticDisplay: preservingStaticDisplay)
        }
        nodes.forEach { $0.stopBreathing(); $0.stopContentTransition() }
        fusionParticles.stop(preservingStaticDisplay: preservingStaticDisplay)
    }
#if DEBUG
    var connectionGlowForTest: USBConnectionGlow { connectionGlow }
    var displayedSceneForTest: PowerFlowScene { displayedScene }
    var semanticNodeFramesForTest: [NSRect] { nodes.map(\.frame) }
    var semanticNodeCompactFractionsForTest: [CGFloat] { nodes.map(\.compactFraction) }
    var semanticNodeAlphasForTest: [CGFloat] { nodes.map { $0.isHidden ? 0 : $0.alphaValue } }
    var semanticNodeLabelAlphasForTest: [CGFloat] { nodes.map(\.labelPresence) }
    var idleOpacitiesForTest: [Float] { idleConnections.map(\.opacity) }
    func advanceTransitionForTest(progress: CGFloat) { advanceMorph(now: CACurrentMediaTime(), progress: progress) }
    var transitionOverlayCountForTest: Int { 0 }
    var transitionIsAnimatingForTest: Bool { morphTimer != nil }
    var transitionTargetOpacityForTest: Float { plot.layer?.opacity ?? 1 }
    var transitionDurationForTest: CFTimeInterval? { morph == nil ? nil : Self.transitionDuration }
    var transitionDeadlineForTest: CFTimeInterval? { morph.map { $0.start + $0.duration } }
    var numericCorrectionProgressForTest: CGFloat? { morph?.numericCorrection?.progress }
    func installParticleHandoffForTest(snapshot: PowerSnapshot, seeds: [FlowMorphParticleSeed], now: Double) {
        latest = snapshot
        renderResting(PowerFlowScene.make(snapshot: snapshot), animated: false,
                      handoffSeeds: seeds, handoffTime: now)
    }
    func particleHandoffOwnersForTest(ordinal: Int, now: Double) -> [FlowEdgeRole] {
        routes(for: displayedScene).compactMap { role, route in
            bundles[role.rawValue].morphSeeds(route: route, now: now).contains { $0.ordinal == ordinal } ? role : nil
        }
    }
    private var visualRoles: [FlowEdgeRole] {
        switch displayedScene.layout {
        case .adapterLed: return [.systemOutput, .batteryCharge]
        case .adapterOutputSplit: return [.systemOutput, .batteryCharge, .deviceOutput]
        case .batteryLed: return [.adapterInput, .batteryInput]
        case .batteryOutputSplit: return [.systemOutput, .deviceOutput]
        case .mixedOutputSplit: return [.adapterInput, .systemOutput, .batteryInput, .deviceOutput, .common]
        }
    }
    var pipeGeometryLayersForTest: [CALayer] { visualRoles.flatMap { bundles[$0.rawValue].geometryLayersForTest } }
    var topologyForTest: String { String(describing: layoutMode(for: latest)) }
    var nodePresentationsForTest: [(caption: String, value: String)] { visibleNodes.map(\.presentationForTest) }
    var nodeIconImagesForTest: [NSImage?] { visibleNodes.map(\.renderedIconForTest) }
    var nodeIconRenderCountsForTest: [Int] { visibleNodes.map(\.iconRenderCountForTest) }
    var nodeFramesForTest: [NSRect] { visibleNodes.map(\.frame) }
    var compactFlagsForTest: [Bool] { visibleNodes.map(\.isCompact) }
    var conditionColorForTest: NSColor { conditionColor(latest) }
    var mixedCommonWidthForTest: CGFloat { displayedScene.mixedCommonWidth }
    var idleEndpointXsForTest: [CGFloat] {
        let boxes = idleConnections.compactMap { $0.path?.boundingBox }
        guard let minX = boxes.map(\.minX).min(), let maxX = boxes.map(\.maxX).max() else { return [] }
        return [minX, maxX]
    }
    var mixedGradientPeakXForTest: CGFloat {
        displayedScene.layout == .mixedOutputSplit ? bundles[0].centeredGradientPeakXForTest ?? 0 : 0
    }
    var fusionParticleLayerForTest: EnergyFlowParticleLayer { fusionParticles }
    var nodeContentsFitForTest: Bool { visibleNodes.allSatisfy {
        $0.contentFitsBoundsForTest && $0.frame.minY >= plot.bounds.minY && $0.frame.maxY <= plot.bounds.maxY
    } }
    var branchThicknessesForTest: [CGFloat] { visualRoles.map { bundles[$0.rawValue].thicknessForTest } }
    var branchParticleCountsForTest: [Int] { visualRoles.map { bundles[$0.rawValue].particleLayersForTest.count } }
    var fusionParticlesVisibleForTest: Bool { !fusionParticles.container.isHidden }
    var particleGeometryUpdatesForTest: Int { bundles.reduce(0) { $0 + $1.particleGeometryUpdatesForTest } }
    var particleRideInstallationsForTest: Int { bundles.reduce(0) { $0 + $1.particleRideInstallationsForTest } }
    var particleLayersForTest: [CALayer] { bundles.flatMap(\.particleLayersForTest)
        + (fusionParticles.container.isHidden ? [] : fusionParticles.particleLayersForTest) }
    var breathingMetricsForTest: (running: Int, installations: Int) {
        (visibleNodes.reduce(0) { $0 + $1.breathingAnimationCountForTest },
         visibleNodes.reduce(0) { $0 + $1.breathingInstallationsForTest })
    }
    func flowMetricsForTest() -> (duration: CFTimeInterval, layerSpeed: Float)? {
        bundles.compactMap { $0.flowMetricsForTest() }.first
    }
#endif
}
