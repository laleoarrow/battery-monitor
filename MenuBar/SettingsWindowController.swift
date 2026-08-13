import AppKit

protocol SettingsSectionController: AnyObject {
    var identifier: String { get }
    var title: String { get }
    var symbolName: String { get }
    var view: NSView { get }
    func refresh()
}

struct SettingsWindowDependencies {
    let loginItemState: () -> LoginItemState
    let refreshLoginItem: (_ completion: @escaping (LoginItemState) -> Void) -> Void
    let setLoginItemEnabled: (
        _ enabled: Bool,
        _ completion: @escaping (Result<LoginItemState, Error>) -> Void
    ) -> Void
    let systemBatteryIconHidden: () -> Bool?
    let helperAvailable: () -> Bool
    let refreshSystemBatteryIcon: (_ completion: @escaping (Bool?) -> Void) -> Void
    let setSystemBatteryIconHidden: (
        _ hidden: Bool,
        _ completion: @escaping (Bool) -> Void
    ) -> Void
    let systemBatteryIconDidChange: Notification.Name
    let announceAccessibility: (_ message: String) -> Void

    static let live = SettingsWindowDependencies(
        loginItemState: { LoginItemController.state },
        refreshLoginItem: { completion in
            LoginItemController.refresh(completion: completion)
        },
        setLoginItemEnabled: { enabled, completion in
            LoginItemController.setEnabled(enabled, completion: completion)
        },
        systemBatteryIconHidden: { SystemBatteryIconController.cachedHidden },
        helperAvailable: { HelperClient.isInstalled },
        refreshSystemBatteryIcon: { completion in
            SystemBatteryIconController.refreshHidden(completion)
        },
        setSystemBatteryIconHidden: { hidden, completion in
            SystemBatteryIconController.setHidden(hidden, completion: completion)
        },
        systemBatteryIconDidChange: SystemBatteryIconController.didChange,
        announceAccessibility: { message in
            NSAccessibility.post(
                element: NSApp as Any,
                notification: .announcementRequested,
                userInfo: [
                    .announcement: message,
                    .priority: NSAccessibilityPriorityLevel.high.rawValue,
                ]
            )
        }
    )
}

private final class SettingsSidebarRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        NSColor.systemGreen.withAlphaComponent(0.16).setFill()
        NSBezierPath(
            roundedRect: bounds.insetBy(dx: 0, dy: 2),
            xRadius: 8,
            yRadius: 8
        ).fill()
    }
}

private final class DynamicSeparatorView: NSView {
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.separatorColor.cgColor
    }
}

private final class StaticModulePreviewView: NSView {
    private let module: Settings.Module

    init(module: Settings.Module) {
        self.module = module
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier(
            "settings.modules.preview.\(module.rawValue)"
        )
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let drawingRect = bounds.insetBy(dx: 12, dy: 10)
        switch module {
        case .flow:
            drawFlow(in: drawingRect)
        case .ring:
            drawRing(in: drawingRect)
        case .lanes:
            drawLanes(in: drawingRect)
        case .history:
            drawHistory(in: drawingRect)
        }
    }

    private func drawFlow(in rect: NSRect) {
        let left = NSRect(x: rect.minX, y: rect.midY - 9, width: 24, height: 18)
        let right = NSRect(x: rect.maxX - 20, y: rect.minY + 4, width: 20, height: 20)
        NSColor.tertiaryLabelColor.setStroke()
        let leftBox = NSBezierPath(roundedRect: left, xRadius: 3, yRadius: 3)
        leftBox.lineWidth = 2
        leftBox.stroke()
        let rightCircle = NSBezierPath(ovalIn: right)
        rightCircle.lineWidth = 2
        rightCircle.stroke()

        let path = NSBezierPath()
        path.move(to: NSPoint(x: left.maxX, y: left.midY))
        path.curve(
            to: NSPoint(x: right.minX, y: right.midY),
            controlPoint1: NSPoint(x: rect.midX, y: left.midY),
            controlPoint2: NSPoint(x: rect.midX - 2, y: right.midY)
        )
        NSColor.systemGreen.setStroke()
        path.lineWidth = 3
        path.lineCapStyle = .round
        path.stroke()
    }

    private func drawRing(in rect: NSRect) {
        let side = min(rect.width, rect.height)
        let ringRect = NSRect(
            x: rect.midX - side / 2,
            y: rect.midY - side / 2,
            width: side,
            height: side
        ).insetBy(dx: 4, dy: 4)
        NSColor.tertiaryLabelColor.withAlphaComponent(0.45).setStroke()
        let base = NSBezierPath(ovalIn: ringRect)
        base.lineWidth = 6
        base.stroke()

        let arc = NSBezierPath()
        arc.appendArc(
            withCenter: NSPoint(x: ringRect.midX, y: ringRect.midY),
            radius: ringRect.width / 2,
            startAngle: -135,
            endAngle: 75
        )
        NSColor.systemGreen.setStroke()
        arc.lineWidth = 6
        arc.lineCapStyle = .round
        arc.stroke()

        let bolt = NSBezierPath()
        bolt.move(to: NSPoint(x: rect.midX + 2, y: rect.midY + 15))
        bolt.line(to: NSPoint(x: rect.midX - 8, y: rect.midY - 1))
        bolt.line(to: NSPoint(x: rect.midX, y: rect.midY))
        bolt.line(to: NSPoint(x: rect.midX - 2, y: rect.midY - 15))
        bolt.line(to: NSPoint(x: rect.midX + 10, y: rect.midY + 2))
        bolt.line(to: NSPoint(x: rect.midX + 2, y: rect.midY + 1))
        bolt.close()
        NSColor.secondaryLabelColor.setFill()
        bolt.fill()
    }

