import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
PROMOTE = (ROOT / ".github/workflows/promote-release.yml").read_text(encoding="utf-8")
PAGES = (ROOT / ".github/workflows/pages.yml").read_text(encoding="utf-8")
HOMEBREW = (ROOT / ".github/workflows/homebrew-tap.yml").read_text(encoding="utf-8")
HOMEBREW_INSTALL = (
    ROOT / ".github/workflows/homebrew-install-test.yml"
).read_text(encoding="utf-8")
CI = (ROOT / ".github/workflows/ci.yml").read_text(encoding="utf-8")
CANDIDATE = (ROOT / ".github/workflows/macos-helper-install.yml").read_text(encoding="utf-8")


class ReleaseWorkflowContractTests(unittest.TestCase):
    def test_macos_workflows_use_the_tk_capable_system_python(self):
        command = "/usr/bin/python3 -m unittest discover -s tests -v"
        self.assertIn(command, CI)
        self.assertIn(command, CANDIDATE)
        self.assertNotIn(" WATTSON_RUN_INTERACTION python3 ", CI)
        self.assertNotIn(" WATTSON_RUN_INTERACTION python3 ", CANDIDATE)

    def test_release_candidate_replays_real_appkit_off_the_user_mac(self):
        self.assertIn("scripts/verify_interaction.sh", CANDIDATE)
        self.assertIn("WATTSON_FORCE_REDUCE_MOTION=0", CANDIDATE)
        self.assertIn("WATTSON_FORCE_LEGACY_KNOB=1", CANDIDATE)
        self.assertGreaterEqual(CANDIDATE.count("WATTSON_FORCE_LEGACY_KNOB=1"), 2)
        self.assertGreaterEqual(CANDIDATE.count("WATTSON_FORCE_REDUCE_MOTION=0"), 3)
        self.assertGreaterEqual(CANDIDATE.count("WATTSON_FORCE_REDUCE_TRANSPARENCY=0"), 3)
        self.assertIn("WATTSON_FORCE_REDUCE_MOTION=1", CANDIDATE)
        self.assertIn("WATTSON_FORCE_REDUCE_TRANSPARENCY=1", CANDIDATE)
        self.assertIn("scripts/verify_animation_stress.sh", CANDIDATE)

    def test_installed_matrix_gates_v5_and_rejects_legacy_as_v5(self):
        self.assertGreaterEqual(CANDIDATE.count("--helper-v5-observation-probe"), 3)
        upgrade = CANDIDATE.split(
            "- name: Test upgrade from the published v2.1.5 release", 1
        )[1].split("- name: Upload installation logs", 1)[0]
        legacy_gate = upgrade.index("legacy_v5_probe_status")
        install = upgrade.index("Upgrading the exact v2.1.5 app")
        upgraded_v5 = upgrade.rindex('"$APP_BIN" --helper-v5-observation-probe')
        self.assertLess(legacy_gate, install)
        self.assertLess(install, upgraded_v5)
        self.assertIn('[[ "$legacy_v5_probe_status" != "0" ]]', upgrade)

    def test_normal_swift_and_appkit_gates_override_runner_accessibility_defaults(self):
        for workflow in (CI, CANDIDATE):
            self.assertIn("WATTSON_FORCE_REDUCE_MOTION=0", workflow)
            self.assertIn("WATTSON_FORCE_REDUCE_TRANSPARENCY=0", workflow)

    def test_promotion_requires_the_successful_main_candidate_run(self):
        self.assertIn("candidate_run_id:", PROMOTE)
        self.assertIn('actions/runs/$CANDIDATE_RUN_ID', PROMOTE)
        self.assertIn('== ".github/workflows/macos-helper-install.yml"', PROMOTE)
        self.assertIn('== "success"', PROMOTE)
        self.assertIn("workflow_dispatch:main", PROMOTE)
        self.assertNotIn("push:release-candidate", PROMOTE)
        self.assertIn(
            "github.event.workflow_run.event == 'workflow_dispatch'", PROMOTE
        )
        self.assertIn("github.event.workflow_run.head_branch == 'main'", PROMOTE)
        self.assertIn('== "$GITHUB_SHA"', PROMOTE)

    def test_release_candidate_push_stays_community_test_only(self):
        self.assertIn("branches:\n      - release-candidate", CANDIDATE)
        self.assertIn("candidate_version:", CANDIDATE)
        self.assertIn("distribution_mode:", CANDIDATE)
        self.assertIn("default: developer-id-notarized", CANDIDATE)
        self.assertIn("steps.resolve-version.outputs.version", CANDIDATE)
        self.assertIn('DISTRIBUTION_MODE="community-ad-hoc"', CANDIDATE)
        self.assertIn("NOTARIZE_RELEASE=0", CANDIDATE)
        self.assertIn("workflow_run:", PROMOTE)
        self.assertIn("github.event.workflow_run.conclusion == 'success'", PROMOTE)
        self.assertNotIn(
            "github.event.workflow_run.head_branch == 'release-candidate'", PROMOTE
        )

    def test_signed_candidate_is_main_only_and_environment_protected(self):
        self.assertIn("github.ref == 'refs/heads/main'", CANDIDATE)
        self.assertIn(
            "inputs.distribution_mode == 'developer-id-notarized' && "
            "'release-signing'",
            CANDIDATE,
        )
        self.assertIn("|| 'community-ci'", CANDIDATE)
        self.assertIn('[[ "$GITHUB_REF" == "refs/heads/main" ]]', CANDIDATE)
        self.assertIn(
            "WATTSON_NOTARIZE: ${{ steps.resolve-version.outputs.notarize }}",
            CANDIDATE,
        )
        self.assertIn("NOTARIZE_RELEASE=1", CANDIDATE)

    def test_candidate_imports_separate_credentials_into_a_temporary_keychain(self):
        for credential in (
            "MACOS_APP_CERT_P12_BASE64",
            "MACOS_APP_CERT_P12_PASSWORD",
            "MACOS_INSTALLER_CERT_P12_BASE64",
            "MACOS_INSTALLER_CERT_P12_PASSWORD",
            "APPLE_NOTARY_API_KEY_P8_BASE64",
            "APPLE_NOTARY_API_KEY_ID",
            "APPLE_NOTARY_API_ISSUER_ID",
            "vars.APPLE_TEAM_ID",
        ):
            self.assertIn(credential, CANDIDATE)
        self.assertIn('umask 077', CANDIDATE)
        self.assertIn('$RUNNER_TEMP/wattson-signing.XXXXXX', CANDIDATE)
        self.assertIn(
            'APPLE_NOTARY_API_KEY_ID" =~ ^[A-Za-z0-9]{10,64}$', CANDIDATE
        )
        self.assertIn(
            'APPLE_NOTARY_API_ISSUER_ID" =~ ^[0-9A-Fa-f]{8}-', CANDIDATE
        )
        self.assertIn('/usr/bin/openssl rand -base64 48', CANDIDATE)
        self.assertIn('echo "::add-mask::$KEYCHAIN_PASSWORD"', CANDIDATE)
        self.assertIn('security create-keychain', CANDIDATE)
        self.assertNotIn('find-identity -v -p', CANDIDATE)
        self.assertIn('-S apple-tool:,apple:,codesign:', CANDIDATE)
        self.assertIn('"Developer ID Application:', CANDIDATE)
        self.assertIn('"Developer ID Installer:', CANDIDATE)
        self.assertIn('WATTSON_DEVELOPER_ID_APP=$APP_IDENTITY_SHA1', CANDIDATE)
        self.assertIn(
            'WATTSON_DEVELOPER_ID_INSTALLER=$INSTALLER_IDENTITY_SHA1', CANDIDATE
        )
        self.assertIn('WATTSON_NOTARY_KEY_PATH=$NOTARY_KEY_PATH', CANDIDATE)
        self.assertIn(
            'WATTSON_NOTARY_KEY_ID=$APPLE_NOTARY_API_KEY_ID', CANDIDATE
        )
        self.assertIn(
            'WATTSON_NOTARY_ISSUER=$APPLE_NOTARY_API_ISSUER_ID', CANDIDATE
        )
        self.assertIn('WATTSON_EXPECT_TEAM_ID=$EXPECTED_TEAM_ID', CANDIDATE)
        self.assertIn(
            '/bin/rm -f -- "$APP_CERT_PATH" "$INSTALLER_CERT_PATH"', CANDIDATE
        )

        scrub = CANDIDATE.index("- name: Scrub signing credentials")
        upload = CANDIDATE.index("- name: Upload the exact release candidate bytes")
        self.assertLess(scrub, upload)
        self.assertIn("if: always()", CANDIDATE[scrub:upload])
        self.assertIn('security delete-keychain "$SIGNING_KEYCHAIN"', CANDIDATE)
        self.assertIn('/bin/rm -rf -- "$SIGNING_TEMP_DIR"', CANDIDATE)

    def test_promotion_requires_successful_headless_ci_on_the_same_main_sha(self):
        self.assertIn("actions/workflows/ci.yml/runs", PROMOTE)
        self.assertIn("-f branch=main", PROMOTE)
        self.assertIn("-f event=push", PROMOTE)
        self.assertIn('-f head_sha="$GITHUB_SHA"', PROMOTE)
        self.assertIn('.head_sha == $sha', PROMOTE)
        self.assertIn('.conclusion == "success"', PROMOTE)

    def test_promotion_downloads_and_publishes_the_same_artifact(self):
        self.assertIn("run-id: ${{ env.CANDIDATE_RUN_ID }}", PROMOTE)
        self.assertIn(
            "name: Wattson-release-candidate-v${{ env.WATTSON_VERSION }}", PROMOTE
        )
        self.assertIn("sha256sum -c SHA256SUMS.txt", PROMOTE)
        self.assertIn('gh release create "$TAG"', PROMOTE)
        self.assertIn("--verify-tag", PROMOTE)
        self.assertIn("--latest=false", PROMOTE)
        self.assertNotIn("scripts/release.sh", PROMOTE)

    def test_promotion_requires_notarized_developer_id_metadata(self):
        self.assertIn("assert_metadata_key_once", PROMOTE)
        for metadata in (
            "distribution_mode=developer-id",
            "app_signature=developer-id",
            "helper_signature=developer-id",
            "package_signature=developer-id",
            "dmg_signature=developer-id",
            "notarized=yes",
            "stapled=yes",
        ):
            self.assertIn(metadata, PROMOTE)
        self.assertIn("**Verified distribution:**", PROMOTE)
        self.assertNotIn("**Community build:**", PROMOTE)

    def test_promotion_dispatches_homebrew_before_pages(self):
        self.assertIn("actions: write", PROMOTE)
        self.assertIn("gh workflow run homebrew-tap.yml", PROMOTE)
        self.assertNotIn("gh workflow run pages.yml", PROMOTE)
        self.assertIn('--field "release_tag=$TAG"', PROMOTE)

        for workflow in (HOMEBREW, PAGES):
            self.assertIn("workflow_dispatch:", workflow)
            self.assertIn("release_tag:", workflow)
            self.assertIn("releases/tags/$RELEASE_TAG", workflow)
            self.assertIn('== "false"', workflow)

    def test_pages_requires_explicit_stable_release_promotion(self):
        self.assertNotIn("\n  release:", PAGES)
        self.assertNotIn("\n  push:", PAGES)
        self.assertIn("workflow_dispatch:", PAGES)
        self.assertIn("ref: ${{ github.sha }}", PAGES)
        self.assertNotIn("ref: ${{ inputs.release_tag }}", PAGES)
        pages_build_header = PAGES.split("jobs:", 1)[1].split("steps:", 1)[0]
        self.assertIn(
            "NEXT_PUBLIC_RELEASE_VERSION: ${{ inputs.release_tag }}",
            pages_build_header,
        )
        self.assertIn('== "false"', PAGES)

    def test_pages_deploys_the_current_tested_main_site(self):
        self.assertIn("git/ref/heads/main", PAGES)
        self.assertIn('[[ "$GITHUB_SHA" == "$MAIN_SHA" ]]', PAGES)
        self.assertIn("actions/workflows/ci.yml/runs", PAGES)
        self.assertIn("-f branch=main", PAGES)
        self.assertIn("-f event=push", PAGES)
        self.assertIn('-f head_sha="$GITHUB_SHA"', PAGES)
        self.assertIn(".head_sha == $sha", PAGES)
        self.assertIn('.head_branch == "main"', PAGES)
        self.assertIn('.event == "push"', PAGES)
        self.assertIn('.status == "completed"', PAGES)
        self.assertIn('.conclusion == "success"', PAGES)

    def test_homebrew_cask_uses_current_portable_syntax(self):
        self.assertIn('desc "Real-time menu-bar power-flow monitor"', HOMEBREW)
        self.assertIn("depends_on macos: :monterey", HOMEBREW)
        self.assertNotIn('desc "Native macOS', HOMEBREW)
        self.assertNotIn('depends_on macos: ">= :monterey"', HOMEBREW)

    def test_homebrew_accepts_only_strict_supported_release_metadata(self):
        self.assertIn("assert_metadata_key_once", HOMEBREW)
        self.assertIn('case "$RELEASE_DISTRIBUTION_MODE" in', HOMEBREW)
        for metadata in (
            "community-ad-hoc)",
            "app_signature=ad-hoc",
            "helper_signature=ad-hoc",
            "package_signature=unsigned",
            "dmg_signature=unsigned",
            "notarized=no",
            "stapled=no",
            "developer-id)",
            "app_signature=developer-id",
            "helper_signature=developer-id",
            "package_signature=developer-id",
            "dmg_signature=developer-id",
            "notarized=yes",
            "stapled=yes",
        ):
            self.assertIn(metadata, HOMEBREW)
        self.assertIn("unsupported release distribution metadata", HOMEBREW)

    def test_public_homebrew_install_uses_real_hosted_runners(self):
        self.assertIn("workflow_dispatch:", HOMEBREW_INSTALL)
        self.assertIn("release_tag:", HOMEBREW_INSTALL)
        self.assertIn("runner: macos-15-intel", HOMEBREW_INSTALL)
        self.assertIn("runner: macos-26", HOMEBREW_INSTALL)
        self.assertIn('RUNNER_ENVIRONMENT:-}" == "github-hosted"', HOMEBREW_INSTALL)
        self.assertIn("releases/tags/$RELEASE_TAG", HOMEBREW_INSTALL)
        self.assertIn("git/ref/tags/$RELEASE_TAG", HOMEBREW_INSTALL)
        self.assertIn("'.casks[0].version'", HOMEBREW_INSTALL)

    def test_public_homebrew_install_removes_unrelated_untrusted_runner_tap(self):
        install = HOMEBREW_INSTALL.split("\n  install:", 1)[1].split(
            "\n  deploy-pages:", 1
        )[0]
        cleanup = 'brew untap --force aws/tap'
        wattson_tap = 'brew tap laleoarrow/tap'
        self.assertIn(
            'AWS_TAP_DIR="$(brew --repository)/Library/Taps/aws/homebrew-tap"',
            install,
        )
        self.assertIn('if [[ -d "$AWS_TAP_DIR" ]]', install)
        self.assertIn(cleanup, install)
        self.assertNotIn('brew trust aws/tap', install)
        self.assertNotIn('HOMEBREW_NO_REQUIRE_TAP_TRUST', install)
        self.assertLess(install.index(cleanup), install.index(wattson_tap))

    def test_homebrew_recovery_resolves_the_tag_from_the_current_main_sha(self):
        prepare = HOMEBREW_INSTALL.split("  prepare:", 1)[1].split(
            "\n  install:", 1
        )[0]
        self.assertIn("push:\n    branches:\n      - 'homebrew-ready/v*'", HOMEBREW_INSTALL)
        self.assertIn(
            "github.event_name == 'workflow_dispatch' && github.ref == 'refs/heads/main'",
            prepare,
        )
        self.assertIn("push:refs/heads/homebrew-ready/v*", prepare)
        self.assertIn(
            'RELEASE_TAG="${GITHUB_REF#refs/heads/homebrew-ready/}"', prepare
        )
        self.assertIn('RELEASE_TAG="$REQUESTED_TAG"', prepare)
        self.assertIn("release_tag: ${{ steps.resolve.outputs.release_tag }}", prepare)
        self.assertIn("git/ref/heads/main", prepare)
        self.assertIn('[[ "$GITHUB_SHA" == "$MAIN_SHA" ]]', prepare)
        self.assertIn(
            "raw.githubusercontent.com/$GITHUB_REPOSITORY/$GITHUB_SHA/VERSION",
            prepare,
        )
        self.assertIn('[[ "$RELEASE_TAG" == "v$SOURCE_VERSION" ]]', prepare)

    def test_homebrew_recovery_requires_successful_headless_ci_on_the_same_sha(self):
        prepare = HOMEBREW_INSTALL.split("  prepare:", 1)[1].split(
            "\n  install:", 1
        )[0]
        self.assertIn("actions/workflows/ci.yml/runs", prepare)
        self.assertIn("-f branch=main", prepare)
        self.assertIn("-f event=push", prepare)
        self.assertIn('-f head_sha="$GITHUB_SHA"', prepare)
        self.assertIn(".head_sha == $sha", prepare)
        self.assertIn('.head_branch == "main"', prepare)
        self.assertIn('.event == "push"', prepare)
        self.assertIn('.status == "completed"', prepare)
        self.assertIn('.conclusion == "success"', prepare)

    def test_homebrew_recovery_revalidates_release_cask_and_exact_tap_ci(self):
        prepare = HOMEBREW_INSTALL.split("  prepare:", 1)[1].split(
            "\n  install:", 1
        )[0]
        for asset in (
            'PKG_NAME="Wattson-v${VERSION}-macos-universal.pkg"',
            'DMG_NAME="Wattson-v${VERSION}-macos-universal.dmg"',
            'INFO_NAME="Wattson-v${VERSION}-release-info.txt"',
            'CHECKSUM_NAME="SHA256SUMS.txt"',
        ):
            self.assertIn(asset, prepare)
        self.assertIn("releases/tags/$RELEASE_TAG", prepare)
        self.assertIn('.draft "$RELEASE_JSON")" == "false"', prepare)
        self.assertIn('.prerelease "$RELEASE_JSON")" == "false"', prepare)
        self.assertIn(
            'for asset_name in "$PKG_NAME" "$DMG_NAME" "$INFO_NAME" "$CHECKSUM_NAME"',
            prepare,
        )
        self.assertIn('/usr/bin/sha256sum -c "$CHECKSUM_NAME"', prepare)
        self.assertIn("homebrew-tap/git/ref/heads/main", prepare)
        self.assertIn("homebrew-tap/$TAP_SHA/Casks/wattson.rb", prepare)
        self.assertIn('version \\"$VERSION\\"', prepare)
        self.assertIn('sha256 \\"$EXPECTED_SHA\\"', prepare)
        self.assertIn(
            "actions/workflows/tests.yml/runs?event=push&head_sha=$TAP_SHA", prepare
        )
        self.assertIn(".head_sha == $sha", prepare)
        self.assertIn('.head_branch == "main"', prepare)
        self.assertIn('.event == "push"', prepare)
        self.assertIn('.status == "completed"', prepare)
        self.assertIn('.conclusion == "success"', prepare)
        self.assertIn('echo "tap_sha=$TAP_SHA" >> "$GITHUB_OUTPUT"', prepare)
        self.assertIn('echo "pkg_sha=$EXPECTED_SHA" >> "$GITHUB_OUTPUT"', prepare)

        install = HOMEBREW_INSTALL.split("\n  install:", 1)[1].split(
            "\n  deploy-pages:", 1
        )[0]
        self.assertIn("needs: prepare", install)
        self.assertIn(
            "RELEASE_TAG: ${{ needs.prepare.outputs.release_tag }}", install
        )
        self.assertIn(
            "EXPECTED_TAP_SHA: ${{ needs.prepare.outputs.tap_sha }}", install
        )
        self.assertIn(
            "EXPECTED_PKG_SHA: ${{ needs.prepare.outputs.pkg_sha }}", install
        )
        self.assertIn('HOMEBREW_NO_AUTO_UPDATE: "1"', install)
        self.assertIn('git -C "$TAP_REPOSITORY" rev-parse HEAD', install)
        self.assertIn('[[ "$CURRENT_TAP_SHA" == "$EXPECTED_TAP_SHA" ]]', install)
        self.assertIn('sha256 \\"$EXPECTED_PKG_SHA\\"', install)
        self.assertIn("'.casks[0].sha256'", install)
        self.assertNotIn("HOMEBREW_TAP_TOKEN", HOMEBREW_INSTALL)

    def test_public_homebrew_success_gates_the_pages_deployment(self):
        self.assertIn("actions: write", HOMEBREW)
        self.assertIn("Verify the public cask", HOMEBREW)
        self.assertIn("actions/workflows/tests.yml/runs", HOMEBREW)
        self.assertIn("completed:success", HOMEBREW)
        self.assertIn("homebrew-install-test.yml", HOMEBREW)
        self.assertIn('version \\"$VERSION\\"', HOMEBREW)
        self.assertIn('sha256 \\"$EXPECTED_SHA\\"', HOMEBREW)
        deploy = HOMEBREW_INSTALL.split("  deploy-pages:", 1)[1]
        self.assertIn("needs: [prepare, install]", deploy)
        self.assertIn("if: success()", deploy)
        self.assertIn(
            "RELEASE_TAG: ${{ needs.prepare.outputs.release_tag }}", deploy
        )
        self.assertIn("-f make_latest=true", deploy)
        self.assertIn("releases/latest", deploy)
        self.assertIn("gh workflow run pages.yml", deploy)

    def test_public_homebrew_install_covers_the_privileged_lifecycle(self):
        install = "brew install --cask laleoarrow/tap/wattson"
        uninstall = "brew uninstall --cask laleoarrow/tap/wattson"
        self.assertIn(install, HOMEBREW_INSTALL)
        self.assertIn(uninstall, HOMEBREW_INSTALL)
        self.assertNotIn("--no-quarantine", HOMEBREW_INSTALL)
        self.assertIn('"$HELPER_BIN" --health-probe', HOMEBREW_INSTALL)
        self.assertIn("0:0:544", HOMEBREW_INSTALL)
        self.assertIn("0:0:644", HOMEBREW_INSTALL)
        self.assertIn('pkgutil --pkg-info "$RECEIPT"', HOMEBREW_INSTALL)
        self.assertIn("assert_helper_absent", HOMEBREW_INSTALL)
        self.assertIn("assert_login_agent_absent", HOMEBREW_INSTALL)
        self.assertIn("CLEANUP_REQUIRED=1", HOMEBREW_INSTALL)


if __name__ == "__main__":
    unittest.main()
