import AppKit

/// Process activity on a fixed scale, on the popover's shared surface.
final class TopProcessesView: PopoverSection {
    private static let rowHeight: CGFloat = 44
    private static let compactRowHeight: CGFloat = 28
    private static let activityHelp = "Activity Score combines CPU usage and idle wakeups. Higher scores indicate greater process activity, not measured power consumption. Bars use a fixed 0–100 scale; › marks scores above 100. CPU 100% means one logical core."
    private let title = NSTextField(labelWithString: "Process Activity")
    private let scale = NSTextField(labelWithString: "Activity Score")
    private let infoButton = NSButton(title: "", target: nil, action: nil)
    private let status = NSTextField(labelWithString: "Measuring…")
    private let rows = (0..<10).map { _ in ProcessRow() }
    private let actionFeedback = FooterHoverFeedbackView(frame: .zero)
    private var infoPopover: NSPopover?
    private var count = 3
    private var compact = false
    private var renderedState: TopProcessesState?
    private var selectedProcess: Selection?
    var forceQuitHandler: ((EnergyProcess) -> Void)?

    private enum Selection: Equatable {
        case identified(ProcessIdentity)
        case unavailable(Int32, String)

        init(_ process: EnergyProcess) {
            if let identity = process.terminationIdentity {
                self = .identified(identity)
            } else {
                self = .unavailable(process.pid, process.name)
            }
        }
    }
#if DEBUG
    private(set) var contentUpdatesForTest = 0
#endif

    static func preferredHeight(count: Int, compact: Bool = false) -> CGFloat {
        36 + (compact ? compactRowHeight : rowHeight) * CGFloat(min(max(count, 1), 10))
    }

    init() {
        super.init(height: Self.preferredHeight(count: 3))
        for field in [title, scale] {
            field.font = .systemFont(ofSize: 11.5, weight: .regular)
            field.textColor = PopoverStyle.secondaryText
            field.setAccessibilityElement(false)
            addSubview(field)
        }
        scale.font = .systemFont(ofSize: 10.5, weight: .regular)
        scale.alignment = .right
        scale.toolTip = "CPU and idle-wakeup activity"
        infoButton.isBordered = false
        infoButton.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
        infoButton.imagePosition = .imageOnly
        infoButton.imageScaling = .scaleProportionallyDown
        infoButton.contentTintColor = PopoverStyle.secondaryText
        infoButton.setButtonType(.momentaryPushIn)
        infoButton.target = self
        infoButton.action = #selector(showActivityInfo(_:))
        infoButton.toolTip = "About Activity Score"
        infoButton.setAccessibilityLabel("About Process Activity")
        infoButton.setAccessibilityHelp(Self.activityHelp)
        addSubview(infoButton)

        status.font = .systemFont(ofSize: 13, weight: .regular)
        status.textColor = PopoverStyle.secondaryText
        status.alignment = .center
        status.setAccessibilityLabel("Process Activity")
        addSubview(status)
        for row in rows {
            row.isHidden = true
            row.selectionHandler = { [weak self, weak row] in
                guard let self, let process = row?.process else { return }
                let selection = Selection(process)
                self.select(self.selectedProcess == selection ? nil : selection)
            }
            row.moveSelectionHandler = { [weak self, weak row] direction in
                guard let self, let row, let index = self.rows.firstIndex(where: { $0 === row }) else { return }
                let next = index + direction
                guard self.rows.indices.contains(next), !self.rows[next].isHidden,
                      let process = self.rows[next].process else { return }
                self.select(Selection(process))
                self.window?.makeFirstResponder(self.rows[next])
            }
            row.clearSelectionHandler = { [weak self] in self?.select(nil) }
            row.forceQuitHandler = { [weak self] process in self?.forceQuitHandler?(process) }
            addSubview(row)
        }
        addSubview(actionFeedback)
        setAccessibilityLabel("Process Activity")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        title.frame = NSRect(x: 0, y: 7, width: 190, height: 16)
        scale.frame = NSRect(x: bounds.width - 104, y: 7, width: 78, height: 16)
        infoButton.frame = NSRect(x: bounds.width - 18, y: 5, width: 18, height: 18)
        let rowHeight = compact ? Self.compactRowHeight : Self.rowHeight
        for (index, row) in rows.enumerated() {
            row.frame = NSRect(x: 0, y: 28 + CGFloat(index) * rowHeight,
                               width: bounds.width, height: rowHeight)
        }
        status.frame = NSRect(x: 0, y: 28 + (CGFloat(count) * rowHeight - 20) / 2,
                              width: bounds.width, height: 20)
        actionFeedback.frame = bounds
        updateActionFeedback()
    }

