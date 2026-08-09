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
        key = self.source.split("static func renderKey", 1)[1].split(
            "static func image", 1
        )[0]
        self.assertIn("if pressed", key)
        self.assertIn(".template", key)

    def test_render_key_tracks_every_input_that_can_change_the_pixels(self):
        self.assertIn("struct RenderKey: Equatable", self.source)
        for field in ("percent", "plugged", "tintRole", "appearanceName",
                      "increasedContrast"):
            self.assertIn(field, self.source)

    def test_color_priority_is_low_power_then_low_battery_then_charging(self):
        low_power = self.source.index("systemYellow")
        low_battery = self.source.index("systemRed")
        charging = self.source.index("systemGreen")
        self.assertLess(low_power, low_battery)
        self.assertLess(low_battery, charging)

    def test_icon_is_one_point_larger_than_the_system_asset_canvas(self):
        width = re.search(r"static let width: CGFloat = ([\d.]+)", self.source)
        height = re.search(r"static let height: CGFloat = ([\d.]+)", self.source)
        self.assertIsNotNone(width)
        self.assertIsNotNone(height)
        self.assertEqual(float(width.group(1)), 23.0)
        self.assertEqual(float(height.group(1)), 14.0)
        self.assertIn("scaleBy(x: width / 22, y: height / 13)", self.source)


    def test_bolt_overflows_the_shell(self):
        # The system bolt is 9x12 against a 10pt shell, so it breaks the
        # outline top and bottom. Containing it inside the shell is what made
        # the glyph read as undersized.
        shell = re.search(r"let shell = NSRect\(x: [\d.]+, y: ([\d.]+), width: [\d.]+, height: ([\d.]+)\)", self.source)
        self.assertIsNotNone(shell)
        top = float(shell.group(1)) + float(shell.group(2))
        ys = [float(m) for m in re.findall(r"bolt\.(?:move|line)\(to: NSPoint\(x: [\d.]+, y: ([\d.]+)\)\)", self.source)]
        self.assertTrue(ys, "bolt path not found")
        self.assertGreater(max(ys), top, "bolt must break the top of the shell")
        self.assertLess(min(ys), float(shell.group(1)), "bolt must break the bottom of the shell")


if __name__ == "__main__":
    unittest.main()
