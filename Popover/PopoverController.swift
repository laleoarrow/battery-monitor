import AppKit

/// Shell only. Plan 2 fills this with the flow modules.
final class PopoverController {
    private let popover = NSPopover()
    private var visibilityHandler: ((Bool) -> Void)?

    init() {
        let content = NSViewController()
        content.view = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 200))
        popover.contentViewController = content
        popover.contentSize = NSSize(width: 360, height: 200)
        popover.behavior = .transient
        popover.animates = true
    }

    var isShown: Bool { popover.isShown }

    func toggle(relativeTo button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
            visibilityHandler?(false)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
            visibilityHandler?(true)
        }
    }

    func onVisibilityChange(_ handler: @escaping (Bool) -> Void) {
        visibilityHandler = handler
    }
}
