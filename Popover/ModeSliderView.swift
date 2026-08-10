import AppKit

/// A horizontally locked mode bar. One native Liquid Glass surface carries
/// the labels; a restrained neutral capsule moves above it to show selection
/// without stacking a second foggy glass layer.
final class ModeSliderView: NSView {
    static let preferredHeight: CGFloat = 30

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

    private var trackGlass: NSView?
    private var usesNativeGlass = false

    /// The native selected capsule is intentionally a lightweight overlay.
    /// Refraction belongs to the shared track, which avoids sampling glass
    /// through glass while the capsule moves between detents.
    private enum Knob {
        case nativeSelection(NSView)
        case plain(NSView)

        var view: NSView {
            switch self {
            case .nativeSelection(let view): return view
            case .plain(let view): return view
            }
        }

        func applyTint(_: NSColor) {
            switch self {
            case .nativeSelection(let view):
                view.layer?.backgroundColor = NSColor.white.withAlphaComponent(
                    ModeSliderView.reducesTransparency ? 0.24 : 0.10
                ).cgColor
                view.layer?.borderWidth = 0
            case .plain(let view):
                let reduceTransparency = ModeSliderView.reducesTransparency
                view.layer?.backgroundColor = reduceTransparency
                    ? NSColor(white: 0.30, alpha: 1).cgColor
                    : NSColor(white: 1, alpha: 0.12).cgColor
                // The native capsule edge is neutral. Keep the older-system
                // fallback neutral too; semantic colour belongs to the label,
                // not to a second outline treatment.
                view.layer?.borderColor = NSColor.white.withAlphaComponent(
                    reduceTransparency ? 0.38 : 0.18
                ).cgColor
            }
        }

