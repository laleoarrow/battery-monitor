import AppKit

/// A Control Center style track with a draggable Liquid Glass knob that snaps
/// to the nearest detent.
///
/// A segmented control was correct but inert. This reads as a physical object:
/// the knob follows the pointer one-to-one while dragging, then springs to the
/// nearest position on release rather than jumping.
final class ModeSliderView: NSView {
    static let preferredHeight: CGFloat = 30

    private let trackView = NSView()
    private let knobHost = NSView()
    /// Which knob was actually built. Liquid Glass takes a tintColor; a plain
    /// NSView does not, and sending it one raises NSUnknownKeyException. Making
    /// the difference a type stops the call site from having to remember.
    private enum Knob {
        case glass(NSView)
        case plain(NSView)

        var view: NSView {
            switch self {
            case .glass(let view): return view
            case .plain(let view): return view
            }
        }

        func applyTint(_ tint: NSColor) {
            switch self {
            case .glass(let view):
                view.setValue(tint.withAlphaComponent(0.55), forKey: "tintColor")
            case .plain(let view):
                view.layer?.borderColor = tint.withAlphaComponent(0.5).cgColor
            }
        }
    }

    private var knob: Knob?
    private var labels: [NSTextField] = []

    private var modes: [EnergyMode] = []
    private var enabled: [Bool] = []
    private var selectedIndex = 0

#if DEBUG
    /// Relabelling is the expensive part of a drag. It must happen once per
    /// detent crossed, not once per mouse event.
    private(set) var highlightCallCountForTest = 0
    var knobCentreForTest: CGFloat { knobHost.frame.midX }
    var settleIsAnimatingForTest: Bool { knobHost.layer?.animation(forKey: "settle") != nil }
    var selectedIndexForTest: Int { selectedIndex }
    var detentCentreForTest: (Int) -> CGFloat { { self.knobFrame(at: $0).midX } }
#endif

    private var dragging = false
    private var grabOffset: CGFloat = 0
    private var highlighted = -1
    /// Where the press landed, so a click can select the detent under the
    /// pointer. Reading the knob's position instead meant a click that never
    /// moved the knob resolved to the mode already selected, and did nothing.
    private var pressX: CGFloat = 0
    private var movedWhileDragging = false

    /// A tap is never perfectly still. Below this the gesture is a click on a
    /// detent, not a drag of the knob.
    private static let dragSlop: CGFloat = 3

    /// Returns true when the change was accepted; a refusal springs back.
    var onSelect: ((EnergyMode) -> Bool)?

    override var isFlipped: Bool { true }

