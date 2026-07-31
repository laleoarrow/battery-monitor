import AppKit

final class PopoverController: NSObject, NSPopoverDelegate {
    private let popover = NSPopover()
    private let content = PopoverContentViewController()
    private var visibilityHandler: ((Bool) -> Void)?

    override init() {
        super.init()
        popover.contentViewController = content
        popover.contentSize = NSSize(width: PopoverStyle.width, height: content.preferredHeight)
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        content.heightDidChange = { [weak self] height in
            self?.popover.contentSize = NSSize(width: PopoverStyle.width, height: height)
        }
    }

    var isShown: Bool { popover.isShown }

    func update(snapshot: PowerSnapshot, history: [Double], peak: Double, degraded: Bool) {
        content.update(snapshot: snapshot, history: history, peak: peak, degraded: degraded)
    }

    func setModeToggleHandler(_ handler: @escaping () -> Bool) {
        content.setModeToggleHandler(handler)
    }

    func toggle(relativeTo button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
            content.setAnimationsEnabled(true)
            visibilityHandler?(true)
        }
    }

    func onVisibilityChange(_ handler: @escaping (Bool) -> Void) {
        visibilityHandler = handler
    }

    func popoverDidClose(_ notification: Notification) {
        content.setAnimationsEnabled(false)
        visibilityHandler?(false)
    }
}
