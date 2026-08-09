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

    def test_pages_requires_explicit_tag_pinned_promotion(self):
        self.assertNotIn("\n  release:", PAGES)
        self.assertNotIn("\n  push:", PAGES)
        self.assertIn("workflow_dispatch:", PAGES)
        self.assertIn("ref: ${{ inputs.release_tag }}", PAGES)
        self.assertIn('== "false"', PAGES)

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

    def test_public_homebrew_success_gates_the_pages_deployment(self):
        self.assertIn("actions: write", HOMEBREW)
        self.assertIn("Verify the public cask", HOMEBREW)
        self.assertIn("actions/workflows/tests.yml/runs", HOMEBREW)
        self.assertIn("completed:success", HOMEBREW)
        self.assertIn("homebrew-install-test.yml", HOMEBREW)
        self.assertIn('version \\"$VERSION\\"', HOMEBREW)
        self.assertIn('sha256 \\"$EXPECTED_SHA\\"', HOMEBREW)
        self.assertIn("deploy-pages:", HOMEBREW_INSTALL)
        self.assertIn("needs: install", HOMEBREW_INSTALL)
        self.assertIn("if: success() && github.ref == 'refs/heads/main'", HOMEBREW_INSTALL)
        self.assertIn("-f make_latest=true", HOMEBREW_INSTALL)
        self.assertIn("releases/latest", HOMEBREW_INSTALL)
        self.assertIn("gh workflow run pages.yml", HOMEBREW_INSTALL)

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
