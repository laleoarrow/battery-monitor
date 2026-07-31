import AppKit
import IOKit.ps
import os

final class StatusItemController: NSObject {
    private static let historyInterval: TimeInterval = 2
    private static let displayInterval: TimeInterval = 1

    /// True while we are showing a stale snapshot because a read failed.
    /// Plan 2's popover reads this to surface a notice.
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

        guard BatterySampler.sample() != nil else {
            os_log("no AppleSmartBattery — this Mac has no battery", log: log, type: .fault)
            noBattery()
            return
        }

        button.target = self
        button.action = #selector(handleClick)
        // Down events are needed too: a coloured icon must revert to template
        // while the selection highlight is drawn behind it.
        button.sendAction(on: [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp])
        button.toolTip = "Wattson — 左键查看功率流，右键切换省电模式"

        popover.onVisibilityChange { [weak self] shown in
            shown ? self?.startDisplayClock() : self?.stopDisplayClock()
        }

        EnergyModeController.observe { [weak self] _ in self?.refreshIcon() }
        startEventDrivenUpdates()
        startHistoryClock()
        sampleNow()
    }

    // MARK: - Clicks

    @objc private func handleClick() {
        guard let button = statusItem.button, let event = NSApp.currentEvent else { return }

        switch event.type {
        case .leftMouseDown, .rightMouseDown:
            pressed = true
            refreshIcon()

        case .rightMouseUp:
            pressed = false
            guard HelperClient.isInstalled else {
                os_log("helper not installed — right-click is a no-op", log: log, type: .error)
                confirmToggle(success: false)
                return
            }
            let ok = EnergyModeController.toggle()
            confirmToggle(success: ok)

        case .leftMouseUp:
            pressed = false
            refreshIcon()
            popover.toggle(relativeTo: button)

        default:
            break
        }
    }

    private func noBattery() {
        NSStatusBar.system.removeStatusItem(statusItem)
        NSApp.terminate(nil)
    }

    /// Right-click is a direct action with no menu, which is undiscoverable.
    /// A brief squeeze confirms that something happened.
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
        refreshIcon()
    }

    // MARK: - Clocks

    /// The system tells us when the power source changes. No polling.
    private func startEventDrivenUpdates() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ raw in
            guard let raw else { return }
            let controller = Unmanaged<StatusItemController>.fromOpaque(raw).takeUnretainedValue()
            controller.sampleNow()
        }, context)?.takeRetainedValue() else { return }
        powerSourceRunLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
    }

    private func startHistoryClock() {
        historyTimer = Timer.scheduledTimer(withTimeInterval: Self.historyInterval, repeats: true) { [weak self] _ in
            self?.sampleNow()
        }
    }

    private func startDisplayClock() {
        displayTimer = Timer.scheduledTimer(withTimeInterval: Self.displayInterval, repeats: true) { [weak self] _ in
            self?.sampleNow()
        }
    }

    private func stopDisplayClock() {
        displayTimer?.invalidate()
        displayTimer = nil
    }

    fileprivate func sampleNow() {
        guard let fresh = BatterySampler.sample() else {
            // Keep the last good snapshot. A dropped read should not blank
            // the icon.
            isDegraded = true
            refreshIcon()
            return
        }
        isDegraded = false
        snapshot = fresh
        history.append(fresh.totalInputW)
        refreshIcon()
    }

    private func refreshIcon() {
        statusItem.button?.image = BatteryIcon.image(
            for: snapshot,
            mode: EnergyModeController.current,
            pressed: pressed
        )
        statusItem.button?.alphaValue = isDegraded ? 0.45 : 1.0
    }
}
