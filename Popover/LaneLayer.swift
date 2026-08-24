import AppKit

/// Two lanes, each length proportional to its own wattage, with the value
/// inside the bar and the label at its far end.
///
/// The proportion is the whole point. Normalising against a fixed ceiling makes
/// 108 W and 32 W render at nearly the same length, which states something
/// false about the data.
final class LaneView: PopoverSection {
    static let laneHeight: CGFloat = 26
    static let laneGap: CGFloat = 9
    static let plotHeight: CGFloat = laneHeight * 2 + laneGap
    static let preferredHeight: CGFloat = plotHeight + PopoverStyle.sectionPadding * 2

    private static let wellSize: CGFloat = 26
    private static let trackX: CGFloat = wellSize + laneGap
    private static var trackWidth: CGFloat { PopoverStyle.contentWidth - trackX }

    private final class Lane {
        let well = CALayer()
        let icon = NSImageView()
        let track = CALayer()
        let fill = CALayer()
        let sweep = CAGradientLayer()
        var sweepWidth: CGFloat = 0
        let value = NSTextField(labelWithString: "0.0 W")
        let caption = NSTextField(labelWithString: "")

        init() {
            well.backgroundColor = PopoverStyle.well.cgColor
            well.cornerRadius = 8
            well.cornerCurve = .continuous

            track.backgroundColor = PopoverStyle.well.cgColor
            track.cornerRadius = 8
            track.cornerCurve = .continuous
            track.masksToBounds = true

            fill.cornerRadius = 8
            fill.cornerCurve = .continuous
            fill.masksToBounds = true
            sweep.startPoint = CGPoint(x: 0, y: 0.5)
            sweep.endPoint = CGPoint(x: 1, y: 0.5)
            fill.addSublayer(sweep)
            track.addSublayer(fill)

            value.font = PopoverStyle.mono(12.5)
            value.textColor = PopoverStyle.primaryText
            caption.font = .systemFont(ofSize: 11, weight: .regular)
            caption.textColor = PopoverStyle.secondaryText
            caption.alignment = .right
        }
    }

    private let lanes = [Lane(), Lane()]
    private var animationsEnabled = false
    private var motionMultiplier: CGFloat = 1
    private var latest: PowerSnapshot?

    init() {
        super.init(height: Self.preferredHeight)
        for lane in lanes {
            layer?.addSublayer(lane.well)
            layer?.addSublayer(lane.track)
            addSubview(lane.icon)
            addSubview(lane.value)
            addSubview(lane.caption)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        for (index, lane) in lanes.enumerated() {
            let y = PopoverStyle.sectionPadding + CGFloat(index) * (Self.laneHeight + Self.laneGap)
            PopoverStyle.setWithoutAnimation {
                lane.well.frame = CGRect(x: 0, y: y, width: Self.wellSize, height: Self.wellSize)
                lane.track.frame = CGRect(x: Self.trackX, y: y, width: Self.trackWidth, height: Self.laneHeight)
            }
            lane.icon.frame = NSRect(x: 5, y: y + 5, width: 16, height: 16)
            lane.value.frame = NSRect(x: Self.trackX + 10, y: y + 5, width: 90, height: 16)
            lane.caption.frame = NSRect(x: PopoverStyle.contentWidth - 130, y: y + 6, width: 120, height: 14)
        }
        if let latest { update(snapshot: latest) }
    }

    func update(snapshot: PowerSnapshot) {
        latest = snapshot
        let color = snapshot.state == .mixedSupply
            ? PopoverStyle.blue
            : PopoverStyle.stateColor(snapshot.state)
        let systemWatts = snapshot.systemW
        let batteryWatts = snapshot.state == .pluggedIdle ? 0 : abs(snapshot.batteryW)
        let hasPositiveDeviceOutput = snapshot.coherentDeviceOutputW.map { $0 > 0 } ?? false
        let systemCaption = hasPositiveDeviceOutput ? "System Total" : "System Load"

        // Normalise against the larger lane so the ratio between them is exact
        // and the dominant lane always fills its track.
        let ceiling = max(systemWatts, batteryWatts, 0.1)
        motionMultiplier = VisualEncoding.multiplier(snapshot.totalInputW)

        apply(lanes[0], symbol: "cpu", caption: systemCaption, watts: systemWatts,
              ceiling: ceiling, color: color)
        apply(lanes[1],
              symbol: snapshot.state == .charging ? "battery.100.bolt" : "battery.50",
              caption: PopoverStyle.batteryFlowLabel(snapshot.state),
              watts: batteryWatts, ceiling: ceiling, color: color)
    }

    private func apply(_ lane: Lane, symbol: String, caption: String,
                       watts: Double, ceiling: Double, color: NSColor) {
        lane.icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: caption)
        lane.icon.contentTintColor = color
        lane.value.stringValue = PopoverStyle.watts(watts)
        lane.caption.stringValue = caption

        let fraction = CGFloat(min(max(watts / ceiling, 0), 1))
        let width = max(fraction * Self.trackWidth, watts > 0.05 ? 12 : 0)

        CATransaction.begin()
        if animationsEnabled {
            CATransaction.setAnimationDuration(0.45)
        } else {
            CATransaction.setDisableActions(true)
        }
        lane.fill.frame = CGRect(x: 0, y: 0, width: width, height: Self.laneHeight)
        lane.fill.backgroundColor = color.withAlphaComponent(0.17).cgColor
        CATransaction.commit()

        PopoverStyle.setWithoutAnimation {
            lane.sweep.frame = CGRect(x: -width, y: 0, width: width * 2, height: Self.laneHeight)
            let clear = color.withAlphaComponent(0).cgColor
            lane.sweep.colors = [clear, color.withAlphaComponent(0.75).cgColor, clear, clear]
            lane.sweep.locations = [0, 0.2, 0.4, 1].map { NSNumber(value: $0) }
        }

        if animationsEnabled {
            if width > 0 {
                startSweep(lane, width: width)
            } else {
                lane.sweep.removeAnimation(forKey: "sweep")
                lane.sweepWidth = 0
            }
        }
    }

