import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "Support" / "WattsonDiagnostics" / "main.swift").read_text(
    encoding="utf-8"
)
BUILD_SCRIPT = (ROOT / "scripts" / "build_diagnostics.sh").read_text(
    encoding="utf-8"
)


class WattsonDiagnosticsContractTests(unittest.TestCase):
    def test_tool_is_explicitly_read_only_and_does_not_upload(self):
        self.assertIn("readOnlyCommandArguments", SOURCE)
        self.assertIn("No password was requested", SOURCE)
        self.assertNotIn("sudo", SOURCE)
        self.assertNotIn("URLSession", SOURCE)
        self.assertNotIn("curl", SOURCE)
        self.assertNotIn("temporaryDirectory", SOURCE)
        self.assertIn("maximumCapturedBytes = 100_000", SOURCE)
        self.assertIn("String(decoding: data, as: UTF8.self)", SOURCE)
        self.assertNotIn("bootstrap", SOURCE)
        self.assertNotIn("bootout", SOURCE)
        self.assertNotIn("launchctl\", arguments: [\"enable", SOURCE)
        self.assertNotIn("launchctl\", arguments: [\"disable", SOURCE)

    def test_one_click_path_copies_a_bounded_report(self):
        self.assertIn('title: "Collect & Copy Diagnostics"', SOURCE)
        self.assertIn("#selector(collectAndCopy)", SOURCE)
        self.assertIn("NSPasteboard.general", SOURCE)
        self.assertIn("maximumCharacters: 50_000", SOURCE)
        self.assertIn("maximumCharacters: 100_000", SOURCE)
        self.assertIn("applicationShouldTerminate", SOURCE)
        self.assertIn(".terminateCancel", SOURCE)
        self.assertIn("Review it before sending", SOURCE)

    def test_report_covers_the_public_v3_installation_path(self):
        self.assertIn("/Applications/Wattson.app", SOURCE)
        self.assertIn('"-dlnO@"', SOURCE)
        self.assertIn("/Library/PrivilegedHelperTools/com.leoarrow.wattson.helper", SOURCE)
        self.assertIn("/Library/LaunchDaemons/com.leoarrow.wattson.helper.plist", SOURCE)
        self.assertIn('"--pkg-info", "com.leoarrow.wattson.pkg"', SOURCE)
        self.assertIn('"-n", "600", "/var/log/install.log"', SOURCE)
        self.assertIn('"show", "--last", "15m"', SOURCE)
        self.assertIn('subsystem == \\"com.leoarrow.wattson\\"', SOURCE)
        self.assertNotIn('eventMessage CONTAINS', SOURCE)

    def test_build_produces_a_universal_macos_12_app_archive(self):
        self.assertIn("arm64 x86_64", BUILD_SCRIPT)
        self.assertIn("-apple-macos${MIN_MACOS_VERSION}", BUILD_SCRIPT)
        self.assertIn("-verify_arch arm64 x86_64", BUILD_SCRIPT)
        self.assertIn("Wattson-Diagnostics-v${DIAGNOSTICS_VERSION}-macos-universal.zip", BUILD_SCRIPT)
        self.assertIn("codesign --verify --deep --strict", BUILD_SCRIPT)
        self.assertIn("--norsrc --noextattr --noqtn --noacl", BUILD_SCRIPT)
        self.assertIn("archive contains AppleDouble metadata", BUILD_SCRIPT)
        self.assertIn("EXTRACTED_APP", BUILD_SCRIPT)
        self.assertIn("shasum -a 256 -c", BUILD_SCRIPT)


if __name__ == "__main__":
    unittest.main()
