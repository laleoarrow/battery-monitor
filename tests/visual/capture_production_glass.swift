import AppKit

/// Fixture-only production-host check for a disposable GUI VM.
/// Never changes the shipping panel/sibling geometry or system preferences.
@main
private enum CaptureProductionGlass {
    static func main() {
        guard CommandLine.arguments.count == 2, #available(macOS 26.0, *) else {
            fputs("usage: ProductionGlassProbe OUTPUT_DIRECTORY\n", stderr)
            exit(2)
        }
        let defaults = MemoryDefaults()
        Settings.configureForTest(defaults: defaults)
        Settings.liquidGlassEnabled = true
        Settings.liquidGlassTransparency = 1
        Settings.checksForUpdatesOnLaunch = false
        Settings.Module.allCases.forEach { Settings.setModule($0, visible: true) }
        setenv("WATTSON_FORCE_REDUCE_MOTION", "0", 1)
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = ProbeDelegate(directory: URL(fileURLWithPath: CommandLine.arguments[1]))
        app.delegate = delegate
        withExtendedLifetime((defaults, delegate)) { app.run() }
        Settings.resetTestConfiguration()
    }
}

private final class MemoryDefaults: UserDefaults {
    private var values: [String: Any] = [:]
    override func object(forKey key: String) -> Any? { values[key] }
    override func string(forKey key: String) -> String? { values[key] as? String }
    override func set(_ value: Any?, forKey key: String) { values[key] = value }
    override func set(_ value: Bool, forKey key: String) { values[key] = value }
    override func removeObject(forKey key: String) { values.removeValue(forKey: key) }
}

@available(macOS 26.0, *)
private final class ProbeDelegate: NSObject, NSApplicationDelegate {
    private let directory: URL
    private var controller: PopoverController?
    private var backdrop: NSWindow?
    private var item: NSStatusItem?

