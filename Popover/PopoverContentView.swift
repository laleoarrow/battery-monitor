import AppKit

typealias PopoverModule = Settings.Module

/// Hero number and state. No separator — it is the top of the surface.
final class PopoverHeaderView: PopoverSection {
    static let preferredHeight: CGFloat = 52

    private let total = NSTextField(labelWithString: "0.0")
    private let unit = NSTextField(labelWithString: "W")
    private let state = NSTextField(labelWithString: "--")
    private let percent = NSTextField(labelWithString: "")

    init() {
        super.init(height: Self.preferredHeight, showsSeparator: false)

        total.font = PopoverStyle.mono(29, .medium)
        total.textColor = PopoverStyle.primaryText
        addSubview(total)

        unit.font = PopoverStyle.mono(14)
        unit.textColor = PopoverStyle.secondaryText
        addSubview(unit)

        state.font = .systemFont(ofSize: 11, weight: .regular)
        state.textColor = PopoverStyle.secondaryText
        state.alignment = .right
        addSubview(state)

        percent.font = PopoverStyle.mono(13)
        percent.alignment = .right
        addSubview(percent)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        total.frame = NSRect(x: 0, y: 5, width: 150, height: 40)
        unit.frame = NSRect(x: totalWidth() + 5, y: 23, width: 30, height: 20)
        percent.frame = NSRect(x: bounds.width - 160, y: 7, width: 160, height: 20)
        state.frame = NSRect(x: bounds.width - 220, y: 29, width: 220, height: 16)
    }

    private func totalWidth() -> CGFloat {
        total.stringValue.size(withAttributes: [.font: total.font as Any]).width
    }

    func update(snapshot: PowerSnapshot, degraded: Bool) {
        total.stringValue = String(format: "%.1f", snapshot.totalInputW)
        if degraded {
            state.stringValue = "Read Failed · Last Reading"
            state.textColor = PopoverStyle.red
        } else if abs(snapshot.conservationError) > 2 {
            state.stringValue = String(format: "Data Issue · Imbalance %+.1f W", snapshot.conservationError)
            state.textColor = PopoverStyle.red
        } else {
            state.stringValue = PopoverStyle.stateTitle(snapshot.state)
            state.textColor = PopoverStyle.secondaryText
        }
        percent.stringValue = "\(snapshot.percent)%"
        percent.textColor = snapshot.percent <= 20 ? PopoverStyle.red : PopoverStyle.stateColor(snapshot.state)
        needsLayout = true
    }

#if DEBUG
    func layoutFitsForTest(snapshot: PowerSnapshot, degraded: Bool = false) -> Bool {
        update(snapshot: snapshot, degraded: degraded)
        layoutSubtreeIfNeeded()
        let fields = [total, unit, state, percent]
        return fields.allSatisfy { field in
            let required = field.stringValue.size(withAttributes: [.font: field.font as Any]).width
            return field.frame.minX >= 0
                && field.frame.minY >= 0
                && field.frame.maxX <= bounds.width
                && field.frame.maxY <= bounds.height
                && required <= field.frame.width
        }
    }

    func statePresentationForTest(snapshot: PowerSnapshot, degraded: Bool = false) ->
        (text: String, color: NSColor?) {
        update(snapshot: snapshot, degraded: degraded)
        return (state.stringValue, state.textColor)
    }
#endif
}

/// Native three-position mode control and system-battery visibility choice.
///
/// `ModeSliderView` owns the tactile Liquid Glass interaction on macOS 26 and
/// its keyboard, VoiceOver, and reduced-transparency fallback on older systems.
final class PopoverFooterView: PopoverSection {
    static let preferredHeight: CGFloat = 78
    private let modes: [EnergyMode] = [.auto, .low, .high]
    private lazy var modeControl = ModeSliderView(modes: modes)
    private lazy var systemBatteryIconButton = NSButton(
        checkboxWithTitle: "Hide System Battery Icon",
        target: self,
        action: #selector(systemBatteryIconChanged)
    )
    private let hint = NSTextField(labelWithString: "Right-click to switch modes")
    private let settingsButton = NSButton()

