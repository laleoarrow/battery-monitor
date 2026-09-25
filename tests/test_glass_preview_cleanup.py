import os
import pathlib
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
BUILD_SCRIPT = ROOT / "scripts" / "build_glass_preview.sh"


class GlassPreviewCleanupTests(unittest.TestCase):
    def setUp(self):
        # Run the actual shell lifecycle in a disposable project. Replace only
        # compiler/macOS commands so tests never register or launch a real app.
        fixture_root = ROOT / ".build" / "preview-tests.noindex"
        fixture_root.mkdir(parents=True, exist_ok=True)
        directory = tempfile.TemporaryDirectory(dir=fixture_root)
        self.addCleanup(directory.cleanup)
        self.root = pathlib.Path(directory.name)
        self.script = self.root / "scripts" / "build_glass_preview.sh"
        self.script.parent.mkdir()
        source = BUILD_SCRIPT.read_text(encoding="utf-8")
        for command, stub in {
            "/usr/bin/pgrep": "stub_pgrep",
            "/usr/libexec/PlistBuddy": "stub_plist",
            "/usr/bin/sips": "stub_sips",
            "/usr/bin/plutil": "stub_plutil",
            "/usr/bin/codesign": "stub_codesign",
            "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister": "stub_lsregister",
        }.items():
            source = source.replace(command, stub)
        stubs = r'''
stub_pgrep() { return "${STUB_RUNNING:-1}"; }
stub_plist() {
    if [[ "$2" == "Print :CFBundleIdentifier" ]]; then
        echo "${STUB_EXISTING_ID:-com.leoarrow.wattson.glass-preview}"
    fi
}
stub_sips() { touch "${@: -1}"; }
stub_plutil() { :; }
stub_codesign() {
    echo "codesign:$1" >> "$STUB_LOG"
    if [[ -n "${STUB_SIGN_SIGNAL:-}" ]]; then
        kill -"$STUB_SIGN_SIGNAL" "$$"
    fi
    return "${STUB_SIGN_STATUS:-0}"
}
stub_lsregister() {
    if [[ -d "$2" ]]; then
        echo "unregister-existing:$2" >> "$STUB_LOG"
    else
        echo "unregister-missing:$2" >> "$STUB_LOG"
    fi
}
xcrun() {
    echo "compile" >> "$STUB_LOG"
    [[ "${STUB_COMPILE_STATUS:-0}" == 0 ]] || return "$STUB_COMPILE_STATUS"
    while [[ "$1" != "-o" ]]; do shift; done
    cat > "$2" << 'EXECUTABLE'
#!/bin/bash
[[ "$1" == "--verify-defaults" ]] || exit 99
echo "self-test" >> "$STUB_LOG"
exit "${STUB_SELF_TEST_STATUS:-0}"
EXECUTABLE
    chmod +x "$2"
}
'''
        self.script.write_text(stubs + source, encoding="utf-8")
        (self.root / "VERSION").write_text("4.3.1\n", encoding="utf-8")
        files = ["Tests/visual/glass_preview_Info.plist", "design/icon/AppIcon.icns"]
        for folder, names in (
            ("in-app-logo", ("AppLogoColor", "AppLogoClearLight", "AppLogoClearDark")),
            ("dock-logo", ("AppDockLogoColor", "AppDockLogoClearLight", "AppDockLogoClearDark")),
        ):
            files.extend(f"design/icon/{folder}/{name}.png" for name in names)
        for name in files:
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("fixture\n", encoding="utf-8")
        self.preview_root = self.root / ".build" / "preview.noindex"
        self.app = self.preview_root / "Wattson Glass Preview.app"
        self.log = self.root / "commands.log"

    def run_build(self, *arguments, **overrides):
        env = dict(os.environ, STUB_LOG=str(self.log), **overrides)
        return subprocess.run(
            ["/bin/bash", str(self.script), *arguments],
            env=env, capture_output=True, text=True, timeout=5,
        )

    def seed_existing_app(self):
        marker = self.app / "Contents" / "old-build"
        marker.parent.mkdir(parents=True)
        marker.write_text("old build", encoding="utf-8")
        return marker

    def assert_only_final_app_remains(self):
        self.assertEqual(list(self.preview_root.iterdir()), [self.app])
        self.assertEqual(list(self.root.rglob("*.app")), [self.app])

    def test_repeated_success_keeps_one_app_and_unregisters_before_replacement(self):
        for attempt in range(3):
            with self.subTest(attempt=attempt):
                result = self.run_build()
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn(str(self.app), result.stdout)
                self.assert_only_final_app_remains()
        events = self.log.read_text(encoding="utf-8").splitlines()
        self.assertEqual(events.count(f"unregister-existing:{self.app}"), 2)
        self.assertFalse(any(line.startswith("unregister-missing:") for line in events))
        for index, event in enumerate(events):
            if event == f"unregister-existing:{self.app}":
                self.assertEqual(events[index - 2], "self-test")

    def test_failures_preserve_previous_app_and_remove_staging(self):
        marker = self.seed_existing_app()
        for failure in ("STUB_COMPILE_STATUS", "STUB_SIGN_STATUS", "STUB_SELF_TEST_STATUS"):
            with self.subTest(failure=failure):
                self.log.write_text("", encoding="utf-8")
                result = self.run_build(**{failure: "7"})
                self.assertEqual(result.returncode, 7, result.stdout + result.stderr)
                self.assertEqual(marker.read_text(encoding="utf-8"), "old build")
                self.assert_only_final_app_remains()
                self.assertNotIn(
                    f"unregister-existing:{self.app}\n",
                    self.log.read_text(encoding="utf-8"),
                )

    def test_failed_first_build_leaves_no_bundle(self):
        result = self.run_build(STUB_SELF_TEST_STATUS="8")
        self.assertEqual(result.returncode, 8)
        self.assertEqual(list(self.preview_root.iterdir()), [])
        self.assertEqual(list(self.root.rglob("*.app")), [])

    def test_interrupts_preserve_previous_app_and_remove_staging(self):
        marker = self.seed_existing_app()
        for signal, status in (("INT", 130), ("TERM", 143)):
            with self.subTest(signal=signal):
                result = self.run_build(STUB_SIGN_SIGNAL=signal)
                self.assertEqual(result.returncode, status, result.stdout + result.stderr)
                self.assertTrue(marker.exists())
                self.assert_only_final_app_remains()

    def test_guards_reject_running_unrelated_and_symlinked_apps(self):
        result = self.run_build(STUB_RUNNING="0")
        self.assertEqual(result.returncode, 2)
        self.assertFalse(self.preview_root.exists())
        marker = self.seed_existing_app()
        result = self.run_build(STUB_EXISTING_ID="com.example.unrelated")
        self.assertEqual(result.returncode, 2)
        self.assertTrue(marker.exists())
        moved = self.root / "unrelated-bundle"
        self.app.rename(moved)
        self.app.symlink_to(moved, target_is_directory=True)
        result = self.run_build()
        self.assertEqual(result.returncode, 2)
        self.assertTrue((moved / "Contents" / "old-build").exists())
        self.assertFalse(self.log.exists())


if __name__ == "__main__":
    unittest.main()