    private func drawLanes(in rect: NSRect) {
        let startX = rect.minX + 16
        let endX = rect.maxX - 5
        for index in 0..<3 {
            let y = rect.maxY - 9 - CGFloat(index * 17)
            let lane = NSBezierPath()
            lane.move(to: NSPoint(x: startX, y: y))
            lane.line(to: NSPoint(x: endX, y: y))
            NSColor.tertiaryLabelColor.setStroke()
            lane.lineWidth = 2
            lane.stroke()
            NSColor.systemGreen.setFill()
            NSBezierPath(
                ovalIn: NSRect(x: rect.midX + CGFloat(index * 4) - 4, y: y - 4, width: 8, height: 8)
            ).fill()
        }
    }

    private func drawHistory(in rect: NSRect) {
        NSColor.tertiaryLabelColor.withAlphaComponent(0.45).setStroke()
        for fraction in [0.25, 0.5, 0.75] as [CGFloat] {
            let guide = NSBezierPath()
            guide.move(to: NSPoint(x: rect.minX + rect.width * fraction, y: rect.minY))
            guide.line(to: NSPoint(x: rect.minX + rect.width * fraction, y: rect.maxY))
            var dash: [CGFloat] = [3, 4]
            guide.setLineDash(&dash, count: dash.count, phase: 0)
            guide.stroke()
        }

        let points: [NSPoint] = [
            NSPoint(x: rect.minX, y: rect.minY + 8),
            NSPoint(x: rect.minX + rect.width * 0.2, y: rect.minY + rect.height * 0.65),
            NSPoint(x: rect.minX + rect.width * 0.4, y: rect.minY + rect.height * 0.35),
            NSPoint(x: rect.minX + rect.width * 0.62, y: rect.minY + rect.height * 0.72),
            NSPoint(x: rect.maxX, y: rect.minY + rect.height * 0.58),
        ]
        let line = NSBezierPath()
        line.move(to: points[0])
        for point in points.dropFirst() { line.line(to: point) }
        NSColor.systemGreen.setStroke()
        line.lineWidth = 3
        line.lineJoinStyle = .round
        line.lineCapStyle = .round
        line.stroke()
        NSColor.systemGreen.setFill()
        NSBezierPath(
            ovalIn: NSRect(x: points.last!.x - 4, y: points.last!.y - 4, width: 8, height: 8)
        ).fill()
    }
}

private final class GeneralSettingsSectionController: NSObject, SettingsSectionController {
    let identifier = "general"
    let title = "General"
    let symbolName = "gearshape"
    let view = NSView()

    private let dependencies: SettingsWindowDependencies
    private let percentageButton = NSButton(
        checkboxWithTitle: "Show Battery Percentage in Menu Bar",
        target: nil,
        action: nil
    )
    private let loginButton = NSButton(
        checkboxWithTitle: "Launch at Login",
        target: nil,
        action: nil
    )
    private let batteryButton = NSButton(
        checkboxWithTitle: "Hide System Battery Icon",
        target: nil,
        action: nil
    )
    private let loginDetail = NSTextField(labelWithString: "")
    private let loginError = NSTextField(labelWithString: "")
    private let batteryDetail = NSTextField(labelWithString: "")
    private let batteryError = NSTextField(labelWithString: "")

    private let loginAccessibilityPurpose =
        "Open Wattson automatically after you sign in to this Mac."
    private let batteryAccessibilityPurpose =
        "Hide Apple’s battery icon while keeping Wattson in the menu bar."

    private var settingsObserver: NSObjectProtocol?
    private var batteryObserver: NSObjectProtocol?
    private var loginGeneration = 0
    private var batteryGeneration = 0
    private var loginMutationInFlight = false
    private var batteryMutationInFlight = false
    private var lastAuthoritativeLoginState: LoginItemState?
    private var lastAuthoritativeBatteryState: Bool?

    init(dependencies: SettingsWindowDependencies) {
        self.dependencies = dependencies
        super.init()

        configureControls()
        buildView()
        installObservers()
    }

    deinit {
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
        if let batteryObserver {
            NotificationCenter.default.removeObserver(batteryObserver)
        }
    }

