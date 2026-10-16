import AppKit

/// A data-driven two-minute chart. Only new, contiguous readings get a short
/// translation; no timer, fabricated readings, or incompatible path morphing.
final class HistoryView: PopoverSection {
    static let chartHeight: CGFloat = 64
    static let headerHeight: CGFloat = 22
    static let plotHeight: CGFloat = headerHeight + chartHeight
    static let preferredHeight: CGFloat = plotHeight + PopoverStyle.sectionPadding * 2

    private let clip = CALayer()
    private let movingPlot = CALayer()
    private let line = CAShapeLayer()
    private let head = CALayer()
    private let gradientMask = CAShapeLayer()
    private let areaGradient = CAGradientLayer()
    private let caption = NSTextField(labelWithString: "Power History · 2 min")
    private let peakLabel = NSTextField(labelWithString: "")
    private var lastSamples: [Double]?
    private var lastTiming: HistoryChartTiming?
    private var lastPeak: Double?
    private var lastColor: NSColor?
    private var scale = HistoryChartScale()
    private var presentationActive = false
    private var animationsEnabled = false
#if DEBUG
    private(set) var renderCountForTest = 0
    var chartPathForTest: CGPath? { line.path }
    var chartCeilingForTest: Double { scale.ceiling }
    var hasChartAnimationForTest: Bool {
        movingPlot.animation(forKey: "history.scroll") != nil || head.animation(forKey: "history.head") != nil
    }
#endif

