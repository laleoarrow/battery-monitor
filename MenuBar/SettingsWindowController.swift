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
    static let contentSize = NSSize(width: 720, height: 520)
    static let sidebarWidth: CGFloat = 176
    static let contentHorizontalInset: CGFloat = 20
    static let contentTopInset: CGFloat = 56
    static let contentBottomInset: CGFloat = 20

    static let trafficLightSafeHeight: CGFloat = 52
    static let identityHeight: CGFloat = 64
    static let identityTileSize: CGFloat = 40
    static let navigationInset: CGFloat = 12
    static let navigationTopGap: CGFloat = 4
    static let navigationRowHeight: CGFloat = 38
    static let navigationRowGap: CGFloat = 4
    static let navigationHeight: CGFloat = 136

    static let headingFont = NSFont.systemFont(ofSize: 22, weight: .semibold)
    static let primaryFont = NSFont.systemFont(ofSize: 14, weight: .regular)
    static let detailFont = NSFont.systemFont(ofSize: 11, weight: .regular)
    static let sidebarFont = NSFont.systemFont(ofSize: 13, weight: .medium)

    static let toggleSize = NSSize(width: 38, height: 22)
    static let generalListHeight: CGFloat = 136
    static let generalRowHeight: CGFloat = 68
    static let generalIconTileSize: CGFloat = 36
    static let moduleCardHeight: CGFloat = 166
    static let moduleCardWidth: CGFloat = 233
    static let moduleCardGap: CGFloat = 12
    static let iconCardGap: CGFloat = 8
    static let iconCardHeight: CGFloat = 80
    static let iconCardGroupHeight: CGFloat = 344
    static let iconStateHeight: CGFloat = 38
    static let iconStateGap: CGFloat = 5
    static let iconStateCornerRadius: CGFloat = 7
    static let surfaceCornerRadius: CGFloat = 10
    static let modulePreviewSize = NSSize(width: 64, height: 60)

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

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let designSize = NSSize(width: 112, height: 108)
        let transform = NSAffineTransform()
        transform.scaleX(
            by: bounds.width / designSize.width,
            yBy: bounds.height / designSize.height
        )
        transform.concat()
        let drawingRect = NSRect(origin: .zero, size: designSize).insetBy(dx: 14, dy: 13)
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
    private let loginButton: SettingsToggleButton
    private let batteryButton: SettingsToggleButton
    private let loginDetail = NSTextField(labelWithString: "")
    private let loginError = NSTextField(labelWithString: "")
    private let batteryDetail = NSTextField(labelWithString: "")
    private let batteryError = NSTextField(labelWithString: "")

    private let loginAccessibilityPurpose =
        "Open Wattson automatically after you sign in to this Mac."
    private let batteryAccessibilityPurpose =
        "Hide Apple’s battery icon while keeping Wattson in the menu bar."

    private var batteryObserver: NSObjectProtocol?
    private var loginGeneration = 0
    private var batteryGeneration = 0
    private var loginMutationInFlight = false
    private var batteryMutationInFlight = false
    private var lastAuthoritativeLoginState: LoginItemState?
    private var lastAuthoritativeBatteryState: Bool?

    init(dependencies: SettingsWindowDependencies) {
        self.dependencies = dependencies
        loginButton = SettingsToggleButton(
            accessibilityLabel: "Launch at Login",
            increaseContrast: dependencies.increaseContrast
        )
        batteryButton = SettingsToggleButton(
            accessibilityLabel: "Hide System Battery Icon",
            increaseContrast: dependencies.increaseContrast
        )
        super.init()

        configureControls()
        buildView()
        installObservers()
    }

    deinit {
        if let batteryObserver {
            NotificationCenter.default.removeObserver(batteryObserver)
        }
    }

    func refresh() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.refresh() }
            return
        }

        refreshLoginItem()
        refreshBatteryIcon()
    }

    private func configureControls() {
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
        let rows = NSStackView(views: [
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
        heading.identifier = NSUserInterfaceItemIdentifier("settings.general.heading")
        heading.font = SettingsStyle.headingFont
        heading.textColor = SettingsStyle.headingText
        heading.setAccessibilityLabel(title)
        heading.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(heading)
        view.addSubview(list)

        NSLayoutConstraint.activate([
            heading.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 2),
            heading.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            heading.topAnchor.constraint(equalTo: view.topAnchor, constant: -2),

            list.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            list.topAnchor.constraint(equalTo: view.topAnchor, constant: 40),
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
        iconTile.cornerRadius = 8
        iconTile.borderWidth = 1
        iconTile.borderColor = SettingsStyle.border
        iconTile.fillColor = SettingsStyle.tileBackground
        iconTile.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView()
        icon.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: nil
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 17, weight: .regular)
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
        text.spacing = 2
        text.translatesAutoresizingMaskIntoConstraints = false

        row.addSubview(iconTile)
        row.addSubview(text)
        row.addSubview(button)

        NSLayoutConstraint.activate([
            iconTile.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 14),
            iconTile.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            iconTile.widthAnchor.constraint(equalToConstant: SettingsStyle.generalIconTileSize),
            iconTile.heightAnchor.constraint(equalToConstant: SettingsStyle.generalIconTileSize),
            icon.centerXAnchor.constraint(equalTo: iconTile.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconTile.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),

            text.leadingAnchor.constraint(equalTo: iconTile.trailingAnchor, constant: 14),
            text.centerYAnchor.constraint(equalTo: row.centerYAnchor, constant: 0.5),
            text.trailingAnchor.constraint(lessThanOrEqualTo: button.leadingAnchor, constant: -12),

            button.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -14),
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

    private func installObservers() {
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

private enum MenuBarIconAppearance: Int, CaseIterable {
    case wattsonIconOnly
    case wattsonWithPercentage
    case macOSIconOnly
    case macOSWithPercentage

    var iconStyle: Settings.MenuBarIconStyle {
        switch self {
        case .wattsonIconOnly, .wattsonWithPercentage: return .wattson
        case .macOSIconOnly, .macOSWithPercentage: return .native
        }
    }

    var showsPercentage: Bool {
        switch self {
        case .wattsonIconOnly, .macOSIconOnly: return false
        case .wattsonWithPercentage, .macOSWithPercentage: return true
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .wattsonIconOnly: return "Wattson icon only"
        case .wattsonWithPercentage: return "Wattson with percentage"
        case .macOSIconOnly: return "macOS 26 icon only"
        case .macOSWithPercentage: return "macOS 26 with percentage"
        }
    }

    var visibleTitle: String {
        switch iconStyle {
        case .wattson: return "Wattson"
        case .native: return "macOS 26"
        }
    }

    var visibleDetail: String { showsPercentage ? "With percentage" : "Icon only" }

    var accessibilityHelp: String {
        let artwork = iconStyle == .wattson
            ? "Wattson’s live status battery glyph"
            : "The battery artwork used by the macOS 26 menu bar"
        return showsPercentage
            ? "\(artwork), with the battery percentage on its left."
            : "\(artwork), without a percentage."
    }

    var identifierSuffix: String {
        switch self {
        case .wattsonIconOnly: return "wattson-icon-only"
        case .wattsonWithPercentage: return "wattson-percentage"
        case .macOSIconOnly: return "macos-icon-only"
        case .macOSWithPercentage: return "macos-percentage"
        }
    }

    init(iconStyle: Settings.MenuBarIconStyle, showsPercentage: Bool) {
        switch (iconStyle, showsPercentage) {
        case (.wattson, false): self = .wattsonIconOnly
        case (.wattson, true): self = .wattsonWithPercentage
        case (.native, false): self = .macOSIconOnly
        case (.native, true): self = .macOSWithPercentage
        }
    }
}

private enum MenuBarIconCardKeyCommand {
    case previous
    case next
    case first
    case last
}

enum MenuBarIconPreviewState: CaseIterable {
    case onBattery
    case pluggedFull
    case charging
    case lowBattery
    case lowBatteryPlugged
    case lowPower
    case lowPowerPlugged

    var identifierSuffix: String {
        switch self {
        case .onBattery: return "battery"
        case .pluggedFull: return "full"
        case .charging: return "charging"
        case .lowBattery: return "low"
        case .lowBatteryPlugged: return "low-ac"
        case .lowPower: return "saver"
        case .lowPowerPlugged: return "saver-ac"
        }
    }

    var visibleLabel: String {
        switch self {
        case .onBattery: return "Battery"
        case .pluggedFull: return "Full"
        case .charging: return "Charging"
        case .lowBattery: return "Low"
        case .lowBatteryPlugged: return "Low + AC"
        case .lowPower: return "Saver"
        case .lowPowerPlugged: return "Saver + AC"
        }
    }

    var accessibilityDescription: String {
        switch self {
        case .onBattery: return "75 percent on battery"
        case .pluggedFull: return "100 percent full and connected to power"
        case .charging: return "72 percent charging"
        case .lowBattery: return "10 percent low battery"
        case .lowBatteryPlugged: return "20 percent low battery connected to power"
        case .lowPower: return "42 percent in Low Power Mode"
        case .lowPowerPlugged: return "42 percent in Low Power Mode connected to power"
        }
    }

    var mode: EnergyMode {
        switch self {
        case .lowPower, .lowPowerPlugged: return .low
        default: return .auto
        }
    }

    var fixture: (
        percent: Int,
        plugged: Bool,
        adapterW: Double,
        batteryW: Double,
        systemW: Double,
        lowPowerMode: Bool
    ) {
        switch self {
        case .onBattery:
            return (percent: 75, plugged: false, adapterW: 0, batteryW: -18,
                    systemW: 18, lowPowerMode: false)
        case .pluggedFull:
            return (percent: 100, plugged: true, adapterW: 42, batteryW: 0,
                    systemW: 42, lowPowerMode: false)
        case .charging:
            return (percent: 72, plugged: true, adapterW: 60, batteryW: 18,
                    systemW: 42, lowPowerMode: false)
        case .lowBattery:
            return (percent: 10, plugged: false, adapterW: 0, batteryW: -12,
                    systemW: 12, lowPowerMode: false)
        case .lowBatteryPlugged:
            return (percent: 20, plugged: true, adapterW: 42, batteryW: 0,
                    systemW: 42, lowPowerMode: false)
        case .lowPower:
            return (percent: 42, plugged: false, adapterW: 0, batteryW: -18,
                    systemW: 18, lowPowerMode: true)
        case .lowPowerPlugged:
            return (percent: 42, plugged: true, adapterW: 42, batteryW: 0,
                    systemW: 42, lowPowerMode: true)
        }
    }

    var snapshot: PowerSnapshot {
        let fixture = fixture
        return PowerSnapshot(
            percent: fixture.percent,
            plugged: fixture.plugged,
            adapterW: fixture.adapterW,
            batteryW: fixture.batteryW,
            systemW: fixture.systemW,
            temperatureC: nil,
            cycleCount: 0,
            lowPowerMode: fixture.lowPowerMode
        )
    }
}

private final class MenuBarIconCardButton: NSButton, SettingsContrastRefreshing {
    let menuBarAppearance: MenuBarIconAppearance
    var onKeyboardCommand: ((MenuBarIconCardKeyCommand) -> Void)?

#if DEBUG
    private(set) var drawCountForTest = 0
#endif

    private let increaseContrast: () -> Bool
    private var stateBoxes: [NSBox] = []

    /// Keeps the menu-bar font family and tabular digit spacing at a compact
    /// preview size, leaving safe insets around three-digit percentages.
    private static let previewMenuBarFont: NSFont = {
        let base = NSFont.menuBarFont(ofSize: 11)
        let descriptor = base.fontDescriptor.addingAttributes([
            .featureSettings: [[
                NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
                NSFontDescriptor.FeatureKey.selectorIdentifier:
                    kMonospacedNumbersSelector,
            ]],
        ])
        return NSFont(descriptor: descriptor, size: 11) ?? base
    }()

    init(
        appearance: MenuBarIconAppearance,
        previews: [(state: MenuBarIconPreviewState, image: NSImage)],
        increaseContrast: @escaping () -> Bool
    ) {
        menuBarAppearance = appearance
        self.increaseContrast = increaseContrast
        super.init(frame: .zero)

        let identifierSuffix = appearance.identifierSuffix
        identifier = NSUserInterfaceItemIdentifier(
            "settings.menu-bar-icon.card.\(identifierSuffix)"
        )
        title = ""
        isBordered = false
        bezelStyle = .regularSquare
        imagePosition = .noImage
        focusRingType = .none
        setButtonType(.radio)
        setAccessibilityRole(.radioButton)
        setAccessibilityLabel(appearance.accessibilityLabel)
        let stateDescriptions = previews.map(\.state.accessibilityDescription).joined(
            separator: ", "
        )
        setAccessibilityHelp("\(appearance.accessibilityHelp) Previews: \(stateDescriptions).")

        let stateViews = previews.map { preview -> NSView in
            let stateSuffix = "\(identifierSuffix).\(preview.state.identifierSuffix)"

            let stateBox = NSBox()
            stateBox.identifier = NSUserInterfaceItemIdentifier(
                "settings.menu-bar-icon.state.\(stateSuffix)"
            )
            let increased = increaseContrast()
            stateBox.boxType = .custom
            stateBox.titlePosition = .noTitle
            stateBox.cornerRadius = SettingsStyle.iconStateCornerRadius
            stateBox.borderWidth = increased ? 2 : 1
            stateBox.borderColor = increased
                ? SettingsStyle.increasedContrastBorder
                : SettingsStyle.border
            stateBox.fillColor = SettingsStyle.previewBackground
            stateBox.setAccessibilityElement(false)
            stateBox.translatesAutoresizingMaskIntoConstraints = false
            stateBoxes.append(stateBox)

            let stateLabel = NSTextField(labelWithString: preview.state.visibleLabel)
            stateLabel.identifier = NSUserInterfaceItemIdentifier(
                "settings.menu-bar-icon.state-label.\(stateSuffix)"
            )
            stateLabel.font = .systemFont(ofSize: 9, weight: .medium)
            stateLabel.textColor = SettingsStyle.secondaryText
            stateLabel.alignment = .center
            stateLabel.lineBreakMode = .byClipping
            stateLabel.maximumNumberOfLines = 1
            stateLabel.setAccessibilityElement(false)
            stateLabel.translatesAutoresizingMaskIntoConstraints = false

            let imageView = NSImageView()
            imageView.identifier = NSUserInterfaceItemIdentifier(
                "settings.menu-bar-icon.preview.\(stateSuffix)"
            )
            imageView.image = preview.image
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.contentTintColor = .labelColor
            imageView.setAccessibilityElement(false)
            imageView.translatesAutoresizingMaskIntoConstraints = false

            var presentationViews: [NSView] = []
            if appearance.showsPercentage {
                let percentage = NSTextField(
                    labelWithString: "\(preview.state.fixture.percent)% "
                )
                percentage.identifier = NSUserInterfaceItemIdentifier(
                    "settings.menu-bar-icon.percentage.\(stateSuffix)"
                )
                percentage.font = Self.previewMenuBarFont
                percentage.textColor = .labelColor
                percentage.lineBreakMode = .byClipping
                percentage.setAccessibilityElement(false)
                presentationViews.append(percentage)
            }
            presentationViews.append(imageView)
            let presentation = NSStackView(views: presentationViews)
            presentation.orientation = .horizontal
            presentation.alignment = .centerY
            presentation.distribution = .fill
            presentation.spacing = 1
            presentation.setAccessibilityElement(false)
            presentation.translatesAutoresizingMaskIntoConstraints = false

            stateBox.addSubview(stateLabel)
            stateBox.addSubview(presentation)
            NSLayoutConstraint.activate([
                stateLabel.leadingAnchor.constraint(equalTo: stateBox.leadingAnchor, constant: 2),
                stateLabel.trailingAnchor.constraint(equalTo: stateBox.trailingAnchor, constant: -2),
                stateLabel.topAnchor.constraint(equalTo: stateBox.topAnchor, constant: 3),

                presentation.centerXAnchor.constraint(equalTo: stateBox.centerXAnchor),
                presentation.bottomAnchor.constraint(equalTo: stateBox.bottomAnchor, constant: -3),
                imageView.widthAnchor.constraint(equalToConstant: BatteryIcon.width),
                imageView.heightAnchor.constraint(equalToConstant: BatteryIcon.height),
                stateLabel.bottomAnchor.constraint(
                    lessThanOrEqualTo: presentation.topAnchor,
                    constant: -1
                ),
            ])
            return stateBox
        }
        let stateRow = NSStackView(views: stateViews)
        stateRow.orientation = .horizontal
        stateRow.alignment = .height
        stateRow.distribution = .fillEqually
        stateRow.spacing = SettingsStyle.iconStateGap
        stateRow.setAccessibilityElement(false)
        stateRow.translatesAutoresizingMaskIntoConstraints = false

        let primary = NSTextField(labelWithString: appearance.visibleTitle)
        primary.identifier = NSUserInterfaceItemIdentifier(
            "settings.menu-bar-icon.title.\(identifierSuffix)"
        )
        primary.font = .systemFont(ofSize: 13, weight: .semibold)
        primary.textColor = SettingsStyle.primaryText
        primary.alignment = .left
        primary.lineBreakMode = .byClipping
        primary.setAccessibilityElement(false)
        primary.translatesAutoresizingMaskIntoConstraints = false

        let secondary = NSTextField(labelWithString: appearance.visibleDetail)
        secondary.identifier = NSUserInterfaceItemIdentifier(
            "settings.menu-bar-icon.detail.\(identifierSuffix)"
        )
        secondary.setAccessibilityIdentifier(
            "settings.menu-bar-icon.detail.\(identifierSuffix)"
        )
        secondary.font = SettingsStyle.detailFont
        secondary.textColor = SettingsStyle.secondaryText
        secondary.alignment = .left
        secondary.lineBreakMode = .byClipping
        secondary.maximumNumberOfLines = 1
        secondary.setAccessibilityElement(false)
        secondary.translatesAutoresizingMaskIntoConstraints = false

        addSubview(primary)
        addSubview(secondary)
        addSubview(stateRow)
        NSLayoutConstraint.activate([
            primary.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            primary.topAnchor.constraint(equalTo: topAnchor, constant: 8),

            secondary.leadingAnchor.constraint(equalTo: primary.trailingAnchor, constant: 8),
            secondary.firstBaselineAnchor.constraint(equalTo: primary.firstBaselineAnchor),
            secondary.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -44),

            stateRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stateRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stateRow.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            stateRow.heightAnchor.constraint(equalToConstant: SettingsStyle.iconStateHeight),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        let becameFirstResponder = super.becomeFirstResponder()
        if becameFirstResponder {
            DispatchQueue.main.async { [weak self] in
                self?.needsDisplay = true
            }
        }
        return becameFirstResponder
    }

    override func resignFirstResponder() -> Bool {
        let resignedFirstResponder = super.resignFirstResponder()
        if resignedFirstResponder {
            DispatchQueue.main.async { [weak self] in
                self?.needsDisplay = true
            }
        }
        return resignedFirstResponder
    }

    override func accessibilityValue() -> Any? {
        NSNumber(value: state == .on)
    }

    var cardFillColor: NSColor {
        guard state == .on else { return SettingsStyle.surfaceBackground }
        return increaseContrast()
            ? SettingsStyle.increasedContrastSelection
            : SettingsStyle.selection
    }

    var cardBorderColor: NSColor {
        if state == .on {
            return increaseContrast()
                ? SettingsStyle.increasedContrastSelectionBorder
                : SettingsStyle.green
        }
        return increaseContrast()
            ? SettingsStyle.increasedContrastBorder
            : SettingsStyle.border
    }

    var cardBorderWidth: CGFloat {
        if state == .on { return increaseContrast() ? 3 : 2 }
        return increaseContrast() ? 2 : 1
    }

    func refreshContrastAppearance() {
        let increased = increaseContrast()
        stateBoxes.forEach {
            $0.borderWidth = increased ? 2 : 1
            $0.borderColor = increased
                ? SettingsStyle.increasedContrastBorder
                : SettingsStyle.border
        }
        needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, frame.contains(point) else { return nil }
        return self
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123, 126:
            onKeyboardCommand?(.previous)
        case 124, 125:
            onKeyboardCommand?(.next)
        case 115:
            onKeyboardCommand?(.first)
        case 119:
            onKeyboardCommand?(.last)
        case 49:
            performClick(nil)
        default:
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
#if DEBUG
        drawCountForTest += 1
#endif
        let inset = max(cardBorderWidth / 2, 1)
        let card = NSBezierPath(
            roundedRect: bounds.insetBy(dx: inset, dy: inset),
            xRadius: SettingsStyle.surfaceCornerRadius,
            yRadius: SettingsStyle.surfaceCornerRadius
        )
        cardFillColor.setFill()
        card.fill()
        cardBorderColor.setStroke()
        card.lineWidth = cardBorderWidth
        card.stroke()

        let radioY = isFlipped ? 15 : bounds.maxY - 29
        let radioRect = NSRect(
            x: bounds.maxX - 29,
            y: radioY,
            width: 14,
            height: 14
        )
        let radio = NSBezierPath(ovalIn: radioRect)
        cardBorderColor.setStroke()
        radio.lineWidth = state == .on ? 2 : 1.5
        radio.stroke()
        if state == .on {
            cardBorderColor.setFill()
            NSBezierPath(ovalIn: radioRect.insetBy(dx: 4, dy: 4)).fill()
        }

        if window?.firstResponder === self {
            NSColor.keyboardFocusIndicatorColor.setStroke()
            let focus = NSBezierPath(
                roundedRect: bounds.insetBy(dx: 4, dy: 4),
                xRadius: SettingsStyle.surfaceCornerRadius - 2,
                yRadius: SettingsStyle.surfaceCornerRadius - 2
            )
            focus.lineWidth = 2
            focus.stroke()
        }
    }
}

private final class MenuBarIconSettingsSectionController: NSObject,
    SettingsSectionController
{
    let identifier = "menu-bar-icon"
    let title = "Menu Bar Icon"
    let symbolName = "battery.100"
    let view = NSView()

    private let increaseContrast: () -> Bool
    private var buttons: [MenuBarIconAppearance: MenuBarIconCardButton] = [:]
    private var settingsObserver: NSObjectProtocol?

    init(increaseContrast: @escaping () -> Bool) {
        self.increaseContrast = increaseContrast
        super.init()
        buildView()
        installObserver()
        refreshSelection()
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
        refreshSelection()
    }

    private func buildView() {
        view.identifier = NSUserInterfaceItemIdentifier("settings.section.menu-bar-icon")

        let heading = NSTextField(labelWithString: title)
        heading.identifier = NSUserInterfaceItemIdentifier("settings.menu-bar-icon.heading")
        heading.font = SettingsStyle.headingFont
        heading.textColor = SettingsStyle.headingText
        heading.setAccessibilityLabel(title)
        heading.translatesAutoresizingMaskIntoConstraints = false

        let subtitle = NSTextField(
            labelWithString: "Choose how Wattson appears in the menu bar."
        )
        subtitle.identifier = NSUserInterfaceItemIdentifier("settings.menu-bar-icon.subtitle")
        subtitle.font = SettingsStyle.detailFont
        subtitle.textColor = SettingsStyle.secondaryText
        subtitle.translatesAutoresizingMaskIntoConstraints = false

        let orderedButtons = MenuBarIconAppearance.allCases.map { appearance in
            let previews = MenuBarIconPreviewState.allCases.map { previewState in
                let snapshot = previewState.snapshot
                let image = BatteryIcon.image(
                    for: snapshot,
                    mode: previewState.mode,
                    pressed: false,
                    style: appearance.iconStyle
                )
                return (state: previewState, image: image)
            }
            let button = MenuBarIconCardButton(
                appearance: appearance,
                previews: previews,
                increaseContrast: increaseContrast
            )
            button.target = self
            button.action = #selector(selectAppearance(_:))
            button.onKeyboardCommand = { [weak self] command in
                self?.handleKeyboard(command, from: appearance)
            }
            button.translatesAutoresizingMaskIntoConstraints = false
            buttons[appearance] = button
            return button
        }

        let group = NSStackView(views: orderedButtons)
        group.identifier = NSUserInterfaceItemIdentifier("settings.menu-bar-icon.group")
        group.orientation = .vertical
        group.alignment = .leading
        group.distribution = .fillEqually
        group.spacing = SettingsStyle.iconCardGap
        group.setAccessibilityElement(true)
        group.setAccessibilityRole(.radioGroup)
        group.setAccessibilityLabel(title)
        group.setAccessibilityHelp(
            "Choose a complete Wattson or macOS menu-bar battery presentation."
        )
        group.setAccessibilityChildren(orderedButtons)
        group.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(heading)
        view.addSubview(subtitle)
        view.addSubview(group)
        NSLayoutConstraint.activate([
            heading.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 2),
            heading.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            heading.topAnchor.constraint(equalTo: view.topAnchor, constant: -3),

            subtitle.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 2),
            subtitle.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            subtitle.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 8),

            group.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            group.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            group.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 14),
            group.heightAnchor.constraint(equalToConstant: SettingsStyle.iconCardGroupHeight),
        ])
        orderedButtons.forEach {
            $0.widthAnchor.constraint(equalTo: group.widthAnchor).isActive = true
            $0.heightAnchor.constraint(
                equalToConstant: SettingsStyle.iconCardHeight
            ).isActive = true
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
                self.refreshSelection()
                return
            }
            switch change {
            case .menuBarIconStyle, .menuBarPercentage:
                self.refreshSelection()
            case .module:
                break
            }
        }
    }

    private func refreshSelection() {
        let selected = MenuBarIconAppearance(
            iconStyle: Settings.menuBarIconStyle,
            showsPercentage: Settings.showsMenuBarPercentage
        )
        for (appearance, button) in buttons {
            button.state = appearance == selected ? .on : .off
            button.needsDisplay = true
        }
    }

    @objc private func selectAppearance(_ sender: MenuBarIconCardButton) {
        select(sender.menuBarAppearance, movingFocus: false)
    }

    private func handleKeyboard(
        _ command: MenuBarIconCardKeyCommand,
        from current: MenuBarIconAppearance
    ) {
        let appearances = MenuBarIconAppearance.allCases
        guard let currentIndex = appearances.firstIndex(of: current) else { return }
        let targetIndex: Int
        switch command {
        case .previous:
            targetIndex = (currentIndex - 1 + appearances.count) % appearances.count
        case .next:
            targetIndex = (currentIndex + 1) % appearances.count
        case .first:
            targetIndex = appearances.startIndex
        case .last:
            targetIndex = appearances.index(before: appearances.endIndex)
        }
        select(appearances[targetIndex], movingFocus: true)
    }

    private func select(
        _ appearance: MenuBarIconAppearance,
        movingFocus: Bool
    ) {
        Settings.setMenuBarAppearance(
            iconStyle: appearance.iconStyle,
            showsPercentage: appearance.showsPercentage
        )
        refreshSelection()
        if movingFocus, let button = buttons[appearance] {
            button.window?.makeFirstResponder(button)
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
        subtitle.font = SettingsStyle.detailFont
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
            subtitle.bottomAnchor.constraint(equalTo: grid.topAnchor, constant: -10),

            grid.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            grid.topAnchor.constraint(equalTo: view.topAnchor, constant: 66),
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
        paragraphStyle.lineSpacing = 3
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
            preview.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            preview.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            preview.widthAnchor.constraint(equalToConstant: SettingsStyle.modulePreviewSize.width),
            preview.heightAnchor.constraint(equalToConstant: SettingsStyle.modulePreviewSize.height),

            primary.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            primary.trailingAnchor.constraint(lessThanOrEqualTo: button.leadingAnchor, constant: -8),
            primary.topAnchor.constraint(equalTo: card.topAnchor, constant: 88),

            detail.leadingAnchor.constraint(equalTo: primary.leadingAnchor),
            detail.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            detail.topAnchor.constraint(equalTo: primary.bottomAnchor, constant: 6),
            detail.bottomAnchor.constraint(lessThanOrEqualTo: card.bottomAnchor, constant: -12),

            button.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
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

    private let sections: [SettingsSectionController]
    private let increaseContrast: () -> Bool
    private let sidebar = NSTableView()
    private let contentHost = NSView()
    private let divider: DynamicSeparatorView
    private var accessibilityDisplayObserver: NSObjectProtocol?
    private var selectedSectionIndex = 0

    static func defaultSections(
        dependencies: SettingsWindowDependencies = .live
    ) -> [SettingsSectionController] {
        [
            GeneralSettingsSectionController(dependencies: dependencies),
            MenuBarIconSettingsSectionController(
                increaseContrast: dependencies.increaseContrast
            ),
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
        // This utility window has one intentionally compact composition.
        // Omitting `.resizable` keeps AppKit's native zoom control disabled.
        window.contentMinSize = SettingsStyle.contentSize
        window.contentMaxSize = SettingsStyle.contentSize
        window.isMovableByWindowBackground = true
        window.autorecalculatesKeyViewLoop = false

        let hadSavedFrame = frameAutosaveName.flatMap {
            UserDefaults.standard.string(forKey: "NSWindow Frame \($0)")
        } != nil
        super.init(window: window)

        configureContent()
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
        iconTile.identifier = NSUserInterfaceItemIdentifier("settings.sidebar.identity.tile")
        iconTile.boxType = .custom
        iconTile.titlePosition = .noTitle
        iconTile.cornerRadius = 9
        iconTile.borderWidth = 1
        iconTile.borderColor = SettingsStyle.border
        iconTile.fillColor = SettingsStyle.tileBackground
        iconTile.translatesAutoresizingMaskIntoConstraints = false

        let icon = ECGIconView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        iconTile.addSubview(icon)

        let name = NSTextField(labelWithString: "Wattson")
        name.font = .systemFont(ofSize: 16, weight: .semibold)
        name.textColor = SettingsStyle.headingText
        name.translatesAutoresizingMaskIntoConstraints = false

        identity.addSubview(iconTile)
        identity.addSubview(name)
        NSLayoutConstraint.activate([
            iconTile.leadingAnchor.constraint(equalTo: identity.leadingAnchor, constant: 16),
            iconTile.centerYAnchor.constraint(equalTo: identity.centerYAnchor),
            iconTile.widthAnchor.constraint(equalToConstant: SettingsStyle.identityTileSize),
            iconTile.heightAnchor.constraint(equalToConstant: SettingsStyle.identityTileSize),
            icon.centerXAnchor.constraint(equalTo: iconTile.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconTile.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 30),
            icon.heightAnchor.constraint(equalToConstant: 30),
            name.leadingAnchor.constraint(equalTo: iconTile.trailingAnchor, constant: 10),
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

        let imageView = NSImageView()
        imageView.image = NSImage(
            systemSymbolName: section.symbolName,
            accessibilityDescription: nil
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        )
        imageView.contentTintColor = .labelColor
        imageView.imageScaling = .scaleNone
        let icon: NSView = imageView
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
            icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
            icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 20),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            title.trailingAnchor.constraint(equalTo: cell.trailingAnchor),
            title.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        cell.setAccessibilityLabel(section.title)
        cell.setAccessibilityHelp("Show the \(section.title) settings page.")
        return cell
    }

#if DEBUG
    var windowForTest: NSWindow? { window }
    var trafficLightButtonsForTest: [NSButton] {
        guard let window else { return [] }
        return [
            window.standardWindowButton(.closeButton),
            window.standardWindowButton(.miniaturizeButton),
            window.standardWindowButton(.zoomButton),
        ].compactMap { $0 }
    }
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

    func iconCardBorderWidthForTest(_ accessibilityLabel: String) -> CGFloat {
        iconCardForTest(accessibilityLabel)?.cardBorderWidth ?? -1
    }

    func iconCardFillColorForTest(_ accessibilityLabel: String) -> NSColor? {
        iconCardForTest(accessibilityLabel)?.cardFillColor
    }

    func iconCardBorderColorForTest(_ accessibilityLabel: String) -> NSColor? {
        iconCardForTest(accessibilityLabel)?.cardBorderColor
    }

    func iconCardDrawCountForTest(_ accessibilityLabel: String) -> Int {
        iconCardForTest(accessibilityLabel)?.drawCountForTest ?? -1
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

    private func iconCardForTest(
        _ accessibilityLabel: String
    ) -> MenuBarIconCardButton? {
        for section in sections {
            if let match = switchButtons(in: section.view)
                .compactMap({ $0 as? MenuBarIconCardButton })
                .first(where: { $0.accessibilityLabel() == accessibilityLabel }) {
                return match
            }
        }
        return nil
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
    var sidebarVisibleRectForTest: NSRect { sidebar.visibleRect }
    func sidebarRectForRowForTest(_ row: Int) -> NSRect { sidebar.rect(ofRow: row) }
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
