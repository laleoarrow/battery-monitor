import AppKit

/// The glass host replaces NSPopover; it is never a second backdrop inside it.
/// The empty optical margin prevents the native glass edge being window-clipped.
final class GlassPopoverPanel: NSPanel {
    static func contentInset(for style: Settings.LiquidGlassStyle) -> CGFloat {
        // Regular's native optical shadow extends past 20pt on macOS 26.6.1.
        // Keep Clear's existing window-shadow geometry independent.
        style == .regular ? 32 : 10
    }

    static var contentInset: CGFloat { contentInset(for: Settings.liquidGlassStyle) }
    var onDismiss: (() -> Void)?
    var onEscape: (() -> Void)?
    private weak var hostedContent: NSView?
    private var foreground: NSView?
    private var background: GlassBackgroundView?
    private var material: NSView?
    private var anchorX: CGFloat?
    private(set) var showsArrow: Bool

    @available(macOS 26.0, *)
    var materialView: GlassPopoverMaterialView? { material as? GlassPopoverMaterialView }

    var bodyFrame: NSRect { foreground?.frame ?? .zero }

    @available(macOS 26.0, *)
    var arrowTip: NSPoint {
        guard let glass = materialView else { return .zero }
        return NSPoint(x: glass.frame.minX + glass.arrowX, y: glass.frame.maxY)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    @available(macOS 26.0, *)
    init(content: NSView, frame: NSRect, style: NSGlassEffectView.Style, showsArrow: Bool = true,
         appearance: NSAppearance? = nil) {
        self.showsArrow = showsArrow
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        self.appearance = appearance
        // AppKit expands a half-point origin during initialization. Use the
        // same sizing path as later placement before laying out the content.
        setFrame(frame, display: false)
        title = "Wattson Power Monitor"
        isOpaque = false
        backgroundColor = .clear
        // The native Regular material already has its own edge treatment.
        // A window shadow around the larger optical margin adds a second box.
        hasShadow = style == .clear
        isReleasedWhenClosed = false
        isRestorable = false
        hidesOnDeactivate = false
        level = .popUpMenu
        collectionBehavior = [.transient, .moveToActiveSpace, .fullScreenAuxiliary]
        let inset = Self.contentInset(for: style == .clear ? .clear : .regular)
        let glass = GlassPopoverMaterialView(frame: contentView!.bounds.insetBy(dx: inset, dy: inset),
                                            style: style, showsArrow: showsArrow)
        glass.autoresizingMask = [.width, .height]
        // SwiftUI glass alone leaves zero-alpha pixels that WindowServer clicks
        // through. One 8-bit alpha step keeps the shaped surface interactive;
        // the optical margin remains fully transparent.
        let background = GlassBackgroundView(frame: glass.frame, cornerRadius: 0, minimumOpacity: 1.0 / 255)
        background.autoresizingMask = [.width, .height]
        contentView!.addSubview(background)
        contentView!.addSubview(glass)
        // An ancestor glass effect flattens the footer's SwiftUI glass into
        // solid fills. Keep the backdrop and interactive content as siblings.
        var bodyFrame = glass.frame
        bodyFrame.size.height -= showsArrow ? PopoverPlacement.glassArrowHeight : 0
        let foreground = NSView(frame: bodyFrame)
        foreground.setAccessibilityElement(false)
        foreground.autoresizingMask = [.width, .height]
        foreground.wantsLayer = true
        foreground.layer?.cornerRadius = GlassPopoverShape.cornerRadius
        foreground.layer?.masksToBounds = true
        // Scroll layers and the animated content stay inside the body, while
        // the sibling material keeps its arrow and external optical margin.
        content.frame = foreground.bounds
        content.autoresizingMask = [.width, .height]
        if content.window == nil {
            // Inherit the destination appearance without a windowless parent.
            contentView!.addSubview(foreground)
            foreground.addSubview(content)
        } else {
            // Preserve the existing detach transition for live content.
            foreground.addSubview(content)
            contentView!.addSubview(foreground)
        }
        hostedContent = content
        self.foreground = foreground
        self.background = background
        material = glass
        updateOutline()
    }

    /// Keep the arrow tied to its actual menu-bar anchor after screen clamping.
    @available(macOS 26.0, *)
    func point(to screenX: CGFloat) {
        anchorX = screenX
        updateOutline()
    }

    @available(macOS 26.0, *)
    func setShowsArrow(_ value: Bool) {
        guard showsArrow != value, let glass = materialView else { return }
        showsArrow = value
        glass.setShowsArrow(value)
        var bodyFrame = glass.frame
        bodyFrame.size.height -= value ? PopoverPlacement.glassArrowHeight : 0
        foreground?.frame = bodyFrame
        updateOutline()
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        if #available(macOS 26.0, *) { updateOutline() }
    }

    @available(macOS 26.0, *)
    private func updateOutline() {
        guard let glass = materialView, let background else { return }
        glass.point(to: (anchorX ?? frame.midX) - frame.minX - glass.frame.minX)
        let mask = (background.layer?.mask as? CAShapeLayer) ?? CAShapeLayer()
        mask.frame = background.bounds
        mask.path = GlassPopoverShape(arrowX: glass.arrowX, showsArrow: showsArrow).appKitPath(in: background.bounds)
        background.layer?.mask = mask
    }

    @available(macOS 26.0, *)
    func detachContent() {
        hostedContent?.removeFromSuperview()
        hostedContent = nil
        foreground?.removeFromSuperview()
        foreground = nil
    }

    /// A process-wide event monitor must not steal Escape from another Wattson
    /// window, including an alert that became key without an outside click.
    func ownsEscapeEvent(eventWindow: NSWindow?, keyWindow: NSWindow?) -> Bool {
        if let eventWindow { return eventWindow === self }
        return keyWindow === self
    }

    override func cancelOperation(_ sender: Any?) { onEscape?() }

    override func close() {
        super.close()
        onDismiss?()
    }
}
