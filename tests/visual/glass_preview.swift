import AppKit

/// A visible fixture host for the shipping views. It never starts Wattson's
/// application delegate, sampler, helper refreshes, or update checker.
@main
private enum GlassPreview {
    static func main() {
        if CommandLine.arguments.contains("--verify-defaults") {
            verifyDefaults()
            return
        }
        let app = NSApplication.shared
        let delegate = PreviewDelegate()
        app.setActivationPolicy(.regular)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }

    /// Runs before NSApplication or the delegate can construct any windows.
    private static func verifyDefaults() {
        precondition(Bundle.main.bundleIdentifier == "com.leoarrow.wattson.glass-preview")
        let defaults = PreviewDefaults()
        let independent = PreviewDefaults()
        defaults.set("memory-only", forKey: "preview.probe")
        precondition(defaults.string(forKey: "preview.probe") == "memory-only")
        precondition(independent.object(forKey: "preview.probe") == nil)
        defaults.removeObject(forKey: "preview.probe")
        precondition(defaults.object(forKey: "preview.probe") == nil)
        Settings.configureForTest(defaults: defaults)
        precondition(!Settings.liquidGlassEnabled && Settings.showsMenuBarPercentage)
        Settings.liquidGlassEnabled = true
        Settings.showsMenuBarPercentage = false
        Settings.checksForUpdatesOnLaunch = false
        Settings.menuBarIconStyle = .native
        Settings.setModule(.flow, visible: false)
        precondition(Settings.liquidGlassEnabled && !Settings.showsMenuBarPercentage)
        precondition(!Settings.checksForUpdatesOnLaunch && Settings.menuBarIconStyle == .native)
        precondition(!Settings.isModuleVisible(.flow))
        precondition(independent.object(forKey: "appearance.liquidGlassEnabled") == nil)
        Settings.resetTestConfiguration()
        print("PREVIEW_DEFAULTS_SELF_TEST_PASSED: construction, memory read/write, isolation, Settings integration")
    }
}

/// Settings' existing DEBUG injection receives an in-memory preferences store.
private final class PreviewDefaults: UserDefaults {
    private var values: [String: Any] = [:]
    override func object(forKey key: String) -> Any? { values[key] }
    override func string(forKey key: String) -> String? { values[key] as? String }
    override func set(_ value: Any?, forKey key: String) { values[key] = value }
    override func set(_ value: Bool, forKey key: String) { values[key] = value }
    override func removeObject(forKey key: String) { values.removeValue(forKey: key) }
}

