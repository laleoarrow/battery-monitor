import AppKit
import Foundation

/// Renders one production PowerFlowView state without ordering a window front.
/// This keeps icon and topology QA off the active desktop.
@main
private enum CapturePowerFlowFixture {
    static func main() {
        guard CommandLine.arguments.count == 3 else {
            fputs("usage: capture_power_flow_fixture charging|idle|battery|mixed OUTPUT.png\n", stderr)
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
        root.layer?.backgroundColor = PopoverStyle.surface.cgColor
        root.appearance = NSAppearance(named: .darkAqua)
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
