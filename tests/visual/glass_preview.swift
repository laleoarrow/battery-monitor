import AppKit
import ScreenCaptureKit

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

        precondition(PreviewPresentation.allCases.map(\.title) == [
            "Classic", "Standard Glass", "Clear Glass"
        ])
        var synchronizedIndex = PreviewPresentation.current.rawValue
        let observer = NotificationCenter.default.addObserver(
            forName: Settings.didChange, object: nil, queue: nil
        ) { _ in
            synchronizedIndex = PreviewPresentation.current.rawValue
        }
        for selection in [PreviewPresentation.clearGlass, .classic, .standardGlass,
                          .classic, .clearGlass, .standardGlass] {
            synchronizedIndex = selection.rawValue
            // Capture the user's choice before a Settings notification can
            // synchronize the control to an intermediate enabled/style state.
            let capturedSelection = PreviewPresentation(rawValue: synchronizedIndex)!
            capturedSelection.apply()
            precondition(PreviewPresentation.current == selection)
            precondition(synchronizedIndex == selection.rawValue)
            precondition(Settings.liquidGlassEnabled == (selection != .classic))
            if selection != .classic {
                precondition(Settings.liquidGlassStyle == (selection == .clearGlass ? .clear : .regular))
            }
        }
        Settings.liquidGlassStyle = .clear
        precondition(synchronizedIndex == PreviewPresentation.clearGlass.rawValue)
        Settings.liquidGlassEnabled = false
        precondition(synchronizedIndex == PreviewPresentation.classic.rawValue)
        Settings.liquidGlassEnabled = true
        precondition(synchronizedIndex == PreviewPresentation.clearGlass.rawValue)
        precondition(independent.object(forKey: "appearance.liquidGlassStyle") == nil)
        NotificationCenter.default.removeObserver(observer)
        Settings.resetTestConfiguration()
        print("PREVIEW_DEFAULTS_SELF_TEST_PASSED: construction, memory read/write, isolation, Settings integration, three presentation mappings and notification synchronization")
    }
}

private enum PreviewPresentation: Int, CaseIterable {
    case classic, standardGlass, clearGlass

    var title: String {
        switch self {
        case .classic: return "Classic"
        case .standardGlass: return "Standard Glass"
        case .clearGlass: return "Clear Glass"
        }
    }

    static var current: Self {
        guard Settings.liquidGlassEnabled else { return .classic }
        return Settings.liquidGlassStyle == .clear ? .clearGlass : .standardGlass
    }

