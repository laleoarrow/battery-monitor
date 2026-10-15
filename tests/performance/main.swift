import AppKit
import Darwin
import Foundation

private func cleanupPerformanceDefaults(_ defaults: UserDefaults, suite: String) -> Bool {
    guard suite.hasPrefix("Wattson.Performance."),
          UUID(uuidString: String(suite.dropFirst("Wattson.Performance.".count))) != nil else { return false }
    defaults.removePersistentDomain(forName: suite)
    guard defaults.synchronize() else { return false }
    // Synchronization alone can leave cfprefsd able to recreate an empty plist.
    let deletion = Process()
    let completed = DispatchSemaphore(value: 0)
    let errors = Pipe()
    deletion.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
    deletion.arguments = ["delete", suite]
    deletion.standardOutput = FileHandle.nullDevice
    deletion.standardError = errors
    deletion.terminationHandler = { _ in completed.signal() }
    do { try deletion.run() } catch { return false }
    guard completed.wait(timeout: .now() + 3) == .success else {
        deletion.terminate()
        if completed.wait(timeout: .now() + 0.5) != .success {
            _ = Darwin.kill(deletion.processIdentifier, SIGKILL)
            _ = completed.wait(timeout: .now() + 1)
        }
        return false
    }
    let errorText = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    guard deletion.terminationStatus == 0 || errorText.contains("Domain (\(suite)) not found.") else { return false }
    let preference = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Preferences/\(suite).plist")
    do { try FileManager.default.removeItem(at: preference) }
    catch CocoaError.fileNoSuchFile { }
    catch { return false }
    return true
}

// Controlled production-renderer microbenchmark. Run the same optimized build
// flags, fixtures and iteration count on both revisions in an isolated GUI VM.
// This measures update/commit cost, not real display FPS or whole-app energy.
let iterations = CommandLine.arguments.dropFirst().first.flatMap(Int.init) ?? 2_000
precondition((100...20_000).contains(iterations))
_ = NSApplication.shared
NSApp.setActivationPolicy(.accessory)
NSApp.finishLaunching()
let suite = "Wattson.Performance.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suite)!
Settings.configureForTest(defaults: defaults)
defer {
    Settings.resetTestConfiguration()
    if !cleanupPerformanceDefaults(defaults, suite: suite) {
        FileHandle.standardError.write(Data("Failed to clean performance test preferences: \(suite)\n".utf8))
        exit(EXIT_FAILURE)
    }
}

func measure(_ name: String, _ action: (Int) -> Void) {
    var samples = [Double]()
    samples.reserveCapacity(iterations)
    for index in 0..<iterations {
        let start = DispatchTime.now().uptimeNanoseconds
        autoreleasepool { action(index) }
        samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000)
    }
    samples.sort()
    let result: [String: Any] = [
        "case": name, "iterations": iterations,
        "median_us": samples[iterations / 2],
        "p95_us": samples[Int(Double(iterations - 1) * 0.95)],
        "total_ms": samples.reduce(0, +) / 1_000,
    ]
    let data = try! JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
}

// Do not cache preference values: outside writes must still be visible.
measure("seven_preference_reads") { _ in
    _ = Settings.menuBarIconStyle
    _ = Settings.showsMenuBarPercentage
    _ = Settings.checksForUpdatesOnLaunch
    for module in Settings.Module.allCases { _ = Settings.isModuleVisible(module) }
}

func snapshot(_ index: Int, device: Bool, moving: Bool) -> PowerSnapshot {
    let system = moving && !device ? 30 + Double(index % 3) : 30.0
    let output = device ? (moving ? 7 + Double(index % 3) : 7.0) : nil
    return PowerSnapshot(percent: 80, plugged: false, adapterW: 0,
                         batteryW: -system, systemW: system, deviceOutputW: output,
                         temperatureC: 34.2, cycleCount: 282, lowPowerMode: false)
}

for (name, device, moving) in [
    ("unchanged_battery", false, false),
    ("varying_battery_fixed_curve", false, true),
    ("unchanged_usb", true, false),
    ("moving_usb_split", true, true),
] {
    autoreleasepool {
        let flow = PowerFlowView()
        flow.frame = NSRect(x: 0, y: 0, width: PopoverStyle.contentWidth,
                            height: PowerFlowView.preferredHeight)
        flow.appearance = NSAppearance(named: .darkAqua)
        flow.update(snapshot: snapshot(0, device: device, moving: moving), animated: false)
        flow.layoutSubtreeIfNeeded()
        flow.setAnimationsEnabled(true)
        CATransaction.flush()
#if WATTSON_PERF_COUNTERS
        let ridesBefore = flow.particleRideInstallationsForTest
        let geometryBefore = flow.particleGeometryUpdatesForTest
#endif
        measure(name) { index in
            flow.update(snapshot: snapshot(index, device: device, moving: moving), animated: true)
            flow.layoutSubtreeIfNeeded()
            CATransaction.flush()
        }
#if WATTSON_PERF_COUNTERS
        print("PARTICLE_WORK \(name) rides=\(flow.particleRideInstallationsForTest - ridesBefore) geometry=\(flow.particleGeometryUpdatesForTest - geometryBefore)")
#endif
        flow.setAnimationsEnabled(false)
        CATransaction.flush()
    }
}
