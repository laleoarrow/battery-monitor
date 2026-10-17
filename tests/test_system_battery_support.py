import hashlib
import json
import os
import pathlib
import shlex
import shutil
import signal
import subprocess
import sys
import time
import unittest
import zipfile

from local_runtime import ROOT, TemporaryDirectory, run


SUPPORT = ROOT / "Support" / "SystemBatteryIcon"
COMMAND = "Collect-Wattson-SystemBatteryIcon.command"
REPORT_ROOT = "Wattson-SystemBatteryIcon"
ARCHIVE_ROOT = "Wattson-SystemBatteryIcon-Support"


@unittest.skipUnless(pathlib.Path("/usr/bin/ditto").exists(), "macOS archive tooling required")
class SystemBatterySupportLifecycleTests(unittest.TestCase):
    def setUp(self):
        self.directory = TemporaryDirectory(prefix="system-battery-support-")
        self.addCleanup(self.directory.cleanup)
        self.work = pathlib.Path(self.directory.name)
        self.bundle = self.work / "Support" / "SystemBatteryIcon"
        shutil.copytree(SUPPORT, self.bundle)
        self.output = self.work / "output"
        self.native_tmp = self.work / "native-tmp.noindex"
        self.native_tmp.mkdir()
        self.environment = dict(os.environ, TMPDIR=str(self.native_tmp))
        self.mock = self.work / "mock"
        self.mock.mkdir()
        self.make_mock("swvers", "echo 26.0\n")
        self.make_mock("uname", "echo arm64\n")
        self.make_mock("codesign", "exit 0\n")
        self.make_mock("perl", "printf '{\"operation\":\"%s\",\"status\":\"ok\",\"durationMs\":1,\"response\":{}}\\n' \"$2\"\n")
        self.make_snapshot_mock()
        self.script = self.bundle / COMMAND
        source = self.script.read_text()
        for original, replacement in {
            "/usr/bin/sw_vers": "swvers", "/usr/bin/uname": "uname",
            "/usr/bin/codesign": "codesign", "/usr/bin/perl": "perl",
            "/usr/bin/osascript": "osascript",
        }.items():
            source = source.replace(original, str(self.mock / replacement))
        self.script.write_text(source)

    def make_mock(self, name, body):
        path = self.mock / name
        path.write_text("#!/bin/bash\n" + body)
        path.chmod(0o755)
        return path

    def make_snapshot_mock(self):
        path = self.mock / "osascript"
        path.write_text(f"#!{sys.executable}\n" + '''import json, pathlib, sys
assert sys.argv[4] == "snapshot"
scratch = pathlib.Path(sys.argv[5])
result = {"fixture": True}
for key in ["health", "batteryIcon"]:
    text = (scratch / (key + ".raw")).read_text().strip()
    try:
        result[key] = json.loads(text)
    except ValueError:
        result[key] = text
print(json.dumps(result))
''')
        path.chmod(0o755)

    def run_command(self, arguments=None):
        return run(["/bin/bash", str(self.script), "--output", str(self.output)]
                   + (arguments or []), capture_output=True, text=True, timeout=15,
                   cleanup_grace=65, env=self.environment)

    def assert_clean(self, existing_root=False):
        scratch_root = self.native_tmp / (REPORT_ROOT + ".noindex")
        if existing_root:
            self.assertEqual(sorted(item.name for item in scratch_root.iterdir()), ["caller-owned.txt"])
            self.assertEqual((scratch_root / "caller-owned.txt").read_text(), "preserve")
        else:
            self.assertFalse(scratch_root.exists())
        self.assertFalse(list(self.output.glob("*.partial.noindex")))

    def read_report(self):
        archives = list(self.output.glob("*.zip"))
        self.assertEqual(len(archives), 1)
        self.assertRegex(archives[0].name, r"^Wattson-SystemBatteryIcon-\d{8}T\d{6}Z-\d+\.zip$")
        with zipfile.ZipFile(archives[0]) as archive:
            names = {item for item in archive.namelist() if not item.endswith("/")}
            self.assertEqual(names, {REPORT_ROOT + "/environment.json", REPORT_ROOT + "/README.txt"})
            return json.loads(archive.read(REPORT_ROOT + "/environment.json"))

    def test_success_packages_only_reviewable_report_and_cleans_scratch(self):
        result = self.run_command()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(self.read_report()["fixture"])
        self.assert_clean()

    def test_collector_also_runs_from_its_directory_without_a_path_prefix(self):
        result = run(["/bin/bash", COMMAND, "--output", str(self.output)],
                     cwd=self.bundle, capture_output=True, text=True, timeout=15,
                     cleanup_grace=65, env=self.environment)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(self.read_report()["fixture"])
        self.assert_clean()

    def test_line_break_paths_fail_before_touching_unrelated_prefix(self):
        for location in ("temporary", "output", "working-directory", "support-directory"):
            for separator in ("\n", "\r"):
                with self.subTest(location=location, separator=repr(separator)):
                    case = self.work / (location + ("-lf" if separator == "\n" else "-cr"))
                    case.mkdir()
                    unrelated = case / "unrelated"
                    unrelated.mkdir()
                    sentinel = unrelated / "caller-owned.txt"
                    sentinel.write_text("must remain byte-for-byte")
                    unusual = case / ("unrelated" + separator + "suffix")
                    unusual.mkdir()
                    script = self.script
                    output = case / "output"
                    environment = dict(self.environment)
                    cwd = None
                    if location == "temporary":
                        environment["TMPDIR"] = str(unusual)
                    elif location == "output":
                        output = unusual
                    elif location == "working-directory":
                        cwd, output = unusual, pathlib.Path(".")
                    else:
                        shutil.copytree(self.bundle, unusual / "bundle")
                        script = unusual / "bundle" / COMMAND
                    result = run(["/bin/bash", str(script), "--output", str(output)],
                                 cwd=cwd, env=environment, capture_output=True, text=True,
                                 timeout=15, cleanup_grace=65)
                    self.assertTrue(sentinel.is_file(), "Truncated path cleanup deleted unrelated caller data")
                    self.assertEqual(sentinel.read_text(), "must remain byte-for-byte")
                    self.assertNotEqual(result.returncode, 0, "Unsupported line-break path must fail closed")
                    self.assertEqual(sorted(p.name for p in unrelated.iterdir()), ["caller-owned.txt"])
                    self.assertEqual(list(unusual.iterdir()), [] if location != "support-directory" else [unusual / "bundle"])
                    self.assertFalse(list((cwd or output).glob("*.zip")))
                    self.assertFalse(list(self.native_tmp.glob("Wattson-SystemBatteryIcon.noindex")))

    def test_line_break_temporary_path_preserves_prefix_on_early_failure_and_signal(self):
        for scenario in ("output-mkdir-failure", "TERM"):
            with self.subTest(scenario=scenario):
                case = self.work / scenario
                case.mkdir()
                unrelated = case / "unrelated"
                unrelated.mkdir()
                sentinel = unrelated / "caller-owned.txt"
                sentinel.write_text("preserve")
                unusual = case / "unrelated\nsuffix"
                unusual.mkdir()
                if scenario == "TERM":
                    result = run(["/bin/bash", "-c",
                        'set -eu; source "$1"; support_begin "$2"; kill -TERM $$',
                        "newline-signal", str(self.bundle / "lifecycle.sh"),
                        str(unusual / (REPORT_ROOT + ".noindex"))],
                        capture_output=True, text=True, timeout=5, cleanup_grace=65)
                else:
                    output_parent = case / "not-a-directory"
                    output_parent.write_text("caller-owned file")
                    result = run(["/bin/bash", str(self.script), "--output", str(output_parent / "output")],
                        env=dict(self.environment, TMPDIR=str(unusual)), capture_output=True,
                        text=True, timeout=5, cleanup_grace=65)
                    self.assertEqual(output_parent.read_text(), "caller-owned file")
                self.assertNotEqual(result.returncode, 0)
                self.assertTrue(sentinel.is_file(), "Early failure/TERM removed unrelated prefix")
                self.assertEqual(sentinel.read_text(), "preserve")
                self.assertEqual(list(unrelated.iterdir()), [sentinel])
                self.assertEqual(list(unusual.iterdir()), [])

    def test_existing_scratch_root_and_output_files_are_preserved(self):
        scratch_root = self.native_tmp / (REPORT_ROOT + ".noindex")
        scratch_root.mkdir()
        (scratch_root / "caller-owned.txt").write_text("preserve")
        self.output.mkdir()
        sentinel = self.output / "caller-owned.txt"
        sentinel.write_text("preserve")
        result = self.run_command()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(self.read_report()["fixture"])
        self.assertEqual(sentinel.read_text(), "preserve")
        self.assert_clean(existing_root=True)

    def test_snapshot_failure_creates_no_report_and_preserves_output(self):
        self.output.mkdir()
        sentinel = self.output / "caller-owned.txt"
        sentinel.write_text("preserve")
        self.make_mock("osascript", "exit 1\n")
        result = self.run_command()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(sentinel.read_text(), "preserve")
        self.assertFalse(list(self.output.glob("*.zip")))
        self.assert_clean()

    def test_socket_process_failure_is_recorded_without_losing_other_diagnostics(self):
        self.make_mock("perl", "exit 1\n")
        result = self.run_command()
        self.assertEqual(result.returncode, 0, result.stderr)
        report = self.read_report()
        self.assertEqual(report["health"], "unavailable")
        self.assertEqual(report["batteryIcon"], "unavailable")
        self.assert_clean()

    def test_socket_timeout_stops_probe_and_still_creates_report(self):
        marker = self.work / "probe.pid"
        self.make_mock("perl", f'''if [[ "$2" == health ]]; then
    echo $$ > {shlex.quote(str(marker))}
    exec /bin/sleep 30
fi
printf '{{"operation":"%s","status":"ok","durationMs":1,"response":{{}}}}\\n' "$2"
''')
        source = self.script.read_text()
        self.assertIn("run_probe health 6", source)
        self.script.write_text(source.replace("run_probe health 6", "run_probe health 1"))
        result = self.run_command()
        self.assertEqual(result.returncode, 0, result.stderr)
        report = self.read_report()
        self.assertEqual(report["health"], "unavailable")
        self.assertEqual(report["batteryIcon"]["status"], "ok")
        self.assert_child_stopped(marker)
        self.assert_clean()

    def assert_child_stopped(self, marker):
        self.assertTrue(marker.exists())
        with self.assertRaises(ProcessLookupError):
            os.kill(int(marker.read_text()), 0)

    def test_snapshot_timeout_stops_probe_and_creates_no_report(self):
        marker = self.work / "snapshot.pid"
        self.make_mock("osascript", f"echo $$ > {shlex.quote(str(marker))}\nexec /bin/sleep 30\n")
        source = self.script.read_text()
        self.assertIn("run_probe snapshot 10", source)
        self.script.write_text(source.replace("run_probe snapshot 10", "run_probe snapshot 1"))
        result = self.run_command()
        self.assertNotEqual(result.returncode, 0)
        self.assert_child_stopped(marker)
        self.assertFalse(list(self.output.glob("*.zip")))
        self.assert_clean()

    def test_catchable_interruptions_stop_probe_and_remove_owned_scratch(self):
        for number in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
            with self.subTest(signal=number):
                marker = self.work / f"snapshot-{number}.pid"
                self.make_mock("osascript", f"echo $$ > {shlex.quote(str(marker))}\nexec /bin/sleep 30\n")
                process = subprocess.Popen(
                    ["/bin/bash", str(self.script), "--output", str(self.output)],
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                    start_new_session=True, env=self.environment,
                )
                process.cleanup_grace = 65
                self.directory.processes.append(process)
                deadline = time.monotonic() + 5
                while not marker.exists() and time.monotonic() < deadline:
                    time.sleep(0.02)
                self.assertTrue(marker.exists())
                process.send_signal(number)
                process.wait(timeout=5)
                self.assertEqual(process.returncode, 128 + number)
                self.assert_child_stopped(marker)
                self.assertFalse(list(self.output.glob("*.zip")))
                self.assert_clean()

    def test_failed_scratch_allocation_removes_only_new_root(self):
        helper = self.bundle / "lifecycle.sh"
        failed_mktemp = self.make_mock("mktemp", "exit 1\n")
        helper.write_text(helper.read_text().replace("/usr/bin/mktemp", str(failed_mktemp)))
        for existing in (False, True):
            with self.subTest(existing=existing):
                scratch_root = self.work / f"allocation-{existing}.noindex"
                if existing:
                    scratch_root.mkdir()
                    (scratch_root / "caller-owned.txt").write_text("preserve")
                result = run(
                    ["/bin/bash", "-c", 'set -eu; source "$1"; support_begin "$2"',
                     "allocation-test", str(helper), str(scratch_root)],
                    capture_output=True, text=True, timeout=5, cleanup_grace=65,
                )
                self.assertNotEqual(result.returncode, 0)
                if existing:
                    self.assertEqual((scratch_root / "caller-owned.txt").read_text(), "preserve")
                else:
                    self.assertFalse(scratch_root.exists())

    def test_failed_output_copy_removes_partial_and_preserves_caller_file(self):
        self.output.mkdir()
        sentinel = self.output / "caller-owned.txt"
        sentinel.write_text("preserve")
        copy = self.make_mock("cp", '''case "${!#}" in
*.partial.noindex) printf partial > "${!#}"; exit 1 ;;
*) exec /bin/cp "$@" ;;
esac
''')
        self.script.write_text(self.script.read_text().replace("/bin/cp", str(copy)))
        result = self.run_command()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(sentinel.read_text(), "preserve")
        self.assertFalse(list(self.output.glob("*.zip")))
        self.assert_clean()

    def test_blocked_archive_verify_and_output_stages_are_bounded_and_cleaned(self):
        original = self.script.read_text()
        for command in ("/usr/bin/ditto", "/usr/bin/unzip", "/bin/cp", "/usr/bin/cmp", "/bin/mv", "/bin/mkdir"):
            with self.subTest(command=command):
                marker = self.work / "blocked-stage.pid"
                marker.unlink(missing_ok=True)
                blocker = self.make_mock("blocked-stage", f"echo $$ > {shlex.quote(str(marker))}\nexec /bin/sleep 30\n")
                if command == "/bin/cp":
                    blocker = self.make_mock("blocked-stage", f'''case "${{!#}}" in
*.partial.noindex)
    printf partial > "${{!#}}"
    echo $$ > {shlex.quote(str(marker))}
    exec /bin/sleep 30 ;;
*) exec /bin/cp "$@" ;;
esac
''')
                target = f"support_run {command}"
                if command == "/bin/cp":
                    target += ' "$ARCHIVE" "$SUPPORT_OUTPUT_PARTIAL"'
                elif command == "/bin/mkdir":
                    target += ' -p -- "$OUTPUT_DIR"'
                self.assertEqual(original.count(target), 1)
                replacement = target.replace("support_run ", "support_run_for 0.5 ", 1).replace(command, str(blocker), 1)
                self.script.write_text(original.replace(target, replacement, 1))
                # Start the bounded observation at the injected blocked stage,
                # not before all unrelated collector probes and VM tool startup.
                with (self.work / "stage-errors").open("w+") as errors:
                    process = subprocess.Popen(["/bin/bash", str(self.script), "--output", str(self.output)],
                        stdout=subprocess.DEVNULL, stderr=errors, env=self.environment, start_new_session=True)
                    process.cleanup_grace = 65
                    self.directory.processes.append(process)
                    try:
                        ready_deadline = time.monotonic() + 15
                        while not marker.exists() and process.poll() is None and time.monotonic() < ready_deadline:
                            time.sleep(0.02)
                        self.assertTrue(marker.exists(),
                                        f"Blocked stage was never reached (exit={process.poll()}): "
                                        + (self.work / "stage-errors").read_text())
                        # 0.5s stage + independent 5s file cleanup + termination
                        # grace; this does not extend any production deadline.
                        process.wait(timeout=7)
                        errors.seek(0)
                        self.assertEqual(process.returncode, 124, errors.read())
                        self.assert_child_stopped(marker)
                    finally:
                        from local_runtime import _stop
                        _stop(process)
                        self.directory.processes.remove(process)
                self.assertFalse(list(self.output.glob("*.zip")))
                self.assert_clean()

    def prepare_build(self):
        scripts = self.work / "scripts"
        scripts.mkdir()
        script = scripts / "build_system_battery_support.sh"
        shutil.copy2(ROOT / "scripts" / script.name, script)
        return script

    def test_build_retains_auditable_sources_and_manifest_but_cleans_scratch(self):
        script = self.prepare_build()
        result = run(["/bin/bash", str(script)], capture_output=True, text=True,
                     timeout=10, cleanup_grace=65)
        self.assertEqual(result.returncode, 0, result.stderr)
        dist = self.work / "dist" / "support"
        archive_path = dist / "Wattson-SystemBatteryIcon-Support-v1.zip"
        with zipfile.ZipFile(archive_path) as archive:
            names = {item for item in archive.namelist() if not item.endswith("/")}
            self.assertEqual(names, {ARCHIVE_ROOT + "/" + name for name in
                                    [COMMAND, "collect.js", "socket_probe.pl", "lifecycle.sh",
                                     "README.md", "REPORT-README.txt"]})
            item = archive.getinfo(ARCHIVE_ROOT + "/" + COMMAND)
            self.assertTrue((item.external_attr >> 16) & 0o100)
        checksum = (dist / "Wattson-SystemBatteryIcon-Support-v1.sha256").read_text()
        digest = hashlib.sha256(archive_path.read_bytes()).hexdigest()
        self.assertIn(digest, checksum)
        metadata = json.loads((dist / "Wattson-SystemBatteryIcon-Support-v1.metadata.json").read_text())
        self.assertEqual(metadata["sha256"], digest)
        self.assertEqual(metadata["archive"], archive_path.name)
        self.assertEqual(metadata["schema"], 1)
        self.assertEqual(metadata["bundleVersion"], 1)
        self.assertEqual(metadata["files"], {
            name: hashlib.sha256((self.bundle / name).read_bytes()).hexdigest()
            for name in [COMMAND, "collect.js", "socket_probe.pl", "lifecycle.sh", "README.md", "REPORT-README.txt"]
        })
        self.assertEqual({item.name for item in dist.iterdir()}, {
            "Wattson-SystemBatteryIcon-Support-v1." + suffix
            for suffix in ("zip", "sha256", "metadata.json")
        })
        self.assertFalse((self.work / ".build" / "system-battery-support.noindex").exists())

    def test_build_archive_failure_cleans_scratch_and_keeps_existing_distribution(self):
        script = self.prepare_build()
        dist = self.work / "dist" / "support"
        dist.mkdir(parents=True)
        sentinel = dist / "caller-owned.txt"
        sentinel.write_text("preserve")
        ditto = self.make_mock("ditto", "exit 1\n")
        script.write_text(script.read_text().replace("/usr/bin/ditto", str(ditto)))
        result = run(["/bin/bash", str(script)], capture_output=True, text=True,
                     timeout=10, cleanup_grace=65)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(list(dist.iterdir()), [sentinel])
        self.assertEqual(sentinel.read_text(), "preserve")
        self.assertFalse((self.work / ".build" / "system-battery-support.noindex").exists())

    def test_build_interruption_stops_archiver_and_cleans_scratch(self):
        script = self.prepare_build()
        marker = self.work / "archiver.pid"
        ditto = self.make_mock("ditto", f"echo $$ > {shlex.quote(str(marker))}\nexec /bin/sleep 30\n")
        script.write_text(script.read_text().replace("/usr/bin/ditto", str(ditto)))
        process = subprocess.Popen(["/bin/bash", str(script)],
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                   start_new_session=True)
        process.cleanup_grace = 65
        self.directory.processes.append(process)
        deadline = time.monotonic() + 5
        while not marker.exists() and time.monotonic() < deadline:
            time.sleep(0.02)
        self.assertTrue(marker.exists())
        process.send_signal(signal.SIGTERM)
        process.wait(timeout=5)
        self.assertEqual(process.returncode, 143)
        self.assert_child_stopped(marker)
        self.assertFalse((self.work / ".build" / "system-battery-support.noindex").exists())
        self.assertFalse(list((self.work / "dist" / "support").glob("*.zip")))


