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

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    @available(macOS 26.0, *)
    init(content: NSView, frame: NSRect, style: NSGlassEffectView.Style) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
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
        let glass = NSGlassEffectView(frame: contentView!.bounds.insetBy(dx: inset, dy: inset))
        glass.autoresizingMask = [.width, .height]
        glass.style = style
        glass.cornerRadius = 26
        let background = GlassBackgroundView(frame: glass.frame, cornerRadius: glass.cornerRadius)
        background.autoresizingMask = [.width, .height]
        contentView!.addSubview(background)
        contentView!.addSubview(glass)
        // An ancestor glass effect flattens the footer's SwiftUI glass into
        // solid fills. Keep the backdrop and interactive content as siblings.
        content.frame = glass.frame
        content.autoresizingMask = [.width, .height]
        contentView!.addSubview(content)
        hostedContent = content
    }

    @available(macOS 26.0, *)
    func detachContent() {
        hostedContent?.removeFromSuperview()
        hostedContent = nil
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
