import AppKit

/// A native scroller with a presentation-only flowing knob. The controller
/// places it over the existing scroller gutter, preserving document geometry.
final class FlowScroller: NSScroller {
    private let capsule = CAGradientLayer()
    private let points = (0..<5).map { _ in CALayer() }
    private var tint = PopoverStyle.neutral
    private var animationsEnabled = false
    private var presentationActive = false
    private var lastKnobSize = NSSize.zero
    var onScrollWheel: ((NSEvent) -> Void)?

    static let flowDuration: CFTimeInterval = 3.4
    static let pointOffsets: [Double] = [0, 0.16, 0.22, 0.58, 0.87]
    private static let pointSizes: [CGFloat] = [2.2, 1.5, 2, 1.3, 1.7]
    private static let pointLanes: [CGFloat] = [-0.7, 0.5, -0.1, 0.8, -0.4]

    override class var isCompatibleWithOverlayScrollers: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        capsule.name = "flow-knob"
        capsule.cornerRadius = 3
        capsule.masksToBounds = true
        capsule.locations = [0, 0.72, 1]
        layer?.addSublayer(capsule)
        for (index, point) in points.enumerated() {
            point.name = "flow-point-\(index)"
            capsule.addSublayer(point)
        }
        setAccessibilityLabel("Scroll content")
        refreshAppearance()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var doubleValue: Double { didSet { synchronizeKnob() } }
    override var knobProportion: CGFloat { didSet { synchronizeKnob() } }
    override var isEnabled: Bool { didSet { synchronizeKnob() } }
    override var isHidden: Bool { didSet { syncMotion() } }

    override func layout() { super.layout(); synchronizeKnob() }
    override func drawKnob() { synchronizeKnob() }
    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}
    override func scrollWheel(with event: NSEvent) {
        if let onScrollWheel { onScrollWheel(event) } else { super.scrollWheel(with: event) }
    }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); synchronizeKnob() }
    override func viewDidHide() { super.viewDidHide(); stopMotion() }
    override func viewDidUnhide() { super.viewDidUnhide(); syncMotion() }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
    }

    func update(snapshot: PowerSnapshot) {
        tint = snapshot.state == .mixedSupply ? PopoverStyle.blue : PopoverStyle.stateColor(snapshot.state)
        refreshAppearance()
    }

    func refreshAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let color = tint.usingColorSpace(.sRGB)!
            let surface = PopoverStyle.surface.usingColorSpace(.sRGB)!
            let contrast = PopoverStyle.isHighContrast(effectiveAppearance)
            var reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
#if DEBUG
            if let forced = ProcessInfo.processInfo.environment["WATTSON_FORCE_REDUCE_TRANSPARENCY"] {
                reduceTransparency = forced == "1"
            }
#endif
            PopoverStyle.setWithoutAnimation {
                self.capsule.colors = [
                    color.blended(withFraction: contrast ? 0.25 : 0.70, of: surface)!.cgColor,
                    color.cgColor,
                    color.blended(withFraction: 0.20, of: .white)!.cgColor,
                ]
                self.capsule.borderColor = NSColor.labelColor.cgColor
                self.capsule.borderWidth = contrast ? 0.5 : 0
                for point in self.points {
                    point.backgroundColor = NSColor.white.cgColor
                    point.shadowColor = NSColor.white.cgColor
                    point.shadowOpacity = contrast || reduceTransparency ? 0 : 0.6
                    point.shadowRadius = 1
                    point.shadowOffset = .zero
                }
            }
        }
        synchronizeKnob()
    }

    func setAnimationsEnabled(_ enabled: Bool) { animationsEnabled = enabled; syncMotion() }
    func setPresentationActive(_ active: Bool) { presentationActive = active; syncMotion() }

    /// Called after AppKit lays out the gutter or updates the scroll position.
    /// Native knob metrics also remain the authoritative dragging hit region.
    func synchronizeKnob() {
        let knob = rect(for: .knob)
        let visible = isEnabled && knobProportion > 0 && knobProportion < 1 && !knob.isEmpty
        let frame = NSRect(x: knob.midX - 3, y: knob.minY, width: 6, height: knob.height)
        if frame.size != lastKnobSize {
            stopMotion()
            lastKnobSize = frame.size
        }
        PopoverStyle.setWithoutAnimation {
            self.capsule.isHidden = !visible
            self.capsule.frame = frame
            self.capsule.startPoint = CGPoint(x: 0.5, y: self.isFlipped ? 0 : 1)
            self.capsule.endPoint = CGPoint(x: 0.5, y: self.isFlipped ? 1 : 0)
            for (index, point) in self.points.enumerated() {
                let size = Self.pointSizes[index]
                point.bounds = CGRect(x: 0, y: 0, width: size, height: size)
                point.cornerRadius = size / 2
                let phase = 0.08 + Self.pointOffsets[index] * 0.88
                point.position = CGPoint(x: 3 + Self.pointLanes[index],
                                         y: self.downwardPosition(phase: phase))
                point.opacity = Float(Self.opacity(at: phase))
            }
        }
        syncMotion()
    }

    private func downwardPosition(phase: Double) -> CGFloat {
        capsule.bounds.height * CGFloat(isFlipped ? phase : 1 - phase)
    }

    static func opacity(at phase: Double) -> Double {
        max(0, min(1, (phase - 0.04) / 0.08, (0.96 - phase) / 0.09))
    }

    private static var reducesMotion: Bool {
#if DEBUG
        switch ProcessInfo.processInfo.environment["WATTSON_FORCE_REDUCE_MOTION"] {
        case "1": return true
        case "0": return false
        default: break
        }
#endif
        return NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private func syncMotion() {
        guard animationsEnabled, presentationActive, window?.isVisible == true,
              !isHiddenOrHasHiddenAncestor, !visibleRect.isEmpty,
              !capsule.isHidden, !Self.reducesMotion else { stopMotion(); return }
        let now = CACurrentMediaTime()
        for (index, point) in points.enumerated() where point.animation(forKey: "flow") == nil {
            let animation = Self.flowAnimation(height: capsule.bounds.height,
                                               flipped: isFlipped, pointIndex: index)
            animation.beginTime = point.convertTime(now, from: nil)
            point.add(animation, forKey: "flow")
        }
    }

    /// Position and opacity share one timeline. The repeat jump is invisible
    /// at both ends, so a white point never visibly travels upward.
    static func flowAnimation(height: CGFloat, flipped: Bool, pointIndex: Int) -> CAAnimationGroup {
        let movement = CABasicAnimation(keyPath: "position.y")
        movement.fromValue = flipped ? 0 : height
        movement.toValue = flipped ? height : 0
        movement.duration = flowDuration
        movement.timingFunction = CAMediaTimingFunction(name: .linear)
        let visibility = CAKeyframeAnimation(keyPath: "opacity")
        visibility.values = [0, 0, 1, 1, 0, 0]
        visibility.keyTimes = [0, 0.04, 0.12, 0.87, 0.96, 1]
        visibility.duration = flowDuration
        visibility.calculationMode = .linear
        let group = CAAnimationGroup()
        group.animations = [movement, visibility]
        group.duration = flowDuration
        group.repeatCount = .infinity
        group.timeOffset = pointOffsets[pointIndex] * flowDuration
        return group
    }

    private func stopMotion() {
        for point in points { point.removeAllAnimations() }
    }
}
