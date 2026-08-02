import AppKit

final class PopoverController: NSObject, NSPopoverDelegate {
    private let popover = NSPopover()
    private let content = PopoverContentViewController()
    private var visibilityHandler: ((Bool) -> Void)?

    /// `.transient` only dismisses for events this process sees. Wattson is an
    /// accessory app that never activates, so a click on the desktop or another
    /// app never reaches it and the popover just stayed open. A global monitor
    /// is the only way to hear those clicks.
    private var outsideClickMonitor: Any?

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

    func setModeSelectHandler(_ handler: @escaping (EnergyMode) -> Bool) {
        content.setModeSelectHandler(handler)
    }

    func setSystemBatteryIconToggleHandler(_ handler: @escaping (Bool) -> Bool) {
        content.setSystemBatteryIconToggleHandler(handler)
    }

    func updateSystemBatteryIconState(_ hidden: Bool?) {
        content.updateSystemBatteryIconState(hidden)
    }

    func toggle(relativeTo button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
            content.setAnimationsEnabled(true)
            EnergyModeController.refreshFromHelper()
            startWatchingForOutsideClicks()
            visibilityHandler?(true)
        }
    }

    func onVisibilityChange(_ handler: @escaping (Bool) -> Void) {
        visibilityHandler = handler
    }

    func popoverDidClose(_ notification: Notification) {
        stopWatchingForOutsideClicks()
        content.setAnimationsEnabled(false)
        visibilityHandler?(false)
    }

    private func startWatchingForOutsideClicks() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            guard let self, self.popover.isShown else { return }
            self.popover.performClose(nil)
        }
    }

    private func stopWatchingForOutsideClicks() {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
    }
}
