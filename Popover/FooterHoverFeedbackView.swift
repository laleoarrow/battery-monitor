import AppKit

/// Pointer feedback above the footer's existing controls, without changing
/// their material, event handling, keyboard focus or accessibility hierarchy.
final class FooterHoverFeedbackView: NSView {
    struct Region: Equatable {
        let rect: NSRect
        let enabled: Bool
    }

    private var regions: [Region] = []
    private var hoveredIndex: Int?
    private var presentationActive = true
    private let glow = CAShapeLayer()
    private let reflection = CAGradientLayer()
    private let rimReflection = CAGradientLayer()
    private let reflectionMask = CAShapeLayer()
    private let rimMask = CAShapeLayer()

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityElement(false)
        setAccessibilityChildren([])
        glow.opacity = 0
        layer?.addSublayer(glow)
        for gradient in [reflection, rimReflection] {
            gradient.type = .radial
            gradient.locations = [0, 0.4, 1]
            glow.addSublayer(gradient)
        }
        reflectionMask.fillColor = NSColor.black.cgColor
        reflection.mask = reflectionMask
        rimMask.fillColor = NSColor.clear.cgColor
        rimMask.strokeColor = NSColor.black.cgColor
        rimMask.lineWidth = 1
        rimReflection.mask = rimMask
        addTrackingArea(NSTrackingArea(rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil))
        refreshAppearance()
        NotificationCenter.default.addObserver(self, selector: #selector(cancelHover),
            name: NSApplication.didResignActiveNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(accessibilityChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    func update(regions: [Region]) {
        guard self.regions != regions else { return }
        cancelHover()
        self.regions = regions
    }

    func setPresentationActive(_ active: Bool) {
        presentationActive = active
        if !active { cancelHover() }
    }

    override func mouseEntered(with event: NSEvent) { updateHover() }
    override func mouseExited(with event: NSEvent) { updateHover() }
    override func mouseMoved(with event: NSEvent) { updateHover() }

    private func updateHover() {
        guard presentationActive, !isHiddenOrHasHiddenAncestor, let window, window.isVisible else {
            cancelHover()
            return
        }
        let point: NSPoint
#if DEBUG
        point = pointerLocationForTest ?? convert(window.mouseLocationOutsideOfEventStream, from: nil)
#else
        point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
#endif
        guard visibleRect.contains(point) else {
            hoveredIndex = nil
            setVisible(false)
            return
        }
        let index = regions.indices.first { index in
            regions[index].enabled && !regions[index].rect.isEmpty && path(for: regions[index]).contains(point)
        }
        let changedRegion = index != hoveredIndex
        hoveredIndex = index
        guard let index else {
            if changedRegion { setVisible(false) }
            return
        }
        if changedRegion {
            PopoverStyle.setWithoutAnimation {
                self.glow.path = self.path(for: self.regions[index])
                for (gradient, mask) in [(self.reflection, self.reflectionMask), (self.rimReflection, self.rimMask)] {
                    gradient.frame = self.regions[index].rect
                    mask.frame = gradient.bounds
                    mask.path = self.path(for: Region(rect: gradient.bounds, enabled: true))
                }
            }
        }
        updateReflection(at: point, in: regions[index].rect, animated: !changedRegion)
        if changedRegion { setVisible(true) }
    }

    private var usesStaticFeedback: Bool {
        reducesMotion || reducesTransparency || PopoverStyle.isHighContrast(effectiveAppearance)
    }

    private func updateReflection(at point: NSPoint, in rect: NSRect, animated: Bool) {
        let center = CGPoint(x: min(0.92, max(0.08, (point.x - rect.minX) / rect.width)),
                             y: min(0.92, max(0.08, (point.y - rect.minY) / rect.height)))
        for gradient in [reflection, rimReflection] {
            gradient.isHidden = usesStaticFeedback
            if usesStaticFeedback { gradient.removeAllAnimations(); continue }
            let end = CGPoint(x: center.x + 0.65, y: center.y + 0.9)
            for (key, target) in [("startPoint", center), ("endPoint", end)] {
                let start = (gradient.presentation() ?? gradient).value(forKey: key) as? NSValue
                gradient.removeAnimation(forKey: key)
                PopoverStyle.setWithoutAnimation { gradient.setValue(NSValue(point: target), forKey: key) }
                if animated, start?.pointValue != target {
                    let animation = CABasicAnimation(keyPath: key)
                    animation.fromValue = start
                    animation.toValue = NSValue(point: target)
                    animation.duration = 0.08
                    animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    gradient.add(animation, forKey: key)
                }
            }
        }
    }

    private func path(for region: Region) -> CGPath {
        let rect = region.rect.insetBy(dx: 0.5, dy: 0.5)
        return CGPath(roundedRect: rect, cornerWidth: rect.height / 2,
                      cornerHeight: rect.height / 2, transform: nil)
    }

    @objc func cancelHover() {
        hoveredIndex = nil
        for item in [glow, reflection, rimReflection, reflectionMask, rimMask] { item.removeAllAnimations() }
        PopoverStyle.setWithoutAnimation { self.glow.opacity = 0 }
    }

    private func setVisible(_ visible: Bool) {
        let target: Float = visible ? 1 : 0
        let start = glow.presentation()?.opacity ?? glow.opacity
        glow.removeAnimation(forKey: "hover")
        PopoverStyle.setWithoutAnimation { self.glow.opacity = target }
        guard !usesStaticFeedback, start != target else { return }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = start
        animation.toValue = target
        animation.duration = visible ? 0.14 : 0.18
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        glow.add(animation, forKey: "hover")
    }

    private var reducesMotion: Bool {
#if DEBUG
        if let value = ProcessInfo.processInfo.environment["WATTSON_FORCE_REDUCE_MOTION"] { return value == "1" }
#endif
        return NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private var reducesTransparency: Bool {
#if DEBUG
        if let value = ProcessInfo.processInfo.environment["WATTSON_FORCE_REDUCE_TRANSPARENCY"] { return value == "1" }
#endif
        return NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }

    private func refreshAppearance() {
        let dark = PopoverStyle.isDark(effectiveAppearance)
        let contrast = PopoverStyle.isHighContrast(effectiveAppearance)
        let neutral = dark ? NSColor.white : NSColor.black
        PopoverStyle.setWithoutAnimation {
            self.glow.fillColor = neutral.withAlphaComponent(contrast ? 0.08 : (dark ? 0.025 : 0.018)).cgColor
            self.glow.strokeColor = neutral.withAlphaComponent(contrast ? 0.6 : (dark ? 0.12 : 0.10)).cgColor
            self.glow.lineWidth = contrast ? 1 : 0.6
            self.glow.shadowColor = neutral.cgColor
            self.glow.shadowOpacity = self.usesStaticFeedback ? 0 : (dark ? 0.18 : 0.12)
            self.glow.shadowRadius = 3
            self.glow.shadowOffset = .zero
            self.reflection.colors = [
                NSColor.white.withAlphaComponent(dark ? 0.065 : 0.045).cgColor,
                NSColor.white.withAlphaComponent(dark ? 0.018 : 0.012).cgColor,
                NSColor.white.withAlphaComponent(0).cgColor,
            ]
            self.rimReflection.colors = [
                NSColor.white.withAlphaComponent(dark ? 0.24 : 0.16).cgColor,
                NSColor.white.withAlphaComponent(dark ? 0.07 : 0.04).cgColor,
                NSColor.white.withAlphaComponent(0).cgColor,
            ]
            self.reflection.isHidden = self.usesStaticFeedback
            self.rimReflection.isHidden = self.usesStaticFeedback
        }
    }

    @objc private func accessibilityChanged() {
        cancelHover()
        refreshAppearance()
    }

    override func layout() {
        super.layout()
        PopoverStyle.setWithoutAnimation { self.glow.frame = self.bounds }
    }

    override func viewDidHide() {
        cancelHover()
        super.viewDidHide()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        cancelHover()
        refreshAppearance()
    }

    override func viewWillMove(toSuperview newSuperview: NSView?) {
        cancelHover()
        super.viewWillMove(toSuperview: newSuperview)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        cancelHover()
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: window)
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            NotificationCenter.default.addObserver(self, selector: #selector(cancelHover),
                name: NSWindow.didResignKeyNotification, object: window)
        }
    }

#if DEBUG
    var pointerLocationForTest: NSPoint?
    var regionsForTest: [Region] { regions }
    var hoveredIndexForTest: Int? { hoveredIndex }
    var glowForTest: CAShapeLayer { glow }
    var reflectionForTest: CAGradientLayer { reflection }
    var rimReflectionForTest: CAGradientLayer { rimReflection }
    var presentationReflectionCenterForTest: CGPoint { reflection.presentation()?.startPoint ?? reflection.startPoint }
#endif
}
