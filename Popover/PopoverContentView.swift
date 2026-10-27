import AppKit

typealias PopoverModule = Settings.Module

/// Hero number and state. No separator — it is the top of the surface.
final class PopoverHeaderView: PopoverSection {
    static let preferredHeight: CGFloat = 48

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
            state.stringValue = PopoverStyle.stateTitle(snapshot)
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

final class PopoverRuntimeView: PopoverSection {
    static let preferredHeight: CGFloat = 88
    private let iconWell = CALayer()
    private let clock = NSImageView()
    private let title = NSTextField(labelWithString: "Estimated Battery Runtime")
    private let runtime = NSTextField(labelWithString: "")
    private let sourceIndicator = BatteryTimeIndicatorView()

    init() {
        super.init(height: Self.preferredHeight)
        iconWell.cornerRadius = 11
        iconWell.cornerCurve = .continuous
        layer?.addSublayer(iconWell)

        clock.image = NSImage(systemSymbolName: "clock", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 24, weight: .regular))
        clock.contentTintColor = PopoverStyle.neutral
        clock.setAccessibilityElement(false)
        addSubview(clock)

        title.font = .systemFont(ofSize: 11.5, weight: .regular)
        title.textColor = PopoverStyle.secondaryText
        title.alignment = .right
        title.setAccessibilityElement(false)
        addSubview(title)

        runtime.font = PopoverStyle.mono(24, .semibold)
        runtime.textColor = PopoverStyle.primaryText
        runtime.alignment = .right
        runtime.setAccessibilityLabel("Estimated battery runtime")
        runtime.setAccessibilityHelp("macOS estimates remaining battery time for current usage. It changes with workload.")
        addSubview(runtime)
        addSubview(sourceIndicator)
        toolTip = "macOS estimates remaining battery time for current usage. It changes with workload."
        refreshAppearance()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        PopoverStyle.setWithoutAnimation {
            self.iconWell.frame = CGRect(x: 12, y: 22, width: 44, height: 44)
        }
        clock.frame = NSRect(x: 22, y: 32, width: 24, height: 24)
        title.frame = NSRect(x: 68, y: 20, width: bounds.width - 80, height: 16)
        sourceIndicator.frame = NSRect(x: title.frame.maxX - ceil(title.intrinsicContentSize.width) - 24,
                                       y: title.frame.midY - 10, width: 20, height: 20)
        runtime.frame = NSRect(x: 68, y: 39, width: bounds.width - 80,
                               height: runtime.intrinsicContentSize.height)
    }

    override func refreshAppearance() {
        super.refreshAppearance()
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let contrast = PopoverStyle.isHighContrast(effectiveAppearance)
            PopoverStyle.setWithoutAnimation {
                self.iconWell.backgroundColor = PopoverStyle.well.cgColor
                self.iconWell.borderColor = PopoverStyle.wellBorder.cgColor
                self.iconWell.borderWidth = contrast ? 1 : 0.5
            }
            clock.contentTintColor = PopoverStyle.neutral
        }
        sourceIndicator.refreshAppearance()
    }

    func update(snapshot: PowerSnapshot, degraded: Bool) {
        sourceIndicator.update(snapshot: snapshot, degraded: degraded)
        title.stringValue = snapshot.plugged ? "Estimated Time to Full" : "Estimated Battery Runtime"
        var help: String
        switch snapshot.batteryTimeEstimateSource {
        case .batteryGauge:
            help = snapshot.plugged
                ? "The battery controller estimates time until full. It changes with charging conditions and workload."
                : "The battery controller estimates remaining battery time. It changes with workload."
        case .observedDischarge:
            help = "Approximate runtime from remaining battery charge and recent average discharge current. It changes with workload."
        default:
            help = snapshot.plugged
                ? "macOS estimates time until the battery is full while charging. It changes with charging conditions and workload."
                : "macOS estimates remaining battery time for current usage. It changes with workload."
        }
        if sourceIndicator.status == .calculating || sourceIndicator.status == .unavailable {
            help = sourceIndicator.accessibilityHelp() ?? help
        }
        runtime.setAccessibilityLabel(snapshot.plugged ? "Estimated time to full charge" : "Estimated battery runtime")
        runtime.setAccessibilityHelp(help)
        toolTip = help

        var minutes: Int?
        var stateText = "Unavailable"
        if !degraded {
            switch snapshot.batteryTimeEstimate {
            case .remaining(let value) where !snapshot.plugged:
                minutes = value
                stateText = "Calculating…"
            case .charging(let value) where snapshot.plugged:
                minutes = value
                stateText = "Calculating…"
            case .full where snapshot.plugged:
                stateText = "Fully Charged"
            case .notCharging where snapshot.plugged:
                stateText = "Not Charging"
            default:
                break
            }
            if snapshot.state == .mixedSupply {
                minutes = nil
                stateText = "Not Charging"
            }
        }
        let runtimeValue: String
        if let minutes, minutes >= 0 {
            if minutes == 0 {
                runtimeValue = "<1m"
            } else if minutes < 60 {
                runtimeValue = "\(minutes)m"
            } else {
                runtimeValue = "\(minutes / 60)h \(minutes % 60)m"
            }
        } else {
            runtimeValue = stateText
        }
        let hasEstimate = (minutes ?? -1) >= 0
        runtime.stringValue = hasEstimate && !snapshot.plugged
            && snapshot.batteryTimeEstimateSource == .observedDischarge
            ? "≈\(runtimeValue)" : runtimeValue
        runtime.font = hasEstimate ? PopoverStyle.mono(24, .semibold) : .systemFont(ofSize: 16, weight: .regular)
        runtime.textColor = hasEstimate ? PopoverStyle.primaryText : PopoverStyle.secondaryText
        needsLayout = true
    }

    func setAnimationsEnabled(_ enabled: Bool) { sourceIndicator.setAnimationsEnabled(enabled) }
    func setPresentationActive(_ active: Bool) { sourceIndicator.setPresentationActive(active) }

