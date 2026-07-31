import AppKit

private enum PopoverModule: String, CaseIterable {
    case flow
    case ring
    case lanes
    case history

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

final class PopoverContentViewController: NSViewController {
    private static let headerHeight: CGFloat = 62
    private static let equationHeight: CGFloat = 22
    private static let flowHeight: CGFloat = 132
    private static let ringHeight: CGFloat = 104
    private static let laneHeight: CGFloat = 92
    private static let historyHeight: CGFloat = 96
    private static let footerHeight: CGFloat = 44
    private static let verticalMargin: CGFloat = 16
    private static let spacing: CGFloat = 8

    private let stack = NSStackView()
    private let headerView = NSView()
    private let totalLabel = NSTextField(labelWithString: "0.0")
    private let unitLabel = NSTextField(labelWithString: "W")
    private let stateLabel = NSTextField(labelWithString: "--")
    private let percentLabel = NSTextField(labelWithString: "0%")
    private let equationLabel = NSTextField(labelWithString: "--")

    private let powerFlowView = PowerFlowView()
    private let ringGaugeView = RingGaugeView()
    private let laneView = LaneView()
    private let historyView = HistoryView()

    private let footerView = NSView()
    private let modeTitle = NSTextField(labelWithString: "省电模式")
    private let modeSwitch = NSSwitch()
    private let hintLabel = NSTextField(labelWithString: "右键菜单栏图标可切换")
    private let settingsButton = NSButton()

    private var moduleVisibility: [PopoverModule: Bool] = [:]
    private var animationsEnabled = false
    private var latestSnapshot = PowerSnapshot()
    private var modeToggleHandler: (() -> Bool)?
    var heightDidChange: ((CGFloat) -> Void)?

    override func loadView() {
        let root = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: PopoverStyle.width, height: 1))
        root.material = .popover
        root.blendingMode = .behindWindow
        root.state = .active
        view = root
        buildContent()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        totalLabel.frame = NSRect(x: 0, y: 3, width: 146, height: 43)
        unitLabel.frame = NSRect(x: 150, y: 21, width: 30, height: 24)
        stateLabel.frame = NSRect(x: 190, y: 7, width: 138, height: 20)
        percentLabel.frame = NSRect(x: 190, y: 30, width: 138, height: 24)

