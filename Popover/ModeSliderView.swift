import AppKit

/// A horizontally locked Liquid Glass selector. The clear base carries the
/// labels; the stronger moving lens sits above it, so macOS can refract the
/// labels instead of merely painting a translucent pill behind them.
final class ModeSliderView: NSView {
    static let preferredHeight: CGFloat = 30

    private static var reducesMotion: Bool {
#if DEBUG
        if ProcessInfo.processInfo.environment["WATTSON_FORCE_REDUCE_MOTION"] == "1" { return true }
#endif
        return NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private static var reducesTransparency: Bool {
#if DEBUG
        if ProcessInfo.processInfo.environment["WATTSON_FORCE_REDUCE_TRANSPARENCY"] == "1" {
            return true
        }
#endif
        return NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }

    private let materialRoot = NSView()
    private let trackView = NSView()
    private let trackContent = NSView()
    private let knobHost = NSView()

    private var materialContainer: NSView?
    private var trackGlass: NSView?

    /// Liquid Glass accepts AppKit-only properties that a plain fallback view
    /// does not. Keeping the distinction typed prevents accidental KVC crashes
    /// on macOS versions that do not have NSGlassEffectView.
    private enum Knob {
        case glass(NSView)
        case plain(NSView)

        var view: NSView {
            switch self {
            case .glass(let view): return view
            case .plain(let view): return view
            }
        }

        func applyTint(_: NSColor) {
            switch self {
            case .glass(let view):
                // The reference lens is almost colourless. The selected label
                // carries semantic colour; a heavy glass tint kills refraction.
                if #available(macOS 26.0, *), let glass = view as? NSGlassEffectView {
                    glass.tintColor = NSColor.white.withAlphaComponent(0.05)
                }
            case .plain(let view):
                let reduceTransparency = ModeSliderView.reducesTransparency
                view.layer?.backgroundColor = reduceTransparency
                    ? NSColor(white: 0.30, alpha: 1).cgColor
                    : NSColor(white: 1, alpha: 0.12).cgColor
                // The native lens edge is neutral. Keep the older-system
                // fallback neutral too; semantic blue belongs to the label,
                // not to a second outline treatment.
                view.layer?.borderColor = NSColor.white.withAlphaComponent(
                    reduceTransparency ? 0.38 : 0.18
                ).cgColor
            }
        }

        func setLifted(_ lifted: Bool) {
            switch self {
            case .glass(let view):
                // Static selection is a neutral fogged plate; direct
                // manipulation becomes the clearer refractive lens.
                if #available(macOS 26.0, *), let glass = view as? NSGlassEffectView {
                    glass.style = lifted ? .clear : .regular
                    glass.tintColor = NSColor.white.withAlphaComponent(lifted ? 0.035 : 0.05)
                }
            case .plain(let view):
                let reduceTransparency = ModeSliderView.reducesTransparency
                view.layer?.backgroundColor = reduceTransparency
                    ? NSColor(white: lifted ? 0.25 : 0.30, alpha: 1).cgColor
                    : NSColor(white: 1, alpha: lifted ? 0.075 : 0.12).cgColor
            }
        }
    }

    private var knob: Knob?
    private var labels: [NSTextField] = []
    /// Fixed foreground copies stay aligned with each detent. Their layer
    /// opacities are blended from the lens centre, so direct manipulation never
    /// has to relayout text and a click cannot switch the highlight ahead of
    /// the glass presentation layer.
    private var activeLabels: [NSTextField] = []

    private var modes: [EnergyMode] = []
    private var enabled: [Bool] = []
    private var selectedIndex = 0
    /// Last mode confirmed by the system. `selectedIndex` may be optimistic
    /// while the helper performs a mode change on its worker queue.
    private var committedIndex = 0

