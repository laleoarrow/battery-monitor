import AppKit

enum PopoverModule: String, CaseIterable {
    case flow, ring, lanes, history

    /// Only ever shown in the module picker. The sections carry no titles —
    /// labelling a ring "ring gauge" costs vertical space and tells the reader
    /// nothing they cannot already see.
    var title: String {
        switch self {
        case .flow: return "能量流"
        case .ring: return "环形仪表"
        case .lanes: return "功率泳道"
        case .history: return "功率历史"
        }
    }

    var defaultsKey: String { "popover.module.\(rawValue)" }
}

/// Hero number, state, and the conservation line. No separator — it is the top
/// of the surface.
final class PopoverHeaderView: PopoverSection {
    static let preferredHeight: CGFloat = 94

    private let total = NSTextField(labelWithString: "0.0")
    private let unit = NSTextField(labelWithString: "W")
    private let state = NSTextField(labelWithString: "--")
    private let percent = NSTextField(labelWithString: "")
    private let equation = NSTextField(labelWithString: "")

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

        equation.font = PopoverStyle.mono(11, .regular)
        equation.textColor = PopoverStyle.tertiaryText
        addSubview(equation)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        // The hero block and the conservation line are separate thoughts, so
        // they get a real gap rather than sitting a few points apart.
        total.frame = NSRect(x: 0, y: 16, width: 150, height: 40)
        unit.frame = NSRect(x: totalWidth() + 5, y: 34, width: 30, height: 20)
        percent.frame = NSRect(x: bounds.width - 160, y: 18, width: 160, height: 20)
        state.frame = NSRect(x: bounds.width - 220, y: 40, width: 220, height: 16)
        equation.frame = NSRect(x: 0, y: 70, width: bounds.width, height: 15)
    }

    private func totalWidth() -> CGFloat {
        total.stringValue.size(withAttributes: [.font: total.font as Any]).width
    }

    func update(snapshot: PowerSnapshot, degraded: Bool) {
        total.stringValue = String(format: "%.1f", snapshot.totalInputW)
        state.stringValue = degraded ? "读取失败 · 上次数据" : PopoverStyle.stateTitle(snapshot.state)
        state.textColor = degraded ? PopoverStyle.red : PopoverStyle.secondaryText
        percent.stringValue = "\(snapshot.percent)%"
        percent.textColor = snapshot.percent <= 20 ? PopoverStyle.red : PopoverStyle.stateColor(snapshot.state)
        equation.stringValue = conservationText(snapshot)
        equation.textColor = abs(snapshot.conservationError) > 2 ? PopoverStyle.red : PopoverStyle.tertiaryText
        needsLayout = true
    }

    /// Not decoration: if this equation stops balancing, a field was parsed
    /// wrong and every number above it is suspect.
    private func conservationText(_ snapshot: PowerSnapshot) -> String {
        let adapter = String(format: "%.1f", snapshot.adapterW)
        let battery = String(format: "%.1f", abs(snapshot.batteryW))
        let system = String(format: "%.1f", snapshot.systemW)
        let base: String
        switch snapshot.state {
        case .charging:    base = "\(adapter) 入  =  \(system) 系统  +  \(battery) 充入"
        case .pluggedIdle: base = "\(adapter) 入  =  \(system) 系统  ·  电池不进不出"
        case .onBattery:   base = "\(battery) 电池  =  \(system) 系统"
        case .mixedSupply: base = "\(adapter) 适配器  +  \(battery) 电池  =  \(system) 系统"
        }
        guard abs(snapshot.conservationError) > 2 else { return base }
        return base + String(format: "   偏差 %+.1f W", snapshot.conservationError)
    }
}

