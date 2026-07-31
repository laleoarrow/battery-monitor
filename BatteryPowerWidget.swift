import AppKit
import CoreGraphics
import Darwin
import Foundation
import WidgetKit

private let currentConfigVersion = 4
private let fallbackAppVersion = "1.3.0"
private let widgetWidth: CGFloat = 319
private let widgetHeight: CGFloat = 100
private let widgetKind = "BatteryPowerSystemWidget"
private let widgetReloadRequestInterval: TimeInterval = 5
private let githubReleasesAPIURL = URL(string: "https://api.github.com/repos/laleoarrow/battery-monitor/releases/latest")!
private let githubReleasesURL = URL(string: "https://github.com/laleoarrow/battery-monitor/releases")!
private let githubIssueURL = URL(string: "https://github.com/laleoarrow/battery-monitor/issues/new")!

private let panelColor = NSColor(calibratedRed: 0x17 / 255, green: 0x19 / 255, blue: 0x1F / 255, alpha: 1)
private let borderColor = NSColor(calibratedRed: 0x34 / 255, green: 0x39 / 255, blue: 0x45 / 255, alpha: 1)
private let innerBorderColor = NSColor(calibratedRed: 0x22 / 255, green: 0x27 / 255, blue: 0x33 / 255, alpha: 1)
private let mutedColor = NSColor(calibratedRed: 0xA6 / 255, green: 0xAB / 255, blue: 0xB6 / 255, alpha: 1)
private let textColor = NSColor(calibratedRed: 0xF8 / 255, green: 0xFA / 255, blue: 0xFC / 255, alpha: 1)
private let greenColor = NSColor(calibratedRed: 0x34 / 255, green: 0xE3 / 255, blue: 0x6E / 255, alpha: 1)
private let blueColor = NSColor(calibratedRed: 0x4A / 255, green: 0xA3 / 255, blue: 0xFF / 255, alpha: 1)
private let redColor = NSColor(calibratedRed: 0xFF / 255, green: 0x45 / 255, blue: 0x3A / 255, alpha: 1)

enum DockDisplayMode: String, CaseIterable {
    case appIcon = "app_icon"
    case totalPower = "total_power"
    case systemPower = "system_power"
    case chargePower = "charge_power"

    var title: String {
        switch self {
        case .appIcon: return "App 图标"
        case .totalPower: return "动态总功率"
        case .systemPower: return "动态负载功率"
        case .chargePower: return "动态充电功率"
        }
    }

    var shortTitle: String {
        switch self {
        case .appIcon: return "图标"
        case .totalPower: return "总功率"
        case .systemPower: return "负载"
        case .chargePower: return "充电"
        }
    }

    func dockMetric(from snapshot: PowerSnapshot) -> (label: String, value: Double, color: NSColor) {
        switch self {
        case .appIcon:
            return ("", 0, textColor)
        case .totalPower:
            return ("总功率", snapshot.totalW, snapshot.heroColor)
        case .systemPower:
            return ("负载", snapshot.systemW, snapshot.heroColor)
        case .chargePower:
            let color = snapshot.chargeW > 0.05 ? greenColor : mutedColor
            return ("充电", snapshot.chargeW, color)
        }
    }
}

struct WidgetConfig {
    var configVersion: Int = currentConfigVersion
    var x: Int = 200
    var y: Int = 100
    var pinned: Bool = false
    var showDockIcon: Bool = false
    var dockDisplayMode: DockDisplayMode = .appIcon
}

// The desktop panel predates the signed power model in Core/PowerSnapshot.swift.
// These accessors let it keep reading the fields it always has, so its drawing
// code needs no changes. Core stays the single source of truth.
extension PowerSnapshot {
    var charging: Bool { state == .charging }
    var chargeW: Double { max(batteryW, 0) }
    var dischargeW: Double { max(-batteryW, 0) }
    var totalW: Double { totalInputW }

    var heroColor: NSColor {
        switch state {
        case .charging: return greenColor
        case .pluggedIdle: return blueColor
        case .onBattery, .mixedSupply: return textColor
        }
    }