#if DEBUG
    /// Relabelling is the expensive part of a drag. It must happen once per
    /// detent crossed, not once per mouse event.
    private(set) var highlightCallCountForTest = 0
    private(set) var labelBlendTraceForTest: [[CGFloat]] = []
    func resetLabelBlendTraceForTest() { labelBlendTraceForTest.removeAll(keepingCapacity: true) }
    var knobCentreForTest: CGFloat { knobHost.frame.midX }
    var settleIsAnimatingForTest: Bool { settleTimer != nil }
    var settleUsesSpringForTest: Bool { activeSettleMotion == .spring }
    var settleUsesMagneticFlowForTest: Bool { activeSettleMotion == .magnetic }
    var focusRingTypeForTest: NSFocusRingType { focusRingType }
    var restingKnobWidthForTest: CGFloat { knobFrame(at: selectedIndex).width }
    var segmentWidthForTest: CGFloat { segmentWidth }
    var selectedIndexForTest: Int { selectedIndex }
    var selectionIsPendingForTest: Bool { pendingSelectionIndex != nil }
    var reducesMotionForTest: Bool { Self.reducesMotion }
    var fallbackSelectorOpacityForTest: CGFloat? {
        guard case .plain(let selector) = knob else { return nil }
        return selector.layer?.backgroundColor?.alpha
    }
    var detentCentreForTest: (Int) -> CGFloat { { self.knobFrame(at: $0).midX } }
    var knobScaleForTest: CGSize {
        let base = knobFrame(at: selectedIndex)
        return CGSize(width: knobHost.frame.width / max(base.width, 1),
                      height: knobHost.frame.height / max(base.height, 1))
    }
    var knobPresentationCentreForTest: CGFloat {
        knobHost.layer?.presentation()?.frame.midX ?? knobHost.frame.midX
    }
    var glassViewFrameForTest: NSRect {
        guard let view = knob?.view else { return knobHost.frame }
        return convert(view.bounds, from: view)
    }
    var glassViewCentreForTest: CGFloat { glassViewFrameForTest.midX }
    var knobPresentationScaleForTest: CGSize {
        knobScaleForTest
    }
    var activeLabelOpacitiesForTest: [CGFloat] {
        activeLabels.map { CGFloat($0.layer?.opacity ?? 0) }
    }
    var activeLabelPresentationOpacitiesForTest: [CGFloat] {
        activeLabels.map { CGFloat($0.layer?.presentation()?.opacity ?? $0.layer?.opacity ?? 0) }
    }
    func magneticMotionCentresForTest(from startIndex: Int, to targetIndex: Int) -> [CGFloat] {
        magneticMotion(from: knobFrame(at: startIndex).midX,
                       to: knobFrame(at: targetIndex).midX).centres
    }
    var nativeGlassStylesForTest: (track: Int, selector: Int)? {
        guard #available(macOS 26.0, *),
              let track = trackGlass as? NSGlassEffectView,
              case .glass(let selectorView) = knob,
              let selector = selectorView as? NSGlassEffectView else { return nil }
        return (track.style.rawValue, selector.style.rawValue)
    }
