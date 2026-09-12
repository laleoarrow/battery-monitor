import AppKit
import Foundation

/// Captures the shipping Settings AppKit hierarchy without touching the live
/// helper, login-item state, system battery icon, or persistent preferences.
///
/// Build with `-D DEBUG` so the harness can select each retained settings page.
/// The retained window is never ordered front or made key; AppKit renders its
/// real frame hierarchy into a bitmap cache without interrupting the active
/// desktop. Pass a section, output PNG path, and optional appearance choices.
/// A view-cache image verifies layout, not WindowServer-composited Liquid Glass.
@main
private enum CaptureRealSettings {
    static func main() {
        guard (3...5).contains(CommandLine.arguments.count) else {
            fputs("usage: capture_real_settings general|menu-bar-icon|modules OUTPUT.png [classic|glass] [light|dark]\n", stderr)
            exit(2)
        }
        let section = CommandLine.arguments[1]
        guard ["general", "menu-bar-icon", "modules"].contains(section) else {
            fputs("section must be general, menu-bar-icon, or modules\n", stderr)
            exit(2)
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        let theme = CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : "classic"
        let appearance = CommandLine.arguments.count > 4 ? CommandLine.arguments[4] : "dark"
        guard ["classic", "glass"].contains(theme), ["light", "dark"].contains(appearance) else {
            fputs("invalid theme or appearance\n", stderr)
            exit(2)
        }
        app.appearance = NSAppearance(named: appearance == "light" ? .aqua : .darkAqua)

        let suiteName = "Wattson.SettingsCapture.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fputs("could not create isolated settings defaults\n", stderr)
            exit(2)
        }
        defaults.removePersistentDomain(forName: suiteName)
        Settings.configureForTest(defaults: defaults)
        Settings.liquidGlassEnabled = theme == "glass"
        defer {
            Settings.resetTestConfiguration()
            defaults.removePersistentDomain(forName: suiteName)
        }

        let fixtureNotification = Notification.Name("Wattson.SettingsCapture.Battery")
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "Development Build"
        let dependencies = SettingsWindowDependencies(
            loginItemState: { .enabled },
            refreshLoginItem: { $0(.enabled) },
            setLoginItemEnabled: { enabled, completion in
                completion(.success(enabled ? .enabled : .notRegistered))
            },
            systemBatteryIconHidden: { false },
            helperAvailable: { true },
            refreshSystemBatteryIcon: { $0(false) },
            setSystemBatteryIconHidden: { _, completion in completion(true) },
            systemBatteryIconDidChange: fixtureNotification,
            currentVersion: { version },
            checkForUpdates: { $0(.success(.upToDate(currentVersion: version))) },
            openUpdateURL: { _ in true },
            increaseContrast: { false },
            announceAccessibility: { _ in }
        )
        let controller = SettingsWindowController(
            dependencies: dependencies,
            frameAutosaveName: nil
        )
        guard let window = controller.windowForTest else {
            fputs("settings window was not created\n", stderr)
            exit(2)
        }
        window.animationBehavior = .none
        controller.selectSectionForTest(identifier: section)
        controller.refreshSectionsForTest()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))

        do {
            try capture(
                controller: controller,
                section: section,
                path: CommandLine.arguments[2]
            )
        } catch {
            fputs("settings capture failed: \(error)\n", stderr)
            exit(2)
        }
        window.close()
        print("Settings layout capture: theme=\(theme) appearance=\(appearance) glassEffective=\(Settings.usesLiquidGlass) compositedGlassEvidence=false")
    }

    private static func capture(
        controller: SettingsWindowController,
        section: String,
        path: String
    ) throws {
        controller.selectSectionForTest(identifier: section)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        guard let window = controller.windowForTest,
              let content = window.contentView,
              let frameView = content.superview else {
            throw CaptureError.missingWindowSurface
        }
        content.layoutSubtreeIfNeeded()
        frameView.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        frameView.displayIfNeeded()
        try renderAppKitFrame(frameView, to: path)
    }

    private static func renderAppKitFrame(_ frameView: NSView, to path: String) throws {
        let bounds = frameView.bounds
        guard let bitmap = frameView.bitmapImageRepForCachingDisplay(in: bounds) else {
            throw CaptureError.couldNotEncodePNG
        }
        frameView.cacheDisplay(in: bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw CaptureError.couldNotEncodePNG
        }
        try png.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    private enum CaptureError: Error {
        case missingWindowSurface
        case couldNotEncodePNG
    }
}
