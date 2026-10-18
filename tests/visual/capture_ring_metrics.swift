import AppKit
import CryptoKit
import Foundation

/// Hidden production AppKit renderers only. No window is ordered front, no
/// native menu is opened, and Settings preferences are held entirely in memory.
@main
private enum CaptureRingMetrics {
    private static var records: [[String: Any]] = []
    private static var assertions = 0
    private static var failures = 0

    static func main() throws {
        guard CommandLine.arguments.count == 2,
              ProcessInfo.processInfo.environment["WATTSON_FORCE_REDUCE_TRANSPARENCY"] == "1",
              ProcessInfo.processInfo.environment["WATTSON_FORCE_REDUCE_MOTION"] == "1" else {
            fputs("usage: WATTSON_FORCE_REDUCE_TRANSPARENCY=1 WATTSON_FORCE_REDUCE_MOTION=1 capture_ring_metrics OUTPUT_DIRECTORY\n", stderr)
            exit(64)
        }
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let initialProtectedFiles = protectedFiles()
        let initialFrontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        app.finishLaunching()
        let defaults = MemoryDefaults()
        Settings.configureForTest(defaults: defaults)
        defer { Settings.resetTestConfiguration(); defaults.clear() }
        Settings.liquidGlassEnabled = false

        for appearance in ["light", "dark"] {
            app.appearance = NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
            Settings.colorScheme = appearance == "dark" ? .dark : .light
            for (state, snapshot) in fixtures {
                try capturePopover(snapshot, state: state, appearance: appearance, output: output)
            }
            try captureSettings(appearance: appearance, output: output)
        }
        Settings.resetTestConfiguration()
        defaults.clear()
        let finalChecks = [
            "canonicalAppHelperAndPreferencesUnchanged": initialProtectedFiles == protectedFiles(),
            "foregroundApplicationUnchanged": initialFrontmost == NSWorkspace.shared.frontmostApplication?.processIdentifier,
            "captureNeverForeground": NSWorkspace.shared.frontmostApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier,
            "memoryDefaultsCleared": defaults.isEmpty,
        ]
        recordChecks(finalChecks)
        let evidence: [String: Any] = [
            "schema": 1,
            "method": "Hidden NSWindow; production PopoverContentViewController and SettingsWindowController cacheDisplay bitmaps; Classic with Reduce Transparency and Reduce Motion; in-memory Settings; fixture readings and dependencies; no live battery sampling or helper IPC.",
            "limitations": "Layout evidence only, not WindowServer screenshots or composited Liquid Glass. Native Metrics menu is inspected without opening it; menu checked states are recorded as data. No pointer, keyboard or VoiceOver acceptance is claimed.",
            "cases": records, "assertions": assertions, "failures": failures,
            "finalChecks": finalChecks, "protectedFileHashes": initialProtectedFiles,
            "executableSHA256": hash(try? Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[0]))),
        ]
        try JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("evidence.json"), options: .atomic)
        print("Ring Metrics: \(records.count) cases, \(assertions) assertions, \(failures) failures")
        exit(failures == 0 ? 0 : 1)
    }

    private static var fixtures: [(String, PowerSnapshot)] {
        let values: [(String, PowerSnapshot)] = [
            ("charging", PowerSnapshot(percent: 72, plugged: true, adapterW: 68, batteryW: 22.2, systemW: 45.8, temperatureC: 34.2, cycleCount: 307, batteryTimeEstimate: .charging(42))),
            ("full", PowerSnapshot(percent: 100, plugged: true, adapterW: 52, batteryW: 0, systemW: 52, temperatureC: 31.8, cycleCount: 307, batteryTimeEstimate: .full)),
            ("on-battery", PowerSnapshot(percent: 67, batteryW: -39.7, systemW: 39.7, deviceOutputW: 12.2, temperatureC: 33.1, cycleCount: 307, batteryTimeEstimate: .remaining(265))),
            ("mixed-supply", PowerSnapshot(percent: 18, plugged: true, adapterW: 28, batteryW: -31.7, systemW: 59.7, temperatureC: 38.6, cycleCount: 307, batteryTimeEstimate: .notCharging)),
            ("low-battery", PowerSnapshot(percent: 14, batteryW: -12, systemW: 12, temperatureC: 32.4, cycleCount: 307, batteryTimeEstimate: .remaining(18))),
            ("low-power", PowerSnapshot(percent: 67, batteryW: -12, systemW: 12, temperatureC: 32.4, cycleCount: 307, lowPowerMode: true, batteryTimeEstimate: .remaining(310))),
        ]
        return values.map { name, original in
            var snapshot = original
            snapshot.batteryVoltageV = 12.81
            snapshot.batteryCurrentMA = Int((snapshot.batteryW / 12.81 * 1_000).rounded())
            snapshot.adapterVoltageV = snapshot.plugged ? 20 : nil
            snapshot.adapterCurrentMA = snapshot.plugged ? Int((snapshot.adapterW / 20 * 1_000).rounded()) : nil
            snapshot.batteryHealthPercent = 81.3
            snapshot.maxCapacityMAh = 6_975
            snapshot.designCapacityMAh = 8_579
            return (name, snapshot)
        }
    }

    private static func capturePopover(_ snapshot: PowerSnapshot, state: String, appearance: String, output: URL) throws {
        Settings.moduleOrder = Settings.Module.allCases
        for module in Settings.Module.allCases { Settings.setModule(module, visible: module != .topProcesses) }
        Settings.ringMetrics = Settings.defaultRingMetrics
        let controller = PopoverContentViewController()
        controller.setAnimationsEnabled(false)
        controller.setPresentationActive(true)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: PopoverStyle.width, height: controller.preferredHeight), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.hasShadow = false
        window.appearance = NSApp.appearance
        window.contentView = controller.view
        defer { controller.setPresentationActive(false); window.close() }
        controller.update(snapshot: snapshot, history: (0..<36).map { snapshot.totalInputW * (0.6 + Double($0 % 7) * 0.06) }, peak: snapshot.totalInputW, degraded: false)
        controller.updateSystemBatteryIconState(false)
        guard let ring = descendants(controller.view).compactMap({ $0 as? RingGaugeView }).first,
              let flow = descendants(controller.view).compactMap({ $0 as? PowerFlowView }).first,
              let lanes = descendants(controller.view).compactMap({ $0 as? LaneView }).first,
              let footer = descendants(controller.view).compactMap({ $0 as? PopoverFooterView }).first else { throw missing("popover sections") }
        let defaultHeight = controller.preferredHeight
        let selections: [(String, [Settings.RingMetric])] = [
            ("default", Settings.defaultRingMetrics),
            ("electrical", [.batteryVoltage, .batteryCurrent, .adapterVoltage, .adapterCurrent]),
            ("health", [.timeEstimate, .batteryHealth, .maxCapacity, .designCapacity]),
        ] + (state == "charging" ? [("power", [.systemLoad, .batteryPower, .adapterPower, .deviceOutput]), ("none", [])] : [])
        for (selectionName, selection) in selections {
            Settings.ringMetrics = selection
            window.setContentSize(NSSize(width: PopoverStyle.width, height: controller.preferredHeight))
            controller.setViewportHeight(controller.preferredHeight)
            settle(controller.view)
            let frames = ring.visibleReadingFramesForTest
            let readings: [[String: Any]] = selection.compactMap { metric in
                guard let reading = ring.readingForTest(metric) else { return nil }
                return ["metric": metric.rawValue, "caption": reading.caption, "value": reading.value]
            }
            let ringFrame = ring.convert(ring.bounds, to: controller.view)
            let checks = [
                "windowNeverShown": !window.isVisible && !window.isKeyWindow,
                "selectionMatchesPreference": ring.selectedMetricsForTest == selection,
                "allSelectedReadingsPresent": readings.count == selection.count,
                "exactlyTwoFramesPerMetric": frames.count == selection.count * 2,
                "captionsAndValuesFit": ring.statsFitBoundsForTest,
                "readingFramesContained": frames.allSatisfy { ring.bounds.contains($0) },
                "readingFramesDoNotOverlap": frames.indices.allSatisfy { first in frames.indices.allSatisfy { second in first >= second || !frames[first].intersects(frames[second]) } },
                "fixedRingHeight": abs(ring.bounds.height - RingGaugeView.preferredHeight) < 0.1 && ring.bounds.height == 138,
                "fixedContentHeight": abs(controller.preferredHeight - defaultHeight) < 0.1,
                "flowRingAndNextSectionContiguous": adjacent(flow, ring, root: controller.view) && adjacent(ring, lanes, root: controller.view),
                "footerContained": controller.view.bounds.insetBy(dx: -0.5, dy: -0.5).contains(footer.convert(footer.bounds, to: controller.view)),
                "noRunningAnimations": controller.runningAnimationCountForTest == 0,
                "batteryAndAdapterVoltagesDistinct": !selection.contains(.adapterVoltage) || ring.readingForTest(.batteryVoltage)?.value != ring.readingForTest(.adapterVoltage)?.value,
                "voltageSourcesExplicit": !selection.contains(.adapterVoltage) || (ring.readingForTest(.batteryVoltage)?.caption == "Battery Voltage" && ring.readingForTest(.adapterVoltage)?.caption == "Adapter Voltage"),
                "currentSourcesExplicit": !selection.contains(.adapterCurrent) || (ring.readingForTest(.batteryCurrent)?.caption == "Battery Current" && ring.readingForTest(.adapterCurrent)?.caption == "Adapter Current"),
            ]
            recordChecks(checks)
            let name = "ring-metrics-\(appearance)-\(state)-\(selectionName)"
            var record: [String: Any] = ["case": name, "checks": checks, "selection": selection.map(\.rawValue), "readings": readings, "readingFrames": frames.map(NSStringFromRect), "ringFrame": NSStringFromRect(ringFrame), "contentHeight": controller.preferredHeight]
            record.merge(try capture(controller.view, name: name, output: output), uniquingKeysWith: { _, new in new })
            record["ringImage"] = try capture(controller.view, name: name + "-section", output: output, rect: ringFrame)
            records.append(record)
        }
    }

    private static func captureSettings(appearance: String, output: URL) throws {
        let dependencies = SettingsWindowDependencies(loginItemState: { .enabled }, refreshLoginItem: { $0(.enabled) }, setLoginItemEnabled: { enabled, completion in completion(.success(enabled ? .enabled : .notRegistered)) }, systemBatteryIconHidden: { false }, helperAvailable: { true }, refreshSystemBatteryIcon: { $0(false) }, setSystemBatteryIconHidden: { _, completion in completion(true) }, systemBatteryIconDidChange: Notification.Name("Wattson.RingMetricsCapture.Battery"), currentVersion: { "Development" }, checkForUpdates: { $0(.success(.upToDate(currentVersion: "Development"))) }, openUpdateURL: { _ in true }, increaseContrast: { false }, announceAccessibility: { _ in })
        Settings.setModule(.ring, visible: true)
        let controller = SettingsWindowController(dependencies: dependencies, frameAutosaveName: nil)
        controller.selectSectionForTest(identifier: "modules")
        guard let window = controller.windowForTest, let content = window.contentView, let frameView = content.superview,
              let popup = descendants(content).compactMap({ $0 as? NSPopUpButton }).first(where: { $0.identifier?.rawValue == "settings.modules.ring-metrics" }),
              let row = descendants(content).first(where: { $0.identifier?.rawValue == "settings.modules.row.ring" }) else { throw missing("Settings Metrics popup") }
        window.animationBehavior = .none
        defer { window.close() }
        for (selectionName, selection) in [("default", Settings.defaultRingMetrics), ("electrical", [.batteryVoltage, .batteryCurrent, .adapterVoltage, .adapterCurrent]), ("none", [Settings.RingMetric]())] {
            Settings.ringMetrics = selection
            controller.refreshSectionsForTest()
            settle(frameView)
            let metricItems = popup.itemArray.filter { ($0.representedObject as? String).flatMap(Settings.RingMetric.init(rawValue:)) != nil }
            let checks = [
                "windowNeverShown": !window.isVisible && !window.isKeyWindow,
                "nativeMenuNeverOpened": !popup.isHighlighted,
                "metricsButtonEnabled": popup.isEnabled,
                "allMetricItemsPresent": metricItems.compactMap { $0.representedObject as? String } == Settings.RingMetric.allCases.map(\.rawValue),
                "checkmarksMatchSelection": metricItems.allSatisfy { item in guard let raw = item.representedObject as? String, let metric = Settings.RingMetric(rawValue: raw) else { return false }; return item.state == (selection.contains(metric) ? .on : .off) },
                "metricTitlesExplicit": metricItems.allSatisfy { item in guard let raw = item.representedObject as? String, let metric = Settings.RingMetric(rawValue: raw) else { return false }; return item.title == metric.title },
                "restoreDefaultActionPresent": popup.itemArray.contains { $0.title == "Restore Default Metrics" && $0.action != nil },
                "metricsButtonInsideRingRow": row.bounds.contains(popup.convert(popup.bounds, to: row)),
                "settingsLabelsFit": descendants(row).compactMap { $0 as? NSTextField }.allSatisfy { $0.attributedStringValue.size().width <= $0.bounds.width + 0.5 },
            ]
            recordChecks(checks)
            let name = "ring-metrics-settings-\(appearance)-\(selectionName)"
            var record: [String: Any] = ["case": name, "checks": checks, "selection": selection.map(\.rawValue), "nativeMenuOpened": false, "menuItems": metricItems.map { ["title": $0.title, "metric": $0.representedObject as? String ?? "", "checked": $0.state == .on] }, "metricsButtonFrame": NSStringFromRect(popup.convert(popup.bounds, to: row))]
            record.merge(try capture(frameView, name: name, output: output), uniquingKeysWith: { _, new in new })
            record["ringRowImage"] = try capture(frameView, name: name + "-row", output: output, rect: row.convert(row.bounds, to: frameView))
            records.append(record)
        }
    }

    private static func settle(_ view: NSView) {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.04))
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
    }

    private static func adjacent(_ first: NSView, _ second: NSView, root: NSView) -> Bool {
        let a = first.convert(first.bounds, to: root), b = second.convert(second.bounds, to: root)
        return min(abs(a.maxY - b.minY), abs(a.minY - b.maxY)) < 0.01
    }

    private static func capture(_ view: NSView, name: String, output: URL, rect: NSRect? = nil) throws -> [String: Any] {
        let bounds = rect ?? view.bounds
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: bounds) else { throw missing("bitmap") }
        view.cacheDisplay(in: bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw missing("PNG") }
        let imageName = name + ".png"
        try png.write(to: output.appendingPathComponent(imageName), options: .atomic)
        return ["image": imageName, "imageSHA256": hash(png), "imageDimensions": [bitmap.pixelsWide, bitmap.pixelsHigh]]
    }

    private static func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    private static func recordChecks(_ checks: [String: Bool]) { assertions += checks.count; failures += checks.values.filter { !$0 }.count }
    private static func missing(_ name: String) -> NSError { NSError(domain: "WattsonRingMetricsCapture", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing \(name)"]) }
    private static func hash(_ data: Data?) -> String { data.map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() } ?? "absent" }
    private static func protectedFiles() -> [String: String] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let files: [(String, URL)] = [
            ("installedInfo", URL(fileURLWithPath: "/Applications/Wattson.app/Contents/Info.plist")),
            ("installedBinary", URL(fileURLWithPath: "/Applications/Wattson.app/Contents/MacOS/Wattson")),
            ("installedHelper", URL(fileURLWithPath: "/Library/PrivilegedHelperTools/com.leoarrow.wattson.helper")),
            ("sandboxPreferences", home.appendingPathComponent("Library/Containers/com.leoarrow.wattson/Data/Library/Preferences/com.leoarrow.wattson.plist")),
            ("legacyPreferences", home.appendingPathComponent("Library/Preferences/com.leoarrow.wattson.plist")),
        ]
        return Dictionary(uniqueKeysWithValues: files.map { ($0.0, hash(try? Data(contentsOf: $0.1))) })
    }
}

private final class MemoryDefaults: UserDefaults {
    private var values: [String: Any] = [:]
    override func object(forKey key: String) -> Any? { values[key] }
    override func string(forKey key: String) -> String? { values[key] as? String }
    override func array(forKey key: String) -> [Any]? { values[key] as? [Any] }
    override func set(_ value: Any?, forKey key: String) { values[key] = value }
    override func set(_ value: Bool, forKey key: String) { values[key] = value }
    override func removeObject(forKey key: String) { values.removeValue(forKey: key) }
    func clear() { values.removeAll() }
    var isEmpty: Bool { values.isEmpty }
}