    init() {
        super.init(height: Self.preferredHeight)
        clip.masksToBounds = true
        clip.addSublayer(movingPlot)
        layer?.addSublayer(clip)
        areaGradient.mask = gradientMask
        gradientMask.fillColor = NSColor.black.cgColor
        gradientMask.strokeColor = nil
        movingPlot.addSublayer(areaGradient)
        line.fillColor = nil
        line.lineWidth = 1.6
        line.lineJoin = .round
        line.lineCap = .round
        movingPlot.addSublayer(line)
        head.cornerRadius = 2.6
        head.opacity = 0
        layer?.addSublayer(head)
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
            self.movingPlot.frame = self.clip.bounds
            self.line.frame = self.clip.bounds
            self.gradientMask.frame = self.clip.bounds
            self.areaGradient.frame = self.clip.bounds
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
        movingPlot.removeAllAnimations()
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
        let interruptedMotion = movingPlot.animation(forKey: "history.scroll") != nil
        lastSamples = samples
        lastTiming = timing
        lastPeak = peak
        lastColor = resolvedColor
#if DEBUG
        renderCountForTest += 1
#endif
        stopMotion()
        let measuredPeak = max(samples.filter(\.isFinite).max() ?? 0, 0)
        peakLabel.stringValue = samples.isEmpty ? "Collecting…" : String(format: "Peak %.1f W", measuredPeak)
        if samples.isEmpty { scale.reset() }
        let ceiling = scale.update(peak: measuredPeak,
            at: timing?.referenceTime ?? ProcessInfo.processInfo.systemUptime)
        let scrollFraction: Double?
        if let oldTiming, let timing, let oldSamples, oldCeiling == ceiling {
            scrollFraction = HistoryChartTiming.scrollFraction(from: oldTiming, samples: oldSamples,
                                                               to: timing, samples: samples)
        } else {
            scrollFraction = nil
        }
        // Keep one departing point only as clipped drawing context. Without it,
        // a full ring would lose its leftmost segment at the start of each slide.
        var drawingSamples = samples
        var drawingTiming = timing
        var hasLeadingContext = false
        if scrollFraction != nil, let oldTiming, let oldSamples, let timing,
           let first = timing.sampledAt.first,
           let index = oldTiming.sampledAt.firstIndex(of: first), index > 0 {
            drawingSamples.insert(oldSamples[index - 1], at: 0)
            drawingTiming = HistoryChartTiming(sampledAt: [oldTiming.sampledAt[index - 1]] + timing.sampledAt,
                                               referenceTime: timing.referenceTime)
            hasLeadingContext = true
        }
        let geometry = HistoryChartGeometry(samples: drawingSamples, timing: drawingTiming, ceiling: ceiling,
                                             leadingContext: hasLeadingContext)
        let plot = chartRect
        func point(_ p: HistoryChartGeometry.Point) -> CGPoint {
            CGPoint(x: CGFloat(p.x) * plot.width, y: CGFloat(1 - p.y) * plot.height)
        }
        let stroke = CGMutablePath(), filled = CGMutablePath()
        var segmentIndex = 0
        for run in geometry.runs {
            guard let first = run.first, let last = run.last else { continue }
            let subpath = CGMutablePath()
            subpath.move(to: point(first))
            for _ in run.dropFirst() {
                let s = geometry.segments[segmentIndex]
                subpath.addCurve(to: point(s.end), control1: point(s.control1), control2: point(s.control2))
                segmentIndex += 1
            }
            stroke.addPath(subpath)
            subpath.addLine(to: CGPoint(x: CGFloat(last.x) * plot.width, y: plot.height))
            subpath.addLine(to: CGPoint(x: CGFloat(first.x) * plot.width, y: plot.height))
            subpath.closeSubpath()
            filled.addPath(subpath)
        }
        PopoverStyle.setWithoutAnimation {
            self.clip.frame = plot
            self.movingPlot.frame = self.clip.bounds
            self.line.frame = self.clip.bounds
            self.gradientMask.frame = self.clip.bounds
            self.areaGradient.frame = self.clip.bounds
            self.line.path = geometry.points.isEmpty ? nil : stroke
            self.line.strokeColor = resolvedColor.cgColor
            self.gradientMask.path = geometry.points.isEmpty ? nil : filled
            self.areaGradient.colors = [resolvedColor.withAlphaComponent(0.38).cgColor,
                                        resolvedColor.withAlphaComponent(0.03).cgColor]
            self.areaGradient.startPoint = CGPoint(x: 0.5, y: 0)
            self.areaGradient.endPoint = CGPoint(x: 0.5, y: 1)
            if let last = geometry.points.last {
                let p = point(last)
                self.head.frame = CGRect(x: plot.minX + p.x - 2.6, y: plot.minY + p.y - 2.6,
                                         width: 5.2, height: 5.2)
                self.head.backgroundColor = resolvedColor.cgColor
                self.head.opacity = 1
            } else {
                self.head.opacity = 0
            }
        }
        guard presentationActive, animationsEnabled, !interruptedMotion,
              window?.isVisible == true, !isHiddenOrHasHiddenAncestor,
              !visibleRect.isEmpty, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              sameColor, let scrollFraction else { return }
        animateScroll(fraction: scrollFraction, geometry: geometry)
    }

    private func animateScroll(fraction: Double, geometry: HistoryChartGeometry) {
        guard let last = geometry.points.last else { return }
        let plot = chartRect
        // Follow the visible end of the same cubic while the new point enters
        // from the right. The dot never floats off the line or pulses.
        var positions: [NSValue] = []
        for frame in 0...16 {
            let shift = fraction * (1 - Double(frame) / 16)
            let visibleX = min(last.x + shift, 1)
            guard let y = geometry.value(at: visibleX - shift) else { return }
            positions.append(NSValue(point: CGPoint(x: plot.minX + CGFloat(visibleX) * plot.width,
                                                     y: plot.minY + CGFloat(1 - y) * plot.height)))
        }
        let scroll = CABasicAnimation(keyPath: "transform.translation.x")
        scroll.fromValue = CGFloat(fraction) * plot.width
        scroll.toValue = 0
        scroll.duration = 0.18
        scroll.timingFunction = CAMediaTimingFunction(name: .linear)
        let dot = CAKeyframeAnimation(keyPath: "position")
        dot.values = positions
        dot.duration = scroll.duration
        dot.calculationMode = .linear
        dot.timingFunction = CAMediaTimingFunction(name: .linear)
        movingPlot.add(scroll, forKey: "history.scroll")
        head.add(dot, forKey: "history.head")
    }
}
