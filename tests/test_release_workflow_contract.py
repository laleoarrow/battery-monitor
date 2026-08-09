import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
PROMOTE = (ROOT / ".github/workflows/promote-release.yml").read_text(encoding="utf-8")
PAGES = (ROOT / ".github/workflows/pages.yml").read_text(encoding="utf-8")
HOMEBREW = (ROOT / ".github/workflows/homebrew-tap.yml").read_text(encoding="utf-8")
CI = (ROOT / ".github/workflows/ci.yml").read_text(encoding="utf-8")
CANDIDATE = (ROOT / ".github/workflows/macos-helper-install.yml").read_text(encoding="utf-8")


class ReleaseWorkflowContractTests(unittest.TestCase):
    def test_macos_workflows_use_the_tk_capable_system_python(self):
        command = "/usr/bin/python3 -m unittest discover -s tests -v"
        self.assertIn(command, CI)
        self.assertIn(command, CANDIDATE)
        self.assertNotIn(" WATTSON_RUN_INTERACTION python3 ", CI)
        self.assertNotIn(" WATTSON_RUN_INTERACTION python3 ", CANDIDATE)

    def test_promotion_requires_the_successful_main_candidate_run(self):
        self.assertIn("candidate_run_id:", PROMOTE)
        self.assertIn('actions/runs/$CANDIDATE_RUN_ID', PROMOTE)
        self.assertIn('== ".github/workflows/macos-helper-install.yml"', PROMOTE)
        self.assertIn('== "success"', PROMOTE)
        self.assertIn('== "main"', PROMOTE)
        self.assertIn('== "$GITHUB_SHA"', PROMOTE)

    def test_promotion_downloads_and_publishes_the_same_artifact(self):
        self.assertIn("run-id: ${{ env.CANDIDATE_RUN_ID }}", PROMOTE)
        self.assertIn("sha256sum -c SHA256SUMS.txt", PROMOTE)
        self.assertIn('gh release create "$TAG"', PROMOTE)
        self.assertIn("--verify-tag", PROMOTE)
        self.assertIn("--latest", PROMOTE)
        self.assertNotIn("scripts/release.sh", PROMOTE)

    def test_promotion_explicitly_dispatches_downstream_workflows(self):
        self.assertIn("actions: write", PROMOTE)
        self.assertIn("gh workflow run homebrew-tap.yml", PROMOTE)
        self.assertIn("gh workflow run pages.yml", PROMOTE)
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
        self.assertIn("enablement: true", PAGES)
        self.assertIn('== "false"', PAGES)


if __name__ == "__main__":
    unittest.main()
