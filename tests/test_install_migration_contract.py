import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
INSTALL = ROOT / "scripts" / "install.sh"
UNINSTALL = ROOT / "scripts" / "uninstall.sh"
PACKAGE = ROOT / "scripts" / "package_dmg.sh"
APP_ENTITLEMENTS = ROOT / "BatteryPowerApp.entitlements"


class InstallMigrationContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.install = INSTALL.read_text(encoding="utf-8")
        cls.uninstall = UNINSTALL.read_text(encoding="utf-8")
        cls.package = PACKAGE.read_text(encoding="utf-8")
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
        self.assertIn('APP_VERSION="${1:-2.0.0}"', self.package)
        self.assertIn("Contents/MacOS/Wattson", self.package)


if __name__ == "__main__":
    unittest.main()
