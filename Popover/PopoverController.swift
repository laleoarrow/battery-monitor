import AppKit

final class PopoverController: NSObject, NSPopoverDelegate {
    private struct Presentation {
        let snapshot: PowerSnapshot
        let history: [Double]
        let peak: Double
        let degraded: Bool
    }

    private static let entranceAnimationKey = "wattson.popover.entrance"
    private static var reducesMotion: Bool {
#if DEBUG
        switch ProcessInfo.processInfo.environment["WATTSON_FORCE_REDUCE_MOTION"] {
        case "1": return true
        case "0": return false
        default: break
        }
#endif
        return NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private var popover = NSPopover()
#if DEBUG
    fileprivate var popoverForTest: NSPopover { popover }
#endif
    private let content = PopoverContentViewController()
    private var glassPanel: GlassPopoverPanel?
    private var usingGlassPanel = false
    private var presentationGeneration: UInt = 0
    private var visibilityHandler: ((Bool) -> Void)?
    private var settingsHandler: (() -> Void)?
    private var latestPresentation: Presentation?
    private var latestSystemBatteryIconHidden: Bool?
    private var latestSystemBatteryIconReadStatus: SystemBatteryIconReadStatus = .notRequested
    private var displayOptionsObserver: NSObjectProtocol?
    private var screenParametersObserver: NSObjectProtocol?
    private var appearanceObserver: NSObjectProtocol?
    private weak var anchorButton: NSStatusBarButton?
#if DEBUG
    private(set) var contentRenderCountForTest = 0
#endif

    /// Clicks in other processes do not reach the popup's native anchor window.
    /// The global monitor dismisses it for desktop and other-app clicks.
    private var outsideClickMonitor: Any?
    private var localEventMonitor: Any?
    private var localObservers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var trackingMenus: [NSMenu] = []
    private weak var observedAnchor: NSStatusBarButton?
    private var anchorPostedFrameChanges = false

    /// Exposed so the watch can be asserted rather than assumed. AppKit's own
    /// event delivery cannot be driven from a test, but everything on this side
    /// of it can.
    var isWatchingOutsideClicks: Bool { outsideClickMonitor != nil }

    override init() {
        super.init()
        refreshColorScheme()
        refreshLiquidGlassAppearance()
        popover.contentViewController = content
        setContentSize(NSSize(width: PopoverStyle.width, height: content.preferredHeight))
        // Keep status-button actions intact after the popup receives focus.
        // Transient dismissal can consume later clicks in its anchor window.
        popover.behavior = .semitransient
        popover.animates = true
        popover.delegate = self
        content.heightDidChange = { [weak self] _ in
            self?.refreshPlacement()
        }
        content.setSettingsHandler { [weak self] in
            self?.closeBeforePresentingSettings()
        }
        displayOptionsObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: NSWorkspace.shared,
            queue: .main
        ) { [weak self] _ in
            self?.refreshDisplayOptions()
        }
        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshPlacement()
        }
        appearanceObserver = NotificationCenter.default.addObserver(
            forName: Settings.didChange, object: nil, queue: .main
        ) { [weak self] notification in
            let change = notification.userInfo?[Settings.changeUserInfoKey] as? Settings.Change
            if change == .liquidGlassAppearance { self?.refreshLiquidGlassAppearance() }
            if change == .colorScheme { self?.refreshColorScheme() }
        }
    }

    deinit {
        if let displayOptionsObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(displayOptionsObserver)
        }
        if let screenParametersObserver {
            NotificationCenter.default.removeObserver(screenParametersObserver)
        }
        if let appearanceObserver {
            NotificationCenter.default.removeObserver(appearanceObserver)
        }
        stopWatchingForOutsideClicks()
        glassPanel?.onDismiss = nil
        glassPanel?.onEscape = nil
        glassPanel?.orderOut(nil)
    }

    private func refreshColorScheme() {
        popover.appearance = Settings.colorScheme.appearance
        glassPanel?.appearance = Settings.colorScheme.appearance
    }

    private func refreshLiquidGlassAppearance() {
        guard wantsOpen, let button = anchorButton else { return }
        // A material/host change invalidates in-flight pointer interaction.
        // Reparent the same content only after the previous host has stopped.
        popover.animates = false
        close()
        open(relativeTo: button, skipExternalRefreshes: true)
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
    private var hostIsShown: Bool {
        usingGlassPanel ? glassPanel?.isVisible == true : popover.isShown
    }

    func update(snapshot: PowerSnapshot, history: [Double], peak: Double, degraded: Bool) {
        latestPresentation = Presentation(
            snapshot: snapshot, history: history, peak: peak, degraded: degraded
        )
        // Keep data current while closed, but do not rebuild invisible AppKit
        // layers. Continue through AppKit's close fade so its last visible
        // frame behaves exactly as before.
        guard wantsOpen || hostIsShown else { return }
        applyLatestPresentation()
    }

    func setModeSelectHandler(
        _ handler: @escaping (EnergyMode, @escaping (EnergyMode?) -> Void) -> Void
    ) {
        content.setModeSelectHandler(handler)
    }

    func setSystemBatteryIconToggleHandler(
        _ handler: @escaping (Bool, @escaping (Bool) -> Void) -> Void
    ) {
        content.setSystemBatteryIconToggleHandler(handler)
    }

    func setSettingsHandler(_ handler: @escaping () -> Void) {
        settingsHandler = handler
    }

    func updateSystemBatteryIconState(
        _ hidden: Bool?, readStatus: SystemBatteryIconReadStatus = .ready
    ) {
        latestSystemBatteryIconHidden = hidden
        latestSystemBatteryIconReadStatus = readStatus
        guard wantsOpen || hostIsShown else { return }
        content.updateSystemBatteryIconState(hidden, readStatus: readStatus)
    }

    func toggle(relativeTo button: NSStatusBarButton) {
        wantsOpen ? close() : open(relativeTo: button)
    }

    private func open(relativeTo button: NSStatusBarButton,
                      skipExternalRefreshes: Bool = false) {
        // Reuse an open host. Reparenting its content into a second panel
        // leaves the original native glass window visible but empty.
        guard !wantsOpen else { refreshPlacement(); return }
        let useGlass = Settings.usesLiquidGlass
        guard var placement = resolvePlacement(relativeTo: button) else { return }
        guard !useGlass || placement.glassPanelFrame(margin: GlassPopoverPanel.contentInset) != nil else { return }
        let reduceMotion = Self.reducesMotion
        let reopeningDuringDismissal = !useGlass && popover.isShown
        if reopeningDuringDismissal {
            // A queued native re-show can outlive the user's next close.
            // Retire the closing instance before requesting another show.
            retireClassicHost()
        }
        popover.animates = !reduceMotion
        usingGlassPanel = useGlass
        setContentSize(placement.contentSize)
        // Prime every module with the newest cached telemetry before AppKit
        // captures the first frame. This replaces hidden periodic rendering
        // without introducing a stale flash on open.
        content.updateSystemBatteryIconState(
            latestSystemBatteryIconHidden, readStatus: latestSystemBatteryIconReadStatus
        )
        applyLatestPresentation()
        // A newly visible/hidden module can change the natural height while
        // priming cached data. Resolve the final viewport before hosting it.
        guard let refreshedPlacement = resolvePlacement(relativeTo: button) else { return }
        placement = refreshedPlacement
        guard !useGlass || placement.glassPanelFrame(margin: GlassPopoverPanel.contentInset) != nil else { return }
        setContentSize(placement.contentSize)
        if #available(macOS 26.0, *), useGlass,
           let frame = placement.glassPanelFrame(margin: GlassPopoverPanel.contentInset) {
            retireClassicHost()
            let panel = GlassPopoverPanel(content: content.view, frame: frame,
                style: Settings.liquidGlassStyle == .clear ? .clear : .regular)
            panel.point(to: placement.anchorFrame.midX)
            panel.appearance = Settings.colorScheme.appearance
            panel.onDismiss = { [weak self] in self?.close() }
            panel.onEscape = { [weak self] in _ = self?.handleEscape() }
            glassPanel = panel
            panel.makeKeyAndOrderFront(nil)
            if let initialFocus = panel.initialFirstResponder { panel.makeFirstResponder(initialFocus) }
        } else {
            popover.contentViewController = content
            let positioningRect = button.convert(
                button.window!.convertFromScreen(placement.anchorFrame), from: nil)
            popover.show(relativeTo: positioningRect, of: button, preferredEdge: .maxY)
            if popover.isShown { showsRequested += 1 }
        }
        guard hostIsShown else { close(); return }   // never leave a monitor behind
        anchorButton = button
        content.setPresentationActive(true)
        // Stop persistent module motion before installing the permitted reduced-
        // motion fade; disabling content animations also clears the root layer.
        content.setAnimationsEnabled(!reduceMotion)
        // Keep the existing content animation when reopening during dismissal;
        // restarting it from a fixed low opacity would flash.
        if !reopeningDuringDismissal {
            playEntranceAnimation(reduceMotion: reduceMotion)
        }
        presentationGeneration &+= 1
        let generation = presentationGeneration
        wantsOpen = true
        if skipExternalRefreshes {
            startWatchingForOutsideClicks()
            visibilityHandler?(true)
            return
        }
        LoginItemController.refresh()
        EnergyModeController.refreshFromHelper { [weak self] refreshed in
            guard refreshed, self?.wantsOpen == true,
                  self?.presentationGeneration == generation else { return }
            self?.content.refreshEnergyModeState()
        }
        startWatchingForOutsideClicks()
        visibilityHandler?(true)
    }

    private func setContentSize(_ size: NSSize) {
        content.setViewportHeight(size.height)
        if !usingGlassPanel, popover.contentSize != size { popover.contentSize = size }
    }

    private func retireClassicHost() {
        guard popover.contentViewController != nil else { return }
        // Do not require a retiring close animation to deliver one final
        // didClose after its shared content moves to another window. Counts
        // belong to one native instance; interrupted closes retire that instance.
        popover.delegate = nil
        popover.animates = false
        popover.close()
        popover.contentViewController = nil
        popover = NSPopover()
        popover.appearance = Settings.colorScheme.appearance
        popover.behavior = .semitransient
        popover.delegate = self
        showsRequested = 0
        closesObserved = 0
    }

    private func resolvePlacement(relativeTo button: NSStatusBarButton) -> PopoverPlacement? {
        guard let window = button.window, window.isVisible,
              !button.isHiddenOrHasHiddenAncestor else { return nil }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        let displays = NSScreen.screens.map {
            PopoverPlacement.Display(frame: $0.frame, visibleFrame: $0.visibleFrame)
        }
        return PopoverPlacement.resolve(
            anchor: anchor,
            displays: displays,
            naturalSize: NSSize(width: PopoverStyle.width, height: content.preferredHeight),
            glassMargin: Settings.usesLiquidGlass ? GlassPopoverPanel.contentInset : nil
        )
    }

    private func refreshPlacement() {
        guard wantsOpen else {
            setContentSize(NSSize(width: PopoverStyle.width, height: content.preferredHeight))
            return
        }
        guard let anchorButton, let placement = resolvePlacement(relativeTo: anchorButton) else {
            close()
            return
        }
        if usingGlassPanel {
            guard let frame = placement.glassPanelFrame(margin: GlassPopoverPanel.contentInset) else {
                close()
                return
            }
            if glassPanel?.frame != frame { glassPanel?.setFrame(frame, display: true) }
            if #available(macOS 26.0, *) { glassPanel?.point(to: placement.anchorFrame.midX) }
        }
        setContentSize(placement.contentSize)
    }

    private func refreshDisplayOptions() {
        let reduceMotion = Self.reducesMotion
        popover.animates = !reduceMotion
        guard wantsOpen else { return }
        content.setAnimationsEnabled(!reduceMotion)
        if reduceMotion { stopEntranceAnimation() }
    }

    private func applyLatestPresentation() {
        guard let latestPresentation else { return }
        content.update(
            snapshot: latestPresentation.snapshot,
            history: latestPresentation.history,
            peak: latestPresentation.peak,
            degraded: latestPresentation.degraded
        )
#if DEBUG
        contentRenderCountForTest += 1
#endif
    }

    private func close() {
        presentationGeneration &+= 1
        wantsOpen = false
        anchorButton = nil
        content.setPresentationActive(false)
        stopWatchingForOutsideClicks()
        if let panel = glassPanel {
            panel.onDismiss = nil
            panel.onEscape = nil
            panel.orderOut(nil)
            if #available(macOS 26.0, *) { panel.detachContent() }
            glassPanel = nil
            content.setAnimationsEnabled(false)
            stopEntranceAnimation()
            visibilityHandler?(false)
        } else {
            popover.performClose(nil)
        }
    }

    private func closeBeforePresentingSettings() {
        guard let handler = settingsHandler else { return }
        close()
        let generation = presentationGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.wantsOpen, self.presentationGeneration == generation else { return }
            handler()
        }
    }

    func onVisibilityChange(_ handler: @escaping (Bool) -> Void) {
        visibilityHandler = handler
    }

    func popoverShouldClose(_ popover: NSPopover) -> Bool {
        shouldCloseClassicPopover(popover, primaryAnchorPress: isCurrentPrimaryAnchorPress())
    }

    private func shouldCloseClassicPopover(_ closingPopover: NSPopover,
                                           primaryAnchorPress: Bool) -> Bool {
        let suppressed = closingPopover === popover && wantsOpen && primaryAnchorPress
        PopupEventLog.record(source: suppressed ? "native-anchor-suppressed" : "native-should-close",
            event: NSApp.currentEvent, openBefore: wantsOpen, openAfter: wantsOpen,
            anchorHit: primaryAnchorPress)
        // Explicit close() clears wantsOpen before asking AppKit, so the
        // button's own close still proceeds while that same press is held.
        return !suppressed
    }

    func popoverDidClose(_ notification: Notification) {
        guard let closingPopover = notification.object as? NSPopover, closingPopover === popover else { return }
        closesObserved += 1
        // A late Classic close must never dismiss the replacement glass panel.
        guard !usingGlassPanel else { return }
        // A close that finishes after the user has already reopened must not
        // tear down the popover it no longer owns.
        guard closesObserved >= showsRequested else { return }
        // Resetting the intent here is what covers AppKit dismissing the
        // popover on its own (Escape, a click elsewhere in the app) without
        // going through `close()`. Leaving it set would make the next click
        // read as "close" and be swallowed.
        let wasOpen = wantsOpen
        let anchorHit = isCurrentPrimaryAnchorPress()
        if wantsOpen { presentationGeneration &+= 1 }
        wantsOpen = false
        anchorButton = nil
        content.setPresentationActive(false)
        stopWatchingForOutsideClicks()
        content.setAnimationsEnabled(false)
        stopEntranceAnimation()
        visibilityHandler?(false)
        PopupEventLog.record(source: "native-classic-close", event: NSApp.currentEvent,
            openBefore: wasOpen, openAfter: wantsOpen, anchorHit: anchorHit)
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
        ) { [weak self] event in
            // A menu-bar host can relay the same press to the status button
            // after this monitor. Its full anchor frame belongs to that action.
            self?.handleGlobalMouseDown(screenPoint: NSEvent.mouseLocation, event: event)
        }
        let workspace = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  application.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            guard let self else { return }
            self.handleWorkspaceActivation(primaryAnchorPress: self.isCurrentPrimaryAnchorPress())
        })
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.sessionDidResignActiveNotification] {
            workspaceObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] _ in self?.handleOutsideClick(source: "workspace-space-or-session")
            })
        }
        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]
        ) { [weak self] event in
            guard let self, self.wantsOpen else { return event }
            if event.type == .keyDown {
                // Scope this process-wide monitor to its own window. Native
                // menus still have priority inside handleEscape().
                if event.keyCode == 53,
                   self.glassPanel?.ownsEscapeEvent(eventWindow: event.window, keyWindow: NSApp.keyWindow) == true,
                   self.handleEscape() { return nil }
            } else {
                let point = event.window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
                let wasOpen = self.wantsOpen
                let anchorHit = self.anchorButton?.window.map {
                    event.window === $0 || $0.frame.contains(point)
                } ?? false
                if self.shouldDismissLocalClick(window: event.window, screenPoint: point) { self.close() }
                PopupEventLog.record(source: "local-mouse", event: event,
                    openBefore: wasOpen, openAfter: self.wantsOpen, anchorHit: anchorHit)
            }
            return event
        }
        guard usingGlassPanel else { return }
        localObservers = [
            NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification,
                object: nil, queue: .main) { [weak self] notification in
                guard let menu = notification.object as? NSMenu else { return }
                self?.trackingMenus.append(menu)
            },
            NotificationCenter.default.addObserver(forName: NSMenu.didEndTrackingNotification,
                object: nil, queue: .main) { [weak self] notification in
                guard let menu = notification.object as? NSMenu else { return }
                self?.trackingMenus.removeAll { $0 === menu }
            },
        ]
        if let anchorButton, let anchorWindow = anchorButton.window {
            observedAnchor = anchorButton
            anchorPostedFrameChanges = anchorButton.postsFrameChangedNotifications
            anchorButton.postsFrameChangedNotifications = true
            localObservers.append(NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification,
                object: anchorButton, queue: .main) { [weak self] _ in self?.refreshPlacement() })
            for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification,
                         NSWindow.didChangeOcclusionStateNotification] {
                localObservers.append(NotificationCenter.default.addObserver(forName: name,
                    object: anchorWindow, queue: .main) { [weak self] _ in self?.refreshPlacement() })
            }
        }
    }

    private func shouldDismissLocalClick(window: NSWindow?, screenPoint: NSPoint) -> Bool {
        guard wantsOpen else { return false }
        if !usingGlassPanel {
            // Semi-transient popovers do not dismiss for other app windows.
            // Keep Classic content and native menu events with AppKit.
            guard let window, window !== content.view.window,
                  window.level < .popUpMenu else { return false }
        }
        if let glassPanel, window === glassPanel { return false }
        // The status window owns edge clicks beyond the shorter button bounds.
        // Leave its down/up sequence to the button's single toggle action.
        if let anchorButton, let anchorWindow = anchorButton.window {
            if window === anchorWindow || anchorWindow.frame.contains(screenPoint) { return false }
        }
        // Native menu tracking uses separate high-level windows (or no event
        // window). Do not swallow module selection or Escape within that menu.
        if !trackingMenus.isEmpty, window == nil || window!.level >= .popUpMenu { return false }
        return true
    }

    private func handleEscape() -> Bool {
        guard trackingMenus.isEmpty else { return false }
        if !content.cancelActiveModeDrag() { close() }
        return true
    }

    /// A native host may relay its own content press to the global monitor.
    /// Leave it with that window, just as with a relayed status-button action.
    func handleGlobalMouseDown(screenPoint: NSPoint, event: NSEvent? = nil) {
        guard wantsOpen else { return }
        let wasOpen = wantsOpen
        let anchorFrame = anchorButton?.window?.frame
        let shouldDismiss = Self.shouldDismissGlobalClick(screenPoint: screenPoint,
            anchorFrame: anchorFrame, eventWindow: event?.window,
            eventWindowNumber: event?.windowNumber ?? 0, contentWindow: content.view.window)
        if shouldDismiss { close() }
        PopupEventLog.record(source: "global-mouse", event: event,
            openBefore: wasOpen, openAfter: wantsOpen,
            anchorHit: !Self.shouldDismissGlobalClick(screenPoint: screenPoint, anchorFrame: anchorFrame))
    }

    static func shouldDismissGlobalClick(screenPoint: NSPoint, anchorFrame: NSRect?,
                                        eventWindow: NSWindow? = nil, eventWindowNumber: Int = 0,
                                        contentWindow: NSWindow? = nil) -> Bool {
        if let contentWindow {
            if eventWindow === contentWindow { return false }
            // Global delivery can omit the local window object. Only a known
            // positive target number can substitute for its identity; screen
            // overlap must not shelter a different process's window.
            if eventWindow == nil, eventWindowNumber > 0,
               eventWindowNumber == contentWindow.windowNumber { return false }
        }
        guard let frame = anchorFrame else { return true }
        // At the display's upper edge the pointer can equal maxY. Keep X
        // half-open so a neighbouring status item still counts as outside.
        return screenPoint.x < frame.minX || screenPoint.x >= frame.maxX
            || screenPoint.y < frame.minY || screenPoint.y > frame.maxY
    }

    static func shouldPreservePrimaryAnchorPress(screenPoint: NSPoint, anchorFrame: NSRect?,
                                                pressedMouseButtons: Int, controlHeld: Bool) -> Bool {
        // currentEvent is the last dequeued event, which can be an older mouse
        // release or key event. Only live device state owns this dismissal.
        pressedMouseButtons == 1 && !controlHeld
            && !shouldDismissGlobalClick(screenPoint: screenPoint, anchorFrame: anchorFrame)
    }

    private func isCurrentPrimaryAnchorPress() -> Bool {
        Self.shouldPreservePrimaryAnchorPress(screenPoint: NSEvent.mouseLocation,
            anchorFrame: anchorButton?.window?.frame, pressedMouseButtons: NSEvent.pressedMouseButtons,
            controlHeld: NSEvent.modifierFlags.contains(.control))
    }

    private func handleWorkspaceActivation(primaryAnchorPress: Bool) {
        guard wantsOpen else { return }
        if primaryAnchorPress {
            PopupEventLog.record(source: "workspace-anchor-suppressed", event: NSApp.currentEvent,
                openBefore: true, openAfter: true, anchorHit: true)
            return
        }
        handleOutsideClick(source: "workspace-activation")
    }

    func handleOutsideClick(source: String = "outside-click") {
        guard wantsOpen else { return }
        close()
        PopupEventLog.record(source: source, event: nil,
            openBefore: true, openAfter: wantsOpen, anchorHit: false)
    }

    private func stopWatchingForOutsideClicks() {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
        if let localEventMonitor { NSEvent.removeMonitor(localEventMonitor) }
        localEventMonitor = nil
        localObservers.forEach(NotificationCenter.default.removeObserver)
        localObservers.removeAll()
        observedAnchor?.postsFrameChangedNotifications = anchorPostedFrameChanges
        observedAnchor = nil
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        workspaceObservers.removeAll()
        let menus = trackingMenus
        trackingMenus.removeAll()
        menus.forEach { $0.cancelTracking() }
    }
}

