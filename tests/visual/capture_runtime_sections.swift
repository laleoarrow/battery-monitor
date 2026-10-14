import AppKit
import CryptoKit
import Foundation

/// Renders the production popover content without showing a window or reading
/// battery telemetry. This is Classic layout evidence, not composited glass.
/// Build all Core/MenuBar/Popover sources with -D DEBUG, then pass an output
/// directory with WATTSON_FORCE_REDUCE_TRANSPARENCY=1 and
/// WATTSON_FORCE_REDUCE_MOTION=1. Preferences use a disposable isolated suite.
@main
private enum CaptureRuntimeSections {
    private static func hash(_ data: Data?) -> String {
        data.map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() } ?? "absent"
    }

    private static func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }

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

    static func main() throws {
        guard CommandLine.arguments.count == 2,
              ProcessInfo.processInfo.environment["WATTSON_FORCE_REDUCE_TRANSPARENCY"] == "1",
              ProcessInfo.processInfo.environment["WATTSON_FORCE_REDUCE_MOTION"] == "1" else {
            fputs("usage: WATTSON_FORCE_REDUCE_TRANSPARENCY=1 WATTSON_FORCE_REDUCE_MOTION=1 capture_runtime_sections OUTPUT_DIRECTORY\n", stderr)
            exit(2)
        }
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let initialFiles = protectedFiles()
        let initialFrontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        app.finishLaunching()
        let suite = "Wattson.RuntimeSectionCapture.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        Settings.configureForTest(defaults: defaults)
        Settings.liquidGlassEnabled = false

        let fixtures: [(String, PowerSnapshot)] = [
            ("charging", PowerSnapshot(percent: 72, plugged: true, adapterW: 68, batteryW: 22.2, systemW: 45.8, temperatureC: 34.2, cycleCount: 116)),
            ("full", PowerSnapshot(percent: 100, plugged: true, adapterW: 52, batteryW: 0, systemW: 52, temperatureC: 31.8, cycleCount: 116)),
            ("battery", PowerSnapshot(percent: 67, batteryW: -39.7, systemW: 39.7, deviceOutputW: 12.2, temperatureC: 33.1, cycleCount: 116, estimatedRuntimeMinutes: 265)),
            ("mixed", PowerSnapshot(percent: 18, plugged: true, adapterW: 28, batteryW: -31.7, systemW: 59.7, temperatureC: 38.6, cycleCount: 116)),
            ("low-battery", PowerSnapshot(percent: 14, batteryW: -12, systemW: 12, temperatureC: 32.4, cycleCount: 116, estimatedRuntimeMinutes: 18)),
            ("low-power", PowerSnapshot(percent: 67, batteryW: -12, systemW: 12, temperatureC: 32.4, cycleCount: 116, lowPowerMode: true, estimatedRuntimeMinutes: 265)),
        ]
        var records: [[String: Any]] = []
        var assertions = 0
        var failures = 0
        for appearance in ["light", "dark"] {
            app.appearance = NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
            Settings.colorScheme = appearance == "dark" ? .dark : .light
            for (name, snapshot) in fixtures {
                for module in Settings.Module.allCases { Settings.setModule(module, visible: true) }
                let controller = PopoverContentViewController()
                controller.setAnimationsEnabled(false)
                controller.setPresentationActive(true)
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: PopoverStyle.width, height: controller.preferredHeight),
                                      styleMask: .borderless, backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.animationBehavior = .none
                window.hasShadow = false
                window.appearance = app.appearance
                window.contentView = controller.view
                let history = (0..<36).map { snapshot.totalInputW * (0.6 + Double($0 % 7) * 0.06) }
                controller.update(snapshot: snapshot, history: history, peak: snapshot.totalInputW, degraded: false)
                controller.updateSystemBatteryIconState(false)
                func settle() {
                    window.setContentSize(NSSize(width: PopoverStyle.width, height: controller.preferredHeight))
                    controller.setViewportHeight(controller.preferredHeight)
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
                    controller.view.layoutSubtreeIfNeeded()
                    controller.view.displayIfNeeded()
                }
                settle()
                let views = descendants(controller.view)
                let header = views.compactMap { $0 as? PopoverHeaderView }.first!
                let runtime = views.compactMap { $0 as? PopoverRuntimeView }.first!
                let flow = views.compactMap { $0 as? PowerFlowView }.first!
                let footer = views.compactMap { $0 as? PopoverFooterView }.first!
                func frame(_ view: NSView) -> NSRect {
                    let rect = view.convert(view.bounds, to: controller.view)
                    return NSRect(x: rect.minX, y: controller.view.bounds.height - rect.maxY,
                                  width: rect.width, height: rect.height)
                }
                func adjacent(_ first: NSView, _ second: NSView) -> Bool {
                    abs(frame(first).maxY - frame(second).minY) < 0.01
                }
                let layout = runtime.sectionLayoutForTest
                let fullHeight = controller.preferredHeight
                let fullFlowY = frame(flow).minY
                let rowFrame = frame(runtime)
                var checks = [
                    "windowNeverShown": !window.isVisible && !window.isKeyWindow,
                    "noForegroundTakeover": NSWorkspace.shared.frontmostApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                    "headerFits": header.layoutFitsForTest(snapshot: snapshot),
                    "runtimeFits": runtime.layoutFitsForTest(snapshot: snapshot),
                    "runtimeHasTopSeparator": layout.hasTopSeparator,
                    "runtimeHasIndependent44PointHeight": runtime.bounds.height == 44,
                    "rowLabelsHaveTwelvePointGap": layout.valueFrame.minX - layout.titleFrame.maxX >= 12,
                    "rowHasVerticalPadding": layout.titleFrame.minY >= 12 && runtime.bounds.maxY - layout.titleFrame.maxY >= 12,
                    "headerThenRuntimeThenFlowWithoutGaps": adjacent(header, runtime) && adjacent(runtime, flow),
                    "footerContained": controller.view.bounds.contains(frame(footer)),
                    "correctStateText": controller.runtimePresentationForTest == "Est. Battery Runtime · \(snapshot.plugged ? "External Power" : name == "low-battery" ? "18m" : "4h 25m")",
                    "noRunningAnimations": controller.runningAnimationCountForTest == 0,
                ]
                let bounds = controller.view.bounds
                guard let bitmap = controller.view.bitmapImageRepForCachingDisplay(in: bounds) else { exit(2) }
                controller.view.cacheDisplay(in: bounds, to: bitmap)
                guard let png = bitmap.representation(using: .png, properties: [:]) else { exit(2) }
                let imageName = "runtime-section-\(appearance)-\(name).png"
                try png.write(to: output.appendingPathComponent(imageName), options: .atomic)

                Settings.setModule(.runtime, visible: false)
                settle()
                checks["hidingRuntimeRemoves44Points"] = fullHeight - controller.preferredHeight == 44
                checks["hidingRuntimeClosesGap"] = fullFlowY - frame(flow).minY == 44 && adjacent(header, flow)
                Settings.setModule(.runtime, visible: true)
                for module in Settings.Module.allCases where module != .runtime { Settings.setModule(module, visible: false) }
                settle()
                checks["runtimeAloneStillSeparatedAndContiguous"] = runtime.sectionLayoutForTest.hasTopSeparator && adjacent(header, runtime) && adjacent(runtime, footer)
                checks["runtimeAloneHasExpectedHeight"] = controller.preferredHeight == PopoverHeaderView.preferredHeight + 44 + PopoverFooterView.preferredHeight + 24
                Settings.setModule(.runtime, visible: false)
                settle()
                checks["allModulesHiddenNoResidualGap"] = adjacent(header, footer) && controller.preferredHeight == PopoverHeaderView.preferredHeight + PopoverFooterView.preferredHeight + 24
                checks["windowStayedHidden"] = !window.isVisible && !window.isKeyWindow
                assertions += checks.count
                failures += checks.values.filter { !$0 }.count
                records.append([
                    "case": "\(appearance)-\(name)", "checks": checks,
                    "runtimeText": "Est. Battery Runtime · \(snapshot.plugged ? "External Power" : name == "low-battery" ? "18m" : "4h 25m")",
                    "runtimeFrame": NSStringFromRect(rowFrame), "titleFrame": NSStringFromRect(layout.titleFrame),
                    "valueFrame": NSStringFromRect(layout.valueFrame), "fullContentHeight": fullHeight,
                    "fixtureRuntimeMinutes": snapshot.estimatedRuntimeMinutes as Any? ?? NSNull(),
                    "image": imageName, "imageSHA256": hash(png),
                    "imageDimensions": [bitmap.pixelsWide, bitmap.pixelsHigh],
                ])
                window.close()
            }
        }
        Settings.resetTestConfiguration()
        defaults.removePersistentDomain(forName: suite)
        let finalChecks = [
            "canonicalAppHelperAndPreferencesUnchanged": initialFiles == protectedFiles(),
            "foregroundApplicationUnchanged": initialFrontmost == NSWorkspace.shared.frontmostApplication?.processIdentifier,
            "isolatedSuiteRemoved": defaults.persistentDomain(forName: suite)?.isEmpty ?? true,
        ]
        assertions += finalChecks.count
        failures += finalChecks.values.filter { !$0 }.count
        let evidence: [String: Any] = [
            "schema": 1, "method": "Hidden NSWindow; production PopoverContentViewController cacheDisplay bitmap; Classic with forced Reduce Transparency and Reduce Motion; no live battery sampling or helper IPC.",
            "limitations": "Layout evidence only. Not a WindowServer screenshot, native popup shadow or composited Liquid Glass verification. Runtime values and power history are fixtures. Footer mode uses the process's cached/default mode and is not a simulated hardware-mode change.",
            "cases": records, "assertions": assertions, "failures": failures,
            "finalChecks": finalChecks, "protectedFileHashes": initialFiles,
            "executableSHA256": hash(try? Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[0]))),
        ]
        try JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("evidence.json"), options: .atomic)
        print("Runtime section: \(records.count) cases, \(assertions) assertions, \(failures) failures")
        exit(failures == 0 ? 0 : 1)
    }
}
