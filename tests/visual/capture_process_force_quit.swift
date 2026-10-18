import AppKit
import Darwin

/// Uses production views, hosts, and alerts with fixture identities. No GUI
/// action is allowed to reach a helper; termination is replaced with a spy.
@main
private enum CaptureProcessForceQuit {
    static func main() {
        guard CommandLine.arguments.count == 2 else { exit(64) }
        let defaults = MemoryDefaults()
        Settings.configureForTest(defaults: defaults)
        Settings.checksForUpdatesOnLaunch = false
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = Probe(URL(fileURLWithPath: CommandLine.arguments[1]))
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

// The fixture and all Timer callbacks run only on AppKit's main run loop.
private final class Probe: NSObject, NSApplicationDelegate, @unchecked Sendable {
    private let directory: URL
    private var statusItem: NSStatusItem?
    private var background: NSWindow?
    private var controller: PopoverController?
    private var assertions = 0
    private var records: [[String: Any]] = []
    private let samples: [(String, PowerSnapshot)] = [
        ("charging", PowerSnapshot(percent: 72, plugged: true, adapterW: 68, batteryW: 22.2, systemW: 45.8, temperatureC: 34.2, cycleCount: 116, batteryTimeEstimate: .charging(42))),
        ("full", PowerSnapshot(percent: 100, plugged: true, adapterW: 52, batteryW: 0, systemW: 52, temperatureC: 31.8, cycleCount: 116, batteryTimeEstimate: .full)),
        ("on-battery", PowerSnapshot(percent: 67, batteryW: -39.7, systemW: 39.7, deviceOutputW: 12.2, temperatureC: 33.1, cycleCount: 116, batteryTimeEstimate: .remaining(265))),
        ("mixed-supply", PowerSnapshot(percent: 18, plugged: true, adapterW: 28, batteryW: -31.7, systemW: 59.7, temperatureC: 38.6, cycleCount: 116, batteryTimeEstimate: .notCharging)),
        ("low-battery", PowerSnapshot(percent: 14, batteryW: -12, systemW: 12, temperatureC: 32.4, cycleCount: 116, batteryTimeEstimate: .remaining(18))),
        ("low-power", PowerSnapshot(percent: 67, batteryW: -12, systemW: 12, temperatureC: 32.4, cycleCount: 116, lowPowerMode: true, batteryTimeEstimate: .remaining(310))),
    ]
    private func process(_ pid: Int32, _ name: String, _ score: Double, permitted: Bool = true) -> EnergyProcess {
        var token = audit_token_t()
        token.val.1 = getuid(); token.val.3 = getuid(); token.val.5 = UInt32(pid)
        let identity = ProcessIdentity(pid: pid, startedAt: UInt64(pid), auditToken: withUnsafeBytes(of: token) { Data($0) })
        let wakeups: Double = score >= 12 ? 240 : 2
        return EnergyProcess(pid: pid, name: name, energyImpact: score, cpuPercent: max(0, score - 0.05 * wakeups),
                             idleWakeupsPerSecond: wakeups, terminationIdentity: permitted ? identity : nil)
    }
    private var processes: [EnergyProcess] {
        [process(990_101, "Safari", 84), process(990_102, "Research Analysis Helper", 46.123456789), process(990_103, "WindowServer", 8.1, permitted: false)]
    }
    init(_ directory: URL) { self.directory = directory }
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 230) { self.stop(); fputs("ForceQuitProbe watchdog\n", stderr); exit(1) }
        Task { @MainActor in
            do { try await run(); stop(); NSApp.terminate(nil) }
            catch { fputs("ForceQuitProbe: \(error)\n", stderr); stop(); exit(1) }
        }
    }
    func applicationWillTerminate(_ notification: Notification) { stop() }
    private func stop() {
        controller?.handleOutsideClick(); controller = nil
        background?.close(); background = nil
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
    }
    @MainActor private func run() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        Settings.topProcessCount = 3
        for module in Settings.Module.allCases { Settings.setModule(module, visible: true) }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        guard let button = item.button else { throw failure("No status button") }
        button.title = " QA"; button.image = NSImage(systemSymbolName: "battery.100", accessibilityDescription: "QA")
        try await pause(0.3)
        guard let screen = button.window?.screen else { throw failure("No screen") }
        let backdrop = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        backdrop.isReleasedWhenClosed = false; backdrop.isRestorable = false; backdrop.hasShadow = false; backdrop.isOpaque = true
        background = backdrop; backdrop.orderFrontRegardless()
        try nativeAlerts()
        for glass in [false, true] {
            Settings.liquidGlassEnabled = glass; Settings.liquidGlassStyle = .regular
            for theme in [Settings.ColorScheme.light, .dark] {
                Settings.colorScheme = theme; NSApp.appearance = theme.appearance
                backdrop.backgroundColor = theme == .light ? .init(white: 0.88, alpha: 1) : .init(white: 0.14, alpha: 1)
                for compact in [false, true] {
                    Settings.topProcessesCompact = compact
                    for (state, sample) in samples {
                        let name = "\(glass ? "glass" : "classic")-\(theme.rawValue)-\(state)-\(compact ? "compact" : "detailed")"
                        try await popup(button, sample: sample, name: name, compact: compact)
                    }
                }
            }
        }
        let evidence: [String: Any] = ["schema": 1, "assertions": assertions, "failures": 0, "captures": records, "fixtureScores": processes.map(\.energyImpact),
            "method": "Real signed sandboxed AppKit fixture application, production Classic/Glass popup hosts and Process Activity rows, WindowServer captures in an owned ARM GUI VM. Native mouse events select rows and track the right-side capsule; action uses a spy. Fixed name/bar geometry, selected-only hidden scores, concise tooltips, native glass capsule and shared pointer-light overlay are checked. The process-only Reduce Motion override is temporarily cleared for hover captures and restored; system accessibility preferences are never written. Production NSAlert confirmation is exercised with a spy executor.",
            "limitations": "Battery and process values/identities are fixtures. The GUI never sends a process signal. A separate owned-child probe verifies the production root helper worker. No canonical app/helper is installed."]
        try JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("evidence.json"))
        print("PROCESS_FORCE_QUIT_NATIVE_PASSED captures=\(records.count) assertions=\(assertions)")
    }
    @MainActor private func popup(_ anchor: NSStatusBarButton, sample: PowerSnapshot, name: String, compact: Bool) async throws {
        let host = PopoverController(); controller = host
        var terminationLifecycle: [String] = []
        host.onProcessTerminationIntent { terminationLifecycle.append("intent") }
        host.onVisibilityChange { shown in if !shown { terminationLifecycle.append("closed") } }
        host.update(snapshot: sample, history: [10, 20, 30, 20], peak: 30, degraded: false)
        host.updateTopProcesses(.ready(processes)); host.updateSystemBatteryIconState(false)
        host.openForSettingsCommandTest(relativeTo: anchor)
        try await pause(0.3)
        guard let content = host.contentViewForTest, let window = content.window,
              let list = descendants(content).compactMap({ $0 as? TopProcessesView }).first,
              let scroll = descendants(content).compactMap({ $0 as? NSScrollView }).first,
              let document = scroll.documentView else { throw failure("Missing production popup") }
        if document.bounds.height > scroll.contentView.bounds.height {
            scroll.contentView.scroll(to: .init(x: 0, y: max(0, document.bounds.height - scroll.contentView.bounds.height)))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        list.layoutSubtreeIfNeeded()
        let palette = try validateActivityPalette(list, content: content)
        let hostColor = NSColor(srgbRed: CGFloat(palette[1][0]), green: CGFloat(palette[1][1]),
                                blue: CGFloat(palette[1][2]), alpha: CGFloat(palette[1][3]))
        try check(list.forceQuitButtonsForTest.allSatisfy(\.isHidden), "Unselected rows show close buttons")
        let namesBefore = try nameFrames(in: list)
        try check(namesBefore.allSatisfy { $0 == NSRect(x: 0, y: 2, width: 132, height: 20) }, "Unselected names do not retain their fixed layout")
        try validateRowTooltips(list)
        try check(try scoreFields(in: list).allSatisfy { !$0.isHidden }, "Unselected row hides its score")
        let before = list.barGeometryForTest.map(\.track)
        try click(list.processRowsForTest[0], in: window)
        try await pause(0.05)
        try check(list.selectedRowIndexForTest == 0, "Native row click did not select")
        try check(!list.forceQuitButtonsForTest[0].isHidden && list.forceQuitButtonsForTest[0].isEnabled, "Selected row has no enabled close button")
        try check(list.forceQuitButtonsForTest.dropFirst().allSatisfy(\.isHidden), "More than one close button visible")
        let actionFrame = list.forceQuitButtonsForTest[0].frame
        try check(actionFrame == NSRect(x: 288, y: 4, width: 38, height: 16),
                  "Action capsule does not retain its fixed width/alignment")
        try check(list.barGeometryForTest.map(\.track) == before, "Selection shifted the score bars")
        try check(try nameFrames(in: list) == namesBefore, "Selection shifted or truncated a process name")
        let values = try scoreFields(in: list)
        try check(values[0].isHidden && values.dropFirst().allSatisfy { !$0.isHidden }, "Only the selected row should hide its score")
        if #available(macOS 26.0, *) {
            try check(list.forceQuitButtonsForTest[0].bezelStyle == .glass && list.forceQuitButtonsForTest[0].borderShape == .capsule, "macOS 26 action is not a native glass capsule")
        }
        try validateRowTooltips(list)
        let row = list.processRowsForTest[0]
        try check(row.isAccessibilitySelected(), "Native AX selection missing")
        try check(abs(row.bounds.height - (compact ? 28 : 44)) < 0.1, "Selection changed row height")
        try check(list.forceQuitButtonsForTest[0].accessibilityLabel()?.contains("Safari") == true, "Close button lacks process name for accessibility")
        _ = try validateActivityPalette(list, content: content)
        let actionMetadata = try actionPaletteMetadata(list, index: 0, palette: palette)
        try capture(window, name: name, fields: actionMetadata.merging(["compact": compact, "selectedProcess": "Safari", "actionCapsuleFrame": NSStringFromRect(list.forceQuitButtonsForTest[0].frame), "nameFrames": namesBefore.map(NSStringFromRect), "selectedScoreHidden": true, "nativeGlassCapsule": true, "activityPaletteSRGB": palette]) { _, value in value })
        try captureModule(list, window: window, name: name + "-module", fields: actionMetadata.merging(["compact": compact, "selectedProcess": "Safari", "activityPaletteSRGB": palette]) { _, value in value })
        if name.contains("charging-") || name.contains("full-") || name.contains("on-battery-") {
            try await hoverLight(list, content: content, window: window, name: name, compact: compact)
        }
        if name.contains("on-battery-") {
            if !compact { try await activityInfo(list, window: window, name: name) }
            let updates = list.contentUpdatesForTest
            for transition in [samples[0].1, samples[1].1, sample] {
                host.update(snapshot: transition, history: [10, 20, 30, 20], peak: 30, degraded: false)
                _ = try validateActivityPalette(list, content: content)
                try check(list.selectedRowIndexForTest == 0 && list.contentUpdatesForTest == updates,
                          "Power color change rebuilt process data or cleared selection")
                try check(list.barGeometryForTest.map(\.track) == before,
                          "Power color change moved the activity bars")
            }
        }
        let productionHandler = list.forceQuitHandler
        var requested: [EnergyProcess] = []
        list.forceQuitHandler = { requested.append($0) }
        try clickButton(list.forceQuitButtonsForTest[0], in: window)
        try check(requested == [processes[0]], "Native button action did not preserve exact identity")
        list.update(state: .ready([processes[1], processes[0], processes[2]]), count: 3, compact: compact, color: hostColor)
        _ = try validateActivityPalette(list, content: content)
        try check(list.selectedRowIndexForTest == 1, "Selection did not follow process identity after reorder")
        list.update(state: .ready(processes), count: 3, compact: !compact, color: hostColor)
        _ = try validateActivityPalette(list, content: content)
        try check(list.selectedRowIndexForTest == 0, "Compact change lost selected process identity")
        list.update(state: .ready(processes), count: 3, compact: compact, color: hostColor)
        _ = try validateActivityPalette(list, content: content)
        try click(list.processRowsForTest[2], in: window)
        try check(list.selectedRowIndexForTest == 2 && !list.forceQuitButtonsForTest[2].isEnabled, "Unavailable process exposes an enabled action")
        list.layoutSubtreeIfNeeded()
        let shortFrame = list.forceQuitButtonsForTest[2].frame
        try check(shortFrame == actionFrame, "Disabled or short-score capsule changes width or position")
        let disabledPalette = try validateActivityPalette(list, content: content)
        if name.contains("on-battery-") {
            try await pause(0.05)
            try captureModule(list, window: window, name: name + "-disabled-module", fields: try actionPaletteMetadata(list, index: 2, palette: disabledPalette).merging(["compact": compact, "selectedProcess": "WindowServer", "actionEnabled": false, "actionCapsuleFrame": NSStringFromRect(shortFrame), "activityPaletteSRGB": disabledPalette]) { _, value in value })
        }
        // The first three power states in each theme/host also traverse the
        // unmodified controller path, closing the popup before its live alert.
        let modalAction = name.contains("charging-") ? "Cancel" : name.contains("full-") ? "Escape" : name.contains("on-battery-") ? "Return" : nil
        if !compact, let modalAction {
            list.forceQuitHandler = productionHandler
            list.update(state: .ready(processes), count: 3, compact: compact, color: hostColor)
            _ = try validateActivityPalette(list, content: content)
            try click(list.processRowsForTest[0], in: window)
            var modalProblems: [String] = []
            var modalObserved = false
            var dismissalDelivered = false
            var returnStayedOpen = false
            let timer = dismissalTimer(action: modalAction, name: name + "-confirmation", problems: { modalProblems.append($0) }, onObserved: { modalObserved = true }, onDismissal: { dismissalDelivered = true }, onReturnStayedOpen: { returnStayedOpen = true })
            RunLoop.main.add(timer, forMode: .common)
            try clickButton(list.forceQuitButtonsForTest[0], in: window)
            try await pause(modalAction == "Return" ? 1.2 : 0.6)
            timer.invalidate()
            try check(modalProblems.isEmpty, modalProblems.joined(separator: "; "))
            try check(modalObserved, "Production-controller action never presented its native confirmation")
            try check(dismissalDelivered, "Native dismissal was never delivered to the observed confirmation")
            try check(modalAction != "Return" || returnStayedOpen, "Return did not remain inert on the observed production confirmation")
            try check(!host.isShownForTest, "Production popup remained open under confirmation")
            try check(NSApp.modalWindow == nil, "Native confirmation did not finish its safe dismissal sequence")
            guard let intent = terminationLifecycle.firstIndex(of: "intent"), let closed = terminationLifecycle.firstIndex(of: "closed") else { throw failure("Missing termination intent or popup dismissal callback") }
            try check(intent < closed, "Process cache invalidation intent arrived after popup dismissal")
        }
        host.handleOutsideClick()
        try check(list.selectedRowIndexForTest == nil, "Dismissal retained row selection")
        for feedback in descendants(list).compactMap({ $0 as? FooterHoverFeedbackView }) {
            try check(feedback.hoveredIndexForTest == nil && feedback.glowForTest.opacity == 0, "Dismissal retained capsule hover light")
        }
        controller = nil
        try await pause(0.1)
    }
    private func nameFrames(in list: TopProcessesView) throws -> [NSRect] {
        try list.processRowsForTest.map { row in
            guard let field = row.subviews.compactMap({ $0 as? NSTextField }).first else { throw failure("Missing process name field") }
            return field.frame
        }
    }
    private func scoreFields(in list: TopProcessesView) throws -> [NSTextField] {
        try list.processRowsForTest.map { row in
            let fields = row.subviews.compactMap { $0 as? NSTextField }
            guard fields.count == 3 else { throw failure("Missing name, score or detail field") }
            return fields[1]
        }
    }
    private func validateActivityPalette(_ list: TopProcessesView, content: NSView) throws -> [[Double]] {
        guard let history = descendants(content).compactMap({ $0 as? HistoryView }).first,
              let stroke = history.layer?.sublayers?.flatMap({ $0.sublayers ?? [] })
                .compactMap({ $0 as? CAShapeLayer }).first(where: { $0.strokeColor != nil })?.strokeColor,
              let expected = NSColor(cgColor: stroke)?.usingColorSpace(.sRGB) else {
            throw failure("Missing production History palette")
        }
        var palette: [[Double]] = []
        for (index, row) in list.processRowsForTest.enumerated() {
            guard let track = row.layer?.sublayers?.first(where: { $0.name == "top-processes.track" }),
                  let gradient = track.sublayers?.compactMap({ $0 as? CAGradientLayer }).first,
                  let colors = gradient.colors as? [CGColor], colors.count == 3 else {
                throw failure("Missing process activity gradient")
            }
            let stops = try colors.map { color -> NSColor in
                guard let result = NSColor(cgColor: color)?.usingColorSpace(.sRGB) else {
                    throw failure("Unresolvable process activity color")
                }
                return result
            }
            let middle = stops[1]
            try check(abs(middle.redComponent - expected.redComponent) < 0.00001
                      && abs(middle.greenComponent - expected.greenComponent) < 0.00001
                      && abs(middle.blueComponent - expected.blueComponent) < 0.00001,
                      "Process activity color differs from the production History palette")
            try check(stops.allSatisfy { abs($0.alphaComponent - 1) < 0.00001 },
                      "Process activity gradient is not opaque")
            guard let button = list.forceQuitButtonsForTest[index] as? ProcessActionButton else {
                throw failure("Missing production process action capsule")
            }
            try checkColor(button.tintColor, stops[2], "Process action tint differs from the full-scale gradient endpoint")
            if !PopoverStyle.isHighContrast(list.effectiveAppearance) {
                let brightness = stops.map { 0.2126 * $0.redComponent + 0.7152 * $0.greenComponent + 0.0722 * $0.blueComponent }
                try check(brightness[0] > brightness[1] && brightness[1] > brightness[2],
                          "Process activity gradient does not run from pale to deep")
            }
            if palette.isEmpty {
                palette = stops.map { [Double($0.redComponent), Double($0.greenComponent), Double($0.blueComponent), Double($0.alphaComponent)] }
            }
        }
        if let selected = list.selectedRowIndexForTest,
           let button = list.forceQuitButtonsForTest[selected] as? ProcessActionButton {
            let feedback = list.forceQuitFeedbackForTest
            if PopoverStyle.isHighContrast(list.effectiveAppearance) {
                try check(feedback.glowForTest.shadowOpacity == 0
                          && feedback.reflectionForTest.isHidden && feedback.rimReflectionForTest.isHidden,
                          "High contrast retains a colored action shadow or reflection")
            } else {
                guard let shadow = feedback.glowForTest.shadowColor.flatMap({ NSColor(cgColor: $0) }) else {
                    throw failure("Missing process action glow shadow color")
                }
                try checkColor(shadow, button.tintColor, "Process action glow differs from the gradient endpoint")
            }
        }
        return palette
    }
    private func colorComponents(_ color: NSColor) throws -> [Double] {
        guard let rgb = color.usingColorSpace(.sRGB) else { throw failure("Unresolvable action palette color") }
        return [Double(rgb.redComponent), Double(rgb.greenComponent), Double(rgb.blueComponent), Double(rgb.alphaComponent)]
    }
    private func checkColor(_ actual: NSColor, _ expected: NSColor, _ message: String) throws {
        let left = try colorComponents(actual), right = try colorComponents(expected)
        try check(zip(left, right).allSatisfy { abs($0.0 - $0.1) < 0.00001 }, message)
    }
    private func actionPaletteMetadata(_ list: TopProcessesView, index: Int, palette: [[Double]]) throws -> [String: Any] {
        guard let button = list.forceQuitButtonsForTest[index] as? ProcessActionButton,
              let glyph = button.contentTintColor,
              let shadow = list.forceQuitFeedbackForTest.glowForTest.shadowColor.flatMap({ NSColor(cgColor: $0) }) else {
            throw failure("Missing native action palette metadata")
        }
        return ["actionTintSRGB": try colorComponents(button.tintColor),
                "gradientEndpointSRGB": palette[2], "glyphTintSRGB": try colorComponents(glyph),
                "glowShadowTintSRGB": try colorComponents(shadow)]
    }
    private func validateRowTooltips(_ list: TopProcessesView) throws {
        for row in list.processRowsForTest {
            guard let summary = row.toolTip else { throw failure("Missing concise process tooltip") }
            try check(summary.components(separatedBy: .newlines).count <= 2, "Process tooltip exceeds two lines")
            try check(summary.contains("PID") && summary.contains("CPU") && summary.contains("Wakeups"), "Process tooltip omits useful rounded readings")
            for view in descendants(row) {
                guard let tooltip = view.toolTip else { continue }
                try check(tooltip.components(separatedBy: .newlines).count <= 2, "Row control tooltip exceeds two lines")
                try check(tooltip.range(of: #"\d+\.\d{3,}"#, options: .regularExpression) == nil, "Process tooltip exposes raw floating-point precision")
                for explanation in ["combines CPU usage", "Higher scores indicate", "one logical core", "fixed 0–100"] {
                    try check(!tooltip.contains(explanation), "Metric explanation escaped the info control")
                }
            }
        }
    }
    private func captureModule(_ list: TopProcessesView, window: NSWindow, name: String, fields: [String: Any]) throws {
        var metadata = fields
        metadata["productionModuleRegion"] = true
        try capture(window, name: name, fields: metadata, screenRect: window.convertToScreen(list.convert(list.bounds, to: nil)).insetBy(dx: -6, dy: -6))
    }
    @MainActor private func hoverLight(_ list: TopProcessesView, content: NSView, window: NSWindow, name: String, compact: Bool) async throws {
        let overlays = descendants(list).compactMap { $0 as? FooterHoverFeedbackView }
        try check(overlays.count == 1, "Process module must reuse one hover overlay")
        guard let feedback = overlays.first else { throw failure("No process action hover overlay") }
        let button = list.forceQuitButtonsForTest[0]
        let capsule = button.convert(button.bounds, to: feedback)
        try check(feedback.regionsForTest.filter(\.enabled).count == 1, "Hover does not track only the selected available action")
        try check(feedback.regionsForTest.contains { $0.rect == capsule && $0.enabled }, "Hover region differs from the native capsule")
        let previousMotion = ProcessInfo.processInfo.environment["WATTSON_FORCE_REDUCE_MOTION"]
        setenv("WATTSON_FORCE_REDUCE_MOTION", "0", 1)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        defer {
            feedback.pointerLocationForTest = nil
            if let previousMotion { setenv("WATTSON_FORCE_REDUCE_MOTION", previousMotion, 1) }
            else { unsetenv("WATTSON_FORCE_REDUCE_MOTION") }
            NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
            feedback.cancelHover()
        }
        var firstCenter: CGPoint?
        for (label, fraction) in [("left", CGFloat(0.25)), ("right", CGFloat(0.75))] {
            let point = NSPoint(x: capsule.minX + capsule.width * fraction, y: capsule.midY)
            feedback.pointerLocationForTest = point
            guard let event = NSEvent.mouseEvent(with: .mouseMoved, location: feedback.convert(point, to: nil), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 4, clickCount: 0, pressure: 0) else { throw failure("No native capsule hover event") }
            feedback.mouseMoved(with: event)
            try await pause(0.18)
            try check(feedback.hoveredIndexForTest != nil && feedback.glowForTest.opacity == 1, "Capsule does not receive hover light")
            try check(!feedback.reflectionForTest.isHidden && !feedback.rimReflectionForTest.isHidden, "Pointer light remains hidden during normal motion")
            try check(feedback.hitTest(point) == nil, "Hover light intercepts the action")
            let palette = try validateActivityPalette(list, content: content)
            guard let action = button as? ProcessActionButton else { throw failure("Missing native action tint") }
            let highlight = action.tintColor.blended(withFraction: PopoverStyle.isDark(list.effectiveAppearance) ? 0.55 : 0.35, of: .white)!
            for gradient in [feedback.reflectionForTest, feedback.rimReflectionForTest] {
                guard let colors = gradient.colors as? [CGColor], colors.count == 3,
                      let first = NSColor(cgColor: colors[0]) else { throw failure("Missing action reflection colors") }
                try checkColor(first.withAlphaComponent(1), highlight.withAlphaComponent(1),
                               "Pointer reflection does not use the action tint family")
            }
            let center = feedback.reflectionForTest.startPoint
            if let firstCenter { try check(center.x > firstCenter.x, "Light does not follow the pointer within its capsule") }
            else { firstCenter = center }
            try captureModule(list, window: window, name: name + "-hover-" + label + "-module", fields: try actionPaletteMetadata(list, index: 0, palette: palette).merging(["compact": compact, "pointerFraction": Double(fraction), "reflectionCenter": NSStringFromPoint(center), "processOnlyReduceMotionOverride": false]) { _, value in value })
        }
        feedback.cancelHover()
        try check(feedback.glowForTest.opacity == 0, "Capsule hover did not clear")
    }
    @MainActor private func activityInfo(_ list: TopProcessesView, window: NSWindow, name: String) async throws {
        guard let info = list.subviews.compactMap({ $0 as? NSButton }).first else { throw failure("Missing Activity Score info control") }
        try check(info.toolTip == "About Activity Score", "Info hover still shows the full explanation")
        info.performClick(nil)
        try await pause(0.18)
        guard let help = list.helpWindow, let content = help.contentView else { throw failure("Activity Score explanation did not open") }
        let text = descendants(content).compactMap { ($0 as? NSTextField)?.stringValue }.joined(separator: "\n")
        try check(text.contains("Activity Score combines CPU usage and idle wakeups") && text.contains("not measured power consumption"), "Info control lost the metric explanation")
        try capture(help, name: name + "-info", fields: ["actualInfoPopover": true, "explanationIsInInfoControl": true])
        info.performClick(nil)
        try await pause(0.08)
        try check(list.helpWindow == nil, "Activity Score info failed to close")
    }
    @MainActor private func nativeAlerts() throws {
        for action in ["Cancel", "Escape", "Return", "Force Quit"] {
            let confirm = action == "Force Quit"
            var signals: [ProcessIdentity] = []
            var problems: [String] = []
            var returnStayedOpen = false
            var attempts = 0
            var dependencies = ProcessTerminationPresenter.Dependencies.live
            dependencies.terminate = { identity, completion in signals.append(identity); completion(.signalSent) }
            dependencies.showFailure = { _, _ in problems.append("Unexpected failure alert") }
            let presenter = ProcessTerminationPresenter(dependencies: dependencies)
            let timer = Timer(timeInterval: 0.15, repeats: true) { timer in
                attempts += 1
                guard let window = NSApp.modalWindow, window.isVisible, let content = window.contentView else {
                    if attempts > 30 { problems.append("No modal confirmation"); timer.invalidate(); NSApp.abortModal() }
                    return
                }
                let buttons = self.descendants(content).compactMap { $0 as? NSButton }
                guard let cancel = buttons.first(where: { $0.title == "Cancel" }),
                      let force = buttons.first(where: { $0.title == "Force Quit" }) else { return }
                if !force.keyEquivalent.isEmpty || !force.hasDestructiveAction { problems.append("Destructive button configuration differs") }
                print("NATIVE_ALERT action=\(action) cancelKey=\(String(reflecting: cancel.keyEquivalent)) defaultCell=\(window.defaultButtonCell?.title ?? "nil")")
                do { try self.capture(window, name: "confirmation-\(action.lowercased().replacingOccurrences(of: " ", with: "-"))", fields: ["defaultButtonCell": window.defaultButtonCell?.title ?? "nil", "cancelKey": String(reflecting: cancel.keyEquivalent), "terminationExecutor": "spy"]) }
                catch { problems.append(String(describing: error)) }
                timer.invalidate()
                if action == "Cancel" || confirm { (confirm ? force : cancel).performClick(nil) }
                else {
                    do { try self.sendDismissalKey(action, to: window, onFailure: { problems.append($0) }, onReturnStayedOpen: { returnStayedOpen = true }) }
                    catch { problems.append(String(describing: error)); NSApp.abortModal() }
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            presenter.request(processes[0])
            timer.invalidate()
            try check(problems.isEmpty, problems.joined(separator: "; "))
            try check(signals.count == (confirm ? 1 : 0), "Confirmation decision did not gate the executor")
            try check(action != "Return" || returnStayedOpen, "Return unexpectedly dismissed the deliberate no-default confirmation")
            try check(!presenter.isBusy, "Native confirmation left presenter busy")
        }
    }
    private func click(_ row: NSView, in window: NSWindow) throws {
        let location = row.convert(NSPoint(x: 65, y: 12), to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard let event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1) else { throw failure("No native mouse event") }
            window.sendEvent(event)
        }
    }
    private func clickButton(_ button: NSButton, in window: NSWindow) throws {
        let location = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
        guard let down = NSEvent.mouseEvent(with: .leftMouseDown, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 1),
              let up = NSEvent.mouseEvent(with: .leftMouseUp, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime + 0.01, windowNumber: window.windowNumber, context: nil, eventNumber: 3, clickCount: 1, pressure: 0) else { throw failure("No native button event") }
        // NSButton's tracking loop consumes its own mouse-up from the queue.
        NSApp.postEvent(up, atStart: true)
        window.sendEvent(down)
    }
    private func dismissalTimer(action: String, name: String, problems: @escaping (String) -> Void, onObserved: @escaping () -> Void, onDismissal: @escaping () -> Void, onReturnStayedOpen: @escaping () -> Void) -> Timer {
        var attempts = 0
        return Timer(timeInterval: 0.1, repeats: true) { timer in
            attempts += 1
            guard let modal = NSApp.modalWindow, modal.isVisible, let content = modal.contentView else {
                if attempts > 30 { problems("No production confirmation appeared"); timer.invalidate(); NSApp.abortModal() }
                return
            }
            guard let cancel = self.descendants(content).compactMap({ $0 as? NSButton }).first(where: { $0.title == "Cancel" }) else { return }
            if self.controller?.isShownForTest != false { problems("Popup was visible under production confirmation") }
            do { try self.capture(modal, name: name, fields: ["dismissal": action, "productionController": true]) }
            catch {
                if attempts > 30 { problems(String(describing: error)); timer.invalidate(); NSApp.abortModal() }
                return
            }
            onObserved()
            timer.invalidate()
            if action == "Cancel" { cancel.performClick(nil); onDismissal(); return }
            do { try self.sendDismissalKey(action, to: modal, onFailure: problems, onReturnStayedOpen: { onReturnStayedOpen(); onDismissal() }); if action != "Return" { onDismissal() } }
            catch { problems(String(describing: error)); NSApp.abortModal() }
        }
    }
    private func sendDismissalKey(_ action: String, to window: NSWindow, onFailure: @escaping (String) -> Void, onReturnStayedOpen: @escaping () -> Void = {}) throws {
        let code: UInt16 = action == "Escape" ? 53 : 36
        let characters = action == "Escape" ? "\u{1b}" : "\r"
        guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code) else { throw failure("No modal key event") }
        let fallback = Timer(timeInterval: 0.7, repeats: false) { _ in
            if action == "Return" {
                guard NSApp.modalWindow === window else { onFailure("Return unexpectedly dismissed the no-default confirmation"); return }
                onReturnStayedOpen()
                guard let content = window.contentView, let cancel = self.descendants(content).compactMap({ $0 as? NSButton }).first(where: { $0.title == "Cancel" }) else { onFailure("No Cancel after inert Return"); NSApp.abortModal(); return }
                cancel.performClick(nil)
            } else if NSApp.modalWindow === window { onFailure("Native \(action) did not dismiss confirmation"); NSApp.abortModal() }
        }
        RunLoop.main.add(fallback, forMode: .common)
        NSApp.postEvent(event, atStart: true)
    }
    private func capture(_ window: NSWindow, name: String, fields: [String: Any], screenRect: NSRect? = nil) throws {
        guard let background, let screen = window.screen else { throw failure("No capture screen") }
        let bounds = screenRect ?? window.frame.insetBy(dx: -8, dy: -8)
        let region = NSRect(x: bounds.minX, y: screen.frame.maxY - bounds.maxY, width: bounds.width, height: bounds.height)
        guard window.isVisible, let image = WattsonCaptureOwnedWindows(region, CGWindowID(window.windowNumber), CGWindowID(background.windowNumber)),
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { throw failure("Owned WindowServer capture refused") }
        try data.write(to: directory.appendingPathComponent(name + ".png"))
        var record = fields; record["image"] = name + ".png"; record["glass"] = Settings.usesLiquidGlass; record["windowFrame"] = NSStringFromRect(window.frame)
        records.append(record)
    }
    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    private func check(_ value: Bool, _ message: String) throws { assertions += 1; if !value { throw failure(message) } }
    private func failure(_ text: String) -> NSError { NSError(domain: "WattsonForceQuitProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
    private func pause(_ seconds: Double) async throws { try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
}
