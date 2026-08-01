import AppKit
import IOKit.ps
import os

final class StatusItemController: NSObject {
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
        guard let button = statusItem.button, let event = NSApp.currentEvent else { return }

        switch event.type {
        case .leftMouseDown, .rightMouseDown:
            pressed = true
            refreshPresentation()
        case .rightMouseUp:
            pressed = false
            let ok = applyEnergyMode(EnergyModeController.current == .low ? .auto : .low)
            confirmToggle(success: ok)
        case .leftMouseUp:
            pressed = false
            refreshPresentation()
            popover.toggle(relativeTo: button)
        default:
            break
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
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
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
