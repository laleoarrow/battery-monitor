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
    let increaseContrast: () -> Bool
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
        increaseContrast: {
            NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        },
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

private enum SettingsStyle {
    static let contentSize = NSSize(width: 792, height: 794)
    static let minimumContentScale: CGFloat = 0.60
    static let sidebarWidth: CGFloat = 232
    static let contentHorizontalInset: CGFloat = 25
    static let contentTopInset: CGFloat = 78
    static let contentBottomInset: CGFloat = 24

    static let trafficLightSafeHeight: CGFloat = 54
    static let identityHeight: CGFloat = 96
    static let identityTileSize: CGFloat = 54
    static let navigationInset: CGFloat = 16
    static let navigationTopGap: CGFloat = -6
    static let navigationRowHeight: CGFloat = 56
    static let navigationRowGap: CGFloat = 4
    static let navigationHeight: CGFloat = 130

    static let headingFont = NSFont.systemFont(ofSize: 31, weight: .semibold)
    static let primaryFont = NSFont.systemFont(ofSize: 19, weight: .regular)
    static let detailFont = NSFont.systemFont(ofSize: 16, weight: .regular)
    static let sidebarFont = NSFont.systemFont(ofSize: 17, weight: .medium)

    static let toggleSize = NSSize(width: 56, height: 32)
    static let generalListHeight: CGFloat = 400
    static let generalRowHeight: CGFloat = 100
    static let generalIconTileSize: CGFloat = 50
    static let moduleCardHeight: CGFloat = 259
    static let moduleCardWidth: CGFloat = 246.5
    static let moduleCardGap: CGFloat = 16
    static let surfaceCornerRadius: CGFloat = 13
    static let modulePreviewSize = NSSize(width: 112, height: 108)

    static let contentBackground = color(hex: 0x151618)
    static let sidebarBackground = color(hex: 0x1E1F21)
    static let surfaceBackground = color(hex: 0x191A1C)
    static let tileBackground = color(hex: 0x202124)
    static let previewBackground = color(hex: 0x1A1B1C)
    static let selection = color(hex: 0x2B362F)
    static let green = color(hex: 0x68C367)
    static let border = color(hex: 0x363838)
    static let divider = color(hex: 0x363838)
    static let toggleOff = color(hex: 0x2E3032)
    static let increasedContrastSelection = color(hex: 0x3B5944)
    static let increasedContrastSelectionBorder = color(hex: 0x8AD88E)
    static let increasedContrastBorder = color(hex: 0x8D949A)
    static let increasedContrastToggleOff = color(hex: 0x575B5F)
    static let increasedContrastToggleBorder = color(hex: 0xB9C0C6)
    static let headingText = color(hex: 0xF4F4F4)
    static let primaryText = color(hex: 0xE9E9E9)
    static let secondaryText = color(hex: 0xA0A0A2)

    private static func color(hex: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: alpha
        )
    }
}

private final class SettingsFillView: NSView {
    private let fillColor: NSColor

    init(color: NSColor) {
        fillColor = color
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = fillColor.cgColor
    }
}

private final class ReferenceTrafficLightButton: NSButton {
    enum Kind {
        case close
        case minimize
        case zoom

        var activeColor: NSColor {
            switch self {
            case .close: return NSColor(srgbRed: 235 / 255, green: 99 / 255, blue: 86 / 255, alpha: 1)
            case .minimize: return NSColor(srgbRed: 246 / 255, green: 199 / 255, blue: 69 / 255, alpha: 1)
            case .zoom: return NSColor(srgbRed: 89 / 255, green: 195 / 255, blue: 87 / 255, alpha: 1)
            }
        }

        var accessibilityLabel: String {
            switch self {
            case .close: return "Close"
            case .minimize: return "Minimize"
            case .zoom: return "Zoom"
            }
        }
    }

    private let kind: Kind
    private weak var nativeButton: NSButton?
    private var isHovered = false
    private var windowObservers: [NSObjectProtocol] = []

    init(kind: Kind, nativeButton: NSButton) {
        self.kind = kind
        self.nativeButton = nativeButton
        super.init(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
        title = ""
        isBordered = false
        setButtonType(.momentaryPushIn)
        focusRingType = .none
        target = self
        action = #selector(forwardNativeAction)
        setAccessibilityLabel(kind.accessibilityLabel)
        setAccessibilityHelp("\(kind.accessibilityLabel) the Wattson Settings window.")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    deinit {
        windowObservers.forEach(NotificationCenter.default.removeObserver)
    }

    override var intrinsicContentSize: NSSize { NSSize(width: 20, height: 20) }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        windowObservers.forEach(NotificationCenter.default.removeObserver)
        windowObservers.removeAll()
        guard let window else { return }
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            windowObservers.append(NotificationCenter.default.addObserver(
                forName: name,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.needsDisplay = true
            })
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let active = window?.isKeyWindow == true || window?.isMainWindow == true
        let base = active
            ? kind.activeColor
            : NSColor(srgbRed: 112 / 255, green: 112 / 255, blue: 114 / 255, alpha: 1)
        let fill = isHighlighted ? base.blended(withFraction: 0.20, of: .black) ?? base : base
        fill.setFill()
        let circle = NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5))
        circle.fill()
        NSColor.black.withAlphaComponent(active ? 0.22 : 0.14).setStroke()
        circle.lineWidth = 0.75
        circle.stroke()

        guard isHovered else { return }
        NSColor.black.withAlphaComponent(0.56).setStroke()
        let symbol = NSBezierPath()
        let width = bounds.width
        let height = bounds.height
        switch kind {
        case .close:
            symbol.move(to: NSPoint(x: width * 0.325, y: height * 0.325))
            symbol.line(to: NSPoint(x: width * 0.675, y: height * 0.675))
            symbol.move(to: NSPoint(x: width * 0.675, y: height * 0.325))
            symbol.line(to: NSPoint(x: width * 0.325, y: height * 0.675))
        case .minimize:
            symbol.move(to: NSPoint(x: width * 0.30, y: height * 0.50))
            symbol.line(to: NSPoint(x: width * 0.70, y: height * 0.50))
        case .zoom:
            symbol.move(to: NSPoint(x: width * 0.30, y: height * 0.50))
            symbol.line(to: NSPoint(x: width * 0.70, y: height * 0.50))
            symbol.move(to: NSPoint(x: width * 0.50, y: height * 0.30))
            symbol.line(to: NSPoint(x: width * 0.50, y: height * 0.70))
        }
        symbol.lineWidth = 1.2 * min(width, height) / 20
        symbol.lineCapStyle = .round
        symbol.stroke()
    }

    @objc private func forwardNativeAction() {
        nativeButton?.performClick(self)
    }
}

private protocol SettingsContrastRefreshing: AnyObject {
    func refreshContrastAppearance()
}

