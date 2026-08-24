#if DEBUG
import AppKit

final class PopoverPreviewWindowController: NSWindowController {
    private let content = PopoverContentViewController()

    init(state: String, appearance: String?) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: PopoverStyle.width, height: content.preferredHeight),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Wattson Popover Preview"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        if appearance == "light" {
            panel.appearance = NSAppearance(named: .aqua)
        } else if appearance == "dark" {
            panel.appearance = NSAppearance(named: .darkAqua)
        }
        panel.contentViewController = content
        panel.setContentSize(NSSize(width: PopoverStyle.width, height: content.preferredHeight))
        super.init(window: panel)

        content.heightDidChange = { [weak panel] height in
            guard let panel else { return }
            panel.setContentSize(NSSize(width: PopoverStyle.width, height: height))
        }

        let snapshot = Self.snapshot(for: state)
        let history = (0..<60).map { index in
            snapshot.totalInputW * (0.56 + 0.36 * sin(Double(index) * 0.23))
        }
        content.update(
            snapshot: snapshot,
            history: history,
            peak: history.max() ?? snapshot.totalInputW,
            degraded: false
        )
        content.setModeSelectHandler { mode, completion in completion(mode) }
        content.setSystemBatteryIconToggleHandler { _, completion in completion(true) }
        content.updateSystemBatteryIconState(false)
        content.setAnimationsEnabled(true)
        panel.center()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func snapshot(for state: String) -> PowerSnapshot {
        switch state {
        case "charging":
            return PowerSnapshot(percent: 72, plugged: true, adapterW: 68, batteryW: 22.2, systemW: 45.8, temperatureC: 34.2, cycleCount: 116, lowPowerMode: false)
        case "device":
            return PowerSnapshot(percent: 72, plugged: true, adapterW: 68, batteryW: 22.2, systemW: 45.8, deviceOutputW: 7.5, temperatureC: 34.2, cycleCount: 116, lowPowerMode: false)
        case "battery":
            return PowerSnapshot(percent: 41, plugged: false, adapterW: 0, batteryW: -36.9, systemW: 36.9, temperatureC: 33.1, cycleCount: 116, lowPowerMode: false)
        case "battery-device":
            return PowerSnapshot(percent: 67, plugged: false, adapterW: 0, batteryW: -39.7, systemW: 39.7, deviceOutputW: 12.2, temperatureC: 33.1, cycleCount: 116, lowPowerMode: false)
        case "mixed":
            return PowerSnapshot(percent: 18, plugged: true, adapterW: 28, batteryW: -31.7, systemW: 59.7, temperatureC: 38.6, cycleCount: 116, lowPowerMode: false)
        case "high":
            return PowerSnapshot(percent: 66, plugged: true, adapterW: 140, batteryW: 32, systemW: 108, temperatureC: 41.4, cycleCount: 116, lowPowerMode: false)
        default:
            return PowerSnapshot(percent: 100, plugged: true, adapterW: 52, batteryW: 0, systemW: 52, temperatureC: 31.8, cycleCount: 116, lowPowerMode: false)
        }
    }
}
#endif
