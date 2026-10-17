import AppKit
import CryptoKit

/// Production AppKit layout and WindowServer evidence. The shell entry point
/// refuses physical Macs; all readings and privileged Settings dependencies
/// are fixtures, with preferences held only in memory.
@main
private enum CaptureTopProcesses {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let moduleOnly = arguments.first == "--module-only"
        guard arguments.count == (moduleOnly ? 2 : 1),
              let output = arguments.last else { exit(64) }
        let defaults = MemoryDefaults()
        Settings.configureForTest(defaults: defaults)
        Settings.checksForUpdatesOnLaunch = false
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = Probe(directory: URL(fileURLWithPath: output), moduleOnly: moduleOnly)
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

private final class Probe: NSObject, NSApplicationDelegate {
    private let directory: URL
    private let isModuleOnly: Bool
    private var records: [[String: Any]] = []
    private var item: NSStatusItem?
    private var backdrop: NSWindow?
    private var popover: PopoverController?
    private var settings: SettingsWindowController?
    private var assertions = 0

    private let samples: [(String, PowerSnapshot)] = [
        ("charging", PowerSnapshot(percent: 72, plugged: true, adapterW: 68, batteryW: 22.2, systemW: 45.8, temperatureC: 34.2, cycleCount: 116, batteryTimeEstimate: .charging(42))),
        ("full", PowerSnapshot(percent: 100, plugged: true, adapterW: 52, batteryW: 0, systemW: 52, temperatureC: 31.8, cycleCount: 116, batteryTimeEstimate: .full)),
        ("on-battery", PowerSnapshot(percent: 67, batteryW: -39.7, systemW: 39.7, deviceOutputW: 12.2, temperatureC: 33.1, cycleCount: 116, batteryTimeEstimate: .remaining(265))),
        ("mixed-supply", PowerSnapshot(percent: 18, plugged: true, adapterW: 28, batteryW: -31.7, systemW: 59.7, temperatureC: 38.6, cycleCount: 116, batteryTimeEstimate: .notCharging)),
        ("low-battery", PowerSnapshot(percent: 14, batteryW: -12, systemW: 12, temperatureC: 32.4, cycleCount: 116, batteryTimeEstimate: .remaining(18))),
        ("low-power", PowerSnapshot(percent: 67, batteryW: -12, systemW: 12, temperatureC: 32.4, cycleCount: 116, lowPowerMode: true, batteryTimeEstimate: .remaining(310))),
    ]
    private let processFixtures: [(name: String, impact: Double, cpu: Double, wakeups: Double)] = [
        ("Safari", 84, 72, 240),
        ("WindowServer", 46, 31, 300),
        ("backupd", 8.1, 8, 2),
        ("mds_stores", 5.4, 4.8, 12),
        ("Code Helper", 3.6, 3, 12),
        ("Terminal", 2.4, 2, 8),
        ("Music", 1.7, 1.2, 10),
        ("Spotlight", 1.1, 0.9, 4),
        ("Docker", 0.6, 0.5, 2),
        ("Very Long Research Application — Analysis Worker with a name that must truncate safely", 0.2, 0.15, 1),
    ]
    private var processes: [EnergyProcess] {
        processFixtures.enumerated().map {
            return EnergyProcess(pid: Int32(990_000 + $0.offset), name: $0.element.name,
                                 energyImpact: $0.element.impact, cpuPercent: $0.element.cpu,
                                 idleWakeupsPerSecond: $0.element.wakeups)
        }
    }

