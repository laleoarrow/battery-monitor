import AppKit

@main enum RenderPowerIcons {
    static let fixtures: [(String, PowerSnapshot)] = [
        ("Charging", PowerSnapshot(percent: 58, plugged: true, adapterW: 65, batteryW: 25, systemW: 40)),
        ("Plugged In · Full", PowerSnapshot(percent: 100, plugged: true, adapterW: 29, batteryW: 0, systemW: 29)),
        ("On Battery", PowerSnapshot(percent: 61, plugged: false, batteryW: -29, systemW: 29)),
        ("Mixed Supply", PowerSnapshot(percent: 44, plugged: true, adapterW: 30, batteryW: -12, systemW: 42)),
        ("Low Battery", PowerSnapshot(percent: 9, plugged: false, batteryW: -18, systemW: 18)),
        ("Low Power", PowerSnapshot(percent: 45, plugged: false, batteryW: -12, systemW: 12, lowPowerMode: true)),
    ]

    static func main() throws {
        guard CommandLine.arguments.count == 2 else { exit(64) }
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        try render(to: output.appendingPathComponent("power-vector-preview.png"), fixtureCount: 4)
        try render(to: output.appendingPathComponent("power-state-matrix.png"), fixtureCount: 6)
        print("Rendered production Flow and Lane icon images offscreen in their real theme/state palettes.")
    }

    static func render(to destination: URL, fixtureCount: Int) throws {
        let width = 1400, rowHeight = 128, header = 48
        let groupHeight = fixtureCount * rowHeight + header
        let height = groupHeight * 2
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)!
        defer { NSGraphicsContext.restoreGraphicsState() }
        let columns = ["Adapter", "System", "Battery", "Lane · System", "Lane · Battery"]
        for (group, appearanceName) in [NSAppearance.Name.darkAqua, .aqua].enumerated() {
            let dark = group == 0
            let base = CGFloat(1 - group) * CGFloat(groupHeight)
            let appearance = NSAppearance(named: appearanceName)!
            appearance.performAsCurrentDrawingAppearance {
                let background = dark ? NSColor(srgbRed: 0.12, green: 0.125, blue: 0.135, alpha: 1)
                    : NSColor(srgbRed: 0.96, green: 0.96, blue: 0.97, alpha: 1)
                let ink = PopoverStyle.primaryText.usingColorSpace(.sRGB)!
                background.setFill()
                NSRect(x: 0, y: base, width: CGFloat(width), height: CGFloat(groupHeight)).fill()
                let heading: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 16, weight: .semibold), .foregroundColor: ink,
                ]
                (dark ? "Dark" : "Light" as NSString).draw(
                    at: NSPoint(x: 22, y: base + CGFloat(groupHeight) - 32), withAttributes: heading)
                for (index, title) in columns.enumerated() {
                    let text = title as NSString
                    let center = CGFloat(index) * 230 + 270
                    text.draw(at: NSPoint(x: center - text.size(withAttributes: heading).width / 2,
                                           y: base + CGFloat(groupHeight) - 32), withAttributes: heading)
                }
                let flow = PowerFlowView()
                let lanes = LaneView()
                flow.appearance = appearance
                lanes.appearance = appearance
                for (row, fixture) in fixtures.prefix(fixtureCount).enumerated() {
                    let y = base + CGFloat(fixtureCount - row - 1) * CGFloat(rowHeight)
                    flow.update(snapshot: fixture.1, animated: false)
                    lanes.update(snapshot: fixture.1)
                    let nodes = flow.nodeIconImagesForTest
                    let images = [nodes[0], nodes[2], nodes[1]] + lanes.iconImagesForTest
                    let attributes: [NSAttributedString.Key: Any] = [
                        .font: NSFont.systemFont(ofSize: 16, weight: .medium), .foregroundColor: ink,
                    ]
                    (fixture.0 as NSString).draw(at: NSPoint(x: 22, y: y + 59), withAttributes: attributes)
                    for (index, image) in images.enumerated() {
                        guard let image else { fatalError("Missing production icon") }
                        let center = CGFloat(index) * 230 + 270
                        let size: CGFloat = index < 3 ? 96 : 72
                        let presence: CGFloat = index == 0 && fixture.1.state == .onBattery ? 0.28
                            : index == 2 && fixture.1.state == .pluggedIdle ? 0.6 : 1
                        image.draw(in: NSRect(x: center - size / 2, y: y + 66 - size / 2,
                                               width: size, height: size), from: .zero,
                                   operation: .sourceOver, fraction: presence)
                        image.draw(in: NSRect(x: center - image.size.width / 2,
                                               y: y + 18 - image.size.height / 2,
                                               width: image.size.width, height: image.size.height),
                                   from: .zero, operation: .sourceOver, fraction: presence)
                    }
                }
            }
        }
        guard let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
        try png.write(to: destination, options: .atomic)
    }
}
