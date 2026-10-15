import os
import pathlib
import plistlib
import shutil
import sys
import unittest

from local_runtime import ROOT, TemporaryDirectory, run
import local_runtime


class DeveloperRuntimeCleanupTests(unittest.TestCase):
    def setUp(self):
        workspace = TemporaryDirectory(prefix="developer-script-")
        self.addCleanup(workspace.cleanup)
        self.root = pathlib.Path(workspace.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.home = self.root / "fixture-home"
        self.home.mkdir()
        self.log = self.root / "commands.log"
        self.stub = self.bin / "stub"
        binary_source = '#!/bin/bash\nexit ${FIXTURE_RUN_STATUS:-0}\n'
        self.stub.write_text(
            f"#!{sys.executable}\n"
            "import os,pathlib,sys,time\n"
            "name=pathlib.Path(sys.argv[0]).name\n"
            "with open(os.environ['FIXTURE_LOG'],'a') as f: f.write(name+':'+repr(sys.argv[1:])+'\\n')\n"
            "if name=='xcrun' and '-o' in sys.argv:\n"
            "    if os.environ.get('FIXTURE_COMPILE_STATUS'): sys.exit(int(os.environ['FIXTURE_COMPILE_STATUS']))\n"
            "    output=pathlib.Path(sys.argv[sys.argv.index('-o')+1])\n"
            f"    output.write_text({binary_source!r})\n"
            "    output.chmod(0o755)\n"
            "elif name=='codesign': sys.exit(int(os.environ.get('FIXTURE_SIGN_STATUS','0')))\n"
            "elif name=='swift': sys.exit(int(os.environ.get('FIXTURE_HELPER_STATUS','99')))\n"
            "elif name=='sudo': sys.exit(99)\n"
            "elif name=='sips': pathlib.Path(sys.argv[-1]).touch()\n"
            "elif name=='pmset': print(' powermode 0')\n",
            encoding="utf-8",
        )
        self.stub.chmod(0o755)
        for command in ("xcrun", "codesign", "swift", "sudo", "sips", "pmset", "launchctl", "pkill", "lsregister"):
            (self.bin / command).symlink_to(self.stub)
        scripts = self.root / "scripts"
        scripts.mkdir()
        shutil.copytree(ROOT / "scripts/lib", scripts / "lib")
        for name in ("install.sh", "verify_interaction.sh", "verify_animation_stress.sh"):
            source = (ROOT / "scripts" / name).read_text()
            source = source.replace('$HOME', '$FIXTURE_HOME')
            source = source.replace('CANONICAL_APP_DIR="/Applications/Wattson.app"',
                                    'CANONICAL_APP_DIR="$ROOT_DIR/canonical/Wattson.app"')
            for command in ("sips", "pmset"):
                source = source.replace('/usr/bin/' + command, str(self.bin / command))
            source = source.replace('/usr/sbin/taskpolicy -b /usr/bin/nice -n 15 ', '')
            source = source.replace('/usr/bin/xcrun', str(self.bin / 'xcrun'))
            source = source.replace('/usr/bin/swift', str(self.bin / 'swift'))
            source = source.replace(str(local_runtime.LSREGISTER), str(self.bin / 'lsregister'))
            (scripts / name).write_text(source)
        library = scripts / "lib/local_cleanup.sh"
        library.write_text(library.read_text().replace('$HOME', '$FIXTURE_HOME').replace(
            str(local_runtime.LSREGISTER), str(self.bin / 'lsregister')))
        (self.root / "VERSION").write_text("0.0.0\n")
        for folder, names in (
            ("", ("AppIcon.icns",)),
            ("in-app-logo", ("AppLogoColor.png", "AppLogoClearLight.png", "AppLogoClearDark.png")),
            ("dock-logo", ("AppDockLogoColor.png", "AppDockLogoClearLight.png", "AppDockLogoClearDark.png")),
        ):
            directory = self.root / "design/icon" / folder
            directory.mkdir(parents=True, exist_ok=True)
            for name in names:
                (directory / name).write_text("fixture")
        self.environment = {
            **os.environ, "PATH": str(self.bin) + os.pathsep + os.environ["PATH"],
            "FIXTURE_HOME": str(self.home), "FIXTURE_LOG": str(self.log),
            "FIXTURE_PID": str(self.root / "harness.pid"),
        }

    def invoke(self, name, *arguments, **overrides):
        return run(["/bin/bash", str(self.root / "scripts" / name), *arguments],
                   env={**self.environment, **overrides}, capture_output=True,
                   text=True, timeout=15, cleanup_grace=65)

    def assert_no_scratch(self):
        self.assertEqual(list((self.root / ".build").glob("*.noindex/run.*")), [])

    def seed_install(self):
        app = self.home / "Applications/Wattson.app"
        (app / "Contents").mkdir(parents=True)
        (app / "Contents/Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": "com.leoarrow.wattson"}))
        marker = app / "old-build"
        marker.write_text("previous verified build")
        return app, marker

    def test_install_preserves_previous_app_until_candidate_verifies(self):
        app, marker = self.seed_install()
        for failure in ("FIXTURE_COMPILE_STATUS", "FIXTURE_SIGN_STATUS"):
            with self.subTest(failure=failure):
                result = self.invoke("install.sh", "--app-only", **{failure: "7"})
                self.assertEqual(result.returncode, 7, result.stdout + result.stderr)
                self.assertEqual(marker.read_text(), "previous verified build")
                self.assert_no_scratch()
        result = self.invoke("install.sh", "--app-only")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(marker.exists())
        self.assertTrue((app / "Contents/MacOS/Wattson").exists())
        self.assert_no_scratch()

    def test_canonical_install_refuses_before_any_build_or_mutation(self):
        _, marker = self.seed_install()
        (self.root / "canonical/Wattson.app").mkdir(parents=True)
        result = self.invoke("install.sh", "--app-only")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertTrue(marker.exists())
        self.assertFalse(self.log.exists())
        self.assertFalse((self.root / ".build").exists())

    def test_helper_compile_failure_preserves_previous_app_without_sudo(self):
        _, marker = self.seed_install()
        result = self.invoke("install.sh", FIXTURE_HELPER_STATUS="7")
        self.assertEqual(result.returncode, 7, result.stdout + result.stderr)
        self.assertTrue(marker.exists())
        self.assertNotIn("sudo:", self.log.read_text())
        self.assert_no_scratch()

    def test_gui_scripts_clean_success_compile_failure_and_harness_failure(self):
        for script in ("verify_interaction.sh", "verify_animation_stress.sh"):
            for overrides in ({}, {"FIXTURE_COMPILE_STATUS": "7"}, {"FIXTURE_RUN_STATUS": "9"}):
                with self.subTest(script=script, overrides=overrides):
                    result = self.invoke(script, **overrides)
                    self.assertEqual(result.returncode, int(next(iter(overrides.values()), "0")),
                                     result.stdout + result.stderr)
                    self.assert_no_scratch()


if __name__ == "__main__":
    unittest.main()
