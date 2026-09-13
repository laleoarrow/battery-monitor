import AppKit

/// The glass host replaces NSPopover; it is never a second backdrop inside it.
/// The empty optical margin prevents the native glass edge being window-clipped.
final class GlassPopoverPanel: NSPanel {
    static let contentInset: CGFloat = 10
    var onDismiss: (() -> Void)?
    var onEscape: (() -> Void)?

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
        let glass = NSGlassEffectView(frame: contentView!.bounds.insetBy(
            dx: Self.contentInset, dy: Self.contentInset))
        glass.autoresizingMask = [.width, .height]
        glass.style = style
        glass.cornerRadius = 26
        glass.contentView = content
        contentView!.addSubview(glass)
    }

    @available(macOS 26.0, *)
    func detachContent() {
        (contentView?.subviews.first as? NSGlassEffectView)?.contentView = nil
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
