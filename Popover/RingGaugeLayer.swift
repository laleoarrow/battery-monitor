import AppKit

/// Charge as the outer ring, power intensity as a rotating inner arc, selected
/// readings beside it.
///
/// The centre reads charge percentage, not watts — the header already owns the
/// wattage, and spending the module's most valuable spot on a number that
/// appears 60pt above it is waste.
final class RingGaugeView: PopoverSection {
    static let plotHeight: CGFloat = 112
    static let preferredHeight: CGFloat = plotHeight + PopoverStyle.sectionPadding * 2

    private static let centre = CGPoint(x: 56, y: 56 + PopoverStyle.sectionPadding)
    private static let ringRadius: CGFloat = 46
    private static let arcRadius: CGFloat = 34

    private let track = CAShapeLayer()
    private let charge = CAShapeLayer()
    private let arcHost = CALayer()
    private let rotatingArc = CAShapeLayer()
    private let arcGradient = CAGradientLayer()

    private let percentLabel = NSTextField(labelWithString: "0")
    private let percentUnit = NSTextField(labelWithString: "%")

    private var captions: [NSTextField] = []
    private var values: [NSTextField] = []
    private var metrics: [Settings.RingMetric] = []
    private var animationsEnabled = false
    private var intensity: CGFloat = 0
    private var motionMultiplier: CGFloat = 1