#if DEBUG
    func layoutFitsForTest(snapshot: PowerSnapshot, degraded: Bool = false) -> Bool {
        update(snapshot: snapshot, degraded: degraded)
        layoutSubtreeIfNeeded()
        return title.frame.maxY <= runtime.frame.minY
            && bounds.contains(sourceIndicator.frame)
            && sourceIndicator.frame.minX >= iconWell.frame.maxX
            && sourceIndicator.frame.maxX <= title.frame.maxX - ceil(title.intrinsicContentSize.width)
            && bounds.contains(iconWell.frame)
            && iconWell.frame.contains(clock.frame) && iconWell.frame.maxX < runtime.frame.minX
            && [title, runtime].allSatisfy { field in
                let required = field.stringValue.size(withAttributes: [.font: field.font as Any]).width
                return bounds.contains(field.frame) && required <= field.frame.width
            }
    }

    func runtimePresentationForTest(snapshot: PowerSnapshot, degraded: Bool = false) -> String {
        update(snapshot: snapshot, degraded: degraded)
        return presentationForTest
    }

    var presentationForTest: String { "\(title.stringValue) · \(runtime.stringValue)" }

    var sectionLayoutForTest: (titleFrame: NSRect, valueFrame: NSRect, iconFrame: NSRect,
                               valueFontSize: CGFloat, titleFontSize: CGFloat, hasTopSeparator: Bool,
                               iconWellFrame: NSRect) {
        layoutSubtreeIfNeeded()
        let hasTopSeparator = layer?.sublayers?.contains {
            $0.frame == CGRect(x: 0, y: 0, width: bounds.width, height: 0.5)
        } ?? false
        return (title.frame, runtime.frame, clock.frame, runtime.font!.pointSize, title.font!.pointSize,
                hasTopSeparator, iconWell.frame)
    }

    var wellColorsForTest: (fill: CGColor?, border: CGColor?, iconTint: NSColor?, borderWidth: CGFloat) {
        (iconWell.backgroundColor, iconWell.borderColor, clock.contentTintColor, iconWell.borderWidth)
    }
#endif
}

private final class PopoverButton: NSButton {
    override func becomeFirstResponder() -> Bool {
        guard super.becomeFirstResponder() else { return false }
        scrollToVisible(bounds.insetBy(dx: -2, dy: -2))
        return true
    }
}

/// Three-position mode control and system-battery visibility choice.
///
/// The tactile 2A slider remains the baseline presentation. Classic Reduce
/// Motion uses native segments; Liquid Glass prefers an interactive capsule,
/// with native glass buttons when accessibility requires a still surface.
final class PopoverFooterView: PopoverSection {
    static let preferredHeight: CGFloat = 78

    private struct ModeControlPresentation {
        let selected: EnergyMode
        let enabledModes: [EnergyMode]
        let tint: NSColor
        let busy: Bool

        func matches(selected: EnergyMode, enabledModes: [EnergyMode], tint: NSColor, busy: Bool) -> Bool {
            self.selected == selected
                && self.enabledModes == enabledModes
                && self.tint.isEqual(tint)
                && self.busy == busy
        }
    }