    func refresh() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.refresh() }
            return
        }

        refreshPercentage()
        refreshLoginItem()
        refreshBatteryIcon()
    }

    private func configureControls() {
        configureSwitch(percentageButton)
        percentageButton.target = self
        percentageButton.action = #selector(togglePercentage(_:))
        percentageButton.setAccessibilityLabel("Show Battery Percentage in Menu Bar")
        percentageButton.setAccessibilityHelp(
            "Show the current battery percentage next to the Wattson menu bar icon."
        )

        configureSwitch(loginButton)
        loginButton.target = self
        loginButton.action = #selector(toggleLoginItem(_:))
        loginButton.allowsMixedState = true
        loginButton.setAccessibilityLabel("Launch at Login")
        loginButton.setAccessibilityHelp(
            loginAccessibilityPurpose
        )

        configureSwitch(batteryButton)
        batteryButton.target = self
        batteryButton.action = #selector(toggleBatteryIcon(_:))
        batteryButton.allowsMixedState = true
        batteryButton.setAccessibilityLabel("Hide System Battery Icon")
        batteryButton.setAccessibilityHelp(
            batteryAccessibilityPurpose
        )

        configureDetailLabel(
            loginDetail,
            identifier: "settings.general.login.detail"
        )
        configureErrorLabel(
            loginError,
            identifier: "settings.general.login.error"
        )
        configureDetailLabel(
            batteryDetail,
            identifier: "settings.general.battery.detail"
        )
        configureErrorLabel(
            batteryError,
            identifier: "settings.general.battery.error"
        )

    }

    private func configureSwitch(_ button: NSButton) {
        let accessibilityLabel = button.title
        button.setButtonType(.switch)
        button.controlSize = .small
        button.cell?.lineBreakMode = .byClipping
        button.setAccessibilityLabel(accessibilityLabel)
        button.title = ""
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 24),
            button.heightAnchor.constraint(equalToConstant: 22),
        ])
    }

    private func configureDetailLabel(
        _ label: NSTextField,
        identifier: String
    ) {
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.setAccessibilityIdentifier(identifier)
    }

    private func configureErrorLabel(
        _ label: NSTextField,
        identifier: String
    ) {
        configureDetailLabel(label, identifier: identifier)
        label.textColor = .systemRed
        label.isHidden = true
    }

    private func buildView() {
        view.identifier = NSUserInterfaceItemIdentifier("settings.section.general")
        let percentageDetail = NSTextField(
            labelWithString: "Show charge next to the menu bar icon"
        )
        configureDetailLabel(
            percentageDetail,
            identifier: "settings.general.percentage.detail"
        )

        let rows = NSStackView(views: [
            row(
                identifier: "percentage",
                symbolName: "percent",
                button: percentageButton,
                detail: percentageDetail,
                error: nil,
                hasSeparator: true
            ),
            row(
                identifier: "login",
                symbolName: "person.fill",
                button: loginButton,
                detail: loginDetail,
                error: loginError,
                hasSeparator: true
            ),
            row(
                identifier: "battery",
                symbolName: "battery.100",
                button: batteryButton,
                detail: batteryDetail,
                error: batteryError,
                hasSeparator: false
            ),
        ])
        rows.orientation = .vertical
        rows.alignment = .width
        rows.distribution = .fillEqually
        rows.spacing = 0
        rows.translatesAutoresizingMaskIntoConstraints = false

        let list = NSBox()
        list.boxType = .custom
        list.identifier = NSUserInterfaceItemIdentifier("settings.general.list")
        list.titlePosition = .noTitle
        list.cornerRadius = 12
        list.borderWidth = 1
        list.borderColor = .separatorColor
        list.fillColor = .controlBackgroundColor
        list.translatesAutoresizingMaskIntoConstraints = false
        list.addSubview(rows)

        let heading = NSTextField(labelWithString: title)
        heading.font = .systemFont(ofSize: 28, weight: .semibold)
        heading.setAccessibilityLabel(title)
        heading.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(heading)
        view.addSubview(list)

        NSLayoutConstraint.activate([
            heading.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            heading.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            heading.topAnchor.constraint(equalTo: view.topAnchor),

            list.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            list.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 28),
            list.heightAnchor.constraint(equalToConstant: 228),
            list.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor),

            rows.leadingAnchor.constraint(equalTo: list.leadingAnchor),
            rows.trailingAnchor.constraint(equalTo: list.trailingAnchor),
            rows.topAnchor.constraint(equalTo: list.topAnchor),
            rows.bottomAnchor.constraint(equalTo: list.bottomAnchor),
        ])
    }

    private func row(
        identifier: String,
        symbolName: String,
        button: NSButton,
        detail: NSTextField,
        error: NSTextField?,
        hasSeparator: Bool
    ) -> NSView {
        let row = NSView()
        row.identifier = NSUserInterfaceItemIdentifier("settings.general.row.\(identifier)")

        let iconTile = NSBox()
        iconTile.boxType = .custom
        iconTile.titlePosition = .noTitle
        iconTile.cornerRadius = 7
        iconTile.borderWidth = 1
        iconTile.borderColor = .separatorColor
        iconTile.fillColor = .windowBackgroundColor
        iconTile.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView()
        icon.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: nil
        )
        icon.contentTintColor = .secondaryLabelColor
        icon.imageScaling = .scaleProportionallyDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        iconTile.addSubview(icon)

        let primary = NSTextField(
            labelWithString: button.accessibilityLabel() ?? ""
        )
        primary.font = .systemFont(ofSize: 14, weight: .medium)
        primary.lineBreakMode = .byTruncatingTail
        primary.translatesAutoresizingMaskIntoConstraints = false

        var textViews: [NSView] = [primary, detail]
        if let error { textViews.append(error) }
        let text = NSStackView(views: textViews)
        text.orientation = .vertical
        text.alignment = .leading
        text.distribution = .fill
        text.spacing = 2
        text.translatesAutoresizingMaskIntoConstraints = false

        row.addSubview(iconTile)
        row.addSubview(text)
        row.addSubview(button)

        NSLayoutConstraint.activate([
            iconTile.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            iconTile.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            iconTile.widthAnchor.constraint(equalToConstant: 38),
            iconTile.heightAnchor.constraint(equalToConstant: 38),
            icon.centerXAnchor.constraint(equalTo: iconTile.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconTile.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 20),
            icon.heightAnchor.constraint(equalToConstant: 20),

            text.leadingAnchor.constraint(equalTo: iconTile.trailingAnchor, constant: 14),
            text.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            text.trailingAnchor.constraint(lessThanOrEqualTo: button.leadingAnchor, constant: -12),

            button.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
            button.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])

        if hasSeparator {
            let separator = NSBox()
            separator.boxType = .separator
            separator.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(separator)
            NSLayoutConstraint.activate([
                separator.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
                separator.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
                separator.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            ])
        }
        return row
    }

    private func installObservers() {
        settingsObserver = NotificationCenter.default.addObserver(
            forName: Settings.didChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            guard let change = notification.userInfo?[Settings.changeUserInfoKey]
                    as? Settings.Change else {
                self.refreshPercentage()
                return
            }
            if change == .menuBarPercentage { self.refreshPercentage() }
        }

        batteryObserver = NotificationCenter.default.addObserver(
            forName: dependencies.systemBatteryIconDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, !self.batteryMutationInFlight else { return }
            let hidden = self.dependencies.systemBatteryIconHidden()
            self.lastAuthoritativeBatteryState = hidden
            self.clearError(self.batteryError)
            self.renderBatteryIcon(hidden)
        }
    }

    private func refreshPercentage() {
        percentageButton.state = Settings.showsMenuBarPercentage ? .on : .off
    }

    private func refreshLoginItem() {
        guard !loginMutationInFlight else { return }
        rememberAuthoritativeLoginState(dependencies.loginItemState())
        loginGeneration += 1
        let generation = loginGeneration
        clearError(loginError)
        renderLoginItem(.checking)
        dependencies.refreshLoginItem { [weak self] state in
            self?.onMain { [weak self] in
                guard let self,
                      generation == self.loginGeneration,
                      !self.loginMutationInFlight else { return }
                self.rememberAuthoritativeLoginState(state)
                self.renderLoginItem(state)
            }
        }
    }

    private func refreshBatteryIcon() {
        guard !batteryMutationInFlight else { return }
        lastAuthoritativeBatteryState = dependencies.systemBatteryIconHidden()
        batteryGeneration += 1
        let generation = batteryGeneration
        clearError(batteryError)
        renderBatteryIconChecking()
        dependencies.refreshSystemBatteryIcon { [weak self] hidden in
            self?.onMain { [weak self] in
                guard let self,
                      generation == self.batteryGeneration,
                      !self.batteryMutationInFlight else { return }
                self.lastAuthoritativeBatteryState = hidden
                self.renderBatteryIcon(hidden)
            }
        }
    }

    @objc private func togglePercentage(_ sender: NSButton) {
        Settings.showsMenuBarPercentage = sender.state == .on
    }

    @objc private func toggleLoginItem(_ sender: NSButton) {
        guard !loginMutationInFlight else { return }
        let restoration = lastAuthoritativeLoginState
            ?? authoritativeLoginState(dependencies.loginItemState())
        guard let restoration else {
            renderLoginItem(.readFailed)
            return
        }
        // AppKit cycles a three-state checkbox through `.mixed`; unknown is a
        // display state here, not a third user choice. Invert the last
        // authoritative value so mouse, keyboard, and VoiceOver agree.
        let requested = restoration != .enabled

        loginMutationInFlight = true
        loginGeneration += 1
        clearError(loginError)
        loginButton.isEnabled = false
        loginDetail.stringValue = "Updating…"
        updateAccessibilityHelp(
            for: loginButton,
            purpose: loginAccessibilityPurpose,
            status: loginDetail.stringValue
        )

        dependencies.setLoginItemEnabled(requested) { [weak self] result in
            self?.onMain { [weak self] in
                guard let self else { return }
                self.loginMutationInFlight = false
                switch result {
                case let .success(state):
                    self.rememberAuthoritativeLoginState(state)
                    self.renderLoginItem(state)
                case let .failure(error):
                    let current = self.dependencies.loginItemState()
                    if current == .checking {
                        self.renderLoginItem(restoration)
                    } else {
                        self.rememberAuthoritativeLoginState(current)
                        self.renderLoginItem(current)
                    }
                    self.showError(
                        error.localizedDescription,
                        in: self.loginError,
                        for: self.loginButton,
                        purpose: self.loginAccessibilityPurpose
                    )
                }
            }
        }
    }

    @objc private func toggleBatteryIcon(_ sender: NSButton) {
        guard !batteryMutationInFlight else { return }
        guard let restoration = lastAuthoritativeBatteryState else {
            renderBatteryIcon(nil)
            return
        }
        let requested = !restoration

        batteryMutationInFlight = true
        batteryGeneration += 1
        clearError(batteryError)
        batteryButton.isEnabled = false
        batteryDetail.stringValue = "Updating…"
        updateAccessibilityHelp(
            for: batteryButton,
            purpose: batteryAccessibilityPurpose,
            status: batteryDetail.stringValue
        )

        dependencies.setSystemBatteryIconHidden(requested) { [weak self] succeeded in
            self?.onMain { [weak self] in
                guard let self else { return }
                self.batteryMutationInFlight = false
                if succeeded {
                    let landed = self.dependencies.systemBatteryIconHidden()
                    self.lastAuthoritativeBatteryState = landed
                    self.renderBatteryIcon(landed)
                } else {
                    self.renderBatteryIcon(restoration)
                    self.showError(
                        "macOS couldn’t update the system battery icon. Try again later.",
                        in: self.batteryError,
                        for: self.batteryButton,
                        purpose: self.batteryAccessibilityPurpose
                    )
                }
            }
        }
    }

    private func renderLoginItem(_ state: LoginItemState) {
        switch state {
        case .enabled:
            loginButton.state = .on
            loginButton.isEnabled = true
            loginDetail.stringValue = "Wattson opens automatically after you sign in."
        case .notRegistered:
            loginButton.state = .off
            loginButton.isEnabled = true
            loginDetail.stringValue = "Open Wattson automatically after you sign in."
        case .checking:
            loginButton.state = .mixed
            loginButton.isEnabled = false
            loginDetail.stringValue = "Checking…"
        case .unavailable:
            loginButton.state = .mixed
            loginButton.isEnabled = false
            loginDetail.stringValue = "Full installer required"
        case .readFailed:
            loginButton.state = .mixed
            loginButton.isEnabled = false
            loginDetail.stringValue = "Status unavailable"
        }
        updateAccessibilityHelp(
            for: loginButton,
            purpose: loginAccessibilityPurpose,
            status: loginDetail.stringValue
        )
    }

    private func renderBatteryIconChecking() {
        batteryButton.state = .mixed
        batteryButton.isEnabled = false
        batteryDetail.stringValue = "Checking…"
        updateAccessibilityHelp(
            for: batteryButton,
            purpose: batteryAccessibilityPurpose,
            status: batteryDetail.stringValue
        )
    }

    private func renderBatteryIcon(_ hidden: Bool?) {
        guard let hidden else {
            batteryButton.state = .mixed
            batteryButton.isEnabled = false
            batteryDetail.stringValue = dependencies.helperAvailable()
                ? "Status unavailable"
                : "Full installer required"
            updateAccessibilityHelp(
                for: batteryButton,
                purpose: batteryAccessibilityPurpose,
                status: batteryDetail.stringValue
            )
            return
        }
        batteryButton.state = hidden ? .on : .off
        batteryButton.isEnabled = true
        batteryDetail.stringValue = hidden
            ? "Apple’s battery icon is hidden."
            : "Keep Apple’s battery icon visible beside Wattson."
        updateAccessibilityHelp(
            for: batteryButton,
            purpose: batteryAccessibilityPurpose,
            status: batteryDetail.stringValue
        )
    }

    private func rememberAuthoritativeLoginState(_ state: LoginItemState) {
        if let state = authoritativeLoginState(state) {
            lastAuthoritativeLoginState = state
        }
    }

    private func authoritativeLoginState(_ state: LoginItemState) -> LoginItemState? {
        switch state {
        case .enabled, .notRegistered: return state
        case .checking, .unavailable, .readFailed: return nil
        }
    }

    private func clearError(_ label: NSTextField) {
        label.stringValue = ""
        label.isHidden = true
    }

    private func showError(
        _ message: String,
        in label: NSTextField,
        for button: NSButton,
        purpose: String
    ) {
        label.stringValue = message
        label.isHidden = false
        updateAccessibilityHelp(for: button, purpose: purpose, status: message)
        dependencies.announceAccessibility(message)
    }

    private func updateAccessibilityHelp(
        for button: NSButton,
        purpose: String,
        status: String
    ) {
        button.setAccessibilityHelp("\(purpose) \(status)")
    }

    private func onMain(_ operation: @escaping () -> Void) {
        if Thread.isMainThread {
            operation()
        } else {
            DispatchQueue.main.async(execute: operation)
        }
    }
}

