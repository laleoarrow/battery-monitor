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
    static let preferredHeight: CGFloat = 72

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
        total.frame = NSRect(x: 0, y: 12, width: 150, height: 36)
        unit.frame = NSRect(x: totalWidth() + 4, y: 27, width: 30, height: 20)
        percent.frame = NSRect(x: bounds.width - 160, y: 14, width: 160, height: 18)
        state.frame = NSRect(x: bounds.width - 200, y: 32, width: 200, height: 16)
        equation.frame = NSRect(x: 0, y: 52, width: bounds.width, height: 15)
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

/// Segmented 省电 / 自动 plus the right-click hint.
final class PopoverFooterView: PopoverSection {
    static let preferredHeight: CGFloat = 46

    private let group = CALayer()
    private let selection = CALayer()
    private let lowLabel = NSTextField(labelWithString: "省电")
    private let autoLabel = NSTextField(labelWithString: "自动")
    private let hint = NSTextField(labelWithString: "右键图标可切换")
    private let settingsButton = NSButton()

    private var isLow = false
    var onToggle: (() -> Bool)?
    var onShowMenu: ((NSButton) -> Void)?

    init() {
        super.init(height: Self.preferredHeight)

        group.backgroundColor = PopoverStyle.well.cgColor
        group.cornerRadius = 7
        group.cornerCurve = .continuous
        layer?.addSublayer(group)

        selection.backgroundColor = NSColor(rgb: 0x3A3A42).cgColor
        selection.cornerRadius = 5
        selection.cornerCurve = .continuous
        group.addSublayer(selection)

        for field in [lowLabel, autoLabel] {
            field.font = .systemFont(ofSize: 11, weight: .regular)
            field.alignment = .center
            addSubview(field)
        }

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

        let click = NSClickGestureRecognizer(target: self, action: #selector(toggleTapped))
        addGestureRecognizer(click)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        let top = PopoverStyle.sectionPadding - 2
        PopoverStyle.setWithoutAnimation {
            self.group.frame = CGRect(x: 0, y: top, width: 108, height: 24)
            self.selection.frame = CGRect(x: self.isLow ? 2 : 54, y: 2, width: 52, height: 20)
        }
        lowLabel.frame = NSRect(x: 2, y: top + 5, width: 52, height: 15)
        autoLabel.frame = NSRect(x: 54, y: top + 5, width: 52, height: 15)
        settingsButton.frame = NSRect(x: bounds.width - 24, y: top + 2, width: 22, height: 20)
        hint.frame = NSRect(x: bounds.width - 190, y: top + 5, width: 158, height: 15)
    }

    func update(isLowPower: Bool, helperInstalled: Bool) {
        isLow = isLowPower
        lowLabel.textColor = isLowPower ? PopoverStyle.primaryText : PopoverStyle.secondaryText
        autoLabel.textColor = isLowPower ? PopoverStyle.secondaryText : PopoverStyle.primaryText
        hint.stringValue = helperInstalled ? "右键图标可切换" : "助手未安装"
        group.opacity = helperInstalled ? 1 : 0.45
        needsLayout = true
    }

    @objc private func toggleTapped(_ sender: NSClickGestureRecognizer) {
        let point = sender.location(in: self)
        guard group.frame.contains(point) else { return }
        _ = onToggle?()
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
    private var modeToggleHandler: (() -> Bool)?
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
        return total + 8
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
        footer.update(isLowPower: EnergyModeController.current == .low,
                      helperInstalled: HelperClient.isInstalled)
    }

    func setModeToggleHandler(_ handler: @escaping () -> Bool) {
        modeToggleHandler = handler
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
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 4),
            header.heightAnchor.constraint(equalToConstant: PopoverHeaderView.preferredHeight),
            flowView.heightAnchor.constraint(equalToConstant: PowerFlowView.preferredHeight),
            ringView.heightAnchor.constraint(equalToConstant: RingGaugeView.preferredHeight),
            laneView.heightAnchor.constraint(equalToConstant: LaneView.preferredHeight),
            historyView.heightAnchor.constraint(equalToConstant: HistoryView.preferredHeight),
            footer.heightAnchor.constraint(equalToConstant: PopoverFooterView.preferredHeight),
        ])

        footer.onToggle = { [weak self] in self?.modeToggleHandler?() ?? false }
        footer.onShowMenu = { [weak self] button in self?.showModuleMenu(button) }
        applyModuleVisibility()
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
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY + 4), in: sender)
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
