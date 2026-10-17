import AppKit
import Foundation

// Test-only driver. Same bytes and optimized compiler flags for both revisions.
// Timings include only synchronous production update preparation, never FPS.
@main struct NarrowBenchmark {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
        let arguments = Array(CommandLine.arguments.dropFirst())
        precondition(arguments.count == 3)
        let revision = arguments[0], block = Int(arguments[1])!, iterations = Int(arguments[2])!
        let suite = ProcessInfo.processInfo.environment["WATTSON_PERF_DEFAULTS_SUITE"]!
        precondition(suite.hasPrefix("Wattson.PerformanceSmoothness."))
        let defaults = UserDefaults(suiteName: suite)!
        Settings.configureForTest(defaults: defaults)
        defer {
            Settings.resetTestConfiguration()
            defaults.removePersistentDomain(forName: suite)
            _ = defaults.synchronize()
        }
        Settings.liquidGlassEnabled = false
        Settings.colorScheme = .dark
        NSApp.appearance = NSAppearance(named: .darkAqua)

        func emit(_ name: String, _ work: (Int) -> Void) {
            for index in 0..<200 { autoreleasepool { work(index) } }
            var samples = [Double]()
            samples.reserveCapacity(iterations)
            for index in 0..<iterations {
                let start = DispatchTime.now().uptimeNanoseconds
                autoreleasepool { work(index) }
                samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000)
            }
            let sorted = samples.sorted()
            let result: [String: Any] = [
                "revision": revision, "block": block, "case": name,
                "iterations": iterations, "samples_us": samples,
                "median_us": sorted[iterations / 2],
                "p95_us": sorted[Int(Double(iterations - 1) * 0.95)],
                "total_ms": samples.reduce(0, +) / 1_000,
            ]
            print(String(decoding: try! JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), as: UTF8.self))
        }

        let view = TopProcessesView()
        view.frame = NSRect(x: 0, y: 0, width: PopoverStyle.contentWidth, height: TopProcessesView.preferredHeight(count: 3))
        view.appearance = NSAppearance(named: .darkAqua)
        let values = [
            EnergyProcess(pid: 900_001, name: "Safari", energyImpact: 84, cpuPercent: 72, idleWakeupsPerSecond: 240),
            EnergyProcess(pid: 900_002, name: "WindowServer", energyImpact: 45, cpuPercent: 40, idleWakeupsPerSecond: 100),
            EnergyProcess(pid: 900_003, name: "Xcode", energyImpact: 12, cpuPercent: 10, idleWakeupsPerSecond: 40),
        ]
        let state = TopProcessesState.ready(values)
        view.update(state: state, count: 3)
        view.layoutSubtreeIfNeeded()
        emit("process_identical_input") { _ in view.update(state: state, count: 3) }
        let changed = TopProcessesState.ready([
            EnergyProcess(pid: 900_001, name: "Safari", energyImpact: 85, cpuPercent: 73, idleWakeupsPerSecond: 240),
            values[1], values[2],
        ])
        emit("process_changed_input") { index in view.update(state: index.isMultiple(of: 2) ? changed : state, count: 3) }

        var increasedContrast = false
        let dependencies = SettingsWindowDependencies(
            loginItemState: { .enabled }, refreshLoginItem: { $0(.enabled) },
            setLoginItemEnabled: { value, done in done(.success(value ? .enabled : .notRegistered)) },
            systemBatteryIconHidden: { false }, helperAvailable: { true },
            refreshSystemBatteryIcon: { $0(false) }, setSystemBatteryIconHidden: { _, done in done(true) },
            systemBatteryIconDidChange: Notification.Name("Wattson.PerformanceSmoothness.Battery"),
            currentVersion: { "Development" }, checkForUpdates: { $0(.success(.upToDate(currentVersion: "Development"))) },
            openUpdateURL: { _ in true }, increaseContrast: { increasedContrast }, announceAccessibility: { _ in }
        )
        let settings = SettingsWindowController(dependencies: dependencies, frameAutosaveName: nil)
        guard let window = settings.windowForTest else { fatalError("Missing Settings fixture window") }
        defer { window.close() }
        window.animationBehavior = .none
        window.makeKeyAndOrderFront(nil)
        settings.selectSectionForTest(identifier: "general")
        window.contentView?.layoutSubtreeIfNeeded()
        func descendants(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(descendants) }
        let icons = settings.sectionViewIdentitiesForTest // Materialize all retained sections before selecting Modules.
        precondition(!icons.isEmpty)
        let general = descendants(window.contentView!).filter { String(describing: type(of: $0)) == "GeneralSettingsIconView" }
        settings.selectSectionForTest(identifier: "modules")
        window.contentView?.layoutSubtreeIfNeeded()
        let modules = descendants(window.contentView!).filter { String(describing: type(of: $0)) == "ModuleSettingsIconView" }
        let allIcons = general + modules
        precondition(general.count == 5 && modules.count == 6, "Unexpected production icon inventory")
        emit("settings_11_icons_identical_appearance") { _ in
            for icon in allIcons { icon.viewDidChangeEffectiveAppearance() }
        }
        emit("settings_11_icons_changed_contrast") { index in
            increasedContrast = index.isMultiple(of: 2)
            for icon in allIcons { icon.viewDidChangeEffectiveAppearance() }
        }
        increasedContrast = false
    }
}
