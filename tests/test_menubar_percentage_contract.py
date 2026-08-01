import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SETTINGS = ROOT / "Core" / "Settings.swift"
STATUS = ROOT / "MenuBar" / "StatusItemController.swift"
CONTENT = ROOT / "Popover" / "PopoverContentView.swift"


class MenuBarPercentageContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.settings = SETTINGS.read_text(encoding="utf-8")
        cls.status = STATUS.read_text(encoding="utf-8")
        cls.content = CONTENT.read_text(encoding="utf-8")

    def test_percentage_is_on_by_default(self):
        # Matches the system battery's "Show Percentage" once enabled.
        self.assertIn("as? Bool ?? true", self.settings)

    def test_percentage_sits_left_of_the_glyph(self):
        # The system puts the number before the battery, not after.
        self.assertIn("imagePosition = .imageRight", self.status)

    def test_percentage_uses_tabular_digits(self):
        # Keep the exact menu-bar face and only switch its number-spacing
        # feature. A fully monospaced system font looks unlike its neighbours.
        self.assertIn("menuBarFont", self.status)
        self.assertIn("kMonospacedNumbersSelector", self.status)

    def test_title_is_plain_so_appkit_keeps_the_colour_right(self):
        # An attributed title would not invert under the pressed highlight and
        # would not follow light/dark on its own.
        self.assertNotIn("attributedTitle", self.status)

    def test_hiding_the_percentage_leaves_the_glyph_alone(self):
        self.assertIn("imagePosition = .imageOnly", self.status)

    def test_status_item_redraws_when_the_setting_changes(self):
        self.assertIn("Settings.didChange", self.status)
        self.assertIn("static let didChange", self.settings)
        self.assertIn("NotificationCenter.default.post", self.settings)

    def test_toggle_is_reachable_from_the_popover(self):
        self.assertIn("菜单栏显示电量百分比", self.content)
        self.assertIn("Settings.showsMenuBarPercentage.toggle()", self.content)


if __name__ == "__main__":
    unittest.main()