/// Native three-position mode control and system-battery visibility choice.
///
/// On macOS 26, NSSegmentedControl adopts Liquid Glass automatically. Keeping
/// the standard control also preserves keyboard and accessibility behavior on
/// older systems, where AppKit supplies the appropriate fallback appearance.
final class PopoverFooterView: PopoverSection {
    static let preferredHeight: CGFloat = 78
    private let modes: [EnergyMode] = [.auto, .low, .high]
    private lazy var modeControl = NSSegmentedControl(
        labels: modes.map(\.title),
        trackingMode: .selectOne,
        target: self,
        action: #selector(modeChanged)
    )
    private lazy var systemBatteryIconButton = NSButton(
        checkboxWithTitle: "隐藏系统电池图标",
        target: self,
        action: #selector(systemBatteryIconChanged)
    )
    private let hint = NSTextField(labelWithString: "右键图标可切换")
    private let settingsButton = NSButton()

    private var selected: EnergyMode = .auto
    private var systemBatteryIconHidden: Bool?
    var onSelect: ((EnergyMode) -> Bool)?
    var onSystemBatteryIconToggle: ((Bool) -> Bool)?
    var onShowMenu: ((NSButton) -> Void)?

    init() {
        super.init(height: Self.preferredHeight)

        modeControl.segmentStyle = .automatic
        modeControl.segmentDistribution = .fillEqually
        modeControl.controlSize = .small
        modeControl.font = .systemFont(ofSize: 11, weight: .medium)
        modeControl.setAccessibilityLabel("性能模式")
        let highIndex = modes.firstIndex(of: .high)!
        modeControl.setEnabled(EnergyModeController.supportsHighPower, forSegment: highIndex)
        if !EnergyModeController.supportsHighPower {
            modeControl.setToolTip("此 Mac 不支持高性能模式", forSegment: highIndex)
        }
        addSubview(modeControl)

        systemBatteryIconButton.controlSize = .small
        systemBatteryIconButton.font = .systemFont(ofSize: 11, weight: .regular)
        systemBatteryIconButton.state = .mixed
        systemBatteryIconButton.setAccessibilityHelp("隐藏 macOS 自带的菜单栏电池图标")
        addSubview(systemBatteryIconButton)

        hint.font = .systemFont(ofSize: 11, weight: .regular)
        hint.textColor = PopoverStyle.secondaryText
        hint.alignment = .right
        addSubview(hint)

        settingsButton.image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: "选择显示模块")
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
        modeControl.frame = NSRect(x: 0, y: 38, width: bounds.width - 34, height: 28)
        settingsButton.frame = NSRect(x: bounds.width - 22, y: 42, width: 22, height: 20)
    }

    func update(mode: EnergyMode, helperInstalled: Bool, systemBatteryIconHidden: Bool?) {
        selected = mode
        self.systemBatteryIconHidden = systemBatteryIconHidden
        modeControl.selectedSegment = modes.firstIndex(of: mode) ?? 0
        modeControl.isEnabled = helperInstalled
        if let systemBatteryIconHidden {
            systemBatteryIconButton.state = systemBatteryIconHidden ? .on : .off
            systemBatteryIconButton.isEnabled = helperInstalled
        } else {
            systemBatteryIconButton.state = .mixed
            systemBatteryIconButton.isEnabled = false
        }
        hint.stringValue = helperInstalled
            ? (systemBatteryIconHidden == nil ? "系统设置不可读" : "右键图标可切换")
            : "助手未安装"
        let highIndex = modes.firstIndex(of: .high)!
        modeControl.setEnabled(helperInstalled && EnergyModeController.supportsHighPower,
                               forSegment: highIndex)
    }

    @objc private func modeChanged(_ sender: NSSegmentedControl) {
        guard modes.indices.contains(sender.selectedSegment) else { return }
        let requested = modes[sender.selectedSegment]
        guard onSelect?(requested) == true else {
            sender.selectedSegment = modes.firstIndex(of: selected) ?? 0
            NSSound.beep()
            return
        }
        selected = requested
    }

    @objc private func systemBatteryIconChanged(_ sender: NSButton) {
        let requested = sender.state == .on
        guard onSystemBatteryIconToggle?(requested) == true else {
            sender.state = systemBatteryIconHidden == true ? .on : .off
            NSSound.beep()
            return
        }
        systemBatteryIconHidden = requested
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
    private var animationsEnabled = false
    private var latestSnapshot = PowerSnapshot()
    private var latestHistory: [Double] = []
    private var latestPeak: Double = 0
    private var systemBatteryIconHidden: Bool?
    private var modeSelectHandler: ((EnergyMode) -> Bool)?
    private var systemBatteryIconToggleHandler: ((Bool) -> Bool)?
    var heightDidChange: ((CGFloat) -> Void)?

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
        if !history.isEmpty { latestHistory = history; latestPeak = peak }

        header.update(snapshot: snapshot, degraded: degraded)
        flowView.update(snapshot: snapshot, animated: true)
        ringView.update(snapshot: snapshot)
        laneView.update(snapshot: snapshot)
        historyView.update(samples: latestHistory, peak: latestPeak,
                           color: PopoverStyle.stateColor(snapshot.state))
        updateFooter()
    }

    func setModeSelectHandler(_ handler: @escaping (EnergyMode) -> Bool) {
        modeSelectHandler = handler
    }

    func setSystemBatteryIconToggleHandler(_ handler: @escaping (Bool) -> Bool) {
        systemBatteryIconToggleHandler = handler
    }

    func updateSystemBatteryIconState(_ hidden: Bool?) {
        systemBatteryIconHidden = hidden
        updateFooter()
    }

    func setAnimationsEnabled(_ enabled: Bool) {
        animationsEnabled = enabled
        flowView.setAnimationsEnabled(enabled && !flowView.isHidden)
        ringView.setAnimationsEnabled(enabled && !ringView.isHidden)
        laneView.setAnimationsEnabled(enabled && !laneView.isHidden)
        if !enabled { view.layer?.removeAllAnimations() }
    }

    private func isVisible(_ module: PopoverModule) -> Bool { moduleVisibility[module] ?? true }

    private func buildContent() {
        loadModuleVisibility()

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

        footer.onSelect = { [weak self] mode in self?.modeSelectHandler?(mode) ?? false }
        footer.onSystemBatteryIconToggle = { [weak self] hidden in
            self?.systemBatteryIconToggleHandler?(hidden) ?? false
        }
        footer.onShowMenu = { [weak self] button in self?.showModuleMenu(button) }
        applyModuleVisibility()
    }

    private func updateFooter() {
        footer.update(
            mode: EnergyModeController.current,
            helperInstalled: HelperClient.isInstalled,
            systemBatteryIconHidden: systemBatteryIconHidden
        )
    }

    private func loadModuleVisibility() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: Dictionary(uniqueKeysWithValues: PopoverModule.allCases.map { ($0.defaultsKey, true) }))
        for module in PopoverModule.allCases {
            moduleVisibility[module] = defaults.bool(forKey: module.defaultsKey)
        }
    }

    private func applyModuleVisibility() {
        flowView.isHidden = !isVisible(.flow)
        ringView.isHidden = !isVisible(.ring)
        laneView.isHidden = !isVisible(.lanes)
        historyView.isHidden = !isVisible(.history)
        if animationsEnabled { setAnimationsEnabled(true) }
        heightDidChange?(preferredHeight)
    }

    private func showModuleMenu(_ sender: NSButton) {
        let menu = NSMenu(title: "显示模块")
        for module in PopoverModule.allCases {
            let item = NSMenuItem(title: module.title, action: #selector(toggleModule(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = module.rawValue
            item.state = isVisible(module) ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let percentage = NSMenuItem(title: "菜单栏显示电量百分比",
                                    action: #selector(togglePercentage), keyEquivalent: "")
        percentage.target = self
        percentage.state = Settings.showsMenuBarPercentage ? .on : .off
        menu.addItem(percentage)

        menu.addItem(.separator())
        // The desktop panel used to own the only way out of the app. With it
        // gone this is the sole quit affordance, so it cannot be dropped.
        let quit = NSMenuItem(title: "退出 Wattson", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY + 4), in: sender)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    @objc private func togglePercentage() {
        Settings.showsMenuBarPercentage.toggle()
    }

    @objc private func toggleModule(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let module = PopoverModule(rawValue: raw) else { return }
        let visible = !isVisible(module)
        moduleVisibility[module] = visible
        UserDefaults.standard.set(visible, forKey: module.defaultsKey)
        applyModuleVisibility()
    }
}