    var statusColor: NSColor {
        if percent <= 20 { return redColor }
        switch state {
        case .charging: return greenColor
        case .pluggedIdle: return blueColor
        case .onBattery: return mutedColor
        // The battery is draining while plugged in — an underpowered adapter.
        case .mixedSupply: return NSColor.systemOrange
        }
    }
}

final class ConfigStore {
    static let shared = ConfigStore()
    private let url: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Wattson", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("config.json")
    }()

    func load() -> WidgetConfig {
        guard let data = try? Data(contentsOf: url) else {
            return WidgetConfig()
        }

        if let raw = String(data: data, encoding: .utf8), raw.contains(","), !raw.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") {
            let parts = raw.split(separator: ",", maxSplits: 1).map(String.init)
            if parts.count == 2, let x = Int(parts[0]), let y = Int(parts[1]) {
                return WidgetConfig(x: x, y: y)
            }
        }

        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return WidgetConfig()
        }

        let savedVersion = object["config_version"] as? Int ?? 0
        var config = WidgetConfig()
        config.x = object["x"] as? Int ?? config.x
        config.y = object["y"] as? Int ?? config.y
        config.pinned = object["pinned"] as? Bool ?? config.pinned
        config.showDockIcon = object["show_dock_icon"] as? Bool ?? config.showDockIcon
        if let rawMode = object["dock_display_mode"] as? String,
           let mode = DockDisplayMode(rawValue: rawMode) {
            config.dockDisplayMode = mode
        }

        if savedVersion < currentConfigVersion {
            config.configVersion = currentConfigVersion
        }
        return config
    }

    func save(_ config: WidgetConfig) {
        let object: [String: Any] = [
            "config_version": config.configVersion,
            "x": config.x,
            "y": config.y,
            "pinned": config.pinned,
            "show_dock_icon": config.showDockIcon,
            "dock_display_mode": config.dockDisplayMode.rawValue,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: object, options: []) {
            try? data.write(to: url)
        }
    }
}

private enum WidgetSnapshotStore {
    private static var snapshotURL: URL {
        realHomeDirectory()
            .appendingPathComponent("Library/Application Support/Wattson", isDirectory: true)
            .appendingPathComponent("widget-snapshot.json")
    }

    @discardableResult
    static func save(_ snapshot: PowerSnapshot) -> Bool {
        let payload: [String: Any] = [
            "percent": snapshot.percent,
            "plugged": snapshot.plugged,
            "charging": snapshot.charging,
            "systemW": snapshot.systemW,
            "chargeW": snapshot.chargeW,
            "dischargeW": snapshot.dischargeW,
            "updatedAt": Date().timeIntervalSince1970,
        ]
        let url = snapshotURL
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: payload)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    private static func realHomeDirectory() -> URL {
        if let passwd = getpwuid(getuid()),
           let home = passwd.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: home), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }
}

final class BatteryView: NSView {
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    var snapshot = PowerSnapshot() {
        didSet { needsDisplay = true }
    }

    weak var controller: AppController?
    private var dragStart: NSPoint?
    private var frameStart: NSPoint?
    private var pulsePhase = 0.0

    override var isOpaque: Bool { false }
    override var isFlipped: Bool { true }