    private static var systemReducesMotion: Bool {
#if DEBUG
        switch ProcessInfo.processInfo.environment["WATTSON_FORCE_REDUCE_MOTION"] {
        case "1": return true
        case "0": return false
        default: break
        }
#endif
        return NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private static var systemReducesTransparency: Bool {
#if DEBUG
        switch ProcessInfo.processInfo.environment["WATTSON_FORCE_REDUCE_TRANSPARENCY"] {
        case "1": return true
        case "0": return false
        default: break
        }
#endif
        return NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }

    private let modes: [EnergyMode] = [.auto, .low, .high]
    private lazy var modeControl = ModeSliderView(modes: modes)
    private lazy var nativeModeControl = NativeModeSegmentedControl(modes: modes)
    private lazy var systemBatteryIconButton = PopoverButton(
        checkboxWithTitle: "Hide System Battery Icon",
        target: self,
        action: #selector(systemBatteryIconChanged)
    )
    private let statusMessage = NSTextField(labelWithString: "")
    private let settingsButton = PopoverButton()
    private var glassControls: NSView?
    private var glassModeControl: NativeGlassModeControl?
    private var interactiveGlassControl: NSView?
    private var usesInteractiveGlass = false
    private let glassControlsContent = NSView()
    private let hoverFeedback = FooterHoverFeedbackView()

    private var selected: EnergyMode = .auto
    private var pendingMode: EnergyMode?
    private var enabledModes: [EnergyMode] = []
    private var currentTint = PopoverStyle.blue
    private var selectionGeneration = 0
    private var synchronizedModePresentation: ModeControlPresentation?
    private var systemBatteryIconHidden: Bool?
    private var systemBatteryIconReadStatus: SystemBatteryIconReadStatus = .notRequested
    private var helperInstalled = false
    private var systemBatteryIconUpdateInFlight = false
    private var usesNativeModeControl = false
    private var displayOptionsObserver: NSObjectProtocol?
    private var settingsObserver: NSObjectProtocol?
    var onSelect: ((EnergyMode, @escaping (EnergyMode?) -> Void) -> Void)?
    var onSystemBatteryIconToggle: ((Bool, @escaping (Bool) -> Void) -> Void)?
    var onShowMenu: ((NSView) -> Void)?

    init() {
        super.init(height: Self.preferredHeight)

        modeControl.onSelect = { [weak self] mode, completion in
            guard let self else {
                completion(nil)
                return
            }
            self.requestModeSelection(mode, sourceCompletion: completion)
        }
        addSubview(modeControl)

        nativeModeControl.onSelect = { [weak self] mode in
            self?.requestModeSelection(mode)
        }
        addSubview(nativeModeControl)

        systemBatteryIconButton.controlSize = .small
        systemBatteryIconButton.font = .systemFont(ofSize: 11, weight: .regular)
        systemBatteryIconButton.allowsMixedState = true
        systemBatteryIconButton.state = .mixed
        systemBatteryIconButton.setAccessibilityHelp("Hide the built-in macOS battery icon in the menu bar")
        addSubview(systemBatteryIconButton)

        statusMessage.font = .systemFont(ofSize: 11, weight: .regular)
        statusMessage.textColor = PopoverStyle.secondaryText
        statusMessage.alignment = .right
        statusMessage.isHidden = true
        addSubview(statusMessage)

        settingsButton.image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: "Choose Modules")
        settingsButton.isBordered = false
        settingsButton.contentTintColor = PopoverStyle.secondaryText
        settingsButton.target = self
        settingsButton.action = #selector(showMenu)
        addSubview(settingsButton)

        refreshDisplayOptions()
        displayOptionsObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: NSWorkspace.shared,
            queue: .main
        ) { [weak self] _ in
            self?.refreshDisplayOptions()
        }
        settingsObserver = NotificationCenter.default.addObserver(
            forName: Settings.didChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let change = notification.userInfo?[Settings.changeUserInfoKey]
                    as? Settings.Change,
                  case .liquidGlassAppearance = change else { return }
            self?.refreshDisplayOptions()
        }
        addSubview(hoverFeedback)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        if let displayOptionsObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(displayOptionsObserver)
        }
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
    }

    override func layout() {
        super.layout()
        systemBatteryIconButton.frame = NSRect(x: 0, y: 10, width: 168, height: 20)
        statusMessage.frame = statusMessage.isHidden ? .zero
            : NSRect(x: 168, y: 12, width: bounds.width - 168, height: 15)
        let modeFrame = NSRect(x: 0, y: 36, width: bounds.width - 46,
                               height: ModeSliderView.preferredHeight)
        modeControl.frame = modeFrame
        nativeModeControl.frame = modeFrame
        if Settings.usesLiquidGlass {
            // Each button owns its glass. A single container batches the row
            // without adding an opaque segmented well or another glass layer.
            glassControls?.frame = NSRect(x: 0, y: 36, width: bounds.width, height: 38)
            glassControlsContent.frame = glassControls?.bounds ?? .zero
            glassModeControl?.frame = NSRect(x: 0, y: 0, width: modeFrame.width, height: 38)
            settingsButton.frame = NSRect(x: bounds.width - 38, y: 0, width: 38, height: 38)
            // Optical room is transparent and does not intercept the checkbox.
            interactiveGlassControl?.frame = NSRect(x: -12, y: 24, width: bounds.width + 24, height: 62)
        } else {
            settingsButton.frame = NSRect(x: bounds.width - 22, y: 42, width: 22, height: 20)
        }
        hoverFeedback.frame = bounds
        if subviews.last !== hoverFeedback {
            addSubview(hoverFeedback, positioned: .above, relativeTo: nil)
        }
        updateHoverRegions()
    }

    private func updateHoverRegions() {
        var regions: [FooterHoverFeedbackView.Region] = []
        let available = pendingMode == nil ? enabledModes : []
        if usesInteractiveGlass, let control = interactiveGlassControl {
            let row = control.bounds.insetBy(dx: 12, dy: 12)
            let width = (row.width - 46) / CGFloat(modes.count)
            regions = modes.enumerated().map { index, mode in
                .init(rect: control.convert(NSRect(x: row.minX + CGFloat(index) * width,
                                                  y: row.minY, width: width, height: row.height),
                                            to: hoverFeedback), enabled: available.contains(mode))
            }
            regions.append(.init(rect: control.convert(NSRect(x: row.maxX - 38, y: row.minY,
                                                               width: 38, height: 38),
                                                         to: hoverFeedback), enabled: true))
        } else {
            if let control = glassModeControl, glassControls?.isHidden == false {
                control.layoutSubtreeIfNeeded()
                regions = control.subviews.compactMap { $0 as? NSButton }.map { button in
                    .init(rect: button.convert(button.bounds, to: hoverFeedback),
                          enabled: button.isEnabled)
                }
            } else {
                let control: NSView = usesNativeModeControl ? nativeModeControl : modeControl
                let width = control.bounds.width / CGFloat(modes.count)
                regions = modes.enumerated().map { index, mode in
                    .init(rect: control.convert(NSRect(x: CGFloat(index) * width, y: 0,
                                                       width: width, height: control.bounds.height),
                                                 to: hoverFeedback), enabled: enabledModes.contains(mode))
                }
            }
            regions.append(.init(rect: settingsButton.convert(settingsButton.bounds, to: hoverFeedback),
                                 enabled: settingsButton.isEnabled))
        }
        hoverFeedback.update(regions: regions)
    }

    func update(mode: EnergyMode, helperInstalled: Bool, systemBatteryIconHidden: Bool?,
                tint: NSColor, readStatus: SystemBatteryIconReadStatus = .ready) {
        self.helperInstalled = helperInstalled
        self.systemBatteryIconHidden = systemBatteryIconHidden
        self.systemBatteryIconReadStatus = readStatus
        if let systemBatteryIconHidden {
            systemBatteryIconButton.state = systemBatteryIconHidden ? .on : .off
            systemBatteryIconButton.isEnabled = helperInstalled && readStatus == .ready
                && !systemBatteryIconUpdateInFlight
        } else {
            systemBatteryIconButton.state = .mixed
            systemBatteryIconButton.isEnabled = false
        }
        if !helperInstalled {
            statusMessage.stringValue = "Helper Not Installed"
        } else {
            switch readStatus {
            case .notRequested: statusMessage.stringValue = ""
            case .checking: statusMessage.stringValue = "Reading…"
            case .ready: statusMessage.stringValue = ""
            case .failed: statusMessage.stringValue = "Status Unavailable"
            }
        }
        systemBatteryIconButton.setAccessibilityHelp(
            "Hide the built-in macOS battery icon in the menu bar"
                + (statusMessage.stringValue.isEmpty ? "" : ". " + statusMessage.stringValue)
        )
        let hideStatus = statusMessage.stringValue.isEmpty
        if statusMessage.isHidden != hideStatus {
            statusMessage.isHidden = hideStatus
            needsLayout = true
        }
        // High power is only a real detent on hardware that has it, and none
        // of them are reachable without the helper.
        enabledModes = helperInstalled ? [.auto, .low] : []
        if helperInstalled && EnergyModeController.supportsHighPower { enabledModes.append(.high) }
        currentTint = tint
        // Always retain the newest authoritative observation as the rollback
        // baseline. `pendingMode` only controls the optimistic presentation.
        selected = mode
        synchronizeModeControls()
    }

    private func requestModeSelection(
        _ mode: EnergyMode,
        sourceCompletion: ((EnergyMode?) -> Void)? = nil
    ) {
        guard enabledModes.contains(mode) else {
            sourceCompletion?(nil)
            synchronizeModeControls()
            return
        }

        guard mode != (pendingMode ?? selected) else {
            sourceCompletion?(mode)
            synchronizeModeControls()
            return
        }

        selectionGeneration += 1
        let generation = selectionGeneration
        pendingMode = mode
        synchronizeModeControls()
        guard let onSelect else {
            finishModeSelection(
                generation: generation,
                landedMode: nil,
                sourceCompletion: sourceCompletion
            )
            return
        }
        onSelect(mode) { [weak self] landedMode in
            guard let self else { return }
            let finish: () -> Void = { [weak self] in
                guard let self else { return }
                self.finishModeSelection(
                    generation: generation,
                    landedMode: landedMode,
                    sourceCompletion: sourceCompletion
                )
            }
            if Thread.isMainThread {
                finish()
            } else {
                DispatchQueue.main.async { finish() }
            }
        }
    }

    private func finishModeSelection(
        generation: Int,
        landedMode: EnergyMode?,
        sourceCompletion: ((EnergyMode?) -> Void)?
    ) {
        guard generation == selectionGeneration else {
            sourceCompletion?(pendingMode ?? selected)
            synchronizeModeControls()
            return
        }
        pendingMode = nil
        if let landedMode { selected = landedMode }
        sourceCompletion?(landedMode)
        synchronizeModeControls()
    }

    private func synchronizeModeControls() {
        let displayedMode = pendingMode ?? selected
        if synchronizedModePresentation?.matches(
            selected: displayedMode,
            enabledModes: enabledModes,
            tint: currentTint,
            busy: pendingMode != nil
        ) == true {
            return
        }
        modeControl.updateFromOwner(
            selected: displayedMode,
            enabledModes: enabledModes,
            tint: currentTint
        )
        nativeModeControl.update(selected: displayedMode, enabledModes: enabledModes)
        glassModeControl?.update(selected: displayedMode,
                                 enabledModes: pendingMode == nil ? enabledModes : [])
        if #available(macOS 26.0, *) {
            (interactiveGlassControl as? InteractiveGlassModeControl)?.update(
                selected: displayedMode, enabledModes: pendingMode == nil ? enabledModes : [])
        }
        synchronizedModePresentation = ModeControlPresentation(
            selected: displayedMode,
            enabledModes: enabledModes,
            tint: currentTint,
            busy: pendingMode != nil
        )
        updateHoverRegions()
    }

    private func refreshDisplayOptions() {
        refreshDisplayOptions(reduceMotion: Self.systemReducesMotion)
    }

    private func refreshDisplayOptions(reduceMotion: Bool) {
        let previousControl: NSView = usesInteractiveGlass ? (interactiveGlassControl ?? modeControl)
            : glassControls?.isHidden == false
            ? (glassModeControl ?? modeControl)
            : (usesNativeModeControl ? nativeModeControl : modeControl)
        let transferFocus = window?.firstResponder === previousControl
            || (window?.firstResponder as? NSView)?.isDescendant(of: previousControl) == true
        var restoreMenuFocus = window?.firstResponder === settingsButton
        if #available(macOS 26.0, *) {
            restoreMenuFocus = restoreMenuFocus
                || (interactiveGlassControl as? InteractiveGlassModeControl)?.hasMenuFocus == true
        }
        cancelInteraction()
        let useInteractive = Settings.usesLiquidGlass && !reduceMotion
            && !Self.systemReducesTransparency && !PopoverStyle.isHighContrast(effectiveAppearance)
        if #available(macOS 26.0, *), Settings.usesLiquidGlass {
            if glassControls == nil {
                let container = NSGlassEffectContainerView(frame: .zero)
                container.spacing = 0
                container.contentView = glassControlsContent
                addSubview(container)
                glassControls = container

                let control = NativeGlassModeControl(modes: modes)
                control.onSelect = { [weak self] mode in self?.requestModeSelection(mode) }
                control.update(selected: pendingMode ?? selected,
                               enabledModes: pendingMode == nil ? enabledModes : [])
                glassControlsContent.addSubview(control)
                glassModeControl = control
            }
            if settingsButton.superview !== glassControlsContent {
                glassControlsContent.addSubview(settingsButton)
            }
            if useInteractive, interactiveGlassControl == nil {
                let control = InteractiveGlassModeControl(modes: modes)
                control.onSelect = { [weak self] mode in self?.requestModeSelection(mode) }
                control.onShowMenu = { [weak self] anchor in self?.onShowMenu?(anchor) }
                control.update(selected: pendingMode ?? selected,
                               enabledModes: pendingMode == nil ? enabledModes : [])
                addSubview(control)
                interactiveGlassControl = control
            }
            glassControls?.isHidden = useInteractive
            settingsButton.bezelStyle = .glass
            settingsButton.borderShape = .circle
            settingsButton.isBordered = true
            settingsButton.contentTintColor = nil
        } else {
            if settingsButton.superview !== self {
                addSubview(settingsButton)
            }
            glassControls?.isHidden = true
            if #available(macOS 26.0, *) {
                settingsButton.borderShape = .automatic
            }
            settingsButton.bezelStyle = .rounded
            settingsButton.isBordered = false
            settingsButton.contentTintColor = PopoverStyle.secondaryText
        }
        interactiveGlassControl?.isHidden = !useInteractive
        usesInteractiveGlass = useInteractive
        needsLayout = true

        let useGlassControl = Settings.usesLiquidGlass
        let useNativeControl = reduceMotion && !useGlassControl
        let nextControl: NSView = useInteractive ? (interactiveGlassControl ?? modeControl)
            : useGlassControl
            ? (glassModeControl ?? modeControl)
            : (useNativeControl ? nativeModeControl : modeControl)
        usesNativeModeControl = useNativeControl
        modeControl.isHidden = useNativeControl || useGlassControl
        nativeModeControl.isHidden = !useNativeControl
        if transferFocus, previousControl !== nextControl {
            let focusView = useInteractive ? nextControl
                : useGlassControl ? (glassModeControl?.keyboardFocusView ?? nextControl) : nextControl
            window?.makeFirstResponder(focusView)
        }
        if restoreMenuFocus {
            if #available(macOS 26.0, *), useInteractive {
                (interactiveGlassControl as? InteractiveGlassModeControl)?.requestMenuFocus()
            } else {
                window?.makeFirstResponder(settingsButton)
            }
        }
    }

    func setHoverPresentationActive(_ active: Bool) {
        hoverFeedback.setPresentationActive(active)
    }

    func cancelInteraction() {
        hoverFeedback.cancelHover()
        if #available(macOS 26.0, *) {
            (interactiveGlassControl as? InteractiveGlassModeControl)?.cancelInteraction()
        }
    }

    func cancelActiveModeDrag() -> Bool {
        if #available(macOS 26.0, *) {
            return (interactiveGlassControl as? InteractiveGlassModeControl)?.cancelDragIfActive() ?? false
        }
        return false
    }

    @objc private func systemBatteryIconChanged(_ sender: NSButton) {
        guard let currentHidden = systemBatteryIconHidden else {
            sender.state = .mixed
            return
        }
        // Mixed state is display-only; invert the authoritative value, as Settings does.
        let requested = !currentHidden
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
            // The owner has already supplied the current authoritative value.
            // An older completion must not overwrite a newer shared read.
            sender.state = self.systemBatteryIconHidden.map { $0 ? .on : .off } ?? .mixed
            sender.isEnabled = self.helperInstalled && self.systemBatteryIconHidden != nil
                && self.systemBatteryIconReadStatus == .ready
            if !succeeded { NSSound.beep() }
        }
    }

    @objc private func showMenu() { onShowMenu?(settingsButton) }

