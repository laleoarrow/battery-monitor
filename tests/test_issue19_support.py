import json
import os
import pathlib
import shutil
import signal
import subprocess
import tempfile
import time
import unittest
import zipfile


ROOT = pathlib.Path(__file__).resolve().parents[1]
SUPPORT = ROOT / "Support" / "Issue19"


@unittest.skipUnless(pathlib.Path("/usr/bin/osascript").exists(), "macOS JXA required")
class PopupEventSanitizerTests(unittest.TestCase):
    def setUp(self):
        self.scratch_root = ROOT / ".build" / "issue19-support-tests.noindex"
        self.scratch_root.mkdir(parents=True, exist_ok=True)
        self.directory = tempfile.TemporaryDirectory(dir=self.scratch_root)
        self.work = pathlib.Path(self.directory.name)
        (self.work / "snapshot.raw").write_text(
            json.dumps({"installation": {"version": "4.3.3", "runningInstances": [{"pid": 123}]}})
        )

    def tearDown(self):
        self.directory.cleanup()
        try:
            self.scratch_root.rmdir()
        except OSError:
            pass

    def sanitize(self, entries, mode="captured"):
        (self.work / "events.ndjson").write_text(
            "\n".join(json.dumps(entry) for entry in entries)
        )
        result = subprocess.run(
            ["/usr/bin/osascript", "-l", "JavaScript", str(SUPPORT / "collect.js"),
             "events", str(self.work), mode],
            check=True, capture_output=True, text=True, timeout=10,
        )
        return json.loads(result.stdout)

    @staticmethod
    def event(message):
        return {"subsystem": "com.leoarrow.wattson", "category": "popup-events",
                "processID": 123, "eventMessage": message,
                "private-extra": "secret-user@example.invalid"}

    def test_only_typed_recognized_event_fields_leave_raw_log(self):
        valid = self.event(
            "source=status-action eventType=2 eventNumber=18 windowNumber=42 "
            "openBefore=false openAfter=true anchorHit=1"
        )
        wrong_category = dict(valid, category="other")
        wrong_subsystem = dict(valid, subsystem="another.application")
        wrong_process = dict(valid, processID=456)
        untrusted = self.event(valid["eventMessage"] + " path=/Users/private-person")
        unknown_source = self.event(valid["eventMessage"].replace("status-action", "arbitrary"))
        invalid_number = self.event(valid["eventMessage"].replace("eventNumber=18", "eventNumber=9999999999"))
        report = self.sanitize([valid, wrong_category, wrong_subsystem, wrong_process, untrusted,
                                unknown_source, invalid_number])
        self.assertEqual(report["acceptedEvents"], [{
            "processID": 123, "source": "status-action", "eventType": 2, "eventNumber": 18,
            "windowNumber": 42, "openBefore": False, "openAfter": True, "anchorHit": True,
        }])
        self.assertEqual(report["traceStatus"], "recorded")
        self.assertNotIn("private-person", json.dumps(report))
        self.assertNotIn("secret-user", json.dumps(report))

    def test_empty_433_trace_is_explicitly_missing(self):
        report = self.sanitize([])
        self.assertEqual(report["traceStatus"], "missing-4.3.3-does-not-emit-popup-traces")
        self.assertEqual(self.sanitize([], "skipped-collect-only")["traceStatus"],
                         "not-recorded-collect-only")

    def test_v2_native_and_workspace_sources_keep_the_strict_event_grammar(self):
        sources = ["native-should-close", "native-anchor-suppressed",
                   "native-classic-close", "workspace-anchor-suppressed"]
        valid = [self.event(
            f"source={source} eventType=-1 eventNumber=-1 windowNumber=-1 "
            "openBefore=true openAfter=false anchorHit=0"
        ) for source in sources]
        report = self.sanitize(valid)
        self.assertEqual([item["source"] for item in report["acceptedEvents"]], sources)
        for item in report["acceptedEvents"]:
            self.assertEqual(set(item), {"processID", "source", "eventType", "eventNumber",
                                         "windowNumber", "openBefore", "openAfter", "anchorHit"})
            self.assertEqual(item["processID"], 123)
            self.assertTrue(item["openBefore"])
            self.assertFalse(item["openAfter"])
            self.assertFalse(item["anchorHit"])
        malformed = []
        for entry, source in zip(valid, sources):
            message = entry["eventMessage"]
            malformed.extend([
                self.event(message.replace(f"source={source} ", f"source={source}-extra ")),
                self.event(message + " windowTitle=private-window"),
                self.event(message.replace("openAfter=false", "openAfter=unknown")),
            ])
        rejected = self.sanitize(malformed)
        self.assertEqual(rejected["acceptedEvents"], [])
        self.assertNotIn("private-window", json.dumps(rejected))

    def test_no_known_wattson_pid_cannot_accept_subsystem_fixture_logs(self):
        (self.work / "snapshot.raw").write_text(
            json.dumps({"installation": {"version": "unavailable", "runningInstances": []}})
        )
        item = self.event(
            "source=status-action eventType=2 eventNumber=18 windowNumber=42 "
            "openBefore=false openAfter=true anchorHit=1"
        )
        report = self.sanitize([item])
        self.assertEqual(report["acceptedEvents"], [])
        self.assertEqual(report["traceStatus"], "missing-no-running-Wattson-instance-at-collection-start")

    def test_capture_plan_skips_433_and_no_app_but_keeps_unknown_or_newer_running(self):
        cases = [
            ({"version": "4.3.3", "runningInstances": []}, "skipped-no-trace-4.3.3"),
            ({"version": "unavailable", "runningInstances": []}, "skipped-no-running-instance"),
            ({"version": "4.3.4", "runningInstances": [{"version": "4.3.3", "pid": 123}]}, "skipped-no-trace-4.3.3"),
            ({"version": "4.3.3", "runningInstances": [{"version": "4.3.4", "pid": 123}]}, "capture"),
            ({"version": "4.3.3", "runningInstances": [{"version": "unavailable", "pid": 123}]}, "capture"),
        ]
        for installation, expected in cases:
            with self.subTest(installation=installation):
                (self.work / "snapshot.raw").write_text(json.dumps({"installation": installation}))
                result = subprocess.run(
                    ["/usr/bin/osascript", "-l", "JavaScript", str(SUPPORT / "collect.js"),
                     "plan", str(self.work)],
                    check=True, capture_output=True, text=True, timeout=10,
                )
                self.assertEqual(result.stdout.strip(), expected)

    def test_event_count_is_bounded(self):
        item = self.event(
            "source=workspace-activation eventType=-1 eventNumber=-1 windowNumber=-1 "
            "openBefore=1 openAfter=0 anchorHit=false"
        )
        self.assertEqual(len(self.sanitize([item] * 500)["acceptedEvents"]), 200)

    def test_capture_limit_uses_utf8_bytes_before_whitespace_trimming(self):
        path = self.work / "events.ndjson"
        path.write_text("é" * 131071 + "\n\n", encoding="utf-8")
        result = subprocess.run(
            ["/usr/bin/osascript", "-l", "JavaScript", str(SUPPORT / "collect.js"),
             "events", str(self.work), "captured"],
            check=True, capture_output=True, text=True, timeout=10,
        )
        self.assertTrue(json.loads(result.stdout)["captureReachedLimit"])


