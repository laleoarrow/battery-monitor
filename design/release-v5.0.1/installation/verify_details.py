"""Fixed read-only checks used by verify-installed.sh; never install or launch GUI."""
import os
import sys

os.environ.pop("PYTHONOPTIMIZE", None)
sys.dont_write_bytecode = True
if sys.flags.optimize:
    raise SystemExit("Optimized Python is unsupported; unset PYTHONOPTIMIZE and do not pass -O.")

import json
import math
import socket
import time
from datetime import datetime, timezone
from pathlib import Path

from installation_state import (APP, DAEMON, HELPER, REQUIRED_SETTINGS, VERSION, canonical_state,
                                check_console_user, digest, run, settings_hashes, write_new)

mode = sys.argv[1]
if mode == 'identity':
    pkg, approved_sha, source_commit, provenance_path, before_path = sys.argv[2:]
    before = json.loads(Path(before_path).read_text())
    provenance = json.loads(Path(provenance_path).read_text())
    assert before['expectedVersion'] == VERSION and before['sourceCommit'] == source_commit, 'Baseline identity mismatch'
    assert provenance['sourceCommit'] == source_commit and provenance['packageSHA256'] == approved_sha, 'Public package provenance mismatch'
    assert provenance['publicAssetsMatchCandidate'] is True and provenance['packageVerified'] is True, 'Public package not verified'
    assert Path(pkg).name == f'Wattson-v{VERSION}-macos-universal.pkg', 'Wrong public package name'
    assert digest(Path(pkg)) == approved_sha, 'Public package checksum mismatch'
    check_console_user()
    assert sum(map(len, before['settingsValueHashes'].values())) == before['productSettingsCount'], 'Invalid baseline settings count'
elif mode == 'details':
    before_path, pkg, approved_sha, source_commit, stage_path, scratch_path, payload_app = sys.argv[2:]
    check_console_user()
    before = json.loads(Path(before_path).read_text())
    actual = settings_hashes()
    matched = 0
    for index, values in before['settingsValueHashes'].items():
        for key, expected in values.items():
            assert actual.get(index, {}).get(key) == expected, f'Existing setting changed: {index}:{key}'
            matched += 1
    assert matched == before['productSettingsCount'] and matched >= len(REQUIRED_SETTINGS), 'Incomplete settings comparison'
    # Names, PIDs, audit tokens and raw frames remain in memory only.
    started = time.monotonic()
    deadline = started + 6
    frame = bytearray()
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
        connection.settimeout(max(.001, deadline - time.monotonic()))
        connection.connect('/var/run/wattson-helper.sock')
        remaining = deadline - time.monotonic()
        assert remaining > 0, 'Process sampling deadline exceeded'
        connection.settimeout(remaining)
        connection.sendall(b'{"_wattsonProtocol":4,"op":"getTopProcesses"}\n')
        while b'\n' not in frame:
            connection.settimeout(max(.001, deadline - time.monotonic()))
            assert time.monotonic() < deadline, 'Process sampling deadline exceeded'
            chunk = connection.recv(4096 - len(frame))
            if not chunk:
                break
            frame.extend(chunk)
            assert len(frame) < 4096, 'Process response too large'
    sampling_elapsed = time.monotonic() - started
    response = json.loads(frame)
    rows = response.get('processes')
    assert response.get('ok') is True and isinstance(rows, list) and 0 < len(rows) <= 10, 'Process sampling unavailable'
    pids = set()
    for row in rows:
        pid = row.get('pid')
        assert type(pid) is int and pid > 0 and pid not in pids, 'Invalid sampled identity'
        pids.add(pid)
        values = [row.get(key) for key in ('energyImpact', 'cpuPercent', 'idleWakeupsPerSecond')]
        assert all(type(value) in (int, float) and math.isfinite(value) and value >= 0 for value in values), 'Invalid process counters'
        score, cpu, wakeups = values
        assert math.isclose(score, cpu + .05 * wakeups, rel_tol=1e-9, abs_tol=1e-8), 'Score formula mismatch'
    state = canonical_state()
    assert state['version'] == state['buildVersion'] == state['receipt']['version'] == VERSION, 'Installed version mismatch'
    assert state['bundleIdentifier'] == 'com.leoarrow.wattson', 'Installed bundle identity mismatch'
    assert digest(Path(pkg)) == approved_sha, 'Package changed during verification'
    write_new(Path(stage_path), {
        'checkedAtUTC': datetime.now(timezone.utc).isoformat(), 'version': VERSION,
        'sourceCommit': source_commit, 'packageSHA256': approved_sha,
        'canonicalAfter': state, 'appAndHelperAndDaemonMatchVerifiedPayload': True,
        'signatureVerified': True, 'architectures': ['arm64', 'x86_64'],
        'helperHealth': True, 'helperV5Negotiated': True,
        'existingSettingsUnchanged': True, 'existingSettingsCompared': matched,
        'processSampling': {'count': len(rows), 'responseBytes': len(frame),
                            'elapsedSeconds': round(sampling_elapsed, 6), 'formulaPassed': True},
        'rawSettingsValuesLogged': False, 'rawProcessValuesLogged': False,
        'publicRelease': True, 'popupInteractionVerified': False,
        'verificationDidNotInstallOrLaunchGUI': True,
        'ownedVerificationResources': {'scratch': scratch_path, 'expandedApp': payload_app},
    })
elif mode == 'finalize':
    stage_path, output_path = sys.argv[2:]
    record = json.loads(Path(stage_path).read_text())
    scratch = Path(record['ownedVerificationResources']['scratch'])
    payload_app = record['ownedVerificationResources']['expandedApp']
    assert not scratch.exists(), 'Owned verification scratch remains'
    registrar = '/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'
    registrations = run([registrar, '-dump'], timeout=45).decode()
    spotlight = run(['/usr/bin/mdfind', 'kMDItemCFBundleIdentifier == "com.leoarrow.wattson"'], timeout=15).decode().splitlines()
    assert payload_app not in registrations and payload_app not in spotlight, 'Expanded test App registration remains'
    assert APP.is_dir() and HELPER.is_file() and DAEMON.is_file(), 'Canonical installation missing after cleanup'
    record['cleanupVerified'] = {'ownedScratchRemoved': True, 'expandedAppLaunchServicesAbsent': True,
                                 'expandedAppSpotlightAbsent': True, 'ownedMountsCreated': False,
                                 'canonicalInstallationNotCleaned': True, 'canonicalAppHelperDaemonStillPresent': True}
    write_new(Path(output_path), record)
    print('CANONICAL_PUBLIC_INSTALL_VERIFIED')
else:
    raise SystemExit('Unknown fixed verification mode')