    override func refreshAppearance() {
        super.refreshAppearance()
        rows.forEach { $0.refreshAppearance() }
        infoPopover?.contentViewController?.view.appearance = effectiveAppearance
    }

    override func viewDidHide() {
        infoPopover?.performClose(nil)
        actionFeedback.cancelHover()
        select(nil)
        super.viewDidHide()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            infoPopover?.performClose(nil)
            actionFeedback.cancelHover()
            select(nil)
        }
    }

    func setPresentationActive(_ active: Bool) {
        actionFeedback.setPresentationActive(active)
        if !active {
            infoPopover?.performClose(nil)
            select(nil)
        }
    }

    var helpWindow: NSWindow? {
        guard infoPopover?.isShown == true else { return nil }
        return infoPopover?.contentViewController?.view.window
    }

    func update(state: TopProcessesState, count: Int, compact: Bool = false,
                color: NSColor = PopoverStyle.blue) {
        rows.forEach { $0.setBarColor(color) }
        let count = min(max(count, 1), 10)
        guard renderedState != state || self.count != count || self.compact != compact else { return }
        if count < self.count { select(nil) }
        renderedState = state
        self.count = count
        self.compact = compact
#if DEBUG
        contentUpdatesForTest += 1
#endif
        let processes: [EnergyProcess]
        switch state {
        case .loading:
            processes = []
            status.stringValue = "Measuring…"
            status.setAccessibilityHelp("Measuring process CPU activity and idle wakeups over about one second.")
        case .unavailable:
            processes = []
            status.stringValue = "Unavailable"
            status.setAccessibilityHelp("Process activity readings require the Wattson helper and a successful sampling interval.")
        case .ready(let values):
            processes = Array(values.prefix(self.count))
            status.stringValue = "No active processes"
            status.setAccessibilityHelp("No active process readings were reported in the recent sampling interval.")
        }
        status.isHidden = !processes.isEmpty
        switch state {
        case .loading: status.toolTip = "Sampling activity…"
        case .unavailable: status.toolTip = "Requires the Wattson helper"
        case .ready: status.toolTip = nil
        }
        if let selectedProcess, !processes.contains(where: { Selection($0) == selectedProcess }) {
            self.selectedProcess = nil
        }
        for (index, row) in rows.enumerated() {
            guard index < processes.count else {
                row.clear()
                row.isHidden = true
                continue
            }
            row.update(process: processes[index], compact: compact)
            row.isHidden = false
            row.setSelected(selectedProcess == Selection(processes[index]))
        }
        needsLayout = true
        updateActionFeedback()
    }

    private func select(_ selection: Selection?) {
        guard selectedProcess != selection else { return }
        selectedProcess = selection
        for row in rows {
            row.setSelected(!row.isHidden && row.process.map { Selection($0) == selection } == true)
        }
        needsLayout = true
        updateActionFeedback()
    }

    private func updateActionFeedback() {
        guard let row = rows.first(where: { !$0.isHidden && $0.isSelected }) else {
            actionFeedback.update(regions: [])
            return
        }
        row.layoutSubtreeIfNeeded()
        let button = row.forceQuitButton
        actionFeedback.update(regions: [.init(rect: button.convert(button.bounds, to: actionFeedback),
                                              enabled: button.isEnabled)])
    }

    @objc private func showActivityInfo(_ sender: NSButton) {
        if infoPopover?.isShown == true {
            infoPopover?.performClose(nil)
            return
        }
        guard window != nil, !isHiddenOrHasHiddenAncestor else { return }
        if infoPopover == nil {
            let controller = NSViewController()
            let font = NSFont.systemFont(ofSize: 12)
            let textWidth: CGFloat = 282
            let textHeight = ceil((Self.activityHelp as NSString).boundingRect(
                with: NSSize(width: textWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font]
            ).height)
            controller.view = NSView(frame: NSRect(x: 0, y: 0, width: textWidth + 28, height: textHeight + 28))
            let explanation = NSTextField(wrappingLabelWithString: Self.activityHelp)
            explanation.font = font
            explanation.textColor = PopoverStyle.primaryText
            explanation.frame = NSRect(x: 14, y: 14, width: textWidth, height: textHeight)
            explanation.setAccessibilityLabel(Self.activityHelp)
            controller.view.addSubview(explanation)
            let popover = NSPopover()
            popover.behavior = .semitransient
            popover.animates = false
            popover.contentViewController = controller
            infoPopover = popover
        }
        infoPopover?.contentViewController?.view.appearance = effectiveAppearance
        infoPopover?.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
    }

