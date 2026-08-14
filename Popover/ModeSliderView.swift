import AppKit

/// Public Core Animation primitives provide a consistent optical edge for the
/// macOS 12–25 sampled-lens fallback. Native Liquid Glass draws its own edge.
private final class OpticalLensChromeView: NSView {
    private let causticLayer = CAGradientLayer()
    private let rimLayer = CAShapeLayer()
    private let innerEdgeLayer = CAShapeLayer()

    private(set) var rimWidth: CGFloat = 1

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.addSublayer(causticLayer)
        layer?.addSublayer(innerEdgeLayer)
        layer?.addSublayer(rimLayer)
        apply(reduceTransparency: false, lifted: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func apply(reduceTransparency: Bool, lifted: Bool) {
        rimWidth = reduceTransparency ? 1.5 : (lifted ? 1.15 : 0.9)
        layer?.backgroundColor = reduceTransparency
            ? NSColor(white: lifted ? 0.22 : 0.27, alpha: 1).cgColor
            : NSColor.clear.cgColor
        rimLayer.lineWidth = rimWidth
        rimLayer.strokeColor = NSColor.white.withAlphaComponent(
            reduceTransparency ? 0.58 : (lifted ? 0.52 : 0.36)
        ).cgColor
        innerEdgeLayer.lineWidth = reduceTransparency ? 0.75 : 0.55
        innerEdgeLayer.strokeColor = NSColor.black.withAlphaComponent(
            reduceTransparency ? 0.28 : 0.18
        ).cgColor
        causticLayer.isHidden = reduceTransparency
        causticLayer.colors = [
            NSColor.white.withAlphaComponent(lifted ? 0.30 : 0.18).cgColor,
            NSColor.white.withAlphaComponent(0.03).cgColor,
            NSColor.black.withAlphaComponent(lifted ? 0.07 : 0.04).cgColor,
            NSColor.white.withAlphaComponent(lifted ? 0.16 : 0.09).cgColor,
        ]
        causticLayer.locations = [0, 0.24, 0.70, 1]
        causticLayer.startPoint = CGPoint(x: 0.04, y: 0.02)
        causticLayer.endPoint = CGPoint(x: 0.96, y: 0.98)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let radius = bounds.height / 2
        layer?.cornerRadius = radius
        layer?.cornerCurve = .continuous
        causticLayer.frame = bounds
        let outer = bounds.insetBy(dx: rimWidth / 2, dy: rimWidth / 2)
        rimLayer.fillColor = NSColor.clear.cgColor
        rimLayer.path = CGPath(roundedRect: outer,
                               cornerWidth: max(radius - rimWidth / 2, 0),
                               cornerHeight: max(radius - rimWidth / 2, 0),
                               transform: nil)
        let inner = bounds.insetBy(dx: 1.7, dy: 1.7)
        innerEdgeLayer.fillColor = NSColor.clear.cgColor
        innerEdgeLayer.path = CGPath(roundedRect: inner,
                                     cornerWidth: max(radius - 1.7, 0),
                                     cornerHeight: max(radius - 1.7, 0),
                                     transform: nil)
    }
}

/// macOS 12–25 fallback. A cached AppKit rendering of the real track content
/// is cropped and magnified inside the moving capsule. Drag events only adjust
/// `contentsRect`; they do not ask AppKit to render a new bitmap every frame.
private final class LegacyOpticalLensView: NSView {
    private let sampleLayer = CALayer()
    private let chromeView = OpticalLensChromeView(frame: .zero)
    private var hostFrameInTrack = NSRect.zero
    private var trackBounds = NSRect.zero
    private var lifted = false
    private var reduceTransparency = false

