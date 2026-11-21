import AppKit
import Foundation

/// Renders one production PowerFlowView state without ordering a window front.
/// This keeps icon and topology QA off the active desktop.
@main
private enum CapturePowerFlowFixture {
    static func main() {
        guard [3, 4].contains(CommandLine.arguments.count) else {
            fputs("usage: capture_power_flow_fixture STATE OUTPUT.png [dark|light]\n", stderr)
            exit(2)
        }

        let snapshot: PowerSnapshot
        switch CommandLine.arguments[1] {
        case "charging":
            snapshot = PowerSnapshot(
                percent: 72,
                plugged: true,
                adapterW: 68,
                batteryW: 22.2,
                systemW: 45.8,
                temperatureC: 34.2,
                cycleCount: 116,
                lowPowerMode: false
            )
        case "charging-device":
            snapshot = PowerSnapshot(percent: 72, plugged: true, adapterW: 68,
                batteryW: 22.2, systemW: 45.8, deviceOutputW: 7.5,
                systemChargingState: .charging)
        case "mixed-device":
            snapshot = PowerSnapshot(percent: 44, plugged: true, adapterW: 30,
                batteryW: -9.7, systemW: 39.7, deviceOutputW: 12.2)
        case "deadband-device":
            snapshot = PowerSnapshot(percent: 72, plugged: true, adapterW: 31.8,
                batteryW: -0.2, systemW: 32, deviceOutputW: 7.5,
                systemChargingState: .charging)
        case "zero-adapter-device":
            snapshot = PowerSnapshot(percent: 44, plugged: true,
                batteryW: -20, systemW: 20, deviceOutputW: 5)
        case "zero-mac-device":
            snapshot = PowerSnapshot(percent: 44, plugged: true, adapterW: 10,
                batteryW: -10, systemW: 20, deviceOutputW: 20)
        case "partial-device":
            snapshot = PowerSnapshot(percent: 72, plugged: true, adapterW: 68,
                batteryW: 22.2, systemW: 45.8, deviceOutputW: 7.5,
                deviceOutputIsComplete: false)
        case "incoherent-device":
            snapshot = PowerSnapshot(percent: 72, plugged: true, adapterW: 68,
                batteryW: 22.2, systemW: 45.8, deviceOutputW: 50)
        case "idle":
            snapshot = PowerSnapshot(
                percent: 100,
                plugged: true,
                adapterW: 52,
                batteryW: 0,
                systemW: 52,
                temperatureC: 31.8,
                cycleCount: 116,
                lowPowerMode: false
            )
        case "idle-device":
            snapshot = PowerSnapshot(
                percent: 100,
                plugged: true,
                adapterW: 48.7,
                batteryW: 0,
                systemW: 48.7,
                deviceOutputW: 14.083,
                temperatureC: 35.7,
                cycleCount: 282,
                lowPowerMode: false
            )
        case "battery":
            snapshot = PowerSnapshot(
                percent: 41,
                plugged: false,
                adapterW: 0,
                batteryW: -36.9,
                systemW: 36.9,
                temperatureC: 33.1,
                cycleCount: 116,
                lowPowerMode: false
            )
        case "battery-device":
            snapshot = PowerSnapshot(
                percent: 67,
                plugged: false,
                adapterW: 0,
                batteryW: -39.7,
                systemW: 39.7,
                deviceOutputW: 12.2,
                temperatureC: 33.1,
                cycleCount: 116,
                lowPowerMode: false
            )
        case "battery-device-low":
            snapshot = PowerSnapshot(
                percent: 14,
                plugged: false,
                adapterW: 0,
                batteryW: -57.1,
                systemW: 57.1,
                deviceOutputW: 0.1,
                temperatureC: 32.4,
                cycleCount: 116,
                lowPowerMode: true
            )
        case "mixed":
            snapshot = PowerSnapshot(
                percent: 18,
                plugged: true,
                adapterW: 28,
                batteryW: -31.7,
                systemW: 59.7,
                temperatureC: 38.6,
                cycleCount: 116,
                lowPowerMode: false
            )
        case "website":
            snapshot = PowerSnapshot(
                percent: 100,
                plugged: true,
                adapterW: 41.7,
                batteryW: 0,
                systemW: 41.7,
                temperatureC: 33.8,
                cycleCount: 278,
                lowPowerMode: false
            )
        default:
            fputs("unknown fixture state\n", stderr)
            exit(2)
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()

        let flow = PowerFlowView()
        let root = NSView(frame: NSRect(
            x: 0,
            y: 0,
            width: PopoverStyle.contentWidth,
            height: PowerFlowView.preferredHeight
        ))
        root.wantsLayer = true
        let theme = CommandLine.arguments.count == 4 ? CommandLine.arguments[3] : "dark"
        guard ["dark", "light"].contains(theme) else { exit(64) }
        root.appearance = NSAppearance(named: theme == "light" ? .aqua : .darkAqua)
        root.appearance?.performAsCurrentDrawingAppearance {
            root.layer?.backgroundColor = PopoverStyle.surface.cgColor
        }
        flow.frame = root.bounds
        root.addSubview(flow)
        flow.update(snapshot: snapshot, animated: false)
        root.layoutSubtreeIfNeeded()
        root.displayIfNeeded()

        guard let bitmap = root.bitmapImageRepForCachingDisplay(in: root.bounds) else {
            fputs("could not allocate capture bitmap\n", stderr)
            exit(2)
        }
        root.cacheDisplay(in: root.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            fputs("could not encode capture PNG\n", stderr)
            exit(2)
        }
        do {
            try png.write(
                to: URL(fileURLWithPath: CommandLine.arguments[2]),
                options: .atomic
            )
        } catch {
            fputs("could not write capture PNG: \(error)\n", stderr)
            exit(2)
        }
    }
}
