#!/usr/bin/python3
"""One-use, memory-only askpass for the already authorized public 5.0.3 PKG."""
import getpass
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import socket
import subprocess
import sys
import threading
import warnings

ROOT = Path(__file__).resolve().parents[3]
PACKAGE = ROOT / "dist/public-v5.0.3-verify/Wattson-v5.0.3-macos-universal.pkg"
ASKPASS = '''#!/usr/bin/python3
import os, socket, sys
os.chdir(os.path.dirname(os.path.abspath(__file__)))
try:
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
        connection.settimeout(10)
        connection.connect("credential.sock")
        connection.sendall(b"wattson-askpass-v1\\n")
        with connection.makefile("rb") as response:
            value = response.read()
        if not value:
            raise OSError("No credential")
        sys.stdout.buffer.write(value + b"\\n")
        sys.stdout.buffer.flush()
except OSError:
    sys.exit(1)
'''


def verify_package(expected):
    if (re.fullmatch(r"[0-9a-f]{64}", expected) is None or PACKAGE.is_symlink()
            or PACKAGE.parent.is_symlink() or not PACKAGE.is_file()
            or hashlib.sha256(PACKAGE.read_bytes()).hexdigest() != expected):
        raise RuntimeError("Exact retained public PKG/digest verification failed")


def interrupt(number, _frame):
    raise InterruptedError("Installation interrupted")


def root_install(expected):
    if os.geteuid() != 0:
        raise RuntimeError("Privileged install mode requires sudo")
    verify_package(expected)
    # Executing the existing owner as root lets it stop/reap privileged
    # installer descendants on timeout, failure and catchable interruption.
    os.execv("/usr/bin/python3", ["/usr/bin/python3", str(ROOT / "scripts/lib/run_owned.py"),
        "--grace", "20", "--timeout", "420", "--", "/usr/sbin/installer",
        "-pkg", str(PACKAGE), "-target", "/"])


def main(expected, scratch, results):
    verify_package(expected)
    scratch, results = Path(scratch).resolve(), Path(results).resolve()
    if (os.geteuid() == 0 or not os.isatty(0)
            or os.stat("/dev/console").st_uid != os.getuid()
            or scratch.parent != ROOT / ".build/public-install-v5.0.3.noindex"
            or scratch.stat().st_mode & 0o777 != 0o700
            or results.parent != Path(__file__).resolve().parent
            or results.stat().st_mode & 0o777 != 0o700):
        raise RuntimeError("Console-user private-scratch/TTY precondition failed")
    for caught in (signal.SIGHUP, signal.SIGINT, signal.SIGTERM):
        signal.signal(caught, interrupt)
    signal.signal(signal.SIGALRM, interrupt)
    warnings.simplefilter("error", getpass.GetPassWarning)
    secret, child, listener, thread = bytearray(), None, None, None
    stopped = threading.Event()
    status, delivered, timestamp_cleared = 1, [], False
    try:
        signal.alarm(120)
        secret = bytearray(getpass.getpass("macOS administrator password (input hidden): ").encode())
        signal.alarm(0)
        if not secret:
            raise RuntimeError("No administrator credential supplied")
        reader = scratch / "askpass"
        reader.write_text(ASKPASS)
        reader.chmod(0o700)
        # Relative socket paths avoid Darwin's short sockaddr_un path limit.
        os.chdir(scratch)
        listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        listener.bind("credential.sock")
        os.chmod("credential.sock", 0o600)
        listener.listen(1)
        listener.settimeout(0.2)

        def serve_once():
            try:
                while not stopped.is_set():
                    try:
                        connection, _ = listener.accept()
                    except socket.timeout:
                        continue
                    with connection:
                        connection.settimeout(2)
                        request = bytearray()
                        while len(request) < len(b"wattson-askpass-v1\n"):
                            part = connection.recv(len(b"wattson-askpass-v1\n") - len(request))
                            if not part:
                                break
                            request.extend(part)
                        if request == b"wattson-askpass-v1\n":
                            connection.sendall(secret)
                            delivered.append(True)
                    return
            except OSError:
                pass
            finally:
                secret[:] = b"\0" * len(secret)
                listener.close()

        thread = threading.Thread(target=serve_once, daemon=True)
        thread.start()
        environment = dict(os.environ, SUDO_ASKPASS=str(reader))
        with (results / "native-installer.log").open("xb") as log:
            child = subprocess.Popen(["/usr/bin/sudo", "-A", "-k", "--", "/usr/bin/python3",
                str(Path(__file__).resolve()), "--root-install", expected],
                stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT,
                env=environment, start_new_session=True)
            status = child.wait(timeout=480)
    except (InterruptedError, KeyboardInterrupt):
        status = 130
    except subprocess.TimeoutExpired:
        status = 124
    finally:
        signal.alarm(0)
        # Cleanup must finish even if a second catchable interruption arrives.
        for caught in (signal.SIGHUP, signal.SIGINT, signal.SIGTERM):
            signal.signal(caught, signal.SIG_IGN)
        if child is not None and child.poll() is None:
            try:
                child.terminate()
            except ProcessLookupError:
                pass
            try:
                child.wait(timeout=30)
            except subprocess.TimeoutExpired:
                try:
                    child.kill()
                except ProcessLookupError:
                    pass
                child.wait(timeout=5)
        stopped.set()
        if thread is not None:
            thread.join(timeout=3)
        if listener is not None:
            listener.close()
        secret[:] = b"\0" * len(secret)
        try:
            invalidation = subprocess.run(["/usr/bin/sudo", "-k"], stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10, start_new_session=True)
            timestamp_cleared = invalidation.returncode == 0
        except (OSError, subprocess.TimeoutExpired):
            timestamp_cleared = False
        if not timestamp_cleared or (thread is not None and thread.is_alive()):
            status = status or 1
        record = {"package": str(PACKAGE), "expectedSHA256": expected,
            "credentialDeliveryCount": len(delivered), "credentialStorage": "memory-only",
            "sudoTimestampInvalidated": timestamp_cleared, "exitCode": status}
        with (results / "install-attempt.json").open("x") as output:
            json.dump(record, output, indent=2)
            output.write("\n")
    return status


if __name__ == "__main__":
    try:
        if len(sys.argv) == 3 and sys.argv[1] == "--root-install":
            root_install(sys.argv[2])
        elif len(sys.argv) == 4:
            sys.exit(main(*sys.argv[1:]))
        else:
            raise RuntimeError("Invalid invocation")
    except Exception as error:
        print(type(error).__name__ + ": authorized install did not complete", file=sys.stderr)
        sys.exit(1)