    private var selected: EnergyMode = .auto
    private var systemBatteryIconHidden: Bool?
    private var helperInstalled = false
    private var systemBatteryIconUpdateInFlight = false
    var onSelect: ((EnergyMode, @escaping (EnergyMode?) -> Void) -> Void)?
    var onSystemBatteryIconToggle: ((Bool, @escaping (Bool) -> Void) -> Void)?
    var onShowMenu: ((NSButton) -> Void)?

    init() {
        super.init(height: Self.preferredHeight)

        modeControl.onSelect = { [weak self] mode, completion in
            guard let self, let onSelect = self.onSelect else {
                completion(nil)
                return
            }
            onSelect(mode, completion)
        }
        addSubview(modeControl)

        systemBatteryIconButton.controlSize = .small
        systemBatteryIconButton.font = .systemFont(ofSize: 11, weight: .regular)
        systemBatteryIconButton.state = .mixed
        systemBatteryIconButton.setAccessibilityHelp("Hide the built-in macOS battery icon in the menu bar")
        addSubview(systemBatteryIconButton)

        hint.font = .systemFont(ofSize: 11, weight: .regular)
        hint.textColor = PopoverStyle.secondaryText
        hint.alignment = .right
        addSubview(hint)

        settingsButton.image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: "Choose Modules")
        settingsButton.isBordered = false
        settingsButton.contentTintColor = PopoverStyle.secondaryText
        settingsButton.target = self
        settingsButton.action = #selector(showMenu)
        addSubview(settingsButton)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        systemBatteryIconButton.frame = NSRect(x: 0, y: 10, width: 168, height: 20)
        hint.frame = NSRect(x: 168, y: 12, width: bounds.width - 168, height: 15)
        // The lifted lens extends about 15% beyond its resting plate. Reserve
        // that optical overscan so a High Power drag never covers the settings
        // button beside the track.
        modeControl.frame = NSRect(x: 0, y: 36, width: bounds.width - 46,
                                   height: ModeSliderView.preferredHeight)
        settingsButton.frame = NSRect(x: bounds.width - 22, y: 42, width: 22, height: 20)
    }

    func update(mode: EnergyMode, helperInstalled: Bool, systemBatteryIconHidden: Bool?,
                tint: NSColor) {
        selected = mode
        self.helperInstalled = helperInstalled
        self.systemBatteryIconHidden = systemBatteryIconHidden
        if let systemBatteryIconHidden {
            systemBatteryIconButton.state = systemBatteryIconHidden ? .on : .off
            systemBatteryIconButton.isEnabled = helperInstalled && !systemBatteryIconUpdateInFlight
        } else {
            systemBatteryIconButton.state = .mixed
            systemBatteryIconButton.isEnabled = false
        }
        hint.stringValue = helperInstalled
            ? (systemBatteryIconHidden == nil ? "Can’t Read System Settings" : "Right-click to switch modes")
            : "Helper Not Installed"
        // High power is only a real detent on hardware that has it, and none
        // of them are reachable without the helper.
        var available: [EnergyMode] = helperInstalled ? [.auto, .low] : []
        if helperInstalled && EnergyModeController.supportsHighPower { available.append(.high) }
        modeControl.update(selected: mode, enabledModes: available, tint: tint)
    }

    @objc private func systemBatteryIconChanged(_ sender: NSButton) {
        let requested = sender.state == .on
        guard let onSystemBatteryIconToggle else {
            sender.state = systemBatteryIconHidden == true ? .on : .off
            NSSound.beep()
            return
        }
        systemBatteryIconUpdateInFlight = true
        sender.isEnabled = false
        onSystemBatteryIconToggle(requested) { [weak self, weak sender] succeeded in
            guard let self, let sender else { return }
            self.systemBatteryIconUpdateInFlight = false
            if succeeded { self.systemBatteryIconHidden = requested }
            sender.state = self.systemBatteryIconHidden == true ? .on : .off
            sender.isEnabled = self.helperInstalled && self.systemBatteryIconHidden != nil
            if !succeeded { NSSound.beep() }
        }
    }

    @objc private func showMenu() { onShowMenu?(settingsButton) }
}