@unittest.skipUnless(sys.platform == "darwin" and pathlib.Path("/usr/bin/perl").exists(),
                     "macOS Perl support bundle required")
class SystemBatterySupportSocketTests(unittest.TestCase):
    def setUp(self):
        self.directory = TemporaryDirectory(prefix="system-battery-socket-")
        self.addCleanup(self.directory.cleanup)
        self.work = pathlib.Path(self.directory.name)
        self.probe = self.work / "socket_probe.pl"
        source = (SUPPORT / "socket_probe.pl").read_text()
        self.assertIn("'/var/run/wattson-helper.sock'", source)
        # A short relative path avoids Darwin's sockaddr_un path limit while
        # keeping both ends strictly inside the owned test workspace.
        self.probe.write_text(source.replace("'/var/run/wattson-helper.sock'", "'probe.sock'"))

    def sanitize(self, operation, value):
        result = run([
            "/usr/bin/perl", "-e",
            'require $ARGV[0]; local $/; my $bytes = <STDIN>; '
            'print JSON::PP->new->utf8->canonical->encode(sanitize_response($ARGV[1], $bytes));',
            str(self.probe), operation,
        ], input=json.dumps(value), text=True, capture_output=True, timeout=5, check=True)
        return json.loads(result.stdout)

    def test_sanitizer_keeps_only_operation_specific_typed_booleans(self):
        for operation, key in [("health", "health"), ("getSystemBatteryIconHidden", "hidden")]:
            with self.subTest(operation=operation):
                report = self.sanitize(operation, {
                    "ok": True, key: False, "private-path": "/Users/secret-person",
                    "message": "secret-user@example.invalid", "arbitrary": 1,
                })
                self.assertEqual(report, {"status": "success", "response": {"ok": True, key: False}})
                for untyped in (1, 0, "true", "false", None, [], {}):
                    with self.subTest(untyped=untyped):
                        self.assertEqual(self.sanitize(operation, {"ok": True, key: untyped}),
                                         {"status": "invalid-response"})
        for value in ({"ok": 1, "health": True}, [], None, "private-message"):
            self.assertEqual(self.sanitize("health", value), {"status": "invalid-response"})

    def test_error_fields_are_allowlisted_and_unknown_text_is_not_exported(self):
        report = self.sanitize("getSystemBatteryIconHidden", {
            "ok": False, "error": "unknown battery preference", "reason": "preferenceMissing",
            "message": "private-message", "path": "/Users/private-person",
        })
        self.assertEqual(report, {"status": "helper-error", "response": {
            "ok": False, "error": "unknown battery preference", "reason": "preferenceMissing",
        }})
        report = self.sanitize("health", {"ok": False, "error": "/Users/private-person",
                                          "reason": "secret-user@example.invalid"})
        self.assertEqual(report, {"status": "helper-error", "response": {
            "ok": False, "error": "unrecognized-error",
        }})

    def start_server(self, response=b'', hold=False):
        script = self.work / "server.py"
        script.write_text('''import json, pathlib, socket, time
server = socket.socket(socket.AF_UNIX)
server.bind("probe.sock")
server.listen(1)
server.settimeout(5)
pathlib.Path("ready").write_text("ready")
connection, _ = server.accept()
connection.settimeout(5)
request = b""
while not request.endswith(b"\\n"):
    request += connection.recv(4096)
pathlib.Path("request.json").write_bytes(request)
''' + ("time.sleep(20)\n" if hold else f"connection.sendall({response!r})\n") +
                          "connection.close()\nserver.close()\n")
        process = subprocess.Popen([sys.executable, "-B", str(script)], cwd=self.work,
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                   start_new_session=True)
        self.directory.processes.append(process)
        deadline = time.monotonic() + 5
        while not (self.work / "ready").exists() and time.monotonic() < deadline:
            if process.poll() is not None:
                self.fail(f"Fixture socket server exited: {process.returncode}")
            time.sleep(0.02)
        self.assertTrue((self.work / "ready").exists())
        return process

    def run_probe(self, operation="health"):
        result = run(["/usr/bin/perl", str(self.probe), operation], cwd=self.work,
                     capture_output=True, text=True, timeout=7, check=True)
        return json.loads(result.stdout)

    def test_probe_sends_only_fixed_legacy_read_request_and_sanitizes_reply(self):
        self.start_server(b'{"ok":true,"hidden":true,"private":"secret-user"}\n')
        report = self.run_probe("getSystemBatteryIconHidden")
        request = json.loads((self.work / "request.json").read_text())
        self.assertEqual(request, {"op": "getSystemBatteryIconHidden", "_wattsonProtocol": 4})
        self.assertEqual(set(report), {"operation", "status", "durationMs", "budgetMs", "response"})
        self.assertEqual(report["status"], "success")
        self.assertEqual(report["response"], {"ok": True, "hidden": True})
        self.assertEqual(report["budgetMs"], 4000)
        self.assertGreaterEqual(report["durationMs"], 0)
        self.assertNotIn("secret-user", json.dumps(report))

    def test_probe_rejects_oversized_response(self):
        self.start_server(b"x" * 4097)
        report = self.run_probe()
        self.assertEqual(report["status"], "response-too-large")
        self.assertNotIn("response", report)

    def test_probe_rejects_malformed_response_without_exporting_raw_bytes(self):
        self.start_server(b"secret-user@example.invalid\n")
        report = self.run_probe()
        self.assertEqual(report["status"], "invalid-response")
        self.assertNotIn("secret-user", json.dumps(report))

    def test_probe_connection_failure_is_sanitized(self):
        report = self.run_probe()
        self.assertEqual(report["status"], "connection-failed")
        self.assertNotIn("response", report)
        self.assertNotIn(str(self.work), json.dumps(report))

    def test_probe_deadline_includes_unresponsive_server(self):
        self.start_server(hold=True)
        started = time.monotonic()
        report = self.run_probe()
        elapsed = time.monotonic() - started
        self.assertEqual(report["status"], "timeout")
        self.assertGreaterEqual(report["durationMs"], 3500)
        self.assertLess(elapsed, 6)
        self.assertNotIn("response", report)

    def test_mutating_and_arbitrary_operations_are_rejected_before_connect(self):
        for operation in ("setSystemBatteryIconHidden", "setPowerMode", "arbitrary"):
            with self.subTest(operation=operation):
                result = run(["/usr/bin/perl", str(self.probe), operation], cwd=self.work,
                             capture_output=True, text=True, timeout=5)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, "")


