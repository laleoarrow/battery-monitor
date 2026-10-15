#!/usr/bin/env python3
"""Run one command in an owned process group and reap it on interruption."""

import os
import signal
import subprocess
import sys
import time


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

    def stop():
        if child is None:
            return
        signal_group(signal.SIGTERM)
        deadline = time.monotonic() + grace
        while child.poll() is None and time.monotonic() < deadline:
            time.sleep(0.05)
        # Descendants can outlive the direct child; kill the owned group even
        # when that child already exited, then reap the direct child.
        signal_group(signal.SIGKILL)
        child.wait()

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