private final class SettingsAdaptiveBorderBox: NSBox, SettingsContrastRefreshing {
    private let increaseContrast: () -> Bool

    init(increaseContrast: @escaping () -> Bool) {
        self.increaseContrast = increaseContrast
        super.init(frame: .zero)
        refreshContrastAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    func refreshContrastAppearance() {
        borderWidth = increaseContrast() ? 2 : 1
        borderColor = increaseContrast()
            ? SettingsStyle.increasedContrastBorder
            : SettingsStyle.border
        needsDisplay = true
    }
}

private final class SettingsToggleButton: NSButton, SettingsContrastRefreshing {
    private let increaseContrast: () -> Bool

    init(
        accessibilityLabel: String,
        increaseContrast: @escaping () -> Bool,
        target: AnyObject? = nil,
        action: Selector? = nil
    ) {
        self.increaseContrast = increaseContrast
        super.init(frame: NSRect(origin: .zero, size: SettingsStyle.toggleSize))
        title = ""
        isBordered = false
        bezelStyle = .regularSquare
        setButtonType(.pushOnPushOff)
        imagePosition = .noImage
        focusRingType = .none
        self.target = target
        self.action = action
        setAccessibilityLabel(accessibilityLabel)
        setAccessibilityRole(.checkBox)
        translatesAutoresizingMaskIntoConstraints = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override var intrinsicContentSize: NSSize { SettingsStyle.toggleSize }

    var trackColor: NSColor {
        guard state != .on else { return SettingsStyle.green }
        return increaseContrast()
            ? SettingsStyle.increasedContrastToggleOff
            : SettingsStyle.toggleOff
    }

    var trackStrokeColor: NSColor {
        guard state != .on, increaseContrast() else { return SettingsStyle.border }
        return SettingsStyle.increasedContrastToggleBorder
    }

    var trackStrokeWidth: CGFloat {
        state != .on && increaseContrast() ? 2 : 1
    }

    func refreshContrastAppearance() {
        needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let trackRect = bounds.insetBy(dx: 1, dy: 1)
        let track = NSBezierPath(
            roundedRect: trackRect,
            xRadius: trackRect.height / 2,
            yRadius: trackRect.height / 2
        )
        let opacity: CGFloat = isEnabled ? 1 : 0.48
        trackColor.withAlphaComponent(opacity).setFill()
        track.fill()

        trackStrokeColor.withAlphaComponent(opacity).setStroke()
        track.lineWidth = trackStrokeWidth
        track.stroke()

        let knobSide = trackRect.height - 4
        let knobX: CGFloat
        switch state {
        case .on:
            knobX = trackRect.maxX - knobSide - 2
        case .mixed:
            knobX = trackRect.midX - knobSide / 2
        default:
            knobX = trackRect.minX + 2
        }
        let knobRect = NSRect(
            x: knobX,
            y: trackRect.midY - knobSide / 2,
            width: knobSide,
            height: knobSide
        )
        NSColor.white.withAlphaComponent(0.98 * opacity).setFill()
        NSBezierPath(ovalIn: knobRect).fill()

        NSColor.black.withAlphaComponent(0.22 * opacity).setStroke()
        let knobBorder = NSBezierPath(ovalIn: knobRect.insetBy(dx: 0.5, dy: 0.5))
        knobBorder.lineWidth = 0.75
        knobBorder.stroke()

        if window?.firstResponder === self {
            NSColor.keyboardFocusIndicatorColor.withAlphaComponent(0.85).setStroke()
            let focus = NSBezierPath(
                roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                xRadius: bounds.height / 2,
                yRadius: bounds.height / 2
            )
            focus.lineWidth = 2
            focus.stroke()
        }
    }
}

private final class SettingsSidebarRowView: NSTableRowView, SettingsContrastRefreshing {
    private let increaseContrast: () -> Bool

    init(increaseContrast: @escaping () -> Bool) {
        self.increaseContrast = increaseContrast
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    var selectionFillColor: NSColor {
        increaseContrast()
            ? SettingsStyle.increasedContrastSelection
            : SettingsStyle.selection
    }

    var selectionStrokeColor: NSColor? {
        increaseContrast() ? SettingsStyle.increasedContrastSelectionBorder : nil
    }

    var selectionStrokeWidth: CGFloat { increaseContrast() ? 2 : 0 }

    override var isSelected: Bool {
        didSet { needsDisplay = true }
    }

    func refreshContrastAppearance() {
        needsDisplay = true
    }

    override func drawBackground(in dirtyRect: NSRect) {
        super.drawBackground(in: dirtyRect)
        guard isSelected else { return }
        selectionFillColor.setFill()
        let selection = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 0, dy: 3),
            xRadius: 9,
            yRadius: 9
        )
        selection.fill()

        guard let selectionStrokeColor else { return }
        selectionStrokeColor.setStroke()
        let outline = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 1, dy: 4),
            xRadius: 8,
            yRadius: 8
        )
        outline.lineWidth = selectionStrokeWidth
        outline.stroke()
    }

    override func drawSelection(in dirtyRect: NSRect) {}
}

private final class DynamicSeparatorView: NSView, SettingsContrastRefreshing {
    private let increaseContrast: () -> Bool
    private let increasedContrastStroke = CALayer()

    init(increaseContrast: @escaping () -> Bool) {
        self.increaseContrast = increaseContrast
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.addSublayer(increasedContrastStroke)
        refreshContrastAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    var strokeColor: NSColor {
        increaseContrast() ? SettingsStyle.increasedContrastBorder : SettingsStyle.divider
    }

    var visualStrokeWidth: CGFloat { increaseContrast() ? 2 : 1 }
    var renderedStrokeWidth: CGFloat {
        increaseContrast() ? increasedContrastStroke.frame.width : bounds.width
    }

    override var wantsUpdateLayer: Bool { true }

    override func layout() {
        super.layout()
        updateStrokeLayers()
    }

    override func updateLayer() {
        updateStrokeLayers()
    }

    func refreshContrastAppearance() {
        updateStrokeLayers()
        needsLayout = true
        needsDisplay = true
    }

    private func updateStrokeLayers() {
        let increased = increaseContrast()
        layer?.masksToBounds = false
        layer?.backgroundColor = increased ? NSColor.clear.cgColor : SettingsStyle.divider.cgColor
        increasedContrastStroke.isHidden = !increased
        increasedContrastStroke.backgroundColor = strokeColor.cgColor
        increasedContrastStroke.frame = NSRect(
            x: (bounds.width - visualStrokeWidth) / 2,
            y: 0,
            width: visualStrokeWidth,
            height: bounds.height
        )
    }
}

private final class ECGIconView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 2, dy: 3)
        let points = [
            NSPoint(x: rect.minX, y: rect.midY),
            NSPoint(x: rect.minX + rect.width * 0.27, y: rect.midY),
            NSPoint(x: rect.minX + rect.width * 0.36, y: rect.midY + 5),
            NSPoint(x: rect.minX + rect.width * 0.46, y: rect.midY - 8),
            NSPoint(x: rect.minX + rect.width * 0.58, y: rect.maxY),
            NSPoint(x: rect.minX + rect.width * 0.70, y: rect.minY),
            NSPoint(x: rect.minX + rect.width * 0.82, y: rect.midY),
            NSPoint(x: rect.maxX, y: rect.midY),
        ]
        let path = NSBezierPath()
        path.move(to: points[0])
        points.dropFirst().forEach(path.line)
        SettingsStyle.green.setStroke()
        path.lineWidth = 3.4
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }
}