#if DEBUG
extension PopoverController {
    func applyLatestPresentationForTest() { applyLatestPresentation() }

    func presentSettingsFromQuickMenuForTest() {
        content.presentSettingsFromQuickMenuForTest()
    }

    func openForSettingsCommandTest(relativeTo button: NSStatusBarButton) {
        open(relativeTo: button, skipExternalRefreshes: true)
    }

    var cachedPercentForTest: Int? { latestPresentation?.snapshot.percent }
    var cachedSystemBatteryIconStateForTest: Bool? { latestSystemBatteryIconHidden }
    var footerUpdateCountForTest: Int { content.footerUpdateCountForTest }

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
    var isShownForTest: Bool { hostIsShown }
    /// Dismissal that does not go through `close()`, the way Escape and a click
    /// elsewhere in the app reach a transient popover.
    func closeBypassingControllerForTest() {
        if let glassPanel { glassPanel.close() } else { popoverForTest.performClose(nil) }
    }

    /// Running animations across the whole content layer tree. A hidden popover
    /// that keeps animating is invisible on screen and expensive on battery,
    /// which is the entire reason `setAnimationsEnabled(false)` exists.
    var contentWindowForTest: NSWindow? { content.view.window }
    var contentViewForTest: NSView? { content.view }
    var popoverAppearanceForTest: NSAppearance? { glassPanel?.appearance ?? popoverForTest.appearance }
    var glassPanelForTest: GlassPopoverPanel? { glassPanel }
    var hasLocalEventMonitorForTest: Bool { localEventMonitor != nil }
    var lifetimeObserverCountForTest: Int { localObservers.count + workspaceObservers.count }
    var classicLifecycleCountsForTest: (shows: Int, closes: Int) { (showsRequested, closesObserved) }
    var classicPopoverForTest: NSPopover { popover }