#if DEBUG
    enum GradientPreviewStyle: CaseIterable {
        case fixedScaleHorizontal, filledWidthHorizontal, vertical, activityTint
    }

    func setGradientPreviewStyle(_ style: GradientPreviewStyle) {
        rows.forEach { $0.setGradientPreviewStyle(style) }
    }

    var barGeometryForTest: [(track: NSRect, fill: NSRect, ratio: CGFloat)] {
        layoutSubtreeIfNeeded()
        return rows.filter { !$0.isHidden }.map(\.barGeometry)
    }

    var activityHelpForTest: String { Self.activityHelp }

    var processRowsForTest: [NSView] { rows.filter { !$0.isHidden } }
    var forceQuitButtonsForTest: [NSButton] { rows.filter { !$0.isHidden }.map(\.forceQuitButton) }
    var selectedRowIndexForTest: Int? { rows.firstIndex { !$0.isHidden && $0.isSelected } }
    var selectedProcessForTest: EnergyProcess? { selectedRowIndexForTest.flatMap { rows[$0].process } }
    var forceQuitFeedbackForTest: FooterHoverFeedbackView { actionFeedback }

    var gradientPreviewGeometryForTest: [(gradientWidth: CGFloat, visibleMaskWidth: CGFloat, usesFixedScale: Bool)] {
        layoutSubtreeIfNeeded()
        return rows.filter { !$0.isHidden }.map(\.gradientPreviewGeometry)
    }
