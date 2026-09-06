import AppKit
import IOKit.ps
import os

/// Tracks the optimistic two-state right-click gesture. The generation is the
/// request identity: comparing only the target mode is ABA-prone after three
/// fast toggles (Low → Auto → Low).
struct RightClickModeSequence {
    private(set) var pendingMode: EnergyMode?
    private(set) var generation = 0

    mutating func next(current: EnergyMode) -> (mode: EnergyMode, generation: Int) {
        let base = pendingMode ?? current
        let mode: EnergyMode = base == .low ? .auto : .low
        pendingMode = mode
        generation += 1
        return (mode, generation)
    }

    mutating func finish(generation completed: Int) -> Bool {
        guard completed == generation else { return false }
        pendingMode = nil
        return true
    }
}

struct StatusButtonPresentation: Equatable {
    let title: String
    let showsPercentage: Bool
    let alpha: CGFloat

    init(snapshot: PowerSnapshot, showsPercentage: Bool, degraded: Bool) {
        title = showsPercentage ? "\(snapshot.percent)% " : ""
        self.showsPercentage = showsPercentage
        alpha = degraded ? 0.45 : 1.0
    }
}

/// Reduces battery availability into the small set of effects the controller
/// may apply. Keeping this state separate makes a cold partial read distinct
/// from a machine that truly has no battery, without coupling tests to AppKit.
struct StartupAvailabilityReducer {
    struct Plan {
        let shouldTerminate: Bool
        let shouldRetry: Bool
        let snapshot: PowerSnapshot?
        let shouldRecordHistory: Bool
    }

    private(set) var hasUsableSnapshot = false
    private(set) var isDegraded = false

    mutating func start(_ result: BatterySampler.SampleResult) -> Plan {
        switch result {
        case .absent:
            hasUsableSnapshot = false
            isDegraded = false
            return Plan(
                shouldTerminate: true, shouldRetry: false,
                snapshot: nil, shouldRecordHistory: false
            )
        case .temporarilyUnavailable:
            hasUsableSnapshot = false
            isDegraded = true
            return Plan(
                shouldTerminate: false, shouldRetry: true,
                snapshot: nil, shouldRecordHistory: false
            )
        case let .snapshot(snapshot):
            return accept(snapshot, recordHistory: true)
        }
    }

    mutating func finish(
        _ snapshot: PowerSnapshot?,
        recordHistory: Bool
    ) -> Plan {
        guard let snapshot else {
            isDegraded = true
            return Plan(
                shouldTerminate: false, shouldRetry: false,
                snapshot: nil, shouldRecordHistory: false
            )
        }
        return accept(snapshot, recordHistory: recordHistory)
    }

    private mutating func accept(
        _ snapshot: PowerSnapshot,
        recordHistory: Bool
    ) -> Plan {
        hasUsableSnapshot = true
        isDegraded = false
        return Plan(
            shouldTerminate: false, shouldRetry: false,
            snapshot: snapshot, shouldRecordHistory: recordHistory
        )
    }
}

/// Coalesces the two periodic clocks into the sample already in flight, while
/// retaining one follow-up for an event that happened after that sample began.
/// Ordinary notifications do not invalidate completed work; wake does, because
/// a pre-sleep acquisition must not repopulate the newly reset history.
/// This keeps coincident 1 s/2 s timer ticks from doubling IOKit/helper work.
struct SampleRequestCoalescer {
    struct Completion {
        let recordHistory: Bool
        let requiresFreshFollowUp: Bool
        let publishCurrent: Bool
    }

    private(set) var isInFlight = false
    private var historyRequested = false
    private var freshFollowUpRequested = false
    private var currentSuperseded = false

    mutating func request(
        recordHistory: Bool,
        requiresFreshFollowUp: Bool,
        supersedesCurrent: Bool = false
    ) -> Bool {
        historyRequested = historyRequested || recordHistory
        guard !isInFlight else {
            freshFollowUpRequested = freshFollowUpRequested
                || requiresFreshFollowUp || supersedesCurrent
            currentSuperseded = currentSuperseded || supersedesCurrent
            return false
        }
        isInFlight = true
        return true
    }

    mutating func complete() -> Completion {
        precondition(isInFlight)
        let completion = Completion(
            recordHistory: historyRequested,
            requiresFreshFollowUp: freshFollowUpRequested,
            publishCurrent: !currentSuperseded
        )
        isInFlight = false
        historyRequested = false
        freshFollowUpRequested = false
        currentSuperseded = false
        return completion
    }
}

