#!/usr/bin/env python3
"""Run one command in an owned process group and reap it on interruption."""

import ctypes
import os
import signal
import subprocess
import sys
import time


if sys.platform == "darwin":
    class BSDProcessInfo(ctypes.Structure):
        # Public proc_bsdinfo from <sys/proc_info.h>; birth time survives
        # reparenting and distinguishes a reused PID down to microseconds.
        _fields_ = [
            (name, ctypes.c_uint32) for name in (
                "flags", "status", "xstatus", "pid", "ppid", "uid", "gid",
                "ruid", "rgid", "svuid", "svgid", "reserved",
            )
        ] + [("comm", ctypes.c_char * 16), ("name", ctypes.c_char * 32),
             ("details", ctypes.c_uint32 * 6),
             ("start_seconds", ctypes.c_uint64), ("start_microseconds", ctypes.c_uint64)]

    libproc = ctypes.CDLL("/usr/lib/libproc.dylib", use_errno=True)
    libproc.proc_pidinfo.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_uint64,
                                   ctypes.c_void_p, ctypes.c_int]
    libproc.proc_pidinfo.restype = ctypes.c_int


def process_identity(pid):
    """Return a live process's UID and kernel birth identity, never its name."""
    if sys.platform == "darwin":
        info = BSDProcessInfo()
        if libproc.proc_pidinfo(pid, 3, 0, ctypes.byref(info), ctypes.sizeof(info)) != ctypes.sizeof(info):
            return None
        return None if info.status == 5 else (info.uid, info.start_seconds, info.start_microseconds)
    try:
        with open(f"/proc/{pid}/stat") as handle:
            fields = handle.read().rsplit(")", 1)[1].split()
        return None if fields[0] == "Z" else (os.stat(f"/proc/{pid}").st_uid, int(fields[19]))
    except FileNotFoundError:
        return None


def stop_executable(executable):
    """Stop only current-user processes whose executable matches exactly."""
    def matching():
        listing = subprocess.check_output(
            ["/bin/ps", "-axo", "pid=,uid=,comm="], text=True, timeout=5,
        )
        result = set()
        for line in listing.splitlines():
            fields = line.split(None, 2)
            if len(fields) == 3 and int(fields[1]) == os.getuid() and fields[2] == executable:
                result.add(int(fields[0]))
        return result

    owned = matching()
    for number in (signal.SIGTERM, signal.SIGKILL):
        for pid in owned & matching():
            try:
                os.kill(pid, number)
            except ProcessLookupError:
                pass
        deadline = time.monotonic() + 2
        while owned & matching():
            if time.monotonic() >= deadline:
                break
            time.sleep(0.05)
        else:
            return 0
    print(f"Cleanup could not stop owned executable: {executable}", file=sys.stderr)
    return 1


def main():
    arguments = sys.argv[1:]
    if arguments[:1] == ["--stop-executable"]:
        return stop_executable(arguments[1])
    timeout = None
    grace = 2.0
    if arguments[:1] == ["--grace"]:
        grace = float(arguments[1])
        arguments = arguments[2:]
    if arguments[:1] == ["--timeout"]:
        timeout = float(arguments[1])
        arguments = arguments[2:]
    if arguments[:1] == ["--"]:
        arguments = arguments[1:]
    child = None
    pending_signal = None

    def signal_group(number):
        try:
            os.killpg(child.pid, number)
        except ProcessLookupError:
            pass
        except PermissionError:
            # Darwin can leave an orphan-zombie group that cannot be signaled.
            # Suppress EPERM only when no live member remains in our group.
            states = subprocess.check_output(
                ["/bin/ps", "-axo", "pgid=,stat="], text=True, timeout=5,
            )
            for line in states.splitlines():
                fields = line.split()
                if len(fields) == 2 and int(fields[0]) == child.pid and not fields[1].startswith("Z"):
                    raise

    def session_members():
        # SwiftPM workers can create separate process groups while remaining
        # in the session established by our Popen(start_new_session=True).
        listing = subprocess.check_output(["/bin/ps", "-axo", "pid=,uid="], text=True, timeout=5)
        members = {}
        for line in listing.splitlines():
            pid, uid = map(int, line.split())
            if uid != os.getuid():
                continue
            try:
                if os.getsid(pid) == child.pid:
                    identity = process_identity(pid)
                    if identity is not None and identity[0] == uid:
                        members[pid] = identity
            except ProcessLookupError:
                pass
        return members

    def live_member(pid, identity):
        try:
            return process_identity(pid) == identity and os.getsid(pid) == child.pid
        except ProcessLookupError:
            return False

    def signal_members(members, number):
        for pid, identity in members.items():
            if live_member(pid, identity):
                try:
                    if number == signal.SIGTERM and os.getpgid(pid) == child.pid:
                        continue  # The group signal already reached this process.
                    # Signal individual owned identities, never an escaped
                    # worker's group, which could include a caller's process.
                    os.kill(pid, number)
                except ProcessLookupError:
                    pass

    def stop():
        if child is None:
            return
        members = {}
        query_failure = None

        def refresh_members():
            nonlocal query_failure
            try:
                members.update(session_members())
            except Exception as error:
                # Preserve the failure status while later bounded attempts can
                # still discover workers missed by a transient query failure.
                if query_failure is None:
                    query_failure = error

        refresh_members()
        signal_group(signal.SIGTERM)
        signal_members(members, signal.SIGTERM)
        deadline = time.monotonic() + grace
        while (child.poll() is None or any(live_member(pid, identity) for pid, identity in members.items())) \
                and time.monotonic() < deadline:
            time.sleep(0.05)
        # Descendants can outlive the direct child; kill the owned group even
        # when that child already exited, then reap the direct child.
        signal_group(signal.SIGKILL)
        refresh_members()
        signal_members(members, signal.SIGKILL)
        child.wait()
        deadline = time.monotonic() + 2
        while True:
            refresh_members()
            members = {pid: identity for pid, identity in members.items() if live_member(pid, identity)}
            if not members:
                break
            if time.monotonic() >= deadline:
                raise ChildProcessError("Owned session workers did not stop")
            signal_members(members, signal.SIGKILL)
            time.sleep(0.05)
        if query_failure is not None:
            raise ChildProcessError(f"Could not verify owned session cleanup: {query_failure}") from query_failure

    def interrupted(number, _frame):
        nonlocal pending_signal
        pending_signal = number

    for caught in (signal.SIGHUP, signal.SIGINT, signal.SIGTERM):
        signal.signal(caught, interrupted)
    try:
        child = subprocess.Popen(arguments, start_new_session=True)
        deadline = None if timeout is None else time.monotonic() + timeout
        try:
            while child.poll() is None:
                if pending_signal is not None:
                    return 128 + pending_signal
                if deadline is not None and time.monotonic() >= deadline:
                    return 124
                time.sleep(0.05)
            status = child.returncode
        finally:
            stop()
        return status if status >= 0 else 128 - status
    except OSError as error:
        print(f"owned command failed: {error}", file=sys.stderr)
        return 127


if __name__ == "__main__":
    sys.exit(main())
