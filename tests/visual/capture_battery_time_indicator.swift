import AppKit
import CryptoKit

/// Four production runtime sections in an owned fixture window. Captures the
/// actual WindowServer output, including Core Animation's presentation layers.
@main
private enum CaptureBatteryTimeIndicator {
    static func main() {
        guard CommandLine.arguments.count == 2 else { exit(64) }
        let defaults = MemoryDefaults()
        Settings.configureForTest(defaults: defaults)
        Settings.checksForUpdatesOnLaunch = false
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = Probe(directory: URL(fileURLWithPath: CommandLine.arguments[1]))
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

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

private final class Probe: NSObject, NSApplicationDelegate {
    private let directory: URL
    private var windows: [NSWindow] = []
    private var rows: [PopoverRuntimeView] = []
    private var records: [[String: Any]] = []
    private var assertions = 0
    private let fixtures: [(String, PowerSnapshot)] = [
        ("System · macOS", .init(percent: 67, batteryW: -12, systemW: 12,
                                batteryTimeEstimate: .remaining(265), batteryTimeEstimateSource: .system)),
        ("Fallback · Battery controller", .init(percent: 67, batteryW: -12, systemW: 12,
                                               batteryTimeEstimate: .remaining(265), batteryTimeEstimateSource: .batteryGauge)),
        ("Calculating", .init(percent: 67, batteryW: -12, systemW: 12,
                             batteryTimeEstimate: .remaining(nil))),
        ("Unavailable", .init(percent: 67, batteryW: -12, systemW: 12)),
    ]

    init(directory: URL) { self.directory = directory }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 50) { [weak self] in
            self?.stop()
            fputs("BatteryTimeProbe: watchdog expired\n", stderr)
            exit(1)
        }
        Task { @MainActor in
            do {
                try await run()
                stop()
                NSApp.terminate(nil)
            } catch {
                fputs("BatteryTimeProbe: \(error)\n", stderr)
                stop()
                exit(1)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) { stop() }

    private func stop() {
        rows.forEach { $0.setPresentationActive(false); $0.setAnimationsEnabled(false) }
        rows.removeAll()
        windows.reversed().forEach { $0.close() }
        windows.removeAll()
    }

    @MainActor private func run() async throws {
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("frames"), withIntermediateDirectories: true)
        guard let screen = NSScreen.main else { throw failure("No GUI screen") }
        let background = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        background.isReleasedWhenClosed = false
        background.isRestorable = false
        background.hasShadow = false
        background.isOpaque = true
        windows.append(background)
        background.orderFrontRegardless()
        let size = NSSize(width: PopoverStyle.width, height: 4 * (PopoverRuntimeView.preferredHeight + 24) + 24)
        let window = NSWindow(contentRect: NSRect(x: screen.frame.midX - size.width / 2,
                                                 y: screen.frame.midY - size.height / 2,
                                                 width: size.width, height: size.height),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.hasShadow = false
        window.isOpaque = true
        windows.append(window)
        let content = FlippedView(frame: NSRect(origin: .zero, size: size))
        window.contentView = content
        for (index, fixture) in fixtures.enumerated() {
            let top = 12 + CGFloat(index) * (PopoverRuntimeView.preferredHeight + 24)
            let label = NSTextField(labelWithString: fixture.0)
            label.font = .systemFont(ofSize: 11, weight: .medium)
            label.textColor = .secondaryLabelColor
            label.frame = NSRect(x: 16, y: top, width: PopoverStyle.contentWidth, height: 16)
            content.addSubview(label)
            let row = PopoverRuntimeView()
            row.frame = NSRect(x: PopoverStyle.sideInset, y: top + 20,
                               width: PopoverStyle.contentWidth, height: PopoverRuntimeView.preferredHeight)
            content.addSubview(row)
            row.update(snapshot: fixture.1, degraded: false)
            rows.append(row)
        }
        for scheme in [Settings.ColorScheme.light, .dark] {
            Settings.colorScheme = scheme
            NSApp.appearance = scheme.appearance
            window.appearance = scheme.appearance
            background.backgroundColor = scheme == .light ? .init(white: 0.88, alpha: 1) : .init(white: 0.14, alpha: 1)
            window.appearance?.performAsCurrentDrawingAppearance { window.backgroundColor = PopoverStyle.surface }
            window.orderFrontRegardless()
            for (index, row) in rows.enumerated() {
                row.refreshAppearance()
                row.update(snapshot: fixtures[index].1, degraded: false)
                row.setPresentationActive(true)
                row.setAnimationsEnabled(true)
                try check(row.layoutFitsForTest(snapshot: fixtures[index].1), "Runtime layout does not fit")
            }
            try await pause(0.25)
            try check(animationCount(rows[0].layer) == 0, "System indicator should remain steady")
            try check(animationCount(rows[1].layer) > 0, "Fallback indicator is not breathing")
            try check(animationCount(rows[2].layer) > 0, "Calculating indicator is not animated")
            try check(animationCount(rows[3].layer) > 0, "Unavailable indicator is not animated")
            try capture(window, background: background, name: "states-\(scheme.rawValue)", elapsed: nil)
        }
        // Restart only the fixture's presentation so the saved sequence begins
        // with the first lap and includes the shared half-second pauses.
        rows.forEach { $0.setPresentationActive(false) }
        rows.forEach { $0.setPresentationActive(true) }
        let start = CACurrentMediaTime()
        for frame in 0..<96 {
            let target = start + Double(frame) / 8
            let wait = target - CACurrentMediaTime()
            if wait > 0 { try await pause(wait) }
            try capture(window, background: background, name: String(format: "frames/frame-%03d", frame),
                        elapsed: CACurrentMediaTime() - start)
        }
        let frameHashes = records.filter { $0["elapsedSeconds"] != nil }.compactMap { $0["imageSHA256"] as? String }
        try check(Set(frameHashes).count > 1, "WindowServer sequence contains no visible change")
        rows.forEach { $0.setPresentationActive(false) }
        try check(rows.allSatisfy { animationCount($0.layer) == 0 }, "Ending presentation retained animations")
        let evidence: [String: Any] = [
            "schema": 1, "assertions": assertions, "failures": 0, "cases": records,
            "framesPerSecond": 8, "frameCount": 96,
            "method": "WindowServer capture of four production PopoverRuntimeView instances in an owned Classic fixture window, light and dark, followed by 12 seconds of live Core Animation output in dark appearance.",
            "limitations": "Fixture labels and container are for comparison only. Battery values and sources are deterministic fixtures. This does not validate hardware telemetry or native popup compositing.",
        ]
        try JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("evidence.json"), options: .atomic)
        print("Battery time indicator: \(records.count) captures, \(assertions) assertions, 0 failures")
    }

    private func capture(_ window: NSWindow, background: NSWindow, name: String, elapsed: Double?) throws {
        guard let screen = window.screen else { throw failure("No capture screen") }
        let bounds = window.frame
        let region = NSRect(x: bounds.minX, y: screen.frame.maxY - bounds.maxY, width: bounds.width, height: bounds.height)
        guard window.isVisible,
              let image = WattsonCaptureOwnedWindows(region, CGWindowID(window.windowNumber), CGWindowID(background.windowNumber)),
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { throw failure("WindowServer capture refused") }
        try png.write(to: directory.appendingPathComponent(name + ".png"), options: .atomic)
        var record: [String: Any] = ["image": name + ".png", "pixels": [image.width, image.height],
                                    "imageSHA256": SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined()]
        if let elapsed { record["elapsedSeconds"] = elapsed }
        records.append(record)
    }

    private func animationCount(_ layer: CALayer?) -> Int {
        guard let layer else { return 0 }
        return (layer.animationKeys()?.count ?? 0) + (layer.sublayers ?? []).reduce(0) { $0 + animationCount($1) }
    }
    private func pause(_ seconds: Double) async throws { try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
    private func check(_ passed: Bool, _ message: String) throws { assertions += 1; if !passed { throw failure(message) } }
    private func failure(_ message: String) -> NSError { NSError(domain: "BatteryTimeProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
