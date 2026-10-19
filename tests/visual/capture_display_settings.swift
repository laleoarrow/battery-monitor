import AppKit
import Foundation

/// The real Settings hierarchy in an owned GUI VM. No sampler, helper, persistent
/// preferences, system controls, or capture-permission prompt is started here.
@main
private enum DisplaySettingsCapture {
    static func main() {
        guard CommandLine.arguments.count >= 2 else { exit(64) }
        let app = NSApplication.shared
        let delegate = DisplayCaptureDelegate()
        app.setActivationPolicy(.regular)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

private final class DisplayCaptureDefaults: UserDefaults {
    private var values: [String: Any] = [:]
    override func object(forKey key: String) -> Any? { values[key] }
    override func string(forKey key: String) -> String? { values[key] as? String }
    override func set(_ value: Any?, forKey key: String) { values[key] = value }
    override func set(_ value: Bool, forKey key: String) { values[key] = value }
    override func removeObject(forKey key: String) { values.removeValue(forKey: key) }
}

private final class DisplayCaptureDelegate: NSObject, NSApplicationDelegate {
    private let defaults = DisplayCaptureDefaults()
    private var controller: SettingsWindowController!
    private let directory = URL(fileURLWithPath: CommandLine.arguments[1])
    private let before = CommandLine.arguments.contains("--before")

    func applicationDidFinishLaunching(_ notification: Notification) {
        Settings.configureForTest(defaults: defaults)
        Settings.checksForUpdatesOnLaunch = false
        Settings.menuBarIconStyle = .wattson
        let dependencies = SettingsWindowDependencies(
            loginItemState: { .enabled }, refreshLoginItem: { $0(.enabled) },
            setLoginItemEnabled: { enabled, done in done(.success(enabled ? .enabled : .notRegistered)) },
            systemBatteryIconHidden: { false }, helperAvailable: { true },
            refreshSystemBatteryIcon: { $0(false) },
            setSystemBatteryIconHidden: { _, done in done(true) },
            systemBatteryIconDidChange: Notification.Name("Wattson.DisplayCapture.MockBatteryIcon"),
            currentVersion: { "Fixture" },
            checkForUpdates: { $0(.success(.upToDate(currentVersion: "Fixture"))) },
            openUpdateURL: { _ in false },
            increaseContrast: {
                ProcessInfo.processInfo.environment["WATTSON_FORCE_INCREASE_CONTRAST"] == "1"
            },
            announceAccessibility: { _ in }
        )
        controller = SettingsWindowController(dependencies: dependencies, frameAutosaveName: nil)
        controller.windowForTest?.animationBehavior = .none
        controller.windowForTest?.center()
        Task { @MainActor in
            do {
                try await captureAll()
                controller.windowForTest?.close()
                Settings.resetTestConfiguration()
                print("DISPLAY_CAPTURE_COMPLETE count=\(before ? 4 : 8) before=\(before)")
                fflush(stdout)
                NSApp.terminate(nil)
            } catch {
                fputs("DISPLAY_CAPTURE_FAILED: \(error)\n", stderr)
                exit(1)
            }
        }
    }

    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }

    @MainActor private func captureAll() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for glass in [false, true] {
            Settings.liquidGlassStyle = .regular
            Settings.liquidGlassEnabled = glass
            for dark in [false, true] {
                Settings.colorScheme = dark ? .dark : .light
                NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                for percentage in before ? [true] : [false, true] {
                    Settings.showsMenuBarPercentage = percentage
                    controller.selectSectionForTest(identifier: "menu-bar-icon")
                    controller.refreshSectionsForTest()
                    controller.show()
                    guard let window = controller.windowForTest,
                          let content = window.contentView else { throw missing("window") }
                    window.makeFirstResponder(nil)
                    window.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)
                    window.layoutIfNeeded()
                    content.layoutSubtreeIfNeeded()
                    window.displayIfNeeded()
                    try await Task.sleep(nanoseconds: 800_000_000)
                    let name = "\(glass ? "glass" : "classic")-\(dark ? "dark" : "light")-percentage-\(percentage ? "on" : "off")"
                    let views = descendants(content)
                    let details: [[String: Any]] = views.compactMap { view in
                        guard let identifier = view.identifier?.rawValue,
                              identifier.hasPrefix("settings.menu-bar-icon.") else { return nil }
                        let frame = view.convert(view.bounds, to: content)
                        var row: [String: Any] = [
                            "identifier": identifier, "class": NSStringFromClass(type(of: view)),
                            "frame": [frame.minX, frame.minY, frame.width, frame.height],
                            "hidden": view.isHiddenOrHasHiddenAncestor,
                        ]
                        if let text = view as? NSTextField {
                            row["text"] = text.stringValue
                            row["fontSize"] = text.font?.pointSize
                            row["intrinsicWidth"] = text.intrinsicContentSize.width
                            row["intrinsicHeight"] = text.intrinsicContentSize.height
                        }
                        if let image = view as? NSImageView, let artwork = image.image {
                            row["imageSize"] = [artwork.size.width, artwork.size.height]
                            row["imageScaling"] = image.imageScaling.rawValue
                        }
                        return row
                    }
                    let report: [String: Any] = [
                        "schema": 1, "before": before, "glassRequested": glass,
                        "glassEffective": Settings.usesLiquidGlass, "dark": dark,
                        "showsPercentage": percentage, "windowKey": window.isKeyWindow,
                        "windowSize": [window.frame.width, window.frame.height],
                        "contentSize": [content.bounds.width, content.bounds.height],
                        "increaseContrast": ProcessInfo.processInfo.environment["WATTSON_FORCE_INCREASE_CONTRAST"] == "1",
                        "reduceTransparency": ProcessInfo.processInfo.environment["WATTSON_FORCE_REDUCE_TRANSPARENCY"] == "1",
                        "views": details,
                    ]
                    try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys, .prettyPrinted])
                        .write(to: directory.appendingPathComponent(name + "-geometry.json"), options: .atomic)
                    let request = try JSONSerialization.data(withJSONObject: ["window": window.windowNumber, "name": name])
                    try request.write(to: directory.appendingPathComponent("frame.json"), options: .atomic)
                    var captured = false
                    for _ in 0..<600 {
                        if FileManager.default.fileExists(atPath: directory.appendingPathComponent(name + ".captured").path) {
                            captured = true
                            break
                        }
                        try await Task.sleep(nanoseconds: 100_000_000)
                    }
                    guard captured else { throw missing("capture receipt \(name)") }
                    print("DISPLAY_CAPTURED \(name)")
                    fflush(stdout)
                }
            }
        }
    }

    private func missing(_ item: String) -> NSError {
        NSError(domain: "Wattson.DisplayCapture", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Missing \(item)"])
    }
}
