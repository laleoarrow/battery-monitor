import AppKit
import XCTest
@testable import Wattson

final class SettingsIconReuseTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!
    private var increasedContrast = false

    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
        suite = testDefaultsSuite("SettingsIconReuse")
        defaults = UserDefaults(suiteName: suite)!
        Settings.configureForTest(defaults: defaults)
    }

    override func tearDown() {
        Settings.resetTestConfiguration()
        defaults.removePersistentTestDomain(forName: suite)
        defaults = nil
        super.tearDown()
    }

    private var dependencies: SettingsWindowDependencies {
        SettingsWindowDependencies(
            loginItemState: { .notRegistered },
            refreshLoginItem: { $0(.notRegistered) },
            setLoginItemEnabled: { _, _ in XCTFail("Icon refresh must not change login items") },
            systemBatteryIconHidden: { false },
            helperAvailable: { true },
            refreshSystemBatteryIcon: { $0(false) },
            setSystemBatteryIconHidden: { _, _ in XCTFail("Icon refresh must not change the battery icon") },
            systemBatteryIconDidChange: Notification.Name(UUID().uuidString),
            currentVersion: { "4.3.19" },
            checkForUpdates: { _ in XCTFail("Icon refresh must not query updates") },
            openUpdateURL: { _ in XCTFail("Icon refresh must not open a browser"); return false },
            increaseContrast: { [weak self] in self?.increasedContrast ?? false },
            announceAccessibility: { _ in }
        )
    }

    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }

    private func icons(in controller: SettingsWindowController) throws -> [NSImageView] {
        let content = try XCTUnwrap(controller.windowForTest?.contentView)
        var result: [NSImageView] = []
        for section in ["general", "modules"] {
            controller.selectSectionForTest(identifier: section)
            content.layoutSubtreeIfNeeded()
            result += descendants(content).compactMap { $0 as? NSImageView }.filter {
                $0.identifier?.rawValue.hasPrefix("settings.\(section).icon.") == true
            }
        }
        XCTAssertEqual(result.count, 11)
        return result
    }

    private func expectedImage(for view: NSImageView) throws -> NSImage {
        let identifier = try XCTUnwrap(view.identifier?.rawValue)
        let dark = view.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let neutral: NSColor = Settings.usesLiquidGlass ? .labelColor
            : NSColor(srgbRed: dark ? 233.0 / 255 : 36.0 / 255,
                      green: dark ? 233.0 / 255 : 36.0 / 255,
                      blue: dark ? 233.0 / 255 : 38.0 / 255, alpha: 1)
        var expected: NSImage?
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            let ink = neutral.usingColorSpace(.sRGB) ?? neutral
            let accent = NSColor.systemBlue.usingColorSpace(.sRGB) ?? .systemBlue
            if identifier.hasPrefix("settings.modules.icon."),
               let module = Settings.Module(rawValue: String(identifier.dropFirst("settings.modules.icon.".count))) {
                expected = ModuleIconArtwork.image(for: module, side: 20, ink: ink, accent: accent,
                                                   increasedContrast: increasedContrast)
            } else {
                let artwork: ModuleIconArtwork.GeneralIcon
                switch identifier {
                case "settings.general.icon.login": artwork = .login
                case "settings.general.icon.battery": artwork = .battery
                case "settings.general.icon.update": artwork = .update
                case "settings.general.icon.automatic-updates": artwork = .automatic
                case "settings.general.icon.feedback": artwork = .feedback
                default: XCTFail("Unknown icon \(identifier)"); return
                }
                expected = ModuleIconArtwork.generalImage(for: artwork, side: 20, ink: ink,
                                                          accent: accent, increasedContrast: increasedContrast)
            }
        }
        return try XCTUnwrap(expected)
    }

    func testGeneralAndModuleIconsReuseResolvedInputsAndKeepApprovedPixels() throws {
        let controller = SettingsWindowController(dependencies: dependencies, frameAutosaveName: nil)
        defer { controller.close() }
        let views = try icons(in: controller)
        let identities = views.map(ObjectIdentifier.init)
        for contrast in [false, true] {
            increasedContrast = contrast
            for appearance in [NSAppearance.Name.aqua, .darkAqua,
                               .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua] {
                for view in views {
                    view.appearance = NSAppearance(named: appearance)
                    view.viewDidChangeEffectiveAppearance()
                    let first = try XCTUnwrap(view.image)
                    let pixels = first.tiffRepresentation
                    XCTAssertEqual(pixels, try expectedImage(for: view).tiffRepresentation)
                    for _ in 0..<100 { view.viewDidChangeEffectiveAppearance() }
                    XCTAssertTrue(view.image === first)
                    XCTAssertEqual(view.image?.tiffRepresentation, pixels)
                    XCTAssertFalse(first.isTemplate)
                    XCTAssertNil(view.contentTintColor)
                    XCTAssertEqual(first.size, NSSize(width: 20, height: 20))
                }
            }
        }
        XCTAssertEqual(views.map(ObjectIdentifier.init), identities)
        XCTAssertFalse(try XCTUnwrap(controller.windowForTest).isVisible)
    }

    func testSidebarReusesSelectionArtworkAndInvalidatesContrastWithoutChangingPixels() throws {
        let controller = SettingsWindowController(dependencies: dependencies, frameAutosaveName: nil)
        defer { controller.close() }
        for (row, artwork) in ModuleIconArtwork.SidebarIcon.allCases.enumerated() {
            let cell = try XCTUnwrap(controller.tableView(controller.sidebarForTest,
                                                         viewFor: nil, row: row) as? NSTableCellView)
            let imageView = try XCTUnwrap(cell.imageView)
            for contrast in [false, true] {
                increasedContrast = contrast
                for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                    cell.appearance = NSAppearance(named: appearance)
                    cell.backgroundStyle = .normal
                    cell.viewDidChangeEffectiveAppearance()
                    let normal = try XCTUnwrap(imageView.image)
                    for _ in 0..<100 { cell.viewDidChangeEffectiveAppearance() }
                    XCTAssertTrue(imageView.image === normal)
                    cell.backgroundStyle = .emphasized
                    let selected = try XCTUnwrap(imageView.image)
                    XCTAssertFalse(selected === normal)
                    var expected: NSImage?
                    cell.effectiveAppearance.performAsCurrentDrawingAppearance {
                        expected = ModuleIconArtwork.sidebarImage(
                            for: artwork, side: 18,
                            ink: NSColor.white.usingColorSpace(.sRGB) ?? .white,
                            accent: NSColor.white.usingColorSpace(.sRGB) ?? .white,
                            increasedContrast: contrast)
                    }
                    XCTAssertEqual(selected.tiffRepresentation, expected?.tiffRepresentation)
                    for _ in 0..<100 { cell.viewDidChangeEffectiveAppearance() }
                    XCTAssertTrue(imageView.image === selected)
                    cell.backgroundStyle = .normal
                    let restored = try XCTUnwrap(imageView.image)
                    XCTAssertFalse(restored === normal, "Each owner retains only its last configuration")
                    XCTAssertEqual(restored.tiffRepresentation, normal.tiffRepresentation)
                    XCTAssertNil(imageView.contentTintColor)
                    XCTAssertEqual(restored.size, NSSize(width: 18, height: 18))
                }
            }
        }
        XCTAssertFalse(try XCTUnwrap(controller.windowForTest).isVisible)
    }

    func testTransparencyNotificationsReuseImagesAndMaterialChangeResolvesSameAppearanceAgain() throws {
        let controller = SettingsWindowController(dependencies: dependencies, frameAutosaveName: nil)
        defer { controller.close() }
        let views = try icons(in: controller)
        for view in views {
            view.appearance = NSAppearance(named: .aqua)
            view.viewDidChangeEffectiveAppearance()
        }
        let initial = try views.map { try XCTUnwrap($0.image) }
        for value in [0.75, 0.5, 0.25, 1.0] { Settings.liquidGlassTransparency = value }
        for (view, image) in zip(views, initial) { XCTAssertTrue(view.image === image) }
        increasedContrast = true
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        for (view, image) in zip(views, initial) {
            XCTAssertFalse(view.image === image)
            XCTAssertEqual(view.image?.tiffRepresentation, try expectedImage(for: view).tiffRepresentation)
        }
        if #available(macOS 26, *) {
            let classic = try views.map { try XCTUnwrap($0.image) }
            Settings.liquidGlassEnabled = true
            for (view, image) in zip(views, classic) {
                XCTAssertEqual(view.effectiveAppearance.name, .aqua)
                XCTAssertFalse(view.image === image, "A material palette change can keep the same appearance name")
                XCTAssertEqual(view.image?.tiffRepresentation, try expectedImage(for: view).tiffRepresentation)
            }
        }
        XCTAssertFalse(try XCTUnwrap(controller.windowForTest).isVisible)
    }
}
