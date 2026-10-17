import AppKit

/// View-owned artwork proof. It creates no application, window or sampling task.
@main enum RenderProcessPreview {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else { exit(64) }
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        let fixtures = [
            EnergyProcess(pid: 101, name: "Safari", energyImpact: 84, cpuPercent: 72, idleWakeupsPerSecond: 240),
            EnergyProcess(pid: 102, name: "WindowServer", energyImpact: 46, cpuPercent: 31, idleWakeupsPerSecond: 300),
            EnergyProcess(pid: 103, name: "backupd", energyImpact: 8.1, cpuPercent: 8, idleWakeupsPerSecond: 2),
        ]
        for (name, appearanceName) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let appearance = NSAppearance(named: appearanceName)!
            for compact in [false, true] {
                var png: Data!
                appearance.performAsCurrentDrawingAppearance {
                    let view = TopProcessesView()
                    view.appearance = appearance
                    view.frame.size = NSSize(width: 328, height: TopProcessesView.preferredHeight(count: 3, compact: compact))
                    view.update(state: .ready(fixtures), count: 3, compact: compact)
                    view.refreshAppearance()
                    view.layoutSubtreeIfNeeded()
                    let scale: CGFloat = 2
                    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                        pixelsWide: Int(view.bounds.width * scale), pixelsHigh: Int(view.bounds.height * scale),
                        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                    bitmap.size = view.bounds.size
                    NSGraphicsContext.saveGraphicsState()
                    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
                    NSGraphicsContext.current = context
                    context.cgContext.scaleBy(x: scale, y: scale)
                    PopoverStyle.surface.setFill()
                    view.bounds.fill()
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    NSGraphicsContext.restoreGraphicsState()
                    png = bitmap.representation(using: .png, properties: [:])
                }
                guard let png else { exit(1) }
                let mode = compact ? "compact" : "detailed"
                try png.write(to: output.appendingPathComponent("process-\(mode)-\(name).png"), options: .atomic)
            }
        }
        print("Rendered Process Activity offscreen from production views with fixed illustrative data; no window or preferences used.")
    }
}
