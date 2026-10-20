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
    private var latestObservationDetails = [String: Any]()
    private let warmups = 3
    private let coldCount = Int(ProcessInfo.processInfo.environment["WATTSON_PERF_COLD_COUNT"] ?? "0") ?? -1
    private let warmCount = Int(ProcessInfo.processInfo.environment["WATTSON_PERF_WARM_COUNT"] ?? "20") ?? -1
    private let themeCount = Int(ProcessInfo.processInfo.environment["WATTSON_PERF_THEME_COUNT"] ?? "0") ?? -1
    private let submission = ProcessInfo.processInfo.environment["WATTSON_PERF_SUBMISSION"] ?? "forced"
    private let fixedOpenColorScheme = ProcessInfo.processInfo.environment["WATTSON_PERF_COLOR_SCHEME"] ?? "dark"

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

    private func waitForObservation(condition: () -> Bool) async -> Bool {
        // Allow AppKit's persistent application loop and CA transaction observer
        // to run. Resolution is approximately one millisecond plus scheduling.
        let start = DispatchTime.now().uptimeNanoseconds
        var last = start
        var maxGap: UInt64 = 0
        var count = 0
        while true {
            await pause(0.001)
            let now = DispatchTime.now().uptimeNanoseconds
            count += 1
            maxGap = max(maxGap, now - last)
            last = now
            let satisfied = condition()
            if satisfied || now - start > 3_000_000_000 {
                latestObservationDetails = ["main_actor_poll_count": count,
                    "first_poll_requested_uptime_ns": start, "last_resume_uptime_ns": now,
                    "maximum_resume_gap_ms": Double(maxGap) / 1_000_000]
                return satisfied
            }
        }
    }

    private func observe(_ label: String, condition: () -> Bool) async throws {
        guard await waitForObservation(condition: condition) else { throw MeasurementError.timedOut(label) }
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
        try await observe("popup dismissal and animation cleanup") {
            self.popup?.isShownForTest != true && (self.popup?.entranceAnimationCountForTest ?? 0) == 0
        }
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
        if submission == "forced" { submit([window]) }
        let submitMS = milliseconds(since: openStart)
        try await observe("popup visible layer") {
            controller.isShownForTest && window.isVisible && view.layer?.presentation() != nil
        }
        let observedMS = milliseconds(since: openStart)
        let animationWaitStart = DispatchTime.now().uptimeNanoseconds
        let entranceRemoved = await waitForObservation { controller.entranceAnimationCountForTest == 0 }
        var row: [String: Any] = ["type": "sample", "case": cold ? "popup_controller_cold" : "popup_reopen_warm",
            "mode": mode, "index": index, "warmup": index < warmups,
            "uptime_start_ns": start, "submission": submission,
            "fixed_open_color_scheme": fixedOpenColorScheme,
            "host_effective_appearance": window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])?.rawValue ?? "unknown",
            "host_appearance_override": window.appearance.map { $0.name.rawValue as Any } ?? NSNull(),
            "construction_and_cache_ms": construction, "call_ms": callMS,
            "visible_layer_observed_ms": observedMS,
            "entrance_animation_removed": entranceRemoved,
            "controller_entrance_finished_ms": entranceRemoved ? milliseconds(since: openStart) as Any : NSNull(),
            "total_including_construction_ms": entranceRemoved ? milliseconds(since: start) as Any : NSNull(),
            "observation_elapsed_ms": milliseconds(since: start)]
        if submission == "forced" { row["submit_cumulative_ms"] = submitMS }
        if !entranceRemoved {
            let now = CACurrentMediaTime()
            let root = view.layer
            let presented = root?.presentation()
            let animation = controller.entranceAnimationForTest
            row["entrance_completion_censored"] = [
                "observer_activity": latestObservationDetails,
                "observation_wait_ms": milliseconds(since: animationWaitStart),
                "observer_resumed_uptime_ns": DispatchTime.now().uptimeNanoseconds,
                "observer_on_main_thread": Thread.isMainThread,
                "ca_media_time": now, "window_visible": window.isVisible,
                "window_occlusion_visible": window.occlusionState.contains(.visible),
                "root_layer_local_time": root?.convertTime(now, from: nil) ?? -1,
                "presentation_local_time": presented?.convertTime(now, from: nil) ?? -1,
                "root_speed": root?.speed ?? -1, "root_begin_time": root?.beginTime ?? -1,
                "root_time_offset": root?.timeOffset ?? -1,
                "root_opacity": root?.opacity ?? -1, "presentation_opacity": presented?.opacity ?? -1,
                "animation_count": controller.entranceAnimationCountForTest,
                "animation_duration": animation?.duration ?? -1,
                "animation_begin_time": animation?.beginTime ?? -1,
                "animation_time_offset": animation?.timeOffset ?? -1,
                "animation_speed": animation?.speed ?? -1,
                "animation_removed_on_completion": animation?.isRemovedOnCompletion ?? false,
            ] as [String: Any]
        }
        record(row)
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
            if submission == "forced" { submit(windows) }
            let submitMS = milliseconds(since: start)
            try await observe("theme appearance applied") {
                windows.allSatisfy { $0.isVisible && $0.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == expected }
            }
            guard popup.map(ObjectIdentifier.init) == popupID,
                  popup?.contentViewForTest.map(ObjectIdentifier.init) == rootID,
                  settings?.sectionViewIdentitiesForTest == settingsIDs else { throw MeasurementError.changedIdentity }
            var row: [String: Any] = ["type": "sample", "case": "theme_\(surface)", "mode": mode,
                "index": index, "warmup": index < warmups, "target": target.rawValue,
                "uptime_start_ns": start, "submission": submission, "call_ms": callMS,
                "appearance_observed_ms": milliseconds(since: start), "identities_retained": true]
            if submission == "forced" { row["submit_cumulative_ms"] = submitMS }
            record(row)
            await pause(0.03)
        }
        if popup != nil { try await closePopup(); popup = nil }
        settings?.close()
        settings = nil
        await pause(0.1)
    }

    private func summarize() {
        let measured = samples.filter { ($0["warmup"] as? Bool) == false }
        let groups = Dictionary(grouping: measured) {
            "\($0["mode"]!)/\($0["case"]!)" + ($0["target"].map { "/\($0)" } ?? "")
        }
        for key in groups.keys.sorted() {
            let rows = groups[key]!
            var result: [String: Any] = ["type": "summary", "group": key, "count": rows.count,
                "submission": submission, "fixed_open_color_scheme": fixedOpenColorScheme]
            if rows.contains(where: { $0["entrance_animation_removed"] != nil }) {
                result["entrance_animation_removed_count"] = rows.filter { ($0["entrance_animation_removed"] as? Bool) == true }.count
                result["entrance_animation_censored_count"] = rows.filter { ($0["entrance_animation_removed"] as? Bool) == false }.count
            }
            for metric in ["construction_and_cache_ms", "call_ms", "submit_cumulative_ms", "visible_layer_observed_ms",
                           "controller_entrance_finished_ms", "total_including_construction_ms", "appearance_observed_ms"] {
                let values = rows.compactMap { $0[metric] as? Double }.sorted()
                guard !values.isEmpty else { continue }
                // Nearest-rank quantiles, preserving all original samples above.
                result[metric] = ["count": values.count, "p50": values[max(0, Int(ceil(Double(values.count) * 0.5)) - 1)],
                    "p95": values[max(0, Int(ceil(Double(values.count) * 0.95)) - 1)],
                    "min": values.first!, "max": values.last!]
            }
            emit(result)
        }
    }

    func run() async throws {
        let locked = (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Int == 1
        guard !locked, defaultsSuite.hasPrefix("Wattson.UILatency."),
              [coldCount, warmCount, themeCount].allSatisfy({ (0...200).contains($0) }),
              coldCount + warmCount + themeCount > 0, ["forced", "natural"].contains(submission),
              let openScheme = Settings.ColorScheme(rawValue: fixedOpenColorScheme),
              let defaults = UserDefaults(suiteName: defaultsSuite), item.button != nil else { throw MeasurementError.invalidEnvironment }
        Settings.configureForTest(defaults: defaults)
        Settings.colorScheme = openScheme
        Settings.topProcessCount = 3
        Settings.topProcessesCompact = false
        item.button?.image = NSImage(systemSymbolName: "battery.100", accessibilityDescription: nil)
        emit(["type": "environment", "schema": 3, "submission": submission,
            "fixed_open_color_scheme": fixedOpenColorScheme,
            "application_effective_appearance": NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])?.rawValue ?? "unknown",
            "application_appearance_override": NSApp.appearance.map { $0.name.rawValue as Any } ?? NSNull(),
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
            "observation": "continuous NSApp.run; approximately 1 ms asynchronous polling; forced explicitly submits layout/display/CA before observing; natural adds no harness submission. A nonempty presentation layer and effectiveAppearance are software state, not proof of a newly displayed theme or physical frame delivery. Entrance removal has a bounded 3-second observation and retains censored samples; closing must clear the key.",
            "cold_definition": "new controller in the same process; first sample of each case retained as warmup; OS/framework caches are not cleared"])
        await pause(0.5)
        var modes = ["classic"]
        if #available(macOS 26, *) { modes += ["glass_regular", "glass_clear"] }
        for mode in modes {
            Settings.liquidGlassEnabled = mode != "classic"
            Settings.liquidGlassStyle = mode == "glass_clear" ? .clear : .regular
            Settings.colorScheme = openScheme
            if coldCount > 0 {
                for index in 0..<(coldCount + warmups) {
                    try await measureOpen(mode: mode, cold: true, index: index)
                }
            }
            if warmCount > 0 {
                for index in 0..<(warmCount + warmups) {
                    try await measureOpen(mode: mode, cold: false, index: index)
                }
            }
            popup = nil
            if themeCount > 0 {
                for surface in ["popup", "general", "menu-bar-icon", "modules"] {
                    try await measureThemes(mode: mode, surface: surface)
                }
            }
            emit(["type": "mode_complete", "mode": mode,
                "sample_count_including_warmup": samples.filter { ($0["mode"] as? String) == mode }.count])
        }
        summarize()
        emit(["type": "complete", "sample_count_including_warmup": samples.count])
    }
}