private final class PuzzleNavigationIconView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 4, y: 23))
        path.line(to: NSPoint(x: 10, y: 23))
        path.line(to: NSPoint(x: 10, y: 25))
        path.curve(
            to: NSPoint(x: 18, y: 25),
            controlPoint1: NSPoint(x: 10, y: 29),
            controlPoint2: NSPoint(x: 18, y: 29)
        )
        path.line(to: NSPoint(x: 18, y: 23))
        path.line(to: NSPoint(x: 24, y: 23))
        path.line(to: NSPoint(x: 24, y: 17))
        path.line(to: NSPoint(x: 26, y: 17))
        path.curve(
            to: NSPoint(x: 26, y: 11),
            controlPoint1: NSPoint(x: 30, y: 17),
            controlPoint2: NSPoint(x: 30, y: 11)
        )
        path.line(to: NSPoint(x: 24, y: 11))
        path.line(to: NSPoint(x: 24, y: 5))
        path.line(to: NSPoint(x: 18, y: 5))
        path.line(to: NSPoint(x: 18, y: 8))
        path.curve(
            to: NSPoint(x: 10, y: 8),
            controlPoint1: NSPoint(x: 18, y: 12),
            controlPoint2: NSPoint(x: 10, y: 12)
        )
        path.line(to: NSPoint(x: 10, y: 5))
        path.line(to: NSPoint(x: 4, y: 5))
        path.line(to: NSPoint(x: 4, y: 11))
        path.line(to: NSPoint(x: 7, y: 11))
        path.curve(
            to: NSPoint(x: 7, y: 17),
            controlPoint1: NSPoint(x: 11, y: 11),
            controlPoint2: NSPoint(x: 11, y: 17)
        )
        path.line(to: NSPoint(x: 4, y: 17))
        path.close()
        SettingsStyle.primaryText.setStroke()
        path.lineWidth = 2.4
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
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
        let backdropRect = bounds.insetBy(dx: 1, dy: 1)
        SettingsStyle.previewBackground.setFill()
        NSBezierPath(
            roundedRect: backdropRect,
            xRadius: 12,
            yRadius: 12
        ).fill()

        let drawingRect = bounds.insetBy(dx: 14, dy: 13)
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
        let left = NSRect(x: rect.minX, y: rect.midY + 8, width: 28, height: 18)
        let right = NSRect(x: rect.maxX - 10, y: rect.minY + 4, width: 22, height: 22)
        NSColor.tertiaryLabelColor.setStroke()
        let leftBox = NSBezierPath(roundedRect: left, xRadius: 2, yRadius: 2)
        leftBox.lineWidth = 2
        leftBox.stroke()
        let batteryCap = NSBezierPath()
        batteryCap.move(to: NSPoint(x: left.maxX + 1, y: left.midY - 4))
        batteryCap.line(to: NSPoint(x: left.maxX + 1, y: left.midY + 4))
        batteryCap.lineWidth = 2
        batteryCap.stroke()
        let rightCircle = NSBezierPath(ovalIn: right)
        rightCircle.lineWidth = 2
        rightCircle.stroke()

        let returnPath = NSBezierPath()
        returnPath.move(to: NSPoint(x: left.maxX + 4, y: left.maxY - 2))
        returnPath.line(to: NSPoint(x: right.midX - 4, y: left.maxY - 2))
        returnPath.curve(
            to: NSPoint(x: right.midX, y: right.midY + 3),
            controlPoint1: NSPoint(x: right.midX, y: left.maxY - 2),
            controlPoint2: NSPoint(x: right.midX, y: right.midY + 8)
        )
        var returnDash: [CGFloat] = [4, 5]
        returnPath.setLineDash(&returnDash, count: returnDash.count, phase: 0)
        returnPath.lineWidth = 2
        returnPath.stroke()

        let path = NSBezierPath()
        path.move(to: NSPoint(x: left.maxX, y: left.midY))
        path.curve(
            to: NSPoint(x: right.minX, y: right.midY),
            controlPoint1: NSPoint(x: rect.midX - 2, y: left.midY),
            controlPoint2: NSPoint(x: rect.midX - 1, y: right.midY)
        )
        SettingsStyle.green.setStroke()
        path.lineWidth = 3
        path.lineCapStyle = .round
        path.stroke()
    }

    private func drawRing(in rect: NSRect) {
        let side = min(rect.width, rect.height)
        let ringRect = NSRect(
            x: rect.midX - 10 - side / 2,
            y: rect.midY - side / 2,
            width: side,
            height: side
        ).insetBy(dx: 1, dy: 1)
        NSColor.tertiaryLabelColor.withAlphaComponent(0.45).setStroke()
        let base = NSBezierPath(ovalIn: ringRect)
        base.lineWidth = 7
        base.stroke()

        let arc = NSBezierPath()
        arc.appendArc(
            withCenter: NSPoint(x: ringRect.midX, y: ringRect.midY),
            radius: ringRect.width / 2,
            startAngle: -135,
            endAngle: 75
        )
        SettingsStyle.green.setStroke()
        arc.lineWidth = 7
        arc.lineCapStyle = .round
        arc.stroke()

        let bolt = NSBezierPath()
        let boltCenterX = rect.midX - 10
        bolt.move(to: NSPoint(x: boltCenterX + 2, y: rect.midY + 15))
        bolt.line(to: NSPoint(x: boltCenterX - 8, y: rect.midY - 1))
        bolt.line(to: NSPoint(x: boltCenterX, y: rect.midY))
        bolt.line(to: NSPoint(x: boltCenterX - 2, y: rect.midY - 15))
        bolt.line(to: NSPoint(x: boltCenterX + 10, y: rect.midY + 2))
        bolt.line(to: NSPoint(x: boltCenterX + 2, y: rect.midY + 1))
        bolt.close()
        NSColor.secondaryLabelColor.setFill()
        bolt.fill()
    }

    private func drawLanes(in rect: NSRect) {
        let iconX = rect.minX - 4
        let startX = rect.minX + 29
        let endX = rect.maxX + 11
        let verticalOffsets: [CGFloat] = [0, 34, 69]
        let dotOffsets: [CGFloat] = [25, 25, 18]
        for index in 0..<3 {
            let y = rect.maxY - 11 - verticalOffsets[index]
            let lane = NSBezierPath()
            lane.move(to: NSPoint(x: startX, y: y))
            lane.line(to: NSPoint(x: endX, y: y))
            NSColor.tertiaryLabelColor.setStroke()
            lane.lineWidth = 2
            var dash: [CGFloat] = [11, 3, 3, 3]
            lane.setLineDash(&dash, count: dash.count, phase: 0)
            lane.stroke()
            SettingsStyle.green.setFill()
            NSBezierPath(
                ovalIn: NSRect(
                    x: rect.midX + dotOffsets[index] - 6,
                    y: y - 6,
                    width: 12,
                    height: 12
                )
            ).fill()

            NSColor.secondaryLabelColor.setStroke()
            switch index {
            case 0:
                let bolt = NSBezierPath()
                bolt.move(to: NSPoint(x: iconX + 10, y: y + 9))
                bolt.line(to: NSPoint(x: iconX + 4, y: y))
                bolt.line(to: NSPoint(x: iconX + 10, y: y + 1))
                bolt.line(to: NSPoint(x: iconX + 7, y: y - 9))
                bolt.lineWidth = 2
                bolt.lineJoinStyle = .round
                bolt.stroke()
            case 1:
                let screen = NSBezierPath(
                    roundedRect: NSRect(x: iconX, y: y - 7, width: 18, height: 13),
                    xRadius: 1.5,
                    yRadius: 1.5
                )
                screen.lineWidth = 1.5
                screen.stroke()
                let stand = NSBezierPath()
                stand.move(to: NSPoint(x: iconX + 7, y: y - 8))
                stand.line(to: NSPoint(x: iconX + 6, y: y - 11))
                stand.line(to: NSPoint(x: iconX + 12, y: y - 11))
                stand.line(to: NSPoint(x: iconX + 11, y: y - 8))
                stand.lineWidth = 1.5
                stand.stroke()
            default:
                let ring = NSBezierPath(
                    ovalIn: NSRect(x: iconX, y: y - 9, width: 18, height: 18)
                )
                var ringDash: [CGFloat] = [3, 3]
                ring.setLineDash(&ringDash, count: ringDash.count, phase: 0)
                ring.lineWidth = 2
                ring.stroke()
            }
        }
    }

    private func drawHistory(in rect: NSRect) {
        let guideRect = rect.offsetBy(dx: -4, dy: 0)
        NSColor.tertiaryLabelColor.withAlphaComponent(0.45).setStroke()
        for fraction in [0, 0.5, 1] as [CGFloat] {
            let guide = NSBezierPath()
            guide.move(to: NSPoint(
                x: guideRect.minX + guideRect.width * fraction,
                y: guideRect.minY
            ))
            guide.line(to: NSPoint(
                x: guideRect.minX + guideRect.width * fraction,
                y: guideRect.maxY
            ))
            var dash: [CGFloat] = [3, 4]
            guide.setLineDash(&dash, count: dash.count, phase: 0)
            guide.stroke()
        }

        let curveRect = NSRect(
            x: rect.minX - 10,
            y: rect.minY,
            width: rect.width + 14,
            height: rect.height
        )
        let points: [NSPoint] = [
            NSPoint(x: curveRect.minX, y: curveRect.minY + 12),
            NSPoint(
                x: curveRect.minX + curveRect.width * 0.2,
                y: curveRect.minY + curveRect.height * 0.58
            ),
            NSPoint(
                x: curveRect.minX + curveRect.width * 0.4,
                y: curveRect.minY + curveRect.height * 0.28
            ),
            NSPoint(
                x: curveRect.minX + curveRect.width * 0.62,
                y: curveRect.minY + curveRect.height * 0.52
            ),
            NSPoint(
                x: curveRect.maxX,
                y: curveRect.minY + curveRect.height * 0.44
            ),
        ]
        let line = NSBezierPath()
        line.move(to: points[0])
        line.curve(
            to: points[1],
            controlPoint1: NSPoint(x: points[0].x + 5, y: points[0].y + 18),
            controlPoint2: NSPoint(x: points[1].x - 6, y: points[1].y + 5)
        )
        line.curve(
            to: points[2],
            controlPoint1: NSPoint(x: points[1].x + 7, y: points[1].y - 2),
            controlPoint2: NSPoint(x: points[2].x - 6, y: points[2].y - 3)
        )
        line.curve(
            to: points[3],
            controlPoint1: NSPoint(x: points[2].x + 7, y: points[2].y + 3),
            controlPoint2: NSPoint(x: points[3].x - 7, y: points[3].y + 2)
        )
        line.curve(
            to: points[4],
            controlPoint1: NSPoint(x: points[3].x + 8, y: points[3].y - 3),
            controlPoint2: NSPoint(x: points[4].x - 8, y: points[4].y)
        )
        SettingsStyle.green.setStroke()
        line.lineWidth = 3
        line.lineJoinStyle = .round
        line.lineCapStyle = .round
        line.stroke()
        SettingsStyle.green.setFill()
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
    private let percentageButton: SettingsToggleButton
    private let loginButton: SettingsToggleButton
    private let batteryButton: SettingsToggleButton
    private let nativeIconButton: SettingsToggleButton
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
        percentageButton = SettingsToggleButton(
            accessibilityLabel: "Show Battery Percentage in Menu Bar",
            increaseContrast: dependencies.increaseContrast
        )
        loginButton = SettingsToggleButton(
            accessibilityLabel: "Launch at Login",
            increaseContrast: dependencies.increaseContrast
        )
        batteryButton = SettingsToggleButton(
            accessibilityLabel: "Hide System Battery Icon",
            increaseContrast: dependencies.increaseContrast
        )
        nativeIconButton = SettingsToggleButton(
            accessibilityLabel: "Use macOS-Style Wattson Icon",
            increaseContrast: dependencies.increaseContrast
        )
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
        refreshIconStyle()
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

        configureSwitch(nativeIconButton)
        nativeIconButton.target = self
        nativeIconButton.action = #selector(toggleNativeIcon(_:))
        nativeIconButton.setAccessibilityLabel("Use macOS-Style Wattson Icon")
        nativeIconButton.setAccessibilityHelp(
            "Changes Wattson only; Apple’s separate battery icon is controlled above."
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
        button.controlSize = .regular
        button.cell?.lineBreakMode = .byClipping
        button.title = ""
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: SettingsStyle.toggleSize.width),
            button.heightAnchor.constraint(equalToConstant: SettingsStyle.toggleSize.height),
        ])
    }

    private func configureDetailLabel(
        _ label: NSTextField,
        identifier: String
    ) {
        label.font = SettingsStyle.detailFont
        label.textColor = SettingsStyle.secondaryText
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
                visibleTitle: "Show Battery Percentage",
                button: percentageButton,
                detail: percentageDetail,
                error: nil,
                hasSeparator: true
            ),
            row(
                identifier: "login",
                symbolName: "person.fill",
                visibleTitle: "Launch at Login",
                button: loginButton,
                detail: loginDetail,
                error: loginError,
                hasSeparator: true
            ),
            row(
                identifier: "battery",
                symbolName: "eye.slash",
                visibleTitle: "Hide System Battery Icon",
                button: batteryButton,
                detail: batteryDetail,
                error: batteryError,
                hasSeparator: true
            ),
            row(
                identifier: "native-icon",
                symbolName: "battery.100",
                visibleTitle: "Use macOS-Style Icon",
                button: nativeIconButton,
                detail: configuredDetailLabel(
                    "Apple battery shape for Wattson’s icon",
                    identifier: "settings.general.native-icon.detail"
                ),
                error: nil,
                hasSeparator: false
            ),
        ])
        rows.orientation = .vertical
        rows.alignment = .width
        rows.distribution = .fillEqually
        rows.spacing = 0
        rows.translatesAutoresizingMaskIntoConstraints = false

        let list = SettingsAdaptiveBorderBox(
            increaseContrast: dependencies.increaseContrast
        )
        list.boxType = .custom
        list.identifier = NSUserInterfaceItemIdentifier("settings.general.list")
        list.titlePosition = .noTitle
        list.cornerRadius = SettingsStyle.surfaceCornerRadius
        list.fillColor = SettingsStyle.surfaceBackground
        list.translatesAutoresizingMaskIntoConstraints = false
        list.addSubview(rows)

        let heading = NSTextField(labelWithString: title)
        heading.font = SettingsStyle.headingFont
        heading.textColor = SettingsStyle.headingText
        heading.setAccessibilityLabel(title)
        heading.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(heading)
        view.addSubview(list)

        NSLayoutConstraint.activate([
            heading.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 13),
            heading.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            heading.topAnchor.constraint(equalTo: view.topAnchor, constant: -4),

            list.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            list.topAnchor.constraint(equalTo: view.topAnchor, constant: 61),
            list.heightAnchor.constraint(equalToConstant: SettingsStyle.generalListHeight),
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
        visibleTitle: String,
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
        iconTile.cornerRadius = 10
        iconTile.borderWidth = 1
        iconTile.borderColor = SettingsStyle.border
        iconTile.fillColor = SettingsStyle.tileBackground
        iconTile.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView()
        icon.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: nil
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 26, weight: .regular)
        )
        icon.contentTintColor = .secondaryLabelColor
        icon.imageScaling = .scaleProportionallyDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        iconTile.addSubview(icon)

        let primary = NSTextField(
            labelWithString: visibleTitle
        )
        primary.font = SettingsStyle.primaryFont
        primary.textColor = SettingsStyle.primaryText
        primary.lineBreakMode = .byTruncatingTail
        primary.translatesAutoresizingMaskIntoConstraints = false

        var textViews: [NSView] = [primary, detail]
        if let error { textViews.append(error) }
        let text = NSStackView(views: textViews)
        text.orientation = .vertical
        text.alignment = .leading
        text.distribution = .fill
        text.spacing = 4
        text.translatesAutoresizingMaskIntoConstraints = false

        row.addSubview(iconTile)
        row.addSubview(text)
        row.addSubview(button)

        NSLayoutConstraint.activate([
            iconTile.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 20),
            iconTile.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            iconTile.widthAnchor.constraint(equalToConstant: SettingsStyle.generalIconTileSize),
            iconTile.heightAnchor.constraint(equalToConstant: SettingsStyle.generalIconTileSize),
            icon.centerXAnchor.constraint(equalTo: iconTile.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconTile.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 24),
            icon.heightAnchor.constraint(equalToConstant: 24),

            text.leadingAnchor.constraint(equalTo: iconTile.trailingAnchor, constant: 29),
            text.centerYAnchor.constraint(equalTo: row.centerYAnchor, constant: 0.5),
            text.trailingAnchor.constraint(lessThanOrEqualTo: button.leadingAnchor, constant: -12),

            button.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -22),
            button.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])

        if hasSeparator {
            let separator = NSBox()
            separator.boxType = .separator
            separator.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(separator)
            NSLayoutConstraint.activate([
                separator.leadingAnchor.constraint(equalTo: row.leadingAnchor),
                separator.trailingAnchor.constraint(equalTo: row.trailingAnchor),
                separator.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            ])
        }
        return row
    }

    private func configuredDetailLabel(
        _ text: String,
        identifier: String
    ) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        configureDetailLabel(label, identifier: identifier)
        return label
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
                self.refreshIconStyle()
                return
            }
            switch change {
            case .menuBarPercentage:
                self.refreshPercentage()
            case .menuBarIconStyle:
                self.refreshIconStyle()
            case .module:
                break
            }
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

    private func refreshIconStyle() {
        nativeIconButton.state = Settings.menuBarIconStyle == .native ? .on : .off
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

    @objc private func toggleNativeIcon(_ sender: NSButton) {
        Settings.menuBarIconStyle = sender.state == .on ? .native : .wattson
    }

    @objc private func toggleLoginItem(_ sender: NSButton) {
        guard !loginMutationInFlight else { return }
        let restoration = lastAuthoritativeLoginState
            ?? authoritativeLoginState(dependencies.loginItemState())
        guard let restoration else {
            renderLoginItem(.readFailed)
            return
        }
        // `.mixed` is a display-only unknown state, not a third user choice.
        // Invert the last authoritative value so mouse, keyboard, and
        // VoiceOver agree.
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
            loginDetail.stringValue = "Open Wattson when you sign in"
        case .notRegistered:
            loginButton.state = .off
            loginButton.isEnabled = true
            loginDetail.stringValue = "Open Wattson when you sign in"
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
        batteryDetail.stringValue = "Reduce duplicate battery indicators"
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
    let symbolName = "puzzlepiece"
    let view = NSView()

    private let increaseContrast: () -> Bool
    private var buttons: [Settings.Module: NSButton] = [:]
    private var settingsObserver: NSObjectProtocol?

    init(increaseContrast: @escaping () -> Bool) {
        self.increaseContrast = increaseContrast
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
        heading.font = SettingsStyle.headingFont
        heading.textColor = SettingsStyle.headingText
        heading.setAccessibilityLabel(title)
        heading.translatesAutoresizingMaskIntoConstraints = false

        let subtitle = NSTextField(
            labelWithString: "Choose what appears in the power popover."
        )
        subtitle.identifier = NSUserInterfaceItemIdentifier("settings.modules.subtitle")
        subtitle.font = .systemFont(ofSize: 18, weight: .regular)
        subtitle.textColor = SettingsStyle.secondaryText
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
        grid.rowSpacing = SettingsStyle.moduleCardGap
        grid.columnSpacing = SettingsStyle.moduleCardGap
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.row(at: 0).height = SettingsStyle.moduleCardHeight
        grid.row(at: 1).height = SettingsStyle.moduleCardHeight
        grid.column(at: 0).width = SettingsStyle.moduleCardWidth
        grid.column(at: 1).width = SettingsStyle.moduleCardWidth

        view.addSubview(heading)
        view.addSubview(subtitle)
        view.addSubview(grid)

        NSLayoutConstraint.activate([
            cards[0].widthAnchor.constraint(equalTo: cards[1].widthAnchor),
            cards[0].widthAnchor.constraint(equalTo: cards[2].widthAnchor),
            cards[0].widthAnchor.constraint(equalTo: cards[3].widthAnchor),
            cards[0].widthAnchor.constraint(equalToConstant: SettingsStyle.moduleCardWidth),

            heading.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 2),
            heading.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            heading.topAnchor.constraint(equalTo: view.topAnchor, constant: -3),

            subtitle.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 2),
            subtitle.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            subtitle.bottomAnchor.constraint(equalTo: grid.topAnchor, constant: -24),

            grid.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            grid.topAnchor.constraint(equalTo: view.topAnchor, constant: 94),
            grid.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor),
            grid.heightAnchor.constraint(
                equalToConstant: SettingsStyle.moduleCardHeight * 2
                    + SettingsStyle.moduleCardGap
            ),
        ])
    }

    private func makeCard(for module: Settings.Module, index: Int) -> NSView {
        let card = SettingsAdaptiveBorderBox(increaseContrast: increaseContrast)
        card.identifier = NSUserInterfaceItemIdentifier(
            "settings.modules.card.\(module.rawValue)"
        )
        card.boxType = .custom
        card.titlePosition = .noTitle
        card.cornerRadius = SettingsStyle.surfaceCornerRadius
        card.fillColor = SettingsStyle.surfaceBackground

        let preview = StaticModulePreviewView(module: module)
        preview.translatesAutoresizingMaskIntoConstraints = false

        let primary = NSTextField(labelWithString: module.title)
        primary.font = SettingsStyle.primaryFont
        primary.textColor = SettingsStyle.primaryText
        primary.lineBreakMode = .byTruncatingTail
        primary.translatesAutoresizingMaskIntoConstraints = false

        let detail = NSTextField(labelWithString: description(for: module))
        detail.font = SettingsStyle.detailFont
        detail.textColor = SettingsStyle.secondaryText
        detail.lineBreakMode = .byWordWrapping
        detail.maximumNumberOfLines = 2
        detail.cell?.usesSingleLineMode = false
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 8
        detail.attributedStringValue = NSAttributedString(
            string: description(for: module),
            attributes: [
                .font: SettingsStyle.detailFont,
                .foregroundColor: SettingsStyle.secondaryText,
                .paragraphStyle: paragraphStyle,
            ]
        )
        detail.translatesAutoresizingMaskIntoConstraints = false

        let button = SettingsToggleButton(
            accessibilityLabel: module.title,
            increaseContrast: increaseContrast,
            target: self,
            action: #selector(toggleModule(_:))
        )
        button.controlSize = .regular
        button.cell?.lineBreakMode = .byClipping
        button.tag = index
        button.setAccessibilityHelp("Show or hide the \(module.title) module in Wattson.")
        buttons[module] = button

        card.addSubview(preview)
        card.addSubview(primary)
        card.addSubview(detail)
        card.addSubview(button)

        NSLayoutConstraint.activate([
            preview.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            preview.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            preview.widthAnchor.constraint(equalToConstant: SettingsStyle.modulePreviewSize.width),
            preview.heightAnchor.constraint(equalToConstant: SettingsStyle.modulePreviewSize.height),

            primary.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            primary.trailingAnchor.constraint(lessThanOrEqualTo: button.leadingAnchor, constant: -10),
            primary.topAnchor.constraint(equalTo: card.topAnchor, constant: 151),

            detail.leadingAnchor.constraint(equalTo: primary.leadingAnchor),
            detail.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
            detail.topAnchor.constraint(equalTo: primary.bottomAnchor, constant: 10),
            detail.bottomAnchor.constraint(lessThanOrEqualTo: card.bottomAnchor, constant: -20),

            button.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -22),
            button.centerYAnchor.constraint(equalTo: primary.centerYAnchor),
            button.widthAnchor.constraint(equalToConstant: SettingsStyle.toggleSize.width),
            button.heightAnchor.constraint(equalToConstant: SettingsStyle.toggleSize.height),
            card.heightAnchor.constraint(equalToConstant: SettingsStyle.moduleCardHeight),
        ])
        return card
    }

    private func description(for module: Settings.Module) -> String {
        switch module {
        case .flow: return "Visualize power\nmovement"
        case .ring: return "Circular battery\nindicator"
        case .lanes: return "Break down\npower usage"
        case .history: return "Track battery\nover time"
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
    private static let trafficLightReferenceFrames = [
        NSRect(x: 23, y: 26, width: 20, height: 20),
        NSRect(x: 53, y: 26, width: 20, height: 20),
        NSRect(x: 84, y: 26, width: 19, height: 19),
    ]

    private let sections: [SettingsSectionController]
    private let increaseContrast: () -> Bool
    private let sidebar = NSTableView()
    private let contentHost = NSView()
    private let titlebarSpacer = NSTitlebarAccessoryViewController()
    private let divider: DynamicSeparatorView
    private var trafficLightButtons: [ReferenceTrafficLightButton] = []
    private var accessibilityDisplayObserver: NSObjectProtocol?
    private var selectedSectionIndex = 0

    static func defaultSections(
        dependencies: SettingsWindowDependencies = .live
    ) -> [SettingsSectionController] {
        [
            GeneralSettingsSectionController(dependencies: dependencies),
            ModuleSettingsSectionController(
                increaseContrast: dependencies.increaseContrast
            ),
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
        increaseContrast = dependencies.increaseContrast
        divider = DynamicSeparatorView(
            increaseContrast: dependencies.increaseContrast
        )

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: SettingsStyle.contentSize),
            styleMask: [
                .titled,
                .closable,
                .miniaturizable,
                .resizable,
                .fullSizeContentView,
            ],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = SettingsStyle.contentBackground
        window.title = "Wattson Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.tabbingMode = .disallowed
        // The reference is a fixed composition; resizing would distort the
        // measured card and sidebar geometry. Keep the native zoom control,
        // but constrain AppKit to the approved artwork size.
        window.contentMinSize = SettingsStyle.contentSize
        window.contentMaxSize = SettingsStyle.contentSize
        window.isMovableByWindowBackground = true
        window.autorecalculatesKeyViewLoop = false

        let hadSavedFrame = frameAutosaveName.flatMap {
            UserDefaults.standard.string(forKey: "NSWindow Frame \($0)")
        } != nil
        super.init(window: window)

        configureContent()
        configureTrafficLights()
        installAccessibilityDisplayObserver()
        refreshContrastAppearance()
        if let frameAutosaveName {
            // NSWindowController initialization clears a name assigned before
            // it takes ownership, so install autosave after `super.init`.
            window.setFrameAutosaveName(frameAutosaveName)
            if !hadSavedFrame { window.center() }
        }
    }

    deinit {
        if let accessibilityDisplayObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(
                accessibilityDisplayObserver
            )
        }
    }

    private func installAccessibilityDisplayObserver() {
        accessibilityDisplayObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshContrastAppearance()
        }
    }

    private func refreshContrastAppearance() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.refreshContrastAppearance()
            }
            return
        }

        sections.forEach { refreshContrastAppearance(in: $0.view) }
        sidebar.enumerateAvailableRowViews { rowView, _ in
            (rowView as? SettingsContrastRefreshing)?.refreshContrastAppearance()
        }
        divider.refreshContrastAppearance()
    }

    private func refreshContrastAppearance(in view: NSView) {
        (view as? SettingsContrastRefreshing)?.refreshContrastAppearance()
        view.subviews.forEach { refreshContrastAppearance(in: $0) }
    }

    private func configureTrafficLights() {
        guard let window else { return }
        // Keep AppKit's standard controls as the action owners. The visible
        // proxy buttons forward to them while matching the reference artwork's
        // 18-point circles instead of AppKit's fixed 14-point drawing size.
        titlebarSpacer.layoutAttribute = .bottom
        titlebarSpacer.view = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 36))
        window.addTitlebarAccessoryViewController(titlebarSpacer)
        window.contentView?.layoutSubtreeIfNeeded()

        let definitions: [(NSWindow.ButtonType, ReferenceTrafficLightButton.Kind)] = [
            (.closeButton, .close),
            (.miniaturizeButton, .minimize),
            (.zoomButton, .zoom),
        ]
        trafficLightButtons.removeAll()
        for ((type, kind), referenceFrame) in zip(
            definitions,
            Self.trafficLightReferenceFrames
        ) {
            guard let native = window.standardWindowButton(type),
                  let parent = native.superview else { continue }
            native.isHidden = true
            let proxy = ReferenceTrafficLightButton(kind: kind, nativeButton: native)
            proxy.frame = referenceFrame
            proxy.autoresizingMask = [.maxXMargin, .minYMargin]
            parent.addSubview(proxy)
            trafficLightButtons.append(proxy)
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
        fitReferenceCompositionToVisibleScreen(window)
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

    private func fitReferenceCompositionToVisibleScreen(_ window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame.insetBy(dx: 12, dy: 12)
        let referenceFrame = window.frameRect(forContentRect: NSRect(
            origin: .zero,
            size: SettingsStyle.contentSize
        )).size
        let scale = max(SettingsStyle.minimumContentScale, min(
            1,
            visible.width / referenceFrame.width,
            visible.height / referenceFrame.height
        ))
        applyContentScale(scale, to: window)
        if scale < 1 { window.center() }
    }

    private func applyContentScale(_ scale: CGFloat, to window: NSWindow) {
        let compact = NSSize(
            width: floor(SettingsStyle.contentSize.width * scale),
            height: floor(SettingsStyle.contentSize.height * scale)
        )
        window.contentMinSize = compact
        window.contentMaxSize = compact
        window.setContentSize(compact)
        // Keep layout in the reference coordinate space while NSView maps it
        // proportionally into a smaller frame. Unlike a layer transform, the
        // bounds transform also preserves hit testing and accessibility.
        if let viewport = window.contentView {
            viewport.setFrameSize(compact)
            viewport.setBoundsSize(SettingsStyle.contentSize)
            viewport.subviews.first {
                $0.identifier?.rawValue == "settings.root"
            }?.frame = viewport.bounds
            viewport.layoutSubtreeIfNeeded()
        }
        applyTrafficLightScale(scale)
    }

    private func applyTrafficLightScale(_ scale: CGFloat) {
        for (button, referenceFrame) in zip(
            trafficLightButtons,
            Self.trafficLightReferenceFrames
        ) {
            guard let parent = button.superview else { continue }
            let referenceTopInset: CGFloat = 68 - referenceFrame.maxY
            let size = NSSize(
                width: referenceFrame.width * scale,
                height: referenceFrame.height * scale
            )
            button.frame = NSRect(
                x: referenceFrame.minX * scale,
                y: parent.bounds.height - referenceTopInset * scale - size.height,
                width: size.width,
                height: size.height
            )
            button.needsDisplay = true
        }
    }

    private func configureContent() {
        guard let window else { return }
        let viewport = NSView(frame: NSRect(origin: .zero, size: SettingsStyle.contentSize))
        viewport.identifier = NSUserInterfaceItemIdentifier("settings.viewport")
        viewport.autoresizingMask = [.width, .height]
        let root = SettingsFillView(color: SettingsStyle.contentBackground)
        root.frame = NSRect(origin: .zero, size: SettingsStyle.contentSize)
        root.identifier = NSUserInterfaceItemIdentifier("settings.root")
        root.autoresizingMask = []

        let sidebarContainer = SettingsFillView(color: SettingsStyle.sidebarBackground)
        sidebarContainer.identifier = NSUserInterfaceItemIdentifier("settings.sidebar")
        sidebarContainer.translatesAutoresizingMaskIntoConstraints = false

        let identity = makeIdentityView()
        let trafficSafeArea = NSView()
        trafficSafeArea.identifier = NSUserInterfaceItemIdentifier(
            "settings.sidebar.traffic-safe-area"
        )
        trafficSafeArea.translatesAutoresizingMaskIntoConstraints = false
        let navigation = makeNavigationView()
        divider.identifier = NSUserInterfaceItemIdentifier("settings.sidebar.divider")
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
            sidebarContainer.widthAnchor.constraint(equalToConstant: SettingsStyle.sidebarWidth),

            trafficSafeArea.leadingAnchor.constraint(equalTo: sidebarContainer.leadingAnchor),
            trafficSafeArea.trailingAnchor.constraint(equalTo: sidebarContainer.trailingAnchor),
            trafficSafeArea.topAnchor.constraint(equalTo: sidebarContainer.topAnchor),
            trafficSafeArea.heightAnchor.constraint(
                equalToConstant: SettingsStyle.trafficLightSafeHeight
            ),

            identity.leadingAnchor.constraint(equalTo: sidebarContainer.leadingAnchor),
            identity.trailingAnchor.constraint(equalTo: sidebarContainer.trailingAnchor),
            identity.topAnchor.constraint(equalTo: trafficSafeArea.bottomAnchor),
            identity.heightAnchor.constraint(equalToConstant: SettingsStyle.identityHeight),

            navigation.leadingAnchor.constraint(
                equalTo: sidebarContainer.leadingAnchor,
                constant: SettingsStyle.navigationInset
            ),
            navigation.trailingAnchor.constraint(
                equalTo: sidebarContainer.trailingAnchor,
                constant: -SettingsStyle.navigationInset
            ),
            navigation.topAnchor.constraint(
                equalTo: identity.bottomAnchor,
                constant: SettingsStyle.navigationTopGap
            ),
            navigation.heightAnchor.constraint(
                equalToConstant: SettingsStyle.navigationHeight
            ),

            divider.leadingAnchor.constraint(equalTo: sidebarContainer.trailingAnchor),
            divider.topAnchor.constraint(equalTo: root.topAnchor),
            divider.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        divider.widthAnchor.constraint(equalToConstant: 1),

            contentHost.leadingAnchor.constraint(
                equalTo: divider.trailingAnchor,
                constant: SettingsStyle.contentHorizontalInset
            ),
            contentHost.trailingAnchor.constraint(
                equalTo: root.trailingAnchor,
                constant: -SettingsStyle.contentHorizontalInset
            ),
            contentHost.topAnchor.constraint(
                equalTo: root.topAnchor,
                constant: SettingsStyle.contentTopInset
            ),
            contentHost.bottomAnchor.constraint(
                equalTo: root.bottomAnchor,
                constant: -SettingsStyle.contentBottomInset
            ),
        ])

        viewport.addSubview(root)
        window.contentView = viewport
        viewport.setBoundsSize(SettingsStyle.contentSize)
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

        let iconTile = NSBox()
        iconTile.boxType = .custom
        iconTile.titlePosition = .noTitle
        iconTile.cornerRadius = 12
        iconTile.borderWidth = 1
        iconTile.borderColor = SettingsStyle.border
        iconTile.fillColor = SettingsStyle.tileBackground
        iconTile.translatesAutoresizingMaskIntoConstraints = false

        let icon = ECGIconView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        iconTile.addSubview(icon)

        let name = NSTextField(labelWithString: "Wattson")
        name.font = .systemFont(ofSize: 21, weight: .semibold)
        name.textColor = SettingsStyle.headingText
        name.translatesAutoresizingMaskIntoConstraints = false

        identity.addSubview(iconTile)
        identity.addSubview(name)
        NSLayoutConstraint.activate([
            iconTile.leadingAnchor.constraint(equalTo: identity.leadingAnchor, constant: 24),
            iconTile.centerYAnchor.constraint(equalTo: identity.centerYAnchor, constant: -1),
            iconTile.widthAnchor.constraint(equalToConstant: SettingsStyle.identityTileSize),
            iconTile.heightAnchor.constraint(equalToConstant: SettingsStyle.identityTileSize),
            icon.centerXAnchor.constraint(equalTo: iconTile.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconTile.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 40),
            icon.heightAnchor.constraint(equalToConstant: 40),
            name.leadingAnchor.constraint(equalTo: iconTile.trailingAnchor, constant: 12),
            name.centerYAnchor.constraint(equalTo: iconTile.centerYAnchor),
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
        sidebar.rowHeight = SettingsStyle.navigationRowHeight
        sidebar.intercellSpacing = NSSize(width: 0, height: SettingsStyle.navigationRowGap)
        sidebar.selectionHighlightStyle = .none
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

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        SettingsStyle.navigationRowHeight
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        SettingsSidebarRowView(increaseContrast: increaseContrast)
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        guard sections.indices.contains(row) else { return nil }
        let section = sections[row]
        let cell = NSTableCellView()

        let icon: NSView
        if section.identifier == "modules" {
            icon = PuzzleNavigationIconView()
        } else {
            let imageView = NSImageView()
            imageView.image = NSImage(
                systemSymbolName: section.symbolName,
                accessibilityDescription: nil
            )?.withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: 23, weight: .regular)
            )
            imageView.contentTintColor = .labelColor
            imageView.imageScaling = .scaleNone
            icon = imageView
        }
        icon.setAccessibilityElement(false)
        icon.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: section.title)
        title.font = SettingsStyle.sidebarFont
        title.textColor = SettingsStyle.primaryText
        title.lineBreakMode = .byTruncatingTail
        title.translatesAutoresizingMaskIntoConstraints = false

        cell.addSubview(icon)
        cell.addSubview(title)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: -3),
            icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 28),
            icon.heightAnchor.constraint(equalToConstant: 28),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 15),
            title.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            title.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        cell.setAccessibilityLabel(section.title)
        cell.setAccessibilityHelp("Show the \(section.title) settings page.")
        return cell
    }