private final class ModuleSettingsSectionController: NSObject, SettingsSectionController {
    let identifier = "modules"
    let title = "Modules"
    let symbolName = "square.grid.2x2"
    let view = NSView()

    private var buttons: [Settings.Module: NSButton] = [:]
    private var settingsObserver: NSObjectProtocol?

    override init() {
        super.init()
        buildView()
        installObserver()
    }

    deinit {
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
    }

    func refresh() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.refresh() }
            return
        }
        for module in Settings.Module.allCases { refresh(module) }
    }

    private func buildView() {
        view.identifier = NSUserInterfaceItemIdentifier("settings.section.modules")

        let heading = NSTextField(labelWithString: title)
        heading.identifier = NSUserInterfaceItemIdentifier("settings.modules.heading")
        heading.font = .systemFont(ofSize: 28, weight: .semibold)
        heading.setAccessibilityLabel(title)
        heading.translatesAutoresizingMaskIntoConstraints = false

        let subtitle = NSTextField(
            labelWithString: "Choose what appears in the power popover."
        )
        subtitle.identifier = NSUserInterfaceItemIdentifier("settings.modules.subtitle")
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = .secondaryLabelColor
        subtitle.translatesAutoresizingMaskIntoConstraints = false

        let cards = Settings.Module.allCases.enumerated().map { index, module in
            makeCard(for: module, index: index)
        }
        precondition(cards.count == 4, "The approved Modules page is a 2×2 grid.")
        let grid = NSGridView(views: [
            [cards[0], cards[1]],
            [cards[2], cards[3]],
        ])
        grid.identifier = NSUserInterfaceItemIdentifier("settings.modules.grid")
        grid.rowSpacing = 12
        grid.columnSpacing = 12
        grid.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(heading)
        view.addSubview(subtitle)
        view.addSubview(grid)

        NSLayoutConstraint.activate([
            heading.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            heading.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            heading.topAnchor.constraint(equalTo: view.topAnchor),

            subtitle.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            subtitle.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            subtitle.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 5),

            grid.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            grid.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            grid.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 24),
            grid.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor),
            grid.heightAnchor.constraint(equalToConstant: 344),
        ])
    }

    private func makeCard(for module: Settings.Module, index: Int) -> NSView {
        let card = NSBox()
        card.identifier = NSUserInterfaceItemIdentifier(
            "settings.modules.card.\(module.rawValue)"
        )
        card.boxType = .custom
        card.titlePosition = .noTitle
        card.cornerRadius = 12
        card.borderWidth = 1
        card.borderColor = .separatorColor
        card.fillColor = .controlBackgroundColor

        let preview = StaticModulePreviewView(module: module)
        preview.translatesAutoresizingMaskIntoConstraints = false

        let primary = NSTextField(labelWithString: module.title)
        primary.font = .systemFont(ofSize: 14, weight: .medium)
        primary.lineBreakMode = .byTruncatingTail
        primary.translatesAutoresizingMaskIntoConstraints = false

        let detail = NSTextField(labelWithString: description(for: module))
        detail.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingTail
        detail.maximumNumberOfLines = 1
        detail.translatesAutoresizingMaskIntoConstraints = false

        let button = NSButton(
            checkboxWithTitle: module.title,
            target: self,
            action: #selector(toggleModule(_:))
        )
        let accessibilityLabel = button.title
        button.setButtonType(.switch)
        button.controlSize = .small
        button.cell?.lineBreakMode = .byClipping
        button.tag = index
        button.setAccessibilityLabel(accessibilityLabel)
        button.setAccessibilityHelp("Show or hide the \(module.title) module in Wattson.")
        button.title = ""
        button.translatesAutoresizingMaskIntoConstraints = false
        buttons[module] = button

        card.addSubview(preview)
        card.addSubview(primary)
        card.addSubview(detail)
        card.addSubview(button)

        NSLayoutConstraint.activate([
            preview.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            preview.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            preview.widthAnchor.constraint(equalToConstant: 64),
            preview.heightAnchor.constraint(equalToConstant: 64),

            primary.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            primary.trailingAnchor.constraint(lessThanOrEqualTo: button.leadingAnchor, constant: -8),
            primary.bottomAnchor.constraint(equalTo: detail.topAnchor, constant: -5),

            detail.leadingAnchor.constraint(equalTo: primary.leadingAnchor),
            detail.trailingAnchor.constraint(lessThanOrEqualTo: button.leadingAnchor, constant: -8),
            detail.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),

            button.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            button.centerYAnchor.constraint(equalTo: primary.centerYAnchor),
            button.widthAnchor.constraint(equalToConstant: 24),
            button.heightAnchor.constraint(equalToConstant: 22),
            card.widthAnchor.constraint(equalToConstant: 233.5),
            card.heightAnchor.constraint(equalToConstant: 166),
        ])
        return card
    }

    private func description(for module: Settings.Module) -> String {
        switch module {
        case .flow: return "Visualize power movement"
        case .ring: return "Circular battery indicator"
        case .lanes: return "Break down power usage"
        case .history: return "Track battery over time"
        }
    }

    private func installObserver() {
        settingsObserver = NotificationCenter.default.addObserver(
            forName: Settings.didChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            guard let change = notification.userInfo?[Settings.changeUserInfoKey]
                    as? Settings.Change else {
                self.refresh()
                return
            }
            if case let .module(module) = change { self.refresh(module) }
        }
    }

    private func refresh(_ module: Settings.Module) {
        buttons[module]?.state = Settings.isModuleVisible(module) ? .on : .off
    }

    @objc private func toggleModule(_ sender: NSButton) {
        guard Settings.Module.allCases.indices.contains(sender.tag) else { return }
        let module = Settings.Module.allCases[sender.tag]
        Settings.setModule(module, visible: sender.state == .on)
    }
}

