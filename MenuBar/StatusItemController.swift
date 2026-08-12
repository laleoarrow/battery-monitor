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
    private static let displayInterval: TimeInterval = 1

    /// True while we are showing a stale snapshot because a read failed.
    private(set) var isDegraded = false
    private let log = OSLog(subsystem: "com.leoarrow.wattson", category: "menubar")

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = PopoverController()
    private let history = PowerHistory()
    private let samplingQueue = DispatchQueue(
        label: "com.leoarrow.wattson.sampler",
        qos: .userInitiated
    )

    private var snapshot = PowerSnapshot()
    private var historyTimer: Timer?
    private var displayTimer: Timer?
    private var powerSourceRunLoopSource: CFRunLoopSource?
    private var sampleInFlight = false
    private var resampleRequested = false
    private var pendingHistorySample = false
    private var pressed = false
    private var clickRouter = ClickRouter()
    private var rightClickModes = RightClickModeSequence()
    private var systemBatteryIconHidden: Bool?
    private var systemBatteryIconRefreshGeneration = 0
    private var renderedStatusIconKey: BatteryIcon.RenderKey?

    func start() -> Bool {
        guard let button = statusItem.button else { return false }
        guard let initial = BatterySampler.sample() else {
            os_log("no AppleSmartBattery — this Mac has no battery", log: log, type: .fault)
            noBattery()
            return false
        }

        snapshot = initial
        history.append(initial.totalInputW)
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
        popover.setSystemBatteryIconToggleHandler { [weak self] hidden in
            self?.applySystemBatteryIconHidden(hidden) ?? false
        }

        EnergyModeController.observe { [weak self] _ in self?.refreshPresentation() }
        NotificationCenter.default.addObserver(
            forName: Settings.didChange, object: nil, queue: .main
        ) { [weak self] _ in
            self?.refreshPresentation()
        }
        startEventDrivenUpdates()
        startHistoryClock()
        LoginItemController.refresh()
        refreshPresentation()
        return true
    }

    // MARK: - Clicks

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
                self.sampleNow(recordHistory: false)
            } else {
                self.refreshPresentation()
            }
        }
    }

    private func refreshSystemBatteryIconState() {
        systemBatteryIconRefreshGeneration += 1
        let generation = systemBatteryIconRefreshGeneration
        guard HelperClient.isInstalled else {
            systemBatteryIconHidden = nil
            popover.updateSystemBatteryIconState(nil)
            return
        }
        SystemBatteryIconController.refreshHidden { [weak self] hidden in
            guard let self = self else { return }
            guard generation == self.systemBatteryIconRefreshGeneration else { return }
            self.systemBatteryIconHidden = hidden
            self.popover.updateSystemBatteryIconState(hidden)
        }
    }

    private func applySystemBatteryIconHidden(_ hidden: Bool) -> Bool {
        // Invalidate any read that began before this user choice.
        systemBatteryIconRefreshGeneration += 1
        guard HelperClient.isInstalled else {
            os_log("helper not installed — system battery setting is a no-op", log: log, type: .error)
            refreshSystemBatteryIconState()
            return false
        }
        let succeeded = SystemBatteryIconController.setHidden(hidden)
        if succeeded {
            systemBatteryIconHidden = hidden
            popover.updateSystemBatteryIconState(hidden)
        }
        refreshSystemBatteryIconState()
        if !succeeded {
            os_log("failed to update the system battery icon", log: log, type: .error)
        }
        return succeeded
    }

    private func noBattery() {
        NSStatusBar.system.removeStatusItem(statusItem)
        NSApp.terminate(nil)
    }

    private func confirmToggle(success: Bool) {
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
            controller.sampleNow(recordHistory: false)
        }, context)?.takeRetainedValue() else { return }
        powerSourceRunLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }

    private func startHistoryClock() {
        let timer = Timer(timeInterval: Self.historyInterval, repeats: true) { [weak self] _ in
            self?.sampleNow(recordHistory: true)
        }
        historyTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func startDisplayClock() {
        guard displayTimer == nil else { return }
        let timer = Timer(timeInterval: Self.displayInterval, repeats: true) { [weak self] _ in
            self?.sampleNow(recordHistory: false)
        }
        displayTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        // Let NSPopover hand its first frame to the window server before doing
        // a fresh IOKit read and rebuilding the animated modules.
        DispatchQueue.main.async { [weak self] in
            guard self?.displayTimer != nil else { return }
            self?.sampleNow(recordHistory: false)
        }
    }

    private func stopDisplayClock() {
        displayTimer?.invalidate()
        displayTimer = nil
    }

    fileprivate func sampleNow(recordHistory: Bool) {
        dispatchPrecondition(condition: .onQueue(.main))
        pendingHistorySample = pendingHistorySample || recordHistory
        guard !sampleInFlight else {
            resampleRequested = true
            return
        }

        sampleInFlight = true
        samplingQueue.async { [weak self] in
            let fresh = BatterySampler.sample()
            let livePower = HelperClient.livePower()
            DispatchQueue.main.async { [weak self] in
                self?.finishSample(fresh, livePower: livePower)
            }
        }
    }

    private func finishSample(
        _ fresh: PowerSnapshot?,
        livePower: HelperClient.LivePower?
    ) {
        dispatchPrecondition(condition: .onQueue(.main))
        let recordHistory = pendingHistorySample
        let shouldResample = resampleRequested
        pendingHistorySample = false
        resampleRequested = false
        sampleInFlight = false

        guard var fresh else {
            isDegraded = true
            refreshPresentation()
            if shouldResample { sampleNow(recordHistory: false) }
            return
        }
        if let live = livePower {
            fresh = BatterySampler.resolvedLivePower(
                snapshot: fresh,
                adapterW: live.adapterW,
                systemW: live.systemW
            )
        }
        isDegraded = false
        snapshot = fresh
        if recordHistory {
            history.append(fresh.totalInputW)
        }
        refreshPresentation()
        if shouldResample { sampleNow(recordHistory: false) }
    }

    private func refreshPresentation() {
        refreshStatusItem()
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
        let mode = EnergyModeController.current
        let key = BatteryIcon.renderKey(
            for: snapshot, mode: mode, pressed: pressed,
            appearance: button.effectiveAppearance,
            increasedContrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        )
        if key != renderedStatusIconKey {
            button.image = BatteryIcon.image(for: snapshot, mode: mode, pressed: pressed)
            renderedStatusIconKey = key
        }

        // Percentage left of the glyph, matching the system battery. Setting a
        // plain title rather than an attributed one lets AppKit keep the text
        // colour correct across light, dark and the pressed highlight.
        if Settings.showsMenuBarPercentage {
            button.font = Self.menuBarTabularFont
            button.title = "\(snapshot.percent)% "
            button.imagePosition = .imageRight
        } else {
            button.title = ""
            button.imagePosition = .imageOnly
        }

        button.alphaValue = isDegraded ? 0.45 : 1.0
    }
}