#if DEBUG
    var windowForTest: NSWindow? { window }
    var trafficLightButtonsForTest: [NSButton] { trafficLightButtons }
    var selectedRowStrokeWidthForTest: CGFloat {
        selectedSidebarRowForTest?.selectionStrokeWidth ?? -1
    }
    var selectedRowFillColorForTest: NSColor? {
        selectedSidebarRowForTest?.selectionFillColor
    }
    var selectedRowStrokeColorForTest: NSColor? {
        selectedSidebarRowForTest?.selectionStrokeColor
    }
    var dividerVisualStrokeWidthForTest: CGFloat { divider.renderedStrokeWidth }
    var dividerColorForTest: NSColor { divider.strokeColor }

    func toggleTrackStrokeWidthForTest(_ accessibilityLabel: String) -> CGFloat {
        settingsToggleForTest(accessibilityLabel)?.trackStrokeWidth ?? -1
    }

    func toggleTrackColorForTest(_ accessibilityLabel: String) -> NSColor? {
        settingsToggleForTest(accessibilityLabel)?.trackColor
    }

    func toggleTrackStrokeColorForTest(_ accessibilityLabel: String) -> NSColor? {
        settingsToggleForTest(accessibilityLabel)?.trackStrokeColor
    }

    private var selectedSidebarRowForTest: SettingsSidebarRowView? {
        guard sidebar.selectedRow >= 0 else { return nil }
        return sidebar.rowView(
            atRow: sidebar.selectedRow,
            makeIfNecessary: true
        ) as? SettingsSidebarRowView
    }

    private func settingsToggleForTest(
        _ accessibilityLabel: String
    ) -> SettingsToggleButton? {
        for section in sections {
            if let match = switchButtons(in: section.view)
                .compactMap({ $0 as? SettingsToggleButton })
                .first(where: { $0.accessibilityLabel() == accessibilityLabel }) {
                return match
            }
        }
        return nil
    }

    func applyContentScaleForTest(_ scale: CGFloat) {
        guard let window else { return }
        applyContentScale(scale, to: window)
    }
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