    private func startSweep(_ lane: Lane, width: CGFloat) {
        let previous = lane.sweep.animation(forKey: "sweep") as? CABasicAnimation
        if previous == nil || abs(width - lane.sweepWidth) > 0.5 {
            let motion = CABasicAnimation(keyPath: "position.x")
            // The gradient spans 2w and its bright pulse sits in the first
            // 40%. A 1w shift only carries the peak to 40% of the lane; 2w
            // moves it completely off both edges, so the whole bar is crossed
            // and the repeat happens while the pulse is invisible.
            motion.byValue = width * 2
            motion.duration = VisualEncoding.motionPeriod
            motion.repeatCount = .infinity
            motion.isRemovedOnCompletion = false
            if let previous {
                // Width follows 1 Hz telemetry. Retarget the travel distance
                // without restarting the normalized phase.
                motion.beginTime = previous.beginTime
                motion.timeOffset = previous.timeOffset
            } else {
                motion.beginTime = lane.sweep.convertTime(CACurrentMediaTime(), from: nil)
            }
            lane.sweep.add(motion, forKey: "sweep")
            lane.sweepWidth = width
        }
        // Keep this outside animation creation: total power can change the
        // shared rate even when a lane's width stays constant.
        PopoverStyle.setAnimationSpeed(lane.sweep, multiplier: motionMultiplier)
    }

    func setAnimationsEnabled(_ enabled: Bool) {
        animationsEnabled = enabled
        if enabled {
            for lane in lanes where lane.fill.bounds.width > 0 {
                startSweep(lane, width: lane.fill.bounds.width)
            }
        } else {
            lanes.forEach { $0.sweep.removeAllAnimations() }
        }
    }

#if DEBUG
    func sweepMetricsForTest(at index: Int) ->
        (fillWidth: CGFloat, travel: CGFloat, beginTime: CFTimeInterval,
         duration: CFTimeInterval, layerSpeed: Float)? {
        guard lanes.indices.contains(index),
              let motion = lanes[index].sweep.animation(forKey: "sweep") as? CABasicAnimation,
              let number = motion.byValue as? NSNumber else { return nil }
        return (lanes[index].fill.bounds.width, CGFloat(truncating: number),
                motion.beginTime, motion.duration, lanes[index].sweep.speed)
    }
#endif
}
