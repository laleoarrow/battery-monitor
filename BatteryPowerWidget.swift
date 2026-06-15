import AppKit
import CoreGraphics
import Foundation

private let currentConfigVersion = 2
private let widgetWidth: CGFloat = 319
private let widgetHeight: CGFloat = 90

private let panelColor = NSColor(calibratedRed: 0x17 / 255, green: 0x19 / 255, blue: 0x1F / 255, alpha: 1)
private let borderColor = NSColor(calibratedRed: 0x34 / 255, green: 0x39 / 255, blue: 0x45 / 255, alpha: 1)
private let innerBorderColor = NSColor(calibratedRed: 0x22 / 255, green: 0x27 / 255, blue: 0x33 / 255, alpha: 1)
private let mutedColor = NSColor(calibratedRed: 0xA6 / 255, green: 0xAB / 255, blue: 0xB6 / 255, alpha: 1)
private let textColor = NSColor(calibratedRed: 0xF8 / 255, green: 0xFA / 255, blue: 0xFC / 255, alpha: 1)
private let greenColor = NSColor(calibratedRed: 0x34 / 255, green: 0xE3 / 255, blue: 0x6E / 255, alpha: 1)
private let blueColor = NSColor(calibratedRed: 0x4A / 255, green: 0xA3 / 255, blue: 0xFF / 255, alpha: 1)
private let redColor = NSColor(calibratedRed: 0xFF / 255, green: 0x45 / 255, blue: 0x3A / 255, alpha: 1)

struct WidgetConfig {
    var configVersion: Int = currentConfigVersion
    var x: Int = 200
    var y: Int = 100
    var pinned: Bool = false
    var desktopMode: Bool = true
}

struct PowerSnapshot {
    var percent: Int = 0
    var plugged: Bool = false
    var charging: Bool = false
    var state: String = "unknown"
    var systemW: Double = 0
    var chargeW: Double = 0
    var dischargeW: Double = 0
    var totalW: Double = 0
    var heroColor: NSColor = textColor
    var statusColor: NSColor = mutedColor
}

final class ConfigStore {
    static let shared = ConfigStore()
    private let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".battery_monitor.cfg")

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
        config.desktopMode = object["desktop_mode"] as? Bool ?? config.desktopMode

        if savedVersion < currentConfigVersion {
            config.configVersion = currentConfigVersion
            config.pinned = WidgetConfig().pinned
            config.desktopMode = WidgetConfig().desktopMode
        }
        return config
    }

    func save(_ config: WidgetConfig) {
        let object: [String: Any] = [
            "config_version": config.configVersion,
            "x": config.x,
            "y": config.y,
            "pinned": config.pinned,
            "desktop_mode": config.desktopMode,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: object, options: []) {
            try? data.write(to: url)
        }
    }
}

final class PowerSampler {
    func sample() -> PowerSnapshot {
        let text = runIoreg()
        guard !text.isEmpty else {
            return PowerSnapshot()
        }

        let percent = intValue("CurrentCapacity", in: text) ?? 0
        let plugged = boolValue("ExternalConnected", in: text) ?? false
        let charging = boolValue("IsCharging", in: text) ?? false
        let voltage = intValue("Voltage", in: text) ?? 0
        let amperage = intValue("Amperage", in: text) ?? 0
        let telemetry = intMap("PowerTelemetryData", in: text)
        let charger = intMap("ChargerData", in: text)

        let chargeW = chargePower(charging: charging, telemetry: telemetry, charger: charger, voltage: voltage, amperage: amperage)
        let systemW: Double
        if let load = telemetry["SystemLoad"] {
            systemW = Double(load) / 1000.0
        } else if let systemIn = telemetry["SystemPowerIn"] {
            systemW = max(Double(systemIn) / 1000.0 - chargeW, 0)
        } else {
            systemW = fallbackPower(voltage: voltage, amperage: amperage)
        }

        let dischargeW = plugged ? 0 : (telemetry["BatteryPower"].map { abs(Double($0) / 1000.0) } ?? fallbackPower(voltage: voltage, amperage: amperage))
        let totalW = max(systemW, 0) + max(chargeW, 0)

        var snapshot = PowerSnapshot()
        snapshot.percent = percent
        snapshot.plugged = plugged
        snapshot.charging = charging
        snapshot.systemW = systemW
        snapshot.chargeW = chargeW
        snapshot.dischargeW = dischargeW
        snapshot.totalW = totalW

        if charging {
            snapshot.state = "charging"
            snapshot.heroColor = greenColor
            snapshot.statusColor = greenColor
        } else if plugged {
            snapshot.state = "plugged_full"
            snapshot.heroColor = blueColor
            snapshot.statusColor = blueColor
        } else if percent <= 20 {
            snapshot.state = "low_battery"
            snapshot.heroColor = textColor
            snapshot.statusColor = redColor
        } else {
            snapshot.state = "discharging"
            snapshot.heroColor = textColor
            snapshot.statusColor = mutedColor
        }
        return snapshot
    }