#if DEBUG
    func applyReduceMotionChangeForTest(_ reduceMotion: Bool) {
        refreshDisplayOptions(reduceMotion: reduceMotion)
    }
#endif
}

private final class PopoverSurfaceView: NSView {
    var appearanceDidChange: (() -> Void)?
    weak var initialFocusView: NSView?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Mouse opening must not focus a footer button and scroll away from
        // the heading. Tab can then enter the controls through AppKit's loop.
        window?.initialFirstResponder = initialFocusView
        appearanceDidChange?()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        appearanceDidChange?()
    }
}

private final class PopoverDocumentView: NSView {
    override var isFlipped: Bool { true }
}

private final class PopoverScrollView: NSScrollView {
    override func tile() {
        super.tile()
        // AppKit may select a legacy scroller when the window attaches or the
        // system preference changes. Give its gutter space without clipping
        // or scaling the fixed-width instruments.
        if let documentView, contentSize.width > 0,
           documentView.frame.width != contentSize.width {
            documentView.setFrameSize(NSSize(width: contentSize.width,
                                             height: documentView.frame.height))
        }
    }
}

final class PopoverContentViewController: NSViewController {
    private let stack = NSStackView()
    private let scrollView = PopoverScrollView()
    private let documentView = PopoverDocumentView()
    private let header = PopoverHeaderView()
    private let runtimeView = PopoverRuntimeView()
    private let flowView = PowerFlowView()
    private let ringView = RingGaugeView()
    private let laneView = LaneView()
    private let historyView = HistoryView()
    private let topProcessesView = TopProcessesView()
    private var topProcessesHeight: NSLayoutConstraint?
    private var latestTopProcesses: TopProcessesState = .loading
    private let footer = PopoverFooterView()

