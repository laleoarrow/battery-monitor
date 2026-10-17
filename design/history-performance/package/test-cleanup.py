"""Failure-inject the actual cleanup AST/functions, without VM or system writes."""
from pathlib import Path
from types import SimpleNamespace
import ast, contextlib, hashlib, io, json, os, shutil, subprocess, tarfile, tempfile, unittest

BASE = Path(__file__).resolve().parent
SOURCE = (BASE / 'stage-package.py').read_text()
MAIN = next(node for node in ast.parse(SOURCE).body if isinstance(node, ast.Try))
SHELL = (BASE / 'tools/run-package-qa.sh').read_text()
REMOVE = SHELL[SHELL.index('remove_install() {'):SHELL.index('finish() {')]
FINISH = SHELL[SHELL.index('finish() {'):SHELL.index('trap finish EXIT')]


class CleanupTests(unittest.TestCase):
    def stage(self, code, failure=None, interrupted=False):
        with tempfile.TemporaryDirectory(prefix='failure-injection.', dir=BASE) as parent:
            root = Path(parent)
            run = root / 'run'
            run.mkdir()
            (run / 'provenance.json').write_text('{}')
            share = root / 'share'
            share.mkdir()
            def copy(source, target):
                if failure == 'copy' or failure == 'archive-copy' and str(source).endswith('.tar.gz'):
                    raise OSError('injected export failure')
                return shutil.copyfile(source, target)
            def sha(data):
                if failure == 'hash':
                    raise OSError('injected hash failure')
                return hashlib.sha256(data)
            def pack(*args, **kwargs):
                if failure == 'tar':
                    raise OSError('injected tar failure')
                return tarfile.open(*args, **kwargs)
            env = {'Path': Path, 'run': run, 'results': run / 'results', 'share': share, 'commit': 'a' * 40, 'validation_label': 'test', 'code': code, 'child': None, 'bootstrap_error': None, 'signals': [1, 2, 15], 'signal': SimpleNamespace(signal=lambda *a: None, SIG_IGN=0), 'shutil': SimpleNamespace(copyfile=copy, rmtree=shutil.rmtree), 'hashlib': SimpleNamespace(sha256=sha), 'json': json, 'tarfile': SimpleNamespace(open=pack), 'sys': __import__('sys')}
            if interrupted:
                node = ast.Try(body=[ast.Raise(exc=ast.Call(func=ast.Name(id='SystemExit', ctx=ast.Load()), args=[ast.Constant(143)], keywords=[]), cause=None)], handlers=MAIN.handlers, orelse=[], finalbody=MAIN.finalbody)
                body = [node]
            else:
                body = MAIN.finalbody
            tree = ast.fix_missing_locations(ast.Module(body=body, type_ignores=[]))
            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                exec(compile(tree, 'actual-stage-cleanup-AST', 'exec'), env)
            self.assertFalse(run.exists(), 'guest staging survived export failure')
            return env['code']

    def test_export_failures_preserve_original_23(self):
        for failure in ['copy', 'hash', 'tar', 'archive-copy']:
            with self.subTest(failure=failure):
                self.assertEqual(self.stage(23, failure), 23)

    def test_export_failure_changes_success_to_failure(self):
        self.assertEqual(self.stage(0, 'copy'), 1)

    def test_interruption_record_and_actual_exit_agree(self):
        self.assertEqual(self.stage(None, interrupted=True), 143)
        self.assertEqual(self.stage(23, interrupted=True), 23)

    def shell(self, body, injection, initial=0):
        with tempfile.TemporaryDirectory(prefix='shell-injection.', dir=BASE) as root:
            events = Path(root) / 'events'
            # Only the derived sandbox copy replaces direct absolute commands.
            body = body.replace('/usr/sbin/pkgutil', 'fake_pkgutil').replace('/usr/bin/sudo', 'fake_sudo').replace('/usr/bin/python3', 'fake_python').replace('/bin/sleep', 'fake_sleep')
            stubs = r'''
set +e
events="$1"; results="$2"; inject="$3"; initial="$4"
app='/test/App'; helper='/test/helper'; tools='/test/tools'; label='test.label'; receipt='test.receipt'; scratch='/test/scratch'
owned_install=1
event() { printf '%s\n' "$1" >> "$events"; [[ "$inject" != "$1" ]]; }
wattson_stop_executable() { event stopApp; }
wattson_unregister_app() { event unregister; }
wattson_run_timeout() {
 case "$*" in
  *' bootout '*) event bootout ;;
  *'--stop-executable'*) event stopHelper ;;
  *' enable '*) event enable ;;
  *'remove-owned-install.py'*) event remove ;;
  *'--forget'*) event forget ;;
  *) return 99 ;;
 esac
}
fake_sudo() { return 0; }
fake_pkgutil() { return 0; }
fake_python() { event audit; return 1; }
fake_sleep() { event sleep; }
_wattson_cleanup() { event scratch; return 1; }
return_status() { return "$1"; }
'''
            script = stubs + '\n' + body
            result = subprocess.run(['/bin/bash', '-c', script, 'isolated-cleanup', str(events), root, injection, str(initial)], capture_output=True, text=True)
            return result, events.read_text().splitlines() if events.exists() else []

    def test_every_remove_failure_is_reported_and_remaining_steps_run(self):
        expected = ['stopApp', 'unregister', 'bootout', 'stopHelper', 'enable', 'remove', 'forget']
        for failure in expected:
            with self.subTest(failure=failure):
                result, events = self.shell(REMOVE + '\nremove_install test\nexit $?\n', failure)
                self.assertEqual(result.returncode, 1, result.stderr)
                self.assertEqual(events, expected)

    def test_remove_success(self):
        result, events = self.shell(REMOVE + '\nremove_install test\n[[ "$owned_install" == 0 ]]\n', '')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_finish_preserves_original_failure_and_continues_all_cleanup(self):
        body = 'remove_install() { event remove; return 1; }\n' + FINISH + '\nreturn_status "$initial"\nfinish\n'
        for initial, expected in [(23, 23), (124, 124), (0, 1)]:
            with self.subTest(initial=initial):
                result, events = self.shell(body, '', initial)
                self.assertEqual(result.returncode, expected, result.stderr)
                self.assertEqual(events, ['remove', 'scratch', 'audit', 'audit'])

    def test_launchctl_disabled_and_enabled_formats(self):
        with tempfile.TemporaryDirectory(prefix='parser-fixtures.', dir=BASE) as root:
            listing = Path(root) / 'launchctl.txt'
            entry = '"com.leoarrow.wattson.helper" => '
            for expected, accepted in [('enabled', ['false', 'enabled']), ('disabled', ['true', 'disabled'])]:
                cases = [(entry + state + '\n', state in accepted) for state in ['false', 'enabled', 'true', 'disabled', 'enabled-other', 'disabled-other', 'enabled extra', 'disabled extra']]
                cases += [(text, False) for text in ['', '"unrelated.helper" => disabled\n', entry + 'unknown\n', entry + 'disabled\n' + entry + 'disabled\n', entry + 'disabled\n' + entry + 'enabled\n', 'prefix ' + entry + 'disabled\n', entry.replace('=>', '=') + 'disabled\n']]
                for text, passed in cases:
                    with self.subTest(expected=expected, text=text):
                        listing.write_text(text)
                        result = subprocess.run(['/usr/bin/python3', str(BASE / 'tools/check-helper-disabled.py'), str(listing), expected], capture_output=True, text=True)
                        self.assertEqual(result.returncode == 0, passed, result.stderr)


if __name__ == '__main__':
    unittest.main(verbosity=2)
