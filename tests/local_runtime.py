"""Own the files, preferences and process groups created by runtime tests."""

import os
import pathlib
import signal
import subprocess
import sys
import tempfile
import time
import uuid
from contextlib import contextmanager


ROOT = pathlib.Path(__file__).resolve().parents[1]
SCRATCH_ROOT = ROOT / ".build" / "tests.noindex"
LSREGISTER = pathlib.Path("/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister")
_active = []
_handlers = {}
_deferring_interrupts = 0
_pending_signal = None


@contextmanager
def _defer_interrupts():
    global _deferring_interrupts, _pending_signal
    _deferring_interrupts += 1
    try:
        yield
    finally:
        _deferring_interrupts -= 1
        if not _deferring_interrupts and _pending_signal:
            pending, _pending_signal = _pending_signal, None
            _handle_interrupt(*pending)


def _live_group(group):
    states = subprocess.check_output(["/bin/ps", "-axo", "pgid=,stat="], text=True, timeout=5)
    return any(int(parts[0]) == group and not parts[1].startswith("Z")
               for line in states.splitlines() if len(parts := line.split()) == 2)


def _signal_group(process, number):
    try:
        os.killpg(process.pid, number)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        live = _live_group(process.pid)
        # A denied signal-zero probe still means the group may be alive.
        # Keep waiting/escalating for that owned group instead of aborting.
        if number == 0:
            return live
        # Darwin can report EPERM for a group containing only orphan zombies.
        # Do not hide a permission failure while a live group member remains.
        if live:
            raise
        return False


@_defer_interrupts()
def _stop(process):
    """Stop descendants as well as the direct child, then reap our child."""
    if not _signal_group(process, signal.SIGTERM):
        process.wait(timeout=1)
        return
    # Lifecycle shell callers explicitly allow time for their nested runners
    # and EXIT traps; ordinary compilers and binaries keep a short deadline.
    deadline = time.monotonic() + getattr(process, "cleanup_grace", 3)
    while time.monotonic() < deadline:
        process.poll()
        if not _signal_group(process, 0):
            break
        time.sleep(0.02)
    else:
        _signal_group(process, signal.SIGKILL)
    process.wait(timeout=1)
    deadline = time.monotonic() + 1
    while _live_group(process.pid):
        if time.monotonic() >= deadline:
            raise ChildProcessError(f"Owned process group {process.pid} did not stop")
        time.sleep(0.02)


def _interrupted(signum, frame):
    global _pending_signal
    previous = _handlers[signum]
    if _deferring_interrupts:
        _pending_signal = (signum, frame, previous)
        return
    _handle_interrupt(signum, frame, previous)


def _handle_interrupt(signum, frame, previous):
    for watched in _handlers:
        signal.signal(watched, signal.SIG_IGN)
    for workspace in list(reversed(_active)):
        workspace.cleanup(raise_errors=False)
    if callable(previous):
        previous(signum, frame)
    else:
        signal.signal(signum, previous)
        os.kill(os.getpid(), signum)


