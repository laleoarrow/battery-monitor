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
        self.assertIn("LoginItemController.refresh", self.popover)
        refresh = self.login_item.split("static func refresh", 1)[1].split(
            "static func setEnabled", 1
        )[0]
        self.assertIn("operations.enqueueRead", refresh)

    def test_toggle_uses_the_serial_mutation_lane_ahead_of_pending_reads(self):
        setter = self.login_item.split("static func setEnabled", 1)[1]
        self.assertIn("operations.enqueueMutation", setter)

    def test_toggle_enters_checking_and_rejects_duplicate_updates(self):
        setter = self.login_item.split("static func setEnabled", 1)[1]
        self.assertIn("updateInFlight = true", setter)
        self.assertIn("cachedState = .checking", setter)
        self.assertIn("guard !updateInFlight", setter)
        self.assertIn("LoginItemError.updateInProgress", setter)

    def test_failed_toggle_does_not_chain_a_second_blocking_helper_call(self):
        setter = self.login_item.split("static func setEnabled", 1)[1].split(
            "private static func authoritative", 1
        )[0]
        operation = setter.split("operation: {", 1)[1].split(
            "completion: { result", 1
        )[0]
        self.assertEqual(operation.count("send("), 1)
        self.assertIn("refresh()", setter)

    def test_unavailable_refresh_invalidates_before_returning(self):
        refresh = self.login_item.split("static func refresh", 1)[1].split(
            "static func setEnabled", 1
        )[0]
        unavailable = refresh.split("guard isAvailable else", 1)[1].split(
            "guard !updateInFlight", 1
        )[0]
        self.assertIn("generation += 1", unavailable)

    def test_helper_budget_covers_the_bounded_launchctl_sequence(self):
        self.assertEqual(self.login_item.count("timeoutSeconds: 15"), 2)

    def test_initial_query_is_not_misreported_as_disabled(self):
        self.assertIn("case checking", self.login_item)
        self.assertIn('? .checking', self.login_item.replace("\n", " "))
        self.assertIn("Checking…", self.content)
        self.assertIn("loginItem.isEnabled = loginState == .notRegistered", self.content)

    def test_preview_bundle_cannot_change_the_installed_login_item(self):
        self.assertIn('Bundle.main.bundleIdentifier == "com.leoarrow.wattson"', self.login_item)
        self.assertIn('canonicalAppPath = "/Applications/Wattson.app"', self.login_item)
        self.assertIn("Bundle.main.bundleURL.standardizedFileURL.path", self.login_item)

    def test_toggle_is_reachable_from_the_settings_menu(self):
        self.assertIn("Launch at Login", self.content)
        self.assertIn("#selector(toggleLoginItem)", self.content)
        self.assertIn("LoginItemController.setEnabled", self.content)
        self.assertIn("Full Installer Required", self.content)
        self.assertNotIn("Currently Unavailable", self.content)

    def test_helper_accepts_only_a_boolean_and_owns_the_fixed_agent(self):
        self.assertIn('case "getLaunchAtLoginEnabled"', self.helper)
        self.assertIn('case "setLaunchAtLoginEnabled"', self.helper)
        self.assertIn('strictJSONBool(object["enabled"])', self.helper)
        self.assertIn('com.leoarrow.wattson.login', self.helper)
        self.assertIn('Library/LaunchAgents', self.helper)
        self.assertNotIn('object["path"]', self.helper)

    def test_uninstall_removes_the_user_login_agent(self):
        self.assertIn('LOGIN_AGENT_LABEL="com.leoarrow.wattson.login"', self.uninstall)
        self.assertIn("launchctl bootout", self.uninstall)
        self.assertIn('rm -f -- "$LOGIN_AGENT_PLIST"', self.uninstall)


if __name__ == "__main__":
    unittest.main()
