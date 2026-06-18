import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
INSTALL_SCRIPT = ROOT / "scripts" / "install.sh"


class InstallScriptContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = INSTALL_SCRIPT.read_text(encoding="utf-8")

    def test_installs_login_agent_for_snapshot_writer(self):
        self.assertIn('LAUNCH_AGENT_ID="${APP_BUNDLE_ID}.agent"', self.source)
        self.assertIn('LAUNCH_AGENT_PLIST="$HOME/Library/LaunchAgents/${LAUNCH_AGENT_ID}.plist"', self.source)
        self.assertIn("<key>RunAtLoad</key>", self.source)
        self.assertIn("<key>Crashed</key>", self.source)
        self.assertIn("<true/>", self.source)
        self.assertIn("<key>KeepAlive</key>", self.source)
        self.assertIn("launchctl bootstrap", self.source)
        self.assertIn("launchctl kickstart -k", self.source)

    def test_unloads_existing_login_agent_before_replacing_app(self):
        bootout_index = self.source.index("launchctl bootout")
        remove_index = self.source.index('rm -rf "$APP_DIR"')
        self.assertLess(bootout_index, remove_index)

    def test_removes_legacy_conflicting_launch_agent_label(self):
        self.assertIn('LEGACY_LAUNCH_AGENT_PLIST="$HOME/Library/LaunchAgents/${APP_BUNDLE_ID}.plist"', self.source)
        self.assertIn('rm -f "$LEGACY_LAUNCH_AGENT_PLIST"', self.source)


if __name__ == "__main__":
    unittest.main()