final class SettingsWindowController: NSWindowController, NSTableViewDataSource,
    NSTableViewDelegate
{
    private static let frameAutosaveName = "WattsonSettingsWindow"
    private static let contentSize = NSSize(width: 720, height: 520)
    private static let sidebarWidth: CGFloat = 176
    private static let contentInset: CGFloat = 32

    private let sections: [SettingsSectionController]
    private let sidebar = NSTableView()
    private let contentHost = NSView()
    private var selectedSectionIndex = 0

    static func defaultSections(
        dependencies: SettingsWindowDependencies = .live
    ) -> [SettingsSectionController] {
        [
            GeneralSettingsSectionController(dependencies: dependencies),
            ModuleSettingsSectionController(),
        ]
    }

    init(
        sections: [SettingsSectionController]? = nil,
        dependencies: SettingsWindowDependencies = .live,
        frameAutosaveName: String? = SettingsWindowController.frameAutosaveName
    ) {
        let resolvedSections = sections ?? Self.defaultSections(dependencies: dependencies)
        precondition(
            Set(resolvedSections.map(\.identifier)).count == resolvedSections.count,
            "Settings section identifiers must be unique."
        )
        precondition(!resolvedSections.isEmpty, "Settings needs at least one section.")
        self.sections = resolvedSections

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Wattson Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.tabbingMode = .disallowed
        window.contentMinSize = Self.contentSize
        window.contentMaxSize = Self.contentSize
        window.autorecalculatesKeyViewLoop = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        let hadSavedFrame = frameAutosaveName.flatMap {
            UserDefaults.standard.string(forKey: "NSWindow Frame \($0)")
        } != nil
        super.init(window: window)

        configureContent()
        if let frameAutosaveName {
            // NSWindowController initialization clears a name assigned before
            // it takes ownership, so install autosave after `super.init`.
            window.setFrameAutosaveName(frameAutosaveName)
            if !hadSavedFrame { window.center() }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    func show(activateApp: Bool = true) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.show(activateApp: activateApp)
            }
            return
        }

        refreshSections()
        guard let window else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.initialFirstResponder = sidebar
        if activateApp {
            window.makeKeyAndOrderFront(nil)
            if #available(macOS 14, *) {
                NSRunningApplication.current.activate(options: [.activateAllWindows])
            } else {
                NSRunningApplication.current.activate(
                    options: [.activateIgnoringOtherApps, .activateAllWindows]
                )
            }
            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.async { [weak window] in
                guard let window, window.isVisible else { return }
                window.makeKeyAndOrderFront(nil)
            }
        } else {
            window.orderFront(nil)
        }
    }

    private func configureContent() {
        guard let window else { return }
        let root = NSView(frame: NSRect(origin: .zero, size: Self.contentSize))

        let sidebarContainer = NSVisualEffectView()
        sidebarContainer.identifier = NSUserInterfaceItemIdentifier("settings.sidebar")
        sidebarContainer.material = .sidebar
        sidebarContainer.blendingMode = .behindWindow
        sidebarContainer.state = .active
        sidebarContainer.translatesAutoresizingMaskIntoConstraints = false

        let identity = makeIdentityView()
        let trafficSafeArea = NSView()
        trafficSafeArea.identifier = NSUserInterfaceItemIdentifier(
            "settings.sidebar.traffic-safe-area"
        )
        trafficSafeArea.translatesAutoresizingMaskIntoConstraints = false
        let navigation = makeNavigationView()
        let divider = DynamicSeparatorView()
        divider.identifier = NSUserInterfaceItemIdentifier("settings.sidebar.divider")
        divider.wantsLayer = true
        divider.translatesAutoresizingMaskIntoConstraints = false

        contentHost.identifier = NSUserInterfaceItemIdentifier("settings.content.host")
        contentHost.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(sidebarContainer)
        root.addSubview(divider)
        root.addSubview(contentHost)
        sidebarContainer.addSubview(identity)
        sidebarContainer.addSubview(trafficSafeArea)
        sidebarContainer.addSubview(navigation)

        NSLayoutConstraint.activate([
            sidebarContainer.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            sidebarContainer.topAnchor.constraint(equalTo: root.topAnchor),
            sidebarContainer.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            sidebarContainer.widthAnchor.constraint(equalToConstant: Self.sidebarWidth),

            trafficSafeArea.leadingAnchor.constraint(equalTo: sidebarContainer.leadingAnchor),
            trafficSafeArea.trailingAnchor.constraint(equalTo: sidebarContainer.trailingAnchor),
            trafficSafeArea.topAnchor.constraint(equalTo: sidebarContainer.topAnchor),
            trafficSafeArea.heightAnchor.constraint(equalToConstant: 38),

            identity.leadingAnchor.constraint(equalTo: sidebarContainer.leadingAnchor),
            identity.trailingAnchor.constraint(equalTo: sidebarContainer.trailingAnchor),
            identity.topAnchor.constraint(equalTo: trafficSafeArea.bottomAnchor),
            identity.heightAnchor.constraint(equalToConstant: 72),

            navigation.leadingAnchor.constraint(equalTo: sidebarContainer.leadingAnchor, constant: 12),
            navigation.trailingAnchor.constraint(equalTo: sidebarContainer.trailingAnchor, constant: -12),
            navigation.topAnchor.constraint(equalTo: identity.bottomAnchor),
            navigation.heightAnchor.constraint(equalToConstant: CGFloat(sections.count) * 48 - 4),

            divider.leadingAnchor.constraint(equalTo: sidebarContainer.trailingAnchor),
            divider.topAnchor.constraint(equalTo: root.topAnchor),
            divider.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        divider.widthAnchor.constraint(equalToConstant: 1),

            contentHost.leadingAnchor.constraint(equalTo: divider.trailingAnchor, constant: Self.contentInset),
            contentHost.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -Self.contentInset),
            contentHost.topAnchor.constraint(equalTo: root.topAnchor, constant: Self.contentInset),
            contentHost.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -Self.contentInset),
        ])

        window.contentView = root
        sidebar.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        tableViewSelectionDidChange(Notification(
            name: NSTableView.selectionDidChangeNotification,
            object: sidebar
        ))
        configureKeyViewLoop()
        root.layoutSubtreeIfNeeded()
    }

    private func makeIdentityView() -> NSView {
        let identity = NSView()
        identity.identifier = NSUserInterfaceItemIdentifier("settings.sidebar.identity")
        identity.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "waveform.path.ecg", accessibilityDescription: nil)
        icon.contentTintColor = .systemGreen
        icon.imageScaling = .scaleProportionallyDown
        icon.translatesAutoresizingMaskIntoConstraints = false

        let name = NSTextField(labelWithString: "Wattson")
        name.font = .systemFont(ofSize: 15, weight: .semibold)
        name.translatesAutoresizingMaskIntoConstraints = false

        identity.addSubview(icon)
        identity.addSubview(name)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: identity.leadingAnchor, constant: 18),
            icon.centerYAnchor.constraint(equalTo: identity.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 28),
            icon.heightAnchor.constraint(equalToConstant: 28),
            name.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            name.centerYAnchor.constraint(equalTo: identity.centerYAnchor),
        ])
        return identity
    }

    private func makeNavigationView() -> NSView {
        let scroll = NSScrollView()
        scroll.identifier = NSUserInterfaceItemIdentifier("settings.sidebar.navigation")
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("settings.sidebar.column"))
        column.resizingMask = .autoresizingMask
        sidebar.addTableColumn(column)
        sidebar.headerView = nil
        sidebar.style = .sourceList
        sidebar.rowHeight = 44
        sidebar.intercellSpacing = NSSize(width: 0, height: 4)
        sidebar.allowsEmptySelection = false
        sidebar.allowsMultipleSelection = false
        sidebar.focusRingType = .default
        sidebar.backgroundColor = .clear
        sidebar.dataSource = self
        sidebar.delegate = self
        scroll.documentView = sidebar
        return scroll
    }

    private func configureKeyViewLoop() {
        sidebar.nextKeyView = firstSwitch(in: sections[selectedSectionIndex].view)
        updateVisibleSwitchKeyLoop()
    }

    private func updateVisibleSwitchKeyLoop() {
        let switches = switchButtons(in: sections[selectedSectionIndex].view)
        sidebar.nextKeyView = switches.first
        for (current, next) in zip(switches, switches.dropFirst()) {
            current.nextKeyView = next
        }
        switches.last?.nextKeyView = sidebar
    }

    private func firstSwitch(in view: NSView) -> NSButton? {
        switchButtons(in: view).first
    }

    private func switchButtons(in view: NSView) -> [NSButton] {
        var buttons: [NSButton] = []
        if let button = view as? NSButton {
            buttons.append(button)
        }
        for subview in view.subviews { buttons.append(contentsOf: switchButtons(in: subview)) }
        return buttons
    }

    private func refreshSections() {
        sections.forEach { $0.refresh() }
    }

    private func showSection(at index: Int) {
        guard sections.indices.contains(index) else { return }
        selectedSectionIndex = index
        let sectionView = sections[index].view
        contentHost.subviews.forEach { $0.removeFromSuperview() }
        sectionView.translatesAutoresizingMaskIntoConstraints = false
        contentHost.addSubview(sectionView)
        NSLayoutConstraint.activate([
            sectionView.leadingAnchor.constraint(equalTo: contentHost.leadingAnchor),
            sectionView.trailingAnchor.constraint(equalTo: contentHost.trailingAnchor),
            sectionView.topAnchor.constraint(equalTo: contentHost.topAnchor),
            sectionView.bottomAnchor.constraint(equalTo: contentHost.bottomAnchor),
        ])
        updateVisibleSwitchKeyLoop()
        contentHost.layoutSubtreeIfNeeded()
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let tableView = notification.object as? NSTableView,
              tableView === sidebar else { return }
        let row = sidebar.selectedRow
        guard sections.indices.contains(row) else {
            sidebar.selectRowIndexes(
                IndexSet(integer: selectedSectionIndex),
                byExtendingSelection: false
            )
            return
        }
        showSection(at: row)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { sections.count }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { 44 }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        SettingsSidebarRowView()
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        guard sections.indices.contains(row) else { return nil }
        let section = sections[row]
        let cell = NSTableCellView()

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: section.symbolName, accessibilityDescription: nil)
        icon.contentTintColor = .labelColor
        icon.imageScaling = .scaleProportionallyDown
        icon.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: section.title)
        title.font = .systemFont(ofSize: 13, weight: .medium)
        title.lineBreakMode = .byTruncatingTail
        title.translatesAutoresizingMaskIntoConstraints = false

        cell.addSubview(icon)
        cell.addSubview(title)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10),
            icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 19),
            icon.heightAnchor.constraint(equalToConstant: 19),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            title.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            title.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        cell.setAccessibilityLabel(section.title)
        cell.setAccessibilityHelp("Show the \(section.title) settings page.")
        return cell
    }