class TemporaryDirectory:
    """A project-local test workspace; cleanup also runs on INT/HUP/TERM."""

    def __init__(self, prefix="runtime-"):
        SCRATCH_ROOT.mkdir(parents=True, exist_ok=True)
        self._directory = tempfile.TemporaryDirectory(prefix=prefix, dir=SCRATCH_ROOT)
        self.name = self._directory.name
        self.processes = []
        self.defaults_suite = "Wattson.TestRuntime." + uuid.uuid4().hex
        self.home = pathlib.Path(self.name) / "isolated-home"
        self.home.mkdir()
        if not _active:
            for watched in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
                _handlers[watched] = signal.getsignal(watched)
                signal.signal(watched, _interrupted)
        _active.append(self)

    def __enter__(self):
        return self.name

    def __exit__(self, *exception):
        self.cleanup(raise_errors=exception[0] is None)

    @_defer_interrupts()
    def cleanup(self, raise_errors=True):
        if self not in _active:
            return
        errors = []
        def attempt(action):
            try:
                action()
            except (OSError, subprocess.SubprocessError) as error:
                errors.append(error)
        try:
            for process in list(self.processes):
                attempt(lambda: _stop(process))
            self.processes.clear()
            # cfprefsd can persist suites outside CFFIXED_USER_HOME. Delete
            # exactly the unique domains passed to this invocation's harness.
            for domain in (self.defaults_suite, self.defaults_suite + ".second", self.defaults_suite + ".app"):
                attempt(lambda: subprocess.run(
                    ["/usr/bin/defaults", "delete", domain],
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                    check=False, timeout=5,
                ))
                attempt(lambda: (pathlib.Path.home() / "Library/Preferences" / (domain + ".plist")).unlink(missing_ok=True))
            if LSREGISTER.is_file():
                for app in sorted(pathlib.Path(self.name).rglob("*.app")):
                    if app.is_dir() and not app.is_symlink():
                        attempt(lambda: subprocess.run(
                            [str(LSREGISTER), "-u", str(app)],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                            check=False, timeout=5,
                        ))
        finally:
            attempt(self._directory.cleanup)
            _active.remove(self)
            if not _active:
                for watched, handler in _handlers.items():
                    signal.signal(watched, handler)
                _handlers.clear()
        if errors:
            message = "; ".join(str(error) for error in errors)
            if raise_errors:
                raise RuntimeError("Test workspace cleanup failed: " + message)
            print("Test workspace cleanup failed: " + message, file=sys.stderr)


def bundle_identifier():
    return _active[-1].defaults_suite + ".app"


def run(*args, input=None, capture_output=False, timeout=120, check=False,
        cleanup_grace=3, **kwargs):
    """subprocess.run for a fixture, with isolated preferences and owned children."""
    if not _active:
        with TemporaryDirectory():
            return run(*args, input=input, capture_output=capture_output,
                       timeout=timeout, check=check, cleanup_grace=cleanup_grace,
                       **kwargs)
    workspace = _active[-1]
    environment = dict(kwargs.pop("env", os.environ))
    environment["CFFIXED_USER_HOME"] = str(workspace.home)
    environment["WATTSON_TEST_DEFAULTS_SUITE"] = workspace.defaults_suite
    kwargs["env"] = environment
    kwargs["start_new_session"] = True
    if capture_output:
        kwargs["stdout"] = subprocess.PIPE
        kwargs["stderr"] = subprocess.PIPE
    if input is not None:
        kwargs["stdin"] = subprocess.PIPE
    with _defer_interrupts():
        process = subprocess.Popen(*args, **kwargs)
        process.cleanup_grace = cleanup_grace
        workspace.processes.append(process)
    try:
        deadline = None if timeout is None else time.monotonic() + timeout
        while True:
            interval = 0.1 if deadline is None else max(0, min(0.1, deadline - time.monotonic()))
            try:
                # communicate retains partial input/output across timeouts.
                # Deliver signals only after its internal wait locks release.
                with _defer_interrupts():
                    stdout, stderr = process.communicate(input, timeout=interval)
                break
            except subprocess.TimeoutExpired as error:
                input = None
                if deadline is not None and time.monotonic() >= deadline:
                    error.timeout = timeout
                    raise
        result = subprocess.CompletedProcess(process.args, process.returncode, stdout, stderr)
        if check:
            result.check_returncode()
        return result
    finally:
        # Preserve the command's failure and captured trace while reporting any
        # cleanup failure separately; failed stops remain owned for a retry.
        failed = sys.exc_info()[0] is not None
        errors = []
        try:
            _stop(process)
        except (OSError, subprocess.SubprocessError) as error:
            errors.append(error)
        else:
            if process in workspace.processes:
                workspace.processes.remove(process)
        for stream in (process.stdin, process.stdout, process.stderr):
            if stream is not None:
                try:
                    stream.close()
                except OSError as error:
                    errors.append(error)
        if errors:
            message = (f"Test command cleanup failed for owned process group {process.pid}: "
                       + "; ".join(str(error) for error in errors))
            if failed:
                print(message, file=sys.stderr)
            else:
                raise RuntimeError(message) from errors[0]
