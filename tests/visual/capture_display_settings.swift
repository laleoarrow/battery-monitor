import AppKit
import Foundation
import ScreenCaptureKit

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
    private let nativeSelected = CommandLine.arguments.contains("--native-selected")
    private let macOS27Selected = CommandLine.arguments.contains("--macos27-selected")
    private let sharedSettings = CommandLine.arguments.contains("--shared-settings")

    func applicationDidFinishLaunching(_ notification: Notification) {
        Settings.configureForTest(defaults: defaults)
        Settings.checksForUpdatesOnLaunch = false
        if macOS27Selected {
            guard let style = Settings.MenuBarIconStyle(rawValue: "native27") else {
                fputs("DISPLAY_CAPTURE_FAILED: macOS 27 style is missing\n", stderr)
                exit(1)
            }
            Settings.menuBarIconStyle = style
        } else {
            Settings.menuBarIconStyle = nativeSelected ? .native : .wattson
        }
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
                print("DISPLAY_CAPTURE_COMPLETE count=\(sharedSettings || macOS27Selected ? 4 : (nativeSelected ? 2 : (before ? 4 : 8))) before=\(before)")
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
        for glass in nativeSelected || macOS27Selected || sharedSettings ? [true] : [false, true] {
            Settings.liquidGlassStyle = .regular
            Settings.liquidGlassEnabled = glass
            for dark in [false, true] {
                Settings.colorScheme = dark ? .dark : .light
                NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                for percentage in before || nativeSelected || sharedSettings ? [true] : [false, true] {
                  for section in sharedSettings ? ["general", "modules"] : ["menu-bar-icon"] {
                    Settings.showsMenuBarPercentage = percentage
                    controller.selectSectionForTest(identifier: section)
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
                    let name = sharedSettings ? "glass-\(section)-\(dark ? "dark" : "light")"
                        : "\(glass ? "glass" : "classic")-\(dark ? "dark" : "light")-percentage-\(percentage ? "on" : "off")"
                    let views = descendants(content)
                    let details: [[String: Any]] = views.compactMap { view in
                        guard let identifier = view.identifier?.rawValue,
                              identifier.hasPrefix(sharedSettings ? "settings." : "settings.menu-bar-icon.") else { return nil }
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
                            let insets = text.alignmentRectInsets
                            row["alignmentRectInsets"] = [insets.top, insets.left, insets.bottom, insets.right]
                            if let parent = text.superview {
                                let alignment = parent.convert(text.alignmentRect(forFrame: text.frame), to: content)
                                row["alignmentRect"] = [alignment.minX, alignment.minY, alignment.width, alignment.height]
                                if identifier.hasPrefix("settings.menu-bar-icon.state-label.") {
                                    let cell = parent.convert(parent.bounds, to: content)
                                    row["headerCellFrame"] = [cell.minX, cell.minY, cell.width, cell.height]
                                }
                            }
                            if let cell = text.cell {
                                let drawing = text.convert(cell.drawingRect(forBounds: text.bounds), to: content)
                                let title = text.convert(cell.titleRect(forBounds: text.bounds), to: content)
                                row["cellDrawingRect"] = [drawing.minX, drawing.minY, drawing.width, drawing.height]
                                row["cellTitleRect"] = [title.minX, title.minY, title.width, title.height]
                            }
                            let size = text.attributedStringValue.size()
                            row["attributedStringSize"] = [size.width, size.height]
                            var state = text.superview
                            while let candidate = state,
                                  !(candidate.identifier?.rawValue.hasPrefix("settings.menu-bar-icon.state.") ?? false) {
                                state = candidate.superview
                            }
                            if let state, let parent = text.superview {
                                row["stateIdentifier"] = state.identifier?.rawValue
                                let alignment = parent.convert(text.alignmentRect(forFrame: text.frame), to: state)
                                row["alignmentRectInState"] = [alignment.minX, alignment.minY, alignment.width, alignment.height]
                                if let cell = text.cell {
                                    let drawing = text.convert(cell.drawingRect(forBounds: text.bounds), to: state)
                                    let title = text.convert(cell.titleRect(forBounds: text.bounds), to: state)
                                    row["cellDrawingRectInState"] = [drawing.minX, drawing.minY, drawing.width, drawing.height]
                                    row["cellTitleRectInState"] = [title.minX, title.minY, title.width, title.height]
                                }
                            }
                        }
                        if let image = view as? NSImageView, let artwork = image.image {
                            row["imageSize"] = [artwork.size.width, artwork.size.height]
                            row["imageScaling"] = image.imageScaling.rawValue
                        }
                        if let button = view as? NSButton {
                            row["buttonTitle"] = button.title
                            row["buttonFontSize"] = button.font?.pointSize
                            row["buttonCellClass"] = button.cell.map { NSStringFromClass(type(of: $0)) }
                            row["accessibilityRole"] = button.accessibilityRole()?.rawValue
                            row["isBordered"] = button.isBordered
                            row["bezelStyle"] = button.bezelStyle.rawValue
                            row["controlSize"] = button.controlSize.rawValue
                            row["focusRingType"] = button.focusRingType.rawValue
                            row["imagePosition"] = button.imagePosition.rawValue
                            row["buttonState"] = button.state.rawValue
                            let focus = button.convert(button.focusRingMaskBounds, to: content)
                            row["focusRingMaskBounds"] = [focus.minX, focus.minY, focus.width, focus.height]
                            if let cell = button.cell {
                                let title = button.convert(cell.titleRect(forBounds: button.bounds), to: content)
                                let image = button.convert(cell.imageRect(forBounds: button.bounds), to: content)
                                row["buttonCellTitleRect"] = [title.minX, title.minY, title.width, title.height]
                                row["buttonCellImageRect"] = [image.minX, image.minY, image.width, image.height]
                            }
                        }
                        return row
                    }
                    var report: [String: Any] = [
                        "schema": 1, "before": before, "glassRequested": glass,
                        "section": section,
                        "glassEffective": Settings.usesLiquidGlass, "dark": dark,
                        "showsPercentage": percentage, "windowKey": window.isKeyWindow,
                        "selectedIconStyle": Settings.menuBarIconStyle.rawValue,
                        "windowSize": [window.frame.width, window.frame.height],
                        "contentSize": [content.bounds.width, content.bounds.height],
                        "increaseContrast": ProcessInfo.processInfo.environment["WATTSON_FORCE_INCREASE_CONTRAST"] == "1",
                        "reduceTransparency": ProcessInfo.processInfo.environment["WATTSON_FORCE_REDUCE_TRANSPARENCY"] == "1",
                        "views": details,
                    ]
                    if #available(macOS 26, *) {
                        report["freshNativeGlassCornerRadius"] = NSGlassEffectView().cornerRadius
                        report["glassSurfaces"] = views.compactMap { view -> [String: Any]? in
                            guard let glass = view as? NSGlassEffectView else { return nil }
                            let frame = glass.convert(glass.bounds, to: content)
                            var surface: [String: Any] = [
                                "identifier": glass.identifier?.rawValue ?? "",
                                "frame": [frame.minX, frame.minY, frame.width, frame.height],
                                "cornerRadius": glass.cornerRadius,
                                "hidden": glass.isHiddenOrHasHiddenAncestor,
                            ]
                            if let box = glass.contentView as? NSBox {
                                surface["boxedControlsCornerRadius"] = box.cornerRadius
                            }
                            return surface
                        }
                    }
                    try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys, .prettyPrinted])
                        .write(to: directory.appendingPathComponent(name + "-geometry.json"), options: .atomic)
                    guard #available(macOS 14.4, *) else { throw missing("macOS 14.4 capture API") }
                    // This API intentionally exposes only this process's own
                    // shareable windows without requesting any TCC permission.
                    let shareable = try await SCShareableContent.currentProcess
                    guard let item = shareable.windows.first(where: {
                        $0.windowID == CGWindowID(window.windowNumber)
                    }) else { throw missing("own shareable window") }
                    let configuration = SCStreamConfiguration()
                    let scale = window.backingScaleFactor
                    configuration.width = Int(window.frame.width * scale)
                    configuration.height = Int(window.frame.height * scale)
                    configuration.showsCursor = false
                    configuration.capturesAudio = false
                    configuration.ignoreShadowsSingleWindow = true
                    let image = try await SCScreenshotManager.captureImage(
                        contentFilter: SCContentFilter(desktopIndependentWindow: item),
                        configuration: configuration
                    )
                    guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                        throw missing("PNG encoding")
                    }
                    try png.write(to: directory.appendingPathComponent(name + ".png"), options: .atomic)
                    print("DISPLAY_CAPTURED \(name)")
                    fflush(stdout)
                  }
                }
            }
        }
    }

    private func missing(_ item: String) -> NSError {
        NSError(domain: "Wattson.DisplayCapture", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Missing \(item)"])
    }
}