    init(modes: [EnergyMode]) {
        self.modes = modes
        super.init(frame: NSRect(x: 0, y: 0, width: PopoverStyle.contentWidth, height: Self.preferredHeight))
        wantsLayer = true

        // A real subview, not a bare sublayer on the backing layer: subviews
        // have a defined draw order against the knob and the labels.
        trackView.wantsLayer = true
        trackView.layer?.backgroundColor = PopoverStyle.well.cgColor
        trackView.layer?.cornerRadius = Self.preferredHeight / 2
        trackView.layer?.cornerCurve = .continuous
        addSubview(trackView)

        knobHost.wantsLayer = true
        knobHost.layer?.cornerRadius = (Self.preferredHeight - 4) / 2
        knobHost.layer?.cornerCurve = .continuous
        knobHost.layer?.borderWidth = 0.5
        knobHost.layer?.shadowColor = NSColor.black.cgColor
        knobHost.layer?.shadowOpacity = 0.35
        knobHost.layer?.shadowRadius = 4
        knobHost.layer?.shadowOffset = CGSize(width: 0, height: 1)
        addSubview(knobHost)
        installKnob()

        for mode in modes {
            let field = NSTextField(labelWithString: mode.title)
            field.font = .systemFont(ofSize: 11, weight: .medium)
            field.alignment = .center
            field.isSelectable = false
            addSubview(field)
            labels.append(field)
        }
        enabled = Array(repeating: true, count: modes.count)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// macOS 26 ships the real material. Older systems get a plain translucent
    /// pill rather than a hand-rolled imitation of glass.
    private func installKnob() {
        let radius = (Self.preferredHeight - 4) / 2
        // Without this the pre-26 branch is unreachable on a macOS 26 machine,
        // so it would only ever be exercised on someone else's Mac.
        let forceLegacy = ProcessInfo.processInfo.environment["WATTSON_FORCE_LEGACY_KNOB"] == "1"
        if !forceLegacy, let glassClass = NSClassFromString("NSGlassEffectView") as? NSView.Type {
            let view = glassClass.init(frame: .zero)
            view.setValue(NSNumber(value: Double(radius)), forKey: "cornerRadius")
            // Liquid Glass renders nothing without content to refract.
            let content = NSView()
            content.wantsLayer = true
            content.layer?.backgroundColor = NSColor(white: 1, alpha: 0.10).cgColor
            view.setValue(content, forKey: "contentView")
            knobHost.addSubview(view)
            knob = .glass(view)
        } else {
            let view = NSView(frame: .zero)
            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor(white: 1, alpha: 0.18).cgColor
            view.layer?.borderColor = NSColor(white: 1, alpha: 0.22).cgColor
            view.layer?.borderWidth = 0.5
            view.layer?.cornerRadius = radius
            view.layer?.cornerCurve = .continuous
            knobHost.addSubview(view)
            knob = .plain(view)
        }
    }

    /// Core Animation derives a shadow from the layer's alpha channel every
    /// frame unless it is given an explicit path. With Liquid Glass sampling the
    /// backdrop on top of that, dragging crawled.
    private func updateShadowPath() {
        let radius = knobHost.layer?.cornerRadius ?? 0
        knobHost.layer?.shadowPath = CGPath(roundedRect: knobHost.bounds,
                                            cornerWidth: radius, cornerHeight: radius,
                                            transform: nil)
    }

    // MARK: - Geometry

    private var segmentWidth: CGFloat { bounds.width / CGFloat(max(modes.count, 1)) }

    private func knobFrame(at index: Int) -> NSRect {
        NSRect(x: 2 + CGFloat(index) * segmentWidth, y: 2,
               width: segmentWidth - 4, height: bounds.height - 4)
    }

    override func layout() {
        super.layout()
        PopoverStyle.setWithoutAnimation {
            self.trackView.frame = self.bounds
        }
        for (index, field) in labels.enumerated() {
            field.frame = NSRect(x: CGFloat(index) * segmentWidth, y: (bounds.height - 15) / 2,
                                 width: segmentWidth, height: 15)
        }
        if !dragging {
            knobHost.frame = knobFrame(at: selectedIndex)
        }
        knob?.view.frame = knobHost.bounds
        updateShadowPath()
    }

    // MARK: - State

    func update(selected: EnergyMode, enabledModes: [EnergyMode], tint: NSColor) {
        enabled = modes.map(enabledModes.contains)
        let previous = selectedIndex
        if let index = modes.firstIndex(of: selected) { selectedIndex = index }

        highlight(selectedIndex)
        knob?.applyTint(tint)
        knobHost.layer?.backgroundColor = NSColor(white: 0.97, alpha: 0.95).cgColor
        knobHost.layer?.borderColor = tint.withAlphaComponent(0.35).cgColor
        // Only spring when the position actually changed. This runs at 1 Hz
        // with the rest of the popover, and re-adding the animation every
        // second left the knob permanently twitching.
        if !dragging, selectedIndex != previous {
            settle(to: selectedIndex, animated: true)
        }
    }

    /// A spring rather than a linear move — the knob arrives with a little
    /// weight instead of sliding to a dead stop.
    private func settle(to index: Int, animated: Bool) {
        let target = knobFrame(at: index)
        guard animated else {
            knobHost.frame = target
            knob?.view.frame = knobHost.bounds
            return
        }
        let spring = CASpringAnimation(keyPath: "position")
        spring.damping = 22
        spring.stiffness = 320
        spring.mass = 1
        spring.initialVelocity = 0
        spring.duration = spring.settlingDuration
        spring.fromValue = knobHost.layer?.presentation()?.position ?? knobHost.layer?.position as Any
        knobHost.frame = target
        knob?.view.frame = knobHost.bounds
        spring.toValue = knobHost.layer?.position
        knobHost.layer?.add(spring, forKey: "settle")
    }

    // MARK: - Clicks and drags

    /// The track, knob and labels are decoration; the control is one object.
    /// Hit-testing through to them leaked that structure into the event system:
    /// AppKit asks whichever view it hit whether it takes the first mouse, and
    /// a plain NSView says no. Dragging still worked because the event bubbled
    /// up the responder chain, which is exactly what made this hard to see.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let local = superview.map({ convert(point, from: $0) }) ?? nil else { return nil }
        return bounds.contains(local) ? self : nil
    }