    init(directory: URL, moduleOnly: Bool) {
        self.directory = directory
        isModuleOnly = moduleOnly
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + (isModuleOnly ? 45 : 220)) { [weak self] in
            self?.stop()
            fputs("TopProcessesProbe: watchdog expired\n", stderr)
            exit(1)
        }
        Task { @MainActor in
            do {
                try await run()
                stop()
                NSApp.terminate(nil)
            } catch {
                fputs("TopProcessesProbe: \(error)\n", stderr)
                stop()
                exit(1)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) { stop() }

    private func stop() {
        popover?.handleOutsideClick(); popover = nil
        settings?.windowForTest?.close(); settings = nil
        backdrop?.close(); backdrop = nil
        if let item { NSStatusBar.system.removeStatusItem(item) }
        item = nil
    }

    @MainActor private func run() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        Settings.topProcessCount = 3
        if !isModuleOnly {
            for module in Settings.Module.allCases { Settings.setModule(module, visible: true) }
            try await hiddenMatrix()
        }
        // Both capture modes exercise the production status-item teardown so
        // the quick preview also verifies its delayed preferences cleanup.
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item = statusItem
        guard let button = statusItem.button else { throw failure("No status item") }
        button.image = NSImage(systemSymbolName: "battery.100", accessibilityDescription: "QA")
        button.title = " QA"
        try await pause(0.5)
        guard let screen = button.window?.screen else { throw failure("No status-item screen") }
        let background = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        background.isReleasedWhenClosed = false
        background.isRestorable = false
        background.hasShadow = false
        background.isOpaque = true
        backdrop = background
        background.orderFrontRegardless()
        for glass in isModuleOnly ? [false] : [false, true] {
            Settings.liquidGlassEnabled = glass
            Settings.liquidGlassStyle = .regular
            for scheme in [Settings.ColorScheme.light, .dark] {
                Settings.colorScheme = scheme
                NSApp.appearance = scheme.appearance
                background.backgroundColor = scheme == .light ? .init(white: 0.88, alpha: 1) : .init(white: 0.14, alpha: 1)
                let theme = glass ? "glass" : "classic"
                if !glass {
                    try await moduleOnly(background: background, name: "module-classic-\(scheme.rawValue)")
                    if !isModuleOnly {
                        let overflow = [
                            EnergyProcess(pid: 990_101, name: "render-worker", energyImpact: 999.95, cpuPercent: 999.9, idleWakeupsPerSecond: 1),
                            EnergyProcess(pid: 990_102, name: "Safari", energyImpact: 156, cpuPercent: 140, idleWakeupsPerSecond: 320),
                            EnergyProcess(pid: 990_103, name: "WindowServer", energyImpact: 100.0001, cpuPercent: 100, idleWakeupsPerSecond: 0.002),
                        ]
                        let tiny = [
                            EnergyProcess(pid: 990_111, name: "Idle Worker", energyImpact: 0.006, cpuPercent: 0.001, idleWakeupsPerSecond: 0.1),
                            EnergyProcess(pid: 990_112, name: "background-task", energyImpact: 0.0004, cpuPercent: 0.0003, idleWakeupsPerSecond: 0.002),
                            EnergyProcess(pid: 990_113, name: "Sleeping Worker", energyImpact: 0, cpuPercent: 0, idleWakeupsPerSecond: 0),
                        ]
                        try await moduleOnly(background: background, name: "module-overflow-\(scheme.rawValue)", values: overflow)
                        try await moduleOnly(background: background, name: "module-tiny-\(scheme.rawValue)", values: tiny)
                    }
                }
                if isModuleOnly { continue }
                for (name, snapshot) in samples {
                    try await actualPopover(button, background: background, name: "\(theme)-\(scheme.rawValue)-\(name)-3", count: 3, sample: snapshot)
                }
                for count in [1, 10] {
                    try await actualPopover(button, background: background, name: "\(theme)-\(scheme.rawValue)-on-battery-\(count)", count: count, sample: samples[2].1)
                }
                try await actualSettings(background: background, name: "settings-\(theme)-\(scheme.rawValue)")
            }
        }
        let evidence: [String: Any] = [
            "schema": 1, "assertions": assertions, "failures": 0, "cases": records,
            "mode": isModuleOnly ? "module-only" : "full-matrix",
            "method": isModuleOnly
                ? "WindowServer capture of default-three production TopProcessesView in two owned Classic fixture windows, light and dark, with an owned underlay in a disposable ARM GUI VM."
                : "Production AppKit content cache plus WindowServer capture of real Classic/Regular Glass popover and Settings windows and an owned underlay in a disposable ARM GUI VM.",
            "limitations": "Process energy, battery telemetry, history, and Settings privileged dependencies are deterministic fixtures. No sampling correctness or physical-hardware power-mode assertion is inferred from screenshots.",
        ]
        try JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("evidence.json"), options: .atomic)
        print("Top processes: \(records.count) captures, \(assertions) assertions, 0 failures")
    }

