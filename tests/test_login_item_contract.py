import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
LOGIN_ITEM = ROOT / "Core" / "LoginItemController.swift"
CONTENT = ROOT / "Popover" / "PopoverContentView.swift"


class LoginItemContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.login_item = LOGIN_ITEM.read_text(encoding="utf-8")
        cls.content = CONTENT.read_text(encoding="utf-8")

    def test_uses_the_native_main_app_login_item(self):
        self.assertIn("import ServiceManagement", self.login_item)
        self.assertIn("SMAppService.mainApp", self.login_item)
        self.assertIn("try service.register()", self.login_item)
        self.assertIn("try service.unregister()", self.login_item)

    def test_system_status_is_the_single_source_of_truth(self):
        self.assertIn("service.status", self.login_item)
        self.assertIn("case .enabled:", self.login_item)
        self.assertIn("case .requiresApproval:", self.login_item)
        self.assertIn("case .notFound:", self.login_item)
        self.assertNotIn("UserDefaults", self.login_item)

    def test_macos_12_keeps_the_option_visible_but_disabled(self):
        self.assertIn("#available(macOS 13.0, *)", self.login_item)
        self.assertIn("case unsupported", self.login_item)
        self.assertIn("loginItem.isEnabled", self.content)
        self.assertIn("需 macOS 13", self.content)

    def test_pending_approval_guides_the_user_to_system_settings(self):
        self.assertIn("SMAppService.openSystemSettingsLoginItems()", self.login_item)
        self.assertIn("待批准", self.content)
        self.assertIn(".mixed", self.content)

    def test_toggle_is_reachable_from_the_settings_menu(self):
        self.assertIn("开机自动启动", self.content)
        self.assertIn("#selector(toggleLoginItem)", self.content)
        self.assertIn("try LoginItemController.toggle()", self.content)
        self.assertIn("无法更新开机自动启动", self.content)


if __name__ == "__main__":
    unittest.main()