    func advancePulse() {
        pulsePhase += 0.32
        if pulsePhase > Double.pi * 2 {
            pulsePhase -= Double.pi * 2
        }
        if snapshot.charging || snapshot.plugged {
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.clear.setFill()
        dirtyRect.fill()

        let shell = bounds.insetBy(dx: 1, dy: 1)
        let outer = NSBezierPath(roundedRect: shell, xRadius: 22, yRadius: 22)
        panelColor.setFill()
        outer.fill()
        borderColor.setStroke()
        outer.lineWidth = 1
        outer.stroke()

        let inner = NSBezierPath(roundedRect: shell.insetBy(dx: 2, dy: 2), xRadius: 20, yRadius: 20)
        innerBorderColor.setStroke()
        inner.lineWidth = 1
        inner.stroke()

        let totalText = String(format: "%.1f", snapshot.totalW)
        let heroSize = fittedTextSize(totalText, maxWidth: 150, sizes: [42, 40, 38, 36])
        drawText(totalText, at: NSPoint(x: 20, y: 14), size: heroSize, weight: .bold, color: snapshot.heroColor)
        let totalWidth = textWidth(totalText, size: heroSize, weight: .bold)
        drawText("W", at: NSPoint(x: max(20 + totalWidth + 8, 108), y: 30), size: 20, weight: .bold, color: mutedColor)

        let percentValue = "\(snapshot.percent)"
        let percentSign = "%"
        let percentSignSize: CGFloat = 20
        let percentSignWidth = textWidth(percentSign, size: percentSignSize, weight: .bold)
        let percentSignX = widgetWidth - 19 - percentSignWidth
        let percentValueWidth = textWidth(percentValue, size: heroSize, weight: .bold)
        let percentValueX = percentSignX - 7 - percentValueWidth
        let maximumPulseRadius: CGFloat = 16
        let dotToValueGap: CGFloat = 4
        let statusDotX = percentValueX - maximumPulseRadius - dotToValueGap

        drawStatusDot(center: NSPoint(x: statusDotX, y: 42))
        drawText(percentValue, at: NSPoint(x: percentValueX, y: 14), size: heroSize, weight: .bold, color: snapshot.statusColor)
        drawText(percentSign, at: NSPoint(x: percentSignX, y: 30), size: percentSignSize, weight: .bold, color: mutedColor)

        let lowerRowY: CGFloat = 70
        drawText("负载", at: NSPoint(x: 20, y: lowerRowY), size: 17, weight: .bold, color: mutedColor)
        drawText(formatW(snapshot.systemW), at: NSPoint(x: 55, y: lowerRowY), size: 17, weight: .bold, color: textColor)

        let battery = batteryCompact()
        drawText(battery.label, at: NSPoint(x: 142, y: lowerRowY), size: 17, weight: .bold, color: mutedColor)
        drawText(battery.value, at: NSPoint(x: 177, y: lowerRowY), size: 17, weight: .bold, color: battery.color)

        let time = timeString()
        let timeWidth = textWidth(time, size: 17, weight: .bold)
        drawText(time, at: NSPoint(x: widgetWidth - 19 - timeWidth, y: lowerRowY), size: 17, weight: .bold, color: mutedColor)
    }

    override func mouseDown(with event: NSEvent) {
        dragStart = NSEvent.mouseLocation
        frameStart = window?.frame.origin
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStart, let frameStart, let window else { return }
        let current = NSEvent.mouseLocation
        let origin = NSPoint(x: frameStart.x + current.x - dragStart.x, y: frameStart.y + current.y - dragStart.y)
        window.setFrameOrigin(origin)
    }

    override func mouseUp(with event: NSEvent) {
        controller?.persistPosition()
    }

    override func rightMouseDown(with event: NSEvent) {
        controller?.showMenu(event: event)
    }

    private func batteryCompact() -> (label: String, value: String, color: NSColor) {
        if snapshot.chargeW > 0.05 {
            return ("充电", formatW(snapshot.chargeW), greenColor)
        }
        if snapshot.dischargeW > 0.05 {
            return ("放电", formatW(snapshot.dischargeW), snapshot.percent <= 20 ? redColor : textColor)
        }
        return ("电池", "0.0 W", mutedColor)
    }

    private func formatW(_ value: Double) -> String {
        String(format: "%.1f W", value)
    }

    private func timeString() -> String {
        Self.timeFormatter.string(from: Date())
    }

    private func drawStatusDot(center: NSPoint) {
        if snapshot.charging || snapshot.plugged {
            let pulse = (sin(pulsePhase) + 1.0) / 2.0
            drawCircle(center: center, diameter: CGFloat(24.0 + 8.0 * pulse), color: snapshot.statusColor.withAlphaComponent(CGFloat(0.10 + 0.14 * pulse)))
            drawCircle(center: center, diameter: CGFloat(15.0 + 3.0 * pulse), color: snapshot.statusColor.withAlphaComponent(CGFloat(0.16 + 0.16 * pulse)))
        }
        drawCircle(center: center, diameter: 9, color: snapshot.statusColor)
    }

    private func drawCircle(center: NSPoint, diameter: CGFloat, color: NSColor) {
        color.setFill()
        NSBezierPath(
            ovalIn: NSRect(
                x: center.x - diameter / 2,
                y: center.y - diameter / 2,
                width: diameter,
                height: diameter
            )
        ).fill()
    }

    private func drawText(_ text: String, at point: NSPoint, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
        ]
        (text as NSString).draw(at: point, withAttributes: attrs)
    }