final class StatusItemController: NSObject {
    /// The system menu bar font with tabular figures switched on. Deriving from
    /// menuBarFont keeps size and weight identical to every neighbouring item;
    /// the feature setting stops the width jumping as digits change.
    private static let menuBarTabularFont: NSFont = {
        let base = NSFont.menuBarFont(ofSize: 0)
        let descriptor = base.fontDescriptor.addingAttributes([
            .featureSettings: [[
                NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
                NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector,
            ]],
        ])
        return NSFont(descriptor: descriptor, size: 0) ?? base
    }()

    private static let historyInterval: TimeInterval = 2
    private static let historyTolerance: TimeInterval = 0.2
    private static let displayInterval: TimeInterval = 1
    private static let displayTolerance: TimeInterval = 0.1

    private let log = OSLog(subsystem: "com.leoarrow.wattson", category: "menubar")

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = PopoverController()
    private lazy var settingsWindowController = SettingsWindowController()
    private let history = PowerHistory()
    private let samplingQueue = DispatchQueue(
        label: "com.leoarrow.wattson.sampler",
        qos: .userInitiated
    )
    private let powerObservationRuntime =
        PowerObservationRuntimeController()

    private var snapshot = PowerSnapshot()
    private var historyTimer: Timer?
    private var displayTimer: Timer?
    private var powerSourceRunLoopSource: CFRunLoopSource?
    private var energyModeObserver: NSObjectProtocol?
    private var settingsObserver: NSObjectProtocol?
    private var systemBatteryIconObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var started = false
    private var startupAvailability = StartupAvailabilityReducer()
    private var hasUsableSnapshot: Bool { startupAvailability.hasUsableSnapshot }
    private var isDegraded: Bool { startupAvailability.isDegraded }
    private var sampleRequests = SampleRequestCoalescer()
    private var pendingPowerObservationEvent:
        PowerObservationRuntimeEvent = .normal
    private var pressed = false
    private var clickRouter = ClickRouter()
    private var rightClickModes = RightClickModeSequence()
    private var renderedStatusIconKey: BatteryIcon.RenderKey?
    private var renderedStatusButtonPresentation: StatusButtonPresentation?

