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
            "github.event_name == 'workflow_dispatch' && github.ref == 'refs/heads/main'",
            PROMOTE,
        )
        self.assertNotIn("workflow_run:", PROMOTE)
        self.assertNotIn("github.event.workflow_run", PROMOTE)
        self.assertIn('== "$GITHUB_SHA"', PROMOTE)

    def test_release_candidate_is_manual_main_only_and_defaults_to_community(self):
        self.assertNotIn("\n  push:", CANDIDATE)
        self.assertNotIn("refs/heads/release-candidate", CANDIDATE)
        self.assertIn("workflow_dispatch:", CANDIDATE)
        self.assertIn(
            "github.event_name == 'workflow_dispatch' && github.ref == 'refs/heads/main'",
            CANDIDATE,
        )
        self.assertIn("candidate_version:", CANDIDATE)
        self.assertIn("distribution_mode:", CANDIDATE)
        self.assertIn("default: community-ad-hoc", CANDIDATE)
        self.assertIn("steps.resolve-version.outputs.version", CANDIDATE)
        self.assertIn('DISTRIBUTION_MODE="$REQUESTED_DISTRIBUTION_MODE"', CANDIDATE)
        self.assertIn("NOTARIZE_RELEASE=0", CANDIDATE)
        self.assertNotIn("gh release create", CANDIDATE)
        self.assertNotIn("gh workflow run promote-release", CANDIDATE)

    def test_candidate_requires_headless_ci_on_the_current_main_sha_before_building(self):
        gate = CANDIDATE.split(
            "- name: Require Headless CI on the frozen main commit", 1
        )[1].split("- name: Resolve and validate the candidate version", 1)[0]
        self.assertIn('[[ "$GITHUB_EVENT_NAME" == "workflow_dispatch" ]]', gate)
        self.assertIn('[[ "$GITHUB_REF" == "refs/heads/main" ]]', gate)
        self.assertIn("git/ref/heads/main", gate)
        self.assertIn('[[ "$GITHUB_SHA" == "$MAIN_SHA" ]]', gate)
        self.assertIn("actions/workflows/ci.yml/runs", gate)
        self.assertIn('-f branch=main -f event=push -f head_sha="$GITHUB_SHA"', gate)
        for identity in (
            ".head_sha == $sha", '.head_branch == "main"', '.event == "push"',
            '.status == "completed"', '.conclusion == "success"',
        ):
            self.assertIn(identity, gate)

    def test_dmg_app_matches_candidate_pkg_and_runs_without_privileged_install(self):
        self.assertIn(
            '/bin/bash scripts/verify_dmg.sh "$DMG_PATH" "$PACKAGED_APP_DIR"',
            CANDIDATE,
        )
        lifecycle = CANDIDATE.split(
            "- name: Test helper-free DMG copy launch and removal without elevation", 1
        )[1].split("- name: Test first install and disabled-service reinstall", 1)[0]
        self.assertIn('[[ "$(/usr/bin/id -u)" != "0" ]]', lifecycle)
        self.assertIn("assert_no_privileged_install()", lifecycle)
        self.assertIn("pkgutil --pkg-info com.leoarrow.wattson.pkg", lifecycle)
        self.assertIn('launchctl print "system/$HELPER_LABEL"', lifecycle)
        self.assertIn('for copy_attempt in 1 2', lifecycle)
        self.assertIn('/usr/bin/ditto "$MOUNT_DIR/Wattson.app" "$APP_DIR"', lifecycle)
        self.assertIn('/usr/bin/diff -qr "$MOUNT_DIR/Wattson.app" "$APP_DIR"', lifecycle)
        self.assertIn('battery_registry="$(/usr/sbin/ioreg -r -c AppleSmartBattery 2>/dev/null)"', lifecycle)
        self.assertIn('[[ "$battery_registry" == *AppleSmartBattery* ]]', lifecycle)
        self.assertNotIn("| /usr/bin/grep -q AppleSmartBattery", lifecycle)
        self.assertIn('[[ "$has_battery" == "0" && "$app_status" == "0" ]]', lifecycle)
        self.assertIn('[[ ! -e "$APP_DIR" && ! -L "$APP_DIR" ]]', lifecycle)
        self.assertGreaterEqual(lifecycle.count("assert_no_privileged_install"), 4)
        self.assertNotIn("sudo", lifecycle)
        self.assertNotIn("/usr/sbin/installer", lifecycle)
        self.assertNotIn("launchctl bootstrap", lifecycle)
        upgrade = CANDIDATE.split(
            'echo "Running the shipped uninstaller, then upgrading an app-only copy..."', 1
        )[1].split("- name: Test upgrade from the published v2.1.5 release", 1)[0]
        seed = upgrade.index('/usr/bin/ditto "$APP_ONLY_SOURCE" "$APP_DIR"')
        full_install = upgrade.index('/usr/sbin/installer', seed)
        self.assertLess(seed, full_install)
        self.assertIn('[[ ! -e "$HELPER_BIN" && ! -e "$HELPER_PLIST" && ! -e "$HELPER_SOCKET" ]]', upgrade[seed:full_install])
        self.assertIn("verify_install", upgrade[full_install:])
        self.assertIn("verify_app_launch_stability", upgrade[full_install:])

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

    def test_public_v3_pkg_upgrade_uses_pinned_bytes_on_every_install_runner(self):
        lifecycle = CANDIDATE.split(
            "- name: Test first install and disabled-service reinstall", 1
        )[1].split("- name: Test upgrade from the published v2.1.5 release", 1)[0]
        upgrade = lifecycle.split(
            'echo "Testing the published 3.0.28 PKG upgrade baseline..."', 1
        )[1].split(
            'echo "Running the shipped uninstaller, then upgrading an app-only copy..."', 1
        )[0]
        self.assertNotIn("\n        if:", lifecycle)
        self.assertIn('[[ "${RUNNER_ENVIRONMENT:-}" == "github-hosted" ]]', lifecycle)
        self.assertIn('readonly BASELINE_VERSION="3.0.28"', upgrade)
        self.assertIn(
            'readonly BASELINE_SHA="86db43a02a79769cd02f022cf6bd5721cdbb96927a83a67e9f144dc8d27127da"',
            upgrade,
        )
        self.assertIn(
            "https://github.com/laleoarrow/battery-monitor/releases/download/"
            "v${BASELINE_VERSION}/Wattson-v${BASELINE_VERSION}-macos-universal.pkg",
            upgrade,
        )
        self.assertIn("--fail --location --proto '=https' --tlsv1.2", upgrade)
        self.assertLess(upgrade.index("shasum -a 256"), upgrade.index("pkgutil --expand-full"))
        baseline_install = upgrade.index('-pkg "$BASELINE_PKG" -target /')
        baseline_health = upgrade.index('verify_install "$BASELINE_VERSION"')
        candidate_install = upgrade.index('-pkg "$PKG_PATH" -target /')
        self.assertLess(upgrade.index("shasum -a 256"), baseline_install)
        self.assertLess(baseline_install, baseline_health)
        self.assertLess(baseline_health, candidate_install)
        self.assertIn("verify_install\n", upgrade[candidate_install:])
        self.assertNotIn("scripts/build_release.sh", upgrade)
        self.assertNotIn(".build/", upgrade)
        self.assertNotIn("--allowUntrusted", upgrade)
        self.assertNotIn("spctl", upgrade)
        self.assertNotIn("tccutil", upgrade)
        self.assertNotIn("xattr", upgrade)
        self.assertEqual(upgrade.count("verify_app_launch_stability"), 2)
        self.assertIn('"$RUNNER_TEMP/wattson-v3-upgrade.log"', upgrade)
        self.assertIn('/bin/rm -rf -- "$APP_ONLY_STAGE"', lifecycle)
        self.assertEqual(lifecycle.count("          uninstall_and_verify\n"), 2)

    def test_public_v3_upgrade_preserves_preferences_and_exact_installed_payloads(self):
        lifecycle = CANDIDATE.split(
            "- name: Test first install and disabled-service reinstall", 1
        )[1].split("- name: Test upgrade from the published v2.1.5 release", 1)[0]
        verify = lifecycle.split("verify_install() {", 1)[1].split(
            "verify_app_launch_stability()", 1
        )[0]
        self.assertIn('local expected_version="${1:-$WATTSON_VERSION}"', verify)
        for field in ("CFBundleShortVersionString", "CFBundleVersion"):
            self.assertIn(
                f"Print :{field}' \"$APP_DIR/Contents/Info.plist\")\" == \"$expected_version\"",
                verify,
            )
        self.assertIn('pkgutil --pkg-info "$RECEIPT"', verify)
        self.assertEqual(verify.count('== "$expected_version"'), 3)
        for probe in ("--health-probe", "--helper-health-probe", "--helper-v5-observation-probe"):
            self.assertIn(probe, verify)
        self.assertIn('codesign --verify --deep --strict "$APP_DIR"', verify)
        self.assertIn('codesign --verify --strict "$HELPER_BIN"', verify)
        for source in (
            '"$BASELINE_PAYLOAD/Applications/Wattson.app"', '"$APP_ONLY_SOURCE"',
        ):
            self.assertIn(f'/usr/bin/diff -qr {source} "$APP_DIR"', lifecycle)
        for payload in ("BASELINE_PAYLOAD", "CANDIDATE_PAYLOAD"):
            self.assertIn(
                f'/usr/bin/sudo -n /usr/bin/cmp -s "${payload}/Library/PrivilegedHelperTools/$HELPER_LABEL" "$HELPER_BIN"',
                lifecycle,
            )
        preference = "Print :updates.checkOnLaunch"
        self.assertEqual(lifecycle.count(preference), 3)
        self.assertIn(
            'readonly SANDBOX_PREFERENCES="$USER_CONTAINER/Data/Library/Preferences/com.leoarrow.wattson.plist"',
            lifecycle,
        )
        self.assertIn('/usr/bin/defaults write "$SANDBOX_PREFERENCES" updates.checkOnLaunch -bool false', lifecycle)
        self.assertNotIn("/usr/bin/defaults write com.leoarrow.wattson", lifecycle)
        self.assertEqual(lifecycle.count(
            '\'Print :updates.checkOnLaunch\' "$SANDBOX_PREFERENCES")" == "false"'
        ), 3)
        self.assertNotIn('\'Print :updates.checkOnLaunch\' "$USER_PREFERENCES"', lifecycle)
        preference_seed = lifecycle.index("/usr/bin/defaults write")
        baseline_health = lifecycle.index('verify_install "$BASELINE_VERSION"')
        baseline_launch = lifecycle.index("verify_app_launch_stability", baseline_health)
        self.assertLess(baseline_launch, preference_seed)
        path_validation = lifecycle[baseline_launch:preference_seed]
        for component in (
            '"$USER_CONTAINER"', '"$USER_CONTAINER/Data"',
            '"$USER_CONTAINER/Data/Library"', '"$USER_CONTAINER/Data/Library/Preferences"',
        ):
            self.assertIn(component, path_validation)
        self.assertIn('[[ -d "$preference_directory" && ! -L "$preference_directory" ]]', path_validation)
        self.assertIn('stat -f \'%u\' "$preference_directory"', path_validation)
        self.assertIn('[[ ! -L "$SANDBOX_PREFERENCES" ]]', path_validation)
        self.assertIn('[[ ! -e "$SANDBOX_PREFERENCES" || -f "$SANDBOX_PREFERENCES" ]]', path_validation)
        self.assertNotIn("/bin/mkdir", path_validation)
        candidate_install = lifecycle.index('-pkg "$PKG_PATH" -target /', preference_seed)
        self.assertLess(lifecycle.index(preference, preference_seed), candidate_install)
        self.assertEqual(lifecycle[candidate_install:].count(preference), 2)
        self.assertIn('[[ "$has_battery" == "0" && "$exit_status" == "0" ]]', lifecycle)
        self.assertIn("not a UI-read assertion", lifecycle)

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
        self.assertNotIn("verified:", HOMEBREW)

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

    def test_homebrew_manual_entry_resolves_the_tag_from_the_current_main_sha(self):
        prepare = HOMEBREW_INSTALL.split("  prepare:", 1)[1].split(
            "\n  install:", 1
        )[0]
        self.assertNotIn("\n  push:", HOMEBREW_INSTALL)
        self.assertNotIn("homebrew-ready", HOMEBREW_INSTALL)
        self.assertIn(
            "github.event_name == 'workflow_dispatch' && github.ref == 'refs/heads/main'",
            prepare,
        )
        self.assertIn('[[ "$GITHUB_REF" == "refs/heads/main" ]]', prepare)
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
