import os
import pathlib
import shutil
import signal
import subprocess
import time
import unittest

from local_runtime import TemporaryDirectory, _live_group, _stop, run

ROOT = pathlib.Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('clang'), 'requires a native compiler for the fake app')
class RunPreviewCleanupTests(unittest.TestCase):
    def setUp(self):
        workspace = TemporaryDirectory(prefix='run-preview-')
        self.workspace = workspace
        self.addCleanup(workspace.cleanup)
        self.root = pathlib.Path(workspace.name)
        (self.root / 'script').mkdir()
        (self.root / 'scripts').mkdir()
        shutil.copytree(ROOT / 'scripts/lib', self.root / 'scripts/lib')
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        (self.root / 'VERSION').write_text('4.3.3\n')
        self.record = self.root / 'events'
        self.app_events = self.root / 'app-events'
        self.pid_file = self.root / 'app.pid'
        self.script = self.root / 'script/build_and_run.sh'
        source = (ROOT / 'script/build_and_run.sh').read_text()
        for command in ('/usr/bin/open', '/usr/bin/codesign', '/usr/bin/log'):
            source = source.replace(command, str(self.bin / pathlib.Path(command).name))
        self.script.write_text(source)
        helper = self.root / 'scripts/lib/local_cleanup.sh'
        helper.write_text(helper.read_text().replace(
            '/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister',
            str(self.bin / 'lsregister'),
        ))
        c_source = self.root / 'fake.c'
        c_source.write_text('''#include <fcntl.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
static int events = -1;
static void terminate(int number) {
    (void)number;
    write(events, "app:TERM\\n", sizeof("app:TERM\\n") - 1);
    _exit(0);
}
int main(void) {
    events = open(getenv("FAKE_APP_EVENTS"), O_WRONLY | O_CREAT | O_APPEND, 0600);
    if (events < 0) return 2;
    signal(SIGTERM, terminate);
    write(events, "app:started\\n", sizeof("app:started\\n") - 1);
    const char *duration = getenv("FAKE_APP_SECONDS");
    if (duration && strcmp(duration, "forever") == 0) {
        for (;;) pause();
    }
    usleep((useconds_t)((duration ? atof(duration) : 30) * 1000000));
    write(events, "app:natural-exit\\n", sizeof("app:natural-exit\\n") - 1);
    return 0;
}
''')
        self.fake = self.root / 'fake-app'
        run(['clang', str(c_source), '-o', str(self.fake)], check=True, capture_output=True)
        self.write_stub('xcrun', '''#!/bin/bash
[[ "${FAKE_COMPILE_STATUS:-0}" == 0 ]] || exit "$FAKE_COMPILE_STATUS"
while [[ "$1" != -o ]]; do shift; done
cp "$FAKE_APP" "$2"
''')
        self.write_stub('codesign', '#!/bin/bash\nexit 0\n')
        self.write_stub('log', '#!/bin/bash\nwhile :; do sleep 1; done\n')
        self.write_stub('open', '''#!/usr/bin/python3
import os, pathlib, subprocess, sys
bundle = next(pathlib.Path(a) for a in sys.argv[1:] if a.endswith('.app'))
child = subprocess.Popen([str(bundle/'Contents/MacOS/WattsonPreview')],
                         start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
pathlib.Path(os.environ['FAKE_PID_FILE']).write_text(str(child.pid))
if '-W' in sys.argv:
    sys.exit(child.wait())
''')
        self.write_stub('lsregister', '''#!/bin/bash
[[ -d "$2" ]] || exit 3
registrar='/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'
if [[ -x "$registrar" ]]; then
    "$registrar" -u "$2" >/dev/null 2>&1 || true
fi
printf 'unregister:%s\n' "$2" >> "$FAKE_EVENTS"
printf 'unregister\n' >> "$FAKE_APP_EVENTS"
''')
        self.env = dict(os.environ, PATH=str(self.bin)+os.pathsep+os.environ['PATH'],
                        FAKE_APP=str(self.fake), FAKE_PID_FILE=str(self.pid_file),
                        FAKE_EVENTS=str(self.record), FAKE_APP_EVENTS=str(self.app_events))
        self.addCleanup(self.stop_fake)

    def write_stub(self, name, content):
        p = self.bin / name
        p.write_text(content)
        p.chmod(0o755)

    def stop_fake(self):
        if self.pid_file.exists():
            try:
                os.kill(int(self.pid_file.read_text()), signal.SIGKILL)
            except ProcessLookupError:
                pass

    def assert_clean(self):
        self.assertEqual(list(self.root.rglob('*.app')), [])
        scratch = self.root / '.build/run.noindex'
        self.assertFalse(scratch.exists() and list(scratch.iterdir()))
        if self.pid_file.exists():
            pid = int(self.pid_file.read_text())
            state = subprocess.run(['/bin/ps', '-p', str(pid), '-o', 'stat='],
                                   capture_output=True, text=True).stdout.strip()
            self.assertTrue(not state or state.startswith('Z'), state)

    def test_verify_stops_detached_app_and_cleans_every_run(self):
        for _ in range(2):
            result = run(['/bin/bash', str(self.script), '--verify'], env=self.env,
                         capture_output=True, text=True, timeout=15, cleanup_grace=65)
            self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
            self.assert_clean()
        self.assertEqual(len(self.record.read_text().splitlines()), 2)

    def test_run_waits_for_app_exit_then_cleans(self):
        environment = dict(self.env, FAKE_APP_SECONDS='0.2')
        result = run(['/bin/bash', str(self.script)], env=environment,
                     capture_output=True, text=True, timeout=10, cleanup_grace=65)
        self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
        self.assert_clean()

    def test_compile_failure_and_invalid_mode_leave_no_app(self):
        for mode, status, overrides in [('--verify', 9, {'FAKE_COMPILE_STATUS':'9'}),
                                        ('--invalid', 2, {})]:
            result = run(['/bin/bash', str(self.script), mode], env=dict(self.env, **overrides),
                         capture_output=True, text=True, timeout=10, cleanup_grace=65)
            self.assertEqual(result.returncode, status, result.stdout+result.stderr)
            self.assert_clean()

    def test_terminated_log_session_stops_its_detached_app(self):
        environment = dict(self.env, FAKE_APP_SECONDS='forever')
        process = subprocess.Popen(['/bin/bash', str(self.script), '--logs'], env=environment,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                                   start_new_session=True)
        process.cleanup_grace = 65
        self.workspace.processes.append(process)
        try:
            deadline = time.monotonic()+10
            while not (self.pid_file.exists() and self.app_events.exists()
                       and 'app:started' in self.app_events.read_text().splitlines()) \
                    and process.poll() is None:
                self.assertLess(time.monotonic(), deadline)
                time.sleep(0.02)
            self.assertTrue(self.pid_file.exists())
            self.assertIn('app:started', self.app_events.read_text().splitlines())
            # Interrupt the shell alone: the app is deliberately not its child.
            with self.app_events.open('a') as events:
                events.write('test:shell-TERM\n')
            process.send_signal(signal.SIGTERM)
            # Allow the same bounded lifecycle cleanup used by finally's _stop.
            stdout, stderr = process.communicate(timeout=process.cleanup_grace)
            self.assertEqual(process.returncode, 143, stdout+stderr)
            self.assert_clean()
            self.assertEqual(self.app_events.read_text().splitlines(), [
                'app:started', 'test:shell-TERM', 'app:TERM', 'unregister',
            ])
        finally:
            _stop(process)
            process.communicate()
            self.workspace.processes.remove(process)

    def assert_termination_during_runner_registration(self, runner):
        runner_pid = self.root / 'log-runner.pid'
        log_pid = self.root / 'log.pid'
        log_ready = self.root / 'log-ready'
        self.write_stub('log', '''#!/bin/bash
while [[ ! -s "$FAKE_APP_EVENTS" ]]; do /bin/sleep 0.01; done
printf '%s\\n' "$$" > "$FAKE_LOG_PID"
touch "$FAKE_LOG_READY"
while :; do /bin/sleep 1; done
''')
        helper = self.root / 'scripts/lib/local_cleanup.sh'
        source = helper.read_text()
        registration = '    _WATTSON_RUNNER_PID=$!\n'
        self.assertIn(registration, source)
        # Hold the real spawn/registration boundary until its command exists,
        # then deliver TERM before the parent can publish the runner PID.
        source = source.replace(registration, '''    if [[ "${1:-}" == "$FAKE_LOG_COMMAND" ]]; then
        printf '%s\\n' "$!" > "$FAKE_RUNNER_PID"
        while [[ ! -f "$FAKE_LOG_READY" ]]; do /bin/sleep 0.01; done
        printf 'test:shell-TERM\\n' >> "$FAKE_APP_EVENTS"
        kill -TERM "$$"
    fi
''' + registration)
        helper.write_text(source)
        log_command = str(self.bin / 'log')
        self.script.write_text(self.script.read_text().replace(
            'wattson_run ' + log_command, runner + ' ' + log_command,
        ))
        environment = dict(self.env, FAKE_APP_SECONDS='forever',
                           FAKE_LOG_COMMAND=log_command, FAKE_RUNNER_PID=str(runner_pid),
                           FAKE_LOG_PID=str(log_pid), FAKE_LOG_READY=str(log_ready))
        process = subprocess.Popen(['/bin/bash', str(self.script), '--logs'], env=environment,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                                   start_new_session=True)
        process.cleanup_grace = 65
        self.workspace.processes.append(process)
        try:
            stdout, stderr = process.communicate(timeout=process.cleanup_grace)
            self.assertEqual(process.returncode, 143, stdout+stderr)
            self.assert_clean()
            self.assertEqual(self.app_events.read_text().splitlines(), [
                'app:started', 'test:shell-TERM', 'app:TERM', 'unregister',
            ])
            for marker in (runner_pid, log_pid):
                self.assertTrue(marker.exists())
                state = subprocess.run(['/bin/ps', '-p', marker.read_text().strip(), '-o', 'stat='],
                                       capture_output=True, text=True, timeout=5).stdout.strip()
                self.assertTrue(not state or state.startswith('Z'), state)
        except subprocess.TimeoutExpired as error:
            owned = [str(process.pid)] + [marker.read_text().strip()
                     for marker in (self.pid_file, runner_pid, log_pid) if marker.exists()]
            tree = subprocess.run(['/bin/ps', '-p', ','.join(owned),
                                   '-o', 'pid=,ppid=,pgid=,stat=,command='],
                                  capture_output=True, text=True, timeout=5).stdout
            self.fail(f'Cleanup timed out with shell status {process.poll()}: {error}\n{tree}')
        finally:
            # A broken registration can miss the runner and its new session.
            # These fixture-written PIDs keep even the failing test bounded.
            for marker, group in ((log_pid, True), (runner_pid, False)):
                if marker.exists():
                    pid = int(marker.read_text())
                    try:
                        (os.killpg if group else os.kill)(pid, signal.SIGTERM)
                    except ProcessLookupError:
                        pass
                    except PermissionError:
                        if not group or _live_group(pid):
                            raise
            _stop(process)
            process.communicate()
            self.workspace.processes.remove(process)

    def test_term_during_log_runner_registration_cleans_detached_app(self):
        self.assert_termination_during_runner_registration('wattson_run')

    def test_term_during_timed_log_runner_registration_cleans_detached_app(self):
        self.assert_termination_during_runner_registration('wattson_run_timeout 30')

    def test_term_during_script_log_runner_registration_cleans_detached_app(self):
        self.assert_termination_during_runner_registration('wattson_run_script')


if __name__ == '__main__':
    unittest.main()
