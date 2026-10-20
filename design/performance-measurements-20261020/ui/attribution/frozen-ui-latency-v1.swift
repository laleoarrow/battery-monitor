import AppKit
import ApplicationServices
import Foundation

// Optimized production-controller measurement in a disposable GUI session.
// Window/layer observation is a software milestone, never display FPS or
// a guarantee that WindowServer has presented a frame to the physical display.
@main
private enum UILatencyMain {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = UILatencyDelegate()
        app.delegate = delegate
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor
private final class UILatencyDelegate: NSObject, NSApplicationDelegate {
    private var runner: UILatencyRunner?

    func applicationDidFinishLaunching(_ notification: Notification) {
        runner = UILatencyRunner()
        Task { @MainActor in
            do {
                try await runner!.run()
                runner = nil
                NSApp.terminate(nil)
            } catch {
                emit(["type": "failure", "error": String(describing: error)])
                runner = nil
                exit(1)
            }
        }
    }
}

private func emit(_ object: [String: Any]) {
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
    fflush(stdout)
}

private enum MeasurementError: Error { case invalidEnvironment, timedOut(String), changedIdentity }

@MainActor
private final class UILatencyRunner {
    private let defaultsSuite = ProcessInfo.processInfo.environment["WATTSON_TEST_DEFAULTS_SUITE"] ?? ""
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var popup: PopoverController?
    private var settings: SettingsWindowController?
    private var samples = [[String: Any]]()
    private let warmups = 3
    private let coldCount = Int(ProcessInfo.processInfo.environment["WATTSON_PERF_COLD_COUNT"] ?? "30") ?? 0
    private let warmCount = Int(ProcessInfo.processInfo.environment["WATTSON_PERF_WARM_COUNT"] ?? "60") ?? 0
    private let themeCount = Int(ProcessInfo.processInfo.environment["WATTSON_PERF_THEME_COUNT"] ?? "60") ?? 0

    deinit {
        NSStatusBar.system.removeStatusItem(item)
        Settings.resetTestConfiguration()
    }

    private func milliseconds(since start: UInt64) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }

    private func pause(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private func observe(_ label: String, condition: () -> Bool) async throws {
        // Allow AppKit's persistent application loop and CA transaction observer
        // to run. Resolution is approximately one millisecond plus scheduling.
        await pause(0.001)
        let deadline = DispatchTime.now().uptimeNanoseconds + 3_000_000_000
        while !condition() {
            if DispatchTime.now().uptimeNanoseconds > deadline { throw MeasurementError.timedOut(label) }
            await pause(0.001)
        }
    }

    private func record(_ row: [String: Any]) {
        samples.append(row)
        emit(row)
    }

    private func prime(_ controller: PopoverController) {
        let reading = PowerSnapshot(percent: 80, plugged: true, adapterW: 60,
            batteryW: 20, systemW: 40, temperatureC: 34.2, cycleCount: 282,
            lowPowerMode: false, batteryHealthPercent: 84,
            batteryTimeEstimate: .charging(42), batteryTimeEstimateSource: .system,
            systemChargingState: .charging)
        let history = (0..<60).map { 35 + sin(Double($0) * 0.3) * 5 }
        controller.update(snapshot: reading, history: history, peak: 40, degraded: false)
        controller.updateTopProcesses(.ready([
            EnergyProcess(pid: 101, name: "Safari", energyImpact: 84, cpuPercent: 72, idleWakeupsPerSecond: 240),
            EnergyProcess(pid: 102, name: "WindowServer", energyImpact: 46.1, cpuPercent: 31.1, idleWakeupsPerSecond: 300),
            EnergyProcess(pid: 103, name: "Research Analysis", energyImpact: 8.1, cpuPercent: 8, idleWakeupsPerSecond: 2),
        ]))
        controller.updateSystemBatteryIconState(false)
    }

    private func submit(_ windows: [NSWindow]) {
        for window in windows {
            window.contentView?.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
        }
        CATransaction.flush()
    }

    private func closePopup() async throws {
        popup?.handleOutsideClick()
        try await observe("popup dismissal") { self.popup?.isShownForTest != true }
        // A complete close avoids measuring the different interrupted-dismissal
        // path. No animation policy is overridden by this measurement harness.
        await pause(0.03)
    }

    private func measureOpen(mode: String, cold: Bool, index: Int) async throws {
        let start = DispatchTime.now().uptimeNanoseconds
        var construction = 0.0
        if cold || popup == nil {
            popup = PopoverController()
            prime(popup!)
            construction = milliseconds(since: start)
        }
        let controller = popup!
        let openStart = DispatchTime.now().uptimeNanoseconds
        controller.openForSettingsCommandTest(relativeTo: item.button!)
        let callMS = milliseconds(since: openStart)
        guard let window = controller.contentWindowForTest, let view = controller.contentViewForTest else {
            throw MeasurementError.timedOut("popup host missing")
        }
        submit([window])
        let submitMS = milliseconds(since: openStart)
        try await observe("popup visible layer") {
            controller.isShownForTest && window.isVisible && view.layer?.presentation() != nil
        }
        let observedMS = milliseconds(since: openStart)
        try await observe("controller entrance animation removed") { controller.entranceAnimationCountForTest == 0 }
        record(["type": "sample", "case": cold ? "popup_controller_cold" : "popup_reopen_warm",
            "mode": mode, "index": index, "warmup": index < warmups,
            "uptime_start_ns": start,
            "construction_and_cache_ms": construction, "call_ms": callMS,
            "submit_cumulative_ms": submitMS, "visible_layer_observed_ms": observedMS,
            "controller_entrance_finished_ms": milliseconds(since: openStart),
            "total_including_construction_ms": milliseconds(since: start)])
        try await closePopup()
        if cold { popup = nil }
    }

    private func dependencies() -> SettingsWindowDependencies {
        SettingsWindowDependencies(loginItemState: { .enabled }, refreshLoginItem: { $0(.enabled) },
            setLoginItemEnabled: { enabled, done in done(.success(enabled ? .enabled : .notRegistered)) },
            systemBatteryIconHidden: { false }, helperAvailable: { true },
            refreshSystemBatteryIcon: { $0(false) }, setSystemBatteryIconHidden: { _, done in done(true) },
            systemBatteryIconDidChange: Notification.Name("Wattson.UILatency.BatteryFixture"),
            currentVersion: { "5.0.0 measurement fixture" },
            checkForUpdates: { $0(.success(.upToDate(currentVersion: "5.0.0"))) },
            openUpdateURL: { _ in false },
            increaseContrast: { NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast },
            announceAccessibility: { _ in })
    }

    private func measureThemes(mode: String, surface: String) async throws {
        if surface == "popup" {
            popup = PopoverController()
            prime(popup!)
            popup!.openForSettingsCommandTest(relativeTo: item.button!)
        } else {
            settings = SettingsWindowController(dependencies: dependencies(), frameAutosaveName: nil)
            settings!.selectSectionForTest(identifier: surface)
            settings!.show(activateApp: false)
        }
        await pause(0.4)
        let popupID = popup.map(ObjectIdentifier.init)
        let rootID = popup?.contentViewForTest.map(ObjectIdentifier.init)
        let settingsIDs = settings?.sectionViewIdentitiesForTest
        for index in 0..<(themeCount + warmups) {
            let target: Settings.ColorScheme = Settings.colorScheme == .dark ? .light : .dark
            let expected = target == .dark ? NSAppearance.Name.darkAqua : .aqua
            let start = DispatchTime.now().uptimeNanoseconds
            Settings.colorScheme = target
            let callMS = milliseconds(since: start)
            let windows = [popup?.contentWindowForTest, settings?.window].compactMap { $0 }
            submit(windows)
            let submitMS = milliseconds(since: start)
            try await observe("theme appearance applied") {
                windows.allSatisfy { $0.isVisible && $0.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == expected }
            }
            guard popup.map(ObjectIdentifier.init) == popupID,
                  popup?.contentViewForTest.map(ObjectIdentifier.init) == rootID,
                  settings?.sectionViewIdentitiesForTest == settingsIDs else { throw MeasurementError.changedIdentity }
            record(["type": "sample", "case": "theme_\(surface)", "mode": mode,
                "index": index, "warmup": index < warmups, "target": target.rawValue,
                "uptime_start_ns": start,
                "call_ms": callMS, "submit_cumulative_ms": submitMS,
                "appearance_observed_ms": milliseconds(since: start), "identities_retained": true])
            await pause(0.03)
        }
        if popup != nil { try await closePopup(); popup = nil }
        settings?.close()
        settings = nil
        await pause(0.1)
    }

    private func summarize() {
        let measured = samples.filter { ($0["warmup"] as? Bool) == false }
        let groups = Dictionary(grouping: measured) { "\($0["mode"]!)/\($0["case"]!)" }
        for key in groups.keys.sorted() {
            let rows = groups[key]!
            var result: [String: Any] = ["type": "summary", "group": key, "count": rows.count]
            for metric in ["construction_and_cache_ms", "call_ms", "submit_cumulative_ms", "visible_layer_observed_ms",
                           "controller_entrance_finished_ms", "total_including_construction_ms", "appearance_observed_ms"] {
                let values = rows.compactMap { $0[metric] as? Double }.sorted()
                guard !values.isEmpty else { continue }
                // Nearest-rank quantiles, preserving all original samples above.
                result[metric] = ["p50": values[max(0, Int(ceil(Double(values.count) * 0.5)) - 1)],
                    "p95": values[max(0, Int(ceil(Double(values.count) * 0.95)) - 1)],
                    "min": values.first!, "max": values.last!]
            }
            emit(result)
        }
    }

    func run() async throws {
        let locked = (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Int == 1
        guard !locked, defaultsSuite.hasPrefix("Wattson.UILatency."),
              (1...200).contains(coldCount), (1...200).contains(warmCount), (1...200).contains(themeCount),
              let defaults = UserDefaults(suiteName: defaultsSuite), item.button != nil else { throw MeasurementError.invalidEnvironment }
        Settings.configureForTest(defaults: defaults)
        Settings.colorScheme = .dark
        Settings.topProcessCount = 3
        Settings.topProcessesCompact = false
        item.button?.image = NSImage(systemSymbolName: "battery.100", accessibilityDescription: nil)
        emit(["type": "environment", "schema": 1,
            "recorded_at": ISO8601DateFormatter().string(from: Date()),
            "source_revision": ProcessInfo.processInfo.environment["WATTSON_PERF_SOURCE_REVISION"] ?? "unknown",
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "processors": ProcessInfo.processInfo.processorCount,
            "physical_memory_bytes": ProcessInfo.processInfo.physicalMemory,
            "optimization": "-O -D DEBUG", "warmups_per_case": warmups,
            "cold_count": coldCount, "warm_count": warmCount, "theme_count": themeCount,
            "reduce_motion": NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            "reduce_transparency": NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
            "increase_contrast": NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast,
            "screens": NSScreen.screens.map { ["frame": NSStringFromRect($0.frame), "scale": $0.backingScaleFactor] },
            "fixture": "charging / all modules / Top 3 detailed / 60 history samples",
            "open_external_refreshes": "skipped; synchronous UI path only; sampling measured separately",
            "observation": "continuous NSApp.run; approximately 1 ms asynchronous polling; window/layer and effective appearance are software state, not physical display delivery",
            "cold_definition": "new controller in the same process; first sample of each case retained as warmup; OS/framework caches are not cleared"])
        await pause(0.5)
        var modes = ["classic"]
        if #available(macOS 26, *) { modes += ["glass_regular", "glass_clear"] }
        for mode in modes {
            Settings.liquidGlassEnabled = mode != "classic"
            Settings.liquidGlassStyle = mode == "glass_clear" ? .clear : .regular
            Settings.colorScheme = .dark
            for index in 0..<(coldCount + warmups) {
                try await measureOpen(mode: mode, cold: true, index: index)
            }
            for index in 0..<(warmCount + warmups) {
                try await measureOpen(mode: mode, cold: false, index: index)
            }
            popup = nil
            for surface in ["popup", "general", "menu-bar-icon", "modules"] {
                try await measureThemes(mode: mode, surface: surface)
            }
        }
        summarize()
        emit(["type": "complete", "sample_count_including_warmup": samples.count])
    }
}
