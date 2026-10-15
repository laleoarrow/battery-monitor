import AppKit
import ScreenCaptureKit

/// Disposable GUI-session probe. Uses the shipping controller and content; only
/// the panel's optical margin changes. No sampler, helper, or persistent defaults.
@main
private enum CaptureGlassShadow {
    static func main() {
        guard CommandLine.arguments.count >= 2 else {
            fputs("usage: GlassShadowProbe OUTPUT_DIRECTORY [--sck|--owned-cg] [--quick]\n", stderr)
            exit(2)
        }
        guard #available(macOS 26.0, *) else { exit(2) }
        let defaults = MemoryDefaults()
        Settings.configureForTest(defaults: defaults)
        Settings.liquidGlassEnabled = true
        Settings.liquidGlassTransparency = 1
        Settings.checksForUpdatesOnLaunch = false
        Settings.Module.allCases.forEach { Settings.setModule($0, visible: true) }
        // This process owns the override; no accessibility preference changes.
        setenv("WATTSON_FORCE_REDUCE_MOTION", "1", 1)
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = ProbeDelegate(directory: URL(fileURLWithPath: CommandLine.arguments[1]),
                                     usesSCK: CommandLine.arguments.contains("--sck"))
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
    private let usesSCK: Bool
    private var controller: PopoverController?
    private var backdrop: NSWindow?
    private let anchor = NSStatusBarButton(frame: .zero)

    init(directory: URL, usesSCK: Bool) {
        self.directory = directory
        self.usesSCK = usesSCK
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            do {
                try await run()
                shutdown()
                NSApp.terminate(nil)
            } catch {
                fputs("GLASS_SHADOW_PROBE_FAILED: \(error)\n", stderr)
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
    }

    @MainActor private func run() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let screen = NSScreen.main else { throw failure("No screen") }
        if usesSCK && !CGPreflightScreenCaptureAccess() {
            throw failure("Existing screen capture permission required; no permission prompt is requested")
        }
        let background = NSWindow(contentRect: screen.visibleFrame, styleMask: .borderless,
                                  backing: .buffered, defer: false)
        background.title = "Wattson glass optical margin — controlled backdrop"
        background.isReleasedWhenClosed = false
        background.isRestorable = false
        background.hasShadow = false
        background.isOpaque = true
        backdrop = background
        anchor.frame = NSRect(x: background.contentView!.bounds.midX - 12,
                              y: background.contentView!.bounds.height - 144,
                              width: 24, height: 24)
        background.contentView!.addSubview(anchor)
        background.orderFrontRegardless()

        let sample = PowerSnapshot(percent: 72, plugged: true, adapterW: 68,
            batteryW: 22.2, systemW: 45.8, temperatureC: 34.2, cycleCount: 282,
            lowPowerMode: false, batteryTimeEstimate: .charging(42))
        let history = (0..<32).map { sample.totalInputW * (0.88 + 0.08 * sin(Double($0) * 0.4)) }
        var fixedSize: NSSize?

        for scheme in [Settings.ColorScheme.light, .dark] {
            Settings.colorScheme = scheme
            NSApp.appearance = scheme.appearance
            let level: CGFloat = scheme == .light ? 0.85 : 0.15
            background.backgroundColor = NSColor(srgbRed: level, green: level, blue: level, alpha: 1)
            let quick = CommandLine.arguments.contains("--quick")
            for style in quick ? [Settings.LiquidGlassStyle.regular] : [.regular, .clear] {
                Settings.liquidGlassStyle = style
                let popover = PopoverController()
                controller = popover
                popover.update(snapshot: sample, history: history, peak: sample.totalInputW, degraded: false)
                popover.updateSystemBatteryIconState(false)
                popover.openForSettingsCommandTest(relativeTo: anchor)
                // AppKit first posts an anchor-window occlusion notification
                // when the panel appears. Let its production placement settle
                // before replacing geometry for the controlled experiment.
                try await Task.sleep(nanoseconds: 1_000_000_000)
                guard let panel = popover.glassPanelForTest,
                      let root = panel.contentView,
                      let content = popover.contentViewForTest,
                      let glass = root.subviews.compactMap({ $0 as? NSGlassEffectView }).first,
                      root.subviews.count == 3 else { throw failure("Production glass host unavailable") }
                popover.stopEntranceAnimationForTest()
                content.layer?.removeAllAnimations()
                let size = content.frame.size
                if let fixedSize, fixedSize != size { throw failure("Content size changed across samples") }
                fixedSize = size
                let fixedContent = NSRect(x: floor(screen.visibleFrame.midX - size.width / 2),
                    y: floor(screen.visibleFrame.midY - size.height / 2), width: size.width, height: size.height)
                for margin: CGFloat in quick ? [10, 32] : [10, 20, 32, 48] {
                    let requestedFrame = fixedContent.insetBy(dx: -margin, dy: -margin)
                    var stable = false
                    for _ in 0..<3 {
                        panel.setFrame(requestedFrame, display: false)
                        for sibling in root.subviews {
                            sibling.frame = root.bounds.insetBy(dx: margin, dy: margin)
                        }
                        panel.makeKeyAndOrderFront(nil)
                        root.layoutSubtreeIfNeeded()
                        panel.displayIfNeeded()
                        try await Task.sleep(nanoseconds: 800_000_000)
                        let expected = NSRect(x: margin, y: margin, width: size.width, height: size.height)
                        if panel.frame == requestedFrame && root.subviews.allSatisfy({ $0.frame == expected }) {
                            stable = true
                            break
                        }
                    }
                    guard stable else { throw failure("Panel or sibling geometry changed after settling") }
                    let name = "\(style.rawValue)-\(scheme.rawValue)-margin-\(Int(margin))"
                    let windowFrame = panel.frame
                    let cgFrame = NSRect(x: windowFrame.minX, y: screen.frame.maxY - windowFrame.maxY,
                                         width: windowFrame.width, height: windowFrame.height)
                    let marker: [String: Any] = [
                        "name": name, "window": panel.windowNumber,
                        "margin": margin, "panelFrameAppKit": rect(windowFrame),
                        "panelFrameCG": rect(cgFrame), "captureRectCG": rect(cgFrame.insetBy(dx: -8, dy: -8)),
                        "glassFrameAppKit": rect(panel.convertToScreen(glass.convert(glass.bounds, to: nil))),
                        "contentSize": [content.frame.width, content.frame.height],
                        "siblingFramesMatch": root.subviews.allSatisfy { $0.frame == glass.frame },
                        "backdropSRGB": [level, level, level], "hasWindowShadow": panel.hasShadow,
                        "contentFrameMatchesGlass": content.frame == glass.frame,
                        "limitations": "Fixed charging fixture; geometry-only optical margin experiment using production views. External capture must include the backdrop and 8pt outside the panel, not alpha-only window extraction."
                    ]
                    try write(marker, named: name + "-geometry.json")
                    if usesSCK { try await capture(panel, name: name) }
                    else if CommandLine.arguments.contains("--owned-cg") {
                        guard let image = WattsonCaptureOwnedWindows(cgFrame.insetBy(dx: -8, dy: -8),
                            CGWindowID(panel.windowNumber), CGWindowID(background.windowNumber))
                        else { throw failure("WindowServer refused capture of the probe's own windows") }
                        try save(image, name: name)
                    }
                    else {
                        try write(marker, named: "frame.json")
                        let receipt = directory.appendingPathComponent(name + ".captured")
                        var received = false
                        for _ in 0..<600 {
                            if FileManager.default.fileExists(atPath: receipt.path) { received = true; break }
                            try await Task.sleep(nanoseconds: 100_000_000)
                        }
                        guard received else { throw failure("External capture timed out: \(name)") }
                    }
                    print("GLASS_SHADOW_CAPTURED: \(name)")
                    fflush(stdout)
                }
                popover.handleOutsideClick()
                controller = nil
                try await Task.sleep(nanoseconds: 400_000_000)
            }
        }
        try write(["complete": true, "captures": CommandLine.arguments.contains("--quick") ? 4 : 16],
                  named: "complete.json")
    }

    @MainActor private func capture(_ target: NSWindow, name: String) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard let app = content.applications.first(where: { $0.processID == ProcessInfo.processInfo.processIdentifier }),
              let item = content.windows.first(where: { $0.windowID == CGWindowID(target.windowNumber) }),
              let display = content.displays.first(where: { $0.frame.contains(item.frame.insetBy(dx: -8, dy: -8)) })
        else { throw failure("Full composited window unavailable") }
        let bounds = item.frame.insetBy(dx: -8, dy: -8)
        let config = SCStreamConfiguration()
        config.sourceRect = bounds.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
        config.width = Int(bounds.width * CGFloat(display.width) / display.frame.width)
        config.height = Int(bounds.height * CGFloat(display.height) / display.frame.height)
        config.showsCursor = false
        config.capturesAudio = false
        let filter = SCContentFilter(display: display, including: [app], exceptingWindows: [])
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        try save(image, name: name)
    }

    private func save(_ image: CGImage, name: String) throws {
        let bitmap = NSBitmapImageRep(cgImage: image)
        // A refused legacy capture can be a transparent image rather than nil.
        guard let color = bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2),
              color.alphaComponent > 0 else { throw failure("WindowServer returned an empty capture") }
        guard let png = bitmap.representation(using: .png, properties: [:])
        else { throw failure("PNG encoding failed") }
        try png.write(to: directory.appendingPathComponent(name + ".png"), options: .atomic)
    }

    private func rect(_ frame: NSRect) -> [CGFloat] { [frame.minX, frame.minY, frame.width, frame.height] }
    private func write(_ object: [String: Any], named name: String) throws {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .prettyPrinted])
            .write(to: directory.appendingPathComponent(name), options: .atomic)
    }
    private func failure(_ message: String) -> NSError {
        NSError(domain: "WattsonGlassShadowProbe", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message])
    }
}
