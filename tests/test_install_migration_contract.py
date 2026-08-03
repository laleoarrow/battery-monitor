import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
INSTALL = ROOT / "scripts" / "install.sh"
UNINSTALL = ROOT / "scripts" / "uninstall.sh"
PACKAGE = ROOT / "scripts" / "package_dmg.sh"
RUN_SCRIPT = ROOT / "script" / "build_and_run.sh"
VERIFY_INTERACTION = ROOT / "scripts" / "verify_interaction.sh"
APP_ENTITLEMENTS = ROOT / "BatteryPowerApp.entitlements"


class InstallMigrationContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.install = INSTALL.read_text(encoding="utf-8")
        cls.uninstall = UNINSTALL.read_text(encoding="utf-8")
        cls.package = PACKAGE.read_text(encoding="utf-8")
        cls.run_script = RUN_SCRIPT.read_text(encoding="utf-8")
        cls.verify_interaction = VERIFY_INTERACTION.read_text(encoding="utf-8")
        cls.entitlements = APP_ENTITLEMENTS.read_text(encoding="utf-8")

    def test_uses_the_new_identity(self):
        self.assertIn("com.leoarrow.wattson", self.install)
        self.assertIn("Wattson.app", self.install)

    def test_unregisters_the_old_bundle_before_deleting_it(self):
        unregister = self.install.index('"$LSREGISTER" -u "$LEGACY_APP"')
        delete = self.install.index('rm -rf "$LEGACY_APP"')
        self.assertLess(unregister, delete)

    def test_compiles_every_source_directory(self):
        for path in ("Core/", "MenuBar/", "Popover/", "main.swift"):
            self.assertIn(path, self.install)

    def test_links_iokit(self):
        self.assertIn("-framework IOKit", self.install)

    def test_app_builds_do_not_link_the_unusable_service_management_path(self):
        self.assertNotIn("-framework ServiceManagement", self.install)
        self.assertNotIn("-framework ServiceManagement", self.run_script)
        self.assertNotIn("-framework ServiceManagement", self.verify_interaction)

    def test_run_script_does_not_reference_the_removed_legacy_source(self):
        self.assertNotIn("BatteryPowerWidget.swift", self.run_script)

    def test_preview_bundle_cannot_shadow_the_installed_app(self):
        self.assertIn('BUNDLE_ID="com.leoarrow.wattson.preview"', self.run_script)
        self.assertIn('LOG_SUBSYSTEM="com.leoarrow.wattson"', self.run_script)
        self.assertIn("<key>CFBundleIconFile</key>", self.run_script)
        self.assertIn("<string>AppIcon</string>", self.run_script)
        self.assertIn('touch "$APP_BUNDLE"', self.run_script)
        unregister = self.run_script.index('"$LSREGISTER" -u "$APP_BUNDLE"')
        delete = self.run_script.index('rm -rf "$APP_BUNDLE"')
        self.assertLess(unregister, delete)

    def test_sandbox_allows_the_new_support_directory(self):
        self.assertIn("/Library/Application Support/Wattson/", self.entitlements)
        self.assertNotIn("/Library/Application Support/电池功率/", self.entitlements)

    def test_installs_the_helper_with_sudo(self):
        self.assertIn("/Library/LaunchDaemons/", self.install)
        self.assertIn("/Library/PrivilegedHelperTools/", self.install)
        self.assertIn("launchctl bootstrap system", self.install)

    def test_uninstall_removes_the_helper(self):
        self.assertIn('HELPER_LABEL="com.leoarrow.wattson.helper"', self.uninstall)
        self.assertIn("launchctl bootout system", self.uninstall)
        self.assertIn('/Library/PrivilegedHelperTools/${HELPER_LABEL}', self.uninstall)

    def test_release_package_uses_the_wattson_identity(self):
        self.assertIn('APP_NAME="Wattson"', self.package)
        self.assertIn('APP_VERSION="${1:-2.0.2}"', self.package)
        self.assertIn("Contents/MacOS/Wattson", self.package)

    def test_release_binary_matches_the_declared_macos_minimum(self):
        self.assertIn('APP_VERSION="${WATTSON_APP_VERSION:-2.0.2}"', self.install)
        self.assertIn('SWIFT_TARGET="arm64-apple-macos12.0"', self.install)
        self.assertIn('-target "$SWIFT_TARGET"', self.install)

    def test_release_dmg_contains_a_full_install_path(self):
        self.assertIn('bash "$SCRIPT_DIR/install.sh" --app-only', self.package)
        self.assertIn('WATTSON_APP_VERSION="$APP_VERSION"', self.package)
        self.assertIn('Install Wattson.command', self.package)
        self.assertIn('Quick Start.txt', self.package)
        self.assertIn('HELPER_LABEL="com.leoarrow.wattson.helper"', self.package)
        self.assertIn('-target "$SWIFT_TARGET"', self.package)


if __name__ == "__main__":
    unittest.main()
