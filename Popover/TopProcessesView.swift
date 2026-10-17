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
    private var infoPopover: NSPopover?
    private var count = 3
    private var compact = false

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
        scale.toolTip = Self.activityHelp
        infoButton.isBordered = false
        infoButton.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
        infoButton.imagePosition = .imageOnly
        infoButton.imageScaling = .scaleProportionallyDown
        infoButton.contentTintColor = PopoverStyle.secondaryText
        infoButton.setButtonType(.momentaryPushIn)
        infoButton.target = self
        infoButton.action = #selector(showActivityInfo(_:))
        infoButton.toolTip = Self.activityHelp
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
            addSubview(row)
        }
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
    }

    override func refreshAppearance() {
        super.refreshAppearance()
        rows.forEach { $0.refreshAppearance() }
        infoPopover?.contentViewController?.view.appearance = effectiveAppearance
    }

    override func viewDidHide() {
        infoPopover?.performClose(nil)
        super.viewDidHide()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { infoPopover?.performClose(nil) }
    }

    func setPresentationActive(_ active: Bool) {
        if !active { infoPopover?.performClose(nil) }
    }

    var helpWindow: NSWindow? {
        guard infoPopover?.isShown == true else { return nil }
        return infoPopover?.contentViewController?.view.window
    }

    func update(state: TopProcessesState, count: Int, compact: Bool = false) {
        self.count = min(max(count, 1), 10)
        self.compact = compact
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
        status.toolTip = status.accessibilityHelp()
        for (index, row) in rows.enumerated() {
            guard index < processes.count else {
                row.isHidden = true
                continue
            }
            row.update(process: processes[index], compact: compact)
            row.isHidden = false
        }
        needsLayout = true
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

    var gradientPreviewGeometryForTest: [(gradientWidth: CGFloat, visibleMaskWidth: CGFloat, usesFixedScale: Bool)] {
        layoutSubtreeIfNeeded()
        return rows.filter { !$0.isHidden }.map(\.gradientPreviewGeometry)
    }
#endif

    private final class ProcessRow: NSView {
        private let name = NSTextField(labelWithString: "")
        private let value = NSTextField(labelWithString: "")
        private let details = NSTextField(labelWithString: "")
        private let overflow = NSImageView()
        private let track = CALayer()
        private let fill = CAGradientLayer()
        private let fillMask = CALayer()
        private var ratio: CGFloat = 0
#if DEBUG
        private var gradientPreviewStyle: GradientPreviewStyle = .fixedScaleHorizontal
#endif

        override var isFlipped: Bool { true }

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
            setAccessibilityElement(true)
            setAccessibilityRole(.staticText)
            setAccessibilityHelp(TopProcessesView.activityHelp)
            refreshAppearance()
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func layout() {
            super.layout()
            name.frame = NSRect(x: 0, y: 2, width: 132, height: 20)
            value.frame = NSRect(x: 272, y: 2, width: 56, height: 20)
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

        func refreshAppearance() {
            effectiveAppearance.performAsCurrentDrawingAppearance {
                let contrast = PopoverStyle.isHighContrast(effectiveAppearance)
                PopoverStyle.setWithoutAnimation {
                    self.track.backgroundColor = NSColor.clear.cgColor
                    self.track.borderColor = contrast ? NSColor.labelColor.cgColor
                        : NSColor(rgb: PopoverStyle.isDark(self.effectiveAppearance) ? 0xDCEEFF : 0xAAC7DE,
                                  alpha: PopoverStyle.isDark(self.effectiveAppearance) ? 0.75 : 1).cgColor
                    self.fill.colors = contrast
                        ? [NSColor.systemBlue.cgColor, NSColor.systemBlue.cgColor, NSColor.systemBlue.cgColor]
                        : [NSColor(rgb: 0x9CDCFF).cgColor, NSColor(rgb: 0x2C9DFF).cgColor, NSColor(rgb: 0x0B69D9).cgColor]
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
            let exact = "Activity Score \(score); CPU \(process.cpuPercent)%; idle wakeups \(process.idleWakeupsPerSecond) per second"
            value.toolTip = exact
            details.toolTip = exact
            setAccessibilityLabel(process.name)
            setAccessibilityValue(exact)
            toolTip = "\(process.name) · PID \(process.pid)\n\(exact)\n\(TopProcessesView.activityHelp)"
            needsLayout = true
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
