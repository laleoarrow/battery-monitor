import AppKit

final class PopoverController: NSObject, NSPopoverDelegate {
    private static let entranceAnimationKey = "wattson.popover.entrance"
    private let popover = NSPopover()
#if DEBUG
    fileprivate var popoverForTest: NSPopover { popover }
#endif
    private let content = PopoverContentViewController()
    private var visibilityHandler: ((Bool) -> Void)?

    /// `.transient` only dismisses for events this process sees. Wattson is an
    /// accessory app that never activates, so a click on the desktop or another
    /// app never reaches it and the popover just stayed open. A global monitor
    /// is the only way to hear those clicks.
    private var outsideClickMonitor: Any?

    /// Exposed so the watch can be asserted rather than assumed. AppKit's own
    /// event delivery cannot be driven from a test, but everything on this side
    /// of it can.
    var isWatchingOutsideClicks: Bool { outsideClickMonitor != nil }

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

    /// What the user last asked for, which is not the same as what AppKit is
    /// currently drawing: `popover.isShown` stays true for the whole ~530ms
    /// close animation. Branching on it meant a click that reopened the popover
    /// mid-fade was read as "still open, close it again" and was swallowed, so
    /// reopening quickly took three clicks.
    private var wantsOpen = false

    /// Which show a `popoverDidClose` belongs to. AppKit pairs one close with
    /// each show, so a close that arrives while a later show is outstanding is
    /// the tail of a dismissal the user has already superseded by reopening.
    /// Counting is exact; the state at that instant is not — `popover.isShown`
    /// is briefly false in the ~7ms between the old popover going away and the
    /// new one landing, which is long enough to tear down a live popover.
    private var showsRequested = 0
    private var closesObserved = 0

    var isOpen: Bool { wantsOpen }

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
        wantsOpen ? close() : open(relativeTo: button)
    }

    private func open(relativeTo button: NSStatusBarButton) {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.animates = !reduceMotion
        let reopeningDuringDismissal = popover.isShown
        // Showing while a previous close is still animating is fine — AppKit
        // takes over the fade rather than dropping the request.
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
        guard popover.isShown else { return }   // never leave a monitor behind
        // Replaying from a fixed low opacity while AppKit is reversing a close
        // would flash. Let the in-flight presentation continue instead.
        if !reopeningDuringDismissal {
            playEntranceAnimation(reduceMotion: reduceMotion)
        }
        showsRequested += 1
        wantsOpen = true
        content.setAnimationsEnabled(true)
        LoginItemController.refresh()
        EnergyModeController.refreshFromHelper { [weak self] refreshed in
            guard refreshed, self?.wantsOpen == true else { return }
            self?.content.refreshEnergyModeState()
        }
        startWatchingForOutsideClicks()
        visibilityHandler?(true)
    }

    private func close() {
        wantsOpen = false
        stopWatchingForOutsideClicks()
        popover.performClose(nil)
    }

    func onVisibilityChange(_ handler: @escaping (Bool) -> Void) {
        visibilityHandler = handler
    }

    func popoverDidClose(_ notification: Notification) {
        closesObserved += 1
        // A close that finishes after the user has already reopened must not
        // tear down the popover it no longer owns.
        guard closesObserved >= showsRequested else { return }
        // Resetting the intent here is what covers AppKit dismissing the
        // popover on its own (Escape, a click elsewhere in the app) without
        // going through `close()`. Leaving it set would make the next click
        // read as "close" and be swallowed.
        wantsOpen = false
        stopWatchingForOutsideClicks()
        content.setAnimationsEnabled(false)
        stopEntranceAnimation()
        visibilityHandler?(false)
    }

    /// Adds a small compositor-only accent to AppKit's native popover reveal.
    /// A stable key replaces interrupted reveals instead of queueing work, and
    /// Reduce Motion keeps only the short cross-fade. No timer or display link
    /// survives the one-shot animation.
    private func playEntranceAnimation(reduceMotion: Bool) {
        guard let layer = content.view.layer else { return }
        layer.removeAnimation(forKey: Self.entranceAnimationKey)

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = reduceMotion ? 0.65 : 0.25
        fade.toValue = 1.0
        fade.duration = reduceMotion ? 0.12 : 0.18
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)

        let animation = CAAnimationGroup()
        if reduceMotion {
            animation.animations = [fade]
            animation.duration = fade.duration
        } else {
            var start = CATransform3DMakeTranslation(0, 7, 0)
            start = CATransform3DScale(start, 0.985, 0.985, 1)

            let settle = CABasicAnimation(keyPath: "transform")
            settle.fromValue = NSValue(caTransform3D: start)
            settle.toValue = NSValue(caTransform3D: CATransform3DIdentity)
            settle.duration = 0.24
            settle.timingFunction = CAMediaTimingFunction(
                controlPoints: 0.22, 1.0, 0.36, 1.0
            )

            animation.animations = [fade, settle]
            animation.duration = settle.duration
        }
        animation.isRemovedOnCompletion = true
        layer.add(animation, forKey: Self.entranceAnimationKey)
    }

    private func stopEntranceAnimation() {
        content.view.layer?.removeAnimation(forKey: Self.entranceAnimationKey)
    }

    private func startWatchingForOutsideClicks() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            self?.handleOutsideClick()
        }
    }

    /// What the global monitor calls. Separated so a test can invoke it.
    func handleOutsideClick() {
        guard wantsOpen else { return }
        close()
    }

    private func stopWatchingForOutsideClicks() {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
    }
}

#if DEBUG
extension PopoverController {
    func playEntranceAnimationForTest(reduceMotion: Bool) {
        playEntranceAnimation(reduceMotion: reduceMotion)
    }

    func stopEntranceAnimationForTest() { stopEntranceAnimation() }

    var entranceAnimationCountForTest: Int {
        content.view.layer?.animationKeys()?.filter { $0 == Self.entranceAnimationKey }.count ?? 0
    }

    var entranceAnimationForTest: CAAnimation? {
        content.view.layer?.animation(forKey: Self.entranceAnimationKey)
    }

    /// What AppKit is drawing, as opposed to `isOpen`, which is what the user
    /// asked for. They differ for the length of the close animation.
    var isShownForTest: Bool { popoverForTest.isShown }
    /// Dismissal that does not go through `close()`, the way Escape and a click
    /// elsewhere in the app reach a transient popover.
    func closeBypassingControllerForTest() { popoverForTest.performClose(nil) }

    /// Running animations across the whole content layer tree. A hidden popover
    /// that keeps animating is invisible on screen and expensive on battery,
    /// which is the entire reason `setAnimationsEnabled(false)` exists.
    var contentWindowForTest: NSWindow? { popoverForTest.contentViewController?.view.window }
    var contentViewForTest: NSView? { popoverForTest.contentViewController?.view }

    var runningAnimationCountForTest: Int {
        func count(_ layer: CALayer) -> Int {
            (layer.animationKeys()?.count ?? 0) + (layer.sublayers ?? []).reduce(0) { $0 + count($1) }
        }
        guard let view = popoverForTest.contentViewController?.view, let root = view.layer else { return 0 }
        return count(root)
    }
}
#endif