    private func textWidth(_ text: String, size: CGFloat, weight: NSFont.Weight) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight)]
        return (text as NSString).size(withAttributes: attrs).width
    }

    private func fittedTextSize(_ text: String, maxWidth: CGFloat, sizes: [CGFloat]) -> CGFloat {
        for size in sizes {
            if textWidth(text, size: size, weight: .bold) <= maxWidth {
                return size
            }
        }
        return sizes.last ?? 36
    }
}

final class WidgetWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class DockPowerView: NSView {
    var snapshot = PowerSnapshot() {
        didSet { needsDisplay = true }
    }
    var mode: DockDisplayMode = .totalPower {
        didSet { needsDisplay = true }
    }

    override var isOpaque: Bool { false }
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.clear.setFill()
        dirtyRect.fill()

        let tile = bounds.insetBy(dx: 8, dy: 8)
        let background = NSBezierPath(roundedRect: tile, xRadius: 28, yRadius: 28)
        panelColor.setFill()
        background.fill()
        borderColor.setStroke()
        background.lineWidth = 3
        background.stroke()

        let metric = mode.dockMetric(from: snapshot)
        let valueText = formatDockW(metric.value)
        let valueSize = fittedTextSize(valueText, maxWidth: 78, sizes: [42, 38, 34, 30])
        let valueWidth = textWidth(valueText, size: valueSize, weight: .bold)
        let unitWidth = textWidth("W", size: 17, weight: .bold)
        let totalWidth = valueWidth + 5 + unitWidth
        let valueX = max((bounds.width - totalWidth) / 2, 12)

        drawText(valueText, at: NSPoint(x: valueX, y: 34), size: valueSize, weight: .bold, color: metric.color)
        drawText("W", at: NSPoint(x: valueX + valueWidth + 5, y: 49), size: 17, weight: .bold, color: mutedColor)
        drawCenteredText(metric.label, y: 84, size: 17, weight: .bold, color: textColor)
    }

    private func formatDockW(_ value: Double) -> String {
        if abs(value) >= 100 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }

    private func drawCenteredText(_ text: String, y: CGFloat, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
        let width = textWidth(text, size: size, weight: weight)
        drawText(text, at: NSPoint(x: (bounds.width - width) / 2, y: y), size: size, weight: weight, color: color)
    }

    private func drawText(_ text: String, at point: NSPoint, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
        ]
        (text as NSString).draw(at: point, withAttributes: attrs)
    }

    private func textWidth(_ text: String, size: CGFloat, weight: NSFont.Weight) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight)]
        return (text as NSString).size(withAttributes: attrs).width
    }

    private func fittedTextSize(_ text: String, maxWidth: CGFloat, sizes: [CGFloat]) -> CGFloat {
        for size in sizes {
            if textWidth(text, size: size, weight: .bold) <= maxWidth {
                return size
            }
        }
        return sizes.last ?? 30
    }
}

