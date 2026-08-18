import pathlib
import plistlib
import stat
import subprocess
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
SCRIPTS = {
    name: ROOT / "scripts" / name
    for name in (
        "build_release.sh",
        "package_pkg.sh",
        "package_dmg.sh",
        "verify_dmg.sh",
        "notarize.sh",
        "release.sh",
        "verify_release.sh",
    )
}
PREINSTALL = ROOT / "Packaging" / "pkg" / "preinstall"
POSTINSTALL = ROOT / "Packaging" / "pkg" / "postinstall"
RELEASE_GUIDE = ROOT / ".agent" / "release.md"
README = ROOT / "README.md"
HANDOFF = ROOT / "HANDOFF.md"
PROMOTE_WORKFLOW = ROOT / ".github" / "workflows" / "promote-release.yml"


class ReleasePackagingContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = {
            name: path.read_text(encoding="utf-8") for name, path in SCRIPTS.items()
        }
        cls.preinstall = PREINSTALL.read_text(encoding="utf-8")
        cls.postinstall = POSTINSTALL.read_text(encoding="utf-8")
        cls.release_guide = RELEASE_GUIDE.read_text(encoding="utf-8")
        cls.readme = README.read_text(encoding="utf-8")
        cls.handoff = HANDOFF.read_text(encoding="utf-8")
        cls.promote_workflow = PROMOTE_WORKFLOW.read_text(encoding="utf-8")

    def test_version_is_the_single_v3_source_and_plist_template_is_english(self):
        self.assertEqual((ROOT / "VERSION").read_text(encoding="utf-8"), "3.0.16\n")
        with (ROOT / "Packaging" / "AppInfo.plist").open("rb") as handle:
            info = plistlib.load(handle)
        self.assertEqual(info["CFBundleIdentifier"], "com.leoarrow.wattson")
        self.assertEqual(info["CFBundleName"], "Wattson")
        self.assertEqual(info["CFBundleDisplayName"], "Wattson")
        self.assertEqual(info["LSMinimumSystemVersion"], "12.0")
        self.assertFalse(list((ROOT / "Packaging").rglob("InfoPlist.strings")))

    def test_current_release_support_and_promotion_copy_are_not_stale(self):
        self.assertIn("support-diagnostics-v1.1.0", self.readme)
        self.assertNotIn("support-diagnostics-v1.0.0", self.readme)
        normalized_readme = " ".join(self.readme.split())
        normalized_promote_workflow = " ".join(self.promote_workflow.split())
        for current_release_topic in (
            "dedicated Menu Bar Icon page",
            "Wattson icon only",
            "Wattson with percentage",
            "macOS 26 icon only",
            "macOS 26 with percentage",
            "appearances vertically",
            "one full-width option per row",
            "seven real production-rendered states",
            "Battery, Full, Charging, Low, Low + AC, Saver, and Saver + AC",
            "real BatteryIcon renderer",
            "percentage rows show matching per-state values to the left of each glyph",
            "full-size macOS 26 Control Center battery parts from the running system",
            "23×12 outline and 11×14 bolt",
            "Every connected state uses the system bolt",
            "only the battery fill is yellow",
            "outline, cap, and bolt keep the menu-bar foreground colour",
            "General adds Check for Updates and Check for Updates on Launch",
            "Manual checks read GitHub Latest Release",
            "launch checks default on, stay quiet when current or offline",
            "never download or install automatically",
            "packaged Wattson app icon",
            "diagonal adapter plug",
            "green bracketed charging battery with a central lightning mark",
            "24-point Medium",
            "existing 36-point wells",
            "Adapter, System, and Battery power-flow node icons one shared optical scale",
            "System uses a simplified matching chip glyph",
            "semantic source and load colours remain unchanged",
            "720×520",
        ):
            self.assertIn(current_release_topic, normalized_promote_workflow)

        for user_facing_topic in (
            "v3.0.16 is the current public release",
            "dedicated Menu Bar Icon page",
            "Wattson icon only",
            "Wattson with percentage",
            "macOS 26 icon only",
            "macOS 26 with percentage",
            "appearances vertically",
            "one full-width option per row",
            "seven real production-rendered states",
            "Battery, Full, Charging, Low, Low + AC, Saver, and Saver + AC",
            "real BatteryIcon renderer",
            "percentage rows show matching per-state values to the left of each glyph",
            "full-size macOS 26 Control Center battery parts from the running system",
            "23×12 outline and 11×14 bolt",
            "Every connected state uses the system bolt",
            "only the battery fill is yellow",
            "outline, cap, and bolt keep the menu-bar foreground colour",
            "General adds Check for Updates and Check for Updates on Launch",
            "Manual checks read GitHub Latest Release",
            "launch checks default on, stay quiet when current or offline",
            "never download or install automatically",
            "packaged Wattson app icon",
            "clear diagonal plug",
            "green bracketed battery with a central lightning mark",
            "24-point Medium",
            "36-point wells",
            "Adapter, System, and Battery power-flow node icons now share one optical scale",
            "System uses a simplified matching chip glyph",
            "semantic source and load colours remain unchanged",
            "720×520",
        ):
            self.assertIn(user_facing_topic, normalized_readme)

        current_handoff = self.handoff.split(
            "## v3.0.16 unified power-flow node scale", 1
        )[1].split("## v3.0.15 restored power-flow node artwork", 1)[0]
        normalized_current_handoff = " ".join(current_handoff.split())
        historical_v3015 = self.handoff.split(
            "## v3.0.15 restored power-flow node artwork", 1
        )[1].split("## v3.0.14 update checks", 1)[0]
        normalized_historical_v3015 = " ".join(historical_v3015.split())
        for misleading_install_claim in (
            "Every installer now converges",
            "All installers converge",
            "Converges every install route",
            "Installers converge",
            "same-bundle-ID residue",
            "only after the canonical app passes validation",
            "rollback backup outside `/Applications`",
            "hidden `.app`",
        ):
            for release_surface in (
                normalized_readme,
                normalized_promote_workflow,
                normalized_current_handoff,
            ):
                self.assertNotIn(misleading_install_claim, release_surface)

        for current_handoff_topic in (
            "Adapter, System, and Battery power-flow node icons one shared optical scale",
            "System uses a simplified matching chip glyph",
            "semantic source and load colours remain unchanged",
        ):
            self.assertIn(current_handoff_topic, normalized_current_handoff)

        for historical_handoff_topic in (
            "clear diagonal plug",
            "green bracketed battery with a central lightning mark",
            "24-point Medium",
            "36-point wells",
            "Check for Updates",
            "four-by-seven Menu Bar Icon selector",
            "macOS 26 native battery artwork",
        ):
            self.assertIn(historical_handoff_topic, normalized_historical_v3015)

        self.assertIn("## v3.0.16 unified power-flow node scale", self.handoff)
        self.assertIn("## v3.0.15 restored power-flow node artwork", self.handoff)
        self.assertIn("## v3.0.14 update checks", self.handoff)
        self.assertIn("## v3.0.13 macOS 26 native icon correction", self.handoff)
        self.assertIn("## v3.0.12 complete runtime-state previews", self.handoff)
        self.assertIn("## v3.0.11 complete menu-bar appearance presets", self.handoff)
        self.assertIn("## v3.0.10 Settings and website work", self.handoff)
        self.assertIn("## v3.0.9 selector and rendering work", self.handoff)
        self.assertIn("## v3.0.8 dynamic Reduce Motion and transaction work", self.handoff)
        self.assertLess(
            self.handoff.index("## v3.0.16 unified power-flow node scale"),
            self.handoff.index("## v3.0.15 restored power-flow node artwork"),
        )
        self.assertLess(
            self.handoff.index("## v3.0.15 restored power-flow node artwork"),
            self.handoff.index("## v3.0.14 update checks"),
        )
        self.assertLess(
            self.handoff.index("## v3.0.14 update checks"),
            self.handoff.index("## v3.0.13 macOS 26 native icon correction"),
        )
        self.assertLess(
            self.handoff.index("## v3.0.13 macOS 26 native icon correction"),
            self.handoff.index("## v3.0.12 complete runtime-state previews"),
        )
        self.assertLess(
            self.handoff.index("## v3.0.12 complete runtime-state previews"),
            self.handoff.index("## v3.0.11 complete menu-bar appearance presets"),
        )
        self.assertLess(
            self.handoff.index("## v3.0.11 complete menu-bar appearance presets"),
            self.handoff.index("## v3.0.10 Settings and website work"),
        )
        self.assertLess(
            self.handoff.index("## v3.0.10 Settings and website work"),
            self.handoff.index("## v3.0.9 selector and rendering work"),
        )
        self.assertLess(
            self.handoff.index("## v3.0.9 selector and rendering work"),
            self.handoff.index("## v3.0.8 dynamic Reduce Motion and transaction work"),
        )

        for stale_copy in (
            "percentage control remains in General",
            "percentage stays in General",
            "all four complete appearances in one row",
            "all four complete menu-bar appearances in one row",
        ):
            self.assertNotIn(stale_copy, normalized_readme)
            self.assertNotIn(stale_copy, normalized_promote_workflow)
            self.assertNotIn(stale_copy, normalized_current_handoff)

    def test_release_scripts_are_executable_and_parse_as_bash(self):
        for path in (*SCRIPTS.values(), PREINSTALL, POSTINSTALL):
            with self.subTest(path=path):
                self.assertTrue(path.stat().st_mode & stat.S_IXUSR)
                result = subprocess.run(
                    ["/bin/bash", "-n", str(path)],
                    check=False,
                    text=True,
                    capture_output=True,
                )
                self.assertEqual(result.returncode, 0, result.stderr)

    def test_swiftpm_build_must_be_universal_and_target_macos_12(self):
        build = self.source["build_release.sh"]
        self.assertIn("/usr/bin/swift build", build)
        self.assertIn("--arch arm64", build)
        self.assertIn("--arch x86_64", build)
        self.assertIn('lipo "$binary_path" -verify_arch arm64 x86_64', build)
        self.assertIn('vtool -arch "$architecture" -show-build', build)
        self.assertIn('MIN_MACOS_VERSION="12.0"', build)
        self.assertNotIn("swiftc", build)
        self.assertNotIn("fall back", build.lower())

    def test_app_and_helper_use_one_explicit_signing_mode(self):
        build = self.source["build_release.sh"]
        self.assertIn("WATTSON_DEVELOPER_ID_APP", build)
        self.assertIn("--options runtime", build)
        self.assertIn('SIGNING_MODE="ad-hoc"', build)
        self.assertIn('--identifier "$HELPER_LABEL"', build)
        helper_signing = build.index('--identifier "$HELPER_LABEL"')
        app_signing = build.index('--entitlements "$ROOT_DIR/BatteryPowerApp.entitlements"')
        self.assertLess(helper_signing, app_signing)

    def test_pkg_owns_the_canonical_app_and_full_helper_payload(self):
        package = self.source["package_pkg.sh"]
        for path in (
            "$PKG_ROOT/Applications/Wattson.app",
            "$PKG_ROOT/Library/PrivilegedHelperTools/$HELPER_LABEL",
            "$PKG_ROOT/Library/LaunchDaemons/$HELPER_LABEL.plist",
        ):
            self.assertIn(path, package)
        self.assertIn("--ownership recommended", package)
        self.assertIn("--install-location /", package)
        self.assertIn('--component-plist "$COMPONENT_PLIST"', package)
        self.assertIn("WATTSON_DEVELOPER_ID_INSTALLER", package)
        self.assertNotIn('$HOME/Applications/Wattson.app', package)

        with (ROOT / "Packaging" / "pkg" / "component.plist").open("rb") as handle:
            components = plistlib.load(handle)
        self.assertEqual(components[0]["RootRelativeBundlePath"], "Applications/Wattson.app")
        self.assertFalse(components[0]["BundleIsRelocatable"])

    def test_pkg_scripts_replace_and_restart_the_existing_helper(self):
        self.assertIn('launchctl bootout "$HELPER_TARGET"', self.preinstall)
        self.assertIn('/bin/rm -f -- "$HELPER_SOCKET"', self.preinstall)
        self.assertIn('APP_DIR="/Applications/Wattson.app"', self.postinstall)
        self.assertIn('/bin/launchctl enable "$HELPER_TARGET"', self.postinstall)
        self.assertIn('/bin/launchctl bootstrap system "$HELPER_PLIST"', self.postinstall)
        self.assertIn('"$HELPER_BIN" --health-probe', self.postinstall)
        self.assertIn('"$HELPER_BIN" --migrate-legacy-login-item', self.postinstall)
        self.assertLess(
            self.postinstall.index('"$HELPER_BIN" --migrate-legacy-login-item'),
            self.postinstall.index("remove_v2_user_app\n"),
        )
        self.assertNotIn("NSStatusItem", self.postinstall)
        self.assertNotIn("--installer-ready-token", self.postinstall)
        self.assertNotIn("/usr/bin/open", self.postinstall)

    def test_v2_user_app_cleanup_is_identity_pinned_and_unprivileged(self):
        self.assertIn('legacy_app="$home_dir/Applications/Wattson.app"', self.postinstall)
        self.assertIn('[[ "$legacy_id" == "$APP_BUNDLE_ID" ]]', self.postinstall)
        identity_check = self.postinstall.index('[[ "$legacy_id" == "$APP_BUNDLE_ID" ]]')
        stop_process = self.postinstall.index('/usr/bin/pkill', identity_check)
        delete_app = self.postinstall.index('/bin/rm -rf -- "$legacy_app"', stop_process)
        self.assertLess(identity_check, stop_process)
        self.assertLess(stop_process, delete_app)
        self.assertIn('-u "$console_uid"', self.postinstall[stop_process:delete_app])
        self.assertIn('legacy_process_pattern', self.postinstall[stop_process:delete_app])
        self.assertIn('/usr/bin/sudo -n -u "#$console_uid"', self.postinstall)
        self.assertNotIn('rm -rf -- "$home_dir"', self.postinstall)

    def test_dmg_contains_the_exact_pkg_and_no_second_install_surface(self):
        package = self.source["package_dmg.sh"]
        verify = self.source["verify_dmg.sh"]
        self.assertIn('/bin/cp "$PKG_PATH" "$STAGING_DIR/$PKG_NAME"', package)
        self.assertIn('/usr/bin/cmp -s "$PKG_PATH" "$STAGING_DIR/$PKG_NAME"', package)
        self.assertIn('/usr/bin/cmp -s "$EXPECTED_PKG" "$EMBEDDED_PKG"', verify)
        self.assertIn("DMG must expose exactly one installer PKG", verify)
        self.assertNotIn("Wattson.app", package)
        self.assertNotIn("Install Wattson.app", package)

    def test_notarization_is_opt_in_and_claimed_only_after_acceptance(self):
        release = self.source["release.sh"]
        notarize = self.source["notarize.sh"]
        self.assertIn('NOTARIZE_RELEASE="${WATTSON_NOTARIZE:-0}"', release)
        self.assertIn('|| -z "${WATTSON_NOTARY_ISSUER:-}"', release)
        self.assertIn('|| -n "${WATTSON_NOTARY_ISSUER:-}"', notarize)
        self.assertIn('|| -z "${WATTSON_NOTARY_ISSUER:-}"', notarize)
        self.assertIn('--issuer "$WATTSON_NOTARY_ISSUER"', notarize)
        self.assertIn('-extract status raw "$SUBMISSION_RESULT"', notarize)
        self.assertIn('-extract id raw "$SUBMISSION_RESULT"', notarize)
        self.assertIn("notarytool log", notarize)
        self.assertIn('-type issues "$NOTARY_LOG"', notarize)
        self.assertIn('-extract issues raw "$NOTARY_LOG"', notarize)
        self.assertIn('NOTARY_ISSUE_COUNT" != "0"', notarize)
        self.assertIn('NOTARY_STATUS" != "Accepted"', notarize)
        self.assertLess(
            notarize.index("notarytool log"),
            notarize.index('NOTARY_STATUS" != "Accepted"'),
        )
        self.assertLess(
            notarize.index('NOTARY_STATUS" != "Accepted"'),
            notarize.index("stapler staple"),
        )
        self.assertLess(
            notarize.index('NOTARY_ISSUE_COUNT" != "0"'),
            notarize.index("stapler staple"),
        )
        self.assertIn('/usr/bin/mktemp -d', notarize)
        self.assertIn("trap cleanup EXIT", notarize)
        self.assertIn('/bin/rm -f -- "$NOTARY_LOG"', notarize)
        self.assertIn('/bin/rm -f -- "$SUBMISSION_RESULT"', notarize)
        self.assertIn('/bin/rmdir "$TEMP_DIR"', notarize)
        self.assertLess(
            release.index('notarize.sh" "$DMG_PATH"'),
            release.index('NOTARIZED="yes"'),
        )
        self.assertIn('NOTARIZED="no"', release)
        self.assertIn("configure both Developer ID Application and Installer", release)

    def test_release_checksums_are_written_after_final_artifacts(self):
        release = self.source["release.sh"]
        checksum_write = release.index('> "$CHECKSUM_PATH"')
        self.assertLess(release.index('notarize.sh" "$DMG_PATH"'), checksum_write)
        self.assertLess(release.index('verify_release.sh" "$PKG_PATH" "$DMG_PATH"'), checksum_write)
        self.assertIn('/usr/bin/shasum -a 256 "$PKG_NAME"', release)
        self.assertIn('/usr/bin/shasum -a 256 "$DMG_NAME"', release)
        self.assertIn('/usr/bin/shasum -a 256 -c', release)

    def test_stable_release_requires_installing_verified_public_pkg_locally(self):
        guide = self.release_guide
        self.assertIn("A stable release is not complete", guide)
        self.assertIn("Do not use\n`scripts/install.sh`", guide)
        self.assertIn("/usr/bin/shasum -a 256 -c", guide)
        self.assertIn('sudo /usr/sbin/installer -pkg "$verified_pkg" -target /', guide)
        self.assertIn("Print :CFBundleShortVersionString", guide)
        self.assertIn("Print :CFBundleVersion", guide)
        self.assertIn("pkgutil --pkg-info com.leoarrow.wattson.pkg", guide)
        self.assertIn("/usr/bin/codesign --verify --deep --strict", guide)
        self.assertIn("/usr/bin/open -n /Applications/Wattson.app", guide)


if __name__ == "__main__":
    unittest.main()
