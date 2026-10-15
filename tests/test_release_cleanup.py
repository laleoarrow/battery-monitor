import os
import pathlib
import shutil
import unittest

from local_runtime import TemporaryDirectory, run


ROOT = pathlib.Path(__file__).resolve().parents[1]


class ReleaseCleanupTests(unittest.TestCase):
    def setUp(self):
        self.workspace = TemporaryDirectory(prefix="release-lifecycle-")
        self.root = pathlib.Path(self.workspace.__enter__())
        self.addCleanup(self.workspace.__exit__, None, None, None)
        self.scripts = self.root / "scripts"
        shutil.copytree(ROOT / "scripts" / "lib", self.scripts / "lib")
        self.bin = self.root / "tools"
        self.bin.mkdir()
        tool = self.bin / "tool"
        tool.write_text('''#!/usr/bin/python3
import os, pathlib, plistlib, shutil, sys, zipfile
name = pathlib.Path(sys.argv[0]).name
a = sys.argv[1:]
def value(flag): return a[a.index(flag) + 1]
if name == 'swift':
    folder = pathlib.Path(value('--scratch-path')) / 'bin'
    folder.mkdir(parents=True, exist_ok=True)
    if '--show-bin-path' in a:
        print(folder)
    else:
        for executable in ('Wattson', 'wattson-helper'):
            p = folder / executable
            p.write_text('#!/bin/sh\\nexit 0\\n')
            p.chmod(0o755)
        sys.exit(int(os.environ.get('FAIL_COMPILE', '0')))
elif name == 'xcrun':
    if a[0] == 'vtool': print('minos 12.0')
    elif a[0] == 'swiftc':
        p = pathlib.Path(value('-o'))
        p.write_text('#!/bin/sh\\nexit 0\\n')
        p.chmod(0o755)
    elif a[0] == 'lipo' and '-create' in a:
        shutil.copy2(a[2], value('-output'))
    elif a[0] == 'actool':
        for resource in ('Assets.car', 'WattsonGlass.icns'):
            (pathlib.Path(value('--compile')) / resource).write_text('fixture')
elif name == 'sips': pathlib.Path(value('--out')).write_text('fixture')
elif name == 'PlistBuddy': print('4.3.1')
elif name == 'codesign': sys.exit(int(os.environ.get('FAIL_SIGN', '0')))
elif name == 'ditto':
    if '-c' in a:
        source, target = map(pathlib.Path, a[-2:])
        with zipfile.ZipFile(target, 'w') as archive:
            for path in source.rglob('*'):
                if path.is_file(): archive.write(path, path.relative_to(source.parent))
    else: shutil.copy2(a[-2], a[-1])
elif name == 'unzip':
    if os.environ.get('FAIL_ARCHIVE') == '1': sys.exit(9)
    archive = pathlib.Path(a[1])
    with zipfile.ZipFile(archive) as data:
        if '-d' in a: data.extractall(value('-d'))
''', encoding="utf-8")
        tool.chmod(0o755)
        commands = ("swift", "xcrun", "sips", "PlistBuddy", "codesign", "ditto", "plutil", "xattr", "lsregister", "unzip")
        for name in commands:
            (self.bin / name).symlink_to(tool)
        for name in ("build_release.sh", "release.sh", "build_diagnostics.sh"):
            source = (ROOT / "scripts" / name).read_text(encoding="utf-8")
            for command in commands:
                for directory in ("/usr/bin/", "/usr/libexec/"):
                    source = source.replace(directory + command, str(self.bin / command))
            (self.scripts / name).write_text(source, encoding="utf-8")
        helper = self.scripts / "lib" / "local_cleanup.sh"
        source = helper.read_text(encoding="utf-8").replace(
            "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
            str(self.bin / "lsregister"),
        )
        helper.write_text(source, encoding="utf-8")
        for name in ("verify_release.sh", "package_pkg.sh", "package_dmg.sh"):
            (self.scripts / name).write_text('''#!/bin/bash
set -euo pipefail
stage="$(basename "$0")"
[[ -d "$WATTSON_RELEASE_BUILD_ROOT/Wattson.app" ]]
echo "$stage:$WATTSON_RELEASE_BUILD_ROOT" >> "$FIXTURE_LOG"
if [[ "$stage" == package_pkg.sh || "$stage" == package_dmg.sh ]]; then
    mkdir -p "$WATTSON_RELEASE_DIST_DIR"
    extension=pkg
    [[ "$stage" != package_dmg.sh ]] || extension=dmg
    echo fixture > "$WATTSON_RELEASE_DIST_DIR/Wattson-v4.3.1-macos-universal.$extension"
fi
[[ "${FAIL_STAGE:-}" != "$stage" ]] || exit 7
''', encoding="utf-8")
        files = ["VERSION", "Package.swift", "Packaging/AppInfo.plist", "BatteryPowerApp.entitlements",
                 "design/icon/WattsonGlass.icon/icon.json", "design/icon/AppIcon.icns",
                 "Support/WattsonDiagnostics/main.swift", "Core/HelperClient.swift"]
        for folder, names in (
            ("in-app-logo", ("AppLogoColor", "AppLogoClearLight", "AppLogoClearDark")),
            ("dock-logo", ("AppDockLogoColor", "AppDockLogoClearLight", "AppDockLogoClearDark")),
        ):
            files.extend(f"design/icon/{folder}/{name}.png" for name in names)
        for name in files:
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("4.3.1\n" if name == "VERSION" else "fixture\n", encoding="utf-8")

    def execute(self, name, *arguments, **environment):
        env = dict(os.environ, FIXTURE_LOG=str(self.root / "stages.log"))
        for key in ("WATTSON_RELEASE_BUILD_ROOT", "WATTSON_RELEASE_DIST_DIR", "WATTSON_DEVELOPER_ID_APP",
                    "WATTSON_DEVELOPER_ID_INSTALLER", "WATTSON_NOTARIZE"):
            env.pop(key, None)
        env.update(environment)
        return run(["/bin/bash", str(self.scripts / name), *arguments],
                   env=env, capture_output=True, text=True, timeout=15,
                   cleanup_grace=65)

    def assert_no_disposable_builds(self):
        self.assertEqual(list((self.root / ".build" / "local.noindex").iterdir()), [])

    def test_standalone_build_cleans_by_default_and_retains_only_on_explicit_request(self):
        result = self.execute("build_release.sh")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assert_no_disposable_builds()
        result = self.execute("build_release.sh", "--keep-build")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue((self.root / ".build/release/Wattson.app").is_dir())
        self.assert_no_disposable_builds()

    def test_compile_failure_cleans_own_root_but_does_not_delete_caller_input(self):
        result = self.execute("build_release.sh", FAIL_COMPILE="8")
        self.assertEqual(result.returncode, 8)
        self.assert_no_disposable_builds()
        caller = self.root / ".build" / "caller.noindex"
        caller.mkdir()
        marker = caller / "existing-input"
        marker.write_text("preserve", encoding="utf-8")
        result = self.execute("build_release.sh", WATTSON_RELEASE_BUILD_ROOT=str(caller))
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(marker.read_text(encoding="utf-8"), "preserve")

    def test_release_transfers_only_verified_artifacts_then_cleans_shared_workspace(self):
        result = self.execute("release.sh")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assert_no_disposable_builds()
        outputs = list((self.root / "dist").iterdir())
        self.assertEqual(len(outputs), 4)
        self.assertTrue((self.root / "dist/SHA256SUMS.txt").is_file())
        stages = (self.root / "stages.log").read_text(encoding="utf-8").splitlines()
        self.assertEqual(len({line.split(":", 1)[1] for line in stages}), 1)

    def test_failed_release_preserves_previous_verified_outputs(self):
        previous = self.root / "dist/Wattson-v4.3.1-macos-universal.pkg"
        previous.parent.mkdir()
        previous.write_text("previous verified bytes", encoding="utf-8")
        result = self.execute("release.sh", FAIL_STAGE="package_dmg.sh")
        self.assertEqual(result.returncode, 7, result.stdout + result.stderr)
        self.assertEqual(previous.read_text(encoding="utf-8"), "previous verified bytes")
        self.assertEqual(list(previous.parent.iterdir()), [previous])
        self.assert_no_disposable_builds()

    def test_diagnostics_failure_preserves_old_zip_and_success_keeps_only_deliverables(self):
        previous = self.root / "dist/support/Wattson-Diagnostics-v1.1.0-macos-universal.zip"
        previous.parent.mkdir(parents=True)
        previous.write_text("previous verified zip", encoding="utf-8")
        result = self.execute("build_diagnostics.sh", FAIL_ARCHIVE="1")
        self.assertEqual(result.returncode, 9, result.stdout + result.stderr)
        self.assertEqual(previous.read_text(encoding="utf-8"), "previous verified zip")
        self.assert_no_disposable_builds()
        result = self.execute("build_diagnostics.sh")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(len(list(previous.parent.iterdir())), 3)
        self.assert_no_disposable_builds()


if __name__ == "__main__":
    unittest.main()
