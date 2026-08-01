import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
ICON_SOURCE = ROOT / "MenuBar" / "BatteryIcon.swift"


class BatteryIconContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = ICON_SOURCE.read_text(encoding="utf-8")

    def test_default_state_is_a_template_image(self):
        # Template is the only way the icon matches the system battery across
        # light, dark and selected menu bars.
        self.assertIn("isTemplate = true", self.source)

    def test_colored_states_are_not_template(self):
        self.assertIn("isTemplate = false", self.source)

    def test_pressed_state_falls_back_to_template(self):
        # A colored image does not invert under the selection highlight.
        self.assertIn("pressed", self.source)
        match = re.search(r"if pressed \{[^}]*isTemplate = true", self.source, re.DOTALL)
        self.assertIsNotNone(match, "pressed must force template rendering")

    def test_color_priority_is_low_power_then_low_battery_then_charging(self):
        low_power = self.source.index("systemYellow")
        low_battery = self.source.index("systemRed")
        charging = self.source.index("systemGreen")
        self.assertLess(low_power, low_battery)
        self.assertLess(low_battery, charging)

    def test_icon_keeps_the_system_battery_width(self):
        match = re.search(r"static let width: CGFloat = ([\d.]+)", self.source)
        self.assertIsNotNone(match)
        # The system glyph on macOS 26 is 25 pt. Going wider would waste scarce
        # menu-bar space; going narrower looks undersized beside it.
        self.assertEqual(float(match.group(1)), 25.0)


if __name__ == "__main__":
    unittest.main()