@unittest.skipUnless(pathlib.Path("/usr/bin/ditto").exists(), "macOS archive tooling required")
class SupportLifecycleTests(unittest.TestCase):
    def setUp(self):
        self.scratch_root = ROOT / ".build" / "issue19-support-tests.noindex"
        self.scratch_root.mkdir(parents=True, exist_ok=True)
        self.directory = tempfile.TemporaryDirectory(dir=self.scratch_root)
        self.work = pathlib.Path(self.directory.name)
        self.bundle = self.work / "Support" / "Issue19"
        shutil.copytree(SUPPORT, self.bundle)
        self.out = self.work / "output"
        self.native_tmp = self.work / "native-tmp.noindex"
        self.native_tmp.mkdir()
        self.environment = dict(os.environ, TMPDIR=str(self.native_tmp))
        self.mock = self.work / "mock"
        self.mock.mkdir()
        self.processes = []
        self.make_mock("swvers", "echo 26.0\n")
        self.make_mock("sysctl", "echo MacBookPro18,3\n")
        self.make_mock("uname", "echo arm64\n")
        self.make_mock("codesign", "exit 0\n")
        self.make_mock("osascript", """case "$4" in
snapshot) echo '{"installation":{"version":"4.3.3"},"fixture":true}' ;;
plan) echo capture ;;
events) echo '{"acceptedEvents":[],"traceStatus":"fixture"}' ;;
*) exit 2 ;;
esac
""")
        source = (self.bundle / "Collect-Wattson-Issue19.command").read_text()
        for original, replacement in {
            "/usr/bin/sw_vers": "swvers", "/usr/sbin/sysctl": "sysctl",
            "/usr/bin/uname": "uname", "/usr/bin/codesign": "codesign",
            "/usr/bin/osascript": "osascript",
        }.items():
            source = source.replace(original, str(self.mock / replacement))
        self.script = self.bundle / "Collect-Wattson-Issue19.command"
        self.script.write_text(source)

    def tearDown(self):
        for process in self.processes:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait(timeout=5)
            if process.stdout:
                process.stdout.close()
            if process.stderr:
                process.stderr.close()
        self.directory.cleanup()
        try:
            self.scratch_root.rmdir()
        except OSError:
            pass

    def make_mock(self, name, body):
        path = self.mock / name
        path.write_text("#!/bin/bash\n" + body)
        path.chmod(0o755)
        return path

    def run_command(self, extra=None):
        return subprocess.run(
            ["/bin/bash", str(self.script), "--collect-only", "--output", str(self.out)]
            + (extra or []), capture_output=True, text=True, timeout=15, env=self.environment,
        )

    def assert_scratch_removed(self):
        self.assertFalse((self.native_tmp / "Wattson-Issue19.noindex").exists())
        self.assertFalse(list(self.out.glob("*.partial.noindex")))

    def test_collect_only_packages_only_reviewable_reports_and_cleans_scratch(self):
        result = self.run_command()
        self.assertEqual(result.returncode, 0, result.stderr)
        archives = list(self.out.glob("*.zip"))
        self.assertEqual(len(archives), 1)
        with zipfile.ZipFile(archives[0]) as archive:
            names = [name for name in archive.namelist() if not name.endswith("/")]
            self.assertEqual(set(names), {"Wattson-Issue19/environment.json",
                                         "Wattson-Issue19/popup-events.json",
                                         "Wattson-Issue19/README.txt"})
            self.assertTrue(json.loads(archive.read("Wattson-Issue19/environment.json"))["fixture"])
        self.assert_scratch_removed()

    def test_probe_failure_preserves_caller_files_but_removes_own_scratch(self):
        self.out.mkdir()
        caller_input = self.out / "caller-owned.txt"
        caller_input.write_text("preserve")
        self.make_mock("osascript", "exit 1\n")
        result = self.run_command()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(caller_input.read_text(), "preserve")
        self.assertEqual(list(self.out.glob("*.zip")), [])
        self.assert_scratch_removed()

    def test_default_433_collection_skips_log_subscription_and_wait(self):
        mock = self.mock / "osascript"
        mock.write_text(mock.read_text().replace("plan) echo capture", "plan) echo skipped-no-trace-4.3.3"))
        marker = self.work / "unexpected-log"
        log_mock = self.make_mock("log", f"touch '{marker}'\nexit 1\n")
        self.script.write_text(self.script.read_text().replace("/usr/bin/log stream", str(log_mock) + " stream"))
        result = subprocess.run(
            ["/bin/bash", str(self.script), "--output", str(self.out)],
            capture_output=True, text=True, timeout=10, env=self.environment,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("4.3.3 没有点击事件记录", result.stdout)
        self.assertFalse(marker.exists())
        self.assertEqual(len(list(self.out.glob("*.zip"))), 1)
        self.assert_scratch_removed()

    def test_scratch_allocation_failure_removes_new_root(self):
        helper = self.bundle / "lifecycle.sh"
        failed_mktemp = self.make_mock("mktemp", "exit 1\n")
        helper.write_text(helper.read_text().replace("/usr/bin/mktemp", str(failed_mktemp)))
        owned_root = self.work / "allocation-failure.noindex"
        result = subprocess.run(
            ["/bin/bash", "-c", 'set -eu; source "$1"; support_begin "$2"',
             "allocation-test", str(helper), str(owned_root)],
            capture_output=True, text=True, timeout=5,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(owned_root.exists())

    def test_probe_timeout_kills_child_and_cleans_scratch(self):
        marker = self.work / "child.pid"
        self.make_mock("osascript", f"echo $$ > '{marker}'\nexec /bin/sleep 30\n")
        self.script.write_text(self.script.read_text().replace("run_probe snapshot 100", "run_probe snapshot 10"))
        result = self.run_command()
        self.assertNotEqual(result.returncode, 0)
        with self.assertRaises(ProcessLookupError):
            os.kill(int(marker.read_text()), 0)
        self.assert_scratch_removed()

    def test_interrupt_stops_owned_log_and_timer_and_cleans_scratch(self):
        marker = self.work / "logger.pid"
        log_mock = self.make_mock("log", f"echo $$ > '{marker}'\nexec /bin/sleep 30\n")
        self.script.write_text(self.script.read_text().replace("/usr/bin/log stream", str(log_mock) + " stream"))
        transcript = self.work / "interrupt.log"
        # Startup must not block on an undrained pipe before creating the marker.
        with transcript.open("w") as output:
            process = subprocess.Popen(
                ["/bin/bash", str(self.script), "--output", str(self.out)],
                stdout=output, stderr=subprocess.STDOUT, text=True, start_new_session=True,
                env=self.environment,
            )
        self.processes.append(process)
        deadline = time.monotonic() + 10
        while not marker.exists() and time.monotonic() < deadline:
            time.sleep(0.05)
        self.assertTrue(marker.exists(), transcript.read_text())
        process.send_signal(signal.SIGTERM)
        process.communicate(timeout=5)
        self.assertEqual(process.returncode, 143)
        with self.assertRaises(ProcessLookupError):
            os.kill(int(marker.read_text()), 0)
        self.assert_scratch_removed()

    def test_build_archive_preserves_executable_and_cleans_build_scratch(self):
        script_dir = self.work / "scripts"
        script_dir.mkdir()
        script = script_dir / "build_issue19_support.sh"
        shutil.copy2(ROOT / "scripts" / script.name, script)
        result = subprocess.run(["/bin/bash", str(script)], capture_output=True,
                                text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        archive_path = self.work / "dist" / "support" / "Wattson-Issue19-Support-v2.zip"
        with zipfile.ZipFile(archive_path) as archive:
            item = archive.getinfo("Wattson-Issue19-Support/Collect-Wattson-Issue19.command")
            self.assertTrue((item.external_attr >> 16) & 0o100)
        self.assertFalse((self.work / ".build" / "issue19-support.noindex").exists())


if __name__ == "__main__":
    unittest.main()
