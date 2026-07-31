import AppKit
import QuartzCore

final class HistoryView: NSView {
    private let titleLabel = NSTextField(labelWithString: "近 2 分钟")
    private let peakLabel = NSTextField(labelWithString: "峰值 0.0 W")
    private let gridLayers = [CAShapeLayer(), CAShapeLayer()]
    private let areaLayer = CAShapeLayer()
    private let lineLayer = CAShapeLayer()
    private var samples: [Double] = []
    private var peak: Double = 0
    private var color: NSColor = .systemBlue

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        PopoverStyle.configureModule(self)

        titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        addSubview(titleLabel)

        peakLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        peakLabel.textColor = .tertiaryLabelColor
        peakLabel.alignment = .right
        addSubview(peakLabel)

        gridLayers.forEach {
            $0.fillColor = nil
            $0.strokeColor = NSColor.separatorColor.withAlphaComponent(0.28).cgColor
            $0.lineWidth = 0.6
            layer?.addSublayer($0)
        }
        areaLayer.fillColor = color.withAlphaComponent(0.16).cgColor
        areaLayer.strokeColor = nil
        layer?.addSublayer(areaLayer)
        lineLayer.fillColor = nil
        lineLayer.strokeColor = color.cgColor
        lineLayer.lineWidth = 1.7
        lineLayer.lineJoin = .round
        lineLayer.lineCap = .round
        layer?.addSublayer(lineLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        titleLabel.frame = NSRect(x: 12, y: 8, width: 100, height: 16)
        peakLabel.frame = NSRect(x: 200, y: 8, width: 116, height: 16)
        redraw()
    }

    func update(samples: [Double], peak: Double, color: NSColor) {
        self.samples = samples
        self.peak = peak
        self.color = color
        peakLabel.stringValue = "峰值 " + PopoverStyle.watts(peak)
        redraw()
    }

    private func redraw() {
        guard bounds.width > 0 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let chart = CGRect(x: 12, y: 28, width: bounds.width - 24, height: bounds.height - 38)
        for (index, grid) in gridLayers.enumerated() {
            let y = chart.minY + chart.height * CGFloat(index + 1) / 3
            let path = CGMutablePath()
            path.move(to: CGPoint(x: chart.minX, y: y))
            path.addLine(to: CGPoint(x: chart.maxX, y: y))
            grid.path = path
            grid.frame = bounds
        }

        guard !samples.isEmpty else {
            areaLayer.path = nil
            lineLayer.path = nil
            return
        }

        let scale = max(peak, 1)
        let points = samples.enumerated().map { index, value -> CGPoint in
            let denominator = max(samples.count - 1, 1)
            let x = chart.minX + chart.width * CGFloat(index) / CGFloat(denominator)
            let y = chart.maxY - chart.height * CGFloat(max(value, 0) / scale)
            return CGPoint(x: x, y: y)
        }

        let linePath = CGMutablePath()
        linePath.move(to: points[0])
        points.dropFirst().forEach { linePath.addLine(to: $0) }
        if points.count == 1 {
            linePath.addLine(to: CGPoint(x: chart.maxX, y: points[0].y))
        }

        let areaPath = linePath.mutableCopy() ?? CGMutablePath()
        areaPath.addLine(to: CGPoint(x: chart.maxX, y: chart.maxY))
        areaPath.addLine(to: CGPoint(x: chart.minX, y: chart.maxY))
        areaPath.closeSubpath()

        areaLayer.path = areaPath
        areaLayer.frame = bounds
        areaLayer.fillColor = color.withAlphaComponent(0.16).cgColor
        lineLayer.path = linePath
        lineLayer.frame = bounds
        lineLayer.strokeColor = color.cgColor
    }
}