    func retireClassicHostForTest() { retireClassicHost() }

    func shouldDismissLocalClickForTest(window: NSWindow?, screenPoint: NSPoint) -> Bool {
        shouldDismissLocalClick(window: window, screenPoint: screenPoint)
    }

    func classicShouldCloseForTest(screenPoint: NSPoint, pressedMouseButtons: Int,
                                  controlHeld: Bool = false) -> Bool {
        shouldCloseClassicPopover(popover, primaryAnchorPress: Self.shouldPreservePrimaryAnchorPress(
            screenPoint: screenPoint, anchorFrame: anchorButton?.window?.frame,
            pressedMouseButtons: pressedMouseButtons, controlHeld: controlHeld))
    }

    func handleWorkspaceActivationForTest(screenPoint: NSPoint, pressedMouseButtons: Int,
                                         controlHeld: Bool = false) {
        handleWorkspaceActivation(primaryAnchorPress: Self.shouldPreservePrimaryAnchorPress(
            screenPoint: screenPoint, anchorFrame: anchorButton?.window?.frame,
            pressedMouseButtons: pressedMouseButtons, controlHeld: controlHeld))
    }

    var runningAnimationCountForTest: Int {
        func count(_ layer: CALayer) -> Int {
            (layer.animationKeys()?.count ?? 0) + (layer.sublayers ?? []).reduce(0) { $0 + count($1) }
        }
        guard let root = content.view.layer else { return 0 }
        return count(root)
    }

    var runningAnimationDescriptionsForTest: [String] {
        content.runningAnimationDescriptionsForTest
    }

    var runningModuleAnimationCountForTest: Int {
        content.runningModuleAnimationCountForTest
    }

    var runningInfiniteAnimationCountForTest: Int {
        func count(_ layer: CALayer) -> Int {
            let local = (layer.animationKeys() ?? []).reduce(0) { total, key in
                total + (layer.animation(forKey: key)?.repeatCount.isInfinite == true ? 1 : 0)
            }
            return local + (layer.sublayers ?? []).reduce(0) { $0 + count($1) }
        }
        guard let root = content.view.layer else { return 0 }
        return count(root)
    }
}
#endif