@unittest.skipUnless(pathlib.Path("/usr/bin/osascript").exists(), "macOS JXA required")
class SystemBatterySupportSanitizerTests(unittest.TestCase):
    def setUp(self):
        self.directory = TemporaryDirectory(prefix="system-battery-sanitizer-")
        self.addCleanup(self.directory.cleanup)
        self.work = pathlib.Path(self.directory.name)
        self.harness = self.work / "sanitize.js"
        # Override only the copied entrypoint. Fixtures exercise production
        # sanitizer functions without calling snapshot or reading preferences.
        self.harness.write_text((SUPPORT / "collect.js").read_text() + '''
function run(arguments) {
    if (arguments[0] === 'probe') {
        return JSON.stringify(sanitizeProbe(arguments[1], arguments[2]));
    }
    var kind = arguments[1], object = null;
    if (kind === 'reference-absent') {
        var raw = $.CFDictionaryGetValue($.NSDictionary.dictionary, $('absent'));
        object = ObjC.castRefToObject(raw);
    } else if (kind === 'boolean') object = $.NSNumber.numberWithBool(true);
    else if (kind === 'number') object = $.NSNumber.numberWithDouble(Number(arguments[2]));
    else if (kind === 'string') object = $('private-user@example.invalid');
    else if (kind === 'array') object = $(['private-user@example.invalid']);
    else if (kind === 'dictionary') object = $({'private': '/Users/private-person'});
    return JSON.stringify(describePreference(object));
}
''')

    def invoke(self, *arguments):
        result = run(["/usr/bin/osascript", "-l", "JavaScript", str(self.harness), *arguments],
                     capture_output=True, text=True, timeout=10, check=True)
        return json.loads(result.stdout)

    def probe(self, value, operation="health"):
        return self.invoke("probe", operation, json.dumps(value))

    def test_preference_reports_only_type_for_non_numeric_values(self):
        for kind in ("absent", "boolean", "string", "array", "dictionary"):
            with self.subTest(kind=kind):
                self.assertEqual(self.invoke("preference", kind), {
                    "status": "available", "exists": kind != "absent", "type": kind,
                })

    def test_preference_numbers_preserve_value_without_coercing_types(self):
        for value in (0, 1, 8, 24, -1, 0.5):
            with self.subTest(value=value):
                self.assertEqual(self.invoke("preference", "number", str(value)), {
                    "status": "available", "exists": True, "type": "number", "value": value,
                })
        for value in ("NaN", "Infinity", "9007199254740992"):
            with self.subTest(value=value):
                self.assertEqual(self.invoke("preference", "number", value), {
                    "status": "available", "exists": True, "type": "number",
                    "numericValueStatus": "unsupported-range",
                })

    def test_absent_cf_reference_bridge_remains_an_absent_preference(self):
        self.assertEqual(self.invoke("preference", "reference-absent"), {
            "status": "available", "exists": False, "type": "absent",
        })

    def test_probe_output_revalidates_operation_booleans_and_timing(self):
        valid = {"operation": "health", "status": "success", "durationMs": 4,
                 "response": {"ok": True, "health": True, "private": "secret-user"},
                 "private-path": "/Users/private-person"}
        self.assertEqual(self.probe(valid), {"operation": "health", "status": "success",
                                          "durationMs": 4, "budgetMs": 4000,
                                          "response": {"ok": True, "health": True}})
        for duration in (-1, 0.5, 10001, "4", None):
            with self.subTest(duration=duration):
                self.assertNotIn("durationMs", self.probe(dict(valid, durationMs=duration)))
        for response in ({"ok": 1, "health": True}, {"ok": True, "health": 1},
                         {"ok": False, "health": True}, None):
            with self.subTest(response=response):
                result = self.probe(dict(valid, response=response))
                self.assertEqual(result["status"], "invalid-response")
                self.assertNotIn("response", result)
        self.assertEqual(self.probe(dict(valid, operation="getSystemBatteryIconHidden"))["status"],
                         "probe-unavailable")

    def test_probe_error_fields_and_failure_statuses_never_export_raw_content(self):
        error = {"operation": "getSystemBatteryIconHidden", "status": "helper-error", "durationMs": 1,
                 "response": {"ok": False, "error": "unknown battery preference",
                              "reason": "preferenceTypeUnsupported", "private": "secret-user"}}
        report = self.probe(error, "getSystemBatteryIconHidden")
        self.assertEqual(report["response"], {"ok": False, "error": "unknown battery preference",
                                             "reason": "preferenceTypeUnsupported"})
        report = self.probe(dict(error, response={"ok": False, "error": "secret-user",
                                                 "reason": "/Users/private-person"}),
                            "getSystemBatteryIconHidden")
        self.assertEqual(report["response"], {"ok": False, "error": "unrecognized-error"})
        for status in ("timeout", "connection-failed", "invalid-response", "response-too-large", "io-error"):
            with self.subTest(status=status):
                report = self.probe(dict(error, status=status), "getSystemBatteryIconHidden")
                self.assertEqual(report["status"], status)
                self.assertNotIn("response", report)
        self.assertEqual(self.probe(dict(error, status="secret-user"), "getSystemBatteryIconHidden")["status"],
                         "probe-unavailable")
        report = self.invoke("probe", "health", "private-user@example.invalid")
        self.assertEqual(report, {"operation": "health", "budgetMs": 4000, "status": "probe-unavailable"})


if __name__ == "__main__":
    unittest.main()
