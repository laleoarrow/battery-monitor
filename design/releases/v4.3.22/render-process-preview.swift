import AppKit

/// View-owned production proof; no app/window, live reader, helper or signal.
@main enum RenderProcessPreview {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else { exit(64) }
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        var token = audit_token_t()
        token.val.5 = 990_101
        let identity = ProcessIdentity(pid: 990_101, startedAt: 1,
                                      auditToken: withUnsafeBytes(of: token) { Data($0) })
        precondition(identity.isValid)
        let fixtures = [
            EnergyProcess(pid: 990_101, name: "Safari", energyImpact: 84, cpuPercent: 72,
                          idleWakeupsPerSecond: 240, terminationIdentity: identity),
            EnergyProcess(pid: 990_102, name: "Research Helper", energyImpact: 46, cpuPercent: 31,
                          idleWakeupsPerSecond: 300),
            EnergyProcess(pid: 990_103, name: "backupd", energyImpact: 8.1, cpuPercent: 8,
                          idleWakeupsPerSecond: 2),
        ]
        let snapshot = PowerSnapshot(percent: 58, plugged: true, adapterW: 65, batteryW: 25, systemW: 40)
        // Same chart palette selection as PopoverContentView's Process Activity branch.
        let color = snapshot.state == .mixedSupply ? PopoverStyle.blue : PopoverStyle.stateColor(snapshot.state)
        for (name, appearanceName) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let appearance = NSAppearance(named: appearanceName)!
            for compact in [false, true] {
                var png: Data!
                appearance.performAsCurrentDrawingAppearance {
                    let view = TopProcessesView()
                    view.appearance = appearance
                    view.frame.size = NSSize(width: 328, height: TopProcessesView.preferredHeight(count: 3, compact: compact))
                    view.update(state: .ready(fixtures), count: 3, compact: compact, color: color)
                    view.refreshAppearance()
                    view.layoutSubtreeIfNeeded()
                    precondition(view.processRowsForTest[0].accessibilityPerformPress())
                    view.layoutSubtreeIfNeeded()
                    precondition(view.selectedRowIndexForTest == 0)
                    let button = view.forceQuitButtonsForTest[0] as! ProcessActionButton
                    precondition(button.isEnabled && button.frame.size == NSSize(width: 38, height: 16))
                    let track = view.processRowsForTest[0].layer!.sublayers!.first { $0.name == "top-processes.track" }!
                    let gradient = track.sublayers!.compactMap { $0 as? CAGradientLayer }.first!
                    let colors = gradient.colors as! [CGColor]
                    let endpoint = NSColor(cgColor: colors[2])!.usingColorSpace(.sRGB)!
                    let actual = button.tintColor.usingColorSpace(.sRGB)!
                    precondition(abs(endpoint.redComponent - actual.redComponent) < 0.00001)
                    precondition(abs(endpoint.greenComponent - actual.greenComponent) < 0.00001)
                    precondition(abs(endpoint.blueComponent - actual.blueComponent) < 0.00001)
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
        print("Four production offscreen Process Activity proofs: charging fixture, selected eligible action, 38x16 bounds and endpoint tint verified; no window or system changes.")
    }
}