private final class PreviewDelegate: NSObject, NSApplicationDelegate {
    private let defaults = PreviewDefaults()
    private let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 900, height: 900),
        styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false
    )
    private let anchor = NSStatusBarButton(frame: .zero)
    private let theme = NSSegmentedControl()
    private let appearance = NSSegmentedControl()
    private let powerState = NSPopUpButton()
    private let diagnosticBackdrop = NSButton(checkboxWithTitle: "Diagnostic backdrop (test only)", target: nil, action: nil)
    private let backdrop = PreviewBackdrop()
    private let usb = NSButton(checkboxWithTitle: "USB device output", target: nil, action: nil)
    private let note = NSTextField(wrappingLabelWithString: "")
    private var popover: PopoverController!
    private var settings: SettingsWindowController!
    private var settingsObserver: NSObjectProtocol?
    private var hiddenBatteryIcon = false
    private var loginEnabled = true
    private var previewMode = EnergyMode.auto
    private var modeRequestCount = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        Settings.configureForTest(defaults: defaults)
        Settings.liquidGlassEnabled = true
        Settings.liquidGlassStyle = .clear
        Settings.checksForUpdatesOnLaunch = false
        // The production quick menu calls this controller directly. Its
        // existing test sender prevents even that path reaching the helper.
        LoginItemController.configureForTest(available: true, initialState: .enabled) { request, _ in
            ["ok": true, "enabled": request["enabled"] as? Bool ?? true]
        }
        SystemBatteryIconController.configureForTest(initialHidden: false) { request, _ in
            ["ok": true, "hidden": request["hidden"] as? Bool ?? false]
        }
        NSApp.appearance = NSAppearance(named: .darkAqua)
        popover = PopoverController()
        settings = SettingsWindowController(dependencies: mockDependencies(), frameAutosaveName: nil)
        settings.windowForTest?.title = "Wattson Glass Preview — Settings"
        settings.windowForTest?.center()
        popover.setModeSelectHandler { [weak self] mode, completion in
            self?.modeRequestCount += 1
            self?.previewMode = mode
            completion(mode)
            self?.updateNote()
        }
        popover.setSystemBatteryIconToggleHandler { [weak self] hidden, completion in
            self?.hiddenBatteryIcon = hidden
            self?.popover.updateSystemBatteryIconState(hidden)
            completion(true)
            self?.updateFixtureFooter()
        }
        popover.setSettingsHandler { [weak self] in self?.showSettingsSection("general") }
        settingsObserver = NotificationCenter.default.addObserver(
            forName: Settings.didChange, object: nil, queue: .main
        ) { [weak self] _ in
            self?.theme.selectedSegment = Settings.liquidGlassEnabled ? 1 : 0
            DispatchQueue.main.async { self?.updateFixtureFooter() }
        }
        buildControls()
        installMenu()
        updateFixture()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func mockDependencies() -> SettingsWindowDependencies {
        SettingsWindowDependencies(
            loginItemState: { [weak self] in self?.loginEnabled == true ? .enabled : .notRegistered },
            refreshLoginItem: { [weak self] done in
                done(self?.loginEnabled == true ? .enabled : .notRegistered)
            },
            setLoginItemEnabled: { [weak self] enabled, done in
                self?.loginEnabled = enabled
                done(.success(enabled ? .enabled : .notRegistered))
            },
            systemBatteryIconHidden: { [weak self] in self?.hiddenBatteryIcon },
            helperAvailable: { true },
            refreshSystemBatteryIcon: { [weak self] done in done(self?.hiddenBatteryIcon) },
            setSystemBatteryIconHidden: { [weak self] hidden, done in
                self?.hiddenBatteryIcon = hidden
                self?.popover.updateSystemBatteryIconState(hidden)
                done(true)
                self?.updateFixtureFooter()
            },
            systemBatteryIconDidChange: Notification.Name("Wattson.GlassPreview.MockBatteryIcon"),
            currentVersion: { "Local Fixture Preview" },
            checkForUpdates: { $0(.success(.upToDate(currentVersion: "Local Fixture Preview"))) },
            openUpdateURL: { _ in false },
            increaseContrast: { NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast },
            announceAccessibility: { _ in }
        )
    }

    private func buildControls() {
        window.title = "Wattson Glass Preview"
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.tabbingMode = .disallowed
        if let screen = NSScreen.main {
            window.setContentSize(NSSize(width: 900,
                                         height: min(screen.visibleFrame.height - 48, 900)))
            window.setFrameTopLeftPoint(NSPoint(x: screen.visibleFrame.minX + 24,
                                               y: screen.visibleFrame.maxY - 12))
        }
        guard let content = window.contentView else { return }
        backdrop.frame = content.bounds
        backdrop.autoresizingMask = [.width, .height]
        content.addSubview(backdrop)
        let controls = NSView(frame: NSRect(x: 0, y: content.bounds.height - 360,
                                            width: 470, height: 360))
        content.addSubview(controls)
        anchor.frame = NSRect(x: 520, y: content.bounds.height - 52, width: 360, height: 32)
        anchor.title = "Show Power Popover"
        anchor.bezelStyle = .rounded
        anchor.target = self
        anchor.action = #selector(showPopover)
        anchor.setAccessibilityLabel("Show Power Popover")
        content.addSubview(anchor)
        diagnosticBackdrop.frame = NSRect(x: 20, y: 332, width: 420, height: 24)
        diagnosticBackdrop.target = self
        diagnosticBackdrop.action = #selector(changeBackdrop)
        controls.addSubview(diagnosticBackdrop)
        for (title, y) in [("Presentation", 304.0), ("Host appearance", 260.0), ("Power fixture", 216.0)] {
            let label = NSTextField(labelWithString: title)
            label.frame = NSRect(x: 20, y: y, width: 140, height: 24)
            controls.addSubview(label)
        }
        for (control, labels, y) in [(theme, ["Classic", "Glass"], 300.0),
                                    (appearance, ["Light", "Dark"], 256.0)] {
            control.segmentCount = 2
            for (index, title) in labels.enumerated() {
                control.setLabel(title, forSegment: index)
                control.setWidth(120, forSegment: index)
            }
            control.selectedSegment = 1
            control.frame = NSRect(x: 166, y: y, width: 280, height: 30)
            control.target = self
            control.action = #selector(changePresentation)
            controls.addSubview(control)
        }
        theme.setAccessibilityLabel("Preview presentation")
        appearance.setAccessibilityLabel("Host appearance")
        powerState.addItems(withTitles: ["Charging", "Plugged In · Full", "On Battery",
                                        "Mixed Supply", "Low Battery", "Low Power"])
        powerState.frame = NSRect(x: 166, y: 212, width: 280, height: 30)
        powerState.target = self
        powerState.action = #selector(changeFixture)
        powerState.setAccessibilityLabel("Power fixture")
        controls.addSubview(powerState)
        usb.frame = NSRect(x: 166, y: 172, width: 280, height: 24)
        usb.target = self
        usb.action = #selector(changeFixture)
        controls.addSubview(usb)
        for (index, title) in ["General", "Menu Bar Icon", "Modules"].enumerated() {
            let button = NSButton(title: title, target: self, action: #selector(showSettings(_:)))
            button.tag = index
            button.frame = NSRect(x: 20 + index * 146, y: 128, width: 140, height: 32)
            controls.addSubview(button)
        }
        note.frame = NSRect(x: 20, y: 58, width: 430, height: 60)
        note.font = .systemFont(ofSize: 12)
        note.textColor = .secondaryLabelColor
        controls.addSubview(note)
    }

    private func installMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "Wattson Glass Preview")
        appMenu.addItem(withTitle: "Quit Wattson Glass Preview", action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)
        NSApp.mainMenu = menu
    }

    @objc private func changePresentation() {
        popover.handleOutsideClick()
        NSApp.appearance = NSAppearance(named: appearance.selectedSegment == 0 ? .aqua : .darkAqua)
        Settings.liquidGlassEnabled = theme.selectedSegment == 1
        updateFixture()
        showPopover()
    }

    @objc private func changeFixture() {
        previewMode = powerState.indexOfSelectedItem == 5 ? .low : .auto
        updateFixture()
        showPopover()
    }

    @objc private func changeBackdrop() {
        backdrop.diagnostic = diagnosticBackdrop.state == .on
        showPopover()
    }

    @objc private func showPopover() {
        updateFixture()
        popover.openForSettingsCommandTest(relativeTo: anchor)
        updateFixtureFooter()
    }

    @objc private func showSettings(_ sender: NSButton) {
        showSettingsSection(["general", "menu-bar-icon", "modules"][sender.tag])
    }

    private func showSettingsSection(_ identifier: String) {
        popover.handleOutsideClick()
        settings.selectSectionForTest(identifier: identifier)
        settings.show()
    }

    private var snapshot: PowerSnapshot {
        let values: (Int, Bool, Double, Double, Double)
        switch powerState.indexOfSelectedItem {
        case 1: values = (100, true, 45.8, 0, 45.8)
        case 2: values = (67, false, 0, -39.7, 39.7)
        case 3: values = (41, true, 28, -31.7, 59.7)
        case 4: values = (8, false, 0, -18, 18)
        case 5: values = (42, false, 0, -18, 18)
        default: values = (72, true, 68, 22.2, 45.8)
        }
        return PowerSnapshot(percent: values.0, plugged: values.1, adapterW: values.2,
                             batteryW: values.3, systemW: values.4,
                             deviceOutputW: usb.state == .on ? (values.1 ? 7.5 : 12.2) : nil,
                             temperatureC: 34.2, cycleCount: 282,
                             lowPowerMode: powerState.indexOfSelectedItem == 5)
    }

    private func updateFixture() {
        let sample = snapshot
        let history = (0..<32).map { sample.totalInputW * (0.88 + 0.08 * sin(Double($0) * 0.4)) }
        popover.update(snapshot: sample, history: history, peak: sample.totalInputW, degraded: false)
        popover.updateSystemBatteryIconState(hiddenBatteryIcon)
        updateFixtureFooter()
        updateNote()
    }

    private func updateNote() {
        note.stringValue = "Fixed fixture readings; system controls are simulated.\n"
            + "Mode requests: \(modeRequestCount) · \(previewMode.title) (mock only).\n"
            + "Diagnostic backdrop is not part of the shipping app."
    }

    private func updateFixtureFooter() {
        // The production footer normally reads the real mode cache. Exercise
        // its existing renderer with the fixture mode without touching pmset.
        func update(in view: NSView) {
            if let footer = view as? PopoverFooterView {
                footer.update(mode: previewMode, helperInstalled: true,
                              systemBatteryIconHidden: hiddenBatteryIcon,
                              tint: PopoverStyle.stateColor(snapshot.state))
            }
            view.subviews.forEach { update(in: $0) }
        }
        if let view = popover.contentViewForTest { update(in: view) }
    }
}

/// Test-only contrast edges behind the production window, never inside it.
private final class PreviewBackdrop: NSView {
    var diagnostic = false { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        guard diagnostic else { return }
        let colors: [NSColor] = [.systemBlue, .systemOrange, .systemTeal, .systemPink]
        for (index, color) in colors.enumerated() {
            color.withAlphaComponent(0.45).setFill()
            NSRect(x: CGFloat(index) * bounds.width / 4, y: 0,
                   width: bounds.width / 4, height: bounds.height).fill()
        }
        NSColor.white.withAlphaComponent(0.65).setStroke()
        let lines = NSBezierPath()
        lines.lineWidth = 1
        for x in stride(from: -bounds.height, to: bounds.width, by: 50) {
            lines.move(to: NSPoint(x: x, y: 0))
            lines.line(to: NSPoint(x: x + bounds.height * 0.3, y: bounds.height))
        }
        lines.stroke()
    }
}