        func setLifted(_ lifted: Bool) {
            switch self {
            case .nativeSelection(let view):
                let reduceTransparency = ModeSliderView.reducesTransparency
                view.layer?.backgroundColor = NSColor.white.withAlphaComponent(
                    reduceTransparency ? (lifted ? 0.20 : 0.24) : (lifted ? 0.14 : 0.10)
                ).cgColor
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
    /// opacities are blended from the capsule centre, so direct manipulation never
    /// has to relayout text and a click cannot switch the highlight ahead of
    /// the moving selection.
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
    var settleIsAnimatingForTest: Bool { activeSettleMotion != nil }
    var settleUsesSpringForTest: Bool { activeSettleMotion == .spring }
    var settleUsesMagneticFlowForTest: Bool { activeSettleMotion == .magnetic }
    var settleDurationForTest: CFTimeInterval? { activeSettleDuration }
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
    var knobPresentationCentreForTest: CGFloat { visibleKnobFrame().midX }
    var glassViewFrameForTest: NSRect { visibleKnobFrame() }
    var glassViewCentreForTest: CGFloat { glassViewFrameForTest.midX }
    var knobPresentationScaleForTest: CGSize {
        let base = knobFrame(at: selectedIndex)
        let visible = visibleKnobFrame()
        return CGSize(width: visible.width / max(base.width, 1),
                      height: visible.height / max(base.height, 1))
    }
    var activeLabelOpacitiesForTest: [CGFloat] {
        guard activeSettleMotion != nil else {
            return activeLabels.map { CGFloat($0.layer?.opacity ?? 0) }
        }
        return labelBlendWeights(at: visibleKnobFrame().midX)
    }
    var activeLabelPresentationOpacitiesForTest: [CGFloat] {
        activeLabels.map { CGFloat($0.layer?.presentation()?.opacity ?? $0.layer?.opacity ?? 0) }
    }
    func magneticMotionCentresForTest(from startIndex: Int, to targetIndex: Int) -> [CGFloat] {
        magneticMotion(from: knobFrame(at: startIndex).midX,
                       to: knobFrame(at: targetIndex).midX).centres
    }
    var nativeTrackStyleForTest: Int? {
        guard #available(macOS 26.0, *), usesNativeGlass,
              let track = trackGlass as? NSGlassEffectView else { return nil }
        return track.style.rawValue
    }
    var nativeTrackHasTintForTest: Bool? {
        guard #available(macOS 26.0, *), usesNativeGlass,
              let track = trackGlass as? NSGlassEffectView else { return nil }
        return track.tintColor != nil
    }
    var nativeSelectorFillAlphaForTest: CGFloat? {
        guard usesNativeGlass, case .nativeSelection(let selector) = knob else { return nil }
        return selector.layer?.backgroundColor?.alpha
    }
    var nativeSelectorBorderWidthForTest: CGFloat? {
        guard usesNativeGlass, case .nativeSelection(let selector) = knob else { return nil }
        return selector.layer?.borderWidth
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
    /// Click and release motion runs on Core Animation's compositor. Direct
    /// dragging still updates real geometry one-to-one with pointer events.
    private var settleCompletionWorkItem: DispatchWorkItem?
    private var settleGeneration = 0
    private var settleStartFrame: NSRect?
    private var activeSettleMotion: SettleMotion?
    private var activeSettleDuration: CFTimeInterval?

    /// Four points filters trackpad tap wobble without making a deliberate drag
    /// feel sticky. A drag that begins away from the knob moves relatively, so
    /// crossing this threshold never makes the capsule jump under the pointer.
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
            field.font = .systemFont(ofSize: 11, weight: .regular)
            field.alignment = .center
            field.isSelectable = false
            field.wantsLayer = true
            field.setAccessibilityElement(false)
            trackContent.addSubview(field)
            labels.append(field)

            let active = NSTextField(labelWithString: mode.title)
            active.font = .systemFont(ofSize: 11, weight: .semibold)
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
        settleCompletionWorkItem?.cancel()
        if let displayOptionsObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(displayOptionsObserver)
        }
    }

    // MARK: - Keyboard and accessibility

    private func configureAccessibility() {
        setAccessibilityElement(true)
        setAccessibilityRole(.slider)
        setAccessibilityLabel("Power Mode")
        setAccessibilityOrientation(.horizontal)
        setAccessibilityMinValue(NSNumber(value: 0))
        setAccessibilityMaxValue(NSNumber(value: max(modes.count - 1, 0)))
        // This compact popover already exposes the selected label in the
        // current semantic accent.
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

    /// Builds the GitHub Mobile-style hierarchy: one neutral system glass track
    /// and one subtle selected capsule. The capsule is not a second glass view,
    /// so the track stays clear instead of being sampled twice. Older systems
    /// retain the lightweight translucent fallback with identical interaction.
    private func installMaterials() {
        materialRoot.wantsLayer = true
        trackView.wantsLayer = true
        trackContent.wantsLayer = true
        knobHost.wantsLayer = true

        let forceLegacy = ProcessInfo.processInfo.environment["WATTSON_FORCE_LEGACY_KNOB"] == "1"
        let radius = (Self.preferredHeight - 4) / 2

        if !forceLegacy, #available(macOS 26.0, *) {
            addSubview(materialRoot)
            usesNativeGlass = true

            let base = NSGlassEffectView(frame: .zero)
            configureGlass(base, style: .regular,
                           cornerRadius: Self.preferredHeight / 2,
                           tint: nil, content: trackContent)
            trackView.addSubview(base)
            trackGlass = base

            let selector = NSView(frame: .zero)
            selector.wantsLayer = true
            selector.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.10).cgColor
            selector.layer?.borderWidth = 0
            selector.layer?.cornerRadius = radius
            selector.layer?.cornerCurve = .continuous
            selector.layer?.allowsEdgeAntialiasing = true
            knobHost.addSubview(selector)
            knob = .nativeSelection(selector)
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
        // Let native Liquid Glass draw its own exterior edge and elevation.
        // Only the plain fallback needs clipping for its painted background.
        trackView.layer?.masksToBounds = !usesNativeGlass
        knobHost.layer?.backgroundColor = NSColor.clear.cgColor
        knobHost.layer?.cornerRadius = (Self.preferredHeight - 4) / 2
        knobHost.layer?.cornerCurve = .continuous

        if !usesNativeGlass {
            trackView.layer?.backgroundColor = PopoverStyle.well.cgColor
            trackView.layer?.borderWidth = 0.5
            trackView.layer?.borderColor = PopoverStyle.wellBorder.withAlphaComponent(0.78).cgColor
        }

        // Native Liquid Glass supplies the shared surface edge and elevation.
        // The older-system fallback keeps one inexpensive selector shadow.
        guard !usesNativeGlass else { return }
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

    /// GitHub Mobile keeps the bar chrome neutral and puts semantic colour on
    /// the selected foreground. Preserve that hierarchy in the fallback too.
    private func applyTrackTint(_: NSColor) {
        guard !usesNativeGlass else { return }
        trackView.layer?.borderColor = PopoverStyle.wellBorder.withAlphaComponent(
            Self.reducesTransparency ? 0.92 : 0.78
        ).cgColor
    }

    /// Core Animation would otherwise derive the shadow from the glass alpha on
    /// every frame. A fixed bounds-relative path stays cheap while the host is
    /// moved and scaled by the compositor.
    private func updateShadowPath() {
        guard !usesNativeGlass else { return }
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
        if !dragging, activeSettleMotion == nil {
            knobHost.frame = knobFrame(at: selectedIndex)
        }
        knob?.view.frame = knobHost.bounds
        updateShadowPath()
        if activeSettleMotion == nil {
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
        // A telemetry refresh can arrive while the pointer is held. Reapply
        // the interaction material so it cannot flatten the lifted capsule.
        knob?.setLifted(movedWhileDragging)
        // During a held drag the 1 Hz telemetry refresh must recolour the mode
        // under the capsule, not jump the highlight back to the committed mode.
        let visualIndex = dragging && highlighted >= 0 ? highlighted : selectedIndex
        highlight(visualIndex, force: true)
        updateAccessibilityValue(announce: false)

        if !dragging, pendingSelectionIndex == nil, selectedIndex != previous {
            settle(to: selectedIndex, animated: true)
        }
    }

    /// Clicks flow toward the next detent with a small overshoot and pull-back;
    /// a released drag uses a faster critically damped capture. Both motions
    /// share one compositor timeline with the label crossfade.
    private func settle(to index: Int, animated: Bool, initialVelocityX: CGFloat = 0,
                        motion: SettleMotion = .magnetic) {
        let target = knobFrame(at: index)
        let start = visibleKnobFrame()
        stopSettleMotion()
        PopoverStyle.setWithoutAnimation {
            self.knobHost.layer?.transform = CATransform3DIdentity
        }
        setKnobFrame(start)
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
            let frames = path.keyTimes.enumerated().map { offset, time in
                let phase = CGFloat(truncating: time)
                let centre = path.centres[offset]
                let scale = self.magneticScale(at: phase,
                                               start: CGSize(width: start.width / target.width,
                                                             height: start.height / target.height))
                return NSRect(x: centre - target.width * scale.width / 2,
                              y: (self.bounds.height - target.height * scale.height) / 2,
                              width: target.width * scale.width,
                              height: target.height * scale.height)
            }
            startSettleMotion(kind: .magnetic, duration: path.duration,
                              frames: frames, keyTimes: path.keyTimes) {
                self.setKnobGeometry(centreX: target.midX,
                                     width: target.width,
                                     height: target.height)
            }

        case .spring:
            // The pointer already established direction and intent. Release
            // should therefore capture promptly instead of replaying a long
            // decorative spring after direct manipulation has ended.
            let duration: CFTimeInterval = 0.24
            let impulse = min(max(initialVelocityX * 0.012, -12), 12)
            let phases = (0...24).map { CGFloat($0) / 24 }
            let frames = phases.map { phase -> NSRect in
                let progress = self.springProgress(phase)
                let velocityCarry = impulse * phase * (1 - phase) * exp(-5 * phase)
                let centre = phase >= 1
                    ? target.midX
                    : start.midX + (target.midX - start.midX) * progress + velocityCarry
                let width = start.width + (target.width - start.width) * progress
                let height = start.height + (target.height - start.height) * progress
                return NSRect(x: centre - width / 2,
                              y: (self.bounds.height - height) / 2,
                              width: width, height: height)
            }
            let keyTimes = phases.map { NSNumber(value: Double($0)) }
            startSettleMotion(kind: .spring, duration: duration,
                              frames: frames, keyTimes: keyTimes) {
                self.setKnobGeometry(centreX: target.midX,
                                     width: target.width,
                                     height: target.height)
            }
        }
    }

    private func magneticDuration(for travel: CGFloat) -> CFTimeInterval {
        let detentDistance = min(abs(travel) / max(segmentWidth, 1), 2)
        return 0.18 + 0.06 * Double(detentDistance)
    }

    private struct MagneticMotion {
        let centres: [CGFloat]
        let keyTimes: [NSNumber]
        let duration: CFTimeInterval
    }

    /// Samples one shared magnetic trajectory for both the capsule position and
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
                return target + overshoot * smoothstep(progress)
            }
            let progress = (phase - 0.82) / 0.18
            return target + overshoot * (1 - smoothstep(progress))
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
                    centreOverrides.append((crossing, detent))
                    phases.append(crossing)
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

    /// Click motion stays within the resting footprint: it streamlines while
    /// travelling, compresses slightly at capture, then returns to one detent.
    private func magneticScale(at phase: CGFloat, start: CGSize) -> CGSize {
        let times: [CGFloat] = [0, 0.18, 0.56, 0.82, 1]
        let widths: [CGFloat] = [start.width, 1, 1, 0.98, 1]
        let heights: [CGFloat] = [start.height, 0.98, 0.92, 0.96, 1]
        for index in 1..<times.count where phase <= times[index] {
            let progress = (phase - times[index - 1])
                / max(times[index] - times[index - 1], 0.0001)
            let eased = progress * progress * (3 - 2 * progress)
            return CGSize(
                width: widths[index - 1] + (widths[index] - widths[index - 1]) * eased,
                height: heights[index - 1] + (heights[index] - heights[index - 1]) * eased
            )
        }
        return CGSize(width: 1, height: 1)
    }

    /// Normalized critically damped response. It has a decisive pull toward
    /// the detent without the loose oscillation that made release feel rubbery.
    private func springProgress(_ phase: CGFloat) -> CGFloat {
        let clamped = min(max(phase, 0), 1)
        let x = 9 * clamped
        let raw = 1 - (1 + x) * exp(-x)
        let end = 1 - 10 * exp(CGFloat(-9))
        return min(max(raw / end, 0), 1)
    }

    private func startSettleMotion(kind: SettleMotion, duration: CFTimeInterval,
                                   frames: [NSRect], keyTimes: [NSNumber],
                                   completion: @escaping () -> Void) {
        guard frames.count >= 2, frames.count == keyTimes.count,
              let start = frames.first, let target = frames.last,
              let layer = knobHost.layer else {
            if let target = frames.last { setKnobFrame(target) }
            completion()
            return
        }

        stopSettleMotion()
        activeSettleMotion = kind
        activeSettleDuration = duration
        settleStartFrame = start
        settleGeneration += 1
        let generation = settleGeneration

        let anchorPoint = layer.anchorPoint
        let positions = frames.map {
            NSValue(point: NSPoint(
                x: $0.minX + $0.width * anchorPoint.x,
                y: $0.minY + $0.height * anchorPoint.y
            ))
        }
        let transforms = frames.map {
            NSValue(caTransform3D: CATransform3DMakeScale(
                $0.width / max(target.width, 1),
                $0.height / max(target.height, 1),
                1
            ))
        }
        let labelWeights = frames.map { labelBlendWeights(at: $0.midX) }
#if DEBUG
        labelBlendTraceForTest.append(contentsOf: labelWeights)
#endif

        let position = CAKeyframeAnimation(keyPath: "position")
        position.values = positions
        position.keyTimes = keyTimes
        position.duration = duration
        position.calculationMode = .linear

        let transform = CAKeyframeAnimation(keyPath: "transform")
        transform.values = transforms
        transform.keyTimes = keyTimes
        transform.duration = duration
        transform.calculationMode = .linear

        let group = CAAnimationGroup()
        group.animations = [position, transform]
        group.duration = duration
        group.timingFunction = CAMediaTimingFunction(name: .linear)

        let beginTime = CACurrentMediaTime()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Model writes and every explicit animation commit atomically. This
        // prevents the final target from becoming visible for one display frame
        // before the first keyframe reaches the render server.
        setKnobFrame(target)
        group.beginTime = layer.convertTime(beginTime, from: nil)
        layer.add(group, forKey: "wattson.settle.geometry")

        for index in activeLabels.indices {
            guard let activeLayer = activeLabels[index].layer,
                  let baseLayer = labels[index].layer else { continue }
            let active = CAKeyframeAnimation(keyPath: "opacity")
            active.values = labelWeights.map { NSNumber(value: Double($0[index])) }
            active.keyTimes = keyTimes
            active.duration = duration
            active.beginTime = activeLayer.convertTime(beginTime, from: nil)
            active.calculationMode = .linear
            activeLayer.add(active, forKey: "wattson.settle.opacity")

            let base = CAKeyframeAnimation(keyPath: "opacity")
            base.values = labelWeights.map { NSNumber(value: Double(1 - $0[index])) }
            base.keyTimes = keyTimes
            base.duration = duration
            base.beginTime = baseLayer.convertTime(beginTime, from: nil)
            base.calculationMode = .linear
            baseLayer.add(base, forKey: "wattson.settle.opacity")
        }
        CATransaction.commit()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.settleGeneration == generation else { return }
            self.removeSettleAnimations()
            self.settleCompletionWorkItem = nil
            self.settleStartFrame = nil
            self.activeSettleMotion = nil
            self.activeSettleDuration = nil
            completion()
        }
        settleCompletionWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
    }