#endif

    private final class ProcessRow: NSView {
        private let name = NSTextField(labelWithString: "")
        private let value = NSTextField(labelWithString: "")
        private let details = NSTextField(labelWithString: "")
        let forceQuitButton = ProcessActionButton(frame: .zero)
        private let overflow = NSImageView()
        private let track = CALayer()
        private let fill = CAGradientLayer()
        private let fillMask = CALayer()
        private var barColor = PopoverStyle.blue
        private var ratio: CGFloat = 0
        private(set) var process: EnergyProcess?
        private(set) var isSelected = false
        var selectionHandler: (() -> Void)?
        var moveSelectionHandler: ((Int) -> Void)?
        var clearSelectionHandler: (() -> Void)?
        var forceQuitHandler: ((EnergyProcess) -> Void)?
#if DEBUG
        private var gradientPreviewStyle: GradientPreviewStyle = .fixedScaleHorizontal
#endif

        override var isFlipped: Bool { true }
        override var acceptsFirstResponder: Bool { !isHiddenOrHasHiddenAncestor && process != nil }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        init() {
            super.init(frame: .zero)
            wantsLayer = true
            identifier = NSUserInterfaceItemIdentifier("top-processes.row")
            track.name = "top-processes.track"
            track.cornerRadius = 3
            track.cornerCurve = .continuous
            track.borderWidth = 1
            track.masksToBounds = true
            fill.cornerRadius = 2
            fill.cornerCurve = .continuous
            fill.startPoint = CGPoint(x: 0, y: 0.5)
            fill.endPoint = CGPoint(x: 1, y: 0.5)
            fill.locations = [0, 0.45, 1]
            fillMask.backgroundColor = NSColor.black.cgColor
            fillMask.cornerRadius = 2
            fillMask.cornerCurve = .continuous
            fill.mask = fillMask
            track.addSublayer(fill)
            layer?.addSublayer(track)
            layer?.cornerRadius = 4
            layer?.cornerCurve = .continuous
            name.font = .systemFont(ofSize: 13, weight: .regular)
            name.textColor = PopoverStyle.primaryText
            value.font = PopoverStyle.mono(13, .semibold)
            value.textColor = PopoverStyle.primaryText
            value.alignment = .right
            details.font = .systemFont(ofSize: 11, weight: .regular)
            details.textColor = PopoverStyle.secondaryText
            for field in [name, value, details] {
                field.maximumNumberOfLines = 1
                field.lineBreakMode = .byTruncatingTail
                field.cell?.wraps = false
                field.cell?.isScrollable = false
                field.setAccessibilityElement(false)
                addSubview(field)
            }
            overflow.identifier = NSUserInterfaceItemIdentifier("top-processes.overflow")
            overflow.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
            overflow.imageScaling = .scaleProportionallyDown
            overflow.contentTintColor = PopoverStyle.primaryText
            overflow.setAccessibilityElement(false)
            overflow.isHidden = true
            addSubview(overflow)
            forceQuitButton.identifier = NSUserInterfaceItemIdentifier("top-processes.force-quit")
            forceQuitButton.target = self
            forceQuitButton.action = #selector(forceQuitSelectedProcess(_:))
            forceQuitButton.isHidden = true
            forceQuitButton.setAccessibilityElement(false)
            addSubview(forceQuitButton)
            setAccessibilityElement(true)
            setAccessibilityRole(.group)
            setAccessibilityChildren([])
            setAccessibilitySelected(false)
            setAccessibilityHelp("Select to show Force Quit.")
            refreshAppearance()
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func layout() {
            super.layout()
            name.frame = NSRect(x: 0, y: 2, width: 132, height: 20)
            value.frame = NSRect(x: 272, y: 2, width: 56, height: 20)
            forceQuitButton.frame = isSelected ? NSRect(x: 288, y: 4, width: 38, height: 16) : .zero
            details.frame = details.isHidden ? .zero : NSRect(x: 0, y: 25, width: bounds.width, height: 15)
            overflow.frame = NSRect(x: 262, y: 6, width: 8, height: 12)
            PopoverStyle.setWithoutAnimation {
                self.track.frame = NSRect(x: 144, y: 6, width: 116, height: 12)
                self.fill.frame = NSRect(x: 1, y: 1, width: 114, height: 10)
                self.fillMask.frame = NSRect(x: 0, y: 0, width: 114 * self.ratio, height: 10)
                self.fill.mask = self.fillMask
#if DEBUG
                if self.gradientPreviewStyle != .fixedScaleHorizontal {
                    self.fill.frame.size.width = 114 * self.ratio
                    self.fill.mask = nil
                }
#endif
            }
        }

        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            refreshAppearance()
        }

        func setBarColor(_ color: NSColor) {
            guard !barColor.isEqual(color) else { return }
            barColor = color
            refreshAppearance()
        }

        func refreshAppearance() {
            forceQuitButton.refreshAppearance()
            effectiveAppearance.performAsCurrentDrawingAppearance {
                let contrast = PopoverStyle.isHighContrast(effectiveAppearance)
                let tint = barColor.usingColorSpace(.sRGB)!
                PopoverStyle.setWithoutAnimation {
                    self.layer?.backgroundColor = self.isSelected
                        ? NSColor.labelColor.withAlphaComponent(contrast ? 0.08 : 0.045).cgColor
                        : NSColor.clear.cgColor
                    self.layer?.borderColor = contrast ? NSColor.labelColor.cgColor : NSColor.clear.cgColor
                    self.layer?.borderWidth = self.isSelected && contrast ? 1 : 0
                    self.track.backgroundColor = NSColor.clear.cgColor
                    self.track.borderColor = contrast ? NSColor.labelColor.cgColor
                        : tint.blended(withFraction: PopoverStyle.isDark(self.effectiveAppearance) ? 0.72 : 0.5,
                                       of: .white)!
                            .withAlphaComponent(PopoverStyle.isDark(self.effectiveAppearance) ? 0.75 : 1).cgColor
                    self.fill.colors = contrast
                        ? [tint.cgColor, tint.cgColor, tint.cgColor]
                        : [tint.blended(withFraction: 0.65, of: .white)!.cgColor, tint.cgColor,
                           tint.blended(withFraction: 0.18, of: .black)!.cgColor]
#if DEBUG
                    let vertical = self.gradientPreviewStyle == .vertical || self.gradientPreviewStyle == .activityTint
                    self.fill.startPoint = vertical ? CGPoint(x: 0.5, y: 0) : CGPoint(x: 0, y: 0.5)
                    self.fill.endPoint = vertical ? CGPoint(x: 0.5, y: 1) : CGPoint(x: 1, y: 0.5)
                    if self.gradientPreviewStyle == .activityTint && !contrast {
                        let low = [0xD4ECFF, 0x90C9F5, 0x5BA5E3].map { NSColor(rgb: $0) }
                        let high = [0x78BCFF, 0x187DE0, 0x0754B0].map { NSColor(rgb: $0) }
                        self.fill.colors = zip(low, high).map {
                            $0.blended(withFraction: self.ratio, of: $1)!.cgColor
                        }
                    }
#endif
                }
            }
        }

        func update(process: EnergyProcess, compact: Bool) {
            self.process = process
            name.stringValue = process.name
            name.toolTip = "\(process.name) · PID \(process.pid)"
            details.isHidden = compact
            let score = process.energyImpact
            ratio = CGFloat(min(max(score / 100, 0), 1))
#if DEBUG
            if gradientPreviewStyle == .activityTint { refreshAppearance() }
#endif
            value.stringValue = Self.shortNumber(score)
            overflow.isHidden = score <= 100
            details.stringValue = "CPU \(Self.shortNumber(process.cpuPercent))% · Idle wakeups \(Self.wakeupNumber(process.idleWakeupsPerSecond))/s"
            let summary = "Score \(Self.shortNumber(score)) · CPU \(Self.shortNumber(process.cpuPercent))% · Wakeups \(Self.wakeupNumber(process.idleWakeupsPerSecond))/s"
            value.toolTip = summary
            details.toolTip = summary
            setAccessibilityLabel(process.name)
            setAccessibilityValue("Activity Score \(Self.shortNumber(score)); CPU \(Self.shortNumber(process.cpuPercent))%; idle wakeups \(Self.wakeupNumber(process.idleWakeupsPerSecond)) per second")
            toolTip = "\(process.name) · PID \(process.pid)\n\(summary)"
            forceQuitButton.isEnabled = process.terminationIdentity != nil
            forceQuitButton.refreshAppearance()
            forceQuitButton.toolTip = process.terminationIdentity != nil ? "Force Quit" : "Force Quit Unavailable"
            forceQuitButton.setAccessibilityLabel("Force Quit \(process.name)")
            forceQuitButton.setAccessibilityHelp(forceQuitButton.toolTip)
            needsLayout = true
        }

        func clear() {
            process = nil
            setSelected(false)
        }

        func setSelected(_ selected: Bool) {
            guard isSelected != selected else { return }
            isSelected = selected
            forceQuitButton.isHidden = !selected
            value.isHidden = selected
            forceQuitButton.setAccessibilityElement(selected)
            setAccessibilitySelected(selected)
            setAccessibilityChildren(selected ? [forceQuitButton] : [])
            refreshAppearance()
            needsLayout = true
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let hit = super.hitTest(point) else { return nil }
            return hit is NSButton ? hit : self
        }

        override func mouseDown(with event: NSEvent) {
            guard !isHiddenOrHasHiddenAncestor, process != nil else { return }
            window?.makeFirstResponder(self)
            selectionHandler?()
        }

        override func keyDown(with event: NSEvent) {
            guard !isHiddenOrHasHiddenAncestor, process != nil else { return }
            switch event.keyCode {
            case 36, 49, 76: selectionHandler?()
            case 126: moveSelectionHandler?(-1)
            case 125: moveSelectionHandler?(1)
            case 53: clearSelectionHandler?()
            default: super.keyDown(with: event)
            }
        }

        override func accessibilityPerformPress() -> Bool {
            guard !isHiddenOrHasHiddenAncestor, process != nil else { return false }
            selectionHandler?()
            return true
        }

        @objc private func forceQuitSelectedProcess(_ sender: NSButton) {
            guard isSelected, !isHiddenOrHasHiddenAncestor, sender.isEnabled,
                  let process, process.terminationIdentity != nil else { return }
            forceQuitHandler?(process)
        }

        private static func shortNumber(_ number: Double) -> String {
            if number > 0 && number < 0.1 { return "<0.1" }
            if number < 999.95 { return String(format: "%.1f", number) }
            if number < 10_000 { return String(format: "%.0f", number) }
            return String(format: "%.0e", number).replacingOccurrences(of: "e+", with: "e")
        }

        private static func wakeupNumber(_ number: Double) -> String {
            if number > 0 && number < 1 { return shortNumber(number) }
            if number < 10_000 { return String(format: "%.0f", number) }
            return shortNumber(number)
        }

        var barGeometry: (track: NSRect, fill: NSRect, ratio: CGFloat) {
            (track.frame, fill.frame, ratio)
        }

#if DEBUG
        func setGradientPreviewStyle(_ style: GradientPreviewStyle) {
            gradientPreviewStyle = style
            refreshAppearance()
            needsLayout = true
        }

        var gradientPreviewGeometry: (gradientWidth: CGFloat, visibleMaskWidth: CGFloat, usesFixedScale: Bool) {
            (fill.frame.width, fill.mask?.frame.width ?? fill.frame.width, fill.mask != nil)
        }
#endif
    }
}