    private var moduleVisibility: [PopoverModule: Bool] = [:]
    private var presentationActive = false
    private var animationsEnabled = false
    private var latestSnapshot = PowerSnapshot()
    private var latestDegraded = false
    private var latestHistory: [Double] = []
    private var latestPeak: Double = 0
    private var latestHistoryTiming: HistoryChartTiming?
    private var systemBatteryIconHidden: Bool?
    private var systemBatteryIconReadStatus: SystemBatteryIconReadStatus = .notRequested
    private var modeSelectHandler: ((EnergyMode, @escaping (EnergyMode?) -> Void) -> Void)?
    private var systemBatteryIconToggleHandler:
        ((Bool, @escaping (Bool) -> Void) -> Void)?
    private var settingsHandler: (() -> Void)?
    private var settingsObserver: NSObjectProtocol?
    private var displayOptionsObserver: NSObjectProtocol?
#if DEBUG
    private(set) var moduleUpdateCountsForTest: [PopoverModule: Int] = [:]
    private(set) var footerUpdateCountForTest = 0
#endif
    var heightDidChange: ((CGFloat) -> Void)?
    var forceQuitProcessHandler: ((EnergyProcess) -> Void)? {
        didSet { topProcessesView.forceQuitHandler = forceQuitProcessHandler }
    }

