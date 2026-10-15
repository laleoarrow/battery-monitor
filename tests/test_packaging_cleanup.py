import os
import pathlib
import shutil
import signal
import subprocess
import time
import unittest

import local_runtime as runtime


ROOT = pathlib.Path(__file__).resolve().parents[1]
LIB = ROOT / "scripts/lib"


class PackagingCleanupTests(unittest.TestCase):
    def setUp(self):
        # Filesystem names may contain characters that are invalid in domains.
        self.workspace = runtime.TemporaryDirectory(prefix="packaging_fixture-")
        self.addCleanup(self.workspace.cleanup)
        self.root = pathlib.Path(self.workspace.name)
        self.addCleanup(self.stop_all_fixture_processes)
        self.lib = self.root / "lib"
        self.lib.mkdir()
        self.bin = self.root / "stubs"
        self.bin.mkdir()
        self.log = self.root / "events.log"
        self.mount_state = self.root / "mount-state"
        source = (LIB / "local_cleanup.sh").read_text(encoding="utf-8")
        source = source.replace(
            "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
            "$STUB_BIN/lsregister",
        )
        for command, name in (("/sbin/mount", "mount"), ("/usr/bin/hdiutil", "hdiutil"),
                              ("/usr/bin/defaults", "defaults")):
            source = source.replace(command, f'"$STUB_BIN/{name}"')
        # Redirect only the fixture library's home paths; never replace real HOME.
        source = source.replace("$HOME/", "$FIXTURE_HOME/")
        (self.lib / "local_cleanup.sh").write_text(source, encoding="utf-8")
        shutil.copyfile(LIB / "run_owned.py", self.lib / "run_owned.py")
        self.stub("lsregister", '''
[[ "$1" == -u && -d "$2" ]] || exit 90
printf 'unregister:%s\n' "$2" >> "$EVENTS"
exit "${UNREGISTER_STATUS:-0}"
''')
        self.stub("mount", '[[ ! -f "$MOUNT_STATE" ]] || cat "$MOUNT_STATE"\n')
        self.stub("hdiutil", '''
[[ "$1" == detach ]] || exit 91
printf 'detach:%s\n' "$2" >> "$EVENTS"
[[ "${DETACH_STATUS:-0}" == 0 ]] || exit "$DETACH_STATUS"
rm -f "$MOUNT_STATE"
''')
        self.stub("defaults", '''
[[ "$1" == delete ]] || exit 92
printf 'defaults:%s\n' "$2" >> "$EVENTS"
# Simulate the empty preference file defaults can leave after deleting a suite.
: > "$FIXTURE_HOME/Library/Preferences/$2.plist"
''')
        self.env = dict(
            os.environ, TEST_LIB=str(self.lib), STUB_BIN=str(self.bin),
            EVENTS=str(self.log), MOUNT_STATE=str(self.mount_state),
            FIXTURE_HOME=str(self.root / "fixture-home"),
            OWNED=str(self.root / "owned"), INPUT=str(self.root / "caller-input"),
        )
        self.prefix = 'set -euo pipefail\nsource "$TEST_LIB/local_cleanup.sh"\nwattson_cleanup_init\n'

    def stub(self, name, body):
        script = self.bin / name
        script.write_text("#!/bin/bash\nset -eu\n" + body, encoding="utf-8")
        script.chmod(0o755)

    def run_shell(self, body, **overrides):
        return runtime.run(
            ["/bin/bash", "-c", self.prefix + body],
            env=dict(self.env, **overrides), capture_output=True, text=True, timeout=12,
            cleanup_grace=65,
        )

    def events(self):
        return self.log.read_text(encoding="utf-8").splitlines() if self.log.exists() else []

    def test_success_and_failure_unregister_owned_apps_before_removing_scratch(self):
        caller = pathlib.Path(self.env["INPUT"])
        caller.mkdir()
        (caller / "keep.txt").write_text("caller-owned", encoding="utf-8")
        for status in (0, 7):
            with self.subTest(status=status):
                self.log.unlink(missing_ok=True)
                result = self.run_shell('''
mkdir -p "$OWNED/explicit.app" "$OWNED/expanded/Payload/discovered.app"
wattson_cleanup_add_dir "$OWNED"
wattson_cleanup_add_app "$OWNED/explicit.app"
wattson_run /bin/bash -c 'exit "$TASK_STATUS"'
''', TASK_STATUS=str(status))
                self.assertEqual(result.returncode, status, result.stderr)
                self.assertFalse(pathlib.Path(self.env["OWNED"]).exists())
                self.assertEqual(len(self.events()), 2, self.events())
                self.assertTrue(all(event.startswith("unregister:") for event in self.events()))
                self.assertEqual((caller / "keep.txt").read_text(), "caller-owned")

    def seed_mount(self):
        parent = pathlib.Path(self.env["OWNED"])
        mount = parent / "nested/mount"
        mount.mkdir(parents=True)
        marker = mount / "payload"
        marker.write_text("mounted bytes", encoding="utf-8")
        self.mount_state.write_text(f"/dev/fake on {mount} (hfs, local, read-only)\n", encoding="utf-8")
        return parent, mount, marker

    def test_detach_failure_preserves_mount_and_ancestors_but_cleans_independent_paths(self):
        for status in (0, 9):
            with self.subTest(status=status):
                parent, mount, marker = self.seed_mount()
                independent = self.root / "independent"
                independent.mkdir()
                self.log.unlink(missing_ok=True)
                result = self.run_shell('''
wattson_cleanup_add_dir "$OWNED"
wattson_cleanup_add_dir "$MOUNT_POINT"
wattson_cleanup_add_dir "$INDEPENDENT"
wattson_cleanup_add_mount "$MOUNT_POINT"
exit "$TASK_STATUS"
''', MOUNT_POINT=str(mount), INDEPENDENT=str(independent), DETACH_STATUS="1", TASK_STATUS=str(status))
                self.assertEqual(result.returncode, status or 1, result.stderr)
                self.assertTrue(marker.exists())
                self.assertTrue(parent.exists())
                self.assertFalse(independent.exists())
                self.assertEqual(self.events().count(f"detach:{mount}"), 3)
                shutil.rmtree(parent)

    def test_successful_detach_then_removal_and_unmounted_noop(self):
        parent, mount, _ = self.seed_mount()
        result = self.run_shell('''
wattson_cleanup_add_dir "$OWNED"
wattson_cleanup_add_mount "$MOUNT_POINT"
''', MOUNT_POINT=str(mount))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(parent.exists())
        self.assertEqual(self.events(), [f"detach:{mount}"])
        self.log.unlink()
        result = self.run_shell('wattson_detach "$OWNED/nonexistent"\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.events(), [])

    def test_container_cleanup_requires_creation_ownership(self):
        containers = pathlib.Path(self.env["FIXTURE_HOME"]) / "Library/Containers"
        scripts = pathlib.Path(self.env["FIXTURE_HOME"]) / "Library/Application Scripts"
        existing = containers / "com.example.existing"
        existing.mkdir(parents=True)
        (existing / "keep").touch()
        existing_scripts = scripts / "com.example.script-existing"
        existing_scripts.mkdir(parents=True)
        (existing_scripts / "keep").touch()
        linked = containers / "com.example.linked"
        linked.symlink_to(existing, target_is_directory=True)
        result = self.run_shell('''
wattson_cleanup_add_container com.example.existing
wattson_cleanup_add_container com.example.linked
wattson_cleanup_add_container com.example.created
wattson_cleanup_add_container com.example.script-existing
mkdir -p "$FIXTURE_HOME/Library/Containers/com.example.created"
mkdir -p "$FIXTURE_HOME/Library/Containers/com.example.script-existing"
mkdir -p "$FIXTURE_HOME/Library/Containers/com.example.unregistered"
mkdir -p "$FIXTURE_HOME/Library/Application Scripts/com.example.created"
mkdir -p "$FIXTURE_HOME/Library/Application Scripts/com.example.existing"
mkdir -p "$FIXTURE_HOME/Library/Application Scripts/com.example.unregistered"
''')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((existing / "keep").exists())
        self.assertTrue(linked.is_symlink())
        self.assertFalse((containers / "com.example.created").exists())
        self.assertFalse((containers / "com.example.script-existing").exists())
        self.assertTrue((containers / "com.example.unregistered").exists())
        self.assertFalse((scripts / "com.example.created").exists())
        self.assertFalse((scripts / "com.example.existing").exists())
        self.assertTrue((existing_scripts / "keep").exists())
        self.assertTrue((scripts / "com.example.unregistered").exists())

    def test_only_explicit_unique_defaults_suite_is_deleted(self):
        preferences = pathlib.Path(self.env["FIXTURE_HOME"]) / "Library/Preferences"
        preferences.mkdir(parents=True)
        canonical = preferences / "com.leoarrow.wattson.plist"
        canonical.write_text("user settings", encoding="utf-8")
        suite = self.workspace.defaults_suite
        owned = preferences / f"{suite}.plist"
        owned.touch()
        result = self.run_shell('wattson_cleanup_add_defaults "$SUITE"\n', SUITE=suite)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.events(), [f"defaults:{suite}"])
        self.assertFalse(owned.exists())
        self.assertEqual(canonical.read_text(), "user settings")
        for invalid in ("../outside", suite + "_invalid"):
            result = self.run_shell('wattson_cleanup_add_defaults "$SUITE"\n', SUITE=invalid)
            self.assertEqual(result.returncode, 2)
        self.assertEqual(self.events(), [f"defaults:{suite}"])
        self.assertEqual(canonical.read_text(), "user settings")

    def create_owned_tree(self):
        script = self.root / "owned_tree.py"
        script.write_text('''
import os
import pathlib
import signal
import subprocess
import sys
import time

signal.signal(signal.SIGTERM, signal.SIG_IGN)
if len(sys.argv) > 1 and sys.argv[1] == "leaf":
    pathlib.Path(os.environ["LEAF_PID"]).write_text(str(os.getpid()))
    pathlib.Path(os.environ["READY"]).touch()
else:
    pathlib.Path(os.environ["LEADER_PID"]).write_text(str(os.getpid()))
    subprocess.Popen([sys.executable, __file__, "leaf"])
    if len(sys.argv) > 1 and sys.argv[1] == "exit":
        while not pathlib.Path(os.environ["READY"]).exists():
            time.sleep(0.01)
        sys.exit(0)
while True:
    time.sleep(0.05)
''', encoding="utf-8")
        return script

    def active(self, pid):
        result = runtime.run(["/bin/ps", "-p", str(pid), "-o", "state="],
                                capture_output=True, text=True, timeout=2)
        state = result.stdout.strip()
        return bool(state and not state.startswith("Z"))

    def stop_fixture_process(self, pid):
        command = runtime.run(["/bin/ps", "-p", str(pid), "-o", "command="],
                                 capture_output=True, text=True, timeout=2).stdout
        if str(self.root) in command and self.active(pid):
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass

    def fixture_process_ids(self):
        listing = runtime.run(["/bin/ps", "-axo", "pid=,uid=,command="],
                              capture_output=True, text=True, check=True).stdout
        pids = []
        for line in listing.splitlines():
            fields = line.split(None, 2)
            if len(fields) == 3 and fields[1] == str(os.getuid()) and str(self.root) in fields[2]:
                pids.append(int(fields[0]))
        return pids

    def stop_all_fixture_processes(self):
        for pid in self.fixture_process_ids():
            self.stop_fixture_process(pid)

    def finish_process(self, process):
        if process.poll() is None:
            process.kill()
        process.communicate(timeout=3)

    def start_process(self, *args, cleanup_grace=3, **kwargs):
        process = subprocess.Popen(*args, start_new_session=True, **kwargs)
        process.cleanup_grace = cleanup_grace
        self.workspace.processes.append(process)
        self.addCleanup(self.finish_process, process)
        return process

    def test_parent_signals_stop_term_ignoring_owned_group_and_remove_scratch(self):
        tree = self.create_owned_tree()
        for number in (signal.SIGHUP, signal.SIGINT, signal.SIGTERM):
            with self.subTest(signal=number.name):
                ready = self.root / "ready"
                ready.unlink(missing_ok=True)
                leader = self.root / "leader.pid"
                leaf = self.root / "leaf.pid"
                env = dict(self.env, TREE=str(tree), READY=str(ready),
                           LEADER_PID=str(leader), LEAF_PID=str(leaf))
                process = self.start_process(
                    ["/bin/bash", "-c", self.prefix + '''
mkdir -p "$OWNED"
wattson_cleanup_add_dir "$OWNED"
wattson_run /usr/bin/python3 "$TREE"
'''], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                    cleanup_grace=65,
                )
                deadline = time.monotonic() + 4
                while not ready.exists() and process.poll() is None and time.monotonic() < deadline:
                    time.sleep(0.02)
                if not ready.exists():
                    process.terminate()
                    output, error = process.communicate(timeout=6)
                    self.fail(f"owned tree did not become ready: {output}{error}")
                pids = [int(leader.read_text()), int(leaf.read_text())]
                listing = runtime.run(
                    ["/bin/ps", "-axo", "pid=,ppid=,command="],
                    capture_output=True, text=True, check=True,
                ).stdout
                for line in listing.splitlines():
                    fields = line.split(None, 2)
                    if (len(fields) == 3 and fields[1] == str(process.pid)
                            and str(self.lib / "run_owned.py") in fields[2]):
                        pids.append(int(fields[0]))
                for pid in pids:
                    self.addCleanup(self.stop_fixture_process, pid)
                started = time.monotonic()
                process.send_signal(number)
                try:
                    output, error = process.communicate(timeout=8)
                except subprocess.TimeoutExpired:
                    for pid in pids:
                        self.stop_fixture_process(pid)
                    self.finish_process(process)
                    self.fail("signal cleanup exceeded 8 seconds")
                self.assertEqual(process.returncode, 128 + number, output + error)
                self.assertLess(time.monotonic() - started, 7)
                self.assertFalse(pathlib.Path(self.env["OWNED"]).exists())
                deadline = time.monotonic() + 2
                while any(self.active(pid) for pid in pids) and time.monotonic() < deadline:
                    time.sleep(0.02)
                self.assertFalse(any(self.active(pid) for pid in pids), f"live owned PIDs: {pids}")

    def test_timeout_and_normal_exit_reap_background_descendants(self):
        tree = self.create_owned_tree()
        for command, status in (("wattson_run_timeout 0.5", 124), ("wattson_run", 0)):
            with self.subTest(command=command):
                ready = self.root / "ready"
                ready.unlink(missing_ok=True)
                leader = self.root / "leader.pid"
                leaf = self.root / "leaf.pid"
                mode = "" if status else "exit"
                result = self.run_shell(
                    'mkdir -p "$OWNED"\nwattson_cleanup_add_dir "$OWNED"\n'
                    f'{command} /usr/bin/python3 "$TREE" {mode}\n',
                    TREE=str(tree), READY=str(ready), LEADER_PID=str(leader), LEAF_PID=str(leaf),
                )
                self.assertEqual(result.returncode, status, result.stderr)
                self.assertFalse(pathlib.Path(self.env["OWNED"]).exists())
                pids = [int(leader.read_text()), int(leaf.read_text())]
                self.assertFalse(any(self.active(pid) for pid in pids), f"live owned PIDs: {pids}")

    def test_nested_script_signals_wait_for_inner_unmount_and_cleanup(self):
        tree = self.create_owned_tree()
        inner_root = self.root / "inner-owned"
        outer_root = self.root / "outer-owned"
        inner = self.root / "inner.sh"
        inner.write_text(self.prefix + '''
mkdir -p "$INNER_ROOT/Wattson.app" "$INNER_ROOT/mount"
printf '/dev/fake on %s (hfs, local, read-only)\n' "$INNER_ROOT/mount" > "$MOUNT_STATE"
wattson_cleanup_add_dir "$INNER_ROOT"
wattson_cleanup_add_app "$INNER_ROOT/Wattson.app"
wattson_cleanup_add_mount "$INNER_ROOT/mount"
wattson_run /usr/bin/python3 "$TREE"
''', encoding="utf-8")
        self.stub("hdiutil", '''
[[ "$1" == detach ]] || exit 91
printf 'detach-started:%s\n' "$2" >> "$EVENTS"
/bin/sleep 2.2
rm -f "$MOUNT_STATE"
printf 'detach-completed:%s\n' "$2" >> "$EVENTS"
''')
        for number in (signal.SIGHUP, signal.SIGINT, signal.SIGTERM):
            with self.subTest(signal=number.name):
                ready = self.root / "ready"
                ready.unlink(missing_ok=True)
                self.log.unlink(missing_ok=True)
                env = dict(
                    self.env, TREE=str(tree), READY=str(ready), INNER_ROOT=str(inner_root),
                    OUTER_ROOT=str(outer_root), INNER_SCRIPT=str(inner),
                    LEADER_PID=str(self.root / "leader.pid"), LEAF_PID=str(self.root / "leaf.pid"),
                )
                process = self.start_process(
                    ["/bin/bash", "-c", self.prefix + '''
mkdir -p "$OUTER_ROOT"
wattson_cleanup_add_dir "$OUTER_ROOT"
wattson_run_script "$INNER_SCRIPT"
'''], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                    cleanup_grace=65,
                )
                deadline = time.monotonic() + 4
                while not ready.exists() and process.poll() is None and time.monotonic() < deadline:
                    time.sleep(0.02)
                self.assertTrue(ready.exists(), "inner owned tree did not become ready")
                pids = self.fixture_process_ids()
                started = time.monotonic()
                process.send_signal(number)
                try:
                    output, error = process.communicate(timeout=12)
                except subprocess.TimeoutExpired:
                    self.stop_all_fixture_processes()
                    self.finish_process(process)
                    self.fail("nested signal cleanup exceeded 12 seconds")
                self.assertEqual(process.returncode, 128 + number, output + error)
                self.assertGreaterEqual(time.monotonic() - started, 2.2)
                self.assertFalse(inner_root.exists())
                self.assertFalse(outer_root.exists())
                self.assertFalse(self.mount_state.exists())
                self.assertEqual(self.events(), [
                    f"unregister:{inner_root}/Wattson.app",
                    f"detach-started:{inner_root}/mount",
                    f"detach-completed:{inner_root}/mount",
                ])
                self.assertFalse(any(self.active(pid) for pid in pids), f"live nested PIDs: {pids}")

    def test_outer_cleanup_preserves_an_inner_script_mount_after_detach_failure(self):
        parent, mount, marker = self.seed_mount()
        inner = self.root / "inner-failure.sh"
        inner.write_text(self.prefix + '''
wattson_cleanup_add_dir "$OWNED/nested"
wattson_cleanup_add_mount "$MOUNT_POINT"
''', encoding="utf-8")
        independent = self.root / "independent"
        independent.mkdir()
        result = self.run_shell('''
wattson_cleanup_add_dir "$OWNED"
wattson_cleanup_add_dir "$INDEPENDENT"
wattson_run_script "$INNER_SCRIPT"
''', INNER_SCRIPT=str(inner), MOUNT_POINT=str(mount), INDEPENDENT=str(independent), DETACH_STATUS="1")
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertTrue(parent.exists())
        self.assertTrue(marker.exists())
        self.assertFalse(independent.exists())
        self.assertEqual(self.events(), [f"detach:{mount}"] * 3)
        self.assertIn("containing an attached volume", result.stderr)

    def test_exact_executable_stop_leaves_other_process_untouched(self):
        owned = self.root / "owned-sleep"
        other = self.root / "other-sleep"
        processes = [self.start_process(["/bin/sleep", "30"]) for _ in range(2)]
        # Supply private executable identities for two real test-owned processes.
        # Copying Apple's platform binaries can fail macOS execution policy, and
        # selecting the real /bin/sleep path could affect unrelated processes.
        runner = self.lib / "run_owned.py"
        runner.write_text(runner.read_text().replace('"/bin/ps"', 'os.environ["STUB_PS"]'))
        self.stub("ps", '''
for role in OWNED OTHER; do
    if [[ "$role" == OWNED ]]; then
        pid="$OWNED_PID"; executable="$EXACT_BINARY"
    else
        pid="$OTHER_PID"; executable="$OTHER_BINARY"
    fi
    read -r state < <(/bin/ps -p "$pid" -o state=) || continue
    [[ "$state" != Z* ]] || continue
    printf '%s %s %s\n' "$pid" "$(id -u)" "$executable"
done
''')
        result = self.run_shell(
            'wattson_stop_executable "$EXACT_BINARY"\n', EXACT_BINARY=str(owned),
            OTHER_BINARY=str(other), OWNED_PID=str(processes[0].pid),
            OTHER_PID=str(processes[1].pid), STUB_PS=str(self.bin / "ps"),
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIsNotNone(processes[0].poll())
        self.assertIsNone(processes[1].poll())
        processes[1].terminate()
        processes[1].wait(timeout=2)


if __name__ == "__main__":
    unittest.main()