final class SettingsWindowController: NSWindowController {
    private weak var appController: AppController?
    private let showDockCheckbox = NSButton(checkboxWithTitle: "在 Dock 栏显示", target: nil, action: nil)
    private let dockModeControl = NSSegmentedControl(
        labels: DockDisplayMode.allCases.map(\.shortTitle),
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let checkUpdatesButton = NSButton(title: "检查更新", target: nil, action: nil)
    private let openIssueButton = NSButton(title: "GitHub Issue", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")

    init(config: WidgetConfig, appController: AppController) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 250),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "设置"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = .floating

        super.init(window: panel)
        self.appController = appController
        buildContent(in: panel)
        refresh(config)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func refresh(_ config: WidgetConfig) {
        showDockCheckbox.state = config.showDockIcon ? .on : .off
        if let selected = DockDisplayMode.allCases.firstIndex(of: config.dockDisplayMode) {
            dockModeControl.selectedSegment = selected
        }
        dockModeControl.isEnabled = config.showDockIcon
    }

    func setUpdateStatus(_ text: String, isError: Bool = false) {
        statusLabel.stringValue = text
        statusLabel.textColor = isError ? redColor : mutedColor
    }

    private func buildContent(in panel: NSPanel) {
        let root = NSVisualEffectView()
        root.material = .hudWindow
        root.blendingMode = .behindWindow
        root.state = .active
        root.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = root

        let titleLabel = NSTextField(labelWithString: "电池功率设置")
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        titleLabel.textColor = textColor

        showDockCheckbox.target = self
        showDockCheckbox.action = #selector(showDockChanged(_:))
        showDockCheckbox.font = .systemFont(ofSize: 14, weight: .medium)
        showDockCheckbox.contentTintColor = textColor

        dockModeControl.target = self
        dockModeControl.action = #selector(dockModeChanged(_:))
        dockModeControl.segmentStyle = .rounded
        for index in 0..<DockDisplayMode.allCases.count {
            dockModeControl.setWidth(72, forSegment: index)
        }

        let modeLabel = NSTextField(labelWithString: "Dock 内容")
        modeLabel.font = .systemFont(ofSize: 13, weight: .medium)
        modeLabel.textColor = mutedColor

        let modeRow = NSStackView(views: [modeLabel, dockModeControl])
        modeRow.orientation = .horizontal
        modeRow.alignment = .centerY
        modeRow.distribution = .gravityAreas
        modeRow.spacing = 14

        checkUpdatesButton.target = self
        checkUpdatesButton.action = #selector(checkUpdates(_:))
        checkUpdatesButton.bezelStyle = .rounded
        checkUpdatesButton.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)
        checkUpdatesButton.imagePosition = .imageLeading

        openIssueButton.target = self
        openIssueButton.action = #selector(openIssue(_:))
        openIssueButton.bezelStyle = .rounded
        openIssueButton.image = NSImage(systemSymbolName: "exclamationmark.bubble", accessibilityDescription: nil)
        openIssueButton.imagePosition = .imageLeading

        let buttonRow = NSStackView(views: [checkUpdatesButton, openIssueButton])
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.distribution = .fillEqually
        buttonRow.spacing = 10

        statusLabel.font = .systemFont(ofSize: 12, weight: .regular)
        statusLabel.textColor = mutedColor
        statusLabel.maximumNumberOfLines = 2
        statusLabel.lineBreakMode = .byWordWrapping

        let separatorLine = separator()
        let stack = NSStackView(views: [titleLabel, showDockCheckbox, modeRow, separatorLine, buttonRow, statusLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
            modeRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            separatorLine.widthAnchor.constraint(equalTo: stack.widthAnchor),
            buttonRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            dockModeControl.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
        ])
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    @objc private func showDockChanged(_ sender: NSButton) {
        appController?.setShowDockIcon(sender.state == .on)
    }

    @objc private func dockModeChanged(_ sender: NSSegmentedControl) {
        guard sender.selectedSegment >= 0, sender.selectedSegment < DockDisplayMode.allCases.count else {
            return
        }
        appController?.setDockDisplayMode(DockDisplayMode.allCases[sender.selectedSegment])
    }

    @objc private func checkUpdates(_ sender: NSButton) {
        appController?.checkForUpdates()
    }

    @objc private func openIssue(_ sender: NSButton) {
        appController?.openGitHubIssue()
    }
}

final class AppController: NSObject, NSApplicationDelegate {
    private var config = ConfigStore.shared.load()
    private let view = BatteryView(frame: NSRect(x: 0, y: 0, width: widgetWidth, height: widgetHeight))
    private let dockView = DockPowerView(frame: NSRect(x: 0, y: 0, width: 128, height: 128))
    private var window: WidgetWindow?
    private var settingsController: SettingsWindowController?
    private var timer: Timer?
    private var pulseTimer: Timer?
    private var latestSnapshot = PowerSnapshot()
    private var lastWidgetReloadRequest = Date.distantPast