        modeTitle.frame = NSRect(x: 0, y: 3, width: 66, height: 20)
        modeSwitch.frame = NSRect(x: 70, y: 1, width: 42, height: 24)
        hintLabel.frame = NSRect(x: 124, y: 5, width: 166, height: 18)
        settingsButton.frame = NSRect(x: 298, y: 0, width: 30, height: 28)
    }

    var preferredHeight: CGFloat {
        var heights: [CGFloat] = [Self.headerHeight, Self.equationHeight]
        if moduleVisibility[.flow] ?? true { heights.append(Self.flowHeight) }
        if moduleVisibility[.ring] ?? true { heights.append(Self.ringHeight) }
        if moduleVisibility[.lanes] ?? true { heights.append(Self.laneHeight) }
        if moduleVisibility[.history] ?? true { heights.append(Self.historyHeight) }
        heights.append(Self.footerHeight)
        return heights.reduce(0, +) + CGFloat(max(heights.count - 1, 0)) * Self.spacing + Self.verticalMargin * 2
    }

    func update(snapshot: PowerSnapshot, history: [Double], peak: Double, degraded: Bool) {
        latestSnapshot = snapshot
        let stateColor = PopoverStyle.stateColor(snapshot.state)
        totalLabel.stringValue = String(format: "%.1f", snapshot.totalInputW)
        stateLabel.stringValue = degraded ? "读取失败 · 显示上次数据" : PopoverStyle.stateTitle(snapshot.state)
        stateLabel.textColor = degraded ? .systemRed : stateColor
        percentLabel.stringValue = "\(snapshot.percent)%"
        percentLabel.textColor = snapshot.percent <= 20 ? .systemRed : .labelColor

        equationLabel.stringValue = conservationText(snapshot)
        equationLabel.textColor = abs(snapshot.conservationError) > 2 ? .systemRed : .secondaryLabelColor

        powerFlowView.update(snapshot: snapshot, animated: true)
        ringGaugeView.update(snapshot: snapshot)
        laneView.update(snapshot: snapshot)
        historyView.update(samples: history, peak: peak, color: stateColor)
        refreshModeControls()
    }

    func setModeToggleHandler(_ handler: @escaping () -> Bool) {
        modeToggleHandler = handler
    }

    func setAnimationsEnabled(_ enabled: Bool) {
        animationsEnabled = enabled
        powerFlowView.setAnimationsEnabled(enabled && !powerFlowView.isHidden)
        ringGaugeView.setAnimationsEnabled(enabled && !ringGaugeView.isHidden)
        laneView.setAnimationsEnabled(enabled && !laneView.isHidden)
        if !enabled {
            view.layer?.removeAllAnimations()
        }
    }

    private func buildContent() {
        configureLabels()
        loadModuleVisibility()

        stack.orientation = .vertical
        stack.alignment = .width
        stack.distribution = .fill
        stack.spacing = Self.spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        let arrangedViews = [
            headerView,
            equationLabel,
            powerFlowView,
            ringGaugeView,
            laneView,
            historyView,
            footerView,
        ]
        arrangedViews.forEach(stack.addArrangedSubview)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: Self.verticalMargin),
            headerView.heightAnchor.constraint(equalToConstant: Self.headerHeight),
            equationLabel.heightAnchor.constraint(equalToConstant: Self.equationHeight),
            powerFlowView.heightAnchor.constraint(equalToConstant: Self.flowHeight),
            ringGaugeView.heightAnchor.constraint(equalToConstant: Self.ringHeight),
            laneView.heightAnchor.constraint(equalToConstant: Self.laneHeight),
            historyView.heightAnchor.constraint(equalToConstant: Self.historyHeight),
            footerView.heightAnchor.constraint(equalToConstant: Self.footerHeight),
        ])

        applyModuleVisibility()
    }

    private func configureLabels() {
        totalLabel.font = .monospacedDigitSystemFont(ofSize: 34, weight: .semibold)
        totalLabel.textColor = .labelColor
        totalLabel.alignment = .right
        headerView.addSubview(totalLabel)

        unitLabel.font = .monospacedDigitSystemFont(ofSize: 16, weight: .medium)
        unitLabel.textColor = .secondaryLabelColor
        headerView.addSubview(unitLabel)

        stateLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        stateLabel.alignment = .right
        headerView.addSubview(stateLabel)

        percentLabel.font = .monospacedDigitSystemFont(ofSize: 20, weight: .semibold)
        percentLabel.alignment = .right
        headerView.addSubview(percentLabel)

        equationLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        equationLabel.alignment = .center
        equationLabel.lineBreakMode = .byClipping

        modeTitle.font = .systemFont(ofSize: 12, weight: .semibold)
        modeTitle.textColor = .labelColor
        footerView.addSubview(modeTitle)

        modeSwitch.target = self
        modeSwitch.action = #selector(modeChanged(_:))
        footerView.addSubview(modeSwitch)

        hintLabel.font = .systemFont(ofSize: 10, weight: .regular)
        hintLabel.textColor = .tertiaryLabelColor
        hintLabel.lineBreakMode = .byTruncatingTail
        footerView.addSubview(hintLabel)

        settingsButton.image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: "选择显示模块")
        settingsButton.bezelStyle = .texturedRounded
        settingsButton.isBordered = false
        settingsButton.target = self
        settingsButton.action = #selector(showModuleMenu(_:))
        footerView.addSubview(settingsButton)
    }

    private func conservationText(_ snapshot: PowerSnapshot) -> String {
        let adapter = String(format: "%.1f", snapshot.adapterW)
        let battery = String(format: "%.1f", abs(snapshot.batteryW))
        let system = String(format: "%.1f", snapshot.systemW)
        let equation: String
        switch snapshot.state {
        case .charging:
            equation = "\(adapter) 适配器 = \(system) 系统 + \(battery) 电池"
        case .pluggedIdle:
            equation = "\(adapter) 适配器 = \(system) 系统"
        case .onBattery:
            equation = "\(battery) 电池 = \(system) 系统"
        case .mixedSupply:
            equation = "\(adapter) 适配器 + \(battery) 电池 = \(system) 系统"
        }
        guard abs(snapshot.conservationError) > 2 else { return equation }
        return equation + String(format: "  偏差 %+.1f W", snapshot.conservationError)
    }

    private func refreshModeControls() {
        let helperInstalled = HelperClient.isInstalled
        modeSwitch.isEnabled = helperInstalled
        modeSwitch.state = EnergyModeController.current == .low ? .on : .off
        hintLabel.stringValue = helperInstalled ? "右键菜单栏图标可切换" : "助手未安装 · 重新运行安装脚本"
        hintLabel.textColor = helperInstalled ? .tertiaryLabelColor : .systemOrange
    }

    @objc private func modeChanged(_ sender: NSSwitch) {
        guard HelperClient.isInstalled, let modeToggleHandler else {
            refreshModeControls()
            return
        }
        let succeeded = modeToggleHandler()
        if succeeded {
            hintLabel.stringValue = sender.state == .on ? "已切换到省电模式" : "已切换到自动模式"
            hintLabel.textColor = .secondaryLabelColor
        } else {
            hintLabel.stringValue = "切换失败"
            hintLabel.textColor = .systemRed
            refreshModeControls()
        }
    }

    private func loadModuleVisibility() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: Dictionary(uniqueKeysWithValues: PopoverModule.allCases.map { ($0.defaultsKey, true) }))
        for module in PopoverModule.allCases {
            moduleVisibility[module] = defaults.bool(forKey: module.defaultsKey)
        }
    }

    private func applyModuleVisibility() {
        powerFlowView.isHidden = !(moduleVisibility[.flow] ?? true)
        ringGaugeView.isHidden = !(moduleVisibility[.ring] ?? true)
        laneView.isHidden = !(moduleVisibility[.lanes] ?? true)
        historyView.isHidden = !(moduleVisibility[.history] ?? true)
        if animationsEnabled {
            setAnimationsEnabled(true)
        }
        heightDidChange?(preferredHeight)
    }

    @objc private func showModuleMenu(_ sender: NSButton) {
        let menu = NSMenu(title: "显示模块")
        for module in PopoverModule.allCases {
            let item = NSMenuItem(title: module.title, action: #selector(toggleModule(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = module.rawValue
            item.state = (moduleVisibility[module] ?? true) ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY + 4), in: sender)
    }

    @objc private func toggleModule(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let module = PopoverModule(rawValue: raw) else { return }
        let visible = !(moduleVisibility[module] ?? true)
        moduleVisibility[module] = visible
        UserDefaults.standard.set(visible, forKey: module.defaultsKey)
        applyModuleVisibility()
    }
}
