import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
STATUS_SOURCE = ROOT / "MenuBar" / "StatusItemController.swift"
SAMPLER_SOURCE = ROOT / "Core" / "BatterySampler.swift"
README = ROOT / "README.md"


class FailurePathContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.status = STATUS_SOURCE.read_text(encoding="utf-8")
        cls.sampler = SAMPLER_SOURCE.read_text(encoding="utf-8")
        cls.readme = README.read_text(encoding="utf-8")

    def test_exits_cleanly_on_a_machine_with_no_battery(self):
        self.assertIn("noBattery", self.status)
        self.assertIn("NSApp.terminate", self.status)

    def test_keeps_the_last_snapshot_when_a_read_fails(self):
        # A dropped read must not blank the icon.
        self.assertIn("isDegraded", self.status)
        self.assertIn("guard let fresh = BatterySampler.sample() else", self.status)

    def test_logs_the_raw_fields_when_conservation_breaks(self):
        self.assertIn("conservationError", self.sampler)
        self.assertIn("os_log", self.sampler)

    def test_right_click_is_a_no_op_without_the_helper(self):
        self.assertIn("HelperClient.isInstalled", self.status)

    def test_readme_documents_recovery_when_the_menu_bar_hides_the_item(self):
        self.assertIn('open "$HOME/Applications/Wattson.app"', self.readme)


if __name__ == "__main__":
    unittest.main()