    /// The popover belongs to an accessory app that never activates, so its
    /// window is never key and every click arrives as a first mouse. Without
    /// this the first click after opening is spent making the window key.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        dragging = true
        movedWhileDragging = false
        pressX = point.x
        grabOffset = knobHost.frame.contains(point) ? point.x - knobHost.frame.minX : knobHost.frame.width / 2
        knobHost.layer?.removeAnimation(forKey: "settle")
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragging else { return }
        let point = convert(event.locationInWindow, from: nil)
        // Hold still under the slop so a tap that wobbles a pixel stays a tap,
        // rather than nudging the knob and snapping back to where it started.
        guard movedWhileDragging || abs(point.x - pressX) >= Self.dragSlop else { return }
        movedWhileDragging = true
        let maxX = bounds.width - knobHost.frame.width - 2
        let x = min(max(point.x - grabOffset, 2), maxX)
        // Only the origin moves. The knob's own frame is in knobHost's
        // coordinate space and the shadow path is bounds-relative, so neither
        // needs touching per event.
        PopoverStyle.setWithoutAnimation {
            self.knobHost.frame.origin.x = x
        }
        let nearest = nearestIndex()
        if nearest != highlighted { highlight(nearest) }
    }

    override func mouseUp(with event: NSEvent) {
        guard dragging else { return }
        dragging = false
        let previous = selectedIndex
        // A drag snaps to the nearest usable detent. A click names one exact
        // detent; clicking a disabled mode is a no-op, not a request for its
        // nearest neighbour.
        let index: Int
        if movedWhileDragging {
            index = nearestIndex()
        } else {
            let pressedIndex = nearestDetentIndex(toward: pressX)
            guard enabled[pressedIndex] else {
                highlight(previous)
                return
            }
            index = pressedIndex
        }
        selectedIndex = index
        settle(to: index, animated: true)
        highlight(index)

        guard index != previous else { return }
        if onSelect?(modes[index]) != true {
            // Refused — spring back so the control never lies about the state.
            selectedIndex = previous
            settle(to: previous, animated: true)
            highlight(previous)
        }
    }

    private func nearestIndex() -> Int { nearestIndex(toward: knobHost.frame.midX) }

    private func nearestDetentIndex(toward x: CGFloat) -> Int {
        modes.indices.min {
            abs(knobFrame(at: $0).midX - x) < abs(knobFrame(at: $1).midX - x)
        } ?? selectedIndex
    }

    /// Skips disabled detents while dragging, so release always snaps to a
    /// usable mode. Clicks are handled separately above because a disabled
    /// detent must be a no-op rather than choosing a neighbour.
    private func nearestIndex(toward x: CGFloat) -> Int {
        let candidates = modes.indices.filter { enabled[$0] }
        guard !candidates.isEmpty else { return selectedIndex }
        return candidates.min {
            abs(knobFrame(at: $0).midX - x) < abs(knobFrame(at: $1).midX - x)
        } ?? selectedIndex
    }

    /// The knob is a light material, so the label riding on it has to go dark.
    /// Leaving it near-white made the active mode the one you could not read.
    private func highlight(_ index: Int) {
#if DEBUG
        highlightCallCountForTest += 1
#endif
        highlighted = index
        for (offset, field) in labels.enumerated() {
            field.textColor = !enabled[offset] ? PopoverStyle.tertiaryText
                : offset == index ? PopoverStyle.surface
                : PopoverStyle.secondaryText
        }
    }
}
