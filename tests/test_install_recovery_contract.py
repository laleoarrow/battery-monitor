import os
import pathlib
import shlex
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
POSTINSTALL = ROOT / "Packaging" / "pkg" / "postinstall"


class InstallRecoveryContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = POSTINSTALL.read_text(encoding="utf-8")
        # Exercise the production failure functions, never the system installer
        # body. Every external command in this extracted slice is replaced.
        cls.functions = "fail() {" + cls.source.split("fail() {", 1)[1].split(
            "\nvalidate_payload_shape() {", 1
        )[0]
        commands = {
            "/usr/libexec/PlistBuddy": "stub_plist",
            "/usr/bin/codesign": "stub_codesign",
            "/usr/bin/stat": "stub_stat",
            "/usr/bin/id": "stub_id",
            "/bin/launchctl": "stub_launchctl",
            "/usr/bin/sudo": "stub_sudo",
            "/usr/bin/open": "stub_open",
        }
        for actual, stub in commands.items():
            cls.functions = cls.functions.replace(actual, stub)
        for prefix in ("/usr/bin/", "/usr/libexec/", "/bin/launchctl"):
            if prefix in cls.functions:
                raise AssertionError("Recovery fixture left a real command unmocked")

    def run_failure(self, *, terminal='exit 42', overrides=None, invalid_app=None):
        with tempfile.TemporaryDirectory(prefix="wattson-install-recovery-") as directory:
            root = pathlib.Path(directory)
            app = root / "Wattson.app"
            executable = app / "Contents" / "MacOS" / "Wattson"
            executable.parent.mkdir(parents=True)
            executable.write_text("fixture only\n", encoding="utf-8")
            info = app / "Contents" / "Info.plist"
            info.write_text("fixture only\n", encoding="utf-8")
            if invalid_app == "missing-executable":
                executable.unlink()
            elif invalid_app == "symlink-app":
                link = root / "Linked.app"
                link.symlink_to(app, target_is_directory=True)
                app = link
            elif invalid_app in ("symlink-contents", "symlink-macos", "symlink-executable", "symlink-info"):
                target = {
                    "symlink-contents": app / "Contents",
                    "symlink-macos": executable.parent,
                    "symlink-executable": executable,
                    "symlink-info": info,
                }[invalid_app]
                moved = root / "Moved"
                target.rename(moved)
                target.symlink_to(moved, target_is_directory=moved.is_dir())

            script = r'''
set -euo pipefail
exec 3>&1
stub_plist() {
    echo "plist:$*" >&3
    echo "${STUB_BUNDLE:-com.leoarrow.wattson}"
}
stub_codesign() {
    echo "codesign:$*" >&3
    return "${STUB_SIGNATURE_STATUS:-0}"
}
stub_stat() {
    echo "console-read" >&3
    if [[ -f "$STUB_STATE" ]]; then
        echo "${STUB_CONSOLE_AFTER:-${STUB_CONSOLE:-sampleuser:501}}"
    else
        : > "$STUB_STATE"
        echo "${STUB_CONSOLE:-sampleuser:501}"
    fi
}
stub_id() {
    echo "id:$*" >&3
    echo "${STUB_UID:-501}"
}
stub_launchctl() {
    echo "launchctl:$*" >&3
    if [[ "$1" == "print" ]]; then
        return "${STUB_GUI_STATUS:-0}"
    fi
    [[ "$1" == "asuser" && "$2" == "501" ]] || return 98
    shift 2
    "$@"
}
stub_sudo() {
    echo "sudo:$*" >&3
    [[ "$1" == "-n" && "$2" == "-u" && "$3" == "#501" && "$4" == "--" ]] || return 99
    shift 4
    "$@"
}
stub_open() {
    echo "open:$*" >&3
    [[ "$1" == "-g" && "$2" == "$APP_DIR" ]] || return 100
    return "${STUB_OPEN_STATUS:-0}"
}
'''
            script += "\nAPP_BUNDLE_ID=com.leoarrow.wattson\n"
            script += f"APP_DIR={shlex.quote(str(app))}\n"
            script += 'APP_EXECUTABLE="$APP_DIR/Contents/MacOS/Wattson"\n'
            script += self.functions
            script += '\ntrap \'finish_installation "$?"\' EXIT\n' + terminal + "\n"
            env = dict(
                os.environ,
                STUB_STATE=str(root / "console-read"),
                STUB_BUNDLE="com.leoarrow.wattson",
                STUB_SIGNATURE_STATUS="0",
                STUB_CONSOLE="sampleuser:501",
                STUB_CONSOLE_AFTER="",
                STUB_UID="501",
                STUB_GUI_STATUS="0",
                STUB_OPEN_STATUS="0",
            )
            env.update(overrides or {})
            return subprocess.run(
                ["/bin/bash", "-c", script],
                env=env, capture_output=True, text=True, timeout=5,
            )

    def test_success_does_not_attempt_recovery_or_launch(self):
        result = self.run_failure(terminal="exit 0")
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
        self.assertEqual(result.stderr, "")

    def test_failure_checks_identity_then_drops_uid_before_opening(self):
        result = self.run_failure()
        self.assertEqual(result.returncode, 42)
        lines = result.stdout.splitlines()
        self.assertTrue(lines[0].startswith("plist:-c Print :CFBundleIdentifier"))
        self.assertTrue(lines[1].startswith("codesign:--verify --deep --strict"))
        self.assertEqual(lines[2:6], [
            "console-read", "id:-u sampleuser", "launchctl:print gui/501", "console-read",
        ])
        self.assertTrue(lines[6].startswith("launchctl:asuser 501 stub_sudo -n -u #501 -- stub_open -g "))
        self.assertTrue(lines[7].startswith("sudo:-n -u #501 -- stub_open -g "))
        self.assertTrue(lines[8].startswith("open:-g "))
        self.assertIn("requested a monitoring restart", result.stderr)
        self.assertIn("https://github.com/laleoarrow/battery-monitor/releases/latest", result.stderr)

    def test_fail_message_and_set_e_status_are_preserved(self):
        explicit = self.run_failure(terminal='fail "helper health probe failed"')
        self.assertEqual(explicit.returncode, 1)
        self.assertTrue(explicit.stderr.startswith("Wattson postinstall: helper health probe failed\n"))
        automatic = self.run_failure(terminal="false")
        self.assertEqual(automatic.returncode, 1)
        self.assertIn("open:-g ", automatic.stdout)

    def test_restart_failure_does_not_replace_installer_failure(self):
        result = self.run_failure(overrides={"STUB_OPEN_STATUS": "7"})
        self.assertEqual(result.returncode, 42)
        self.assertIn("automatic restart was unavailable", result.stderr)
        self.assertIn("open /Applications/Wattson.app", result.stderr)

    def test_headless_invalid_and_changed_console_sessions_never_launch(self):
        for overrides in (
            {"STUB_CONSOLE": "root:0"},
            {"STUB_CONSOLE": "loginwindow:501"},
            {"STUB_CONSOLE": "sampleuser:0"},
            {"STUB_CONSOLE": "sampleuser:000"},
            {"STUB_CONSOLE": "bad user:501"},
            {"STUB_UID": "502"},
            {"STUB_GUI_STATUS": "1"},
            {"STUB_CONSOLE_AFTER": "otheruser:502"},
        ):
            with self.subTest(overrides=overrides):
                result = self.run_failure(overrides=overrides)
                self.assertEqual(result.returncode, 42)
                self.assertNotIn("launchctl:asuser", result.stdout)
                self.assertNotIn("open:-g", result.stdout)

    def test_invalid_bundle_or_signature_never_launches(self):
        for overrides in (
            {"STUB_BUNDLE": "com.example.unrelated"},
            {"STUB_SIGNATURE_STATUS": "1"},
        ):
            with self.subTest(overrides=overrides):
                result = self.run_failure(overrides=overrides)
                self.assertEqual(result.returncode, 42)
                self.assertNotIn("console-read", result.stdout)
                self.assertNotIn("open:-g", result.stdout)

    def test_missing_and_symlinked_bundle_components_never_launch(self):
        for invalid_app in (
            "missing-executable", "symlink-app", "symlink-contents",
            "symlink-macos", "symlink-executable", "symlink-info",
        ):
            with self.subTest(invalid_app=invalid_app):
                result = self.run_failure(invalid_app=invalid_app)
                self.assertEqual(result.returncode, 42)
                self.assertEqual(result.stdout, "")

    def test_trap_is_installed_after_invocation_checks_before_payload_work(self):
        trap = self.source.index('trap \'finish_installation "$?"\' EXIT')
        self.assertLess(self.source.index('fail "Installer did not run as root"'), trap)
        self.assertLess(self.source.index('fail "Wattson can only be installed on the startup volume"'), trap)
        self.assertLess(trap, self.source.index("\nvalidate_payload_shape\n"))
        recovery = self.source.split("recover_monitoring() {", 1)[1].split("\nvalidate_payload_shape() {", 1)[0]
        for forbidden in ("xattr", "spctl", "tccutil", "installer -pkg", "curl", "wget", "chmod", "--args"):
            self.assertNotIn(forbidden, recovery)


if __name__ == "__main__":
    unittest.main()
