import AppKit

/// A user-controlled backing fill beneath foreground content. Content stays in
/// the window at full opacity; no private material layers are edited.
final class GlassBackgroundView: NSView {
    private var settingsObserver: NSObjectProtocol?
    private var displayObserver: NSObjectProtocol?

    static var accessibilityRequiresSolidBackground: Bool {
        var reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        var contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
#if DEBUG
        if let value = ProcessInfo.processInfo.environment["WATTSON_FORCE_REDUCE_TRANSPARENCY"] {
            reduce = value == "1"
        }
        if let value = ProcessInfo.processInfo.environment["WATTSON_FORCE_INCREASE_CONTRAST"] {
            contrast = value == "1"
        }
#endif
        return reduce || contrast
    }

    static let fillColor = NSColor(name: nil) { _ in
        let opacity = accessibilityRequiresSolidBackground ? 1 : 1 - Settings.liquidGlassTransparency
        return opacity == 0 ? .clear : NSColor.windowBackgroundColor.withAlphaComponent(opacity)
    }

    init(frame: NSRect = .zero, cornerRadius: CGFloat) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        setAccessibilityElement(false)
        settingsObserver = NotificationCenter.default.addObserver(
            forName: Settings.didChange, object: nil, queue: .main
        ) { [weak self] notification in
            if notification.userInfo?[Settings.changeUserInfoKey] as? Settings.Change == .liquidGlassTransparency {
                self?.needsDisplay = true
            }
        }
        displayObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.needsDisplay = true }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    deinit {
        if let settingsObserver { NotificationCenter.default.removeObserver(settingsObserver) }
        if let displayObserver { NSWorkspace.shared.notificationCenter.removeObserver(displayObserver) }
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = Self.fillColor.cgColor
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
