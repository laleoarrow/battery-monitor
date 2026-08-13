import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
CONTENT = ROOT / "Popover" / "PopoverContentView.swift"
POPOVER = ROOT / "Popover" / "PopoverController.swift"


class SettingsIntegrationContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.content = CONTENT.read_text(encoding="utf-8")
        cls.popover = POPOVER.read_text(encoding="utf-8")

    def test_popover_modules_use_the_shared_settings_store(self):
        self.assertIn("typealias PopoverModule = Settings.Module", self.content)
        self.assertNotIn("enum PopoverModule", self.content)
        self.assertIn("Settings.isModuleVisible", self.content)
        self.assertIn("Settings.setModule", self.content)
        self.assertNotIn("UserDefaults.standard", self.content)
        self.assertNotIn("register(defaults:", self.content)

    def test_live_popover_observes_module_changes_on_main(self):
        self.assertIn("Settings.didChange", self.content)
        observer = self.content.split("Settings.didChange", 1)[1].split("\n        )", 1)[0]
        self.assertIn("queue: .main", observer)
        self.assertIn("applyModuleVisibility()", self.content)
        self.assertIn("removeObserver", self.content)

    def test_quick_menu_settings_item_precedes_version_and_quit(self):
        menu = self.content.split("private func showModuleMenu", 1)[1].split(
            "@objc private func quitApp", 1
        )[0]
        settings_index = menu.index('title: "Settings…"')
        version_index = menu.index('title: "Wattson Version \\(version)"')
        quit_index = menu.index('title: "Quit Wattson"')
        self.assertLess(settings_index, version_index)
        self.assertLess(settings_index, quit_index)
        self.assertIn('keyEquivalent: ","', menu)
        self.assertIn("keyEquivalentModifierMask = [.command]", menu)
        self.assertIn("#selector(showSettings)", menu)
        self.assertIn("settingsHandler?()", self.content)

    def test_popover_relay_closes_before_presenting_on_next_main_turn(self):
        self.assertIn("func setSettingsHandler", self.popover)
        relay = self.popover.split("private func closeBeforePresentingSettings", 1)[1].split(
            "\n    func onVisibilityChange", 1
        )[0]
        self.assertLess(relay.index("close()"), relay.index("DispatchQueue.main.async"))
        close = self.popover.split("private func close()", 1)[1].split(
            "\n    private func closeBeforePresentingSettings", 1
        )[0]
        self.assertLess(close.index("wantsOpen = false"), close.index("stopWatchingForOutsideClicks()"))
        self.assertLess(close.index("stopWatchingForOutsideClicks()"), close.index("performClose"))


if __name__ == "__main__":
    unittest.main()