    private func runIoreg() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
        process.arguments = ["-rd1", "-c", "AppleSmartBattery"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ""
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func intValue(_ key: String, in text: String) -> Int? {
        let pattern = "\"\(key)\"\\s*=\\s*(-?\\d+)"
        guard let match = text.range(of: pattern, options: .regularExpression) else {
            return nil
        }
        let matched = String(text[match])
        return Int(matched.components(separatedBy: "=").last?.trimmingCharacters(in: .whitespaces) ?? "")
    }

    private func boolValue(_ key: String, in text: String) -> Bool? {
        let pattern = "\"\(key)\"\\s*=\\s*(Yes|No)"
        guard let match = text.range(of: pattern, options: .regularExpression) else {
            return nil
        }
        return String(text[match]).contains("Yes")
    }

    private func intMap(_ name: String, in text: String) -> [String: Int] {
        let pattern = "\"\(name)\"\\s*=\\s*\\{([^}]*)\\}"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return [:]
        }
        let body = String(text[range])
        let pairRegex = try? NSRegularExpression(pattern: "\"?(\\w+)\"?\\s*=\\s*(-?\\d+)")
        var values: [String: Int] = [:]
        pairRegex?.enumerateMatches(in: body, range: NSRange(body.startIndex..., in: body)) { match, _, _ in
            guard let match,
                  let keyRange = Range(match.range(at: 1), in: body),
                  let valueRange = Range(match.range(at: 2), in: body),
                  let value = Int(body[valueRange]) else {
                return
            }
            values[String(body[keyRange])] = value
        }
        return values
    }

    private func fallbackPower(voltage: Int, amperage: Int) -> Double {
        abs(Double(voltage * amperage) / 1_000_000.0)
    }

    private func chargePower(charging: Bool, telemetry: [String: Int], charger: [String: Int], voltage: Int, amperage: Int) -> Double {
        guard charging else { return 0 }
        if let chargeVoltage = charger["ChargingVoltage"],
           let current = charger["ChargingCurrent"],
           current > 0 {
            return abs(Double(chargeVoltage * current) / 1_000_000.0)
        }
        if let batteryPower = telemetry["BatteryPower"] {
            return abs(Double(batteryPower) / 1000.0)
        }
        return fallbackPower(voltage: voltage, amperage: amperage)
    }
}

final class BatteryView: NSView {
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
        pulsePhase += 0.16
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

        let percentText = "\(snapshot.percent)%"
        let percentY: CGFloat = 22
        let percentSize: CGFloat = 29
        let percentWidth = textWidth(percentText, size: percentSize, weight: .bold)
        let percentX = widgetWidth - 19 - percentWidth
        drawStatusDot(center: NSPoint(x: percentX - 14.5, y: percentY + percentSize / 2))
        drawText(percentText, at: NSPoint(x: percentX, y: percentY), size: percentSize, weight: .bold, color: snapshot.statusColor)

        drawText("负载", at: NSPoint(x: 20, y: 64), size: 17, weight: .bold, color: mutedColor)
        drawText(formatW(snapshot.systemW), at: NSPoint(x: 55, y: 64), size: 17, weight: .bold, color: textColor)

        let battery = batteryCompact()
        drawText(battery.label, at: NSPoint(x: 142, y: 64), size: 17, weight: .bold, color: mutedColor)
        drawText(battery.value, at: NSPoint(x: 177, y: 64), size: 17, weight: .bold, color: battery.color)

        let time = timeString()
        let timeWidth = textWidth(time, size: 17, weight: .bold)
        drawText(time, at: NSPoint(x: widgetWidth - 19 - timeWidth, y: 64), size: 17, weight: .bold, color: mutedColor)
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
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date())
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

final class AppController: NSObject, NSApplicationDelegate {
    private var config = ConfigStore.shared.load()
    private let sampler = PowerSampler()
    private let view = BatteryView(frame: NSRect(x: 0, y: 0, width: widgetWidth, height: widgetHeight))
    private var window: WidgetWindow?
    private var timer: Timer?
    private var pulseTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
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
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.view.advancePulse()
        }
    }

    func showMenu(event: NSEvent) {
        let menu = NSMenu()
        let desktopItem = NSMenuItem(title: "\(config.desktopMode ? "✓ " : "")桌面模式", action: #selector(toggleDesktopMode), keyEquivalent: "")
        desktopItem.target = self
        menu.addItem(desktopItem)
        let pinnedItem = NSMenuItem(title: "\(config.pinned ? "✓ " : "")置顶", action: #selector(togglePinned), keyEquivalent: "")
        pinnedItem.target = self
        menu.addItem(pinnedItem)
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

    @objc private func toggleDesktopMode() {
        config.desktopMode.toggle()
        if config.desktopMode {
            config.pinned = false
        }
        ConfigStore.shared.save(config)
        applyWindowMode()
    }

    @objc private func togglePinned() {
        config.pinned.toggle()
        ConfigStore.shared.save(config)
        applyWindowMode()
    }

    @objc private func quit() {
        persistPosition()
        NSApp.terminate(nil)
    }

    private func update() {
        view.snapshot = sampler.sample()
    }

    private func applyWindowMode() {
        guard let window else { return }
        if config.desktopMode {
            window.level = .normal
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            window.alphaValue = 0.92
        } else {
            window.level = config.pinned ? .floating : .normal
            window.collectionBehavior = []
            window.alphaValue = 1
        }
        window.orderFrontRegardless()
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

let app = NSApplication.shared
let delegate = AppController()
app.delegate = delegate
app.run()