    private(set) var sampleImage: CGImage?
    private(set) var sampleRect = CGRect.zero
    private(set) var magnification: CGFloat = 1.018
    var rimWidth: CGFloat { chromeView.rimWidth }
    var samplingEnabled: Bool { lifted && !reduceTransparency && sampleImage != nil }

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        sampleLayer.contentsGravity = .resize
        sampleLayer.magnificationFilter = .linear
        sampleLayer.minificationFilter = .trilinear
        // The cached material replaces the underlying track pixels inside the
        // lens. Foreground labels stay above the lens, so an opaque sample is
        // what prevents the base glyph plus refracted glyph plus active glyph
        // from becoming unreadable triple text.
        sampleLayer.opacity = 1
        layer?.addSublayer(sampleLayer)
        addSubview(chromeView)
        applyMaterial(reduceTransparency: false, lifted: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func install(sample image: CGImage) {
        sampleImage = image
        sampleLayer.contents = image
        sampleLayer.contentsScale = window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 2
        updateSamplingRect()
    }

    func applyMaterial(reduceTransparency: Bool, lifted: Bool) {
        self.reduceTransparency = reduceTransparency
        self.lifted = lifted
        layer?.backgroundColor = reduceTransparency
            ? NSColor(white: lifted ? 0.22 : 0.27, alpha: 1).cgColor
            : NSColor.white.withAlphaComponent(lifted ? 0.075 : 0.105).cgColor
        sampleLayer.isHidden = !samplingEnabled
        chromeView.apply(reduceTransparency: reduceTransparency, lifted: lifted)
        updateSamplingRect()
    }

    func update(hostFrameInTrack: NSRect, trackBounds: NSRect) {
        self.hostFrameInTrack = hostFrameInTrack
        self.trackBounds = trackBounds
        updateSamplingRect()
    }

    private func updateSamplingRect() {
        guard trackBounds.width > 0, trackBounds.height > 0 else { return }
        magnification = samplingEnabled ? 1.105 : 1
        guard samplingEnabled else {
            sampleRect = .zero
            sampleLayer.contentsRect = .zero
            return
        }

        let sourceWidth = min(hostFrameInTrack.width / magnification, trackBounds.width)
        let sourceHeight = min(trackBounds.height / magnification, trackBounds.height)
        let distanceFromMiddle = (hostFrameInTrack.midX - trackBounds.midX)
            / max(trackBounds.width / 2, 1)
        // A small inward prism displacement plus magnification is much more
        // legible than blur alone, while staying restrained at the end detents.
        let sourceCentreX = hostFrameInTrack.midX - distanceFromMiddle * 1.4
        let sourceMinX = min(
            max(sourceCentreX - sourceWidth / 2, trackBounds.minX),
            trackBounds.maxX - sourceWidth
        )
        let sourceMinY = trackBounds.midY - sourceHeight / 2
        sampleRect = CGRect(
            x: (sourceMinX - trackBounds.minX) / trackBounds.width,
            y: (sourceMinY - trackBounds.minY) / trackBounds.height,
            width: sourceWidth / trackBounds.width,
            height: sourceHeight / trackBounds.height
        )
        sampleLayer.contentsRect = sampleRect
    }

    override func layout() {
        super.layout()
        let radius = bounds.height / 2
        layer?.cornerRadius = radius
        layer?.cornerCurve = .continuous
        sampleLayer.frame = bounds
        chromeView.frame = bounds
        chromeView.layoutSubtreeIfNeeded()
    }
}

/// A horizontally locked mode bar. Native systems use a clear Liquid Glass
/// selector above the regular glass track; older systems move a sampled optical
/// lens over the same content so the lifted drag state visibly refracts it.
final class ModeSliderView: NSView {
    static let preferredHeight: CGFloat = 30

    @available(macOS 14.0, *)
    private final class NativeGlassDisplayLinkTarget: NSObject {
        weak var owner: ModeSliderView?

        @objc func displayLinkDidFire(_ displayLink: CADisplayLink) {
            owner?.nativeGlassDisplayLinkDidFire(displayLink)
        }
    }

    private static var systemReducesMotion: Bool {
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
        switch ProcessInfo.processInfo.environment["WATTSON_FORCE_REDUCE_TRANSPARENCY"] {
        case "1": return true
        case "0": return false
        default: break
        }
#endif
        return NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }

    private let materialRoot = NSView()
    private let materialContent = NSView()
    private let trackView = NSView()
    private let trackContent = NSView()
    private let knobHost = NSView()

