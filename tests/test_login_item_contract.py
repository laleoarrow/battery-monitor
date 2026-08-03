import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
LOGIN_ITEM = ROOT / "Core" / "LoginItemController.swift"
CONTENT = ROOT / "Popover" / "PopoverContentView.swift"
POPOVER = ROOT / "Popover" / "PopoverController.swift"
HELPER = ROOT / "Helper" / "wattson-helper.swift"
UNINSTALL = ROOT / "scripts" / "uninstall.sh"


class LoginItemContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.login_item = LOGIN_ITEM.read_text(encoding="utf-8")
        cls.content = CONTENT.read_text(encoding="utf-8")
        cls.popover = POPOVER.read_text(encoding="utf-8")
        cls.helper = HELPER.read_text(encoding="utf-8")
        cls.uninstall = UNINSTALL.read_text(encoding="utf-8")

    def test_ad_hoc_build_uses_the_existing_helper_not_smappservice(self):
        self.assertNotIn("ServiceManagement", self.login_item)
        self.assertNotIn("SMAppService", self.login_item)
        self.assertIn('"getLaunchAtLoginEnabled"', self.login_item)
        self.assertIn('"setLaunchAtLoginEnabled"', self.login_item)

    def test_status_refresh_never_blocks_popover_opening(self):
        self.assertIn("DispatchQueue", self.login_item)
        self.assertIn("DispatchQueue.main.async", self.login_item)
        self.assertIn("LoginItemController.refresh", self.popover)

    def test_initial_query_is_not_misreported_as_disabled(self):
        self.assertIn("case checking", self.login_item)
        self.assertIn('? .checking', self.login_item.replace("\n", " "))
        self.assertIn("正在读取…", self.content)
        self.assertIn("loginItem.isEnabled = loginState == .notRegistered", self.content)

    def test_preview_bundle_cannot_change_the_installed_login_item(self):
        self.assertIn('Bundle.main.bundleIdentifier == "com.leoarrow.wattson"', self.login_item)

    def test_toggle_is_reachable_from_the_settings_menu(self):
        self.assertIn("开机自动启动", self.content)
        self.assertIn("#selector(toggleLoginItem)", self.content)
        self.assertIn("LoginItemController.setEnabled", self.content)
        self.assertIn("需完整安装", self.content)
        self.assertNotIn("当前不可用", self.content)

    def test_helper_accepts_only_a_boolean_and_owns_the_fixed_agent(self):
        self.assertIn('case "getLaunchAtLoginEnabled"', self.helper)
        self.assertIn('case "setLaunchAtLoginEnabled"', self.helper)
        self.assertIn('object["enabled"] as? Bool', self.helper)
        self.assertIn('com.leoarrow.wattson.login', self.helper)
        self.assertIn('Library/LaunchAgents', self.helper)
        self.assertNotIn('object["path"]', self.helper)

    def test_uninstall_removes_the_user_login_agent(self):
        self.assertIn('LOGIN_AGENT_LABEL="com.leoarrow.wattson.login"', self.uninstall)
        self.assertIn("launchctl bootout", self.uninstall)
        self.assertIn('rm -f "$LOGIN_AGENT_PLIST"', self.uninstall)


if __name__ == "__main__":
    unittest.main()
