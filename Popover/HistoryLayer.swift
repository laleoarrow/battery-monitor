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
    private let movingPlot = CALayer()
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
    var chartCeilingForTest: Double { scale.ceiling }
    var hasChartAnimationForTest: Bool {
        movingPlot.animation(forKey: "history.scroll") != nil
            || movingPlot.animation(forKey: "history.viewport") != nil
            || line.animation(forKey: "history.curve") != nil
            || gradientMask.animation(forKey: "history.fill") != nil
            || areaGradient.animation(forKey: "history.gradient") != nil
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
        movingPlot.anchorPoint = CGPoint(x: 0, y: 1)
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

    private var gradientRect: CGRect {
        let left = CGFloat(min(lastGeometry?.points.first?.x ?? 0, 0)) * chartRect.width
        let peak = lastGeometry?.points.map(\.y).max() ?? 0
        let top = CGFloat(min(1 - peak, 0)) * chartRect.height
        return CGRect(x: left, y: top, width: chartRect.width - left, height: chartRect.height - top)
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
            self.areaGradient.frame = self.gradientRect
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
        movingPlot.removeAllAnimations()
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
        // Read the visible transform before removing its animation. A new
        // sample must continue from this viewport, rather than its old target.
        let presentedTransform = movingPlot.presentation()?.transform ?? movingPlot.transform
        let presentedHead = head.presentation()?.position ?? head.position
        let presentedPath = line.presentation()?.path ?? line.path
        let presentedGradient = areaGradient.presentation() ?? areaGradient
        let presentedBandY = HistoryChartViewport.gradientScreenStartY(
            startPointY: Double(presentedGradient.startPoint.y),
            frameMinY: Double(presentedGradient.frame.minY), frameHeight: Double(presentedGradient.frame.height),
            scaleY: Double(presentedTransform.m22), plotHeight: Double(Self.chartHeight))
        let oldGeometry = lastGeometry
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
        let targetPaths = paths(for: geometry)
        PopoverStyle.setWithoutAnimation {
            self.clip.frame = plot
            self.movingPlot.frame = self.clip.bounds
            self.line.frame = self.clip.bounds
            self.areaGradient.frame = self.gradientRect
            self.gradientMask.frame = self.areaGradient.bounds
            self.line.path = geometry.points.isEmpty ? nil : targetPaths.stroke
            self.line.strokeColor = resolvedColor.cgColor
            self.gradientMask.path = geometry.points.isEmpty ? nil : self.fillPath(targetPaths.filled)
            self.areaGradient.colors = [resolvedColor.withAlphaComponent(0.38).cgColor,
                                        resolvedColor.withAlphaComponent(0.03).cgColor]
            let gradient = self.gradientRect
            self.areaGradient.startPoint = CGPoint(x: 0.5, y: -gradient.minY / gradient.height)
            self.areaGradient.endPoint = CGPoint(x: 0.5, y: (plot.height - gradient.minY) / gradient.height)
            self.reveal.bounds = CGRect(x: 0, y: 0,
                width: CGFloat(geometry.points.last?.x ?? 1) * plot.width, height: plot.height)
            self.headClip.frame = self.bounds
            self.headClipMask.frame = self.headClip.bounds
            self.headClipMask.path = CGPath(rect: plot.insetBy(dx: -2.6, dy: -2.6), transform: nil)
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
        guard presentationActive, animationsEnabled,
              window?.isVisible == true, !isHiddenOrHasHiddenAncestor,
              !visibleRect.isEmpty, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              sameColor, let viewportFraction,
              let oldGeometry, let presentedPath,
              let presentedSegments = segments(in: presentedPath),
              let startGeometry = geometry.alignedStart(from: oldGeometry, presentedSegments: presentedSegments,
                fraction: viewportFraction, oldCeiling: oldCeiling, newCeiling: ceiling),
              let viewport = HistoryChartViewport(oldCeiling: oldCeiling, newCeiling: ceiling,
                fraction: viewportFraction, width: Double(plot.width),
                presentedTranslationX: Double(presentedTransform.m41),
                presentedScaleY: Double(presentedTransform.m22)),
              abs(viewport.translationX) > 1e-8 || abs(viewport.scaleY - 1) > 1e-8 else { return }
        animateViewport(viewport, geometry: geometry, startGeometry: startGeometry,
                        presentedHead: presentedHead, presentedBandY: presentedBandY)
    }

    private func point(_ p: HistoryChartGeometry.Point) -> CGPoint {
        CGPoint(x: CGFloat(p.x) * chartRect.width, y: CGFloat(1 - p.y) * chartRect.height)
    }

    private func paths(for geometry: HistoryChartGeometry) -> (stroke: CGPath, filled: CGPath) {
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
            subpath.addLine(to: CGPoint(x: CGFloat(last.x) * chartRect.width, y: chartRect.height))
            subpath.addLine(to: CGPoint(x: CGFloat(first.x) * chartRect.width, y: chartRect.height))
            subpath.closeSubpath()
            filled.addPath(subpath)
        }
        return (stroke, filled)
    }

    private func fillPath(_ path: CGPath) -> CGPath {
        let translated = CGMutablePath()
        translated.addPath(path, transform: CGAffineTransform(translationX: -gradientRect.minX,
                                                             y: -gradientRect.minY))
        return translated
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

    private func animateViewport(_ viewport: HistoryChartViewport, geometry: HistoryChartGeometry,
                                 startGeometry: HistoryChartGeometry,
                                 presentedHead: CGPoint, presentedBandY: Double) {
        guard let last = geometry.points.last else { return }
        let plot = chartRect
        let scaling = abs(viewport.scaleY - 1) > 1e-8
        let duration = scaling ? 0.35 : 0.18
        let timing = CAMediaTimingFunction(name: scaling ? .easeInEaseOut : .linear)
        // Keep the dot a constant size outside the scaled plot. Its positions
        // follow the same affine transform and cubic as the line and area.
        let startX = Double((presentedHead.x - plot.minX) / plot.width)
        var positions: [NSValue] = []
        for frame in 0...32 {
            let progress = Double(frame) / 32
            let shift = viewport.translationX / Double(plot.width) * (1 - progress)
            let sy = 1 + (viewport.scaleY - 1) * (1 - progress)
            let visibleX = min(startX + (last.x - startX) * progress, last.x + shift)
            guard let y = geometry.value(at: min(visibleX - shift, last.x),
                                         blendingFrom: startGeometry, progress: progress) else { return }
            positions.append(NSValue(point: CGPoint(x: plot.minX + CGFloat(visibleX) * plot.width,
                y: plot.minY + plot.height - CGFloat(y * sy) * plot.height)))
        }
        let motion = CABasicAnimation(keyPath: scaling ? "transform" : "transform.translation.x")
        if scaling {
            var start = CATransform3DIdentity
            start.m22 = CGFloat(viewport.scaleY)
            start.m41 = CGFloat(viewport.translationX)
            motion.fromValue = NSValue(caTransform3D: start)
            motion.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        } else {
            motion.fromValue = viewport.translationX
            motion.toValue = 0
        }
        motion.duration = duration
        motion.timingFunction = timing
        let dot = CAKeyframeAnimation(keyPath: "position")
        dot.values = positions
        dot.duration = duration
        dot.calculationMode = .linear
        dot.timingFunction = timing
        if scaling || abs(presentedBandY) > 1e-8 {
            let gradient = gradientRect
            let band = CAKeyframeAnimation(keyPath: "startPoint")
            band.values = (0...256).map { frame in
                NSValue(point: CGPoint(x: 0.5, y: viewport.gradientStartY(at: Double(frame) / 256,
                    fromScreenY: presentedBandY, frameMinY: Double(gradient.minY),
                    frameHeight: Double(gradient.height), plotHeight: Double(plot.height))))
            }
            band.duration = duration
            band.calculationMode = .linear
            band.timingFunction = timing
            areaGradient.add(band, forKey: "history.gradient")
        }
        let changesShape = zip(startGeometry.segments, geometry.segments).contains {
            abs($0.control1.y - $1.control1.y) > 1e-12 || abs($0.control2.y - $1.control2.y) > 1e-12
        }
        if changesShape {
            let startPaths = paths(for: startGeometry), targetPaths = paths(for: geometry)
            for (shape, from, to, key) in [(line, startPaths.stroke, targetPaths.stroke, "history.curve"),
                (gradientMask, fillPath(startPaths.filled), fillPath(targetPaths.filled), "history.fill")] {
                let curve = CABasicAnimation(keyPath: "path")
                curve.fromValue = from
                curve.toValue = to
                curve.duration = duration
                curve.timingFunction = timing
                shape.add(curve, forKey: key)
            }
        }
        let startWidth = CGFloat(startX) * plot.width, endWidth = CGFloat(last.x) * plot.width
        if abs(startWidth - endWidth) > 1e-8 {
            let edge = CABasicAnimation(keyPath: "bounds.size.width")
            edge.fromValue = startWidth
            edge.toValue = endWidth
            edge.duration = duration
            edge.timingFunction = timing
            reveal.add(edge, forKey: "history.reveal")
        }
        movingPlot.add(motion, forKey: scaling ? "history.viewport" : "history.scroll")
        head.add(dot, forKey: "history.head")
    }
}
