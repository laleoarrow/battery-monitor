import hashlib
import json
import math
import os
import plistlib
import socket
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

evidence, pkg, approved_sha, source_commit = sys.argv[1:]
evidence = Path(evidence)
before = json.loads((evidence / 'before.json').read_text())
assert before['expectedVersion'] == '4.3.20', 'Unexpected baseline version'
assert before['sourceCommit'] == source_commit, 'Source baseline mismatch'
assert os.stat('/dev/console').st_uid == os.getuid(), 'Must run as console user'
paths = {
    '0': Path.home() / 'Library/Containers/com.leoarrow.wattson/Data/Library/Preferences/com.leoarrow.wattson.plist',
    '1': Path.home() / 'Library/Preferences/com.leoarrow.wattson.plist',
}
matched_settings = 0
for index, expected in before['settingsValueHashes'].items():
    assert index in paths, 'Unknown baseline preference location'
    actual = plistlib.loads(paths[index].read_bytes())
    for key, expected_hash in expected.items():
        assert key in actual, 'An existing setting was removed'
        digest = hashlib.sha256(plistlib.dumps(actual[key], fmt=plistlib.FMT_BINARY)).hexdigest()
        assert digest == expected_hash, 'An existing setting changed'
        matched_settings += 1

# Fixed, single native-sampling read. Names, PIDs, and raw frames never leave memory.
started = time.monotonic()
deadline = started + 6.0
with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
    connection.settimeout(max(0.001, deadline - time.monotonic()))
    connection.connect('/var/run/wattson-helper.sock')
    connection.sendall(b'{"_wattsonProtocol":4,"op":"getTopProcesses"}\n')
    frame = bytearray()
    while b'\n' not in frame:
        remaining = deadline - time.monotonic()
        assert remaining > 0, 'Process sampling deadline exceeded'
        connection.settimeout(remaining)
        chunk = connection.recv(4096 - len(frame))
        if not chunk:
            break
        frame.extend(chunk)
        assert len(frame) < 4096, 'Process sampling response exceeds bound'
elapsed = time.monotonic() - started
reply = json.loads(frame)
assert reply.get('ok') is True, 'Native process sampling unavailable'
rows = reply.get('processes')
assert isinstance(rows, list) and len(rows) <= 10, 'Invalid process row count'
seen = set()
for row in rows:
    assert isinstance(row, dict), 'Invalid process row'
    pid = row.get('pid')
    assert type(pid) is int and pid > 0 and pid not in seen, 'Invalid process identity'
    seen.add(pid)
    values = [row.get(key) for key in ('energyImpact', 'cpuPercent', 'idleWakeupsPerSecond')]
    assert all(type(value) in (int, float) and math.isfinite(value) and value >= 0 for value in values), 'Invalid process counters'
    score, cpu, wakeups = values
    assert math.isclose(score, cpu + 0.05 * wakeups, rel_tol=1e-9, abs_tol=1e-8), 'Activity Score formula mismatch'
package_digest = hashlib.sha256(Path(pkg).read_bytes()).hexdigest()
assert package_digest == approved_sha, 'Package changed during verification'
record = dict(
    checkedAtUTC=datetime.now(timezone.utc).isoformat(),
    version='4.3.20', sourceCommit=source_commit, packageSHA256=package_digest,
    appAndHelperAndDaemonMatchVerifiedPayload=True,
    receiptVersion='4.3.20', signatureVerified=True,
    architectures=['arm64', 'x86_64'], helperHealth=True, helperV5=True,
    existingSettingsUnchanged=True, existingSettingsCompared=matched_settings,
    processSampling=dict(count=len(rows), elapsedSeconds=round(elapsed, 6),
                         responseBytes=len(frame), formulaPassed=True),
    publicRelease=False,
)
with (evidence / 'local-install-verified.json').open('x') as destination:
    destination.write(json.dumps(record, indent=2) + '\n')