    private var trackGlass: NSView?
    private var nativeGlassContainer: NSView?
    private var fallbackLens: LegacyOpticalLensView?
    private var usesNativeGlass = false
    private let forceLegacyMaterials: Bool
    private var opticalSnapshotDirty = true
    private var opticalSnapshotCaptureCount = 0
    private var opticalSnapshotSize = NSSize.zero

    /// Both cases are true optical surfaces. The native selector delegates
    /// refraction to AppKit; the fallback selector samples the real track once
    /// and moves a cheap crop through that cached image.
    private enum Knob {
        case nativeSelection(NSView)
        case plain(NSView)

        var view: NSView {
            switch self {
            case .nativeSelection(let view): return view
            case .plain(let view): return view
            }
        }

        private static func applyNativeSurface(_ view: NSView, lifted: Bool) {
            let reduceTransparency = ModeSliderView.reducesTransparency
            let fill = reduceTransparency
                ? NSColor(white: lifted ? 0.22 : 0.27, alpha: 1)
                : NSColor.clear
            view.alphaValue = reduceTransparency
                ? 1
                : (lifted ? ModeSliderView.nativeActiveGlassOpacity
                          : ModeSliderView.nativeRestingGlassOpacity)
            view.layer?.backgroundColor = fill.cgColor
            view.layer?.borderWidth = 0
            if #available(macOS 26.0, *),
               let glass = view as? NSGlassEffectView,
               let content = glass.contentView {
                content.wantsLayer = true
                content.layer?.backgroundColor = fill.cgColor
                content.layer?.borderWidth = 0
            }
        }

        func applyTint(_: NSColor) {
            switch self {
            case .nativeSelection(let view):
                Self.applyNativeSurface(view, lifted: false)
            case .plain(let view):
                let reduceTransparency = ModeSliderView.reducesTransparency
                if let lens = view as? LegacyOpticalLensView {
                    lens.applyMaterial(reduceTransparency: reduceTransparency, lifted: false)
                }
            }
        }

