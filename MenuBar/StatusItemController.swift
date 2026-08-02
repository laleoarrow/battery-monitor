import AppKit
import IOKit.ps
import os

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

    private var snapshot = PowerSnapshot()
    private var historyTimer: Timer?
    private var displayTimer: Timer?
    private var powerSourceRunLoopSource: CFRunLoopSource?
    private var pressed = false
    /// Both halves of one click must not act twice.
    private static let clickCoalescingWindow: TimeInterval = 0.3
    private var lastClickAt: TimeInterval = 0
    private var systemBatteryIconHidden: Bool?

    func start() {
        guard let button = statusItem.button else { return }
        guard let initial = BatterySampler.sample() else {
            os_log("no AppleSmartBattery — this Mac has no battery", log: log, type: .fault)
            noBattery()
            return
        }

        snapshot = initial
        history.append(initial.totalInputW)
        button.target = self
        button.action = #selector(handleClick)
        button.sendAction(on: [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp])
        button.toolTip = "Wattson — 左键查看功率流，右键切换省电模式"

        popover.onVisibilityChange { [weak self] shown in
            shown ? self?.startDisplayClock() : self?.stopDisplayClock()
        }
        popover.setModeSelectHandler { [weak self] mode in
            self?.applyEnergyMode(mode) ?? false
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
        refreshPresentation()
    }

    // MARK: - Clicks

    @objc private func handleClick() {
        guard let button = statusItem.button else { return }
        let event = NSApp.currentEvent
        let type = event?.type

        // Act on whichever half of the click arrives first, and ignore the
        // other half. A trackpad tap is short enough that AppKit may deliver
        // only one of the pair, and by the time the action runs
        // NSApp.currentEvent can already be nil — the old code required it and
        // silently dropped the click, so taps did nothing while a held press
        // worked.
        let now = Date().timeIntervalSinceReferenceDate
        let isPress = type == .leftMouseDown || type == .rightMouseDown
        let isRelease = type == .leftMouseUp || type == .rightMouseUp

        // A coloured icon has to revert to template while the selection
        // highlight is drawn behind it, so the press state still has to be set
        // even though the action itself fires on whichever half arrives first.
        if isPress {
            pressed = true
            refreshPresentation()
        }
        if isRelease {
            if pressed {
                pressed = false
                refreshPresentation()
            }
            if now - lastClickAt < Self.clickCoalescingWindow { return }
        }
        lastClickAt = now

        let isSecondary = type == .rightMouseDown || type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true
        if isSecondary {
            let ok = applyEnergyMode(EnergyModeController.current == .low ? .auto : .low)
            confirmToggle(success: ok)
        } else {
            // Only when opening: the query wakes the helper through launchd, so
            // it has no business running on the 1 Hz refresh or on close.
            if !popover.isShown { refreshSystemBatteryIconState() }
            refreshPresentation()
            popover.toggle(relativeTo: button)
        }
    }

    private func applyEnergyMode(_ mode: EnergyMode) -> Bool {
        guard HelperClient.isInstalled else {
            os_log("helper not installed — mode change is a no-op", log: log, type: .error)
            refreshPresentation()
            return false
        }
        let succeeded = EnergyModeController.set(mode)
        if succeeded {
            sampleNow(recordHistory: false)
        } else {
            refreshPresentation()
        }
        return succeeded
    }

    private func refreshSystemBatteryIconState() {
        systemBatteryIconHidden = HelperClient.isInstalled
            ? SystemBatteryIconController.isHidden
            : nil
        popover.updateSystemBatteryIconState(systemBatteryIconHidden)
    }

    private func applySystemBatteryIconHidden(_ hidden: Bool) -> Bool {
        guard HelperClient.isInstalled else {
            os_log("helper not installed — system battery setting is a no-op", log: log, type: .error)
            refreshSystemBatteryIconState()
            return false
        }
        let succeeded = SystemBatteryIconController.setHidden(hidden)
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
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
    }

    private func startHistoryClock() {
        historyTimer = Timer.scheduledTimer(withTimeInterval: Self.historyInterval, repeats: true) { [weak self] _ in
            self?.sampleNow(recordHistory: true)
        }
    }

    private func startDisplayClock() {
        guard displayTimer == nil else { return }
        sampleNow(recordHistory: false)
        displayTimer = Timer.scheduledTimer(withTimeInterval: Self.displayInterval, repeats: true) { [weak self] _ in
            self?.sampleNow(recordHistory: false)
        }
    }

    private func stopDisplayClock() {
        displayTimer?.invalidate()
        displayTimer = nil
    }

    fileprivate func sampleNow(recordHistory: Bool) {
        guard let fresh = BatterySampler.sample() else {
            isDegraded = true
            refreshPresentation()
            return
        }
        isDegraded = false
        snapshot = fresh
        if recordHistory {
            history.append(fresh.totalInputW)
        }
        refreshPresentation()
    }

    private func refreshPresentation() {
        guard let button = statusItem.button else { return }
        button.image = BatteryIcon.image(
            for: snapshot,
            mode: EnergyModeController.current,
            pressed: pressed
        )

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
        popover.update(
            snapshot: snapshot,
            history: history.samples,
            peak: history.peak,
            degraded: isDegraded
        )
    }
}
