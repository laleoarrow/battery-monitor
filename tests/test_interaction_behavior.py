import os
import pathlib
import shutil
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
RUNNER = ROOT / "scripts" / "verify_interaction.sh"


class InteractionBehaviorTests(unittest.TestCase):
    """Executes the click and popover paths instead of reading them.

    Every other test in this suite asserts against source text. That is enough
    for geometry and constants, and it was not enough here: reading the code
    missed a press held past the coalescing window acting twice, and missed a
    click during the close animation being swallowed. Both only appear when
    AppKit's own timing is in the loop, so this one builds a real .app and
    drives real NSStatusItem and NSPopover objects.

    It takes about 20 seconds. Set WATTSON_SKIP_INTERACTION=1 to skip it while
    iterating on the fast structural tests.
    """

    def test_interaction_contract_holds_against_real_appkit(self):
        if os.environ.get("WATTSON_SKIP_INTERACTION") == "1":
            self.skipTest("WATTSON_SKIP_INTERACTION=1")
        if shutil.which("xcrun") is None:
            self.skipTest("no Xcode command line tools")
        # A status item cannot host a popover without a window server.
        probe = subprocess.run(
            ["launchctl", "managername"], capture_output=True, text=True, check=False
        )
        if "Aqua" not in probe.stdout:
            self.skipTest("no GUI session; a status item cannot host a popover")

        result = subprocess.run(
            ["/bin/bash", str(RUNNER)], capture_output=True, text=True, check=False, timeout=300
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


if __name__ == "__main__":
    unittest.main()
