import AppKit

final class ProcessWhitelistWindowController: NSWindowController, NSTableViewDataSource,
    NSTableViewDelegate, NSTextFieldDelegate
{
    private let table = NSTableView()
    private let mode = NSPopUpButton()
    private let pattern = NSTextField()
    private let addButton = NSButton(title: "Add", target: nil, action: nil)
    private let removeButton = NSButton(title: "Remove Selected", target: nil, action: nil)
    private let message = NSTextField(labelWithString: "")
    private let help = NSTextField(wrappingLabelWithString: "")
    private var rules: [ProcessWhitelistRule] = []
    private var settingsObserver: NSObjectProtocol?

    init() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 400),
                            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "Process Whitelist"
        panel.isReleasedWhenClosed = false
        panel.isRestorable = false
        super.init(window: panel)
        buildView()
        refreshRules()
        refreshEditor()
        settingsObserver = NotificationCenter.default.addObserver(
            forName: Settings.didChange, object: nil, queue: .main
        ) { [weak self] notification in
            let change = notification.userInfo?[Settings.changeUserInfoKey] as? Settings.Change
            if change == .colorScheme {
                self?.window?.appearance = Settings.colorScheme.appearance
            }
            guard change == .processWhitelist else { return }
            self?.refreshRules()
            self?.refreshEditor()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        if let settingsObserver { NotificationCenter.default.removeObserver(settingsObserver) }
    }

    func present(asSheetFor parent: NSWindow) {
        guard let window, window.sheetParent == nil else { return }
        window.appearance = parent.appearance
        parent.beginSheet(window)
        window.makeFirstResponder(pattern)
    }

    private func buildView() {
        guard let content = window?.contentView else { return }
        let explanation = NSTextField(wrappingLabelWithString:
            "Matching processes stay hidden from Process Activity. To edit a rule, remove it and add its replacement.")
        explanation.textColor = .secondaryLabelColor
        explanation.font = .systemFont(ofSize: 12)

        table.identifier = NSUserInterfaceItemIdentifier("settings.process-whitelist.rules")
        table.setAccessibilityIdentifier("settings.process-whitelist.rules")
        table.setAccessibilityLabel("Process whitelist rules")
        table.delegate = self
        table.dataSource = self
        table.rowHeight = 26
        table.usesAlternatingRowBackgroundColors = true
        table.allowsEmptySelection = true
        for (identifier, title, width) in [("mode", "Match", CGFloat(92)), ("pattern", "Process name or pattern", CGFloat(350))] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
            column.title = title
            column.width = width
            table.addTableColumn(column)
        }
        let scroll = NSScrollView()
        scroll.borderType = .bezelBorder
        scroll.hasVerticalScroller = true
        scroll.documentView = table
        scroll.heightAnchor.constraint(equalToConstant: 166).isActive = true

        configure(removeButton, identifier: "remove", action: #selector(removeRule(_:)))
        removeButton.setAccessibilityHelp("Remove the selected rule so matching processes can appear again.")
        configure(addButton, identifier: "add", action: #selector(addRule(_:)))
        mode.identifier = NSUserInterfaceItemIdentifier("settings.process-whitelist.mode")
        mode.setAccessibilityIdentifier("settings.process-whitelist.mode")
        mode.setAccessibilityLabel("Match type")
        mode.addItems(withTitles: ProcessWhitelistRule.MatchMode.allCases.map(Self.title))
        mode.target = self
        mode.action = #selector(changeMode(_:))
        mode.widthAnchor.constraint(equalToConstant: 105).isActive = true
        pattern.identifier = NSUserInterfaceItemIdentifier("settings.process-whitelist.pattern")
        pattern.setAccessibilityIdentifier("settings.process-whitelist.pattern")
        pattern.setAccessibilityLabel("Process name or pattern")
        pattern.placeholderString = "Process name or pattern"
        pattern.delegate = self
        pattern.target = self
        pattern.action = #selector(addRule(_:))
        let editor = NSStackView(views: [mode, pattern, addButton])
        editor.orientation = .horizontal
        editor.spacing = 8
        pattern.setContentHuggingPriority(.defaultLow, for: .horizontal)

        help.font = .systemFont(ofSize: 11)
        help.textColor = .secondaryLabelColor
        help.identifier = NSUserInterfaceItemIdentifier("settings.process-whitelist.help")
        message.identifier = NSUserInterfaceItemIdentifier("settings.process-whitelist.validation")
        message.setAccessibilityIdentifier("settings.process-whitelist.validation")
        message.font = .systemFont(ofSize: 11)
        message.textColor = .systemRed
        message.heightAnchor.constraint(equalToConstant: 16).isActive = true
        let done = NSButton(title: "Done", target: self, action: #selector(dismiss(_:)))
        done.identifier = NSUserInterfaceItemIdentifier("settings.process-whitelist.done")
        done.setAccessibilityIdentifier("settings.process-whitelist.done")
        done.bezelStyle = .rounded
        done.keyEquivalent = "\u{1b}"
        let footer = NSStackView(views: [removeButton, NSView(), done])
        footer.orientation = .horizontal
        footer.spacing = 8
        let stack = NSStackView(views: [explanation, scroll, editor, help, message, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -20),
        ] + [explanation, scroll, editor, help, message, footer].map {
            $0.widthAnchor.constraint(equalTo: stack.widthAnchor)
        })
    }

    private func configure(_ button: NSButton, identifier: String, action: Selector) {
        button.identifier = NSUserInterfaceItemIdentifier("settings.process-whitelist.\(identifier)")
        button.setAccessibilityIdentifier("settings.process-whitelist.\(identifier)")
        button.bezelStyle = .rounded
        button.target = self
        button.action = action
    }

    private static func title(_ mode: ProcessWhitelistRule.MatchMode) -> String {
        switch mode {
        case .exact: return "Exact"
        case .wildcard: return "Wildcard"
        case .regex: return "Regex"
        }
    }

    private var candidate: ProcessWhitelistRule {
        let modes = ProcessWhitelistRule.MatchMode.allCases
        return ProcessWhitelistRule(pattern: pattern.stringValue, mode: modes[mode.indexOfSelectedItem])
    }

    private func refreshRules() {
        let selected = rules.indices.contains(table.selectedRow) ? rules[table.selectedRow] : nil
        rules = Settings.processWhitelist
        table.reloadData()
        if let selected, let index = rules.firstIndex(of: selected) {
            table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        } else {
            table.deselectAll(nil)
        }
        removeButton.isEnabled = table.selectedRow >= 0
    }

    private func refreshEditor() {
        let rule = candidate
        let error = rule.validationMessage ?? (rules.contains(rule) ? "This rule is already in the whitelist." : nil)
        message.stringValue = pattern.stringValue.isEmpty ? "" : error ?? ""
        addButton.isEnabled = error == nil
        switch rule.mode {
        case .exact: help.stringValue = "Exact matches the whole process name. Matching is case-sensitive."
        case .wildcard: help.stringValue = "Wildcard matches the whole name: * means any text, ? means one character. Case-sensitive."
        case .regex: help.stringValue = "Regex searches within the name. Use ^ and $ to match the whole name. Case-sensitive."
        }
    }

    @objc private func addRule(_ sender: Any?) {
        let rule = candidate
        if let error = rule.validationMessage {
            message.stringValue = error
            return
        }
        guard !rules.contains(rule) else { refreshEditor(); return }
        Settings.processWhitelist = Settings.processWhitelist + [rule]
        pattern.stringValue = ""
        refreshEditor()
    }

    @objc private func removeRule(_ sender: NSButton) {
        guard rules.indices.contains(table.selectedRow) else { return }
        let selected = rules[table.selectedRow]
        Settings.processWhitelist = Settings.processWhitelist.filter { $0 != selected }
    }

    @objc private func changeMode(_ sender: NSPopUpButton) { refreshEditor() }

    @objc private func dismiss(_ sender: NSButton) {
        close()
    }

    override func close() {
        if let window { window.sheetParent?.endSheet(window) }
        super.close()
    }

    func controlTextDidChange(_ notification: Notification) { refreshEditor() }

    func numberOfRows(in tableView: NSTableView) -> Int { rules.count }

    func tableViewSelectionDidChange(_ notification: Notification) {
        removeButton.isEnabled = rules.indices.contains(table.selectedRow)
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard rules.indices.contains(row) else { return nil }
        let label = NSTextField(labelWithString: tableColumn?.identifier.rawValue == "mode"
                              ? Self.title(rules[row].mode) : rules[row].pattern)
        label.lineBreakMode = .byTruncatingTail
        label.toolTip = rules[row].pattern
        return label
    }
}
