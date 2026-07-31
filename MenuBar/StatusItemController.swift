import AppKit
import IOKit.ps

final class StatusItemController: NSObject {
    private static let historyInterval: TimeInterval = 2
    private static let displayInterval: TimeInterval = 1

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
        button.target = self
        button.action = #selector(handleClick)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
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
        guard let button = statusItem.button else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            let ok = EnergyModeController.toggle()
            confirmToggle(success: ok)
        } else {
            popover.toggle(relativeTo: button)
        }
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
        guard let fresh = BatterySampler.sample() else { return }
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
    }
}