    func applicationDidFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.disableAutomaticTermination("Battery power monitor keeps a live floating window and widget snapshot current.")
        applyDockPresentation()
        ConfigStore.shared.save(config)
        view.controller = self

        let panel = WidgetWindow(
            contentRect: initialFrame(),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.contentView = view
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.setFrameTopLeftPoint(initialTopLeftPoint())
        window = panel
        applyWindowMode()
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)

        update()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.update()
        }
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in
            self?.view.advancePulse()
        }
    }

    func showMenu(event: NSEvent) {
        let menu = NSMenu()
        let pinnedItem = NSMenuItem(title: "\(config.pinned ? "✓ " : "")置顶", action: #selector(togglePinned), keyEquivalent: "")
        pinnedItem.target = self
        menu.addItem(pinnedItem)
        let settingsItem = NSMenuItem(title: "设置…", action: #selector(showSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    func persistPosition() {
        guard let window else { return }
        config.x = Int(window.frame.minX.rounded())
        if let screen = window.screen ?? NSScreen.main {
            config.y = Int((screen.frame.maxY - window.frame.maxY).rounded())
        }
        ConfigStore.shared.save(config)
    }

    @objc private func togglePinned() {
        config.pinned.toggle()
        ConfigStore.shared.save(config)
        applyWindowMode()
    }

    @objc private func showSettings() {
        if settingsController == nil {
            settingsController = SettingsWindowController(config: config, appController: self)
        }
        settingsController?.refresh(config)
        settingsController?.setUpdateStatus("")
        settingsController?.showWindow(nil)
        settingsController?.window?.center()
        settingsController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() {
        persistPosition()
        NSApp.terminate(nil)
    }

    func setShowDockIcon(_ show: Bool) {
        config.showDockIcon = show
        ConfigStore.shared.save(config)
        settingsController?.refresh(config)
        applyDockPresentation()
    }

    func setDockDisplayMode(_ mode: DockDisplayMode) {
        config.dockDisplayMode = mode
        ConfigStore.shared.save(config)
        settingsController?.refresh(config)
        applyDockPresentation()
    }

    func checkForUpdates() {
        settingsController?.setUpdateStatus("正在检查更新…")
        var request = URLRequest(url: githubReleasesAPIURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("battery-monitor/\(appVersionString())", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.handleUpdateResponse(data: data, response: response, error: error)
            }
        }.resume()
    }

    func openGitHubIssue() {
        NSWorkspace.shared.open(githubIssueURL)
    }

    private func update() {
        let snapshot = BatterySampler.sample() ?? PowerSnapshot()
        latestSnapshot = snapshot
        view.snapshot = snapshot
        updateDockTile()
        syncWidgetIfNeeded()
    }

    private func applyWindowMode() {
        guard let window else { return }
        window.level = config.pinned ? .floating : .normal
        window.collectionBehavior = []
        window.alphaValue = 1
        window.orderFrontRegardless()
    }

    private func applyDockPresentation() {
        if config.showDockIcon {
            NSApp.setActivationPolicy(.regular)
            if config.dockDisplayMode == .appIcon {
                NSApp.dockTile.contentView = nil
                NSApp.dockTile.badgeLabel = nil
            } else {
                dockView.mode = config.dockDisplayMode
                dockView.snapshot = latestSnapshot
                NSApp.dockTile.contentView = dockView
                NSApp.dockTile.badgeLabel = nil
            }
            NSApp.dockTile.display()
        } else {
            NSApp.dockTile.contentView = nil
            NSApp.dockTile.badgeLabel = nil
            NSApp.dockTile.display()
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private func updateDockTile() {
        guard config.showDockIcon, config.dockDisplayMode != .appIcon else { return }
        dockView.mode = config.dockDisplayMode
        dockView.snapshot = latestSnapshot
        if NSApp.dockTile.contentView !== dockView {
            NSApp.dockTile.contentView = dockView
        }
        NSApp.dockTile.display()
    }

    private func syncWidgetIfNeeded() {
        let now = Date()
        guard now.timeIntervalSince(lastWidgetReloadRequest) >= widgetReloadRequestInterval else {
            return
        }
        lastWidgetReloadRequest = now
        guard WidgetSnapshotStore.save(latestSnapshot) else {
            return
        }
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }

    private func handleUpdateResponse(data: Data?, response: URLResponse?, error: Error?) {
        if let error {
            settingsController?.setUpdateStatus("检查失败：\(error.localizedDescription)", isError: true)
            return
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), let data else {
            settingsController?.setUpdateStatus("没有读取到 GitHub Release。", isError: true)
            showReleaseFallbackAlert(message: "当前无法读取最新 Release，可以打开发布页手动查看。")
            return
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let latestTag = object["tag_name"] as? String else {
            settingsController?.setUpdateStatus("Release 响应格式不符合预期。", isError: true)
            return
        }

        let current = appVersionString()
        let releaseURL = (object["html_url"] as? String).flatMap(URL.init(string:)) ?? githubReleasesURL
        if compareVersions(latestTag, current) == .orderedDescending {
            settingsController?.setUpdateStatus("发现新版本 \(latestTag)。")
            showUpdateAlert(latestTag: latestTag, releaseURL: releaseURL)
        } else {
            settingsController?.setUpdateStatus("已是最新版：\(current)")
        }
    }

    private func showUpdateAlert(latestTag: String, releaseURL: URL) {
        let alert = NSAlert()
        alert.messageText = "发现新版本 \(latestTag)"
        alert.informativeText = "可以打开 GitHub 发布页下载最新版本。"
        alert.addButton(withTitle: "打开发布页")
        alert.addButton(withTitle: "稍后")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(releaseURL)
        }
    }

    private func showReleaseFallbackAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = "检查更新"
        alert.informativeText = message
        alert.addButton(withTitle: "打开发布页")
        alert.addButton(withTitle: "关闭")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(githubReleasesURL)
        }
    }

    private func appVersionString() -> String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? fallbackAppVersion
    }

    private func compareVersions(_ left: String, _ right: String) -> ComparisonResult {
        let leftParts = versionParts(left)
        let rightParts = versionParts(right)
        for index in 0..<max(leftParts.count, rightParts.count) {
            let leftValue = index < leftParts.count ? leftParts[index] : 0
            let rightValue = index < rightParts.count ? rightParts[index] : 0
            if leftValue < rightValue { return .orderedAscending }
            if leftValue > rightValue { return .orderedDescending }
        }
        return .orderedSame
    }

    private func versionParts(_ version: String) -> [Int] {
        let cleaned = version.replacingOccurrences(of: #"^[vV]"#, with: "", options: .regularExpression)
        return cleaned.split(separator: ".").map { part in
            let digits = part.prefix { $0.isNumber }
            return Int(digits) ?? 0
        }
    }

    private func initialFrame() -> NSRect {
        let topLeft = initialTopLeftPoint()
        return NSRect(x: topLeft.x, y: topLeft.y - widgetHeight, width: widgetWidth, height: widgetHeight)
    }

    private func initialTopLeftPoint() -> NSPoint {
        let screen = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSPoint(x: CGFloat(config.x), y: screen.maxY - CGFloat(config.y))
    }
}

