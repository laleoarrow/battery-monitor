import os
import pathlib
import shutil
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
RUNNER = ROOT / "scripts" / "verify_interaction.sh"
HARNESS = ROOT / "tests" / "interaction" / "main.swift"


class InteractionBehaviorTests(unittest.TestCase):
    """Executes the click and popover paths instead of reading them.

    Every other test in this suite asserts against source text. That is enough
    for geometry and constants, and it was not enough here: reading the code
    missed a press held past the coalescing window acting twice, and missed a
    click during the close animation being swallowed. Both only appear when
    AppKit's own timing is in the loop, so this one builds a real .app and
    drives real NSStatusItem and NSPopover objects.

    It takes about 20 seconds and displays a real popover, so it is opt-in.
    Set WATTSON_RUN_INTERACTION=1 only in a disposable or idle GUI session.
    """

    def test_slider_harness_uses_the_production_mode_order(self):
        source = HARNESS.read_text(encoding="utf-8")
        self.assertIn("ModeSliderView(modes: [.auto, .low, .high])", source)
        self.assertNotIn("ModeSliderView(modes: [.low, .auto, .high])", source)

    def _assert_interaction_contract(
        self, force_legacy=False, accessibility_fallback=False,
        force_reduce_transparency=False
    ):
        if os.environ.get("WATTSON_RUN_INTERACTION") != "1":
            self.skipTest("real AppKit interaction is opt-in (WATTSON_RUN_INTERACTION=1)")
        if shutil.which("xcrun") is None:
            self.skipTest("no Xcode command line tools")
        # A status item cannot host a popover without a window server.
        probe = subprocess.run(
            ["launchctl", "managername"], capture_output=True, text=True, check=False
        )
        if "Aqua" not in probe.stdout:
            self.skipTest("no GUI session; a status item cannot host a popover")

        environment = os.environ.copy()
        if force_legacy:
            environment["WATTSON_FORCE_LEGACY_KNOB"] = "1"
        if accessibility_fallback:
            environment["WATTSON_FORCE_REDUCE_MOTION"] = "1"
            environment["WATTSON_FORCE_REDUCE_TRANSPARENCY"] = "1"
        else:
            environment["WATTSON_FORCE_REDUCE_MOTION"] = "0"
            environment["WATTSON_FORCE_REDUCE_TRANSPARENCY"] = (
                "1" if force_reduce_transparency else "0"
            )
        result = subprocess.run(
            ["/bin/bash", str(RUNNER)], capture_output=True, text=True, check=False,
            timeout=300, env=environment
        )
        output = result.stdout + result.stderr
        # A locked screen starts CoreAnimation but never completes it, so the
        # popover never finishes closing. Those checks cannot run; counting
        # them as passes would overstate the coverage and counting them as
        # failures would invent bugs.
        if "SCREEN_LOCKED_CHECKS_SKIPPED" in output:
            self.assertEqual(result.returncode, 2, output)
            self.skipTest("screen is locked; popover close checks cannot run")
        self.assertEqual(result.returncode, 0, output)
        self.assertIn("ALL_INTERACTION_CHECKS_PASSED", output, output)
        # A harness that silently stops checking still prints a pass line.
        self.assertGreaterEqual(output.count("✅"), 32, output)

    def test_interaction_contract_holds_against_real_appkit(self):
        self._assert_interaction_contract()

    def test_legacy_slider_contract_holds_against_real_appkit(self):
        self._assert_interaction_contract(force_legacy=True, accessibility_fallback=True)

    def test_legacy_optical_lens_contract_holds_against_real_appkit(self):
        self._assert_interaction_contract(force_legacy=True)

    def test_reduce_transparency_contract_holds_against_real_appkit(self):
        self._assert_interaction_contract(force_reduce_transparency=True)


if __name__ == "__main__":
    unittest.main()