    func apply() {
        if self != .classic {
            Settings.liquidGlassStyle = self == .clearGlass ? .clear : .regular
        }
        Settings.liquidGlassEnabled = self != .classic
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
    private let theme = NSPopUpButton()
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
        PreviewPresentation.clearGlass.apply()
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
            self?.theme.selectItem(at: PreviewPresentation.current.rawValue)
            DispatchQueue.main.async { self?.updateFixtureFooter() }
        }
        buildControls()
        installMenu()
        updateFixture()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if let index = CommandLine.arguments.firstIndex(where: { ["--export-gallery", "--prepare-gallery"].contains($0) }),
           index + 1 < CommandLine.arguments.count, #available(macOS 14, *) {
            Task { @MainActor in
                do {
                    try await exportGallery(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
                    NSApp.terminate(nil)
                } catch {
                    fputs("GALLERY_FAILED: \(error)\n", stderr)
                    exit(1)
                }
            }
        }
        if CommandLine.arguments.contains("--verify-presentation-cycles") {
            DispatchQueue.main.async { self.verifyPresentationCycles() }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Opt-in GUI regression for this preview's real actions and observers.
    /// Run only in the disposable GUI test session, never on the user's desktop.
    private func verifyPresentationCycles() {
        func fail(_ message: String) -> Never {
            FileHandle.standardError.write(Data(("PREVIEW_PRESENTATION_CYCLES_FAILED: " + message + "\n").utf8))
            exit(1)
        }
        guard #available(macOS 26.0, *) else { fail("requires macOS 26") }
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { fail("60-second GUI watchdog expired") }
        guard let originalRoot = popover.contentViewForTest else { fail("missing production content") }
        func descendants(_ view: NSView) -> [NSView] {
            [view] + view.subviews.flatMap(descendants)
        }
        var checkCount = 0
        func check(_ phase: String, expected: PreviewPresentation, dark: Bool,
                   diagnostic: Bool, fixture: Int) {
            let panel = popover.glassPanelForTest
            let classic = popover.classicPopoverForTest
            let activeWindow = expected == .classic ? classic.contentViewController?.view.window : panel
            let installed = activeWindow?.contentView.map(descendants) ?? []
            let material = panel?.contentView?.subviews.compactMap { $0 as? NSGlassEffectView }.first
            let visibleGlassPanels = NSApp.windows.filter { $0 is GlassPopoverPanel && $0.isVisible }
            guard visibleGlassPanels.count == (expected == .classic ? 0 : 1),
                  visibleGlassPanels.allSatisfy({ $0 === panel }) else {
                fail("\(phase): orphaned glass windows=\(visibleGlassPanels.count), expected=\(expected.title)")
            }
            let hostMatches = expected == .classic
                ? panel == nil && classic.isShown
                : panel != nil && material?.contentView === originalRoot
                    && material?.style == (expected == .clearGlass ? .clear : .regular)
            let rootAttached = activeWindow != nil && originalRoot.window === activeWindow
                && installed.contains { $0 === originalRoot }
                && originalRoot.bounds.width > 0 && originalRoot.bounds.height > 0
                && !originalRoot.isHiddenOrHasHiddenAncestor
            let fields = installed.compactMap { $0 as? NSTextField }
            let footer = installed.compactMap { $0 as? PopoverFooterView }.first
            let footerVisible = footer.map {
                $0.window === activeWindow && !$0.isHiddenOrHasHiddenAncestor
                    && $0.bounds.width > 0 && $0.bounds.height > 0
            } == true
            guard PreviewPresentation.current == expected,
                  theme.indexOfSelectedItem == expected.rawValue,
                  (NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua) == dark,
                  backdrop.diagnostic == diagnostic,
                  (diagnosticBackdrop.state == .on) == diagnostic,
                  powerState.indexOfSelectedItem == fixture,
                  popover.cachedPercentForTest == [72, 100, 67, 41, 8, 42][fixture],
                  popover.isOpen, popover.isShownForTest, activeWindow?.isVisible == true,
                  hostMatches, rootAttached, footerVisible,
                  fields.contains(where: { !$0.stringValue.isEmpty && !$0.isHiddenOrHasHiddenAncestor }) else {
                fail("\(phase): expected=\(expected.title) selected=\(theme.indexOfSelectedItem) "
                    + "host=\(hostMatches) root=\(rootAttached) footer=\(footerVisible) "
                    + "fields=\(fields.count) open=\(popover.isOpen) shown=\(popover.isShownForTest) "
                    + "visible=\(activeWindow?.isVisible == true) "
                    + "appearance=\(NSApp.effectiveAppearance.name.rawValue) dark=\(dark) "
                    + "backdrop=\(backdrop.diagnostic)/\(diagnosticBackdrop.state.rawValue) expected=\(diagnostic) "
                    + "fixture=\(powerState.indexOfSelectedItem) expected=\(fixture) percent=\(popover.cachedPercentForTest ?? -1)")
            }
            checkCount += 1
            print("PREVIEW_CYCLE_OK: \(phase) \(expected.title) dark=\(dark) backdrop=\(diagnostic) fixture=\(fixture)")
            fflush(stdout)
        }
        let selections: [PreviewPresentation] = [.clearGlass, .classic, .standardGlass,
                                                 .classic, .clearGlass, .standardGlass]
        func run(_ index: Int) {
            guard index < selections.count * 4 else {
                popover.handleOutsideClick()
                print("PREVIEW_PRESENTATION_CYCLES_PASSED: 24 cycles, \(checkCount) checks")
                fflush(stdout)
                NSApp.terminate(nil)
                return
            }
            let dark = index / selections.count >= 2
            let diagnostic = (index / selections.count) % 2 == 1
            let selection = selections[index % selections.count]
            let fixture = index % 6
            let previous = PreviewPresentation.current
            let previousFixture = powerState.indexOfSelectedItem
            let previousBackdrop = backdrop.diagnostic
            appearance.selectedSegment = dark ? 1 : 0
            changeHostAppearance()
            check("\(index) host immediate", expected: previous, dark: dark,
                  diagnostic: previousBackdrop, fixture: previousFixture)
            diagnosticBackdrop.state = diagnostic ? .on : .off
            changeBackdrop()
            check("\(index) backdrop immediate", expected: previous, dark: dark,
                  diagnostic: diagnostic, fixture: previousFixture)
            theme.selectItem(at: selection.rawValue)
            changePresentation()
            check("\(index) presentation immediate", expected: selection, dark: dark,
                  diagnostic: diagnostic, fixture: previousFixture)
            powerState.selectItem(at: fixture)
            usb.state = index % 2 == 0 ? .off : .on
            changeFixture()
            check("\(index) fixture immediate", expected: selection, dark: dark,
                  diagnostic: diagnostic, fixture: fixture)
            Timer.scheduledTimer(withTimeInterval: 0.75, repeats: false) { _ in
                check("\(index) after native close delay", expected: selection, dark: dark,
                      diagnostic: diagnostic, fixture: fixture)
                run(index + 1)
            }
        }
        showPopover()
        Timer.scheduledTimer(withTimeInterval: 0.75, repeats: false) { _ in run(0) }
    }

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
            currentVersion: { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Preview" },
            checkForUpdates: { $0(.success(.upToDate(currentVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Preview"))) },
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
        theme.addItems(withTitles: PreviewPresentation.allCases.map(\.title))
        theme.selectItem(at: PreviewPresentation.current.rawValue)
        theme.frame = NSRect(x: 166, y: 300, width: 280, height: 30)
        theme.target = self
        theme.action = #selector(changePresentation)
        theme.setAccessibilityLabel("Preview presentation")
        controls.addSubview(theme)
        appearance.segmentCount = 2
        for (index, title) in ["Light", "Dark"].enumerated() {
            appearance.setLabel(title, forSegment: index)
            appearance.setWidth(120, forSegment: index)
        }
        appearance.selectedSegment = 1
        appearance.frame = NSRect(x: 166, y: 256, width: 280, height: 30)
        appearance.target = self
        appearance.action = #selector(changeHostAppearance)
        appearance.setAccessibilityLabel("Host appearance")
        controls.addSubview(appearance)
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
        for (index, title) in ["General", "Display", "Modules"].enumerated() {
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
        guard let selection = PreviewPresentation(rawValue: theme.indexOfSelectedItem) else { return }
        selection.apply()
        showPopover()
    }

    @objc private func changeHostAppearance() {
        NSApp.appearance = NSAppearance(named: appearance.selectedSegment == 0 ? .aqua : .darkAqua)
        showPopover()
    }

    @objc private func changeFixture() {
        previewMode = powerState.indexOfSelectedItem == 5 ? .low : .auto
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

    /// App-owned fixtures captured by WindowServer, with no capture permission prompt.
    @available(macOS 14, *)
    @MainActor private func exportGallery(to directory: URL) async throws {
        let externalCapture = CommandLine.arguments.contains("--prepare-gallery")
        guard externalCapture || CGPreflightScreenCaptureAccess() else {
            throw NSError(domain: "WattsonGallery", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Existing screen capture permission required"])
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        window.contentView?.subviews.filter { $0 !== backdrop && $0 !== anchor }
            .forEach { $0.isHidden = true }
        anchor.title = ""
        anchor.isBordered = false
        let transparencyGallery = CommandLine.arguments.contains("--transparency-gallery")
        let transparencyLevels = transparencyGallery ? [0.0, 0.5, 1.0] : [1.0]
        backdrop.diagnostic = transparencyGallery
        usb.state = .off
        if let screen = NSScreen.main { window.setFrame(screen.visibleFrame, display: true) }

        func descendants(_ view: NSView) -> [NSView] {
            [view] + view.subviews.flatMap(descendants)
        }
        func capture(_ target: NSWindow, name: String) async throws {
            let name = transparencyGallery
                ? "transparency-\(Int(Settings.liquidGlassTransparency * 100))-" + name : name
            NSApp.activate(ignoringOtherApps: true)
            target.makeKeyAndOrderFront(nil)
            target.contentView?.layoutSubtreeIfNeeded()
            try await Task.sleep(nanoseconds: 700_000_000)
            if externalCapture {
                let request = try JSONSerialization.data(withJSONObject: ["window": target.windowNumber, "name": name])
                try request.write(to: directory.appendingPathComponent("frame.json"), options: .atomic)
                let receipt = directory.appendingPathComponent(name + ".captured")
                for _ in 0..<600 {
                    if FileManager.default.fileExists(atPath: receipt.path) {
                        print("GALLERY_CAPTURED: \(name)")
                        fflush(stdout)
                        return
                    }
                    try await Task.sleep(nanoseconds: 100_000_000)
                }
                throw NSError(domain: "WattsonGallery", code: 5,
                              userInfo: [NSLocalizedDescriptionKey: "External capture timed out: \(name)"])
            }
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            guard let app = content.applications.first(where: { $0.processID == ProcessInfo.processInfo.processIdentifier }),
                  let item = content.windows.first(where: { $0.windowID == CGWindowID(target.windowNumber) }),
                  let display = content.displays.first(where: { $0.frame.contains(item.frame.insetBy(dx: -8, dy: -8)) }) else {
                throw NSError(domain: "WattsonGallery", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "Complete window unavailable: \(name)"])
            }
            let bounds = item.frame.insetBy(dx: -8, dy: -8)
            let config = SCStreamConfiguration()
            config.sourceRect = bounds.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
            config.width = Int(bounds.width * CGFloat(display.width) / display.frame.width)
            config.height = Int(bounds.height * CGFloat(display.height) / display.frame.height)
            config.showsCursor = false
            config.capturesAudio = false
            let filter = SCContentFilter(display: display, including: [app], exceptingWindows: [])
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            let bitmap = NSBitmapImageRep(cgImage: image)
            guard let png = bitmap.representation(using: .png, properties: [:]) else {
                throw NSError(domain: "WattsonGallery", code: 3)
            }
            try png.write(to: directory.appendingPathComponent(name + ".png"), options: .atomic)
            print("GALLERY_CAPTURED: \(name) \(config.width)x\(config.height)")
            fflush(stdout)
        }

        for transparency in transparencyLevels {
            Settings.liquidGlassTransparency = transparency
            for scheme in [Settings.ColorScheme.light, .dark] {
                Settings.colorScheme = scheme
                NSApp.appearance = scheme.appearance
                for presentation in [PreviewPresentation.clearGlass, .standardGlass, .classic] {
                    let style = ["classic", "standard", "clear"][presentation.rawValue]
                    presentation.apply()
                    let fixtures = presentation == .clearGlass ? Array(0..<6) : [0]
                    for fixture in fixtures {
                        powerState.selectItem(at: fixture)
                        previewMode = fixture == 5 ? .low : .auto
                        showPopover()
                        guard let target = popover.contentWindowForTest else {
                            throw NSError(domain: "WattsonGallery", code: 4)
                        }
                        let state = ["charging", "full", "battery", "mixed", "low-battery", "low-power"][fixture]
                        try await capture(target, name: "\(style)-\(state)-\(scheme.rawValue)")
                        popover.handleOutsideClick()
                        try await Task.sleep(nanoseconds: 650_000_000)
                    }
                }
                for glass in [true, false] {
                    Settings.liquidGlassEnabled = glass
                    for section in glass ? ["general", "appearance", "menu-bar-icon", "modules"] : ["appearance"] {
                        showSettingsSection(section == "appearance" ? "general" : section)
                        let target = settings.windowForTest!
                        let views = descendants(target.contentView!)
                        if let scroll = views.first(where: { $0.identifier?.rawValue == "settings.general.scroll" }) as? NSScrollView {
                            scroll.contentView.scroll(to: .zero)
                            target.contentView?.layoutSubtreeIfNeeded()
                            if section == "appearance", let appearance = views.first(where: {
                                $0.identifier?.rawValue == "settings.general.appearance"
                            }) { appearance.scrollToVisible(appearance.bounds) }
                        }
                        target.makeFirstResponder(nil)
                        try await capture(target, name: "settings-\(glass ? "glass" : "classic")-\(section)-\(scheme.rawValue)")
                        target.orderOut(nil)
                    }
                }
            }
        }
        let includeComparison = CommandLine.arguments.contains("--include-transparency-comparison")
        if includeComparison {
            backdrop.diagnostic = true
            PreviewPresentation.clearGlass.apply()
            powerState.selectItem(at: 1)
            previewMode = .auto
            for transparency in [0.0, 0.5, 1.0] {
                Settings.liquidGlassTransparency = transparency
                for scheme in [Settings.ColorScheme.light, .dark] {
                    Settings.colorScheme = scheme
                    NSApp.appearance = scheme.appearance
                    showPopover()
                    guard let target = popover.contentWindowForTest else {
                        throw NSError(domain: "WattsonGallery", code: 4)
                    }
                    try await capture(target, name: "transparency-\(Int(transparency * 100))-full-\(scheme.rawValue)")
                    popover.handleOutsideClick()
                    try await Task.sleep(nanoseconds: 650_000_000)
                }
            }
        }
        print("GALLERY_COMPLETE: \(26 * transparencyLevels.count + (includeComparison ? 6 : 0)) real compositor captures")
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