    func start() -> Bool {
        guard !started else { return true }
        guard let button = statusItem.button else { return false }
        let startupPlan = startupAvailability.start(BatterySampler.sampleResult())
        if startupPlan.shouldTerminate {
            os_log("no AppleSmartBattery — this Mac has no battery", log: log, type: .fault)
            noBattery()
            return false
        }

        started = true
        if let initial = startupPlan.snapshot {
            snapshot = initial
            if startupPlan.shouldRecordHistory {
                history.append(initial.totalInputW)
            }
        }
        button.target = self
        button.action = #selector(handleClick)
        button.sendAction(on: [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp])
        button.toolTip = "Wattson — click for power flow; right-click to toggle Low Power Mode"

        popover.onVisibilityChange { [weak self] shown in
            shown ? self?.startDisplayClock() : self?.stopDisplayClock()
        }
        popover.setModeSelectHandler { [weak self] mode, completion in
            guard let self else {
                completion(nil)
                return
            }
            self.applyEnergyMode(mode, completion: completion)
        }
        popover.setSystemBatteryIconToggleHandler { [weak self] hidden, completion in
            guard let self else {
                completion(false)
                return
            }
            self.applySystemBatteryIconHidden(hidden, completion: completion)
        }
        wireSettingsPresentation()
        installMainMenuIfNeeded()

        energyModeObserver = EnergyModeController.observe {
            [weak self] _ in self?.refreshPresentation()
        }
        settingsObserver = NotificationCenter.default.addObserver(
            forName: Settings.didChange, object: nil, queue: .main
        ) { [weak self] _ in
            self?.refreshPresentation()
        }
        installSystemBatteryIconObservationIfNeeded()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            // Timers may be coalesced across sleep. Refresh immediately so a
            // stale pre-sleep power route is never left visible after wake.
            self.history.reset()
            self.refreshPresentation()
            self.sampleNow(
                recordHistory: true,
                requiresFreshFollowUp: true,
                supersedesCurrent: true,
                event: .sleepWake
            )
        }
        startEventDrivenUpdates()
        startHistoryClock()
        LoginItemController.refresh()
        refreshPresentation()
        if startupPlan.shouldRetry {
            sampleNow(recordHistory: false, requiresFreshFollowUp: true)
        }
        return true
    }

    deinit {
        historyTimer?.invalidate()
        displayTimer?.invalidate()
        if let powerSourceRunLoopSource {
            CFRunLoopSourceInvalidate(powerSourceRunLoopSource)
        }
        if let energyModeObserver {
            NotificationCenter.default.removeObserver(energyModeObserver)
        }
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
        if let systemBatteryIconObserver {
            NotificationCenter.default.removeObserver(systemBatteryIconObserver)
        }
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    // MARK: - Clicks

    private func wireSettingsPresentation() {
        popover.setSettingsHandler { [weak self] in
            // PopoverController owns close-before-callback and dispatches this
            // presenter on the next main turn. Calling the raw presenter here
            // avoids a second close while keeping every direct command on the
            // guarded `showSettings` path below.
            self?.presentSettingsWindow()
        }
    }

    private func installMainMenuIfNeeded() {
        guard NSApp.mainMenu == nil else { return }

        let mainMenu = NSMenu(title: "Wattson")
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu(title: "Wattson")
        applicationItem.submenu = applicationMenu
        mainMenu.addItem(applicationItem)

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(showSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        settingsItem.keyEquivalentModifierMask = [.command]
        applicationMenu.addItem(settingsItem)
        applicationMenu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Wattson",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = NSApp
        quitItem.keyEquivalentModifierMask = [.command]
        applicationMenu.addItem(quitItem)
        NSApp.mainMenu = mainMenu
    }

    @objc private func showSettings() {
        // Command-Comma and the application menu can fire while the popover is
        // open. Establish the closed logical state synchronously, including
        // stopping its 1 Hz display clock, before any Settings refresh runs.
        stopDisplayClock()
        popover.handleOutsideClick()
        DispatchQueue.main.async { [weak self] in
            self?.presentSettingsWindow()
        }
    }

    private func presentSettingsWindow() {
        // The quick-menu relay closes the popover first but its animated
        // `popoverDidClose` arrives later. Stop hidden work at presentation
        // time instead of waiting for that delegate callback.
        stopDisplayClock()
        settingsWindowController.show()
    }

    @objc private func handleClick() {
        guard let button = statusItem.button else { return }
        let event = NSApp.currentEvent
        for intent in clickRouter.intents(for: event?.type,
                                          controlHeld: event?.modifierFlags.contains(.control) ?? false) {
            switch intent {
            case .press:
                pressed = true
                refreshStatusItem()
            case .release:
                if pressed {
                    pressed = false
                    refreshStatusItem()
                }
            case .primary:
                pressed = false
                guard hasUsableSnapshot else {
                    refreshStatusItem()
                    continue
                }
                let opening = !popover.isOpen
                refreshStatusItem()
                popover.toggle(relativeTo: button)
                // A cold launchd helper can miss the frame budget. Show first,
                // then fetch the setting without holding AppKit's event loop.
                if opening { refreshSystemBatteryIconState() }
            case .secondary:
                pressed = false
                refreshStatusItem()
                let request = rightClickModes.next(current: EnergyModeController.current)
                applyEnergyMode(request.mode) { [weak self] landedMode in
                    guard let self,
                          self.rightClickModes.finish(generation: request.generation) else { return }
                    self.confirmToggle(success: landedMode == request.mode)
                }
            }
        }
    }

    /// The popover's selector settles immediately; helper wake-up, `pmset`, and
    /// authoritative readback happen off the AppKit thread. Right-click uses
    /// this same path so it cannot overtake an in-flight popover write.
    private func applyEnergyMode(_ mode: EnergyMode, completion: @escaping (EnergyMode?) -> Void) {
        guard HelperClient.isInstalled else {
            os_log("helper not installed — mode change is a no-op", log: log, type: .error)
            refreshPresentation()
            completion(nil)
            return
        }
        EnergyModeController.set(mode) { [weak self] landedMode in
            guard let self else {
                completion(nil)
                return
            }
            completion(landedMode)
            if landedMode == mode {
                self.sampleNow(recordHistory: false, requiresFreshFollowUp: true)
            } else {
                self.refreshPresentation()
            }
        }
    }

    private func refreshSystemBatteryIconState() {
        SystemBatteryIconController.refreshHidden { [weak self] _ in
            self?.updateSystemBatteryIconPresentation()
        }
    }

    private func installSystemBatteryIconObservationIfNeeded() {
        guard systemBatteryIconObserver == nil else { return }
        systemBatteryIconObserver = NotificationCenter.default.addObserver(
            forName: SystemBatteryIconController.didChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateSystemBatteryIconPresentation()
        }
        updateSystemBatteryIconPresentation()
    }

    private func updateSystemBatteryIconPresentation() {
        popover.updateSystemBatteryIconState(SystemBatteryIconController.cachedHidden)
    }

    private func applySystemBatteryIconHidden(
        _ hidden: Bool,
        completion: @escaping (Bool) -> Void
    ) {
        guard HelperClient.isInstalled else {
            os_log("helper not installed — system battery setting is a no-op", log: log, type: .error)
            updateSystemBatteryIconPresentation()
            completion(false)
            return
        }
        SystemBatteryIconController.setHidden(hidden) { [weak self] succeeded in
            guard let self else {
                completion(false)
                return
            }
            self.updateSystemBatteryIconPresentation()
            if !succeeded {
                os_log("failed to update the system battery icon", log: self.log, type: .error)
            }
            completion(succeeded)
        }
    }

    private func noBattery() {
        NSStatusBar.system.removeStatusItem(statusItem)
        NSApp.terminate(nil)
    }

    private func confirmToggle(success: Bool) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            refreshPresentation()
            return
        }
        guard let button = statusItem.button else { return }
        button.wantsLayer = true
        guard let layer = button.layer else { return }
        let squeeze = CABasicAnimation(keyPath: "transform.scale")
        squeeze.fromValue = 1.0
        squeeze.toValue = success ? 0.82 : 0.95
        squeeze.duration = 0.11
        squeeze.autoreverses = true
        squeeze.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(squeeze, forKey: "confirmToggle")
        refreshPresentation()
    }

    // MARK: - Clocks

    private func startEventDrivenUpdates() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ raw in
            guard let raw else { return }
            let controller = Unmanaged<StatusItemController>.fromOpaque(raw).takeUnretainedValue()
            controller.sampleNow(
                recordHistory: false,
                requiresFreshFollowUp: true,
                event: .powerSourceTransition
            )
        }, context)?.takeRetainedValue() else { return }
        powerSourceRunLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }

    private func startHistoryClock() {
        let timer = Timer(timeInterval: Self.historyInterval, repeats: true) { [weak self] _ in
            self?.sampleNow(recordHistory: true)
        }
        timer.tolerance = Self.historyTolerance
        historyTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func startDisplayClock() {
        guard displayTimer == nil else { return }
        let timer = Timer(timeInterval: Self.displayInterval, repeats: true) { [weak self] _ in
            self?.sampleNow(recordHistory: false)
        }
        timer.tolerance = Self.displayTolerance
        displayTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        // Let NSPopover hand its first frame to the window server before doing
        // a fresh IOKit read and rebuilding the animated modules.
        DispatchQueue.main.async { [weak self] in
            guard self?.displayTimer != nil else { return }
            self?.sampleNow(recordHistory: false, requiresFreshFollowUp: true)
        }
    }

    private func stopDisplayClock() {
        displayTimer?.invalidate()
        displayTimer = nil
    }

    fileprivate func sampleNow(
        recordHistory: Bool,
        requiresFreshFollowUp: Bool = false,
        supersedesCurrent: Bool = false,
        event: PowerObservationRuntimeEvent = .normal
    ) {
        dispatchPrecondition(condition: .onQueue(.main))
        pendingPowerObservationEvent =
            pendingPowerObservationEvent.merging(event)
        guard sampleRequests.request(
            recordHistory: recordHistory,
            requiresFreshFollowUp: requiresFreshFollowUp,
            supersedesCurrent: supersedesCurrent
        ) else { return }
        let runtimeEvent = pendingPowerObservationEvent
        pendingPowerObservationEvent = .normal
        samplingQueue.async { [weak self] in
            guard let self else { return }
            let result = self.powerObservationRuntime.sample(
                event: runtimeEvent
            )
            DispatchQueue.main.async { [weak self] in
                self?.finishSample(result)
            }
        }
    }

    private func finishSample(
        _ result: PowerObservationRuntimeSample
    ) {
        dispatchPrecondition(condition: .onQueue(.main))
        let completedRequest = sampleRequests.complete()

        // IOPS notifications can continue throughout successive acquisitions.
        // Publish completed work before following them up so updates cannot
        // starve. Only wake invalidates the in-flight result and its history.
        if completedRequest.publishCurrent {
            let availabilityPlan = startupAvailability.finish(
                result.visibleSnapshot,
                recordHistory: completedRequest.recordHistory
            )
            if let fresh = availabilityPlan.snapshot {
                snapshot = fresh
                if availabilityPlan.shouldRecordHistory {
                    history.append(fresh.totalInputW)
                }
            }
            refreshPresentation()
        }

        if completedRequest.requiresFreshFollowUp {
            sampleNow(
                recordHistory: completedRequest.recordHistory && !completedRequest.publishCurrent
            )
        }
    }

    private func refreshPresentation() {
        refreshStatusItem()
        guard hasUsableSnapshot else { return }
        let historyPresentation = history.presentation
        popover.update(
            snapshot: snapshot,
            history: historyPresentation.samples,
            peak: historyPresentation.peak,
            degraded: isDegraded
        )
    }

    private func refreshStatusItem() {
        guard let button = statusItem.button else { return }
        guard hasUsableSnapshot else {
            button.image = nil
            button.imagePosition = .noImage
            button.title = "—"
            button.alphaValue = 0.45
            renderedStatusIconKey = nil
            renderedStatusButtonPresentation = nil
            return
        }
        let mode = EnergyModeController.current
        let iconStyle = Settings.menuBarIconStyle
        let key = BatteryIcon.renderKey(
            for: snapshot, mode: mode, pressed: pressed,
            style: iconStyle,
            appearance: button.effectiveAppearance,
            increasedContrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        )
        if key != renderedStatusIconKey {
            button.image = BatteryIcon.image(
                for: snapshot,
                mode: mode,
                pressed: pressed,
                style: iconStyle
            )
            renderedStatusIconKey = key
        }

        let presentation = StatusButtonPresentation(
            snapshot: snapshot,
            showsPercentage: Settings.showsMenuBarPercentage,
            degraded: isDegraded
        )
        let rendered = renderedStatusButtonPresentation

        // Percentage left of the glyph, matching the system battery. Setting a
        // plain title rather than an attributed one lets AppKit keep the text
        // colour correct across light, dark and the pressed highlight. These
        // setters invalidate status-item layout, so write only changed fields.
        if presentation.showsPercentage != rendered?.showsPercentage {
            if presentation.showsPercentage { button.font = Self.menuBarTabularFont }
            button.imagePosition = presentation.showsPercentage ? .imageRight : .imageOnly
        }
        if presentation.title != rendered?.title {
            button.title = presentation.title
        }
        if presentation.alpha != rendered?.alpha {
            button.alphaValue = presentation.alpha
        }
        renderedStatusButtonPresentation = presentation
    }
}

#if DEBUG
extension StatusItemController {
    func configureSettingsWindowForTest(_ controller: SettingsWindowController) {
        settingsWindowController = controller
    }

    func wireSettingsPresentationForTest() { wireSettingsPresentation() }
    func installMainMenuForTest() { installMainMenuIfNeeded() }
    func beginSystemBatteryIconObservationForTest() {
        installSystemBatteryIconObservationIfNeeded()
    }

    var settingsWindowForTest: NSWindow? { settingsWindowController.window }
    var presentedSystemBatteryIconHiddenForTest: Bool? {
        popover.cachedSystemBatteryIconStateForTest
    }
    var popoverIsOpenForTest: Bool { popover.isOpen }
    var popoverIsWatchingOutsideClicksForTest: Bool { popover.isWatchingOutsideClicks }
    var displayClockIsRunningForTest: Bool { displayTimer != nil }

    func startDisplayClockForSettingsCommandTest() { startDisplayClock() }

    func openPopoverForSettingsCommandTest(relativeTo button: NSStatusBarButton) {
        popover.openForSettingsCommandTest(relativeTo: button)
    }

    func presentSettingsFromQuickMenuForTest() {
        popover.presentSettingsFromQuickMenuForTest()
    }
}
#endif