    deinit {
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
        if let displayOptionsObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(displayOptionsObserver)
        }
    }

    override func loadView() {
        let root = PopoverSurfaceView(frame: NSRect(x: 0, y: 0, width: PopoverStyle.width, height: 1))
        root.initialFocusView = scrollView
        root.wantsLayer = true
        // NSPopover supplies the native adaptive material. An extra effect
        // view here would cover its system glass on newer macOS versions.
        view = root
        buildContent()
        root.appearanceDidChange = { [weak self] in self?.refreshAppearance() }
        displayOptionsObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: NSWorkspace.shared, queue: .main
        ) { [weak self] _ in self?.refreshAppearance() }
        refreshAppearance()
    }

    func setViewportHeight(_ height: CGFloat) {
        _ = view
        view.setFrameSize(NSSize(width: PopoverStyle.width, height: height))
        documentView.setFrameSize(NSSize(width: PopoverStyle.width, height: preferredHeight))
        scrollView.hasVerticalScroller = height < preferredHeight
        view.layoutSubtreeIfNeeded()
        scrollView.tile()
        // Clamp the old scroll offset when hiding modules or moving to a taller
        // display; do not reset it on the 1 Hz telemetry update.
        let offset = min(scrollView.contentView.bounds.minY, max(preferredHeight - height, 0))
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: max(offset, 0)))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func refreshAppearance() {
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            var reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
#if DEBUG
            if let value = ProcessInfo.processInfo.environment["WATTSON_FORCE_REDUCE_TRANSPARENCY"] {
                reduceTransparency = value == "1"
            }
#endif
            // Glass hosts supply a rounded opaque backing for accessibility.
            // Keep their foreground clear; Classic retains its own fallback.
            let needsOpaqueForeground = reduceTransparency && !(view.window is GlassPopoverPanel)
            view.layer?.backgroundColor = needsOpaqueForeground ? PopoverStyle.surface.cgColor : nil
            for section in [header, runtimeView, flowView, ringView, laneView, historyView, topProcessesView, footer] {
                section.refreshAppearance()
            }
            update(snapshot: latestSnapshot, history: latestHistory,
                   peak: latestPeak, degraded: latestDegraded, historyTiming: latestHistoryTiming)
        }
    }

    var preferredHeight: CGFloat {
        var total = PopoverHeaderView.preferredHeight + PopoverFooterView.preferredHeight
        if isVisible(.runtime) { total += PopoverRuntimeView.preferredHeight }
        if isVisible(.flow) { total += PowerFlowView.preferredHeight }
        if isVisible(.ring) { total += RingGaugeView.preferredHeight }
        if isVisible(.lanes) { total += LaneView.preferredHeight }
        if isVisible(.history) { total += HistoryView.preferredHeight }
        if isVisible(.topProcesses) {
            total += TopProcessesView.preferredHeight(count: Settings.topProcessCount, compact: Settings.topProcessesCompact)
        }
        return total + 24
    }

    func updateTopProcesses(_ state: TopProcessesState) {
        guard latestTopProcesses != state else { return }
        latestTopProcesses = state
        guard isVisible(.topProcesses) else { return }
        updateModule(.topProcesses)
    }

    func update(snapshot: PowerSnapshot, history: [Double], peak: Double, degraded: Bool,
                historyTiming: HistoryChartTiming? = nil) {
        latestSnapshot = snapshot
        latestHistory = history
        latestHistoryTiming = historyTiming
        latestPeak = peak
        let degradationChanged = latestDegraded != degraded
        latestDegraded = degraded
        if degradationChanged { setAnimationsEnabled(animationsEnabled) }

        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            header.update(snapshot: snapshot, degraded: degraded)
            for module in PopoverModule.allCases where isVisible(module) {
                updateModule(module)
            }
            updateFooter()
        }
    }

    private func updateModule(_ module: PopoverModule) {
#if DEBUG
        moduleUpdateCountsForTest[module, default: 0] += 1
#endif
        switch module {
        case .runtime:
            runtimeView.update(snapshot: latestSnapshot, degraded: latestDegraded)
        case .flow:
            flowView.update(snapshot: latestSnapshot, animated: animationsEnabled && !latestDegraded)
        case .ring:
            ringView.update(snapshot: latestSnapshot, degraded: latestDegraded)
        case .lanes:
            laneView.update(snapshot: latestSnapshot)
        case .history:
            updateHistory()
        case .topProcesses:
            let color = latestSnapshot.state == .mixedSupply
                ? PopoverStyle.blue : PopoverStyle.stateColor(latestSnapshot.state)
            topProcessesView.update(state: latestTopProcesses, count: Settings.topProcessCount,
                                    compact: Settings.topProcessesCompact, color: color)
        }
    }

    private func updateHistory() {
        let snapshot = latestSnapshot
        let historyColor = snapshot.state == .mixedSupply
            ? PopoverStyle.blue
            : PopoverStyle.stateColor(snapshot.state)
        historyView.update(samples: latestHistory, peak: latestPeak,
                           color: historyColor, timing: latestHistoryTiming)
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

    func updateSystemBatteryIconState(
        _ hidden: Bool?, readStatus: SystemBatteryIconReadStatus = .ready
    ) {
        systemBatteryIconHidden = hidden
        systemBatteryIconReadStatus = readStatus
        updateFooter()
    }

    func refreshEnergyModeState() {
        updateFooter()
    }

    func setAnimationsEnabled(_ enabled: Bool) {
        animationsEnabled = enabled
        // Keep the requested policy so a fresh reading can resume motion, but
        // never animate stale telemetry as if it were a live power flow.
        let allowsMotion = enabled && !latestDegraded
        flowView.setAnimationsEnabled(allowsMotion && !flowView.isHidden)
        ringView.setAnimationsEnabled(allowsMotion && !ringView.isHidden)
        laneView.setAnimationsEnabled(allowsMotion && !laneView.isHidden)
        historyView.setAnimationsEnabled(allowsMotion && !historyView.isHidden)
        if !allowsMotion, let root = view.layer {
            removeAnimationsRecursively(from: root)
        }
        // A red source indicator reports failure; it is not stale power-flow
        // telemetry. Keep it breathing while the other degraded modules stop.
        runtimeView.setAnimationsEnabled(enabled && !runtimeView.isHidden)
    }

    func setPresentationActive(_ active: Bool) {
        presentationActive = active
        runtimeView.setPresentationActive(active && isVisible(.runtime))
        footer.setHoverPresentationActive(active)
        historyView.setPresentationActive(active)
        topProcessesView.setPresentationActive(active && isVisible(.topProcesses))
        if !active { footer.cancelInteraction() }
    }

    func cancelActiveModeDrag() -> Bool { footer.cancelActiveModeDrag() }

    var processActivityHelpWindow: NSWindow? { topProcessesView.helpWindow }

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
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.contentView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true
        scrollView.hasHorizontalScroller = false
        scrollView.documentView = documentView
        // tile() tracks the actual clip width. Autoresizing from the initial
        // zero-sized clip would instead add the viewport width twice.
        documentView.addSubview(stack)
        view.addSubview(scrollView)

        stack.addArrangedSubview(header)
        for module in Settings.moduleOrder {
            stack.addArrangedSubview(moduleView(for: module))
        }
        stack.addArrangedSubview(footer)

        let processesHeight = topProcessesView.heightAnchor.constraint(
            equalToConstant: TopProcessesView.preferredHeight(count: Settings.topProcessCount, compact: Settings.topProcessesCompact)
        )
        topProcessesHeight = processesHeight

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.widthAnchor.constraint(equalToConstant: PopoverStyle.contentWidth),
            stack.centerXAnchor.constraint(equalTo: documentView.centerXAnchor),
            stack.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 12),
            header.heightAnchor.constraint(equalToConstant: PopoverHeaderView.preferredHeight),
            runtimeView.heightAnchor.constraint(equalToConstant: PopoverRuntimeView.preferredHeight),
            flowView.heightAnchor.constraint(equalToConstant: PowerFlowView.preferredHeight),
            ringView.heightAnchor.constraint(equalToConstant: RingGaugeView.preferredHeight),
            laneView.heightAnchor.constraint(equalToConstant: LaneView.preferredHeight),
            historyView.heightAnchor.constraint(equalToConstant: HistoryView.preferredHeight),
            processesHeight,
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
            tint: PopoverStyle.stateColor(latestSnapshot.state),
            readStatus: systemBatteryIconReadStatus
        )
    }

    private func observeSettingsChanges() {
        settingsObserver = NotificationCenter.default.addObserver(
            forName: Settings.didChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let change = notification.userInfo?[Settings.changeUserInfoKey]
                    as? Settings.Change else { return }
            switch change {
            case .module:
                self?.reloadModuleVisibility()
                self?.applyModuleVisibility()
            case .moduleOrder:
                self?.applyModuleOrder()
            case .ringMetrics:
                guard let self else { return }
                self.ringView.reloadMetrics()
                self.updateModule(.ring)
            case .processWhitelist:
                self?.updateModule(.topProcesses)
            case .topProcessCount, .topProcessesCompact:
                guard let self else { return }
                self.topProcessesHeight?.constant = TopProcessesView.preferredHeight(
                    count: Settings.topProcessCount, compact: Settings.topProcessesCompact
                )
                self.updateModule(.topProcesses)
                self.heightDidChange?(self.preferredHeight)
            default:
                break
            }
        }
    }

    private func moduleView(for module: PopoverModule) -> NSView {
        switch module {
        case .runtime: return runtimeView
        case .flow: return flowView
        case .ring: return ringView
        case .lanes: return laneView
        case .history: return historyView
        case .topProcesses: return topProcessesView
        }
    }

    private func applyModuleOrder() {
        let offset = scrollView.contentView.bounds.origin
        for (index, module) in Settings.moduleOrder.enumerated() {
            let section = moduleView(for: module)
            if stack.arrangedSubviews[index + 1] !== section {
                // AppKit moves an existing arranged view without removing it
                // from the hierarchy. History retains its window and motion.
                stack.insertArrangedSubview(section, at: index + 1)
            }
        }
        view.layoutSubtreeIfNeeded()
        scrollView.contentView.scroll(to: offset)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func reloadModuleVisibility() {
        for module in PopoverModule.allCases {
            moduleVisibility[module] = Settings.isModuleVisible(module)
        }
    }

    private func applyModuleVisibility() {
        let views: [(PopoverModule, NSView)] = [
            (.runtime, runtimeView),
            (.flow, flowView), (.ring, ringView),
            (.lanes, laneView), (.history, historyView),
            (.topProcesses, topProcessesView),
        ]
        for (module, moduleView) in views {
            let wasHidden = moduleView.isHidden
            moduleView.isHidden = !isVisible(module)
            if presentationActive && wasHidden && !moduleView.isHidden {
                updateModule(module)
            }
        }
        topProcessesView.setPresentationActive(presentationActive && isVisible(.topProcesses))
        runtimeView.setPresentationActive(presentationActive && isVisible(.runtime))
        if animationsEnabled { setAnimationsEnabled(true) }
        heightDidChange?(preferredHeight)
    }

    private func makeModuleMenuItems() -> [NSMenuItem] {
        Settings.moduleOrder.map { module in
            let item = NSMenuItem(title: module.title, action: #selector(toggleModule(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = module.rawValue
            item.state = isVisible(module) ? .on : .off
            return item
        }
    }

    private func showModuleMenu(_ sender: NSView) {
        let menu = NSMenu(title: "Modules")
        makeModuleMenuItems().forEach(menu.addItem)

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
        moduleView(for: module).isHidden
    }

    func moduleViewForTest(_ module: PopoverModule) -> NSView { moduleView(for: module) }

    var moduleOrderForTest: [PopoverModule] {
        stack.arrangedSubviews.compactMap { section in
            PopoverModule.allCases.first { moduleView(for: $0) === section }
        }
    }

    var moduleMenuItemsForTest: [NSMenuItem] { makeModuleMenuItems() }

    var latestHistoryForTest: [Double] { latestHistory }

    var runtimePresentationForTest: String {
        runtimeView.presentationForTest
    }

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
