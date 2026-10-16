import os
import pathlib
import shlex
import signal
import subprocess
import time
import unittest

import local_runtime
from local_runtime import ROOT, TemporaryDirectory, run


SUPPORT = ROOT / "Support" / "SystemBatteryIcon"


@unittest.skipUnless(pathlib.Path("/usr/bin/perl").exists(), "bundled Perl required")
class SystemBatterySupportDeadlineTests(unittest.TestCase):
    def setUp(self):
        self.directory = TemporaryDirectory(prefix="system-battery-deadline-")
        self.addCleanup(self.directory.cleanup)
        self.work = pathlib.Path(self.directory.name)
        self.lifecycle = SUPPORT / "lifecycle.sh"

    def shell(self, body, timeout=5):
        script = self.work / "fixture.sh"
        script.write_text('set -euo pipefail\nsource ' + shlex.quote(str(self.lifecycle)) + '\n' + body)
        return run(["/bin/bash", str(script)], capture_output=True, text=True,
                   timeout=timeout, cleanup_grace=65)

    def assert_stopped(self, pid):
        deadline = time.monotonic() + 2
        while time.monotonic() < deadline:
            try:
                os.kill(pid, 0)
            except ProcessLookupError:
                return
            time.sleep(0.02)
        self.fail(f"Owned child {pid} is still present")

    def test_signal_between_launch_and_registration_is_deferred_until_owned(self):
        collector = (SUPPORT / "Collect-Wattson-SystemBatteryIcon.command").read_text()
        probe = collector[collector.index("run_probe() {"):collector.index("\nrun_probe productVersion")]
        points = ['\"local pid=\"*|\"pid=\\$!\"', 'support_track*', 'SUPPORT_CHILDREN+=*']
        for operation in ("support_run", "run_probe"):
            for point in points:
                for number in (signal.SIGHUP, signal.SIGINT, signal.SIGTERM):
                    with self.subTest(operation=operation, point=point, signal=number):
                        marker = self.work / "child.pid"
                        marker.unlink(missing_ok=True)
                        scratch = self.work / "scratch.noindex"
                        body = f'''support_begin {shlex.quote(str(scratch))}
{probe}
armed=1
set -T
trap 'case "$BASH_COMMAND" in {point})
    if [[ "$armed" == 1 ]]; then
        armed=0
        printf "%s\\n" "$!" > {shlex.quote(str(marker))}
        kill -{number} $$
    fi ;;
esac' DEBUG
''' + ("support_run /bin/sleep 30 >/dev/null 2>&1\n" if operation == "support_run"
       else "run_probe injected 3 /bin/sleep 30\n")
                        script = self.work / "fixture.sh"
                        script.write_text('set -euo pipefail\nsource ' + shlex.quote(str(self.lifecycle)) + '\n' + body)
                        with (self.work / "stderr").open("w+") as errors:
                            process = subprocess.Popen(["/bin/bash", str(script)],
                                stdout=subprocess.DEVNULL, stderr=errors, start_new_session=True)
                            self.directory.processes.append(process)
                            try:
                                process.wait(timeout=5)
                                errors.seek(0)
                                self.assertEqual(process.returncode, 128 + number, errors.read())
                                self.assertTrue(marker.exists())
                                self.assert_stopped(int(marker.read_text()))
                                self.assertFalse(scratch.exists())
                            finally:
                                local_runtime._stop(process)
                                self.directory.processes.remove(process)

    def test_supervisor_signals_across_fork_and_group_setup_reap_the_child(self):
        original = self.lifecycle.read_text()
        copied = self.work / "lifecycle.sh"
        self.lifecycle = copied
        marker = self.work / "supervised.pid"
        record = f'''if ($child) {{ open my $record, ">", q{{{marker}}} or die; print $record $child; close $record; }}'''
        for point in ("before-fork", "after-fork", "before-setpgid", "after-setpgid"):
            for number in (signal.SIGHUP, signal.SIGINT, signal.SIGTERM):
                with self.subTest(point=point, signal=number):
                    marker.unlink(missing_ok=True)
                    source = original.replace('my $child = fork();',
                        'my $target = $command[0] eq "/bin/sleep" && $command[1] eq "30";\n'
                        + (f'kill {number}, $$ if $target;\n' if point == "before-fork" else '')
                        + 'my $child = fork();\n' + 'if ($target) { ' + record + ' }\n'
                        + (f'kill {number}, $$ if $target && $child;\n' if point == "after-fork" else ''))
                    group_setup = 'setpgid(0, 0) == 0 or die "Cannot isolate support stage\\n";'
                    if point in ("before-setpgid", "after-setpgid"):
                        inject = f'kill {number}, $$ if $command[0] eq "/bin/sleep" && $command[1] eq "30";'
                        source = source.replace(group_setup, inject + '\n' + group_setup
                            if point == "before-setpgid" else group_setup + '\n' + inject)
                    copied.write_text(source)
                    scratch = self.work / "scratch.noindex"
                    result = self.shell(f'support_begin {shlex.quote(str(scratch))}\nsupport_run /bin/sleep 30\n')
                    self.assertEqual(result.returncode, 128 + number, result.stderr)
                    self.assertTrue(marker.exists())
                    self.assert_stopped(int(marker.read_text()))
                    self.assertFalse(scratch.exists())

    def test_cleanup_ignores_repeated_signals_and_has_independent_grace(self):
        scratch = self.work / "scratch.noindex"
        remover = self.work / "remove.sh"
        remover.write_text('''#!/bin/bash
kill -HUP "$OWNER_PID"
kill -INT "$OWNER_PID"
kill -TERM "$OWNER_PID"
exec /bin/rm "$@"
''')
        remover.chmod(0o755)
        copied = self.work / "lifecycle.sh"
        copied.write_text(self.lifecycle.read_text().replace('/bin/rm -rf', str(remover) + ' -rf'))
        self.lifecycle = copied
        result = self.shell(f'''export OWNER_PID=$$
SUPPORT_TOTAL_SECONDS=0.3
support_begin {shlex.quote(str(scratch))}
support_run /bin/sleep 30
''')
        self.assertEqual(result.returncode, 124, result.stderr)
        self.assertFalse(scratch.exists())

    def test_parent_process_group_signals_stop_the_owned_stage(self):
        scratch = self.work / "scratch.noindex"
        marker = self.work / "group-child.pid"
        child = self.work / "blocked.sh"
        child.write_text('echo $$ > ' + shlex.quote(str(marker)) + '\nexec /bin/sleep 30\n')
        script = self.work / "fixture.sh"
        script.write_text('set -euo pipefail\nsource ' + shlex.quote(str(self.lifecycle))
            + f'\nsupport_begin {shlex.quote(str(scratch))}\nsupport_run /bin/bash {shlex.quote(str(child))}\n')
        for number in (signal.SIGHUP, signal.SIGINT, signal.SIGTERM):
            with self.subTest(signal=number):
                marker.unlink(missing_ok=True)
                process = subprocess.Popen(["/bin/bash", str(script)], stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL, start_new_session=True)
                self.directory.processes.append(process)
                try:
                    deadline = time.monotonic() + 3
                    while not marker.exists() and time.monotonic() < deadline:
                        time.sleep(0.02)
                    self.assertTrue(marker.exists())
                    os.killpg(process.pid, number)
                    process.wait(timeout=5)
                    self.assertEqual(process.returncode, 128 + number)
                    self.assert_stopped(int(marker.read_text()))
                    self.assertFalse(scratch.exists())
                finally:
                    local_runtime._stop(process)
                    self.directory.processes.remove(process)

    def test_normally_exiting_stage_cannot_leave_a_term_ignoring_descendant(self):
        scratch = self.work / "scratch.noindex"
        marker = self.work / "descendant.pid"
        child = self.work / "fork.sh"
        child.write_text('''/bin/bash -c 'trap "" TERM; exec /bin/sleep 30' &
''' + 'echo $! > ' + shlex.quote(str(marker)) + '\nexit 0\n')
        # Observe before the test-runtime outer cleanup, so it cannot mask a leak.
        script = self.work / "fixture.sh"
        script.write_text('set -euo pipefail\nsource ' + shlex.quote(str(self.lifecycle))
            + f'\nsupport_begin {shlex.quote(str(scratch))}\nsupport_run /bin/bash {shlex.quote(str(child))}\n')
        process = subprocess.Popen(["/bin/bash", str(script)], stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL, start_new_session=True)
        self.directory.processes.append(process)
        try:
            process.wait(timeout=5)
            self.assertEqual(process.returncode, 0)
            self.assert_stopped(int(marker.read_text()))
            self.assertFalse(scratch.exists())
        finally:
            if marker.exists():
                try:
                    os.kill(int(marker.read_text()), signal.SIGKILL)
                except ProcessLookupError:
                    pass
            local_runtime._stop(process)
            self.directory.processes.remove(process)

    def test_allocation_timeout_still_collects_its_created_scratch_path(self):
        scratch = self.work / "scratch.noindex"
        allocator = self.work / "mktemp.sh"
        allocator.write_text('''#!/bin/bash
/usr/bin/mktemp "$@"
exec /bin/sleep 30
''')
        allocator.chmod(0o755)
        copied = self.work / "lifecycle.sh"
        copied.write_text(self.lifecycle.read_text().replace('/usr/bin/mktemp', str(allocator)))
        self.lifecycle = copied
        result = self.shell(f'''SUPPORT_STAGE_SECONDS=0.3
support_begin {shlex.quote(str(scratch))}
''')
        self.assertEqual(result.returncode, 124, result.stderr)
        self.assertFalse(scratch.exists())

    def test_stage_deadline_stops_a_blocked_command(self):
        scratch = self.work / "scratch.noindex"
        marker = self.work / "blocked.pid"
        child = self.work / "blocked.sh"
        child.write_text('echo $$ > ' + shlex.quote(str(marker)) + '\nexec /bin/sleep 30\n')
        started = time.monotonic()
        result = self.shell(f'''SUPPORT_STAGE_SECONDS=0.3
SUPPORT_TOTAL_SECONDS=4
support_begin {shlex.quote(str(scratch))}
support_run /bin/bash {shlex.quote(str(child))}
''', timeout=3)
        self.assertEqual(result.returncode, 124, result.stderr)
        self.assertLess(time.monotonic() - started, 2)
        self.assert_stopped(int(marker.read_text()))
        self.assertFalse(scratch.exists())

    def test_total_deadline_limits_accumulated_successful_stages(self):
        scratch = self.work / "scratch.noindex"
        completed = self.work / "completed"
        markers = [self.work / f"stage-{stage}" for stage in range(1, 6)]
        # Only this copied supervisor's monotonic clock is controlled. Every
        # stage advances one tick: each stage is below its 2-tick
        # limit, but the third must exhaust the shared 2.5-tick budget. This
        # isolates cumulative-budget logic from VM startup/scheduler speed;
        # the separate blocked-stage test exercises the real monotonic clock.
        original = self.lifecycle.read_text()
        prefix, runner = original.split("/usr/bin/perl -e '\n", 1)
        clock = "sub fixture_clock {\n" + "".join(
            f"    return {100 + index} if -e q{{{markers[index - 1]}}};\n"
            for index in range(5, 0, -1)) + "    return 100;\n}\n"
        runner = runner.replace("my ($overall, $limit, @command) = @ARGV;",
                                clock + "my ($overall, $limit, @command) = @ARGV;")
        runner = runner.replace("clock_gettime(CLOCK_MONOTONIC)", "fixture_clock()")
        self.lifecycle = self.work / "controlled-clock-lifecycle.sh"
        self.lifecycle.write_text(prefix + "/usr/bin/perl -e '\n" + runner)
        result = self.shell(f'''support_begin {shlex.quote(str(scratch))}
SUPPORT_STAGE_SECONDS=2
SUPPORT_DEADLINE=102.5
for stage in 1 2 3 4 5; do
    support_run /bin/bash -c ': > "$1"; [[ "$2" != 3 ]] || exec /bin/sleep 30' -- {shlex.quote(str(self.work))}/stage-$stage "$stage"
    [[ "$SUPPORT_DEADLINE" == 102.5 ]]
    echo "$stage" >> {shlex.quote(str(completed))}
done
''', timeout=10)
        self.assertEqual(result.returncode, 124, result.stderr)
        self.assertEqual(completed.read_text().splitlines(), ["1", "2"])
        self.assertEqual([marker.exists() for marker in markers], [True, True, True, False, False])
        self.assertFalse(scratch.exists())


if __name__ == "__main__":
    unittest.main()