#if DEBUG
    var windowForTest: NSWindow? { window }
    var sectionIdentifiersForTest: [String] { sections.map(\.identifier) }
    var selectedSectionIdentifierForTest: String { sections[selectedSectionIndex].identifier }
    var visibleSectionIdentifierForTest: String? {
        sections.first(where: { $0.view.superview === contentHost })?.identifier
    }
    var contentHostSubviewCountForTest: Int { contentHost.subviews.count }
    var sectionViewIdentitiesForTest: [ObjectIdentifier] {
        sections.map { ObjectIdentifier($0.view) }
    }
    var contentHostFrameForTest: NSRect { contentHost.frame }
    var sidebarStyleForTest: NSTableView.Style { sidebar.style }
    var sidebarAllowsEmptySelectionForTest: Bool { sidebar.allowsEmptySelection }
    var sidebarRowHeightForTest: CGFloat { sidebar.rowHeight }
    var sidebarRowGapForTest: CGFloat { sidebar.intercellSpacing.height }
    var sidebarForTest: NSTableView { sidebar }
    var sidebarNextKeyViewForTest: NSView? { sidebar.nextKeyView }
    var lastVisibleSwitchNextKeyViewForTest: NSView? {
        switchButtons(in: sections[selectedSectionIndex].view).last?.nextKeyView
    }

    func selectSectionForTest(identifier: String) {
        guard let index = sections.firstIndex(where: { $0.identifier == identifier }) else { return }
        sidebar.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
    }

    func selectSidebarRowForTest(_ row: Int) {
        sidebar.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    }

    func refreshSectionsForTest() { refreshSections() }
#endif
}
