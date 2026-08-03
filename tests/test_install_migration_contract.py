import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
INSTALL = ROOT / "scripts" / "install.sh"
UNINSTALL = ROOT / "scripts" / "uninstall.sh"
PACKAGE = ROOT / "scripts" / "package_dmg.sh"
INSTALLER = ROOT / "Installer" / "main.swift"
INSTALLER_HELPER = ROOT / "Installer" / "install-helper.sh"
APP_MAIN = ROOT / "main.swift"
STATUS_ITEM = ROOT / "MenuBar" / "StatusItemController.swift"
HELPER_SOURCE = ROOT / "Helper" / "wattson-helper.swift"
RUN_SCRIPT = ROOT / "script" / "build_and_run.sh"
VERIFY_INTERACTION = ROOT / "scripts" / "verify_interaction.sh"
APP_ENTITLEMENTS = ROOT / "BatteryPowerApp.entitlements"


class InstallMigrationContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.install = INSTALL.read_text(encoding="utf-8")
        cls.uninstall = UNINSTALL.read_text(encoding="utf-8")
        cls.package = PACKAGE.read_text(encoding="utf-8")
        cls.installer = INSTALLER.read_text(encoding="utf-8")
        cls.installer_helper = INSTALLER_HELPER.read_text(encoding="utf-8")
        cls.app_main = APP_MAIN.read_text(encoding="utf-8")
        cls.status_item = STATUS_ITEM.read_text(encoding="utf-8")
        cls.helper_source = HELPER_SOURCE.read_text(encoding="utf-8")
        cls.run_script = RUN_SCRIPT.read_text(encoding="utf-8")
        cls.verify_interaction = VERIFY_INTERACTION.read_text(encoding="utf-8")
        cls.entitlements = APP_ENTITLEMENTS.read_text(encoding="utf-8")

    def test_uses_the_new_identity(self):
        self.assertIn("com.leoarrow.wattson", self.install)
        self.assertIn("Wattson.app", self.install)
        self.assertIn('open \\"$APP_DIR\\"', self.install)
        self.assertNotIn('open -a ${APP_NAME}', self.install)

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
        self.assertIn('APP_VERSION="${1:-2.0.3}"', self.package)
        self.assertIn("Contents/MacOS/Wattson", self.package)

    def test_release_binary_matches_the_declared_macos_minimum(self):
        self.assertIn('APP_VERSION="${WATTSON_APP_VERSION:-2.0.3}"', self.install)
        self.assertIn('SWIFT_TARGET="arm64-apple-macos12.0"', self.install)
        self.assertIn('-target "$SWIFT_TARGET"', self.install)

    def test_release_dmg_has_one_graphical_install_path(self):
        self.assertIn('bash "$SCRIPT_DIR/install.sh" --app-only', self.package)
        self.assertIn('WATTSON_APP_VERSION="$APP_VERSION"', self.package)
        self.assertIn('INSTALLER_NAME="Install Wattson.app"', self.package)
        self.assertIn('Installer/main.swift', self.package)
        self.assertIn('Wattson.zip', self.package)
        self.assertNotIn('Install Wattson.command', self.package)
        self.assertNotIn('Quick Start.txt', self.package)
        self.assertNotIn('ln -s /Applications', self.package)

    def test_release_dmg_is_world_traversable_and_not_spotlight_indexed(self):
        self.assertIn('chmod 755 "$STAGING_DIR"', self.package)
        self.assertIn('.metadata_never_index', self.package)
        self.assertIn('chmod -R a+rX "$STAGING_DIR"', self.package)
        self.assertIn('verify_dmg.sh', self.package)

    def test_graphical_installer_preserves_the_privileged_features(self):
        self.assertIn('install-helper.sh', self.installer)
        self.assertIn('with administrator privileges', self.installer)
        self.assertIn('/Library/PrivilegedHelperTools/', self.installer_helper)
        self.assertIn('/Library/LaunchDaemons/', self.installer_helper)
        self.assertIn('HELPER_LABEL="com.leoarrow.wattson.helper"', self.package)
        self.assertIn('-target "$SWIFT_TARGET"', self.package)

    def test_privileged_installer_uses_only_fixed_verified_targets(self):
        self.assertNotIn("eval ", self.installer_helper)
        self.assertNotIn('SOURCE_HELPER="$1"', self.installer_helper)
        self.assertNotIn('SOURCE_PLIST="$2"', self.installer_helper)
        self.assertIn('duplicate_id', self.installer_helper)
        self.assertIn('duplicate_id" == "com.leoarrow.wattson"', self.installer_helper)
        self.assertIn('/usr/bin/codesign --verify --strict', self.installer_helper)

    def test_helper_replacement_is_transactional(self):
        self.assertIn("HELPER_CANDIDATE", self.installer_helper)
        self.assertIn("BACKUP_HELPER", self.installer_helper)
        self.assertIn("rollback_helper_install", self.installer_helper)
        self.assertIn("replacement_started=1", self.installer_helper)
        self.assertIn("DUPLICATE_BACKUP", self.installer_helper)
        self.assertIn("duplicate_moved=1", self.installer_helper)
        self.assertIn("trap rollback_helper_install EXIT", self.installer_helper)
        candidate_validation = self.installer_helper.index('validate_helper "$HELPER_CANDIDATE"')
        replacement = self.installer_helper.index("replacement_started=1")
        stop_old_service = self.installer_helper.index('/bin/launchctl bootout system', replacement)
        self.assertLess(candidate_validation, stop_old_service)

    def test_privileged_phase_is_pinned_and_staged_by_root(self):
        self.assertIn("__INSTALL_HELPER_SHA256__", self.installer)
        self.assertIn("__HELPER_BINARY_SHA256__", self.installer)
        self.assertIn("__HELPER_PLIST_SHA256__", self.installer)
        self.assertIn("mktemp -d /private/tmp/com.leoarrow.wattson.install.XXXXXX", self.installer)
        self.assertIn("expectedInstallHelperSHA256", self.installer)
        self.assertIn("expectedHelperBinarySHA256", self.installer)
        self.assertIn("expectedHelperPlistSHA256", self.installer)
        self.assertIn("/usr/bin/env -i", self.installer)
        self.assertIn("/bin/bash -p -c", self.installer)
        self.assertIn("trap 'exit 130' HUP INT TERM", self.installer)
        self.assertIn("rollback data preserved", self.installer)
        self.assertIn("INSTALL_HELPER_SHA256", self.package)
        self.assertIn("HELPER_BINARY_SHA256", self.package)
        self.assertIn("HELPER_PLIST_SHA256", self.package)

    def test_graphical_install_requires_its_read_only_signed_dmg(self):
        self.assertIn("MNT_RDONLY", self.installer)
        self.assertIn('codesign", ["--verify", "--deep", "--strict"', self.installer)
        self.assertIn("请直接从只读 DMG", self.installer)

    def test_application_replacement_is_transactional(self):
        self.assertIn("ApplicationInstallTransaction", self.installer)
        self.assertIn("rollbackApplicationInstall", self.installer)
        self.assertIn("commitApplicationInstall", self.installer)
        helper = self.installer.index("installPrivilegedHelper")
        commit = self.installer.index("commitApplicationInstall")
        self.assertLess(helper, commit)

    def test_command_capture_cannot_fill_a_pipe_or_wait_forever(self):
        self.assertNotIn("let output = Pipe()", self.installer)
        self.assertIn("WattsonInstallerCommand-", self.installer)
        self.assertIn("timeout: TimeInterval", self.installer)
        self.assertIn("SIGKILL", self.installer)
        self.assertIn("process.environment = [", self.installer)

    def test_success_requires_helper_and_menu_bar_readiness(self):
        self.assertIn('"$HELPER_BIN" --health-probe', self.installer_helper)
        self.assertIn("--health-probe", self.helper_source)
        self.assertIn("modeVerified", self.helper_source)
        self.assertIn("dropHealthProbePrivilegesToConsoleUser", self.helper_source)
        self.assertIn("--installer-ready-token=", self.installer)
        self.assertIn("installer-ready-", self.installer)
        self.assertIn("--installer-ready-token=", self.app_main)
        self.assertIn("installer-ready-", self.app_main)
        self.assertIn("DispatchQueue.main.async", self.app_main)
        self.assertIn("applicationReadinessStabilityInterval", self.installer)
        self.assertIn("func start() -> Bool", self.status_item)

    def test_graphical_installer_verifies_the_launched_app(self):
        self.assertIn('codesign', self.installer)
        self.assertIn('com.leoarrow.wattson', self.installer)
        self.assertIn('Contents/MacOS/Wattson', self.installer)

    def test_preview_build_does_not_create_a_searchable_dist_app(self):
        self.assertNotIn('APP_BUNDLE="$DIST_DIR/$APP_NAME.app"', self.run_script)
        self.assertIn('LEGACY_APP_BUNDLE="$ROOT_DIR/dist/Wattson.app"', self.run_script)
        unregister = self.run_script.index('"$LSREGISTER" -u "$LEGACY_APP_BUNDLE"')
        delete = self.run_script.index('rm -rf "$LEGACY_APP_BUNDLE"')
        self.assertLess(unregister, delete)

    def test_preview_binary_matches_its_declared_macos_minimum(self):
        self.assertIn('SWIFT_TARGET="arm64-apple-macos12.0"', self.run_script)
        self.assertIn('-target "$SWIFT_TARGET"', self.run_script)


if __name__ == "__main__":
    unittest.main()
