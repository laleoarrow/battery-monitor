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
        guard index != hoveredIndex else { return }
        hoveredIndex = index
        guard let index else { setVisible(false); return }
        PopoverStyle.setWithoutAnimation {
            self.glow.path = self.path(for: self.regions[index])
            self.glow.shadowPath = self.glow.path
        }
        setVisible(true)
    }

    private func path(for region: Region) -> CGPath {
        let rect = region.rect.insetBy(dx: 0.5, dy: 0.5)
        return CGPath(roundedRect: rect, cornerWidth: rect.height / 2,
                      cornerHeight: rect.height / 2, transform: nil)
    }

    @objc func cancelHover() {
        hoveredIndex = nil
        glow.removeAllAnimations()
        PopoverStyle.setWithoutAnimation { self.glow.opacity = 0 }
    }

    private func setVisible(_ visible: Bool) {
        let target: Float = visible ? 1 : 0
        let start = glow.presentation()?.opacity ?? glow.opacity
        glow.removeAnimation(forKey: "hover")
        PopoverStyle.setWithoutAnimation { self.glow.opacity = target }
        guard !reducesMotion, !reducesTransparency, start != target else { return }
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
            self.glow.fillColor = neutral.withAlphaComponent(contrast ? 0.08 : 0.055).cgColor
            self.glow.strokeColor = neutral.withAlphaComponent(contrast ? 0.6 : 0.16).cgColor
            self.glow.lineWidth = contrast ? 1 : 0.6
            self.glow.shadowColor = neutral.cgColor
            self.glow.shadowOpacity = contrast || self.reducesTransparency ? 0 : 0.28
            self.glow.shadowRadius = 4
            self.glow.shadowOffset = .zero
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
#endif
}
