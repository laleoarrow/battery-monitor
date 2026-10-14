import AppKit
import Foundation

/// Real production feedback flow, for a disposable GUI session only. Compile
/// with the production Core/MenuBar/Popover sources and -D DEBUG, then package
/// and sandbox-sign with BatteryPowerApp.entitlements under this distinct ID.
/// Pass --cancel and an unused .txt path to verify opening/cancellation. Pass
/// --save and the path the guest user will choose to verify actual export.
/// Sandboxed save panels require genuine user acceptance; this probe never
/// attempts to accept the out-of-process Powerbox through app-call ok(_:).
@main
private enum FeedbackExportProbe {
    static func main() {
        guard CommandLine.arguments.count == 3,
              ["--cancel", "--save"].contains(CommandLine.arguments[1]),
              Bundle.main.bundleIdentifier == "com.leoarrow.wattson.feedback-export-probe" else {
            fail("Run the isolated sandbox-signed probe bundle with --cancel|--save and an unused output .txt path.")
        }
        let app = NSApplication.shared
        let delegate = ProbeDelegate(
            output: URL(fileURLWithPath: CommandLine.arguments[2]),
            expectsSave: CommandLine.arguments[1] == "--save"
        )
        app.setActivationPolicy(.regular)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

private final class ProbeDefaults: UserDefaults {
    private var values: [String: Any] = [:]
    override func object(forKey key: String) -> Any? { values[key] }
    override func string(forKey key: String) -> String? { values[key] as? String }
    override func set(_ value: Any?, forKey key: String) { values[key] = value }
    override func set(_ value: Bool, forKey key: String) { values[key] = value }
    override func removeObject(forKey key: String) { values.removeValue(forKey: key) }
}

private final class ProbeDelegate: NSObject, NSApplicationDelegate {
    private enum Stage {
        case cancelPanel, cancelled(Date), savePanel, report
    }
    private let output: URL
    private let expectsSave: Bool
    private let defaults = ProbeDefaults()
    private var controller: SettingsWindowController!
    private var button: NSButton!
    private var stage = Stage.cancelPanel
    private var timer: Timer?
    private var openedURLs: [URL] = []

    init(output: URL, expectsSave: Bool) { self.output = output; self.expectsSave = expectsSave }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Settings.configureForTest(defaults: defaults)
        Settings.colorScheme = .dark
        Settings.liquidGlassEnabled = true
        Settings.liquidGlassStyle = .regular
        Settings.checksForUpdatesOnLaunch = false
        var snapshot = PowerSnapshot()
        snapshot.percent = 47
        snapshot.batteryW = -12.5
        snapshot.systemW = 12.5
        snapshot.batteryTimeEstimate = .remaining(132)
        var dependencies = SettingsWindowDependencies(
            loginItemState: { .enabled }, refreshLoginItem: { $0(.enabled) },
            setLoginItemEnabled: { _, _ in fail("Unexpected privileged login mutation") },
            systemBatteryIconHidden: { false }, helperAvailable: { true },
            refreshSystemBatteryIcon: { $0(false) },
            setSystemBatteryIconHidden: { _, _ in fail("Unexpected battery-icon mutation") },
            systemBatteryIconDidChange: Notification.Name("FeedbackExportProbe.Battery"),
            currentVersion: { "Sandbox-Probe" },
            checkForUpdates: { _ in fail("Unexpected update request") },
            openUpdateURL: { [weak self] url in self?.verifySavedReport(url); return true },
            increaseContrast: { false }, announceAccessibility: { _ in }
        )
        dependencies.feedbackSnapshot = { snapshot }
        dependencies.feedbackReadingIsStale = { false }
        controller = SettingsWindowController(dependencies: dependencies, frameAutosaveName: nil)
        controller.show()
        guard let content = controller.windowForTest?.contentView,
              let reportButton = descendants(content).compactMap({ $0 as? NSButton }).first(where: {
                  $0.accessibilityIdentifier() == "settings.general.feedback.button"
              }) else { fail("Missing production feedback button") }
        button = reportButton
        controller.windowForTest?.makeFirstResponder(button)
        log("PRODUCTION_FEEDBACK_BUTTON_FOUND")
        DispatchQueue.main.asyncAfter(deadline: .now() + (expectsSave ? 90 : 35)) {
            fail("Feedback flow watchdog expired")
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in self?.advance() }
        button.performClick(nil)
    }

    private func advance() {
        let panel = (controller.windowForTest?.attachedSheet as? NSSavePanel)
            ?? NSApp.windows.compactMap { $0 as? NSSavePanel }.first { $0.isVisible }
        switch stage {
        case .cancelPanel:
            guard let panel else { return }
            guard panel.nameFieldStringValue == FeedbackDiagnostics.filename,
                  panel.prompt == "Save & Open Issue",
                  panel.allowedContentTypes.contains(where: { $0.identifier == "public.plain-text" }),
                  panel.message.contains("public GitHub issue") else { fail("Unexpected production Save panel configuration") }
            log("NATIVE_SAVE_PANEL_CANCEL")
            stage = .cancelled(Date().addingTimeInterval(0.6))
            panel.cancel(nil)
        case let .cancelled(deadline):
            guard Date() >= deadline, controller.windowForTest?.attachedSheet == nil else { return }
            guard openedURLs.isEmpty, !FileManager.default.fileExists(atPath: output.path), button.isEnabled else {
                fail("Cancelled Save unexpectedly produced a file, issue URL, or disabled control")
            }
            log("CANCELLED_SAVE_PASSED: no file and no issue draft")
            if !expectsSave {
                log("SANDBOX_FEEDBACK_CANCEL_PASSED: production action and configured native save panel; acceptance/export intentionally unverified")
                timer?.invalidate()
                Settings.resetTestConfiguration()
                NSApp.terminate(nil)
                return
            }
            stage = .savePanel
            button.performClick(nil)
        case .savePanel:
            guard let panel else { return }
            guard panel.isVisible else { return }
            stage = .report
            log("NATIVE_SAVE_PANEL_READY_FOR_GUEST_USER: choose \(output.path) and accept Save")
        case .report:
            guard let content = controller.windowForTest?.contentView else { return }
            if let error = descendants(content).compactMap({ $0 as? NSTextField }).first(where: {
                $0.accessibilityIdentifier() == "settings.general.feedback.error" && !$0.isHidden
            }) { fail("Production feedback error: \(error.stringValue)") }
        }
    }

    private func verifySavedReport(_ url: URL) {
        openedURLs.append(url)
        guard openedURLs.count == 1, case .report = stage,
              url.scheme == "https", url.host == "github.com",
              url.path == "/laleoarrow/battery-monitor/issues/new" else { fail("Unexpected issue URL or flow stage") }
        do {
            let report = try String(contentsOf: output, encoding: .utf8)
            for field in ["version: Sandbox-Probe", "macOSBuild:", "macModel:", "cpuModel:",
                          "processArchitecture: arm64", "theme: dark", "liquidGlassStyle: regular",
                          "[Accessibility]", "[Helper and installation]", "batteryPercent: 47",
                          "batteryTimeKind: remaining", "estimatedRuntimeMinutes: 132",
                          "estimatedTimeToFullMinutes: unavailable", "Excludes serial numbers"] {
                guard report.contains(field) else { fail("Report missing expected field: \(field)") }
            }
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let body = components.queryItems?.first(where: { $0.name == "body" })?.value,
                  body.contains("Review and drag Wattson-Diagnostics.txt"),
                  !body.contains(output.path), button.isEnabled else { fail("Invalid reviewable draft or button state") }
            log("SANDBOX_FEEDBACK_EXPORT_PASSED: production action, native user-selected save, local report, captured GitHub draft; no browser opened or issue submitted")
            timer?.invalidate()
            Settings.resetTestConfiguration()
            NSApp.terminate(nil)
        } catch { fail("Saved report could not be read: \(error)") }
    }
}

private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
private func log(_ message: String) { FileHandle.standardOutput.write(Data((message + "\n").utf8)) }
private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("SANDBOX_FEEDBACK_EXPORT_FAILED: " + message + "\n").utf8))
    exit(1)
}
