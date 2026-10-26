import os
import pathlib
import shutil
import signal
import subprocess
import time
import unittest

from local_runtime import TemporaryDirectory, run


ROOT = pathlib.Path(__file__).resolve().parents[1]


class RendererLifecycleTests(unittest.TestCase):
    def setUp(self):
        self.workspace = TemporaryDirectory(prefix="renderer-owner-")
        self.addCleanup(self.workspace.cleanup)
        self.root = pathlib.Path(self.workspace.name)
        scripts = self.root / "scripts"
        shutil.copytree(ROOT / "scripts/lib", scripts / "lib")
        self.script = scripts / "measure_renderers.sh"
        self.script.write_text((ROOT / "scripts/measure_renderers.sh").read_text().replace(
            "wattson_run_timeout 120", "wattson_run_timeout 0.5"))
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.preferences = self.root / "fixture-home/Library/Preferences"
        self.preferences.mkdir(parents=True)
        self.sentinel = self.preferences / "caller-owned.plist"
        self.sentinel.write_text("preserved")
        library = scripts / "lib/local_cleanup.sh"
        library.write_text(library.read_text().replace("$HOME/", "$FIXTURE_HOME/").replace(
            "/usr/bin/defaults", '"$STUB_BIN/defaults"'))
        self.stub("defaults", '''
[[ "$1" == delete && -z "${CFFIXED_USER_HOME:-}" ]] || exit 91
printf '%s\n' "$2" >> "$FIXTURE_ROOT/deleted"
: > "$FIXTURE_HOME/Library/Preferences/$2.plist"
''')
        self.stub("xcrun", '''
[[ "$1" == swiftc ]] || exit 92
while [[ "$1" != -o ]]; do shift; done
cp "$STUB_BIN/benchmark" "$2"
chmod +x "$2"
printf '%s\n' "$2" > "$FIXTURE_ROOT/binary"
exit "${COMPILE_STATUS:-0}"
''')
        self.stub("benchmark", '''
[[ -z "${CFFIXED_USER_HOME:-}" ]] || exit 93
printf 'fixture' > "$FIXTURE_HOME/Library/Preferences/$WATTSON_TEST_DEFAULTS_SUITE.plist"
printf '%s\n%s\n' "$WATTSON_TEST_DEFAULTS_SUITE" "$$" > "$FIXTURE_ROOT/ready"
printf '{"iterations":%s}\n' "$1"
if [[ "${PROBE_WAIT:-0}" == 1 ]]; then
    trap '' TERM
    while true; do sleep 0.05; done
fi
exit "${PROBE_STATUS:-0}"
''')
        self.env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ["PATH"],
                        FIXTURE_ROOT=str(self.root), FIXTURE_HOME=str(self.root / "fixture-home"),
                        STUB_BIN=str(self.bin))

    def stub(self, name, body):
        path = self.bin / name
        path.write_text("#!/bin/bash\nset -euo pipefail\n" + body)
        path.chmod(0o755)

    def invoke(self, *arguments, **environment):
        return run(["/bin/bash", str(self.script), *arguments],
                   env=dict(self.env, **environment), capture_output=True, text=True,
                   timeout=10, cleanup_grace=65)

    def assert_clean(self, executed=True):
        binary = pathlib.Path((self.root / "binary").read_text().strip())
        self.assertFalse(binary.parent.exists())
        self.assertEqual(list((self.root / ".build/renderers.noindex").iterdir()), [])
        self.assertEqual(self.sentinel.read_text(), "preserved")
        self.assertEqual(list(self.preferences.iterdir()), [self.sentinel])
        if executed:
            domain, pid = (self.root / "ready").read_text().splitlines()
            self.assertRegex(domain, r"^Wattson\.Performance\.[0-9A-F-]{36}$")
            self.assertIn(domain, (self.root / "deleted").read_text().splitlines())
            state = run(["/bin/ps", "-p", pid, "-o", "stat="],
                        capture_output=True, text=True).stdout.strip()
            self.assertTrue(not state or state.startswith("Z"), state)

    def test_default_compile_only_and_failed_compilation_clean_scratch(self):
        for code in (0, 9):
            with self.subTest(code=code):
                result = self.invoke(COMPILE_STATUS=str(code))
                self.assertEqual(result.returncode, code, result.stderr)
                if not code:
                    self.assertIn("RENDERERS_COMPILE_OK", result.stdout)
                self.assertFalse((self.root / "ready").exists())
                self.assert_clean(executed=False)

    def test_success_and_failure_preserve_output_and_clean_preferences(self):
        for code in (0, 7):
            with self.subTest(code=code):
                result = self.invoke("--run-gui", "500", PROBE_STATUS=str(code))
                self.assertEqual(result.returncode, code, result.stderr)
                self.assertEqual(result.stdout.strip(), '{"iterations":500}')
                self.assert_clean()

    def test_timeout_stops_process_before_cleaning_preferences(self):
        result = self.invoke("--run-gui", PROBE_WAIT="1")
        self.assertEqual(result.returncode, 124, result.stderr)
        self.assert_clean()

    def test_term_stops_process_before_cleaning_preferences(self):
        process = subprocess.Popen(["/bin/bash", str(self.script), "--run-gui"],
                                   env=dict(self.env, PROBE_WAIT="1"), start_new_session=True,
                                   text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        process.cleanup_grace = 65
        self.workspace.processes.append(process)
        self.addCleanup(process.stdout.close)
        self.addCleanup(process.stderr.close)
        deadline = time.monotonic() + 5
        while not (self.root / "ready").exists() and process.poll() is None:
            self.assertLess(time.monotonic(), deadline)
            time.sleep(0.01)
        self.assertTrue((self.root / "ready").exists())
        process.send_signal(signal.SIGTERM)
        stdout, stderr = process.communicate(timeout=10)
        self.assertEqual(process.returncode, 143, stdout + stderr)
        self.assert_clean()

    @unittest.skipUnless(shutil.which("xcrun"), "requires macOS Swift")
    def test_real_harness_rejects_unmanaged_invocation_before_appkit_or_preferences(self):
        source = (ROOT / "tests/performance/main.swift").read_text()
        source = source.split("_ = NSApplication.shared", 1)[0].replace("import AppKit\n", "")
        source += '\nprint("MANAGED")\n'
        main = self.root / "main.swift"
        main.write_text(source)
        probe = self.root / "guard-probe"
        result = run(["xcrun", "swiftc", str(main), "-o", str(probe)],
                     capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        for suite in (None, "com.leoarrow.wattson", "Wattson.Performance.invalid"):
            with self.subTest(suite=suite):
                assignment = (["-u", "WATTSON_TEST_DEFAULTS_SUITE"] if suite is None else
                              ["WATTSON_TEST_DEFAULTS_SUITE=" + suite])
                result = run(["/usr/bin/env", *assignment, str(probe)],
                             capture_output=True, text=True)
                self.assertEqual(result.returncode, 1, result.stderr)
                self.assertNotIn("MANAGED", result.stdout)
                self.assertIn("scripts/measure_renderers.sh --run-gui", result.stderr)
        result = run(["/usr/bin/env",
                      "WATTSON_TEST_DEFAULTS_SUITE=Wattson.Performance.00000000-0000-0000-0000-000000000000",
                      str(probe)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "MANAGED")


if __name__ == "__main__":
    unittest.main()