    private func stopSettleMotion() {
        settleGeneration += 1
        settleCompletionWorkItem?.cancel()
        settleCompletionWorkItem = nil
        removeSettleAnimations()
        settleStartFrame = nil
        activeSettleMotion = nil
        activeSettleDuration = nil
    }

    private func removeSettleAnimations() {
        knobHost.layer?.removeAnimation(forKey: "wattson.settle.geometry")
        for label in labels + activeLabels {
            label.layer?.removeAnimation(forKey: "wattson.settle.opacity")
        }
    }

    private func visibleKnobFrame() -> NSRect {
        if activeSettleMotion != nil {
            if let presentation = knobHost.layer?.presentation() {
                // `frame` is undefined for transformed layers. Our settle uses
                // scale plus position only, so derive the visible rectangle
                // explicitly from presentation values.
                let width = presentation.bounds.width * abs(presentation.transform.m11)
                let height = presentation.bounds.height * abs(presentation.transform.m22)
                return NSRect(
                    x: presentation.position.x - width * presentation.anchorPoint.x,
                    y: presentation.position.y - height * presentation.anchorPoint.y,
                    width: width,
                    height: height
                )
            }
            if let settleStartFrame { return settleStartFrame }
        }
        return knobHost.frame
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
    /// the capsule centre: a detent is fully bright at its centre and two adjacent
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
                self.labels[index].layer?.opacity = Float(1 - weight)
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
        // the helper disappears). Always lower the capsule back onto the last
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

    /// Core Animation keeps the target in the model layer. Re-grabbing first
    /// captures the visible presentation frame, then removes only our named
    /// settle animations and resumes direct manipulation from that exact point.
    private func interruptSettleAtVisibleGeometry() -> CGFloat {
        let visibleFrame = visibleKnobFrame()
        stopSettleMotion()
        PopoverStyle.setWithoutAnimation {
            self.knobHost.layer?.transform = CATransform3DIdentity
        }
        setKnobFrame(visibleFrame)
        return visibleFrame.midX
    }

    private func moveKnob(centreX: CGFloat, scaleX: CGFloat, scaleY: CGFloat) {
        let base = knobFrame(at: selectedIndex)
        setKnobGeometry(centreX: centreX,
                        width: base.width * scaleX,
                        height: base.height * scaleY)
    }

    /// The dragged capsule may extend beyond the base, but its centre stops exactly
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
        if !dragging, activeSettleMotion == nil {
            applyLabelBlend(at: knobHost.frame.midX)
        }
    }
}
