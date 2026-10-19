#!/usr/bin/env python3
"""Own the GUI fixture process and validate its own-window compositor outputs."""
import json
import pathlib
import signal
import subprocess
import sys
import time


def interrupted(number, _frame):
    raise SystemExit(128 + number)


for watched in (signal.SIGINT, signal.SIGHUP, signal.SIGTERM):
    signal.signal(watched, interrupted)

executable = pathlib.Path(sys.argv[1])
directory = pathlib.Path(sys.argv[2])
directory.mkdir(parents=True, exist_ok=True)
process = None
try:
    with (directory / 'fixture.log').open('w') as out, (directory / 'fixture.err').open('w') as err:
        process = subprocess.Popen([str(executable), str(directory), *sys.argv[3:]], stdout=out, stderr=err)
        started = time.monotonic()
        captures = []
        while process.poll() is None:
            if time.monotonic() - started > 180:
                raise TimeoutError('Display capture exceeded 180 seconds')
            captures = sorted(path.stem for path in directory.glob('*.png'))
            time.sleep(.05)
        assert process.returncode == 0, (process.returncode, (directory / 'fixture.err').read_text())
        captures = sorted(path.stem for path in directory.glob('*.png'))
        for target in directory.glob('*.png'):
            assert target.stat().st_size > 1000 and target.read_bytes().startswith(b'\x89PNG\r\n\x1a\n'), target
        expected = 2 if '--native-selected' in sys.argv else (4 if '--before' in sys.argv else 8)
        assert len(captures) == expected, captures
        assert f'DISPLAY_CAPTURE_COMPLETE count={expected}' in (directory / 'fixture.log').read_text()
        (directory / 'capture-results.json').write_text(json.dumps({
            'schema': 1, 'allPassed': True, 'captureCount': len(captures), 'captures': captures,
            'method': 'Actual SettingsWindowController NSWindow; ScreenCaptureKit currentProcess own-window WindowServer capture without TCC consent in disposable GUI VM; no AppKit bitmap approximation.',
        }, indent=2) + '\n')
finally:
    if process is not None and process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)
