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
        self.assertIn("WATTSON_FORCE_REDUCE_MOTION=1", CANDIDATE)
        self.assertIn("WATTSON_FORCE_REDUCE_TRANSPARENCY=1", CANDIDATE)
        self.assertIn("scripts/verify_animation_stress.sh", CANDIDATE)

    def test_promotion_requires_the_successful_main_candidate_run(self):
        self.assertIn("candidate_run_id:", PROMOTE)
        self.assertIn('actions/runs/$CANDIDATE_RUN_ID', PROMOTE)
        self.assertIn('== ".github/workflows/macos-helper-install.yml"', PROMOTE)
        self.assertIn('== "success"', PROMOTE)
        self.assertIn("workflow_dispatch:main", PROMOTE)
        self.assertIn("push:release-candidate", PROMOTE)
        self.assertIn('== "$GITHUB_SHA"', PROMOTE)

    def test_release_candidate_branch_runs_the_fail_closed_promotion_chain(self):
        self.assertIn("branches:\n      - release-candidate", CANDIDATE)
        self.assertIn("candidate_version:", CANDIDATE)
        self.assertIn("steps.resolve-version.outputs.version", CANDIDATE)
        self.assertIn("workflow_run:", PROMOTE)
        self.assertIn("github.event.workflow_run.conclusion == 'success'", PROMOTE)
        self.assertIn("github.event.workflow_run.head_branch == 'release-candidate'", PROMOTE)

    def test_promotion_requires_successful_headless_ci_on_the_same_main_sha(self):
        self.assertIn("actions/workflows/ci.yml/runs", PROMOTE)
        self.assertIn("-f branch=main", PROMOTE)
        self.assertIn("-f event=push", PROMOTE)
        self.assertIn('-f head_sha="$GITHUB_SHA"', PROMOTE)
        self.assertIn('.head_sha == $sha', PROMOTE)
        self.assertIn('.conclusion == "success"', PROMOTE)

    def test_promotion_downloads_and_publishes_the_same_artifact(self):
        self.assertIn("run-id: ${{ env.CANDIDATE_RUN_ID }}", PROMOTE)
        self.assertIn("sha256sum -c SHA256SUMS.txt", PROMOTE)
        self.assertIn('gh release create "$TAG"', PROMOTE)
        self.assertIn("--verify-tag", PROMOTE)
        self.assertIn("--latest=false", PROMOTE)
        self.assertNotIn("scripts/release.sh", PROMOTE)

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