    init(directory: URL) { self.directory = directory }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 120) { [weak self] in
            fputs("PRODUCTION_GLASS_FAILED: 120-second GUI watchdog expired\n", stderr)
            self?.shutdown()
            exit(1)
        }
        Task { @MainActor in
            do {
                try await run()
                shutdown()
                NSApp.terminate(nil)
            } catch {
                fputs("PRODUCTION_GLASS_FAILED: \(error)\n", stderr)
                shutdown()
                exit(1)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) { shutdown() }

    private func shutdown() {
        controller?.handleOutsideClick()
        controller = nil
        backdrop?.close()
        backdrop = nil
        if let item { NSStatusBar.system.removeStatusItem(item) }
        item = nil
    }

    @MainActor private func run() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item = statusItem
        guard let anchor = statusItem.button else { throw failure("Status button unavailable") }
        anchor.image = NSImage(systemSymbolName: "battery.100", accessibilityDescription: "Wattson QA fixture")
        anchor.title = " QA"
        try await Task.sleep(nanoseconds: 600_000_000)
        guard let anchorWindow = anchor.window, anchorWindow.isVisible,
              let screen = anchorWindow.screen else { throw failure("Native status-item window unavailable") }
        let background = NSWindow(contentRect: screen.visibleFrame, styleMask: .borderless,
                                  backing: .buffered, defer: false)
        background.isReleasedWhenClosed = false
        background.isRestorable = false
        background.hasShadow = false
        background.isOpaque = true
        backdrop = background
        background.orderFrontRegardless()
        let sample = PowerSnapshot(percent: 72, plugged: true, adapterW: 68,
            batteryW: 22.2, systemW: 45.8, temperatureC: 34.2, cycleCount: 282,
            lowPowerMode: false, batteryTimeEstimate: .charging(42))
        let history = (0..<32).map { sample.totalInputW * (0.88 + 0.08 * sin(Double($0) * 0.4)) }
        var captures = 0
        for scheme in [Settings.ColorScheme.light, .dark] {
            Settings.colorScheme = scheme
            NSApp.appearance = scheme.appearance
            let level: CGFloat = scheme == .light ? 0.85 : 0.15
            background.backgroundColor = NSColor(srgbRed: level, green: level, blue: level, alpha: 1)
            for style in [Settings.LiquidGlassStyle.regular, .clear] {
                Settings.liquidGlassStyle = style
                let popover = PopoverController()
                controller = popover
                popover.update(snapshot: sample, history: history, peak: sample.totalInputW, degraded: false)
                popover.updateSystemBatteryIconState(false)
                popover.openForSettingsCommandTest(relativeTo: anchor)
                try await Task.sleep(nanoseconds: 1_200_000_000)
                guard let panel = popover.glassPanelForTest,
                      let root = panel.contentView,
                      let content = popover.contentViewForTest,
                      let glass = root.subviews.compactMap({ $0 as? NSGlassEffectView }).first,
                      let scroll = descendants(content).compactMap({ $0 as? NSScrollView }).first,
                      let document = scroll.documentView,
                      let footer = descendants(content).compactMap({ $0 as? PopoverFooterView }).first,
                      let runtime = descendants(content).compactMap({ $0 as? PopoverRuntimeView }).first
                else { throw failure("Production hierarchy unavailable") }
                // Reuse the existing preview's footer-fixture API. No helper
                // calls, pmset changes, or geometry modifications are made.
                footer.update(mode: .auto, helperInstalled: true, systemBatteryIconHidden: false,
                              tint: PopoverStyle.stateColor(sample.state))
                content.layoutSubtreeIfNeeded()
                try await Task.sleep(nanoseconds: 400_000_000)
                let scrolling = document.bounds.height > scroll.contentView.bounds.height + 1
                for position in scrolling ? ["top", "bottom"] : ["full"] {
                    if position == "bottom" {
                        scroll.contentView.scroll(to: NSPoint(x: 0,
                            y: max(0, document.bounds.height - scroll.contentView.bounds.height)))
                        scroll.reflectScrolledClipView(scroll.contentView)
                        content.layoutSubtreeIfNeeded()
                        try await Task.sleep(nanoseconds: 300_000_000)
                        let visible = scroll.documentVisibleRect.insetBy(dx: -0.5, dy: -0.5)
                        guard visible.contains(footer.convert(footer.bounds, to: document)),
                              visible.contains(runtime.convert(runtime.bounds, to: document))
                        else { throw failure("Footer or runtime unreachable in short-screen viewport") }
                    }
                    let margin = GlassPopoverPanel.contentInset(for: style)
                    let expectedSibling = root.bounds.insetBy(dx: margin, dy: margin)
                    let anchorFrame = anchorWindow.convertToScreen(anchor.convert(anchor.bounds, to: nil))
                    let glassFrame = panel.convertToScreen(glass.convert(glass.bounds, to: nil))
                    guard abs(content.frame.width - 360) < 0.01,
                          root.subviews.count == 3,
                          root.subviews.allSatisfy({ $0.frame == expectedSibling }),
                          screen.visibleFrame.insetBy(dx: -0.5, dy: -0.5).contains(panel.frame),
                          abs(panel.frame.maxY - (min(anchorFrame.minY, screen.visibleFrame.maxY) - 4)) <= 0.5,
                          abs(glassFrame.maxY - (panel.frame.maxY - margin)) <= 0.5
                    else {
                        throw failure("Production geometry failed: panel=\(panel.frame) glass=\(glassFrame) "
                            + "anchor=\(anchorFrame) screen=\(screen.visibleFrame) content=\(content.frame) "
                            + "margin=\(margin) siblings=\(root.subviews.map(\.frame))")
                    }
                    let name = "\(style.rawValue)-\(scheme.rawValue)-\(position)"
                    let cgFrame = NSRect(x: panel.frame.minX, y: screen.frame.maxY - panel.frame.maxY,
                                         width: panel.frame.width, height: panel.frame.height)
                    let region = cgFrame.insetBy(dx: -8, dy: -8)
                    guard let image = WattsonCaptureOwnedWindows(region, CGWindowID(panel.windowNumber),
                                                                 CGWindowID(background.windowNumber))
                    else { throw failure("WindowServer refused the probe's own windows") }
                    let bitmap = NSBitmapImageRep(cgImage: image)
                    guard let center = bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2),
                          center.alphaComponent > 0,
                          let png = bitmap.representation(using: .png, properties: [:])
                    else { throw failure("WindowServer returned an empty capture") }
                    try png.write(to: directory.appendingPathComponent(name + ".png"), options: .atomic)
                    let marker: [String: Any] = [
                        "name": name, "margin": margin, "window": panel.windowNumber,
                        "panelFrameAppKit": rect(panel.frame), "glassFrameAppKit": rect(glassFrame),
                        "anchorButtonFrameAppKit": rect(anchorFrame), "anchorWindowFrameAppKit": rect(anchorWindow.frame),
                        "screenFrameAppKit": rect(screen.frame), "visibleFrameAppKit": rect(screen.visibleFrame),
                        "contentSize": [content.frame.width, content.frame.height],
                        "scrollDocumentSize": [document.bounds.width, document.bounds.height],
                        "scrollDocumentVisibleRect": rect(scroll.documentVisibleRect),
                        "scrolling": scrolling, "hasVerticalScroller": scroll.hasVerticalScroller,
                        "allSiblingFramesMatch": root.subviews.allSatisfy { $0.frame == expectedSibling },
                        "footerFrameInDocument": rect(footer.convert(footer.bounds, to: document)),
                        "runtimeFrameInDocument": rect(runtime.convert(runtime.bounds, to: document)),
                        "hasWindowShadow": panel.hasShadow, "reduceMotionOverride": false,
                        "captureRectCG": rect(region), "pixels": [bitmap.pixelsWide, bitmap.pixelsHigh],
                        "limitations": "Fixed charging and simulated footer state; production status item, placement and views, no manually adjusted panel/sibling geometry. Captures own panel plus backdrop only."
                    ]
                    try write(marker, name: name + "-geometry.json")
                    print("PRODUCTION_GLASS_CAPTURED: \(name)")
                    fflush(stdout)
                    captures += 1
                }
                popover.handleOutsideClick()
                controller = nil
                try await Task.sleep(nanoseconds: 400_000_000)
            }
        }
        try write(["complete": true, "captures": captures], name: "complete.json")
    }

    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    private func rect(_ frame: NSRect) -> [CGFloat] { [frame.minX, frame.minY, frame.width, frame.height] }
    private func write(_ value: [String: Any], name: String) throws {
        try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent(name), options: .atomic)
    }
    private func failure(_ message: String) -> NSError {
        NSError(domain: "WattsonProductionGlassProbe", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message])
    }
}
