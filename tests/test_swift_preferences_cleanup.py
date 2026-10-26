import json
import os
import pathlib
import plistlib
import pwd
import shutil
import time
import unittest
import uuid

from local_runtime import TemporaryDirectory, run


ROOT = pathlib.Path(__file__).resolve().parents[1]
HELPER = ROOT / "SwiftTests" / "TestDefaultsCleanup.swift"
REAL_PREFERENCES = pathlib.Path(pwd.getpwuid(os.getuid()).pw_dir) / "Library/Preferences"


@unittest.skipUnless(shutil.which("xcrun"), "requires macOS Swift")
class SwiftPreferencesCleanupTests(unittest.TestCase):
    def setUp(self):
        self.workspace = TemporaryDirectory(prefix="swift-preferences-")
        self.addCleanup(self.workspace.cleanup)
        self.root = pathlib.Path(self.workspace.name)
        self.domain = "Wattson.SwiftTests.PythonProbe." + str(uuid.uuid4()).upper()
        # The outer fixture also owns this exact domain if the unittest process
        # is interrupted before it can make its assertions.
        self.workspace.defaults_suite = self.domain
        self.preference = REAL_PREFERENCES / (self.domain + ".plist")
        self.manifest = self.root / "manifest"
        self.manifest.mkdir()
        self.environment = dict(os.environ, WATTSON_TEST_DEFAULTS_MANIFEST=str(self.manifest))

    def compile_probe(self, command=None):
        # Compile the production test helper's actual functions. Replace only
        # XCTest's reporting adapter so this probe can run without a test host.
        source = HELPER.read_text().split("final class TestDefaultsCleanupTests:", 1)[0]
        source = source.replace("import XCTest", '''
var cleanupErrors: [String] = []
func XCTFail(_ message: String, file: StaticString = #filePath, line: UInt = #line) {
    cleanupErrors.append(message)
}
''')
        if command is not None:
            original = 'deletion.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")'
            self.assertEqual(source.count(original), 1)
            source = source.replace(original, "deletion.executableURL = URL(fileURLWithPath: "
                                    + json.dumps(str(command), ensure_ascii=False) + ")")
        source += '''
let mode = CommandLine.arguments[1]
let suite = CommandLine.arguments[2]
let preference = testPreferencesFile(for: suite)
var observed: [String: Any] = [
    "foundationHome": FileManager.default.homeDirectoryForCurrentUser.path,
    "realPreference": preference.path,
]
if mode == "write-clean" {
    _ = registerTestDefaultsSuite(suite)
    let marker = URL(fileURLWithPath: ProcessInfo.processInfo.environment["WATTSON_TEST_DEFAULTS_MANIFEST"]!)
        .appendingPathComponent(suite)
    observed["registeredBeforeWrite"] = FileManager.default.fileExists(atPath: marker.path)
    observed["existedBeforeWrite"] = FileManager.default.fileExists(atPath: preference.path)
    let defaults = UserDefaults(suiteName: suite)!
    defaults.set("fixture", forKey: "probe")
    precondition(defaults.synchronize())
    observed["persistedBeforeCleanup"] = FileManager.default.fileExists(atPath: preference.path)
    defaults.removePersistentTestDomain(forName: suite)
    observed["existsAfterCleanup"] = FileManager.default.fileExists(atPath: preference.path)
} else if mode == "read" {
    let defaults = UserDefaults(suiteName: suite)!
    observed["probeIsAbsent"] = defaults.object(forKey: "probe") == nil
    precondition(defaults.synchronize())
} else if mode == "reject" {
    // Construct only the caller-owned sentinel, never production defaults.
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentTestDomain(forName: CommandLine.arguments[3])
} else if mode == "register-write" {
    _ = registerTestDefaultsSuite(suite)
    try! Data().write(to: URL(fileURLWithPath: CommandLine.arguments[3]))
    let defaults = UserDefaults(suiteName: suite)!
    defaults.set("fixture", forKey: "probe")
    precondition(defaults.synchronize())
}
observed["errors"] = cleanupErrors
let encoded = try! JSONSerialization.data(withJSONObject: observed, options: [.sortedKeys])
print(String(decoding: encoded, as: UTF8.self))
'''
        main = self.root / "main.swift"
        main.write_text(source)
        binary = self.root / "probe"
        compiled = run(["xcrun", "swiftc", str(main), "-o", str(binary)],
                       capture_output=True, text=True)
        self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
        return binary

    def probe(self, binary, mode="write-clean", *, redirected=True, extra=(), environment=None):
        command = [str(binary), mode, self.domain, *extra]
        if not redirected:
            command = ["/usr/bin/env", "-u", "CFFIXED_USER_HOME", *command]
        result = run(command, env=environment or self.environment,
                     capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return json.loads(result.stdout)

    def test_normal_and_redirected_homes_clean_real_preferences_after_process_exit(self):
        binary = self.compile_probe()
        for redirected in (False, True, True):
            with self.subTest(redirected=redirected):
                observed = self.probe(binary, redirected=redirected)
                self.assertEqual(observed["realPreference"], str(self.preference))
                self.assertEqual(observed["foundationHome"] != str(REAL_PREFERENCES.parent.parent),
                                 redirected)
                self.assertTrue(observed["registeredBeforeWrite"])
                self.assertFalse(observed["existedBeforeWrite"])
                self.assertTrue(observed["persistedBeforeCleanup"])
                self.assertFalse(observed["existsAfterCleanup"])
                self.assertEqual(observed["errors"], [])
                self.assertFalse(self.preference.exists())
                self.assertEqual([p.name for p in self.manifest.iterdir()], [self.domain])
                # Reopen in fresh processes: assertions in the writer's process
                # alone cannot reveal a late daemon or process-exit writeback.
                for _ in range(3):
                    reread = self.probe(binary, "read", redirected=redirected)
                    self.assertTrue(reread["probeIsAbsent"])
                    time.sleep(0.1)
                    self.assertFalse(self.preference.exists())

    def defaults_stub(self, body):
        path = self.root / "defaults-stub"
        path.write_text("#!/usr/bin/python3\nimport json, os, pathlib, signal, sys, time\n"
                        "pathlib.Path(os.environ['DEFAULTS_OBSERVATION']).write_text(json.dumps({"
                        "'pid': os.getpid(), 'fixed_home': os.environ.get('CFFIXED_USER_HOME'),"
                        "'locale': os.environ.get('LC_ALL')}))\n" + body)
        path.chmod(0o755)
        marker = self.root / "defaults-observation.json"
        return path, marker, dict(self.environment, DEFAULTS_OBSERVATION=str(marker), LC_ALL="fr_FR.UTF-8")

    def test_missing_or_invalid_manifest_exits_before_preferences_write(self):
        binary = self.compile_probe()
        reached_user_defaults = self.root / "reached-user-defaults"
        manifest_file = self.root / "manifest-file"
        manifest_file.write_text("caller-owned")
        manifest_link = self.root / "manifest-link"
        manifest_link.symlink_to(self.manifest, target_is_directory=True)
        missing_directory = self.root / "missing-manifest"
        cases = (
            (None, "Run tests with bash scripts/test_swift.sh"),
            (manifest_file, "manifest must be an owned directory"),
            (manifest_link, "manifest must be an owned directory"),
            (missing_directory, "Could not register test preferences"),
        )
        for manifest, message in cases:
            with self.subTest(manifest=manifest):
                environment = dict(self.environment)
                environment.pop("WATTSON_TEST_DEFAULTS_MANIFEST")
                if manifest is not None:
                    environment["WATTSON_TEST_DEFAULTS_MANIFEST"] = str(manifest)
                result = run([str(binary), "register-write", self.domain, str(reached_user_defaults)],
                             env=environment, capture_output=True, text=True, timeout=10)
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertIn(message, result.stderr)
                self.assertFalse(reached_user_defaults.exists())
                self.assertFalse(self.preference.exists())
                self.assertEqual(list(self.manifest.iterdir()), [])
                self.assertEqual(manifest_file.read_text(), "caller-owned")
                self.assertTrue(manifest_link.is_symlink())
                self.assertFalse(missing_directory.exists())

    def test_defaults_child_does_not_inherit_redirected_home(self):
        command, marker, environment = self.defaults_stub(
            "os.execv('/usr/bin/defaults', ['defaults', *sys.argv[1:]])\n")
        observed = self.probe(self.compile_probe(command), environment=environment)
        child = json.loads(marker.read_text())
        self.assertIsNone(child["fixed_home"])
        self.assertEqual(child["locale"], "C")
        self.assertEqual(observed["errors"], [])
        self.assertFalse(self.preference.exists())

    def test_command_failure_reports_error_and_still_removes_real_plist(self):
        command, _, environment = self.defaults_stub(
            "sys.stderr.write('échec simulé du service\\n')\nsys.exit(9)\n")
        observed = self.probe(self.compile_probe(command), environment=environment)
        self.assertTrue(observed["persistedBeforeCleanup"])
        self.assertTrue(any("Could not delete test domain" in error for error in observed["errors"]))
        self.assertFalse(observed["existsAfterCleanup"])
        self.assertFalse(self.preference.exists())

    def test_command_timeout_reaps_child_and_still_removes_real_plist(self):
        command, marker, environment = self.defaults_stub(
            "signal.signal(signal.SIGTERM, signal.SIG_IGN)\nwhile True: time.sleep(0.1)\n")
        observed = self.probe(self.compile_probe(command), environment=environment)
        self.assertTrue(any("Timed out deleting test domain" in error for error in observed["errors"]))
        self.assertFalse(observed["existsAfterCleanup"])
        self.assertFalse(self.preference.exists())
        pid = json.loads(marker.read_text())["pid"]
        state = run(["/bin/ps", "-p", str(pid), "-o", "stat="],
                    capture_output=True, text=True).stdout.strip()
        self.assertTrue(not state or state.startswith("Z"), state)

    def test_command_start_failure_still_removes_real_plist(self):
        observed = self.probe(self.compile_probe(self.root / "absent-command"))
        self.assertTrue(any("Could not delete test domain through cfprefsd" in error
                            for error in observed["errors"]))
        self.assertFalse(observed["existsAfterCleanup"])
        self.assertFalse(self.preference.exists())

    def test_invalid_and_production_names_preserve_caller_owned_sentinel(self):
        self.domain = "Wattson.CleanupSentinel." + str(uuid.uuid4()).upper()
        self.workspace.defaults_suite = self.domain
        self.preference = REAL_PREFERENCES / (self.domain + ".plist")
        sentinel = plistlib.dumps({"keep": "caller-owned"})
        self.preference.write_bytes(sentinel)
        binary = self.compile_probe()
        for rejected in (self.domain, "com.leoarrow.wattson"):
            with self.subTest(rejected=rejected):
                observed = self.probe(binary, "reject", extra=(rejected,))
                self.assertTrue(any("Refusing to remove a non-test" in error for error in observed["errors"]))
                self.assertEqual(self.preference.read_bytes(), sentinel)
                self.assertEqual(list(self.manifest.iterdir()), [])

    def test_performance_helper_cleans_real_preferences_with_redirected_home(self):
        self.domain = "Wattson.Performance." + str(uuid.uuid4()).upper()
        self.workspace.defaults_suite = self.domain
        self.preference = REAL_PREFERENCES / (self.domain + ".plist")
        # Extract only the real cleanup function, before the AppKit benchmark.
        source = (ROOT / "tests/performance/main.swift").read_text()
        source = source.split("// Controlled production-renderer", 1)[0]
        source = source.replace("import AppKit\n", "")
        source += '''
let suite = CommandLine.arguments[2]
let preference = CommandLine.arguments[3]
let defaults = UserDefaults(suiteName: suite)!
defaults.set("fixture", forKey: "probe")
precondition(defaults.synchronize())
let before = FileManager.default.fileExists(atPath: preference)
let cleaned = cleanupPerformanceDefaults(defaults, suite: suite)
let observed: [String: Any] = [
    "foundationHome": FileManager.default.homeDirectoryForCurrentUser.path,
    "persistedBeforeCleanup": before,
    "cleaned": cleaned,
    "existsAfterCleanup": FileManager.default.fileExists(atPath: preference),
]
print(String(decoding: try! JSONSerialization.data(withJSONObject: observed), as: UTF8.self))
'''
        main = self.root / "main.swift"
        main.write_text(source)
        binary = self.root / "probe"
        compiled = run(["xcrun", "swiftc", str(main), "-o", str(binary)],
                       capture_output=True, text=True)
        self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
        observed = self.probe(binary, extra=(str(self.preference),))
        self.assertNotEqual(observed["foundationHome"], str(REAL_PREFERENCES.parent.parent))
        self.assertTrue(observed["persistedBeforeCleanup"])
        self.assertTrue(observed["cleaned"])
        self.assertFalse(observed["existsAfterCleanup"])
        self.assertFalse(self.preference.exists())


if __name__ == "__main__":
    unittest.main()
