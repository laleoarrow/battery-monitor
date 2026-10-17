import AppKit

/// A data-driven two-minute chart. Matched readings share a bounded viewport
/// transition; no timer, fabricated readings, or incompatible path morphing.
final class HistoryView: PopoverSection {
    static let chartHeight: CGFloat = 64
    static let headerHeight: CGFloat = 22
    static let plotHeight: CGFloat = headerHeight + chartHeight
    static let preferredHeight: CGFloat = plotHeight + PopoverStyle.sectionPadding * 2

    private let clip = CALayer()
    private let reveal = CALayer()
    private let line = CAShapeLayer()
    private let head = CALayer()
    private let headClip = CALayer()
    private let headClipMask = CAShapeLayer()
    private let gradientMask = CAShapeLayer()
    private let areaGradient = CAGradientLayer()
    private let caption = NSTextField(labelWithString: "Power History · 2 min")
    private let peakLabel = NSTextField(labelWithString: "")
    private var lastSamples: [Double]?
    private var lastTiming: HistoryChartTiming?
    private var lastPeak: Double?
    private var lastColor: NSColor?
    private var lastGeometry: HistoryChartGeometry?
    private var lastDrawingSamples: [Double] = []
    private var lastDrawingTiming: HistoryChartTiming?
    private var scale = HistoryChartScale()
    private var presentationActive = false
    private var animationsEnabled = false
#if DEBUG
    private(set) var renderCountForTest = 0
    var chartPathForTest: CGPath? { line.path }
    func pathForTest(_ geometry: HistoryChartGeometry, filled: Bool = false) -> CGPath {
        path(for: geometry, filled: filled)
    }
    var chartCeilingForTest: Double { scale.ceiling }
    var hasChartAnimationForTest: Bool {
        line.animation(forKey: "history.stroke") != nil
            || gradientMask.animation(forKey: "history.fill") != nil
            || areaGradient.animation(forKey: "history.gradient.startPoint") != nil
            || areaGradient.animation(forKey: "history.gradient.endPoint") != nil
            || reveal.animation(forKey: "history.reveal") != nil
            || head.animation(forKey: "history.head") != nil
    }
#endif

