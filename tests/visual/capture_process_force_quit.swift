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
        [process(990_101, "Safari", 84), process(990_102, "Research Analysis Helper", 46), process(990_103, "WindowServer", 8.1, permitted: false)]
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
        let evidence: [String: Any] = ["schema": 1, "assertions": assertions, "failures": 0, "captures": records,
            "method": "Real signed sandboxed AppKit fixture application, production Classic/Glass popup hosts and Process Activity rows, WindowServer captures in an owned ARM GUI VM. Native mouse events select rows; button target/action uses a spy. Production NSAlert confirmation is exercised with Cancel and Force Quit using a spy executor.",
            "limitations": "Battery and process values/identities are fixtures. The GUI never sends a process signal. A separate owned-child probe verifies the production root helper worker. No canonical app/helper is installed."]
        try JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("evidence.json"))
        print("PROCESS_FORCE_QUIT_NATIVE_PASSED captures=\(records.count) assertions=\(assertions)")
    }
    @MainActor private func popup(_ anchor: NSStatusBarButton, sample: PowerSnapshot, name: String, compact: Bool) async throws {
        let host = PopoverController(); controller = host
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
        try check(list.forceQuitButtonsForTest.allSatisfy(\.isHidden), "Unselected rows show close buttons")
        let before = list.barGeometryForTest.map(\.track)
        try click(list.processRowsForTest[0], in: window)
        try await pause(0.05)
        try check(list.selectedRowIndexForTest == 0, "Native row click did not select")
        try check(!list.forceQuitButtonsForTest[0].isHidden && list.forceQuitButtonsForTest[0].isEnabled, "Selected row has no enabled close button")
        try check(list.forceQuitButtonsForTest.dropFirst().allSatisfy(\.isHidden), "More than one close button visible")
        try check(list.forceQuitButtonsForTest[0].frame.size == NSSize(width: 18, height: 18), "Close button is not 18pt")
        try check(list.barGeometryForTest.map(\.track) == before, "Selection shifted the score bars")
        let row = list.processRowsForTest[0]
        try check(row.isAccessibilitySelected(), "Native AX selection missing")
        try check(abs(row.bounds.height - (compact ? 28 : 44)) < 0.1, "Selection changed row height")
        try check(list.forceQuitButtonsForTest[0].accessibilityLabel()?.contains("Safari") == true, "Close button lacks process name for accessibility")
        try capture(window, name: name, fields: ["compact": compact, "selectedProcess": "Safari", "closeButtonFrame": NSStringFromRect(list.forceQuitButtonsForTest[0].frame)])
        if name.contains("on-battery-") {
            try capture(window, name: name + "-module", fields: ["compact": compact, "selectedProcess": "Safari", "productionModuleRegion": true], screenRect: window.convertToScreen(list.convert(list.bounds, to: nil)).insetBy(dx: -6, dy: -6))
        }
        let productionHandler = list.forceQuitHandler
        var requested: [EnergyProcess] = []
        list.forceQuitHandler = { requested.append($0) }
        try clickButton(list.forceQuitButtonsForTest[0], in: window)
        try check(requested == [processes[0]], "Native button action did not preserve exact identity")
        list.update(state: .ready([processes[1], processes[0], processes[2]]), count: 3, compact: compact)
        try check(list.selectedRowIndexForTest == 1, "Selection did not follow process identity after reorder")
        list.update(state: .ready(processes), count: 3, compact: !compact)
        try check(list.selectedRowIndexForTest == 0, "Compact change lost selected process identity")
        try click(list.processRowsForTest[2], in: window)
        try check(list.selectedRowIndexForTest == 2 && !list.forceQuitButtonsForTest[2].isEnabled, "Unavailable process exposes an enabled action")
        // The first three power states in each theme/host also traverse the
        // unmodified controller path, closing the popup before its live alert.
        let modalAction = name.contains("charging-") ? "Cancel" : name.contains("full-") ? "Escape" : name.contains("on-battery-") ? "Return" : nil
        if !compact, let modalAction {
            list.forceQuitHandler = productionHandler
            list.update(state: .ready(processes), count: 3, compact: compact)
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
        }
        host.handleOutsideClick()
        try check(list.selectedRowIndexForTest == nil, "Dismissal retained row selection")
        controller = nil
        try await pause(0.1)
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
