import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
INSTALL_SCRIPT = ROOT / "scripts" / "install.sh"


class InstallScriptContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = INSTALL_SCRIPT.read_text(encoding="utf-8")

    def test_removes_both_legacy_login_agent_names(self):
        self.assertIn(
            'LEGACY_AGENT="$HOME/Library/LaunchAgents/${LEGACY_BUNDLE_ID}.agent.plist"',
            self.source,
        )
        self.assertIn(
            'LEGACY_AGENT_OLD="$HOME/Library/LaunchAgents/${LEGACY_BUNDLE_ID}.plist"',
            self.source,
        )
        self.assertIn('launchctl bootout "$LAUNCH_DOMAIN" "$LEGACY_AGENT"', self.source)
        self.assertIn('launchctl bootout "$LAUNCH_DOMAIN" "$LEGACY_AGENT_OLD"', self.source)
        self.assertIn('rm -f "$LEGACY_AGENT" "$LEGACY_AGENT_OLD"', self.source)

    def test_unloads_existing_login_agent_before_removing_legacy_app(self):
        bootout_index = self.source.index("launchctl bootout")
        remove_index = self.source.index('rm -rf "$LEGACY_APP"')
        self.assertLess(bootout_index, remove_index)


if __name__ == "__main__":
    unittest.main()