        func setLifted(_ lifted: Bool, reduceMotion: Bool) {
            let lifted = lifted && !reduceMotion
            switch self {
            case .nativeSelection(let view):
                Self.applyNativeSurface(view, lifted: lifted)
            case .plain(let view):
                let reduceTransparency = ModeSliderView.reducesTransparency
                if let lens = view as? LegacyOpticalLensView {
                    lens.applyMaterial(reduceTransparency: reduceTransparency, lifted: lifted)
                }
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
    private var reducesMotion = false

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
    var settleStartCentreForTest: CGFloat? { settleStartFrame?.midX }
    var focusRingTypeForTest: NSFocusRingType { focusRingType }
    var restingKnobWidthForTest: CGFloat { knobFrame(at: selectedIndex).width }
    var segmentWidthForTest: CGFloat { segmentWidth }
    var knobCornerRadiusForTest: CGFloat { knobHost.layer?.cornerRadius ?? 0 }
    var selectorCornerRadiusForTest: CGFloat { knob?.view.layer?.cornerRadius ?? 0 }
    var selectedIndexForTest: Int { selectedIndex }
    var selectionIsPendingForTest: Bool { pendingSelectionIndex != nil }
    var reducesMotionForTest: Bool { reducesMotion }
    var fallbackSelectorOpacityForTest: CGFloat? {
        guard case .plain(let selector) = knob else { return nil }
        return selector.layer?.backgroundColor?.alpha
    }
    var fallbackLensSampleImageForTest: CGImage? { fallbackLens?.sampleImage }
    var fallbackLensSampleRectForTest: CGRect? { fallbackLens?.sampleRect }
    var fallbackLensRimWidthForTest: CGFloat? { fallbackLens?.rimWidth }
    var fallbackLensMagnificationForTest: CGFloat? { fallbackLens?.magnification }
    var fallbackLensSamplingEnabledForTest: Bool? { fallbackLens?.samplingEnabled }
    var fallbackLensCaptureCountForTest: Int { opticalSnapshotCaptureCount }
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
    var nativeSelectorOpacityForTest: CGFloat? {
        guard usesNativeGlass, case .nativeSelection(let selector) = knob else { return nil }
        return selector.alphaValue
    }
    var nativeSelectorStyleForTest: Int? {
        guard #available(macOS 26.0, *), usesNativeGlass,
              case .nativeSelection(let selector) = knob,
              let glass = selector as? NSGlassEffectView else { return nil }
        return glass.style.rawValue
    }
    var nativeGlassContainerSpacingForTest: CGFloat? {
        guard #available(macOS 26.0, *), usesNativeGlass,
              let container = nativeGlassContainer as? NSGlassEffectContainerView else { return nil }
        return container.spacing
    }
    var nativeSelectorIsInsideContainerForTest: Bool? {
        guard #available(macOS 26.0, *), usesNativeGlass,
              let container = nativeGlassContainer as? NSGlassEffectContainerView,
              case .nativeSelection(let selector) = knob,
              let content = container.contentView else { return nil }
        var ancestor = selector.superview
        while let current = ancestor {
            if current === content { return true }
            ancestor = current.superview
        }
        return false
    }
    var nativeSelectorContentFillAlphaForTest: CGFloat? {
        guard #available(macOS 26.0, *), usesNativeGlass,
              case .nativeSelection(let selector) = knob,
              let glass = selector as? NSGlassEffectView else { return nil }
        return glass.contentView?.layer?.backgroundColor?.alpha
    }
    var nativeSelectorHasCustomChromeForTest: Bool {
        guard #available(macOS 26.0, *), usesNativeGlass,
              case .nativeSelection(let selector) = knob,
              let glass = selector as? NSGlassEffectView else { return false }
        return glass.contentView is OpticalLensChromeView
    }
    var nativeSettleUsesHostLayerAnimationForTest: Bool {
        knobHost.layer?.animation(forKey: "wattson.settle.geometry") != nil
    }
    var nativeSelectorFrameInSliderForTest: NSRect? {
        guard usesNativeGlass, case .nativeSelection(let selector) = knob else { return nil }
        return selector.convert(selector.bounds, to: self)
    }
    func applyReduceMotionChangeForTest(_ reduceMotion: Bool) {
        refreshDisplayOptions(reduceMotion: reduceMotion)
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
    /// Older-system click motion runs on Core Animation's compositor. Native
    /// glass uses display-linked real view geometry so AppKit's material and
    /// the selector boundary cannot advance on different timelines.
    private var settleCompletionWorkItem: DispatchWorkItem?
    private var settleGeneration = 0
    private var settleStartFrame: NSRect?
    private var activeSettleMotion: SettleMotion?
    private var activeSettleDuration: CFTimeInterval?
    private var nativeSettleDisplayLink: AnyObject?
    private var nativeSettleDisplayLinkTarget: AnyObject?
    private var nativeSettleFrames: [NSRect] = []
    private var nativeSettleKeyTimes: [CGFloat] = []
    private var nativeSettleStartedAt: CFTimeInterval = 0
    private var nativeSettleGeneration = 0

    /// Four points filters trackpad tap wobble without making a deliberate drag
    /// feel sticky. A drag that begins away from the knob moves relatively, so
    /// crossing this threshold never makes the capsule jump under the pointer.
    private static let dragSlop: CGFloat = 4
    private static let nativeRestingGlassOpacity: CGFloat = 0.045
    private static let nativeActiveGlassOpacity: CGFloat = 0.14

    private enum SettleMotion: Equatable {
        case magnetic
        case spring
    }

    /// Completion is asynchronous so helper wake-up, `pmset`, and readback never
    /// hold AppKit's event loop while the release spring is trying to render.
    var onSelect: ((EnergyMode, @escaping (EnergyMode?) -> Void) -> Void)?

    override var isFlipped: Bool { true }

    convenience init(modes: [EnergyMode]) {
        self.init(
            modes: modes,
            forceLegacyMaterials:
                ProcessInfo.processInfo.environment["WATTSON_FORCE_LEGACY_KNOB"] == "1"
        )
    }

#if DEBUG
    convenience init(modes: [EnergyMode], forceLegacyMaterialsForTest: Bool) {
        self.init(modes: modes, forceLegacyMaterials: forceLegacyMaterialsForTest)
    }
#endif

    private init(modes: [EnergyMode], forceLegacyMaterials: Bool) {
        self.modes = modes
        self.forceLegacyMaterials = forceLegacyMaterials
        self.reducesMotion = Self.systemReducesMotion
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
        invalidateNativeGlassDisplayLink()
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

    /// Builds two equivalent optical hierarchies. macOS 26 batches a regular
    /// track and clear moving lens in one native glass container. macOS 12–25
    /// uses a sampled lens with the same geometry and interaction semantics.
    private func installMaterials() {
        materialRoot.wantsLayer = true
        materialContent.wantsLayer = true
        trackView.wantsLayer = true
        trackContent.wantsLayer = true
        knobHost.wantsLayer = true

        let radius = Self.preferredHeight / 2
        addSubview(materialRoot)

        if !forceLegacyMaterials, #available(macOS 26.0, *) {
            usesNativeGlass = true

            let container = NSGlassEffectContainerView(frame: .zero)
            container.spacing = 0
            container.contentView = materialContent
            materialRoot.addSubview(container)
            nativeGlassContainer = container

            let base = NSGlassEffectView(frame: .zero)
            configureGlass(base, style: .regular,
                           cornerRadius: Self.preferredHeight / 2,
                           tint: nil, content: trackContent)
            trackView.addSubview(base)
            trackGlass = base

            let selector = NSGlassEffectView(frame: .zero)
            let content = NSView(frame: .zero)
            content.wantsLayer = true
            content.layer?.backgroundColor = NSColor.clear.cgColor
            configureGlass(selector, style: .clear,
                           cornerRadius: radius,
                           tint: nil, content: content)
            selector.wantsLayer = true
            selector.layer?.backgroundColor = NSColor.clear.cgColor
            selector.layer?.borderWidth = 0
            selector.layer?.cornerRadius = radius
            selector.layer?.cornerCurve = .continuous
            selector.layer?.allowsEdgeAntialiasing = true
            knobHost.addSubview(selector)
            knob = .nativeSelection(selector)
        } else {
            materialRoot.addSubview(materialContent)
            trackView.addSubview(trackContent)

            let selector = LegacyOpticalLensView(frame: .zero)
            selector.layer?.cornerRadius = radius
            selector.layer?.cornerCurve = .continuous
            knobHost.addSubview(selector)
            fallbackLens = selector
            knob = .plain(selector)
        }

        materialContent.addSubview(trackView)
        materialContent.addSubview(knobHost)
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
        knobHost.layer?.cornerRadius = Self.preferredHeight / 2
        knobHost.layer?.cornerCurve = .continuous

        if !usesNativeGlass {
            trackView.layer?.backgroundColor = PopoverStyle.well.cgColor
            trackView.layer?.borderWidth = 0.5
            trackView.layer?.borderColor = PopoverStyle.wellBorder.withAlphaComponent(0.78).cgColor
        }

        // Native Liquid Glass supplies the surface elevation. The older-system
        // lens uses one fixed-path shadow, avoiding per-frame offscreen shadow
        // analysis while its cached contentsRect moves.
        guard !usesNativeGlass else { return }
        knobHost.layer?.shadowColor = NSColor.black.cgColor
        knobHost.layer?.shadowOpacity = 0.28
        knobHost.layer?.shadowRadius = 5
        knobHost.layer?.shadowOffset = CGSize(width: 0, height: 2)
    }

    private func refreshDisplayOptions() {
        refreshDisplayOptions(reduceMotion: Self.systemReducesMotion)
    }

    private func refreshDisplayOptions(reduceMotion: Bool) {
        reducesMotion = reduceMotion
        if reduceMotion, activeSettleMotion != nil {
            stopSettleMotion()
            PopoverStyle.setWithoutAnimation {
                self.knobHost.layer?.transform = CATransform3DIdentity
            }
            setKnobFrame(knobFrame(at: selectedIndex))
        } else if reduceMotion, dragging, movedWhileDragging {
            let draggedCentre = visibleKnobFrame().midX
            let restingFrame = knobFrame(at: selectedIndex)
            setKnobGeometry(centreX: draggedCentre,
                            width: restingFrame.width,
                            height: restingFrame.height)
        }
        applyTrackTint(currentTint)
        knob?.applyTint(currentTint)
        knob?.setLifted(
            (dragging && movedWhileDragging)
                || (usesNativeGlass && activeSettleMotion != nil),
            reduceMotion: reducesMotion
        )
        if highlighted >= 0 { highlight(highlighted, force: true) }
        invalidateOpticalSnapshot()
        needsLayout = true
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
        let lifted = dragging && movedWhileDragging && !reducesMotion
        let radius = knobHost.bounds.height / 2
        knobHost.layer?.cornerRadius = radius
        knobHost.layer?.shadowOpacity = Self.reducesTransparency
            ? 0.34
            : (lifted ? 0.38 : 0.28)
        knobHost.layer?.shadowRadius = lifted ? 8 : 5
        knobHost.layer?.shadowOffset = CGSize(width: 0, height: lifted ? 3 : 2)
        knobHost.layer?.shadowPath = CGPath(roundedRect: knobHost.bounds,
                                            cornerWidth: radius,
                                            cornerHeight: radius,
                                            transform: nil)
    }

    private func invalidateOpticalSnapshot() {
        guard fallbackLens != nil else { return }
        opticalSnapshotDirty = true
    }

    /// The fallback takes a real AppKit snapshot of the track, including its
    /// material and edge rendering. Labels are deliberately excluded: the
    /// sampled opaque material masks the underlying base glyph, while the sharp
    /// active foreground copy remains above the lens. This produces refraction
    /// around text without stacking multiple distorted copies of each word.
    private func captureOpticalSnapshotIfNeeded() {
        guard let fallbackLens,
              !Self.reducesTransparency,
              opticalSnapshotDirty,
              trackView.bounds.width > 1,
              trackView.bounds.height > 1 else { return }

        let priorOpacities = labels.map { $0.layer?.opacity ?? 1 }
        PopoverStyle.setWithoutAnimation {
            for label in self.labels { label.layer?.opacity = 0 }
        }
        defer {
            PopoverStyle.setWithoutAnimation {
                for (index, opacity) in priorOpacities.enumerated() {
                    self.labels[index].layer?.opacity = opacity
                }
            }
        }

        guard let bitmap = trackView.bitmapImageRepForCachingDisplay(in: trackView.bounds) else {
            return
        }
        trackView.cacheDisplay(in: trackView.bounds, to: bitmap)
        guard let image = bitmap.cgImage else { return }
        fallbackLens.install(sample: image)
        opticalSnapshotCaptureCount += 1
        opticalSnapshotSize = trackView.bounds.size
        opticalSnapshotDirty = false
    }

    // MARK: - Geometry

    private var segmentWidth: CGFloat { bounds.width / CGFloat(max(modes.count, 1)) }

    private func knobFrame(at index: Int) -> NSRect {
        let width = segmentWidth
        let centre = (CGFloat(index) + 0.5) * segmentWidth
        return NSRect(x: centre - width / 2, y: 0,
                      width: width, height: bounds.height)
    }

    override func layout() {
        super.layout()
        if opticalSnapshotSize != bounds.size { invalidateOpticalSnapshot() }
        PopoverStyle.setWithoutAnimation {
            self.materialRoot.frame = self.bounds
            self.nativeGlassContainer?.frame = self.materialRoot.bounds
            self.materialContent.frame = self.materialRoot.bounds
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
        if #available(macOS 26.0, *),
           case .nativeSelection(let selector) = knob,
           let glass = selector as? NSGlassEffectView {
            glass.cornerRadius = knobHost.bounds.height / 2
            glass.layer?.cornerRadius = knobHost.bounds.height / 2
            glass.contentView?.frame = glass.bounds
        }
        fallbackLens?.update(hostFrameInTrack: knobHost.frame, trackBounds: bounds)
        updateShadowPath()
        if activeSettleMotion == nil {
            applyLabelBlend(at: knobHost.frame.midX)
        }
        captureOpticalSnapshotIfNeeded()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        invalidateOpticalSnapshot()
        needsLayout = true
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        invalidateOpticalSnapshot()
        needsLayout = true
    }

    // MARK: - State

    /// The footer arbitrates requests shared by the glass and reduced-motion
    /// controls. Its presentation must supersede any older completion retained
    /// by this standalone control.
    func updateFromOwner(selected: EnergyMode, enabledModes: [EnergyMode], tint: NSColor) {
        if pendingSelectionIndex != nil {
            selectionGeneration += 1
            pendingSelectionIndex = nil
        }
        update(selected: selected, enabledModes: enabledModes, tint: tint)
    }

    func update(selected: EnergyMode, enabledModes: [EnergyMode], tint: NSColor) {
        let previousEnabled = enabled
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
        knob?.setLifted(
            (dragging && movedWhileDragging)
                || (usesNativeGlass && activeSettleMotion != nil),
            reduceMotion: reducesMotion
        )
        // During a held drag the 1 Hz telemetry refresh must recolour the mode
        // under the capsule, not jump the highlight back to the committed mode.
        let visualIndex = dragging && highlighted >= 0 ? highlighted : selectedIndex
        highlight(visualIndex, force: true)
        updateAccessibilityValue(announce: false)
        if enabled != previousEnabled {
            invalidateOpticalSnapshot()
            captureOpticalSnapshotIfNeeded()
        }

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
        knob?.setLifted(false, reduceMotion: reducesMotion)

        let reduceMotion = reducesMotion
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

        if usesNativeGlass, #available(macOS 26.0, *) {
            knob?.setLifted(true, reduceMotion: false)
            startNativeGlassSettleMotion(
                duration: duration,
                frames: frames,
                keyTimes: keyTimes,
                generation: generation,
                completion: completion
            )
            return
        }

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

    @available(macOS 14.0, *)
    private func startNativeGlassSettleMotion(
        duration: CFTimeInterval,
        frames: [NSRect],
        keyTimes: [NSNumber],
        generation: Int,
        completion: @escaping () -> Void
    ) {
        nativeSettleFrames = frames
        nativeSettleKeyTimes = keyTimes.map { CGFloat(truncating: $0) }
        nativeSettleStartedAt = CACurrentMediaTime()
        nativeSettleGeneration = generation
        setKnobFrame(frames[0])

        let target = NativeGlassDisplayLinkTarget()
        target.owner = self
        guard let window else {
            setKnobFrame(frames[frames.count - 1])
            knob?.setLifted(false, reduceMotion: reducesMotion)
            invalidateNativeGlassDisplayLink()
            settleStartFrame = nil
            activeSettleMotion = nil
            activeSettleDuration = nil
            completion()
            return
        }
        let displayLink = window.displayLink(
            target: target,
            selector: #selector(NativeGlassDisplayLinkTarget.displayLinkDidFire(_:))
        )
        nativeSettleDisplayLinkTarget = target
        nativeSettleDisplayLink = displayLink
        displayLink.add(to: .main, forMode: .common)

        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  self.settleGeneration == generation,
                  self.nativeSettleGeneration == generation else { return }
            if let target = self.nativeSettleFrames.last {
                self.setKnobFrame(target)
            }
            self.knob?.setLifted(false, reduceMotion: self.reducesMotion)
            self.invalidateNativeGlassDisplayLink()
            self.settleCompletionWorkItem = nil
            self.settleStartFrame = nil
            self.activeSettleMotion = nil
            self.activeSettleDuration = nil
            completion()
        }
        settleCompletionWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
    }

    @available(macOS 14.0, *)
    fileprivate func nativeGlassDisplayLinkDidFire(_ displayLink: CADisplayLink) {
        guard nativeSettleGeneration == settleGeneration,
              nativeSettleDisplayLink === displayLink,
              activeSettleDuration != nil else { return }
        let duration = max(activeSettleDuration ?? 0, 0.0001)
        let phase = CGFloat(
            min(max((displayLink.timestamp - nativeSettleStartedAt) / duration, 0), 1)
        )
        setKnobFrame(nativeSettleFrame(at: phase))
        if phase >= 1 {
            knob?.setLifted(false, reduceMotion: reducesMotion)
            stopNativeGlassDisplayLink()
        }
    }

    private func nativeSettleFrame(at phase: CGFloat) -> NSRect {
        guard let first = nativeSettleFrames.first,
              let last = nativeSettleFrames.last,
              nativeSettleFrames.count == nativeSettleKeyTimes.count else {
            return knobHost.frame
        }
        if phase <= nativeSettleKeyTimes.first ?? 0 { return first }
        if phase >= nativeSettleKeyTimes.last ?? 1 { return last }

        for upper in 1..<nativeSettleKeyTimes.count where phase <= nativeSettleKeyTimes[upper] {
            let lower = upper - 1
            let span = max(nativeSettleKeyTimes[upper] - nativeSettleKeyTimes[lower], 0.0001)
            let progress = (phase - nativeSettleKeyTimes[lower]) / span
            let from = nativeSettleFrames[lower]
            let to = nativeSettleFrames[upper]
            return NSRect(
                x: from.minX + (to.minX - from.minX) * progress,
                y: from.minY + (to.minY - from.minY) * progress,
                width: from.width + (to.width - from.width) * progress,
                height: from.height + (to.height - from.height) * progress
            )
        }
        return last
    }

    private func stopNativeGlassDisplayLink() {
        if #available(macOS 14.0, *),
           let displayLink = nativeSettleDisplayLink as? CADisplayLink {
            displayLink.invalidate()
        }
        nativeSettleDisplayLink = nil
        nativeSettleDisplayLinkTarget = nil
    }

    private func invalidateNativeGlassDisplayLink() {
        stopNativeGlassDisplayLink()
        nativeSettleFrames.removeAll(keepingCapacity: true)
        nativeSettleKeyTimes.removeAll(keepingCapacity: true)
        nativeSettleStartedAt = 0
        nativeSettleGeneration = 0
    }

    private func stopSettleMotion() {
        settleGeneration += 1
        settleCompletionWorkItem?.cancel()
        settleCompletionWorkItem = nil
        invalidateNativeGlassDisplayLink()
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
        if usesNativeGlass { return knobHost.frame }
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
        let weights = labelBlendWeights(at: frame.midX)
#if DEBUG
        labelBlendTraceForTest.append(weights)
#endif
        PopoverStyle.setWithoutAnimation {
            self.knobHost.frame = frame
            self.knob?.view.frame = self.knobHost.bounds
            if #available(macOS 26.0, *),
               case .nativeSelection(let selector) = self.knob,
               let glass = selector as? NSGlassEffectView {
                glass.cornerRadius = self.knobHost.bounds.height / 2
                glass.layer?.cornerRadius = self.knobHost.bounds.height / 2
                glass.contentView?.frame = glass.bounds
            }
            self.fallbackLens?.update(hostFrameInTrack: frame, trackBounds: self.bounds)
            self.applyLabelBlend(weights)
        }
        updateShadowPath()
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

    private func applyLabelBlend(_ weights: [CGFloat]) {
        for index in activeLabels.indices {
            let weight = weights[index]
            activeLabels[index].layer?.opacity = Float(weight)
            labels[index].layer?.opacity = Float(1 - weight)
        }
    }

    private func applyLabelBlend(at centreX: CGFloat) {
        let weights = labelBlendWeights(at: centreX)
#if DEBUG
        labelBlendTraceForTest.append(weights)
#endif
        PopoverStyle.setWithoutAnimation {
            self.applyLabelBlend(weights)
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
            knob?.setLifted(true, reduceMotion: reducesMotion)
        }
        updateVelocity(pointerX: point.x, timestamp: event.timestamp)

        let rawCentre = grabbedKnob
            ? point.x - grabOffsetFromCentre
            : dragStartCentreX + (point.x - pressX)
        let centre = clampedCentre(rawCentre)
        let nearest = nearestIndex(toward: centre)
        moveKnob(centreX: centre)

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

    private func moveKnob(centreX: CGFloat) {
        let base = knobFrame(at: selectedIndex)
        setKnobGeometry(centreX: centreX,
                        width: base.width,
                        height: base.height)
    }

    /// The dragged capsule keeps its resting footprint while its centre stops
    /// exactly on the first and last slot like the reference control.
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