    @MainActor private func moduleOnly(background: NSWindow, name: String, values: [EnergyProcess]? = nil) async throws {
        let height = TopProcessesView.preferredHeight(count: 3)
        let window = NSWindow(contentRect: .init(x: background.frame.midX - 180, y: background.frame.midY - height / 2 - 12, width: PopoverStyle.width, height: height + 24), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = true
        window.hasShadow = false
        window.appearance = NSApp.appearance
        window.backgroundColor = PopoverStyle.surface
        defer { window.close() }
        let list = TopProcessesView()
        list.frame = .init(x: PopoverStyle.sideInset, y: 12, width: PopoverStyle.contentWidth, height: height)
        window.contentView?.addSubview(list)
        let displayed = values ?? processes
        list.update(state: .ready(displayed), count: 3)
        list.setPresentationActive(true)
        defer { list.setPresentationActive(false) }
        window.orderFrontRegardless()
        try await pause(0.15)
        try validate(list, count: 3, expectedProcesses: Array(displayed.prefix(3)))
        try composite(window, background: background, name: name, fields: ["productionSectionOnly": true, "processCount": 3, "container": "Fixture window with production Classic surface color and 16-point side insets; unmodified TopProcessesView renderer."])
        if isModuleOnly && Settings.colorScheme == .dark {
            guard let button = list.subviews.compactMap({ $0 as? NSButton }).first else { throw failure("Missing standalone info button") }
            button.performClick(nil)
            try await pause(0.15)
            guard let help = list.helpWindow, let content = help.contentView else { throw failure("Standalone info did not open") }
            let fields = descendants(content).compactMap { $0 as? NSTextField }.filter { !$0.isHiddenOrHasHiddenAncestor }
            try check(fields.contains { $0.stringValue == list.activityHelpForTest && $0.stringValue.hasSuffix("one logical core.") }, "Info omits the full Activity Score explanation")
            var heights: [[String: Any]] = []
            for field in fields {
                guard let cell = field.cell else { continue }
                let required = cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: field.bounds.width, height: 100_000))
                try check(required.height <= field.bounds.height + 0.5, "Standalone info text is clipped")
                heights.append(["text": field.stringValue, "requiredCellHeight": required.height, "frame": NSStringFromRect(field.frame)])
            }
            try composite(help, background: background, name: name + "-help", fields: ["actualInfoPopover": true, "textCellHeights": heights])
            button.performClick(nil)
            try await pause(0.1)
            try check(list.helpWindow == nil, "Standalone info did not close")
        }
        if !isModuleOnly && values == nil { try await standaloneHelpLifecycle(list) }
    }

    @MainActor private func hiddenMatrix() async throws {
        Settings.liquidGlassEnabled = false
        for scheme in [Settings.ColorScheme.light, .dark] {
            Settings.colorScheme = scheme
            NSApp.appearance = scheme.appearance
            for (name, snapshot) in samples {
                for count in [1, 3, 10] {
                    try await hidden(name: "layout-\(scheme.rawValue)-\(name)-\(count)", snapshot: snapshot, count: count, state: .ready(processes))
                }
            }
            let zero = EnergyProcess(pid: 990_099, name: "Idle Worker", energyImpact: 0,
                                     cpuPercent: 0, idleWakeupsPerSecond: 0)
            for (name, state) in [("loading", TopProcessesState.loading), ("empty", .ready([])), ("unavailable", .unavailable), ("zero-use", .ready([zero]))] {
                try await hidden(name: "layout-\(scheme.rawValue)-\(name)", snapshot: samples[2].1, count: 3, state: state)
            }
        }
    }

    @MainActor private func hidden(name: String, snapshot: PowerSnapshot, count: Int, state: TopProcessesState) async throws {
        Settings.topProcessCount = count
        let controller = PopoverContentViewController()
        controller.setAnimationsEnabled(false)
        controller.setPresentationActive(true)
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: PopoverStyle.width, height: controller.preferredHeight), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSApp.appearance
        window.contentView = controller.view
        defer { window.close() }
        controller.update(snapshot: snapshot, history: [10, 20, 30, 20], peak: 30, degraded: false)
        controller.updateTopProcesses(state)
        controller.updateSystemBatteryIconState(false)
        controller.setViewportHeight(controller.preferredHeight)
        window.setContentSize(.init(width: PopoverStyle.width, height: controller.preferredHeight))
        try await pause(0.02)
        controller.view.layoutSubtreeIfNeeded()
        guard let list = descendants(controller.view).compactMap({ $0 as? TopProcessesView }).first else { throw failure("Missing process list") }
        try validate(list, count: count, expectedProcesses: state.visibleProcesses(limit: count))
        guard !window.isVisible else { throw failure("Layout window unexpectedly visible") }
        let bounds = controller.view.bounds
        guard let bitmap = controller.view.bitmapImageRepForCachingDisplay(in: bounds) else { throw failure("No layout bitmap") }
        controller.view.cacheDisplay(in: bounds, to: bitmap)
        try save(bitmap, name: name, fields: ["composited": false, "processCount": count, "contentHeight": bounds.height])
    }

    @MainActor private func actualPopover(_ button: NSStatusBarButton, background: NSWindow, name: String, count: Int, sample: PowerSnapshot) async throws {
        Settings.topProcessCount = count
        let controller = PopoverController()
        popover = controller
        controller.update(snapshot: sample, history: [10, 20, 30, 20], peak: 30, degraded: false)
        controller.updateTopProcesses(.ready(processes))
        controller.updateSystemBatteryIconState(false)
        controller.openForSettingsCommandTest(relativeTo: button)
        try await pause(0.45)
        guard let content = controller.contentViewForTest, let window = content.window,
              let scroll = descendants(content).compactMap({ $0 as? NSScrollView }).first,
              let document = scroll.documentView,
              let list = descendants(content).compactMap({ $0 as? TopProcessesView }).first,
              let footer = descendants(content).compactMap({ $0 as? PopoverFooterView }).first else { throw failure("Missing actual popup hierarchy") }
        footer.update(mode: .auto, helperInstalled: true, systemBatteryIconHidden: false, tint: PopoverStyle.stateColor(sample.state))
        try validate(list, count: count, expectedProcesses: Array(processes.prefix(count)))
        let scrolling = document.bounds.height > scroll.contentView.bounds.height + 1
        for position in scrolling ? ["top", "bottom"] : ["full"] {
            if position == "bottom" {
                scroll.contentView.scroll(to: .init(x: 0, y: max(0, document.bounds.height - scroll.contentView.bounds.height)))
                scroll.reflectScrolledClipView(scroll.contentView)
                try await pause(0.1)
                try check(scroll.documentVisibleRect.insetBy(dx: -0.5, dy: -0.5).contains(list.convert(list.bounds, to: document)), "Process rows clipped after bottom scroll: \(name)")
                try check(scroll.documentVisibleRect.insetBy(dx: -0.5, dy: -0.5).contains(footer.convert(footer.bounds, to: document)), "Footer unreachable: \(name)")
            }
            try composite(window, background: background, name: name + "-" + position, fields: ["processCount": count, "scrolling": scrolling, "listFrame": NSStringFromRect(list.convert(list.bounds, to: document))])
        }
        if count == 3 && name.contains("on-battery") {
            try await hostedHelp(list, controller: controller, background: background, name: name + "-help")
        }
        controller.handleOutsideClick()
        popover = nil
        try await pause(0.2)
    }

    @MainActor private func actualSettings(background: NSWindow, name: String) async throws {
        let dependencies = SettingsWindowDependencies(loginItemState: { .enabled }, refreshLoginItem: { $0(.enabled) }, setLoginItemEnabled: { value, completion in completion(.success(value ? .enabled : .notRegistered)) }, systemBatteryIconHidden: { false }, helperAvailable: { true }, refreshSystemBatteryIcon: { $0(false) }, setSystemBatteryIconHidden: { _, completion in completion(true) }, systemBatteryIconDidChange: Notification.Name("Wattson.TopProcessesCapture.Battery"), currentVersion: { "Development" }, checkForUpdates: { $0(.success(.upToDate(currentVersion: "Development"))) }, openUpdateURL: { _ in true }, increaseContrast: { false }, announceAccessibility: { _ in })
        let controller = SettingsWindowController(dependencies: dependencies, frameAutosaveName: nil)
        settings = controller
        controller.selectSectionForTest(identifier: "modules")
        controller.refreshSectionsForTest()
        guard let window = controller.windowForTest else { throw failure("No Settings window") }
        window.animationBehavior = .none
        window.makeKeyAndOrderFront(nil)
        try await pause(0.4)
        guard let content = window.contentView,
              let scroll = descendants(content).compactMap({ $0 as? NSScrollView }).first(where: { $0.identifier?.rawValue == "settings.modules.scroll" }),
              let document = scroll.documentView,
              let count = descendants(content).compactMap({ $0 as? NSPopUpButton }).first(where: { $0.identifier?.rawValue == "settings.modules.top-process-count" }) else { throw failure("No Settings process count control/scroll view") }
        let viewportFrame = scroll.convert(scroll.bounds, to: content)
        for identifier in ["settings.modules.subtitle", "settings.modules.restore-default-order"] {
            guard let fixedHeader = descendants(content).first(where: { $0.identifier?.rawValue == identifier }) else { throw failure("Missing fixed Settings header") }
            try check(!viewportFrame.intersects(fixedHeader.convert(fixedHeader.bounds, to: content)), "Module viewport overlaps fixed header: \(name) \(identifier)")
        }
        try composite(window, background: background, name: name + "-top", fields: ["count": Settings.topProcessCount])
        window.makeFirstResponder(count)
        try await pause(0.15)
        let visible = scroll.documentVisibleRect.insetBy(dx: -0.5, dy: -0.5)
        try check(visible.contains(count.convert(count.bounds, to: document)), "Count control unreachable: \(name)")
        guard let countRow = descendants(document).first(where: { $0.identifier?.rawValue == "settings.modules.row.topProcesses" }) else { throw failure("Missing process-count module row") }
        try check(visible.contains(countRow.convert(countRow.bounds, to: document)), "Process count row clipped: \(name)")
        try check(count.numberOfItems == 10 && count.isEnabled, "Count choices incomplete: \(name)")
        try composite(window, background: background, name: name + "-count", fields: ["count": Settings.topProcessCount, "countFrame": NSStringFromRect(count.convert(count.bounds, to: document)), "scrollVisibleRect": NSStringFromRect(visible)])
        window.close()
        settings = nil
    }

    private func validate(_ list: TopProcessesView, count: Int, expectedProcesses: [EnergyProcess]) throws {
        list.layoutSubtreeIfNeeded()
        try check(abs(list.bounds.height - TopProcessesView.preferredHeight(count: count)) < 0.1, "Wrong process-list height")
        let visibleViews = descendants(list).filter { !$0.isHiddenOrHasHiddenAncestor }
        guard let scoreHeader = list.subviews.compactMap({ $0 as? NSTextField }).first(where: { $0.stringValue == "Activity Score" }) else { throw failure("Missing Activity Score header") }
        try check(scoreHeader.intrinsicContentSize.width <= scoreHeader.bounds.width, "Activity Score header is clipped")
        let labels = visibleViews.compactMap { $0 as? NSTextField }.map(\.stringValue)
            + visibleViews.compactMap { $0.accessibilityLabel() }
        try check(expectedProcesses.map(\.name).allSatisfy(labels.contains), "A requested process name is missing")
        for view in visibleViews where view !== list && !view.bounds.isEmpty {
            try check(list.bounds.insetBy(dx: -0.5, dy: -0.5).contains(view.convert(view.bounds, to: list)), "Process content outside section")
        }
        let rows = list.subviews.filter { $0.identifier?.rawValue == "top-processes.row" && !$0.isHidden }
        let bars = list.barGeometryForTest
        try check(rows.count == expectedProcesses.count && bars.count == expectedProcesses.count, "Incorrect visible process-row count")
        for (index, process) in expectedProcesses.enumerated() {
            let bar = bars[index]
            let expectedRatio = CGFloat(min(max(process.energyImpact / 100, 0), 1))
            try check(abs(bar.ratio - expectedRatio) < 0.0001, "Bar does not use the fixed 0–100-point scale")
            try check(bar.track.height == 12 && bar.fill.height == 10, "Incorrect activity-bar height")
            try check(abs(bar.fill.width - (bar.track.width - 2) * expectedRatio) < 0.01, "Activity-bar fill does not match its fixed scale")
            let fields = rows[index].subviews.compactMap { $0 as? NSTextField }
            try check(fields.count == 3, "Expected process name, score and CPU/wakeups details")
            try check(fields[1].intrinsicContentSize.width <= fields[1].bounds.width, "Activity score is clipped")
            try check(fields[2].stringValue.contains("CPU") && fields[2].stringValue.contains("Idle wakeups"), "Missing CPU/wakeups detail")
            guard let marker = rows[index].subviews.first(where: { $0.identifier?.rawValue == "top-processes.overflow" }) else { throw failure("Missing overflow marker") }
            try check(marker.isHidden == (process.energyImpact <= 100), "Incorrect activity overflow state")
        }
    }

    @MainActor private func standaloneHelpLifecycle(_ list: TopProcessesView) async throws {
        guard let button = list.subviews.compactMap({ $0 as? NSButton }).first,
              let parent = list.superview else { throw failure("Missing standalone help button or parent") }
        button.performClick(nil)
        try await pause(0.15)
        try check(list.helpWindow?.isVisible == true, "Standalone info did not open")
        list.setPresentationActive(false)
        try await pause(0.1)
        try check(list.helpWindow == nil, "Inactive module retained info")
        list.setPresentationActive(true)
        button.performClick(nil)
        try await pause(0.1)
        list.isHidden = true
        try await pause(0.1)
        try check(list.helpWindow == nil, "Hidden module retained info")
        list.isHidden = false
        button.performClick(nil)
        try await pause(0.1)
        list.removeFromSuperview()
        try await pause(0.1)
        try check(list.helpWindow == nil, "Detached module retained info")
        parent.addSubview(list)
    }

    @MainActor private func hostedHelp(_ list: TopProcessesView, controller: PopoverController, background: NSWindow, name: String) async throws {
        guard let button = list.subviews.compactMap({ $0 as? NSButton }).first else { throw failure("Missing hosted info button") }
        button.performClick(nil)
        try await pause(0.25)
        guard let help = list.helpWindow, let content = help.contentView else { throw failure("Hosted info did not open") }
        try check(controller.isShownForTest && help.isVisible, "Opening info dismissed its production host")
        let point = NSPoint(x: help.frame.midX, y: help.frame.midY)
        try check(!controller.shouldDismissLocalClickForTest(window: help, screenPoint: point), "Actual info window is not exempt from local dismissal")
        let fields = descendants(content).compactMap { $0 as? NSTextField }.filter { !$0.isHiddenOrHasHiddenAncestor }
        try check(fields.contains { $0.stringValue.hasSuffix("one logical core.") }, "Info omits its final CPU convention")
        var heights: [[String: Any]] = []
        for field in fields {
            guard let cell = field.cell else { continue }
            let required = cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: field.bounds.width, height: 100_000))
            try check(required.height <= field.bounds.height + 0.5, "Info text cell requires \(required.height) points but only has \(field.bounds.height): \(field.stringValue)")
            heights.append(["text": field.stringValue, "requiredCellHeight": required.height, "frame": NSStringFromRect(field.frame)])
        }
        try composite(help, background: background, name: name, fields: ["actualInfoPopover": true, "textCellHeights": heights])
        button.performClick(nil)
        try await pause(0.15)
        try check(list.helpWindow == nil, "Second info-button click did not close info")
        button.performClick(nil)
        try await pause(0.1)
        controller.handleOutsideClick()
        try await pause(0.2)
        try check(list.helpWindow == nil, "Closing production popup retained info")
    }

    private func composite(_ window: NSWindow, background: NSWindow, name: String, fields: [String: Any]) throws {
        guard let screen = window.screen else { throw failure("No capture screen") }
        let region = NSRect(x: window.frame.minX - 8, y: screen.frame.maxY - window.frame.maxY - 8, width: window.frame.width + 16, height: window.frame.height + 16)
        guard window.isVisible, let image = WattsonCaptureOwnedWindows(region, CGWindowID(window.windowNumber), CGWindowID(background.windowNumber)) else { throw failure("WindowServer capture refused") }
        var metadata = fields
        metadata["composited"] = true
        metadata["windowFrame"] = NSStringFromRect(window.frame)
        metadata["glass"] = Settings.usesLiquidGlass
        try save(NSBitmapImageRep(cgImage: image), name: name, fields: metadata)
    }

    private func save(_ bitmap: NSBitmapImageRep, name: String, fields: [String: Any]) throws {
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw failure("PNG encoding failed") }
        try png.write(to: directory.appendingPathComponent(name + ".png"), options: .atomic)
        var record = fields
        record["case"] = name
        record["image"] = name + ".png"
        record["imageSHA256"] = SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined()
        record["pixels"] = [bitmap.pixelsWide, bitmap.pixelsHigh]
        records.append(record)
    }

    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    private func pause(_ seconds: Double) async throws { try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
    private func check(_ passed: Bool, _ message: String) throws { assertions += 1; if !passed { throw failure(message) } }
    private func failure(_ text: String) -> NSError { NSError(domain: "WattsonTopProcessesProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
}

private extension TopProcessesState {
    func visibleProcesses(limit: Int) -> [EnergyProcess] {
        if case .ready(let values) = self { return Array(values.prefix(limit)) }
        return []
    }
}
