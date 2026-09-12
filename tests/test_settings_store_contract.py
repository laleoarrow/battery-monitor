import pathlib
import subprocess
import tempfile
import textwrap
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
SETTINGS = ROOT / "Core" / "Settings.swift"


class SettingsStoreContractTests(unittest.TestCase):
    def test_settings_store_runtime_contract(self):
        harness = textwrap.dedent(
            r'''
            import Foundation

            func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
                guard condition() else {
                    FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
                    exit(1)
                }
            }

            let suiteName = "com.leoarrow.wattson.tests.settings.\(UUID().uuidString)"
            guard let defaults = UserDefaults(suiteName: suiteName) else {
                fatalError("could not create isolated defaults suite")
            }
            defaults.removePersistentDomain(forName: suiteName)
            Settings.configureForTest(defaults: defaults)
            defer {
                Settings.resetTestConfiguration()
                defaults.removePersistentDomain(forName: suiteName)
            }

            let expectedModules: [(Settings.Module, String, String)] = [
                (.flow, "Energy Flow", "popover.module.flow"),
                (.ring, "Ring Gauge", "popover.module.ring"),
                (.lanes, "Power Lanes", "popover.module.lanes"),
                (.history, "Power History", "popover.module.history"),
            ]
            expect(
                Settings.Module.allCases.map(\.rawValue) == ["flow", "ring", "lanes", "history"],
                "module order or raw values changed"
            )
            for (module, title, key) in expectedModules {
                expect(module.title == title, "wrong title for \(module.rawValue)")
                expect(module.defaultsKey == key, "wrong key for \(module.rawValue)")
                expect(Settings.isModuleVisible(module), "\(module.rawValue) must default visible")
            }
            expect(Settings.showsMenuBarPercentage, "percentage must default on")
            expect(Settings.menuBarIconStyle == .wattson,
                   "existing users must retain the Wattson icon by default")
            expect(Settings.MenuBarIconStyle.allCases.map(\.rawValue) == ["wattson", "native"],
                   "icon styles must remain strongly typed and ordered")
            expect(Settings.checksForUpdatesOnLaunch,
                   "launch update checking must default on")
            expect(!Settings.liquidGlassEnabled && !Settings.usesLiquidGlass,
                   "upgrades must retain the classic appearance until opted in")
            expect((defaults.persistentDomain(forName: suiteName) ?? [:]).isEmpty,
                   "reading defaults must not persist preferences")

            var changes: [Settings.Change] = []
            var observedAppearances: [(Settings.MenuBarIconStyle, Bool)] = []
            var keptNilObject = true
            let observer = NotificationCenter.default.addObserver(
                forName: Settings.didChange,
                object: nil,
                queue: nil
            ) { notification in
                keptNilObject = keptNilObject && notification.object == nil
                guard let change = notification.userInfo?[Settings.changeUserInfoKey]
                        as? Settings.Change else {
                    FileHandle.standardError.write(Data("FAIL: missing typed change payload\n".utf8))
                    exit(1)
                }
                changes.append(change)
                observedAppearances.append((
                    Settings.menuBarIconStyle,
                    Settings.showsMenuBarPercentage
                ))
            }
            defer { NotificationCenter.default.removeObserver(observer) }

            Settings.showsMenuBarPercentage = true
            expect(changes.isEmpty, "an unchanged percentage must not notify")
            Settings.showsMenuBarPercentage = false
            expect(changes == [.menuBarPercentage],
                   "percentage change must notify exactly once")
            Settings.showsMenuBarPercentage = false
            expect(changes == [.menuBarPercentage],
                   "repeating a percentage value must not notify")

            Settings.menuBarIconStyle = .wattson
            expect(changes == [.menuBarPercentage],
                   "an unchanged icon style must not notify")
            Settings.menuBarIconStyle = .native
            expect(changes == [.menuBarPercentage, .menuBarIconStyle],
                   "icon style change must notify exactly once")
            expect(defaults.string(forKey: "menubar.iconStyle") == "native",
                   "icon style must persist its stable raw value")
            expect(Settings.menuBarIconStyle == .native,
                   "icon style must read back as the strong type")
            Settings.menuBarIconStyle = .native
            expect(changes == [.menuBarPercentage, .menuBarIconStyle],
                   "repeating an icon style must not notify")

            changes.removeAll()
            observedAppearances.removeAll()
            Settings.setMenuBarAppearance(iconStyle: .wattson, showsPercentage: true)
            expect(
                changes == [.menuBarIconStyle, .menuBarPercentage],
                "changing both appearance dimensions emits both existing notifications"
            )
            expect(
                observedAppearances.count == 2
                    && observedAppearances.allSatisfy { style, percentage in
                        style == .wattson && percentage
                    },
                "every atomic appearance notification observes the complete landed preset"
            )
            expect(
                defaults.string(forKey: "menubar.iconStyle") == "wattson"
                    && defaults.object(forKey: "menubar.showsPercentage") as? Bool == true,
                "atomic appearance persists both existing keys"
            )
            Settings.setMenuBarAppearance(iconStyle: .wattson, showsPercentage: true)
            expect(
                changes == [.menuBarIconStyle, .menuBarPercentage],
                "repeating a complete appearance emits no notification"
            )
            Settings.setMenuBarAppearance(iconStyle: .wattson, showsPercentage: false)
            expect(
                changes == [.menuBarIconStyle, .menuBarPercentage, .menuBarPercentage],
                "changing only percentage emits only its existing notification"
            )
            expect(
                observedAppearances.last?.0 == .wattson
                    && observedAppearances.last?.1 == false,
                "single-dimension atomic notification observes the landed preset"
            )

            changes.removeAll()

            Settings.checksForUpdatesOnLaunch = true
            expect(changes.isEmpty,
                   "an unchanged launch update preference must not notify")
            Settings.checksForUpdatesOnLaunch = false
            expect(changes == [.checkForUpdatesOnLaunch],
                   "launch update preference change must notify exactly once")
            Settings.checksForUpdatesOnLaunch = false
            expect(changes == [.checkForUpdatesOnLaunch],
                   "repeating launch update preference must not notify")
            expect(defaults.object(forKey: "updates.checkOnLaunch") as? Bool == false,
                   "launch update preference must persist")

            changes.removeAll()

            Settings.liquidGlassEnabled = false
            expect(changes.isEmpty, "an unchanged appearance must not notify")
            Settings.liquidGlassEnabled = true
            expect(changes == [.liquidGlassAppearance],
                   "appearance change must emit exactly one typed notification")
            expect(defaults.object(forKey: "appearance.liquidGlassEnabled") as? Bool == true,
                   "appearance opt-in must be persisted before notification")
            if #available(macOS 26.0, *) {
                expect(Settings.usesLiquidGlass, "supported systems honor the opt-in")
            } else {
                expect(!Settings.usesLiquidGlass, "older systems keep the classic appearance")
            }
            Settings.liquidGlassEnabled = true
            expect(changes == [.liquidGlassAppearance],
                   "repeating the appearance must not notify")
            Settings.liquidGlassEnabled = false
            expect(changes == [.liquidGlassAppearance, .liquidGlassAppearance]
                       && !Settings.usesLiquidGlass,
                   "turning off immediately restores classic appearance")
            Settings.liquidGlassEnabled = true
            changes.removeAll()

            Settings.setModule(.flow, visible: true)
            expect(changes.isEmpty,
                   "an unchanged module must not notify")
            Settings.setModule(.flow, visible: false)
            expect(changes == [.module(.flow)],
                   "module change must identify the changed module")
            Settings.setModule(.flow, visible: false)
            expect(changes == [.module(.flow)],
                   "repeating a module value must not notify")
            expect(!Settings.isModuleVisible(.flow), "module write must persist")
            defaults.set("future-style", forKey: "menubar.iconStyle")
            expect(Settings.menuBarIconStyle == .wattson,
                   "unknown future values must safely fall back to Wattson")
            expect(keptNilObject, "legacy notification object must remain nil")

            let secondSuite = suiteName + ".second"
            let secondDefaults = UserDefaults(suiteName: secondSuite)!
            defer { secondDefaults.removePersistentDomain(forName: secondSuite) }
            Settings.configureForTest(defaults: secondDefaults)
            expect(Settings.showsMenuBarPercentage && Settings.isModuleVisible(.flow),
                   "a fresh suite must retain its own default values")
            expect(!Settings.liquidGlassEnabled, "fresh suites must not inherit the opt-in")
            secondDefaults.set(true, forKey: "appearance.liquidGlassEnabled")
            expect(Settings.liquidGlassEnabled, "appearance reads external writes immediately")
            secondDefaults.removeObject(forKey: "appearance.liquidGlassEnabled")
            expect(!Settings.liquidGlassEnabled, "removing opt-in restores classic default")
            secondDefaults.set(["invalid"], forKey: "appearance.liquidGlassEnabled")
            expect(!Settings.liquidGlassEnabled, "invalid appearance values fail to classic")
            secondDefaults.set(false, forKey: "menubar.showsPercentage")
            expect(!Settings.showsMenuBarPercentage,
                   "external preference changes must remain immediately visible")
            secondDefaults.removeObject(forKey: "menubar.showsPercentage")
            expect(Settings.showsMenuBarPercentage,
                   "removing a preference must restore its default")
            secondDefaults.set(["invalid"], forKey: "menubar.showsPercentage")
            secondDefaults.set(["invalid"], forKey: "updates.checkOnLaunch")
            secondDefaults.set(["invalid"], forKey: "menubar.iconStyle")
            expect(Settings.showsMenuBarPercentage && Settings.checksForUpdatesOnLaunch
                       && Settings.menuBarIconStyle == .wattson,
                   "invalid stored types must fall back to safe defaults")
            for module in Settings.Module.allCases {
                secondDefaults.set(false, forKey: module.defaultsKey)
                expect(!Settings.isModuleVisible(module), "external module writes must stay visible")
                secondDefaults.removeObject(forKey: module.defaultsKey)
                expect(Settings.isModuleVisible(module), "removed module values must default visible")
                secondDefaults.set(["invalid"], forKey: module.defaultsKey)
                expect(Settings.isModuleVisible(module), "invalid module values must default visible")
            }

            Settings.configureForTest(defaults: UserDefaults(suiteName: suiteName)!)
            expect(!Settings.showsMenuBarPercentage && !Settings.checksForUpdatesOnLaunch
                       && !Settings.isModuleVisible(.flow),
                   "reopening the original suite must preserve its saved choices")
            expect(Settings.liquidGlassEnabled,
                   "reopening the original suite must preserve the appearance opt-in")
            '''
        )

        with tempfile.TemporaryDirectory(prefix="wattson-settings-contract-") as temp:
            temp_path = pathlib.Path(temp)
            main = temp_path / "main.swift"
            binary = temp_path / "settings-contract"
            main.write_text(harness, encoding="utf-8")
            compile_result = subprocess.run(
                [
                    "xcrun",
                    "swiftc",
                    "-swift-version",
                    "5",
                    "-D",
                    "DEBUG",
                    str(SETTINGS),
                    str(main),
                    "-o",
                    str(binary),
                ],
                cwd=ROOT,
                capture_output=True,
                text=True,
                timeout=60,
            )
            self.assertEqual(
                compile_result.returncode,
                0,
                f"settings contract did not compile:\n{compile_result.stderr}",
            )
            run_result = subprocess.run(
                [str(binary)],
                cwd=ROOT,
                capture_output=True,
                text=True,
                timeout=10,
            )
            self.assertEqual(
                run_result.returncode,
                0,
                f"settings contract failed:\n{run_result.stdout}{run_result.stderr}",
            )


if __name__ == "__main__":
    unittest.main()
