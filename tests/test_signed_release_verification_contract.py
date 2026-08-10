import pathlib
import subprocess
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
VERIFY_RELEASE = ROOT / "scripts" / "verify_release.sh"


class SignedReleaseVerificationContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = VERIFY_RELEASE.read_text(encoding="utf-8")

    def function_body(self, name):
        start = self.source.index(f"{name}() {{")
        end = self.source.index("\n}\n", start) + 3
        return self.source[start:end]

    def test_verifier_parses_as_macos_compatible_bash(self):
        result = subprocess.run(
            ["/bin/bash", "-n", str(VERIFY_RELEASE)],
            check=False,
            text=True,
            capture_output=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        for bash_four_only_feature in ("mapfile", "readarray", "declare -A"):
            self.assertNotIn(bash_four_only_feature, self.source)

    def test_community_mode_remains_the_default(self):
        self.assertIn(
            'EXPECT_INSTALLER_SIGNED="${WATTSON_EXPECT_INSTALLER_SIGNED:-0}"',
            self.source,
        )
        self.assertIn(
            'EXPECT_DMG_SIGNED="${WATTSON_EXPECT_DMG_SIGNED:-0}"', self.source
        )
        self.assertIn(
            'EXPECT_NOTARIZED="${WATTSON_EXPECT_NOTARIZED:-0}"', self.source
        )
        self.assertIn('SIGNED_RELEASE_REQUIRED=0', self.source)
        self.assertIn(
            '[[ "$EXPECT_INSTALLER_SIGNED" == "1" || "$EXPECT_DMG_SIGNED" == "1" ]]',
            self.source,
        )

    def test_final_pkg_payload_is_expanded_and_independently_verified(self):
        expand = self.source.index('pkgutil --expand-full "$PKG_PATH" "$EXPAND_DIR"')
        packaged_app = self.source.index('PACKAGED_APP_DIR="$(')
        packaged_helper = self.source.index('PACKAGED_HELPER_EXECUTABLE="$(')
        self.assertLess(expand, packaged_app)
        self.assertLess(expand, packaged_helper)
        self.assertIn("*/Payload/Applications/Wattson.app", self.source)
        self.assertIn(
            "*/Payload/Library/PrivilegedHelperTools/$HELPER_LABEL", self.source
        )
        packaged_checks = self.source[packaged_helper:]
        self.assertIn('verify_app_bundle "$PACKAGED_APP_DIR"', packaged_checks)
        self.assertIn('verify_binary "$PACKAGED_APP_EXECUTABLE"', packaged_checks)
        self.assertIn('verify_binary "$PACKAGED_HELPER_EXECUTABLE"', packaged_checks)
        self.assertIn(
            'codesign --verify --deep --strict "$PACKAGED_APP_DIR"',
            packaged_checks,
        )
        self.assertIn(
            'codesign --verify --strict "$PACKAGED_HELPER_EXECUTABLE"',
            packaged_checks,
        )

    def test_developer_id_leaf_runtime_timestamp_and_team_are_strict(self):
        body = self.function_body("verify_developer_id_application_signature")
        self.assertIn("Authority=Developer ID Application: ", body)
        self.assertNotIn('authority_count" == "3"', body)
        self.assertNotIn("Developer ID Certification Authority", body)
        self.assertIn('verify_expected_team_id "$signing_details"', body)
        self.assertIn('^Timestamp=', body)
        self.assertIn("runtime[^)]*", body)

        team_body = self.function_body("verify_expected_team_id")
        self.assertIn("TeamIdentifier=", team_body)
        self.assertIn("EXPECTED_TEAM_ID", team_body)
        self.assertIn("SIGNED_RELEASE_TEAM_ID", team_body)
        self.assertIn('EXPECTED_TEAM_ID="${WATTSON_EXPECT_TEAM_ID:-}"', self.source)

    def test_packaged_entitlements_are_production_entitlements(self):
        body = self.function_body("verify_production_entitlements")
        self.assertIn('codesign --display --entitlements :- "$app_dir"', body)
        self.assertIn('codesign --display --entitlements :- "$helper_path"', body)
        self.assertIn("com.apple.security.get-task-allow", body)
        self.assertIn('"$APP_ENTITLEMENTS"', body)
        self.assertEqual(body.count("plutil -convert json"), 2)
        self.assertIn("/usr/bin/cmp -s", body)
        self.assertIn("BatteryPowerApp.entitlements", body)

    def test_pkg_uses_exact_installer_leaf_and_trusted_timestamp(self):
        body = self.function_body("verify_installer_signature")
        self.assertIn('pkgutil --check-signature "$pkg_path"', body)
        self.assertIn("Signed with a trusted timestamp on:", body)
        self.assertIn("Developer ID Installer: ", body)
        self.assertIn('" ($SIGNED_RELEASE_TEAM_ID)"', body)
        self.assertNotIn('certificate_count" == "3"', body)

    def test_gatekeeper_uses_the_artifact_specific_assessment_types(self):
        signed_block = self.source[
            self.source.index('if [[ "$SIGNED_RELEASE_REQUIRED" == "1" ]]') :
        ]
        self.assertIn(
            'verify_gatekeeper "$PACKAGED_APP_DIR" execute "packaged app"',
            signed_block,
        )
        self.assertIn('verify_gatekeeper "$PKG_PATH" install "PKG"', signed_block)
        self.assertIn(
            'verify_developer_id_application_signature "$DMG_PATH" "DMG" 0',
            signed_block,
        )
        dmg_body = self.function_body("verify_dmg_gatekeeper")
        self.assertIn("--type open", dmg_body)
        self.assertIn("--context context:primary-signature", dmg_body)

    def test_notarized_expectation_requires_both_staples_to_validate(self):
        notarized_block = self.source[
            self.source.index('if [[ "$EXPECT_NOTARIZED" == "1" ]]') :
        ]
        self.assertIn('xcrun stapler validate -v "$PKG_PATH"', notarized_block)
        self.assertIn('xcrun stapler validate -v "$DMG_PATH"', notarized_block)

    def test_verification_never_installs_or_changes_gatekeeper_policy(self):
        self.assertNotIn("/usr/sbin/installer", self.source)
        self.assertNotIn("spctl --add", self.source)
        self.assertNotIn("spctl --enable", self.source)
        self.assertNotIn("syspolicy_check", self.source)
        self.assertNotIn("codesign --sign", self.source)


if __name__ == "__main__":
    unittest.main()
