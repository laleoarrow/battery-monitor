import AppKit

/// Two minutes of total input power. Redrawn on data, never animated — a
/// moving history chart is harder to read than a still one.
final class HistoryView: PopoverSection {
    static let chartHeight: CGFloat = 64
    static let headerHeight: CGFloat = 22
    static let plotHeight: CGFloat = headerHeight + chartHeight
    static let preferredHeight: CGFloat = plotHeight + PopoverStyle.sectionPadding * 2

    private let area = CAShapeLayer()
    private let line = CAShapeLayer()
    private let head = CALayer()
    private let gradientMask = CAShapeLayer()
    private let areaGradient = CAGradientLayer()

    private let caption = NSTextField(labelWithString: "Power History · 2 min")
    private let peakLabel = NSTextField(labelWithString: "")
    private var lastSamples: [Double]?
    private var lastPeak: Double?
    private var lastColor: NSColor?
#if DEBUG
    private(set) var renderCountForTest = 0
#endif

    init() {
        super.init(height: Self.preferredHeight)

        areaGradient.mask = gradientMask
        gradientMask.fillColor = NSColor.black.cgColor
        gradientMask.strokeColor = nil
        layer?.addSublayer(areaGradient)

        line.fillColor = nil
        line.lineWidth = 1.6
        line.lineJoin = .round
        line.lineCap = .round
        layer?.addSublayer(line)

        head.cornerRadius = 2.6
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
            self.area.frame = self.bounds
            self.line.frame = self.bounds
            self.gradientMask.frame = self.bounds
            self.areaGradient.frame = self.bounds
        }
    }

    func update(samples: [Double], peak: Double, color: NSColor) {
        if samples == lastSamples,
           peak == lastPeak,
           let lastColor,
           lastColor.isEqual(color) {
            return
        }
        lastSamples = samples
        lastPeak = peak
        lastColor = color
#if DEBUG
        renderCountForTest += 1
#endif
        peakLabel.stringValue = samples.isEmpty ? "Collecting…" : String(format: "Peak %.1f W", peak)

        let plot = chartRect
        guard samples.count > 1 else {
            PopoverStyle.setWithoutAnimation {
                self.gradientMask.path = nil
                self.line.path = nil
                self.head.opacity = 0
            }
            return
        }

        let ceiling = max(peak * 1.14, 8)
        let step = plot.width / CGFloat(samples.count - 1)
        func point(_ index: Int) -> CGPoint {
            let value = min(max(samples[index], 0), ceiling)
            return CGPoint(x: plot.minX + CGFloat(index) * step,
                           y: plot.maxY - CGFloat(value / ceiling) * plot.height)
        }

        let stroke = CGMutablePath()
        stroke.move(to: point(0))
        for index in 1..<samples.count { stroke.addLine(to: point(index)) }

        let filled = CGMutablePath()
        filled.addPath(stroke)
        filled.addLine(to: CGPoint(x: plot.maxX, y: plot.maxY))
        filled.addLine(to: CGPoint(x: plot.minX, y: plot.maxY))
        filled.closeSubpath()

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        line.path = stroke
        line.strokeColor = color.cgColor

        gradientMask.path = filled
        areaGradient.colors = [color.withAlphaComponent(0.38).cgColor,
                               color.withAlphaComponent(0.03).cgColor]
        areaGradient.startPoint = CGPoint(x: 0.5, y: 0)
        areaGradient.endPoint = CGPoint(x: 0.5, y: 1)

        let last = point(samples.count - 1)
        head.frame = CGRect(x: last.x - 2.6, y: last.y - 2.6, width: 5.2, height: 5.2)
        head.backgroundColor = color.cgColor
        head.opacity = 1
        CATransaction.commit()
    }
}