final class PopoverContentViewController: NSViewController {
    private let stack = NSStackView()
    private let header = PopoverHeaderView()
    private let flowView = PowerFlowView()
    private let ringView = RingGaugeView()
    private let laneView = LaneView()
    private let historyView = HistoryView()
    private let footer = PopoverFooterView()

    private var moduleVisibility: [PopoverModule: Bool] = [:]
    private var presentationActive = false
    private var animationsEnabled = false
    private var latestSnapshot = PowerSnapshot()
    private var latestHistory: [Double] = []
    private var latestPeak: Double = 0
    private var systemBatteryIconHidden: Bool?
    private var modeSelectHandler: ((EnergyMode, @escaping (EnergyMode?) -> Void) -> Void)?
    private var systemBatteryIconToggleHandler:
        ((Bool, @escaping (Bool) -> Void) -> Void)?
    private var settingsHandler: (() -> Void)?
    private var settingsObserver: NSObjectProtocol?
#if DEBUG
    private(set) var moduleUpdateCountsForTest: [PopoverModule: Int] = [:]
    private(set) var footerUpdateCountForTest = 0
#endif
    var heightDidChange: ((CGFloat) -> Void)?

    deinit {
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
    }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: PopoverStyle.width, height: 1))
        root.wantsLayer = true
        root.layer?.backgroundColor = PopoverStyle.surface.cgColor
        // The prototype is a dark instrument panel. Letting the popover follow
        // a light system appearance would wash every colour decision out.
        root.appearance = NSAppearance(named: .darkAqua)
        view = root
        buildContent()
    }

    var preferredHeight: CGFloat {
        var total = PopoverHeaderView.preferredHeight + PopoverFooterView.preferredHeight
        if isVisible(.flow) { total += PowerFlowView.preferredHeight }
        if isVisible(.ring) { total += RingGaugeView.preferredHeight }
        if isVisible(.lanes) { total += LaneView.preferredHeight }
        if isVisible(.history) { total += HistoryView.preferredHeight }
        return total + 24
    }

    func update(snapshot: PowerSnapshot, history: [Double], peak: Double, degraded: Bool) {
        latestSnapshot = snapshot
        latestHistory = history
        latestPeak = peak

        header.update(snapshot: snapshot, degraded: degraded)
        for module in PopoverModule.allCases where isVisible(module) {
            updateModule(module)
        }
        updateFooter()
    }

    private func updateModule(_ module: PopoverModule) {
#if DEBUG
        moduleUpdateCountsForTest[module, default: 0] += 1
#endif
        switch module {
        case .flow:
            flowView.update(snapshot: latestSnapshot, animated: animationsEnabled)
        case .ring:
            ringView.update(snapshot: latestSnapshot)
        case .lanes:
            laneView.update(snapshot: latestSnapshot)
        case .history:
            updateHistory()
        }
    }

    private func updateHistory() {
        let snapshot = latestSnapshot
        let historyColor = snapshot.state == .mixedSupply
            ? PopoverStyle.blue
            : PopoverStyle.stateColor(snapshot.state)
        historyView.update(samples: latestHistory, peak: latestPeak,
                           color: historyColor)
    }

    func setModeSelectHandler(
        _ handler: @escaping (EnergyMode, @escaping (EnergyMode?) -> Void) -> Void
    ) {
        modeSelectHandler = handler
    }

    func setSystemBatteryIconToggleHandler(
        _ handler: @escaping (Bool, @escaping (Bool) -> Void) -> Void
    ) {
        systemBatteryIconToggleHandler = handler
    }

    func setSettingsHandler(_ handler: @escaping () -> Void) {
        settingsHandler = handler
    }

    func updateSystemBatteryIconState(_ hidden: Bool?) {
        systemBatteryIconHidden = hidden
        updateFooter()
    }

    func refreshEnergyModeState() {
        updateFooter()
    }

    func setAnimationsEnabled(_ enabled: Bool) {
        animationsEnabled = enabled
        flowView.setAnimationsEnabled(enabled && !flowView.isHidden)
        ringView.setAnimationsEnabled(enabled && !ringView.isHidden)
        laneView.setAnimationsEnabled(enabled && !laneView.isHidden)
        if !enabled, let root = view.layer {
            removeAnimationsRecursively(from: root)
        }
    }

    func setPresentationActive(_ active: Bool) {
        presentationActive = active
    }

    private func removeAnimationsRecursively(from layer: CALayer) {
        layer.removeAllAnimations()
        layer.sublayers?.forEach(removeAnimationsRecursively)
    }

    private func isVisible(_ module: PopoverModule) -> Bool {
        moduleVisibility[module] ?? true
    }

    private func buildContent() {
        reloadModuleVisibility()
        observeSettingsChanges()

        stack.orientation = .vertical
        stack.alignment = .width
        stack.distribution = .fill
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        [header, flowView, ringView, laneView, historyView, footer].forEach(stack.addArrangedSubview)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: PopoverStyle.sideInset),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -PopoverStyle.sideInset),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            header.heightAnchor.constraint(equalToConstant: PopoverHeaderView.preferredHeight),
            flowView.heightAnchor.constraint(equalToConstant: PowerFlowView.preferredHeight),
            ringView.heightAnchor.constraint(equalToConstant: RingGaugeView.preferredHeight),
            laneView.heightAnchor.constraint(equalToConstant: LaneView.preferredHeight),
            historyView.heightAnchor.constraint(equalToConstant: HistoryView.preferredHeight),
            footer.heightAnchor.constraint(equalToConstant: PopoverFooterView.preferredHeight),
        ])

        footer.onSelect = { [weak self] mode, completion in
            guard let self, let handler = self.modeSelectHandler else {
                completion(nil)
                return
            }
            handler(mode, completion)
        }
        footer.onSystemBatteryIconToggle = { [weak self] hidden, completion in
            guard let handler = self?.systemBatteryIconToggleHandler else {
                completion(false)
                return
            }
            handler(hidden, completion)
        }
        footer.onShowMenu = { [weak self] button in self?.showModuleMenu(button) }
        applyModuleVisibility()
    }

    private func updateFooter() {
#if DEBUG
        footerUpdateCountForTest += 1
#endif
        footer.update(
            mode: EnergyModeController.current,
            helperInstalled: HelperClient.isInstalled,
            systemBatteryIconHidden: systemBatteryIconHidden,
            tint: PopoverStyle.stateColor(latestSnapshot.state)
        )
    }

    private func observeSettingsChanges() {
        settingsObserver = NotificationCenter.default.addObserver(
            forName: Settings.didChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let change = notification.userInfo?[Settings.changeUserInfoKey]
                    as? Settings.Change,
                  case .module = change else { return }
            self?.reloadModuleVisibility()
            self?.applyModuleVisibility()
        }
    }

    private func reloadModuleVisibility() {
        for module in PopoverModule.allCases {
            moduleVisibility[module] = Settings.isModuleVisible(module)
        }
    }

    private func applyModuleVisibility() {
        let views: [(PopoverModule, NSView)] = [
            (.flow, flowView), (.ring, ringView),
            (.lanes, laneView), (.history, historyView),
        ]
        for (module, moduleView) in views {
            let wasHidden = moduleView.isHidden
            moduleView.isHidden = !isVisible(module)
            if presentationActive && wasHidden && !moduleView.isHidden {
                updateModule(module)
            }
        }
        if animationsEnabled { setAnimationsEnabled(true) }
        heightDidChange?(preferredHeight)
    }

    private func showModuleMenu(_ sender: NSButton) {
        let menu = NSMenu(title: "Modules")
        for module in PopoverModule.allCases {
            let item = NSMenuItem(title: module.title, action: #selector(toggleModule(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = module.rawValue
            item.state = isVisible(module) ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let percentage = NSMenuItem(title: "Show Battery Percentage in Menu Bar",
                                    action: #selector(togglePercentage), keyEquivalent: "")
        percentage.target = self
        percentage.state = Settings.showsMenuBarPercentage ? .on : .off
        menu.addItem(percentage)

        let loginState = LoginItemController.state
        let loginTitle: String
        let loginMenuState: NSControl.StateValue
        switch loginState {
        case .checking:
            loginTitle = "Launch at Login (Checking…)"
            loginMenuState = .off
        case .notRegistered:
            loginTitle = "Launch at Login"
            loginMenuState = .off
        case .enabled:
            loginTitle = "Launch at Login"
            loginMenuState = .on
        case .unavailable:
            loginTitle = "Launch at Login (Full Installer Required)"
            loginMenuState = .off
        case .readFailed:
            loginTitle = "Launch at Login (Status Unavailable)"
            loginMenuState = .off
        }
        let loginItem = NSMenuItem(title: loginTitle,
                                   action: #selector(toggleLoginItem), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = loginMenuState
        loginItem.isEnabled = loginState == .notRegistered || loginState == .enabled
        menu.addItem(loginItem)

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(showSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        settingsItem.keyEquivalentModifierMask = [.command]
        menu.addItem(settingsItem)

        menu.addItem(.separator())
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "Development Build"
        let versionItem = NSMenuItem(
            title: "Wattson Version \(version)",
            action: nil,
            keyEquivalent: ""
        )
        versionItem.isEnabled = false
        menu.addItem(versionItem)

        menu.addItem(.separator())
        // The desktop panel used to own the only way out of the app. With it
        // gone this is the sole quit affordance, so it cannot be dropped.
        let quit = NSMenuItem(title: "Quit Wattson", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY + 4), in: sender)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    @objc private func showSettings() {
        settingsHandler?()
    }

    @objc private func togglePercentage() {
        Settings.showsMenuBarPercentage.toggle()
    }

    @objc private func toggleLoginItem() {
        let enable = LoginItemController.state != .enabled
        LoginItemController.setEnabled(enable) { result in
            guard case let .failure(error) = result else { return }
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Couldn’t Update Launch at Login"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    @objc private func toggleModule(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let module = PopoverModule(rawValue: raw) else { return }
        let visible = !isVisible(module)
        Settings.setModule(module, visible: visible)
    }

#if DEBUG
    func presentSettingsFromQuickMenuForTest() {
        showSettings()
    }

    func setModuleVisibleForTest(_ module: PopoverModule, visible: Bool) {
        Settings.setModule(module, visible: visible)
    }

    func toggleModuleFromMenuForTest(_ module: PopoverModule) {
        let item = NSMenuItem()
        item.representedObject = module.rawValue
        toggleModule(item)
    }

    func moduleIsHiddenForTest(_ module: PopoverModule) -> Bool {
        switch module {
        case .flow: return flowView.isHidden
        case .ring: return ringView.isHidden
        case .lanes: return laneView.isHidden
        case .history: return historyView.isHidden
        }
    }

    var latestHistoryForTest: [Double] { latestHistory }

    var runningAnimationCountForTest: Int {
        func count(_ layer: CALayer) -> Int {
            (layer.animationKeys()?.count ?? 0)
                + (layer.sublayers ?? []).reduce(0) { $0 + count($1) }
        }
        return view.layer.map(count) ?? 0
    }

    var runningModuleAnimationCountForTest: Int {
        func count(_ layer: CALayer) -> Int {
            (layer.animationKeys()?.count ?? 0)
                + (layer.sublayers ?? []).reduce(0) { $0 + count($1) }
        }
        return [flowView, ringView, laneView, historyView]
            .compactMap(\.layer)
            .reduce(0) { $0 + count($1) }
    }

    var runningAnimationDescriptionsForTest: [String] {
        func collect(_ layer: CALayer, path: String) -> [String] {
            let local = (layer.animationKeys() ?? []).map { "\(path):\($0)" }
            let nested = (layer.sublayers ?? []).enumerated().flatMap { index, child in
                collect(child, path: "\(path)/\(index)-\(type(of: child))")
            }
            return local + nested
        }
        guard let root = view.layer else { return [] }
        return collect(root, path: "root")
    }
#endif
}
