import AppKit
import CryptoKit

/// Five production runtime sections in an owned fixture window. Captures the
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
    private var activityMonitorBaseline: Set<pid_t>?
    private var activityMonitorEvidence: [String: Any] = [:]
    private let fixtures: [(String, PowerSnapshot)] = [
        ("System · macOS", .init(percent: 67, batteryW: -12, systemW: 12,
                                batteryTimeEstimate: .remaining(265), batteryTimeEstimateSource: .system)),
        ("Fallback · Battery controller", .init(percent: 67, batteryW: -12, systemW: 12,
                                               batteryTimeEstimate: .remaining(265), batteryTimeEstimateSource: .batteryGauge)),
        ("Calculating", .init(percent: 67, batteryW: -12, systemW: 12,
                             batteryTimeEstimate: .remaining(nil))),
        ("Unavailable", .init(percent: 67, batteryW: -12, systemW: 12)),
        ("Fully Charged · 3D double orbit", .init(percent: 100, plugged: true,
                                               adapterW: 21.1, systemW: 21.1,
                                               batteryTimeEstimate: .full,
                                               batteryTimeEstimateSource: .system)),
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
        guard stopActivityMonitor() else {
            fputs("BatteryTimeProbe: owned Activity Monitor did not terminate\n", stderr)
            exit(1)
        }
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
        let size = NSSize(width: PopoverStyle.width,
                          height: CGFloat(fixtures.count) * (PopoverRuntimeView.preferredHeight + 24) + 24)
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
            try check(animationCount(rows[4].layer) > 0, "Full-charge double orbit is not animated")
            try capture(window, background: background, name: "states-\(scheme.rawValue)", elapsed: nil)
            try await verifyClockHover(rows[0], window: window, background: background, scheme: scheme.rawValue)
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
        try await verifyActivityMonitorClick(rows[0], window: window)
        let evidence: [String: Any] = [
            "schema": 1, "assertions": assertions, "failures": 0, "cases": records,
            "activityMonitor": activityMonitorEvidence,
            "framesPerSecond": 8, "frameCount": 96,
            "method": "WindowServer capture of five production PopoverRuntimeView instances in an owned Classic fixture window, light and dark, followed by 12 seconds of live Core Animation output in dark appearance. Clock captures compare the original artwork with the new controls hidden, idle, two injected pointer locations delivered through the production hover handler, and exit. Native queued mouse events exercise the clock button's default Activity Monitor launch action; only a newly launched Activity Monitor is terminated.",
            "limitations": "Fixture labels and container are for comparison only. Battery values and sources are deterministic fixtures. This does not validate hardware telemetry or native popup compositing.",
        ]
        try JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("evidence.json"), options: .atomic)
        print("Battery time indicator: \(records.count) captures, \(assertions) assertions, 0 failures")
    }

    @MainActor private func verifyClockHover(_ row: PopoverRuntimeView, window: NSWindow,
                                             background: NSWindow, scheme: String) async throws {
        guard let button = row.subviews.compactMap({ $0 as? NSButton }).first,
              let feedback = row.subviews.compactMap({ $0 as? FooterHoverFeedbackView }).first
        else { throw failure("Runtime clock controls missing") }
        let screenRect = window.convertToScreen(row.convert(row.bounds, to: nil))
        button.isHidden = true
        feedback.isHidden = true
        try await pause(0.2)
        let original = try capture(window, background: background, name: "clock-\(scheme)-original",
                                   elapsed: nil, screenRect: screenRect)
        button.isHidden = false
        feedback.isHidden = false
        try await pause(0.2)
        let idle = try capture(window, background: background, name: "clock-\(scheme)-idle",
                               elapsed: nil, screenRect: screenRect)
        try check(original == idle, "Clock resting artwork changed when controls became visible: \(scheme)")
        let rect = feedback.convert(button.bounds, from: button)
        var hashes: [String] = []
        for (index, fraction) in [CGFloat(0.25), 0.75].enumerated() {
            let point = NSPoint(x: rect.minX + rect.width * fraction, y: rect.minY + rect.height * fraction)
            feedback.pointerLocationForTest = point
            guard let event = NSEvent.mouseEvent(with: .mouseMoved, location: feedback.convert(point, to: nil),
                modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)
            else { throw failure("Cannot create clock hover event") }
            feedback.mouseMoved(with: event)
            try await pause(0.25)
            try check(feedback.hoveredIndexForTest == 0 && feedback.glowForTest.opacity == 1,
                      "Clock hover feedback missing: \(scheme)")
            hashes.append(try capture(window, background: background, name: "clock-\(scheme)-hover-\(index)",
                                      elapsed: nil, screenRect: screenRect))
        }
        try check(hashes.allSatisfy { $0 != idle } && hashes[0] != hashes[1],
                  "Clock pointer movement did not change the rendered glow: \(scheme)")
        feedback.pointerLocationForTest = NSPoint(x: -10, y: -10)
        guard let exitEvent = NSEvent.enterExitEvent(with: .mouseExited, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)
        else { throw failure("Cannot create clock exit event") }
        feedback.mouseExited(with: exitEvent)
        try await pause(0.25)
        let exited = try capture(window, background: background, name: "clock-\(scheme)-exited",
                                 elapsed: nil, screenRect: screenRect)
        try check(exited == idle && feedback.hoveredIndexForTest == nil && feedback.glowForTest.opacity == 0,
                  "Clock did not return to its exact resting appearance: \(scheme)")
        feedback.pointerLocationForTest = nil
    }

    @MainActor private func verifyActivityMonitorClick(_ row: PopoverRuntimeView, window: NSWindow) async throws {
        guard let button = row.subviews.compactMap({ $0 as? NSButton }).first else {
            throw failure("Runtime clock button missing")
        }
        try check(button.accessibilityLabel() == "Open Activity Monitor" && button.toolTip == "Open Activity Monitor",
                  "Clock launch action is not discoverable")
        activityMonitorBaseline = Set(NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.ActivityMonitor")
            .map(\.processIdentifier))
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
        let point = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
            else { throw failure("Cannot create clock click event") }
            NSApp.postEvent(event, atStart: false)
        }
        let deadline = CACurrentMediaTime() + 6
        var launched: NSRunningApplication?
        repeat {
            try await pause(0.1)
            launched = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.ActivityMonitor")
                .first { $0.isFinishedLaunching && $0.isActive }
        } while launched == nil && CACurrentMediaTime() < deadline
        try check(launched?.bundleURL?.path == "/System/Applications/Utilities/Activity Monitor.app",
                  "Native clock click did not activate the system Activity Monitor")
        activityMonitorEvidence = ["nativeQueuedMouseClick": true, "active": launched?.isActive == true,
                                   "bundlePath": launched?.bundleURL?.path ?? "",
                                   "newlyOwned": launched.map { !(activityMonitorBaseline?.contains($0.processIdentifier) ?? true) } ?? false]
        try check(stopActivityMonitor(), "Owned Activity Monitor remained running after verification")
        activityMonitorEvidence["ownedProcessCleanupPassed"] = true
    }

    private func stopActivityMonitor() -> Bool {
        guard let baseline = activityMonitorBaseline else { return true }
        let owned = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.ActivityMonitor")
            .filter { !baseline.contains($0.processIdentifier) }
        owned.forEach { _ = $0.terminate() }
        let deadline = Date().addingTimeInterval(2)
        while owned.contains(where: { !$0.isTerminated }) && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        owned.filter { !$0.isTerminated }.forEach { _ = $0.forceTerminate() }
        let forceDeadline = Date().addingTimeInterval(1)
        while owned.contains(where: { !$0.isTerminated }) && Date() < forceDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        let stopped = owned.allSatisfy(\.isTerminated)
        if stopped { activityMonitorBaseline = nil }
        return stopped
    }

    @discardableResult
    private func capture(_ window: NSWindow, background: NSWindow, name: String, elapsed: Double?,
                         screenRect: NSRect? = nil) throws -> String {
        guard let screen = window.screen else { throw failure("No capture screen") }
        let bounds = screenRect ?? window.frame
        let region = NSRect(x: bounds.minX, y: screen.frame.maxY - bounds.maxY, width: bounds.width, height: bounds.height)
        guard window.isVisible,
              let image = WattsonCaptureOwnedWindows(region, CGWindowID(window.windowNumber), CGWindowID(background.windowNumber)),
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { throw failure("WindowServer capture refused") }
        try png.write(to: directory.appendingPathComponent(name + ".png"), options: .atomic)
        let hash = SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined()
        var record: [String: Any] = ["image": name + ".png", "pixels": [image.width, image.height],
                                    "imageSHA256": hash]
        if let elapsed { record["elapsedSeconds"] = elapsed }
        records.append(record)
        return hash
    }

    private func animationCount(_ layer: CALayer?) -> Int {
        guard let layer else { return 0 }
        return (layer.animationKeys()?.count ?? 0) + animationCount(layer.mask)
            + (layer.sublayers ?? []).reduce(0) { $0 + animationCount($1) }
    }
    private func pause(_ seconds: Double) async throws { try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
    private func check(_ passed: Bool, _ message: String) throws { assertions += 1; if !passed { throw failure(message) } }
    private func failure(_ message: String) -> NSError { NSError(domain: "BatteryTimeProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
