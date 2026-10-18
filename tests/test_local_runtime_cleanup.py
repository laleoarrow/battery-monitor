import json
import io
import os
import pathlib
import signal
import shlex
import subprocess
import sys
import time
import unittest
from unittest.mock import patch

import local_runtime


class LocalRuntimeCleanupTests(unittest.TestCase):
    def setUp(self):
        fixture = local_runtime.TemporaryDirectory(prefix="cleanup-test-")
        self.workspace = fixture
        self.addCleanup(fixture.cleanup)
        self.root = pathlib.Path(fixture.name)
        self.events = self.root / "events.jsonl"
        self.pids = self.root / "pids"
        self.slow_cleanup = self.root / "slow-cleanup-finished"
        self.registrar = self.root / "lsregister"
        self.registrar.write_text(
            f"#!{sys.executable}\n"
            "import json, pathlib, subprocess, sys\n"
            f"pids = pathlib.Path({str(self.pids)!r})\n"
            "alive = []\n"
            "for pid in pids.read_text().split() if pids.exists() else []:\n"
            "    state = subprocess.run(['/bin/ps', '-p', pid, '-o', 'stat='], capture_output=True, text=True).stdout.strip()\n"
            "    if state and not state.startswith('Z'): alive.append(pid)\n"
            f"with open({str(self.events)!r}, 'a') as stream:\n"
            "    stream.write(json.dumps({'exists': pathlib.Path(sys.argv[2]).is_dir(), 'alive': alive}) + '\\n')\n",
            encoding="utf-8",
        )
        self.registrar.chmod(0o755)

    def assert_unregistered_before_removal(self, directory):
        self.assertFalse(pathlib.Path(directory).exists())
        events = [json.loads(line) for line in self.events.read_text().splitlines()]
        self.assertTrue(events)
        self.assertTrue(all(event == {"exists": True, "alive": []} for event in events), events)

    def child_command(self):
        # The descendant ignores TERM, so a timeout must also kill the group
        # after the parent exits; killing just the direct child is insufficient.
        child = "import signal,time; signal.signal(signal.SIGTERM,signal.SIG_IGN); time.sleep(60)"
        code = (
            "import os,pathlib,subprocess,sys,time; "
            f"child=subprocess.Popen([sys.executable,'-c',{child!r}]); "
            f"pathlib.Path({str(self.pids)!r}).write_text(str(os.getpid())+' '+str(child.pid)); "
            "time.sleep(60)"
        )
        return [sys.executable, "-c", code]

    def nested_child_command(self, slow_cleanup=False):
        library = local_runtime.ROOT / "scripts/lib/local_cleanup.sh"
        prefix = f"source {shlex.quote(str(library))}\nwattson_cleanup_init\n"
        shell = prefix + "wattson_run " + shlex.join(self.child_command())
        if slow_cleanup:
            # Model a nested packaging script whose unmount/unregister EXIT
            # work takes longer than the ordinary binary's three-second grace.
            cleanup = ('trap "" HUP INT TERM; /bin/sleep 4; /usr/bin/touch '
                       + shlex.quote(str(self.slow_cleanup)) + '; _wattson_cleanup')
            inner = self.root / "slow-lifecycle.sh"
            inner.write_text(prefix + "trap " + shlex.quote(cleanup) + " EXIT\n"
                             + "wattson_run " + shlex.join(self.child_command()))
            shell = prefix + "wattson_run_script " + shlex.quote(str(inner))
        return ["/bin/bash", "-c", shell]

    def test_source_only_runners_preserve_caller_traps_and_complete_cleanup(self):
        library = local_runtime.ROOT / "scripts/lib/local_cleanup.sh"
        events = self.root / "source-only-events"
        worker = self.root / "source-only-worker.py"
        worker.write_text(
            "import os,pathlib,subprocess,sys\n"
            "child = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(60)'])\n"
            f"pathlib.Path({str(self.pids)!r}).write_text(str(os.getpid())+' '+str(child.pid))\n"
        )
        command = self.root / "source-only-command.sh"
        command.write_text("#!/bin/bash\nexec " + shlex.join([sys.executable, str(worker)]) + "\n")
        command.chmod(0o755)
        for runner in ("wattson_run", "wattson_run_timeout 5", "wattson_run_script"):
            with self.subTest(runner=runner):
                self.pids.unlink(missing_ok=True)
                events.unlink(missing_ok=True)
                shell = '''set -euo pipefail
unset _WATTSON_PENDING_SIGNAL
caller_cleanup() {
    wattson_run /usr/bin/true
    printf 'caller-cleanup\\n' >> "$SOURCE_ONLY_EVENTS"
}
trap caller_cleanup EXIT
trap 'printf "caller-signal\\n" >> "$SOURCE_ONLY_EVENTS"' TERM
''' + f"source {shlex.quote(str(library))}\n" + runner + " " + shlex.quote(str(command)) + '''
kill -TERM "$$"
printf 'body-final\\n' >> "$SOURCE_ONLY_EVENTS"
'''
                try:
                    result = local_runtime.run(
                        ["/bin/bash", "-c", shell],
                        env=dict(os.environ, SOURCE_ONLY_EVENTS=str(events)),
                        capture_output=True, text=True, timeout=15, cleanup_grace=65,
                    )
                    markers = events.read_text().splitlines() if events.exists() else []
                    detail = f"exit={result.returncode}, markers={markers!r}\n{result.stdout}{result.stderr}"
                    self.assertEqual(markers, ["caller-signal", "body-final", "caller-cleanup"], detail)
                    self.assertEqual(result.returncode, 0, detail)
                    self.assertNotIn("unbound variable", result.stderr)
                    self.assertTrue(self.pids.exists(), detail)
                    for pid in self.pids.read_text().split():
                        state = subprocess.run(['/bin/ps', '-p', pid, '-o', 'stat='],
                                               capture_output=True, text=True, timeout=5).stdout.strip()
                        self.assertTrue(not state or state.startswith('Z'), state)
                finally:
                    if self.pids.exists():
                        group = int(self.pids.read_text().split()[0])
                        try:
                            os.killpg(group, signal.SIGKILL)
                        except ProcessLookupError:
                            pass
                        except PermissionError:
                            if local_runtime._live_group(group):
                                raise

    def test_success_and_command_failure_remove_workspace(self):
        for status in (0, 7):
            with self.subTest(status=status), patch.object(local_runtime, "LSREGISTER", self.registrar):
                with local_runtime.TemporaryDirectory() as directory:
                    (pathlib.Path(directory) / "Fixture.app").mkdir()
                    result = local_runtime.run(
                        [sys.executable, "-c", f"raise SystemExit({status})"],
                        capture_output=True, text=True,
                    )
                    self.assertEqual(result.returncode, status)
                self.assert_unregistered_before_removal(directory)

    def test_communicate_retries_preserve_input_output_and_timeout(self):
        command = [sys.executable, "-c",
                   "import sys,time; data=sys.stdin.buffer.read(); "
                   "sys.stdout.buffer.write(data[:17]); sys.stdout.flush(); "
                   "sys.stderr.write('first'); sys.stderr.flush(); time.sleep(.25); "
                   "sys.stdout.buffer.write(data[17:]); sys.stderr.write('last')"]
        for text in (False, True):
            with self.subTest(text=text):
                payload = "fixture" * 20000 if text else b"fixture" * 20000
                result = local_runtime.run(command, input=payload, capture_output=True,
                                           text=text, check=True, timeout=None)
                self.assertEqual(result.stdout, payload)
                self.assertEqual(result.stderr, "firstlast" if text else b"firstlast")
        with self.assertRaises(subprocess.TimeoutExpired) as caught:
            local_runtime.run([sys.executable, "-c",
                               "import sys,time; print('partial',flush=True); "
                               "print('error',file=sys.stderr,flush=True); time.sleep(60)"],
                              capture_output=True, text=True, timeout=.25)
        self.assertEqual(caught.exception.timeout, .25)
        self.assertEqual(caught.exception.output, b"partial\n")
        self.assertEqual(caught.exception.stderr, b"error\n")

    def test_signals_inside_popen_wait_locks_do_not_reenter_cleanup(self):
        for phase in ("wait", "poll"):
            for caught in (signal.SIGINT, signal.SIGTERM):
                with self.subTest(phase=phase, signal=caught):
                    self.pids.unlink(missing_ok=True)
                    manifest = self.root / "locked-workspace"
                    injected = self.root / "signal-injected"
                    injected.unlink(missing_ok=True)
                    source = f'''import os,pathlib,signal,subprocess,sys
sys.path.insert(0, {str(local_runtime.ROOT / "tests")!r})
import local_runtime
local_runtime.LSREGISTER = pathlib.Path({str(self.registrar)!r})
child = [sys.executable, '-c', 'import time; time.sleep(60)']
class LockedPopen(subprocess.Popen):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.target = self.args == child
        self.injected = False
        if self.target:
            pathlib.Path({str(self.pids)!r}).write_text(str(self.pid))
    def inject(self, phase):
        if getattr(self, 'target', False) and not self.injected and phase == {phase!r}:
            self.injected = True
            with self._waitpid_lock:
                pathlib.Path({str(injected)!r}).write_text('lock held')
                os.kill(os.getpid(), {int(caught)})
    def wait(self, *args, **kwargs):
        self.inject('wait')
        return super().wait(*args, **kwargs)
    def poll(self):
        self.inject('poll')
        return super().poll()
subprocess.Popen = LockedPopen
with local_runtime.TemporaryDirectory() as directory:
    pathlib.Path({str(manifest)!r}).write_text(directory)
    (pathlib.Path(directory) / 'Fixture.app').mkdir()
    local_runtime.run(child, timeout=.2)
'''
                    try:
                        result = local_runtime.run([sys.executable, "-B", "-c", source],
                                                   capture_output=True, timeout=6)
                        self.assertNotEqual(result.returncode, 0)
                        self.assertTrue(injected.exists(), result.stderr.decode(errors="replace"))
                        self.assert_unregistered_before_removal(manifest.read_text())
                    finally:
                        # A failing regression must not strand the probe's
                        # separately supervised process group.
                        if self.pids.exists():
                            for pid in self.pids.read_text().split():
                                state = subprocess.run(['/bin/ps', '-p', pid, '-o', 'stat='],
                                                       capture_output=True, text=True).stdout.strip()
                                if state and not state.startswith('Z'):
                                    os.killpg(int(pid), signal.SIGKILL)

    def test_assertion_failure_also_cleans_workspace(self):
        with patch.object(local_runtime, "LSREGISTER", self.registrar):
            with self.assertRaisesRegex(AssertionError, "fixture failure"):
                with local_runtime.TemporaryDirectory() as directory:
                    (pathlib.Path(directory) / "Fixture.app").mkdir()
                    raise AssertionError("fixture failure")
        self.assert_unregistered_before_removal(directory)

    def test_cleanup_error_does_not_skip_later_resources_or_mask_failure(self):
        commands = []
        def invoke(command, **kwargs):
            commands.append(command)
            if command[0] == "/usr/bin/defaults" and not command[-1].endswith((".second", ".app")):
                raise subprocess.TimeoutExpired(command, 5)
            return subprocess.CompletedProcess(command, 0)

        with patch.object(local_runtime.subprocess, "run", side_effect=invoke), \
                patch.object(local_runtime, "LSREGISTER", self.registrar), \
                patch("sys.stderr", new_callable=io.StringIO):
            with self.assertRaisesRegex(ValueError, "original failure"):
                with local_runtime.TemporaryDirectory() as outer:
                    (pathlib.Path(outer) / "Outer.app").mkdir()
                    with local_runtime.TemporaryDirectory() as inner:
                        (pathlib.Path(inner) / "Inner.app").mkdir()
                        raise ValueError("original failure")
        self.assertFalse(pathlib.Path(outer).exists())
        self.assertFalse(pathlib.Path(inner).exists())
        self.assertEqual(sum(command[0] == str(self.registrar) for command in commands), 2)
        self.assertEqual(sum(command[0] == "/usr/bin/defaults" for command in commands), 6)

    def test_timeout_stops_descendants_before_unregistering(self):
        with patch.object(local_runtime, "LSREGISTER", self.registrar):
            with self.assertRaises(subprocess.TimeoutExpired):
                with local_runtime.TemporaryDirectory() as directory:
                    (pathlib.Path(directory) / "Fixture.app").mkdir()
                    local_runtime.run(self.child_command(), capture_output=True, timeout=0.3)
        self.assert_unregistered_before_removal(directory)

    def test_timeout_allows_nested_shell_supervisor_to_reap_its_group(self):
        with patch.object(local_runtime, "LSREGISTER", self.registrar):
            with self.assertRaises(subprocess.TimeoutExpired):
                with local_runtime.TemporaryDirectory() as directory:
                    (pathlib.Path(directory) / "Fixture.app").mkdir()
                    local_runtime.run(self.nested_child_command(), capture_output=True, timeout=0.3)
        self.assert_unregistered_before_removal(directory)

    def test_timeout_waits_for_slow_nested_lifecycle_cleanup(self):
        with patch.object(local_runtime, "LSREGISTER", self.registrar):
            with self.assertRaises(subprocess.TimeoutExpired):
                with local_runtime.TemporaryDirectory() as directory:
                    (pathlib.Path(directory) / "Fixture.app").mkdir()
                    local_runtime.run(self.nested_child_command(slow_cleanup=True),
                                      capture_output=True, timeout=0.3, cleanup_grace=65)
        self.assertTrue(self.slow_cleanup.exists())
        self.assert_unregistered_before_removal(directory)

    def test_parent_interrupts_stop_children_and_remove_workspace(self):
        for caught, command, cleanup_grace in (
            (signal.SIGINT, self.child_command(), 3),
            (signal.SIGTERM, self.child_command(), 3),
            (signal.SIGINT, self.nested_child_command(), 3),
            (signal.SIGTERM, self.nested_child_command(), 3),
            (signal.SIGTERM, self.nested_child_command(slow_cleanup=True), 65),
        ):
            with self.subTest(signal=caught, command=command[0]):
                self.pids.unlink(missing_ok=True)
                self.slow_cleanup.unlink(missing_ok=True)
                manifest = self.root / "workspace"
                manifest.unlink(missing_ok=True)
                source = (
                    "import pathlib,sys\n"
                    f"sys.path.insert(0,{str(local_runtime.ROOT / 'tests')!r})\n"
                    "import local_runtime\n"
                    f"local_runtime.LSREGISTER=pathlib.Path({str(self.registrar)!r})\n"
                    "with local_runtime.TemporaryDirectory() as directory:\n"
                    f"    pathlib.Path({str(manifest)!r}).write_text(directory)\n"
                    "    (pathlib.Path(directory)/'Fixture.app').mkdir()\n"
                    f"    local_runtime.run({command!r},capture_output=True,cleanup_grace={cleanup_grace})\n"
                )
                process = subprocess.Popen([sys.executable, "-B", "-c", source],
                                           stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                           start_new_session=True)
                process.cleanup_grace = cleanup_grace
                self.workspace.processes.append(process)
                try:
                    deadline = time.monotonic() + 5
                    while not self.pids.exists() and time.monotonic() < deadline:
                        time.sleep(0.02)
                    self.assertTrue(self.pids.exists())
                    os.kill(process.pid, caught)
                    stdout, stderr = process.communicate(timeout=8)
                    self.assertNotEqual(process.returncode, 0, (stdout, stderr))
                    self.assertTrue(self.events.exists(), stderr.decode(errors="replace"))
                finally:
                    local_runtime._stop(process)
                    process.stdout.close()
                    process.stderr.close()
                    if process in self.workspace.processes:
                        self.workspace.processes.remove(process)
                if cleanup_grace == 65:
                    self.assertTrue(self.slow_cleanup.exists())
                self.assert_unregistered_before_removal(manifest.read_text())

    @unittest.skipUnless(pathlib.Path("/usr/bin/xcrun").exists(), "requires Foundation")
    def test_foundation_preferences_are_removed_after_harness_failure(self):
        # CFFIXED_USER_HOME alone is not sufficient: cfprefsd persists suite
        # files in the actual user Preferences directory on current macOS.
        with local_runtime.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            source = root / "main.swift"
            binary = root / "preferences-probe"
            source.write_text(
                'import Foundation\n'
                'let suite = ProcessInfo.processInfo.environment["WATTSON_TEST_DEFAULTS_SUITE"]!\n'
                'let defaults = UserDefaults(suiteName: suite)!\n'
                'defaults.set("fixture", forKey: "probe")\n'
                'guard defaults.synchronize() else { exit(2) }\n'
                'print(suite)\nexit(7)\n', encoding="utf-8",
            )
            local_runtime.run(["/usr/bin/xcrun", "swiftc", str(source), "-o", str(binary)],
                              check=True, capture_output=True)
            result = local_runtime.run([str(binary)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 7, result.stderr)
            domain = result.stdout.strip()
            self.assertTrue(domain.startswith("Wattson.TestRuntime."))
            preference = pathlib.Path.home() / "Library/Preferences" / (domain + ".plist")
            # Check the domain through cfprefsd as well as its backing file.
            read = subprocess.run(["/usr/bin/defaults", "read", domain, "probe"],
                                  capture_output=True, text=True)
            self.assertEqual(read.stdout.strip(), "fixture")
        self.assertFalse(preference.exists())
        read = subprocess.run(["/usr/bin/defaults", "read", domain], capture_output=True)
        self.assertNotEqual(read.returncode, 0)


if __name__ == "__main__":
    unittest.main()
