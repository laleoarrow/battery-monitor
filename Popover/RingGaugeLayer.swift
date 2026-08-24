import AppKit

/// Charge as the outer ring, power intensity as a rotating inner arc, four
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

        for text in ["System Load", "To Battery", "Battery Temp", "Cycle Count"] {
            captions.append(label(text, size: 11, color: PopoverStyle.secondaryText))
        }
        for _ in 0..<4 {
            let field = label("--", size: 15, color: PopoverStyle.primaryText, mono: true)
            values.append(field)
        }
        captions[3].setAccessibilityElement(false)
        captions[3].cell?.setAccessibilityElement(false)
        values[3].setAccessibilityElement(true)
        values[3].setAccessibilityRole(.staticText)
        values[3].setAccessibilityLabel("Cycle Count")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        percentLabel.frame = NSRect(x: Self.centre.x - 40, y: Self.centre.y - 20, width: 80, height: 28)
        percentUnit.frame = NSRect(x: Self.centre.x - 40, y: Self.centre.y + 8, width: 80, height: 14)

        // Two columns beside the ring. The trailing slot may change content,
        // but its geometry remains identical.
        for index in 0..<4 {
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

    func update(snapshot: PowerSnapshot) {
        let color = PopoverStyle.stateColor(snapshot.state)
        intensity = VisualEncoding.t(snapshot.totalInputW)
        motionMultiplier = VisualEncoding.multiplier(snapshot.totalInputW)

        percentLabel.stringValue = "\(snapshot.percent)"
        percentLabel.textColor = snapshot.percent <= 20 ? PopoverStyle.red : PopoverStyle.primaryText

        captions[1].stringValue = PopoverStyle.batteryFlowLabel(snapshot.state)
        values[0].stringValue = PopoverStyle.watts(snapshot.systemW)
        values[1].stringValue = snapshot.state == .pluggedIdle
            ? "0.0 W" : PopoverStyle.watts(abs(snapshot.batteryW))
        values[2].stringValue = snapshot.temperatureC.map {
            String(format: "%.1f°C", $0)
        } ?? "—"
        if let deviceOutputW = snapshot.coherentDeviceOutputW {
            captions[3].stringValue = "Device Output"
            values[3].stringValue = PopoverStyle.watts(deviceOutputW)
            values[3].setAccessibilityLabel("Device Output")
        } else {
            captions[3].stringValue = "Cycle Count"
            values[3].stringValue = "\(snapshot.cycleCount)"
            values[3].setAccessibilityLabel("Cycle Count")
        }

        PopoverStyle.setWithoutAnimation {
            self.charge.strokeColor = (snapshot.percent <= 20 ? PopoverStyle.red : color).cgColor
            self.charge.strokeEnd = CGFloat(snapshot.percent) / 100
            let arcColor = snapshot.state == .mixedSupply ? PopoverStyle.blue : color
            self.arcGradient.colors = [arcColor.withAlphaComponent(0.12).cgColor, arcColor.cgColor]
            self.rotatingArc.strokeEnd = max(0.06, self.intensity)
        }
        applyRotation()
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
    var temperatureTextForTest: String { values[2].stringValue }
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
