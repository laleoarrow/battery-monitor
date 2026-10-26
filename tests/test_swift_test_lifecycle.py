import json
import os
import pathlib
import pwd
import shutil
import signal
import subprocess
import time
import unittest
import uuid

from local_runtime import TemporaryDirectory, run


ROOT = pathlib.Path(__file__).resolve().parents[1]
PREFERENCES = pathlib.Path(pwd.getpwuid(os.getuid()).pw_dir) / "Library/Preferences"


@unittest.skipUnless(shutil.which("xcrun"), "requires macOS Foundation")
class SwiftTestLifecycleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.compilation = TemporaryDirectory(prefix="swift-owner-probe-")
        cls.addClassCleanup(cls.compilation.cleanup)
        source = pathlib.Path(cls.compilation.name) / "main.swift"
        source.write_text('''import Foundation
import Darwin
let environment = ProcessInfo.processInfo.environment
let suite = environment["PROBE_DOMAIN"]!
let manifest = URL(fileURLWithPath: environment["WATTSON_TEST_DEFAULTS_MANIFEST"]!)
try Data().write(to: manifest.appendingPathComponent(suite), options: .atomic)
if environment["PROBE_INVALID_MARKER"] == "1" {
    try Data().write(to: manifest.appendingPathComponent("com.leoarrow.wattson"))
}
if let target = environment["PROBE_LINK_TARGET"] {
    try FileManager.default.createSymbolicLink(
        atPath: manifest.appendingPathComponent("Wattson.SwiftTests.Link.00000000-0000-0000-0000-000000000000").path,
        withDestinationPath: target)
}
let defaults = UserDefaults(suiteName: suite)!
defaults.set("fixture", forKey: "probe")
precondition(defaults.synchronize())
let ready: [String: Any] = ["pid": getpid(), "manifest": manifest.path,
                          "redirectedHome": environment["CFFIXED_USER_HOME"] != nil]
try JSONSerialization.data(withJSONObject: ready).write(
    to: URL(fileURLWithPath: environment["PROBE_READY"]!), options: .atomic)
if environment["PROBE_WAIT"] == "1" {
    signal(SIGTERM, SIG_IGN)
    while true { usleep(20_000) }
}
// Deliberately omit any teardown. The parent owns process-exit cleanup.
exit(Int32(environment["PROBE_EXIT"] ?? "0")!)
''')
        cls.probe = source.parent / "probe"
        result = run(["xcrun", "swiftc", str(source), "-o", str(cls.probe)],
                     capture_output=True, text=True)
        if result.returncode:
            raise RuntimeError(result.stdout + result.stderr)

    def setUp(self):
        self.workspace = TemporaryDirectory(prefix="swift-owner-")
        self.addCleanup(self.workspace.cleanup)
        self.root = pathlib.Path(self.workspace.name)
        (self.root / "scripts").mkdir()
        shutil.copytree(ROOT / "scripts/lib", self.root / "scripts/lib")
        self.script = self.root / "scripts/test_swift.sh"
        shutil.copy2(ROOT / "scripts/test_swift.sh", self.script)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        swift = self.bin / "swift"
        swift.write_text('#!/bin/bash\n[[ "$1" == test ]] || exit 90\n'
                         'printf "%s\\n" "$*" > "$PROBE_ARGUMENTS"\nexec "$PROBE_BINARY"\n')
        swift.chmod(0o755)
        self.environment = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ["PATH"],
                                PROBE_BINARY=str(self.probe),
                                PROBE_ARGUMENTS=str(self.root / "arguments"),
                                CFFIXED_USER_HOME=str(self.root / "redirected-home"))
        self.domains = []
        self.addCleanup(self.remove_probe_domains)

    def remove_probe_domains(self):
        # A failed assertion must not leave this regression's own probe behind.
        for domain in self.domains:
            subprocess.run(["/usr/bin/env", "-u", "CFFIXED_USER_HOME", "/usr/bin/defaults", "delete", domain],
                           capture_output=True, timeout=5)
            (PREFERENCES / (domain + ".plist")).unlink(missing_ok=True)

    def invocation(self, **overrides):
        domain = "Wattson.SwiftTests.ParentProbe." + str(uuid.uuid4()).upper()
        self.domains.append(domain)
        ready = self.root / (domain + ".json")
        environment = dict(self.environment, PROBE_DOMAIN=domain, PROBE_READY=str(ready), **overrides)
        return domain, ready, environment

    def start(self, environment):
        process = subprocess.Popen(["/bin/bash", str(self.script), "--skip-build", "--filter", "Probe"],
                                   env=environment, start_new_session=True, text=True,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        process.cleanup_grace = 65
        self.workspace.processes.append(process)
        self.addCleanup(process.stdout.close)
        self.addCleanup(process.stderr.close)
        return process

    def ready(self, path, process):
        deadline = time.monotonic() + 10
        while not path.exists() and process.poll() is None:
            self.assertLess(time.monotonic(), deadline, "Swift preference probe did not start")
            time.sleep(0.02)
        self.assertTrue(path.exists())
        record = json.loads(path.read_text())
        self.assertFalse(record["redirectedHome"])
        return record

    def assert_clean(self, domain, record):
        preference = PREFERENCES / (domain + ".plist")
        self.assertFalse(preference.exists(), str(preference))
        result = run(["/usr/bin/env", "-u", "CFFIXED_USER_HOME", "/usr/bin/defaults", "read", domain],
                     capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(preference.exists())
        self.assertFalse(pathlib.Path(record["manifest"]).parent.exists())
        state = run(["/bin/ps", "-p", str(record["pid"]), "-o", "stat="],
                    capture_output=True, text=True).stdout.strip()
        self.assertTrue(not state or state.startswith("Z"), state)

    def test_normal_and_failed_exit_clean_real_preferences_without_teardown(self):
        for code in (0, 7, 0):
            with self.subTest(code=code):
                domain, ready, environment = self.invocation(PROBE_EXIT=str(code))
                result = run(["/bin/bash", str(self.script), "--skip-build", "--filter", "Probe"],
                             env=environment, capture_output=True, text=True, timeout=10, cleanup_grace=65)
                self.assertEqual(result.returncode, code, result.stderr)
                self.assertIn("SWIFT_TEST_DEFAULTS_CLEANUP registered=1 remaining=0", result.stdout)
                record = json.loads(ready.read_text())
                self.assertFalse(record["redirectedHome"])
                self.assertEqual((self.root / "arguments").read_text().strip(), "test --skip-build --filter Probe")
                self.assert_clean(domain, record)

    def test_timeout_stops_test_then_cleans_its_preferences(self):
        domain, ready, environment = self.invocation(PROBE_WAIT="1", WATTSON_SWIFT_TEST_TIMEOUT="0.5")
        result = run(["/bin/bash", str(self.script)], env=environment,
                     capture_output=True, text=True, timeout=10, cleanup_grace=65)
        self.assertEqual(result.returncode, 124, result.stderr)
        self.assertIn("SWIFT_TEST_DEFAULTS_CLEANUP registered=1 remaining=0", result.stdout)
        self.assert_clean(domain, json.loads(ready.read_text()))

    def test_parent_hup_int_and_term_cleanup_after_owned_process_stops(self):
        for caught in (signal.SIGHUP, signal.SIGINT, signal.SIGTERM):
            with self.subTest(signal=caught):
                domain, ready, environment = self.invocation(PROBE_WAIT="1")
                process = self.start(environment)
                record = self.ready(ready, process)
                self.assertTrue((PREFERENCES / (domain + ".plist")).exists())
                process.send_signal(caught)
                stdout, stderr = process.communicate(timeout=10)
                self.assertEqual(process.returncode, 128 + caught, stdout + stderr)
                self.assertIn("SWIFT_TEST_DEFAULTS_CLEANUP registered=1 remaining=0", stdout)
                self.assert_clean(domain, record)

    def test_concurrent_run_and_preexisting_sentinel_are_not_cleaned_by_another_run(self):
        sentinel = self.workspace.defaults_suite
        run(["/usr/bin/env", "-u", "CFFIXED_USER_HOME", "/usr/bin/defaults", "write", sentinel,
             "sentinel", "-string", "preserved"], check=True, capture_output=True)
        domain_b, ready_b, environment_b = self.invocation(PROBE_WAIT="1")
        process_b = self.start(environment_b)
        record_b = self.ready(ready_b, process_b)
        domain_a, ready_a, environment_a = self.invocation(PROBE_EXIT="7")
        result = run(["/bin/bash", str(self.script)], env=environment_a,
                     capture_output=True, text=True, timeout=10, cleanup_grace=65)
        self.assertEqual(result.returncode, 7, result.stderr)
        self.assert_clean(domain_a, json.loads(ready_a.read_text()))
        self.assertIsNone(process_b.poll())
        self.assertTrue((PREFERENCES / (domain_b + ".plist")).exists())
        preserved = run(["/usr/bin/env", "-u", "CFFIXED_USER_HOME", "/usr/bin/defaults", "read", sentinel, "sentinel"],
                        check=True, capture_output=True, text=True)
        self.assertEqual(preserved.stdout.strip(), "preserved")
        process_b.send_signal(signal.SIGTERM)
        process_b.communicate(timeout=10)
        self.assertEqual(process_b.returncode, 143)
        self.assert_clean(domain_b, record_b)

    def test_manifest_rejects_non_test_names_and_symlinks_without_touching_target(self):
        target = self.root / "caller-owned"
        target.write_text("preserved")
        for code in (0, 7):
            with self.subTest(code=code):
                domain, ready, environment = self.invocation(
                    PROBE_EXIT=str(code), PROBE_INVALID_MARKER="1", PROBE_LINK_TARGET=str(target))
                result = run(["/bin/bash", str(self.script)], env=environment,
                             capture_output=True, text=True, timeout=10, cleanup_grace=65)
                self.assertEqual(result.returncode, code or 1, result.stderr)
                self.assertIn("refused an invalid test defaults marker", result.stderr)
                self.assertEqual(target.read_text(), "preserved")
                self.assert_clean(domain, json.loads(ready.read_text()))

    def test_unreadable_manifest_makes_successful_command_fail_cleanup(self):
        manifest = self.root / "unreadable-manifest"
        manifest.mkdir()
        manifest.chmod(0)
        try:
            result = run(["/bin/bash", "-c",
                          'source "$1"; wattson_cleanup_init; '
                          'wattson_cleanup_add_defaults_manifest "$2"; exit 0',
                          "bash", str(self.root / "scripts/lib/local_cleanup.sh"), str(manifest)],
                         capture_output=True, text=True)
            self.assertEqual(result.returncode, 1, result.stderr)
            self.assertIn("refused an invalid test defaults manifest", result.stderr)
        finally:
            manifest.chmod(0o700)


if __name__ == "__main__":
    unittest.main()