    init() {
        super.init(height: Self.preferredHeight)

        track.fillColor = nil
        track.lineWidth = 7
        track.strokeColor = PopoverStyle.ringTrack.cgColor
        layer?.addSublayer(track)

        charge.fillColor = nil
        charge.lineWidth = 7
        charge.lineCap = .round
        layer?.addSublayer(charge)

        rotatingArc.fillColor = nil
        rotatingArc.lineWidth = 4.5
        rotatingArc.lineCap = .round
        rotatingArc.strokeColor = NSColor.black.cgColor
        // Fading the inner arc along its sweep separates it from the outer
        // ring; two solid arcs of the same colour read as one thick ring.
        arcGradient.mask = rotatingArc
        arcHost.addSublayer(arcGradient)
        layer?.addSublayer(arcHost)

        percentLabel.font = PopoverStyle.mono(25, .semibold)
        percentLabel.textColor = PopoverStyle.primaryText
        percentLabel.alignment = .center
        addSubview(percentLabel)

        percentUnit.font = .systemFont(ofSize: 11, weight: .regular)
        percentUnit.textColor = PopoverStyle.secondaryText
        percentUnit.alignment = .center
        addSubview(percentUnit)

        reloadMetrics()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func reloadMetrics() {
        let selected = Settings.ringMetrics
        guard metrics != selected else { return }
        (captions + values).forEach { $0.removeFromSuperview() }
        captions.removeAll()
        values.removeAll()
        metrics = selected
        for metric in metrics {
            let caption = label(metric.title, size: 11, color: PopoverStyle.secondaryText)
            caption.setAccessibilityElement(false)
            caption.cell?.setAccessibilityElement(false)
            captions.append(caption)
            let value = label("—", size: 15, color: PopoverStyle.primaryText, mono: true)
            value.setAccessibilityElement(true)
            value.setAccessibilityRole(.staticText)
            value.setAccessibilityLabel(metric.title)
            if metric == .batteryCurrent {
                value.toolTip = "Battery current: positive charges the battery; negative discharges it."
                value.setAccessibilityHelp(value.toolTip)
            } else if metric == .adapterCurrent || metric == .adapterVoltage {
                value.toolTip = "Measured adapter input, when available from this Mac."
                value.setAccessibilityHelp(value.toolTip)
            } else if metric == .batteryHealth {
                value.toolTip = "Maximum capacity reported by macOS. The raw capacity-to-design ratio is a different measurement."
                value.setAccessibilityHelp(value.toolTip)
            } else if metric == .maxCapacity {
                value.toolTip = "Raw full-charge capacity from the battery controller, in mAh. This is not the macOS Maximum Capacity percentage."
                value.setAccessibilityHelp(value.toolTip)
            } else if metric == .designCapacity {
                value.toolTip = "Battery design capacity in mAh, as reported by the battery controller."
                value.setAccessibilityHelp(value.toolTip)
            }
            caption.toolTip = value.toolTip
            values.append(value)
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        percentLabel.frame = NSRect(x: Self.centre.x - 40, y: Self.centre.y - 20, width: 80, height: 28)
        percentUnit.frame = NSRect(x: Self.centre.x - 40, y: Self.centre.y + 8, width: 80, height: 14)

        // Two columns beside the ring. The trailing slot may change content,
        // but its geometry remains identical.
        for index in metrics.indices {
            let column = index % 2
            let row = index / 2
            let x = 132 + CGFloat(column) * 100
            let y = PopoverStyle.sectionPadding + 14 + CGFloat(row) * 50
            captions[index].frame = NSRect(x: x, y: y, width: 96, height: 14)
            values[index].frame = NSRect(x: x, y: y + 15, width: 96, height: 19)
        }

        PopoverStyle.setWithoutAnimation {
            for shape in [self.track, self.charge] { shape.frame = self.bounds }
            self.arcHost.bounds = CGRect(x: 0, y: 0, width: Self.arcRadius * 2 + 12, height: Self.arcRadius * 2 + 12)
            self.arcHost.position = Self.centre
            self.rotatingArc.frame = self.arcHost.bounds
            self.arcGradient.frame = self.arcHost.bounds
            self.arcGradient.startPoint = CGPoint(x: 0, y: 0)
            self.arcGradient.endPoint = CGPoint(x: 1, y: 1)
        }
        rebuildPaths()
    }

    private func rebuildPaths() {
        PopoverStyle.setWithoutAnimation {
            let ring = CGMutablePath()
            ring.addArc(center: Self.centre, radius: Self.ringRadius,
                        startAngle: -.pi / 2, endAngle: .pi * 1.5, clockwise: false)
            self.track.path = ring
            self.charge.path = ring

            // Drawn in the rotating layer's own space so spinning it does not
            // drag the arc off the ring's centre.
            let local = CGPoint(x: self.arcHost.bounds.midX, y: self.arcHost.bounds.midY)
            let arc = CGMutablePath()
            arc.addArc(center: local, radius: Self.arcRadius,
                       startAngle: -.pi / 2, endAngle: .pi * 1.5, clockwise: false)
            self.rotatingArc.path = arc
        }
    }

    func update(snapshot: PowerSnapshot, degraded: Bool = false) {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            updateContents(snapshot: snapshot, degraded: degraded)
        }
    }

    private func updateContents(snapshot: PowerSnapshot, degraded: Bool) {
        let color = PopoverStyle.stateColor(snapshot.state)
        intensity = VisualEncoding.t(snapshot.totalInputW)
        motionMultiplier = VisualEncoding.multiplier(snapshot.totalInputW)

        percentLabel.stringValue = "\(snapshot.percent)"
        percentLabel.textColor = snapshot.percent <= 20 ? PopoverStyle.red : PopoverStyle.primaryText

        for (index, metric) in metrics.enumerated() {
            let reading = reading(metric, snapshot: snapshot, degraded: degraded)
            captions[index].stringValue = reading.caption
            values[index].stringValue = reading.value
            values[index].setAccessibilityLabel(reading.caption)
            if metric == .timeEstimate {
                let help = timeEstimateHelp(snapshot)
                captions[index].toolTip = help
                values[index].toolTip = help
                values[index].setAccessibilityHelp(help)
            }
            // State words need a smaller proportional face than numeric values.
            values[index].font = metric == .timeEstimate
                ? .systemFont(ofSize: 12, weight: .medium) : PopoverStyle.mono(15)
        }

        PopoverStyle.setWithoutAnimation {
            self.track.strokeColor = PopoverStyle.ringTrack.cgColor
            self.charge.strokeColor = (snapshot.percent <= 20 ? PopoverStyle.red : color).cgColor
            self.charge.strokeEnd = CGFloat(snapshot.percent) / 100
            let arcColor = snapshot.state == .mixedSupply ? PopoverStyle.blue : color
            self.arcGradient.colors = [arcColor.withAlphaComponent(0.12).cgColor, arcColor.cgColor]
            self.rotatingArc.strokeEnd = max(0.06, self.intensity)
        }
        applyRotation()
    }

    private func reading(_ metric: Settings.RingMetric, snapshot: PowerSnapshot, degraded: Bool) -> (caption: String, value: String) {
        var caption = metric.title
        let value: String
        switch metric {
        case .systemLoad:
            let hasPositiveDeviceOutput = snapshot.coherentDeviceOutputW.map { $0 > 0 } ?? false
            caption = hasPositiveDeviceOutput ? "System Total" : "System Load"
            value = PopoverStyle.watts(snapshot.systemW)
        case .batteryPower:
            caption = PopoverStyle.batteryFlowLabel(snapshot)
            value = snapshot.state == .pluggedIdle ? "0.0 W" : PopoverStyle.watts(abs(snapshot.batteryW))
        case .temperature:
            value = snapshot.temperatureC.map { String(format: "%.1f°C", $0) } ?? "—"
        case .cycleCount:
            value = "\(snapshot.cycleCount)"
        case .timeEstimate:
            caption = snapshot.plugged ? "Time to Full" : "Battery Runtime"
            value = degraded ? "—" : timeEstimate(snapshot)
        case .batteryHealth:
            value = snapshot.batteryHealthPercent.map { String(format: "%.0f%%", $0) } ?? "—"
        case .batteryVoltage:
            value = snapshot.batteryVoltageV.map { String(format: "%.2f V", $0) } ?? "—"
        case .batteryCurrent:
            value = snapshot.batteryCurrentMA.map { String(format: "%+d mA", $0) } ?? "—"
        case .adapterVoltage:
            value = snapshot.adapterVoltageV.map { String(format: "%.2f V", $0) } ?? "—"
        case .adapterCurrent:
            value = snapshot.adapterCurrentMA.map { "\($0) mA" } ?? "—"
        case .adapterPower:
            value = PopoverStyle.watts(snapshot.adapterW)
        case .deviceOutput:
            value = snapshot.coherentDeviceOutputW.map(PopoverStyle.watts) ?? "—"
        case .maxCapacity:
            value = snapshot.maxCapacityMAh.map { "\($0) mAh" } ?? "—"
        case .designCapacity:
            value = snapshot.designCapacityMAh.map { "\($0) mAh" } ?? "—"
        }
        return (caption, value)
    }

    private func timeEstimate(_ snapshot: PowerSnapshot) -> String {
        if snapshot.state == .mixedSupply { return "Not Charging" }
        let minutes: Int?
        switch snapshot.batteryTimeEstimate {
        case .charging(let value) where snapshot.plugged: minutes = value
        case .remaining(let value) where !snapshot.plugged: minutes = value
        case .full where snapshot.plugged: return "Fully Charged"
        case .notCharging where snapshot.plugged: return "Not Charging"
        default: return "—"
        }
        guard let minutes, minutes >= 0 else { return "Calculating…" }
        let time = minutes == 0 ? "<1m" : minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h \(minutes % 60)m"
        return !snapshot.plugged && snapshot.batteryTimeEstimateSource == .observedDischarge ? "≈\(time)" : time
    }

    private func timeEstimateHelp(_ snapshot: PowerSnapshot) -> String {
        switch snapshot.batteryTimeEstimateSource {
        case .batteryGauge:
            return snapshot.plugged
                ? "The battery controller estimates time until full. It changes with charging conditions and workload."
                : "The battery controller estimates remaining battery time. It changes with workload."
        case .observedDischarge:
            return "Approximate runtime from remaining battery charge and recent average discharge current. It changes with workload."
        default:
            return snapshot.plugged
                ? "macOS estimates time until the battery is full while charging. It changes with charging conditions and workload."
                : "macOS estimates remaining battery time for current usage. It changes with workload."
        }
    }

    private func applyRotation() {
        guard animationsEnabled else { return }
        if arcHost.animation(forKey: "spin") == nil {
            let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
            rotation.fromValue = 0
            rotation.toValue = CGFloat.pi * 2
            rotation.duration = VisualEncoding.motionPeriod
            rotation.repeatCount = .infinity
            rotation.isRemovedOnCompletion = false
            arcHost.add(rotation, forKey: "spin")
        }
        PopoverStyle.setAnimationSpeed(arcHost, multiplier: motionMultiplier)
    }

    func setAnimationsEnabled(_ enabled: Bool) {
        animationsEnabled = enabled
        if enabled { applyRotation() } else { arcHost.removeAllAnimations() }
    }

#if DEBUG
    var selectedMetricsForTest: [Settings.RingMetric] { metrics }
    func readingForTest(_ metric: Settings.RingMetric) -> (caption: String, value: String)? {
        guard let index = metrics.firstIndex(of: metric) else { return nil }
        return (captions[index].stringValue, values[index].stringValue)
    }
    var temperatureTextForTest: String { readingForTest(.temperature)?.value ?? "" }
    var trailingReadingForTest: (caption: String, value: String) {
        (captions[3].stringValue, values[3].stringValue)
    }
    var visibleReadingFramesForTest: [NSRect] {
        captions.indices.flatMap { [captions[$0].frame, values[$0].frame] }
    }
    var statsFitBoundsForTest: Bool {
        let visibleFields = captions.indices.flatMap { index -> [NSTextField] in
            [captions[index], values[index]]
        }
        return visibleFields.allSatisfy { field in
            bounds.contains(field.frame)
                && field.attributedStringValue.size().width <= field.bounds.width + 0.5
                && field.attributedStringValue.size().height <= field.bounds.height + 0.5
        }
    }

    func rotationMetricsForTest() -> (duration: CFTimeInterval, layerSpeed: Float)? {
        guard let motion = arcHost.animation(forKey: "spin") as? CABasicAnimation else { return nil }
        return (motion.duration, arcHost.speed)
    }
#endif
}