#endif

    private var dragging = false
    private var grabbedKnob = false
    private var dragStartCentreX: CGFloat = 0
    private var grabOffsetFromCentre: CGFloat = 0
    private var pressX: CGFloat = 0
    private var movedWhileDragging = false
    private var highlighted = -1
    private var currentTint = PopoverStyle.blue

    private var lastPointerX: CGFloat = 0
    private var lastEventTimestamp: TimeInterval?
    private var dragVelocityX: CGFloat = 0

    private var selectionGeneration = 0
    private var pendingSelectionIndex: Int?
    private var displayOptionsObserver: NSObjectProtocol?
    /// Native Liquid Glass is promoted into the container's own SDF/backdrop
    /// tree. Advancing an ancestor's presentation layer does not move that
    /// material, so the brief settle drives the actual view frame instead.
    private var settleTimer: Timer?
    private var activeSettleMotion: SettleMotion?

    /// Four points filters trackpad tap wobble without making a deliberate drag
    /// feel sticky. A drag that begins away from the knob moves relatively, so
    /// crossing this threshold never makes the lens jump under the pointer.
    private static let dragSlop: CGFloat = 4
    private static let pressedScale = CGSize(width: 1.13, height: 1.35)

    private enum SettleMotion: Equatable {
        case magnetic
        case spring
    }

    /// Completion is asynchronous so helper wake-up, `pmset`, and readback never
    /// hold AppKit's event loop while the release spring is trying to render.
    var onSelect: ((EnergyMode, @escaping (EnergyMode?) -> Void) -> Void)?

    override var isFlipped: Bool { true }

    init(modes: [EnergyMode]) {
        self.modes = modes
        super.init(frame: NSRect(x: 0, y: 0,
                                 width: PopoverStyle.contentWidth,
                                 height: Self.preferredHeight))
        wantsLayer = true
        installMaterials()

        for mode in modes {
            let field = NSTextField(labelWithString: mode.title)
            field.font = .systemFont(ofSize: 11, weight: .medium)
            field.alignment = .center
            field.isSelectable = false
            field.wantsLayer = true
            field.setAccessibilityElement(false)
            trackContent.addSubview(field)
            labels.append(field)

            let active = NSTextField(labelWithString: mode.title)
            active.font = .systemFont(ofSize: 11, weight: .medium)
            active.alignment = .center
            active.isSelectable = false
            active.wantsLayer = true
            active.layer?.opacity = 0
            active.setAccessibilityElement(false)
            addSubview(active)
            activeLabels.append(active)
        }
        enabled = Array(repeating: true, count: modes.count)
        configureAccessibility()
        displayOptionsObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: NSWorkspace.shared,
            queue: .main
        ) { [weak self] _ in
            self?.refreshDisplayOptions()
        }
        refreshDisplayOptions()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        settleTimer?.invalidate()
        if let displayOptionsObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(displayOptionsObserver)
        }
    }

    // MARK: - Keyboard and accessibility

    private func configureAccessibility() {
        setAccessibilityElement(true)
        setAccessibilityRole(.slider)
        setAccessibilityLabel("电源模式")
        setAccessibilityOrientation(.horizontal)
        setAccessibilityMinValue(NSNumber(value: 0))
        setAccessibilityMaxValue(NSNumber(value: max(modes.count - 1, 0)))
        // This compact popover already exposes the selected label in blue.
        // AppKit's full-control accent ring reads as a second, unrelated glass
        // outline after a mouse click, so keep keyboard semantics without it.
        focusRingType = .none
        updateAccessibilityValue(announce: false)
    }

    private func updateAccessibilityValue(announce: Bool) {
        guard modes.indices.contains(selectedIndex) else { return }
        setAccessibilityEnabled(enabled.contains(true))
        setAccessibilityAllowedValues(
            enabled.indices.filter { enabled[$0] }.map { NSNumber(value: $0) }
        )
        setAccessibilityValue(NSNumber(value: selectedIndex))
        setAccessibilityValueDescription(modes[selectedIndex].title)
        if announce {
            NSAccessibility.post(element: self, notification: .valueChanged)
        }
    }

    override var acceptsFirstResponder: Bool { enabled.contains(true) }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123:
            if selectAdjacentMode(direction: -1) { return }
        case 124:
            if selectAdjacentMode(direction: 1) { return }
        case 36, 49, 76:
            commitSelection(selectedIndex)
            return
        default:
            break
        }
        super.keyDown(with: event)
    }

    override func accessibilityPerformIncrement() -> Bool {
        selectAdjacentMode(direction: 1)
    }

    override func accessibilityPerformDecrement() -> Bool {
        selectAdjacentMode(direction: -1)
    }

    override func accessibilityPerformPress() -> Bool {
        guard enabled.indices.contains(selectedIndex), enabled[selectedIndex] else { return false }
        commitSelection(selectedIndex)
        return true
    }

    // MARK: - Material

    /// Builds the two reference surfaces in one native glass container:
    /// a dark-tinted regular base and a regular, empty selector above its content.
    /// On older systems the exact same hierarchy gets a lightweight translucent
    /// fallback, keeping event and geometry behavior identical.
    private func installMaterials() {
        materialRoot.wantsLayer = true
        trackView.wantsLayer = true
        trackContent.wantsLayer = true
        knobHost.wantsLayer = true

        let forceLegacy = ProcessInfo.processInfo.environment["WATTSON_FORCE_LEGACY_KNOB"] == "1"
        let radius = (Self.preferredHeight - 4) / 2

        if !forceLegacy, #available(macOS 26.0, *) {
            let container = NSGlassEffectContainerView(frame: .zero)
            container.contentView = materialRoot
            // Zero still batches the two related glass surfaces, without asking
            // AppKit to merge the full-width base into the moving selector.
            container.spacing = 0
            addSubview(container)
            materialContainer = container

            let base = NSGlassEffectView(frame: .zero)
            configureGlass(base, style: .regular, cornerRadius: Self.preferredHeight / 2,
                           tint: NSColor.black.withAlphaComponent(0.16), content: trackContent)
            trackView.addSubview(base)
            trackGlass = base

            let selectorContent = NSView()
            selectorContent.wantsLayer = true
            selectorContent.layer?.backgroundColor = NSColor.clear.cgColor
            let selector = NSGlassEffectView(frame: .zero)
            configureGlass(selector, style: .regular, cornerRadius: radius,
                           tint: NSColor.white.withAlphaComponent(0.05), content: selectorContent)
            knobHost.addSubview(selector)
            knob = .glass(selector)
        } else {
            addSubview(materialRoot)
            trackView.addSubview(trackContent)

            let selector = NSView(frame: .zero)
            selector.wantsLayer = true
            selector.layer?.backgroundColor = NSColor(white: 1, alpha: 0.12).cgColor
            selector.layer?.borderColor = NSColor(white: 1, alpha: 0.24).cgColor
            selector.layer?.borderWidth = 0.5
            selector.layer?.cornerRadius = radius
            selector.layer?.cornerCurve = .continuous
            knobHost.addSubview(selector)
            knob = .plain(selector)
        }

        materialRoot.addSubview(trackView)
        materialRoot.addSubview(knobHost)
        installFallbackChromeIfNeeded()
    }

    @available(macOS 26.0, *)
    private func configureGlass(_ view: NSGlassEffectView, style: NSGlassEffectView.Style,
                                cornerRadius: CGFloat,
                                tint: NSColor?, content: NSView) {
        view.cornerRadius = cornerRadius
        view.style = style
        view.tintColor = tint
        view.contentView = content
    }

    private func installFallbackChromeIfNeeded() {
        trackView.layer?.cornerRadius = Self.preferredHeight / 2
        trackView.layer?.cornerCurve = .continuous
        trackView.layer?.masksToBounds = true
        knobHost.layer?.backgroundColor = NSColor.clear.cgColor
        knobHost.layer?.cornerRadius = (Self.preferredHeight - 4) / 2
        knobHost.layer?.cornerCurve = .continuous

        // Native Liquid Glass supplies its own dynamic reflection, refraction,
        // colour separation, edge lighting, and shadow. The older-system path
        // stays deliberately restrained instead of imitating those effects
        // with static gradients that would look painted on during movement.
        guard trackGlass == nil else { return }
        trackView.layer?.backgroundColor = PopoverStyle.well.cgColor
        trackView.layer?.borderWidth = 0.5
        trackView.layer?.borderColor = PopoverStyle.wellBorder.withAlphaComponent(0.78).cgColor
        knobHost.layer?.shadowColor = NSColor.black.cgColor
        knobHost.layer?.shadowOpacity = 0.28
        knobHost.layer?.shadowRadius = 5
        knobHost.layer?.shadowOffset = CGSize(width: 0, height: 2)
    }

    private func refreshDisplayOptions() {
        applyTrackTint(currentTint)
        knob?.applyTint(currentTint)
        knob?.setLifted(movedWhileDragging)
        if highlighted >= 0 { highlight(highlighted, force: true) }
    }

    /// The outer panel edge follows the live power state. Native Liquid Glass
    /// derives the coloured edge from its semantic tint; the older-system path
    /// uses the same tint on its real border rather than a fixed blue accent.
    private func applyTrackTint(_ tint: NSColor) {
        if #available(macOS 26.0, *), let glass = trackGlass as? NSGlassEffectView {
            glass.tintColor = tint.withAlphaComponent(0.11)
        } else {
            trackView.layer?.borderColor = tint.withAlphaComponent(
                Self.reducesTransparency ? 0.56 : 0.40
            ).cgColor
        }
    }

    /// Core Animation would otherwise derive the shadow from the glass alpha on
    /// every frame. A fixed bounds-relative path stays cheap while the host is
    /// moved and scaled by the compositor.
    private func updateShadowPath() {
        guard trackGlass == nil else { return }
        let radius = knobHost.layer?.cornerRadius ?? 0
        knobHost.layer?.shadowPath = CGPath(roundedRect: knobHost.bounds,
                                            cornerWidth: radius,
                                            cornerHeight: radius,
                                            transform: nil)
    }

    // MARK: - Geometry

    private var segmentWidth: CGFloat { bounds.width / CGFloat(max(modes.count, 1)) }

    private func knobFrame(at index: Int) -> NSRect {
        let width = segmentWidth
        let centre = (CGFloat(index) + 0.5) * segmentWidth
        return NSRect(x: centre - width / 2, y: 2,
                      width: width, height: bounds.height - 4)
    }

    override func layout() {
        super.layout()
        PopoverStyle.setWithoutAnimation {
            self.materialContainer?.frame = self.bounds
            self.materialRoot.frame = self.bounds
            self.trackView.frame = self.bounds
            self.trackGlass?.frame = self.trackView.bounds
            self.trackContent.frame = self.trackView.bounds
        }
        for index in labels.indices {
            let frame = NSRect(x: CGFloat(index) * segmentWidth,
                               y: (bounds.height - 15) / 2,
                               width: segmentWidth, height: 15)
            labels[index].frame = frame
            activeLabels[index].frame = frame
        }
        if !dragging, settleTimer == nil {
            knobHost.frame = knobFrame(at: selectedIndex)
        }
        knob?.view.frame = knobHost.bounds
        updateShadowPath()
        if settleTimer == nil {
            applyLabelBlend(at: knobHost.frame.midX)
        }
    }

    // MARK: - State

    func update(selected: EnergyMode, enabledModes: [EnergyMode], tint: NSColor) {
        enabled = modes.map(enabledModes.contains)
        let previous = selectedIndex
        if let externalIndex = modes.firstIndex(of: selected), pendingSelectionIndex == nil {
            committedIndex = externalIndex
            if !dragging { selectedIndex = externalIndex }
        }

        currentTint = tint
        applyTrackTint(tint)
        knob?.applyTint(tint)
        // During a held drag the 1 Hz telemetry refresh must recolour the mode
        // under the lens, not jump the highlight back to the committed mode.
        let visualIndex = dragging && highlighted >= 0 ? highlighted : selectedIndex
        highlight(visualIndex, force: true)
        updateAccessibilityValue(announce: false)

        if !dragging, pendingSelectionIndex == nil, selectedIndex != previous {
            settle(to: selectedIndex, animated: true)
        }
    }

    /// Clicks flow toward the next detent with a small overshoot and pull-back;
    /// a released drag keeps the shorter viscous spring. Both motions advance
    /// the real view frame because NSGlassEffectContainerView promotes glass
    /// into a material tree that does not follow an ancestor's CA presentation.
    private func settle(to index: Int, animated: Bool, initialVelocityX: CGFloat = 0,
                        motion: SettleMotion = .magnetic) {
        let target = knobFrame(at: index)
        let start = knobHost.frame
        stopSettleMotion()
        knobHost.layer?.removeAllAnimations()
        PopoverStyle.setWithoutAnimation {
            self.knobHost.layer?.transform = CATransform3DIdentity
        }
        knob?.setLifted(false)

        let reduceMotion = Self.reducesMotion
        let geometryChanged = abs(target.midX - start.midX) > 0.5
            || abs(target.width - start.width) > 0.5
            || abs(target.height - start.height) > 0.5
        guard animated, !reduceMotion, window?.isVisible == true,
              start.width > 0.5, geometryChanged else {
            setKnobGeometry(centreX: target.midX,
                            width: target.width,
                            height: target.height)
            return
        }

        switch motion {
        case .magnetic:
            let path = magneticMotion(from: start.midX, to: target.midX)
            startSettleMotion(kind: .magnetic, duration: path.duration) { phase in
                let centre = self.interpolatedCentre(in: path, phase: phase)
                let scale = self.magneticScale(at: phase,
                                               start: CGSize(width: start.width / target.width,
                                                             height: start.height / target.height))
                return NSRect(x: centre - target.width * scale.width / 2,
                              y: (self.bounds.height - target.height * scale.height) / 2,
                              width: target.width * scale.width,
                              height: target.height * scale.height)
            } completion: {
                self.setKnobGeometry(centreX: target.midX,
                                     width: target.width,
                                     height: target.height)
            }

        case .spring:
            let duration: CFTimeInterval = 0.32
            let impulse = min(max(initialVelocityX * 0.012, -12), 12)
            startSettleMotion(kind: .spring, duration: duration) { phase in
                let progress = self.springProgress(phase)
                let velocityCarry = impulse * phase * exp(-6 * phase)
                let centre = start.midX + (target.midX - start.midX) * progress + velocityCarry
                let width = start.width + (target.width - start.width) * progress
                let height = start.height + (target.height - start.height) * progress
                return NSRect(x: centre - width / 2,
                              y: (self.bounds.height - height) / 2,
                              width: width, height: height)
            } completion: {
                self.setKnobGeometry(centreX: target.midX,
                                     width: target.width,
                                     height: target.height)
            }
        }
    }

    private func magneticDuration(for travel: CGFloat) -> CFTimeInterval {
        let detentDistance = min(abs(travel) / max(segmentWidth, 1), 2)
        return 0.36 + 0.06 * Double(detentDistance)
    }

    private struct MagneticMotion {
        let centres: [CGFloat]
        let keyTimes: [NSNumber]
        let duration: CFTimeInterval
    }

    /// Samples one shared magnetic trajectory for both the glass position and
    /// label opacity. Exact detent-crossing phases are inserted so a two-slot
    /// click still brings the middle label all the way to full brightness.
    private func magneticMotion(from start: CGFloat, to target: CGFloat) -> MagneticMotion {
        let travel = target - start
        let direction: CGFloat = travel < 0 ? -1 : 1
        let overshoot = direction * min(max(abs(travel) * 0.018, 1.5), 3)

        func smoothstep(_ value: CGFloat) -> CGFloat {
            value * value * (3 - 2 * value)
        }
        func centre(at phase: CGFloat) -> CGFloat {
            if phase <= 0.72 {
                let progress = smoothstep(phase / 0.72)
                return start + travel * progress
            }
            if phase <= 0.82 {
                let progress = (phase - 0.72) / 0.10
                let eased = 1 - (1 - progress) * (1 - progress)
                return target + overshoot * eased
            }
            let progress = (phase - 0.82) / 0.18
            let remaining = 1 - progress
            return target + overshoot * remaining * remaining * remaining
        }
        func phase(forLinearProgress progress: CGFloat) -> CGFloat {
            var lower: CGFloat = 0
            var upper: CGFloat = 1
            for _ in 0..<18 {
                let midpoint = (lower + upper) / 2
                if smoothstep(midpoint) < progress {
                    lower = midpoint
                } else {
                    upper = midpoint
                }
            }
            return 0.72 * (lower + upper) / 2
        }

        var phases = (0...30).map { CGFloat($0) / 30 }
        phases.append(contentsOf: [0.72, 0.82])
        var centreOverrides: [(phase: CGFloat, centre: CGFloat)] = []
        if abs(travel) > 0.5 {
            for index in modes.indices {
                let detent = knobFrame(at: index).midX
                let progress = (detent - start) / travel
                if progress > 0, progress < 1 {
                    let crossing = phase(forLinearProgress: progress)
                    let halfWindow: CGFloat = 0.04
                    phases.removeAll { abs($0 - crossing) < halfWindow }
                    centreOverrides.append((crossing - halfWindow,
                                            detent - direction * 4))
                    centreOverrides.append((crossing, detent))
                    centreOverrides.append((crossing + halfWindow,
                                            detent + direction * 4))
                    phases.append(contentsOf: centreOverrides.suffix(3).map { $0.phase })
                }
            }
        }
        phases.sort()
        var uniquePhases: [CGFloat] = []
        for phase in phases where uniquePhases.last.map({ abs($0 - phase) > 0.0001 }) ?? true {
            uniquePhases.append(phase)
        }
        return MagneticMotion(
            centres: uniquePhases.map { phase in
                centreOverrides.first(where: { abs($0.phase - phase) < 0.0001 })?.centre
                    ?? centre(at: phase)
            },
            keyTimes: uniquePhases.map { NSNumber(value: Double($0)) },
            duration: magneticDuration(for: travel)
        )
    }

    private func interpolatedCentre(in motion: MagneticMotion, phase: CGFloat) -> CGFloat {
        guard let first = motion.centres.first, let last = motion.centres.last else { return 0 }
        if phase <= 0 { return first }
        if phase >= 1 { return last }
        for index in 1..<motion.keyTimes.count {
            let upper = CGFloat(truncating: motion.keyTimes[index])
            guard phase <= upper else { continue }
            let lower = CGFloat(truncating: motion.keyTimes[index - 1])
            let span = max(upper - lower, 0.0001)
            let progress = (phase - lower) / span
            return motion.centres[index - 1]
                + (motion.centres[index] - motion.centres[index - 1]) * progress
        }
        return last
    }

    /// Click motion stays within the resting footprint: it streamlines while
    /// travelling, compresses slightly at capture, then returns to one detent.
    private func magneticScale(at phase: CGFloat, start: CGSize) -> CGSize {
        let times: [CGFloat] = [0, 0.18, 0.56, 0.82, 1]
        let widths: [CGFloat] = [start.width, 1, 1, 0.98, 1]
        let heights: [CGFloat] = [start.height, 0.98, 0.92, 0.96, 1]
        for index in 1..<times.count where phase <= times[index] {
            let progress = (phase - times[index - 1])
                / max(times[index] - times[index - 1], 0.0001)
            return CGSize(
                width: widths[index - 1] + (widths[index] - widths[index - 1]) * progress,
                height: heights[index - 1] + (heights[index] - heights[index - 1]) * progress
            )
        }
        return CGSize(width: 1, height: 1)
    }

    /// Normalized critically damped response. It has a decisive pull toward
    /// the detent without the loose oscillation that made release feel rubbery.
    private func springProgress(_ phase: CGFloat) -> CGFloat {
        let clamped = min(max(phase, 0), 1)
        let x = 7 * clamped
        let raw = 1 - (1 + x) * exp(-x)
        let end = 1 - 8 * exp(CGFloat(-7))
        return min(max(raw / end, 0), 1)
    }

    private func startSettleMotion(kind: SettleMotion, duration: CFTimeInterval,
                                   frameAt: @escaping (CGFloat) -> NSRect,
                                   completion: @escaping () -> Void) {
        stopSettleMotion()
        activeSettleMotion = kind
        let startTime = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            let phase = min(max(CGFloat((CACurrentMediaTime() - startTime) / duration), 0), 1)
            if phase >= 1 || self.window?.isVisible != true {
                timer.invalidate()
                self.settleTimer = nil
                self.activeSettleMotion = nil
                completion()
                return
            }
            self.setKnobFrame(frameAt(phase))
        }
        settleTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        timer.fire()
    }

    private func stopSettleMotion() {
        settleTimer?.invalidate()
        settleTimer = nil
        activeSettleMotion = nil
    }

    private func setKnobFrame(_ frame: NSRect) {
        PopoverStyle.setWithoutAnimation {
            self.knobHost.frame = frame
            self.knob?.view.frame = self.knobHost.bounds
        }
        updateShadowPath()
        applyLabelBlend(at: frame.midX)
    }

    private func setKnobGeometry(centreX: CGFloat, width: CGFloat, height: CGFloat) {
        setKnobFrame(NSRect(x: centreX - width / 2,
                            y: (bounds.height - height) / 2,
                            width: width, height: height))
    }

    /// Linear distance weights make the foreground labels crossfade exactly at
    /// the lens centre: a detent is fully bright at its centre and two adjacent
    /// labels are each 50% bright halfway between them.
    private func labelBlendWeights(at centreX: CGFloat) -> [CGFloat] {
        modes.indices.map { index in
            guard enabled.indices.contains(index), enabled[index] else { return 0 }
            let distance = abs(knobFrame(at: index).midX - centreX)
            return min(max(1 - distance / max(segmentWidth, 1), 0), 1)
        }
    }

    private func applyLabelBlend(at centreX: CGFloat) {
        let weights = labelBlendWeights(at: centreX)
#if DEBUG
        labelBlendTraceForTest.append(weights)
#endif
        PopoverStyle.setWithoutAnimation {
            for index in self.activeLabels.indices {
                let weight = weights[index]
                self.activeLabels[index].layer?.opacity = Float(weight)
                self.labels[index].layer?.opacity = self.trackGlass == nil
                    ? Float(1 - weight)
                    : 1
            }
        }
    }

    private func refreshLabelPalette() {
        let active = currentTint.blended(withFraction: 0.14, of: .white) ?? currentTint
        for index in labels.indices {
            labels[index].textColor = enabled[index]
                ? PopoverStyle.secondaryText
                : PopoverStyle.tertiaryText
            activeLabels[index].textColor = enabled[index]
                ? active
                : PopoverStyle.tertiaryText
        }
    }

    // MARK: - Clicks and drags

    /// The nested material and label views are decoration; hit-test the whole
    /// selector as one control so first-mouse delivery cannot leak its hierarchy.
    override func hitTest(_ point: NSPoint) -> NSView? {
        // Unlike UIKit, AppKit passes this point in the superview's coordinate
        // system. Convert once before checking our bounds.
        guard let superview else { return nil }
        let local = convert(point, from: superview)
        return bounds.contains(local) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard enabled.contains(true) else { return }
        let point = convert(event.locationInWindow, from: nil)
        let visibleCentre = interruptSettleAtVisibleGeometry()

        dragging = true
        movedWhileDragging = false
        pressX = point.x
        dragStartCentreX = visibleCentre
        grabbedKnob = abs(point.x - visibleCentre) <= knobHost.frame.width / 2
        grabOffsetFromCentre = grabbedKnob ? point.x - visibleCentre : 0
        lastPointerX = point.x
        lastEventTimestamp = event.timestamp > 0 ? event.timestamp : nil
        dragVelocityX = 0
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragging else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard movedWhileDragging || abs(point.x - pressX) >= Self.dragSlop else { return }

        if !movedWhileDragging {
            movedWhileDragging = true
            knob?.setLifted(true)
        }
        updateVelocity(pointerX: point.x, timestamp: event.timestamp)

        let rawCentre = grabbedKnob
            ? point.x - grabOffsetFromCentre
            : dragStartCentreX + (point.x - pressX)
        let centre = clampedCentre(rawCentre)
        let nearest = nearestIndex(toward: centre)
        let nearestCentre = knobFrame(at: nearest).midX
        let between = min(abs(centre - nearestCentre) / max(segmentWidth / 2, 1), 1)
        let speed = min(abs(dragVelocityX) / 1_600, 1)

        let reduceMotion = Self.reducesMotion
        let scaleX = reduceMotion ? 1 : Self.pressedScale.width + 0.07 * between + 0.03 * speed
        let scaleY = reduceMotion ? 1 : Self.pressedScale.height + 0.04 * speed
        moveKnob(centreX: centre, scaleX: scaleX, scaleY: scaleY)

        if nearest != highlighted { highlight(nearest) }
        lastPointerX = point.x
    }

    override func mouseUp(with event: NSEvent) {
        guard dragging else { return }
        dragging = false
        let motion: SettleMotion = movedWhileDragging ? .spring : .magnetic

        let index: Int
        if movedWhileDragging {
            let point = convert(event.locationInWindow, from: nil)
            let releaseCentre = grabbedKnob
                ? point.x - grabOffsetFromCentre
                : dragStartCentreX + (point.x - pressX)
            index = nearestIndex(toward: clampedCentre(releaseCentre))
        } else {
            let pressedIndex = nearestDetentIndex(toward: pressX)
            guard enabled[pressedIndex] else {
                settle(to: selectedIndex, animated: true, motion: motion)
                highlight(selectedIndex)
                return
            }
            index = pressedIndex
        }

        // Availability can change while the pointer is held (for example if
        // the helper disappears). Always lower the lens back onto the last
        // confirmed detent instead of leaving a disabled drag suspended.
        guard enabled.indices.contains(index), enabled[index] else {
            settle(to: committedIndex, animated: true, motion: motion)
            highlight(committedIndex)
            return
        }
        commitSelection(index, initialVelocityX: dragVelocityX, motion: motion)
    }

    @discardableResult
    private func selectAdjacentMode(direction: Int) -> Bool {
        let candidates = enabled.indices.filter { enabled[$0] }
        let target = direction < 0
            ? candidates.last(where: { $0 < selectedIndex })
            : candidates.first(where: { $0 > selectedIndex })
        guard let target else { return false }
        commitSelection(target)
        return true
    }

    private func commitSelection(_ index: Int, initialVelocityX: CGFloat = 0,
                                 motion: SettleMotion = .magnetic) {
        guard enabled.indices.contains(index), enabled[index] else { return }
        let changed = selectedIndex != index
        selectedIndex = index
        settle(to: index, animated: true, initialVelocityX: initialVelocityX, motion: motion)
        highlight(index)
        updateAccessibilityValue(announce: changed)

        if pendingSelectionIndex == index { return }
        guard index != committedIndex || pendingSelectionIndex != nil else { return }

        selectionGeneration += 1
        let generation = selectionGeneration
        pendingSelectionIndex = index
        guard let onSelect else {
            finishSelection(index: index, generation: generation, landedMode: nil)
            return
        }
        onSelect(modes[index]) { [weak self] landedMode in
            guard let self else { return }
            if Thread.isMainThread {
                self.finishSelection(index: index, generation: generation, landedMode: landedMode)
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.finishSelection(index: index, generation: generation, landedMode: landedMode)
                }
            }
        }
    }

    private func finishSelection(index: Int, generation: Int, landedMode: EnergyMode?) {
        guard generation == selectionGeneration else { return }
        pendingSelectionIndex = nil
        let landedIndex = landedMode.flatMap { modes.firstIndex(of: $0) } ?? committedIndex
        committedIndex = landedIndex
        guard !dragging else { return }

        let changed = selectedIndex != landedIndex
        selectedIndex = landedIndex
        if landedIndex != index { settle(to: landedIndex, animated: true) }
        highlight(selectedIndex)
        updateAccessibilityValue(announce: changed)
    }

    /// A settle advances model geometry, so re-grabbing simply freezes its last
    /// real frame. There is no separate presentation position to reconcile.
    private func interruptSettleAtVisibleGeometry() -> CGFloat {
        let visibleCentre = knobHost.frame.midX
        stopSettleMotion()
        knobHost.layer?.removeAllAnimations()
        PopoverStyle.setWithoutAnimation {
            self.knobHost.layer?.transform = CATransform3DIdentity
        }
        applyLabelBlend(at: visibleCentre)
        return visibleCentre
    }

    private func moveKnob(centreX: CGFloat, scaleX: CGFloat, scaleY: CGFloat) {
        let base = knobFrame(at: selectedIndex)
        setKnobGeometry(centreX: centreX,
                        width: base.width * scaleX,
                        height: base.height * scaleY)
    }

    /// The optical body may extend beyond the base, but its centre stops exactly
    /// on the first and last slot like the reference control.
    private func clampedCentre(_ centre: CGFloat) -> CGFloat {
        let firstIndex = modes.indices.first ?? 0
        let lastIndex = modes.indices.last ?? firstIndex
        let first = knobFrame(at: firstIndex).midX
        let last = knobFrame(at: lastIndex).midX
        return min(max(centre, first), last)
    }

    private func updateVelocity(pointerX: CGFloat, timestamp: TimeInterval) {
        defer { if timestamp > 0 { lastEventTimestamp = timestamp } }
        guard timestamp > 0, let previous = lastEventTimestamp else { return }
        let deltaTime = timestamp - previous
        guard deltaTime >= 1.0 / 240.0, deltaTime <= 0.20 else { return }
        let instant = (pointerX - lastPointerX) / CGFloat(deltaTime)
        dragVelocityX = dragVelocityX * 0.68 + instant * 0.32
    }

    private func nearestDetentIndex(toward x: CGFloat) -> Int {
        modes.indices.min {
            abs(knobFrame(at: $0).midX - x) < abs(knobFrame(at: $1).midX - x)
        } ?? selectedIndex
    }

    /// Skips disabled detents while dragging, so release always resolves to a
    /// real mode. Disabled clicks are handled separately and remain a no-op.
    private func nearestIndex(toward x: CGFloat) -> Int {
        let candidates = modes.indices.filter { enabled[$0] }
        guard !candidates.isEmpty else { return committedIndex }
        return candidates.min {
            abs(knobFrame(at: $0).midX - x) < abs(knobFrame(at: $1).midX - x)
        } ?? committedIndex
    }

    /// Semantic detent changes stay discrete for accessibility and writeback;
    /// visible brightness is handled independently by cheap layer opacity.
    private func highlight(_ index: Int, force: Bool = false) {
        guard force || index != highlighted else { return }
#if DEBUG
        highlightCallCountForTest += 1
#endif
        highlighted = index
        refreshLabelPalette()
        if !dragging, settleTimer == nil {
            applyLabelBlend(at: knobHost.frame.midX)
        }
    }
}
