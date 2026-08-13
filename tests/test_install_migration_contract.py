import os
import pathlib
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
INSTALL = ROOT / "scripts" / "install.sh"
UNINSTALL = ROOT / "scripts" / "uninstall.sh"
PACKAGE = ROOT / "scripts" / "package_dmg.sh"
PACKAGE_PKG = ROOT / "scripts" / "package_pkg.sh"
BUILD_RELEASE = ROOT / "scripts" / "build_release.sh"
PKG_POSTINSTALL = ROOT / "Packaging" / "pkg" / "postinstall"
INSTALLER = ROOT / "Installer" / "main.swift"
INSTALLER_HELPER = ROOT / "Installer" / "install-helper.sh"
APP_MAIN = ROOT / "main.swift"
STATUS_ITEM = ROOT / "MenuBar" / "StatusItemController.swift"
HELPER_SOURCE = ROOT / "Helper" / "wattson-helper.swift"
RUN_SCRIPT = ROOT / "script" / "build_and_run.sh"
VERIFY_INTERACTION = ROOT / "scripts" / "verify_interaction.sh"
APP_ENTITLEMENTS = ROOT / "BatteryPowerApp.entitlements"
CI_HELPER_INSTALL = ROOT / "scripts" / "ci_test_helper_install.sh"
CI_HELPER_WORKFLOW = ROOT / ".github" / "workflows" / "macos-helper-install.yml"


class InstallMigrationContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.install = INSTALL.read_text(encoding="utf-8")
        cls.uninstall = UNINSTALL.read_text(encoding="utf-8")
        cls.package = PACKAGE.read_text(encoding="utf-8")
        cls.package_pkg = PACKAGE_PKG.read_text(encoding="utf-8")
        cls.build_release = BUILD_RELEASE.read_text(encoding="utf-8")
        cls.pkg_postinstall = PKG_POSTINSTALL.read_text(encoding="utf-8")
        cls.installer = INSTALLER.read_text(encoding="utf-8")
        cls.installer_helper = INSTALLER_HELPER.read_text(encoding="utf-8")
        cls.app_main = APP_MAIN.read_text(encoding="utf-8")
        cls.status_item = STATUS_ITEM.read_text(encoding="utf-8")
        cls.helper_source = HELPER_SOURCE.read_text(encoding="utf-8")
        cls.run_script = RUN_SCRIPT.read_text(encoding="utf-8")
        cls.verify_interaction = VERIFY_INTERACTION.read_text(encoding="utf-8")
        cls.entitlements = APP_ENTITLEMENTS.read_text(encoding="utf-8")
        cls.ci_helper_install = CI_HELPER_INSTALL.read_text(encoding="utf-8")
        cls.ci_helper_workflow = CI_HELPER_WORKFLOW.read_text(encoding="utf-8")

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
        self.assertIn('HELPER_TARGET="system/$HELPER_LABEL"', self.uninstall)
        self.assertIn('launchctl bootout "$HELPER_TARGET"', self.uninstall)
        self.assertIn('/Library/PrivilegedHelperTools/${HELPER_LABEL}', self.uninstall)

    def test_uninstall_removes_v3_app_and_package_receipt(self):
        self.assertIn('APP_DIR="/Applications/Wattson.app"', self.uninstall)
        self.assertIn('PACKAGE_RECEIPT="com.leoarrow.wattson.pkg"', self.uninstall)
        self.assertIn('pkgutil --forget "$PACKAGE_RECEIPT"', self.uninstall)

    def test_release_package_uses_the_wattson_identity(self):
        self.assertIn('APP_NAME="Wattson"', self.package)
        self.assertEqual((ROOT / "VERSION").read_text(encoding="utf-8").strip(), "3.0.8")
        self.assertIn('VERSION_FILE="$ROOT_DIR/VERSION"', self.package)
        self.assertIn('Contents/MacOS/Wattson', self.package_pkg)

    def test_release_binary_matches_the_declared_macos_minimum(self):
        self.assertIn('VERSION_FILE="$ROOT_DIR/VERSION"', self.build_release)
        self.assertIn('MIN_MACOS_VERSION="12.0"', self.build_release)
        self.assertIn('--arch arm64', self.build_release)
        self.assertIn('--arch x86_64', self.build_release)

    def test_release_dmg_wraps_the_exact_native_pkg(self):
        self.assertIn('/bin/cp "$PKG_PATH" "$STAGING_DIR/$PKG_NAME"', self.package)
        self.assertIn('/usr/bin/cmp -s "$PKG_PATH" "$STAGING_DIR/$PKG_NAME"', self.package)
        self.assertIn("getconf DARWIN_USER_TEMP_DIR", self.package)
        self.assertIn('macos-universal.pkg', self.package)
        self.assertNotIn('install.sh" --app-only', self.package)
        self.assertNotIn('Installer/main.swift', self.package)
        self.assertNotIn('Wattson.zip', self.package)
        self.assertNotIn('Install Wattson.command', self.package)
        self.assertNotIn('Quick Start.txt', self.package)
        self.assertNotIn('ln -s /Applications', self.package)

    def test_packaging_destination_rejects_a_spoofed_tmpdir(self):
        # Keep the spoof outside DARWIN_USER_TEMP_DIR even when a release gate
        # runs this repository from an isolated snapshot under that directory.
        with tempfile.TemporaryDirectory(dir=pathlib.Path.home()) as directory:
            fake_temp = pathlib.Path(directory)
            target = fake_temp / "Wattson.app"
            target.mkdir()
            sentinel = target / "must-not-be-deleted"
            sentinel.write_text("sentinel", encoding="utf-8")
            environment = os.environ.copy()
            environment["TMPDIR"] = str(fake_temp)
            environment["WATTSON_PACKAGE_APP_DIR"] = str(target)

            result = subprocess.run(
                ["/bin/bash", str(INSTALL), "--app-only"],
                check=False,
                env=environment,
                text=True,
                capture_output=True,
            )

            self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
            self.assertIn("inside the temp root", result.stderr)
            self.assertEqual(sentinel.read_text(encoding="utf-8"), "sentinel")

    def test_release_dmg_is_world_traversable_and_not_spotlight_indexed(self):
        self.assertIn('chmod 755 "$STAGING_DIR"', self.package)
        self.assertIn('.metadata_never_index', self.package)
        self.assertIn('chmod -R a+rX "$STAGING_DIR"', self.package)
        self.assertIn('verify_dmg.sh', self.package)

    def test_native_pkg_preserves_the_privileged_features(self):
        self.assertIn('HELPER_LABEL="com.leoarrow.wattson.helper"', self.package_pkg)
        self.assertIn('Library/PrivilegedHelperTools', self.package_pkg)
        self.assertIn('Library/LaunchDaemons', self.package_pkg)
        self.assertIn('--scripts "$PACKAGE_SCRIPTS"', self.package_pkg)
        self.assertIn('/bin/launchctl bootstrap system "$HELPER_PLIST"', self.pkg_postinstall)

    def test_public_pkg_retires_only_the_exact_legacy_battery_power_bundle(self):
        cleanup = self.pkg_postinstall.split(
            "remove_legacy_battery_power_app() {", 1
        )[1].split("[[ \"$(/usr/bin/id -u)\"", 1)[0]
        self.assertIn('Applications/电池功率.app', cleanup)
        self.assertIn('legacy_id" == "com.leoarrow.battery-monitor"', cleanup)
        self.assertIn('com.leoarrow.battery-monitor.agent.plist', cleanup)
        self.assertIn('ProgramArguments:0', cleanup)
        self.assertIn('/bin/launchctl bootout "gui/$console_uid"', cleanup)
        self.assertIn('/usr/bin/sudo -n -u "#$console_uid" -- /bin/rm -rf', cleanup)
        self.assertNotIn('.battery_monitor.py', cleanup)
        self.assertNotIn('.battery_monitor.cfg', cleanup)

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
        stop_old_service = self.installer_helper.index('stop_loaded_helper', replacement)
        self.assertLess(candidate_validation, stop_old_service)

    def test_helper_replacement_clears_disabled_and_stale_launchd_state(self):
        self.assertIn('HELPER_TARGET="system/$HELPER_LABEL"', self.installer_helper)
        self.assertIn("old_service_disabled=0", self.installer_helper)
        self.assertIn("print-disabled system", self.installer_helper)
        self.assertNotIn(
            "print-disabled system 2>/dev/null || true", self.installer_helper
        )

        replacement = self.installer_helper.index("replacement_started=1")
        stop_old_service = self.installer_helper.index(
            'stop_loaded_helper', replacement
        )
        bootstrap_function = self.installer_helper.index("bootstrap_helper() {")
        enable_service = self.installer_helper.index(
            '/bin/launchctl enable "$HELPER_TARGET"', bootstrap_function
        )
        bootstrap_service = self.installer_helper.index(
            '/bin/launchctl bootstrap system "$HELPER_PLIST"', bootstrap_function
        )
        bootstrap_call = self.installer_helper.index("if bootstrap_helper; then", replacement)
        self.assertLess(enable_service, bootstrap_service)
        self.assertLess(stop_old_service, bootstrap_call)

        rollback = self.installer_helper.split("rollback_helper_install() {", 1)[1]
        rollback = rollback.split("abort_helper_install() {", 1)[0]
        rollback_enable = rollback.index('/bin/launchctl enable "$HELPER_TARGET"')
        rollback_bootstrap = rollback.index(
            '/bin/launchctl bootstrap system "$HELPER_PLIST"'
        )
        rollback_disable = rollback.index('/bin/launchctl disable "$HELPER_TARGET"')
        self.assertLess(rollback_enable, rollback_bootstrap)
        self.assertLess(rollback_bootstrap, rollback_disable)

        self.assertIn('HELPER_TARGET="system/$HELPER_LABEL"', self.install)
        self.assertNotIn("print-disabled system 2>/dev/null || true", self.install)
        self.assertIn('sudo launchctl bootout "$HELPER_TARGET"', self.install)
        self.assertIn('sudo launchctl enable "$HELPER_TARGET"', self.install)
        self.assertIn(
            'if ! sudo launchctl bootstrap system "$HELPER_PLIST"', self.install
        )
        self.assertIn('sudo launchctl disable "$HELPER_TARGET"', self.install)

    def test_graphical_helper_handles_external_distribution_state(self):
        helper_plist = (ROOT / "Helper" / "com.leoarrow.wattson.helper.plist").read_text(
            encoding="utf-8"
        )
        self.assertIn("AssociatedBundleIdentifiers", helper_plist)
        self.assertIn("com.leoarrow.wattson", helper_plist)
        self.assertIn("clear_quarantine", self.installer_helper)
        self.assertIn("com.apple.quarantine", self.installer_helper)
        self.assertIn("bootstrap_helper", self.installer_helper)
        self.assertIn("for attempt in 1 2", self.installer_helper)
        self.assertIn('/bin/launchctl enable "$HELPER_TARGET"', self.installer_helper)
        self.assertIn('--identifier "$HELPER_LABEL"', self.build_release)
        self.assertIn("Candidate helper signature before rollback", self.installer_helper)
        self.assertIn("Candidate helper xattr names before rollback", self.installer_helper)

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
        self.assertIn('--ownership recommended', self.package_pkg)
        self.assertIn('--install-location /', self.package_pkg)
        self.assertIn('/usr/bin/codesign --verify --strict "$HELPER_BIN"', self.pkg_postinstall)

    def test_graphical_install_requires_its_read_only_signed_dmg(self):
        self.assertIn("MNT_RDONLY", self.installer)
        self.assertIn('codesign", ["--verify", "--deep", "--strict"', self.installer)
        self.assertIn("Open Install Wattson.app directly from the read-only DMG", self.installer)

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
        self.assertIn('case "health"', self.helper_source)
        self.assertIn('strictJSONBool(response["health"]) == true', self.helper_source)
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

    def test_install_failure_offers_one_click_read_only_diagnostics(self):
        diagnostics = self.installer.split(
            "private enum InstallationDiagnostics {", 1
        )[1].split("private struct PreparedPayload", 1)[0]
        self.assertIn('alert.addButton(withTitle: "Copy Diagnostics")', self.installer)
        self.assertIn("NSPasteboard.general", self.installer)
        self.assertIn("copyInstallationDiagnostics", self.installer)
        self.assertIn("readOnlyCommandArguments", diagnostics)
        self.assertIn("contains(arguments) == true", diagnostics)
        self.assertIn("matchingWattsonLines", diagnostics)
        self.assertIn('"/usr/bin/sw_vers"', diagnostics)
        self.assertIn('"/bin/launchctl"', diagnostics)
        self.assertIn('"/usr/bin/sfltool"', diagnostics)
        self.assertIn('"/usr/bin/log"', diagnostics)
        self.assertIn('"show", "--last", "15m"', diagnostics)
        self.assertIn('["dumpbtm"]', diagnostics)
        self.assertIn('["--verify", "--strict", helperInstallPath]', diagnostics)
        self.assertIn("acceptedExitCodes: [0, 1]", diagnostics)
        self.assertIn("50_000", diagnostics)
        self.assertNotIn("sudo", diagnostics)
        self.assertNotIn('["resetbtm"]', diagnostics)
        self.assertNotIn('["-d"', diagnostics)
        self.assertNotIn('["--global-disable"', diagnostics)
        self.assertNotIn('["erase"', diagnostics)
        self.assertNotIn('["bootstrap"', diagnostics)
        self.assertNotIn('["bootout"', diagnostics)
        self.assertNotIn('["enable"', diagnostics)
        self.assertNotIn('["disable"', diagnostics)
        self.assertNotIn('CONTAINS[c] \\"com.leoarrow\\"', diagnostics)
        self.assertNotIn('normalized.contains("com.leoarrow")', diagnostics)

    def test_remote_v3_install_is_explicit_and_ephemeral(self):
        self.assertIn("workflow_dispatch:", self.ci_helper_workflow)
        self.assertNotIn("pull_request:", self.ci_helper_workflow)
        self.assertIn("\n  push:\n    branches:\n      - release-candidate", self.ci_helper_workflow)
        self.assertNotIn("branches-ignore:", self.ci_helper_workflow)
        self.assertIn("runs-on: macos-26", self.ci_helper_workflow)
        for runner in ("macos-14", "macos-15", "macos-26", "macos-15-intel", "macos-26-intel"):
            self.assertIn(f"runner: {runner}", self.ci_helper_workflow)
        self.assertIn("persist-credentials: false", self.ci_helper_workflow)
        self.assertNotIn("uses: actions/checkout@v4", self.ci_helper_workflow)
        self.assertNotIn("uses: actions/upload-artifact@v4", self.ci_helper_workflow)
        self.assertNotIn("uses: actions/download-artifact@v4", self.ci_helper_workflow)
        self.assertIn("retention-days: 7", self.ci_helper_workflow)
        self.assertIn("Wattson-release-candidate-v", self.ci_helper_workflow)
        self.assertNotIn("UNNOTARIZED-CI-ONLY", self.ci_helper_workflow)
        self.assertIn("scripts/release.sh", self.ci_helper_workflow)
        self.assertIn("unittest discover", self.ci_helper_workflow)
        self.assertIn("shasum -a 256 -c SHA256SUMS.txt", self.ci_helper_workflow)
        self.assertIn('/usr/sbin/installer \\', self.ci_helper_workflow)
        self.assertIn('-pkg "$PKG_PATH"', self.ci_helper_workflow)
        self.assertIn('-target /', self.ci_helper_workflow)
        self.assertIn('V2_VERSION="2.1.5"', self.ci_helper_workflow)
        self.assertIn("test_v2_upgrade: true", self.ci_helper_workflow)
        self.assertIn("ProgramArguments:2 string $LEGACY_APP", self.ci_helper_workflow)
        self.assertIn("ProgramArguments:2' \"$LOGIN_PLIST\"", self.ci_helper_workflow)
        self.assertIn("verify_app_launch_stability", self.ci_helper_workflow)
        self.assertIn('--helper-health-probe', self.ci_helper_workflow)
        self.assertIn('--helper-power-probe', self.ci_helper_workflow)
        self.assertIn("/usr/sbin/ioreg -r -c AppleSmartBattery", self.ci_helper_workflow)
        self.assertIn('[[ "$battery_registry" == *AppleSmartBattery* ]]', self.ci_helper_workflow)
        self.assertNotIn("| /usr/bin/grep -q AppleSmartBattery", self.ci_helper_workflow)
        self.assertIn('[[ "$has_battery" == "0" && "$exit_status" == "0" ]]', self.ci_helper_workflow)
        self.assertIn("hosted runner has no AppleSmartBattery", self.ci_helper_workflow)
        self.assertIn("/bin/bash scripts/uninstall.sh", self.ci_helper_workflow)
        self.assertNotIn("ci_test_helper_install.sh", self.ci_helper_workflow)

    def test_signed_candidate_matrix_verifies_exact_uploaded_bytes(self):
        workflow = self.ci_helper_workflow
        self.assertEqual(workflow.count("scripts/release.sh"), 1)
        self.assertIn(
            "WATTSON_DISTRIBUTION_MODE: ${{ needs.build.outputs.distribution_mode }}",
            workflow,
        )
        self.assertIn(
            "EXPECTED_TEAM_ID: ${{ needs.build.outputs.signing_team_id }}",
            workflow,
        )
        for metadata in (
            "distribution_mode=developer-id",
            "app_signature=developer-id",
            "helper_signature=developer-id",
            "package_signature=developer-id",
            "dmg_signature=developer-id",
            "notarized=yes",
            "stapled=yes",
        ):
            self.assertIn(metadata, workflow)
        self.assertIn('pkgutil --check-signature "$PKG_PATH"', workflow)
        self.assertIn(
            'codesign --verify --deep --strict --verbose=2 "$PACKAGED_APP_DIR"',
            workflow,
        )
        self.assertIn(
            'codesign --verify --strict --verbose=2 "$PACKAGED_HELPER"',
            workflow,
        )
        self.assertIn('codesign --verify --strict --verbose=2 "$DMG_PATH"', workflow)
        self.assertIn('TeamIdentifier=$EXPECTED_TEAM_ID', workflow)
        self.assertIn("Signed with a trusted timestamp", workflow)
        self.assertIn("'^Timestamp=.+'", workflow)
        self.assertIn('xcrun stapler validate -v "$PKG_PATH"', workflow)
        self.assertIn('xcrun stapler validate -v "$DMG_PATH"', workflow)
        self.assertIn('spctl --assess --type execute', workflow)
        self.assertIn('spctl --assess --type install', workflow)
        self.assertIn('--context context:primary-signature', workflow)
        self.assertIn('/usr/bin/cmp -s "$PKG_PATH" "$MOUNT_DIR/$PKG_NAME"', workflow)

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