    init() {
        super.init(height: Self.preferredHeight)
        clip.masksToBounds = true
        reveal.anchorPoint = .zero
        reveal.backgroundColor = NSColor.black.cgColor
        clip.mask = reveal
        layer?.addSublayer(clip)
        areaGradient.mask = gradientMask
        gradientMask.fillColor = NSColor.black.cgColor
        gradientMask.strokeColor = nil
        clip.addSublayer(areaGradient)
        line.fillColor = nil
        line.lineWidth = 1.6
        line.lineJoin = .round
        line.lineCap = .round
        clip.addSublayer(line)
        head.cornerRadius = 2.6
        head.opacity = 0
        headClip.mask = headClipMask
        headClipMask.fillColor = NSColor.black.cgColor
        headClip.addSublayer(head)
        layer?.addSublayer(headClip)
        caption.font = .systemFont(ofSize: 11, weight: .regular)
        caption.textColor = PopoverStyle.secondaryText
        addSubview(caption)
        peakLabel.font = PopoverStyle.mono(11, .regular)
        peakLabel.textColor = PopoverStyle.tertiaryText
        peakLabel.alignment = .right
        addSubview(peakLabel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var chartRect: CGRect {
        CGRect(x: 0, y: PopoverStyle.sectionPadding + Self.headerHeight,
               width: PopoverStyle.contentWidth, height: Self.chartHeight)
    }

    override func layout() {
        super.layout()
        caption.frame = NSRect(x: 0, y: PopoverStyle.sectionPadding, width: 180, height: 15)
        peakLabel.frame = NSRect(x: PopoverStyle.contentWidth - 160,
                                 y: PopoverStyle.sectionPadding, width: 160, height: 15)
        PopoverStyle.setWithoutAnimation {
            self.clip.frame = self.chartRect
            self.line.frame = self.clip.bounds
            self.areaGradient.frame = self.clip.bounds
            self.gradientMask.frame = self.areaGradient.bounds
            self.reveal.bounds = CGRect(x: 0, y: 0,
                width: CGFloat(self.lastGeometry?.points.last?.x ?? 1) * self.clip.bounds.width,
                height: self.clip.bounds.height)
            self.headClip.frame = self.bounds
            self.headClipMask.frame = self.headClip.bounds
            self.headClipMask.path = CGPath(rect: self.chartRect.insetBy(dx: -2.6, dy: -2.6), transform: nil)
        }
    }

    override var isHidden: Bool {
        didSet { if isHidden { stopMotion() } }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stopMotion() }
    }

    func setAnimationsEnabled(_ enabled: Bool) {
        animationsEnabled = enabled
        if !enabled { stopMotion() }
    }

    func setPresentationActive(_ active: Bool) {
        presentationActive = active
        if !active { stopMotion() }
    }

    private func stopMotion() {
        reveal.removeAllAnimations()
        line.removeAllAnimations()
        gradientMask.removeAllAnimations()
        areaGradient.removeAllAnimations()
        head.removeAllAnimations()
    }

    func update(samples: [Double], peak: Double, color: NSColor,
                timing: HistoryChartTiming? = nil) {
        var resolvedColor = color
        effectiveAppearance.performAsCurrentDrawingAppearance {
            resolvedColor = color.usingColorSpace(.sRGB) ?? color
        }
        if samples == lastSamples, timing == lastTiming, peak == lastPeak,
           lastColor?.isEqual(resolvedColor) == true { return }

        let oldSamples = lastSamples, oldTiming = lastTiming
        let sameColor = lastColor?.isEqual(resolvedColor) == true
        let oldCeiling = scale.ceiling
        let mayAnimate = presentationActive && animationsEnabled
            && window?.isVisible == true && !isHiddenOrHasHiddenAncestor
            && !visibleRect.isEmpty && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            && sameColor
        // Capture the visible curves and color band before changing the model.
        let presentedHead = mayAnimate ? head.presentation()?.position ?? head.position : .zero
        let presentedPath = mayAnimate ? line.presentation()?.path ?? line.path : nil
        let gradient = areaGradient.presentation() ?? areaGradient
        let shownClip = clip.presentation() ?? clip
        func gradientPoint(_ p: CGPoint) -> CGPoint {
            gradient.convert(CGPoint(x: gradient.bounds.minX + p.x * gradient.bounds.width,
                                     y: gradient.bounds.minY + p.y * gradient.bounds.height), to: shownClip)
        }
        let presentedGradient = (gradientPoint(gradient.startPoint), gradientPoint(gradient.endPoint))
        let oldGeometry = lastGeometry
        lastSamples = samples
        lastTiming = timing
        lastPeak = peak
        lastColor = resolvedColor
#if DEBUG
        renderCountForTest += 1
#endif
        stopMotion()
        let measuredPeak = samples.reduce(0) { $1.isFinite ? max($0, $1) : $0 }
        peakLabel.stringValue = samples.isEmpty ? "Collecting…" : String(format: "Peak %.1f W", measuredPeak)
        if samples.isEmpty { scale.reset() }
        let ceiling = scale.update(peak: measuredPeak,
            at: timing?.referenceTime ?? ProcessInfo.processInfo.systemUptime)
        let viewportFraction: Double?
        if let oldTiming, let timing, let oldSamples {
            viewportFraction = HistoryChartTiming.viewportFraction(from: oldTiming, samples: oldSamples,
                                                                   to: timing, samples: samples)
        } else {
            viewportFraction = nil
        }
        // Carry the previous drawing boundary, including its existing context.
        // A raw ring alone loses that interval on the second consecutive slide.
        // Six seconds bounds age; at most one additional ring bounds count.
        var drawingSamples = samples
        var drawingTiming = timing
        var leadingContextCount = 0
        if viewportFraction != nil, let timing, let lastDrawingTiming,
           let first = timing.sampledAt.first {
            let context = lastDrawingTiming.sampledAt.indices.filter {
                lastDrawingTiming.sampledAt[$0] < first
                    && timing.referenceTime - lastDrawingTiming.sampledAt[$0] <= HistoryChartTiming.window + 6
            }.suffix(samples.count)
            drawingSamples = context.map { lastDrawingSamples[$0] } + samples
            drawingTiming = HistoryChartTiming(sampledAt: context.map { lastDrawingTiming.sampledAt[$0] }
                                                + timing.sampledAt,
                                               referenceTime: timing.referenceTime)
            leadingContextCount = context.count
        }
        lastDrawingSamples = drawingSamples
        lastDrawingTiming = drawingTiming
        let geometry = HistoryChartGeometry(samples: drawingSamples, timing: drawingTiming, ceiling: ceiling,
                                             leadingContextCount: leadingContextCount)
        lastGeometry = geometry
        let plot = chartRect
        let targetStroke = path(for: geometry)
        let targetFill = path(for: geometry, filled: true)
        PopoverStyle.setWithoutAnimation {
            self.clip.frame = plot
            self.line.frame = self.clip.bounds
            self.areaGradient.frame = self.clip.bounds
            self.gradientMask.frame = self.areaGradient.bounds
            self.line.path = geometry.points.isEmpty ? nil : targetStroke
            self.gradientMask.path = geometry.points.isEmpty ? nil : targetFill
            if !sameColor {
                self.line.strokeColor = resolvedColor.cgColor
                self.areaGradient.colors = [resolvedColor.withAlphaComponent(0.38).cgColor,
                                            resolvedColor.withAlphaComponent(0.03).cgColor]
                self.head.backgroundColor = resolvedColor.cgColor
            }
            self.areaGradient.startPoint = CGPoint(x: 0.5, y: 0)
            self.areaGradient.endPoint = CGPoint(x: 0.5, y: 1)
            self.reveal.bounds = CGRect(x: 0, y: 0,
                width: CGFloat(geometry.points.last?.x ?? 1) * plot.width, height: plot.height)
            self.headClip.frame = self.bounds
            self.headClipMask.frame = self.headClip.bounds
            self.headClipMask.path = CGPath(rect: plot.insetBy(dx: -2.6, dy: -2.6), transform: nil)
            if let last = geometry.points.last {
                let p = point(last)
                self.head.frame = CGRect(x: plot.minX + p.x - 2.6, y: plot.minY + p.y - 2.6,
                                         width: 5.2, height: 5.2)
                self.head.opacity = 1
            } else {
                self.head.opacity = 0
            }
        }
        guard mayAnimate, let viewportFraction,
              let oldGeometry, let presentedPath,
              let presentedSegments = segments(in: presentedPath),
              let startGeometry = geometry.alignedStart(from: oldGeometry, presentedSegments: presentedSegments,
                fraction: viewportFraction, oldCeiling: oldCeiling, newCeiling: ceiling) else { return }
        animateViewport(geometry: geometry, startGeometry: startGeometry,
                        presentedHead: presentedHead, presentedGradient: presentedGradient,
                        targetStroke: targetStroke, targetFill: targetFill)
    }

    private func point(_ p: HistoryChartGeometry.Point) -> CGPoint {
        CGPoint(x: CGFloat(p.x) * chartRect.width, y: CGFloat(1 - p.y) * chartRect.height)
    }

    private func path(for geometry: HistoryChartGeometry, filled: Bool = false) -> CGPath {
        let path = CGMutablePath()
        var segmentIndex = 0
        let separateRuns = !filled && geometry.runs.count > 1
        for run in geometry.runs {
            guard let first = run.first, let last = run.last else { continue }
            // addPath retains isolated move commands across gaps; consecutive
            // move(to:) calls would otherwise discard a single-point run.
            let subpath = separateRuns ? CGMutablePath() : path
            subpath.move(to: point(first))
            for _ in run.dropFirst() {
                let s = geometry.segments[segmentIndex]
                subpath.addCurve(to: point(s.end), control1: point(s.control1), control2: point(s.control2))
                segmentIndex += 1
            }
            if filled {
                subpath.addLine(to: CGPoint(x: CGFloat(last.x) * chartRect.width, y: chartRect.height))
                subpath.addLine(to: CGPoint(x: CGFloat(first.x) * chartRect.width, y: chartRect.height))
                subpath.closeSubpath()
            }
            if separateRuns { path.addPath(subpath) }
        }
        return path
    }

    /// Decode the actual presentation controls, retaining the cached model's
    /// raw timestamp identities. Never interpolate unrelated path commands.
    private func segments(in path: CGPath) -> [HistoryChartGeometry.Cubic]? {
        var segments: [HistoryChartGeometry.Cubic] = []
        var previous: HistoryChartGeometry.Point?
        var valid = true
        func normalized(_ p: CGPoint) -> HistoryChartGeometry.Point {
            .init(x: Double(p.x / chartRect.width), y: Double(1 - p.y / chartRect.height))
        }
        path.applyWithBlock { pointer in
            let element = pointer.pointee
            switch element.type {
            case .moveToPoint:
                previous = normalized(element.points[0])
            case .addCurveToPoint:
                guard let start = previous else { valid = false; return }
                let end = normalized(element.points[2])
                segments.append(.init(start: start, control1: normalized(element.points[0]),
                                      control2: normalized(element.points[1]), end: end))
                previous = end
            default:
                valid = false
            }
        }
        return valid ? segments : nil
    }

    private func animateViewport(geometry: HistoryChartGeometry, startGeometry: HistoryChartGeometry,
                                 presentedHead: CGPoint, presentedGradient: (CGPoint, CGPoint),
                                 targetStroke: CGPath, targetFill: CGPath) {
        guard let last = geometry.points.last else { return }
        let plot = chartRect
        let startStroke = path(for: startGeometry)
        let bandStart = CGPoint(x: presentedGradient.0.x / plot.width, y: presentedGradient.0.y / plot.height)
        let bandEnd = CGPoint(x: presentedGradient.1.x / plot.width, y: presentedGradient.1.y / plot.height)
        guard [bandStart.x, bandStart.y, bandEnd.x, bandEnd.y].allSatisfy(\.isFinite),
              bandEnd.y > bandStart.y,
              startStroke != targetStroke || presentedHead != head.position
                || bandStart != areaGradient.startPoint || bandEnd != areaGradient.endPoint else { return }
        // Presentation rounding affects duration selection only, never geometry.
        let scaling = zip(startGeometry.points, geometry.points).contains {
            abs($0.y - $1.y) * Double(plot.height) > 0.0001
        }
        let duration = scaling ? 0.35 : 0.18
        let timing = CAMediaTimingFunction(name: scaling ? .easeInEaseOut : .linear)
        let startX = Double((presentedHead.x - plot.minX) / plot.width)
        let initialLastX = startGeometry.points.last?.x ?? last.x
        var positions = [NSValue(point: presentedHead)]
        for frame in 1..<32 {
            let q = Double(frame) / 32
            let visibleX = min(startX + (last.x - startX) * q,
                               initialLastX + (last.x - initialLastX) * q)
            guard let y = geometry.value(at: visibleX, blendingFrom: startGeometry, progress: q) else { return }
            positions.append(NSValue(point: CGPoint(x: plot.minX + CGFloat(visibleX) * plot.width,
                y: plot.minY + plot.height * CGFloat(1 - y))))
        }
        positions.append(NSValue(point: head.position))
        let begin = CACurrentMediaTime()
        func add(_ animation: CAPropertyAnimation, to layer: CALayer, key: String) {
            animation.duration = duration
            animation.timingFunction = timing
            animation.beginTime = layer.convertTime(begin, from: nil)
            layer.add(animation, forKey: key)
        }
        let stroke = CABasicAnimation(keyPath: "path")
        stroke.fromValue = startStroke
        stroke.toValue = targetStroke
        add(stroke, to: line, key: "history.stroke")
        let fill = CABasicAnimation(keyPath: "path")
        fill.fromValue = path(for: startGeometry, filled: true)
        fill.toValue = targetFill
        add(fill, to: gradientMask, key: "history.fill")
        for (key, from, to) in [("startPoint", bandStart, areaGradient.startPoint),
                                ("endPoint", bandEnd, areaGradient.endPoint)] where from != to {
            let band = CABasicAnimation(keyPath: key)
            band.fromValue = NSValue(point: from)
            band.toValue = NSValue(point: to)
            add(band, to: areaGradient, key: "history.gradient." + key)
        }
        let startWidth = CGFloat(startX) * plot.width, endWidth = CGFloat(last.x) * plot.width
        if abs(startWidth - endWidth) > 1e-8 {
            let edge = CABasicAnimation(keyPath: "bounds.size.width")
            edge.fromValue = startWidth
            edge.toValue = endWidth
            add(edge, to: reveal, key: "history.reveal")
        }
        let dot = CAKeyframeAnimation(keyPath: "position")
        dot.values = positions
        dot.calculationMode = .linear
        add(dot, to: head, key: "history.head")
    }
}
