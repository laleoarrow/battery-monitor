#!/usr/bin/env python3
"""Owned-copy loopback VZ VNC; exact executable and native cursor gates."""
from pathlib import Path, PurePosixPath
from datetime import datetime, timezone
import argparse, hashlib, importlib.util, json, math, os, shlex, signal, socket, stat, subprocess, time, uuid

BASE = Path(__file__).resolve().parent
FROZEN = BASE / 'slow_vnc_7c6866aa.py'
assert hashlib.sha256(FROZEN.read_bytes()).hexdigest() == '7c6866aa9fb1292c260dc694962211968bb18c7a85f693344fb405eb29f04cbe'
spec = importlib.util.spec_from_file_location('frozen_guest_rfb', FROZEN)
rfb = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rfb)
require = rfb.require
GUEST_FROZEN = BASE / 'guest_calibrated_7c8aac80.py'
assert hashlib.sha256(GUEST_FROZEN.read_bytes()).hexdigest() == '7c8aac8000637ac46472ad29915aad80a6942d559bbf9a0477e444aeb396c0bd'
spec = importlib.util.spec_from_file_location('frozen_guest_cursor', GUEST_FROZEN)
guest_cursor = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guest_cursor)
PROBE = guest_cursor.shared.PROBE
OWNED_COPY_ROOT = BASE.parent / 'loopback-vz'
TART = '/opt/homebrew/bin/tart'


def peer_guard(owner, lease):
    require(owner['vncBackend'] == 'directVZ' and owner['vncHost'] in ('127.0.0.1', '::1'), 'Only directVZ literal loopback is allowed')
    require(type(owner['vncPort']) is int and 1024 <= owner['vncPort'] <= 65535, 'Invalid owned VNC port')
    require(type(owner['vncListenerPID']) is int and owner['vncListenerPID'] > 1, 'Missing owned listener PID')
    require(owner['ownedVM'].startswith('Wattson-NormalSlowDrag-'), 'Unexpected owned VM name')
    uuid.UUID(owner['platformUUID'])
    for key in ('ownedVM', 'platformUUID', 'guestIP'):
        require(owner[key] == lease[key], 'Owner/guest VM identity mismatch')
    require(owner['hwModel'].startswith('VirtualMac') and lease['hwModel'].startswith('VirtualMac'), 'Not a VirtualMac')
    require(lease['inputAuthorized'] is True, 'Guest input authorization missing')
    age = (datetime.now(timezone.utc) - datetime.fromisoformat(lease['atUTC'].replace('Z', '+00:00'))).total_seconds()
    require(-1 <= age <= 30, 'Guest lease is stale or exceeds one-second clock skew')


def listener_output_guard(owner, command, listing):
    words = shlex.split(command)
    executable = PurePosixPath(owner['vncExecutablePath'])
    require(executable.is_absolute() and '..' not in executable.parts
            and executable.is_relative_to(OWNED_COPY_ROOT), 'VNC executable is outside owned Tart copy')
    require(words and words[0] == str(executable) and 'run' in words and owner['ownedVM'] in words,
            'Listener process is not the exact owned Tart copy and VM')
    require(all(flag in words for flag in ('--vnc-experimental', '--no-graphics', '--no-audio', '--no-clipboard')),
            'Owned Tart isolation flags are missing')
    pids = [int(line[1:]) for line in listing.splitlines() if line.startswith('p')]
    names = [line[1:] for line in listing.splitlines() if line.startswith('n')]
    port = str(owner['vncPort'])
    expected = ('[::1]:' if owner['vncHost'] == '::1' else '127.0.0.1:') + port
    require(pids == [owner['vncListenerPID']] and names and expected in names
            and all(name in ('127.0.0.1:' + port, '[::1]:' + port) for name in names),
            'VNC listener is missing, foreign, or not loopback-only')


def listener_guard(owner):
    pid, port = str(owner['vncListenerPID']), str(owner['vncPort'])
    command = subprocess.check_output(['/bin/ps', '-p', pid, '-o', 'command='], text=True, timeout=3)
    listing = subprocess.check_output(['/usr/sbin/lsof', '-nP', '-a', '-p', pid, '-iTCP:' + port, '-sTCP:LISTEN', '-Fpn'], text=True, timeout=3)
    listener_output_guard(owner, command, listing)


def private_password(path):
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    try:
        info = os.fstat(fd)
        require(stat.S_ISREG(info.st_mode) and stat.S_IMODE(info.st_mode) == 0o600
                and info.st_uid == os.geteuid() and info.st_nlink == 1, 'Password file must be private owned regular 0600')
        value = os.read(fd, 257)
        require(1 <= len(value) <= 256 and all(32 <= b <= 126 for b in value), 'Invalid private VZ password file')
        # Security type 2 uses the first eight bytes, per RFC 6143 + EID 4951.
        return value[:8]
    finally:
        os.close(fd)


def state_guard(owner, lease, state_bytes, kind):
    peer_guard(owner, lease)
    require(hashlib.sha256(state_bytes).hexdigest() == lease['stateSHA256'], 'Frozen state hash mismatch')
    state = json.loads(state_bytes)
    plan = state['inputTargets'][kind]
    require(lease['executablePath'].startswith(rfb.PREFIX) and '..' not in PurePosixPath(lease['executablePath']).parts,
            'Target executable is outside owned guest fixture')
    require(lease['bundleID'].startswith('com.leoarrow.wattson.modules-slow.'), 'Unexpected fixture bundle')
    require(type(lease['pid']) is int and lease['pid'] > 1 and type(lease['windowID']) is int and lease['windowID'] > 0,
            'Invalid fixture PID/window')
    require(lease['frontmostPID'] == lease['pid'] and state['visible'] and state['keyWindow'] and state['pressedMouseButtons'] == 0,
            'Fixture is not foreground/button-up')
    for key in ('pid', 'bundleID', 'windowID'):
        require(plan[key] == state[key] == lease[key], 'Fixture identity mismatch')
    require(plan['hardwareUUID'] == state['hardwareUUID'] == owner['platformUUID'], 'Fixture UUID mismatch')
    window = lease['window']
    require(window['kCGWindowNumber'] == lease['windowID'] and window['kCGWindowOwnerPID'] == lease['pid'], 'Window ownership mismatch')
    require(all(window[key] == state['cgWindow'][key] for key in ('kCGWindowNumber', 'kCGWindowOwnerPID', 'kCGWindowBounds')),
            'Frozen CG window mismatch')
    geometry = lease['inputGeometry']
    require(all(geometry[key] == state['inputGeometry'][key] for key in ('coordinateSpace', 'displayID', 'screenCount', 'displayBoundsCG', 'screenFrameAppKit')),
            'Display geometry mismatch')
    require(plan['duration'] == 1.5 and plan['holdBefore'] == 0.3 and plan['holdAfter'] == 0.5, 'Unexpected drag timing')
    return plan, geometry, window['kCGWindowBounds']


def cursor_probe(owner, path, report):
    return guest_cursor.cursor_probe(owner, path, report)


def calibrate(client, owner, lease, geometry, framebuffer, point, probe_path, report):
    require(geometry['coordinateSpace'] == 'CG-global-top-left' and geometry['screenCount'] == 1, 'Single verified guest display required')
    x, y, width, height = geometry['displayBoundsCG']
    # Calibration is move-only, so its permitted source rectangle is the display.
    plan = {'source': point, 'target': point}
    mapped, scale = rfb.mapped_points(plan, geometry, {'X': x, 'Y': y, 'Width': width, 'Height': height}, framebuffer)
    before = cursor_probe(owner, probe_path, report)
    def distance(a, b):
        return max(abs(float(a[key]) - float(b[key])) for key in ('x', 'y'))
    candidates = [{'x': x + width * fx, 'y': y + height * fy}
                  for fx in (0.25, 0.5, 0.75) for fy in (0.25, 0.5, 0.75)]
    waypoint = next((p for p in candidates if distance(p, point) >= 8 and distance(p, before['pointerCG']) >= 8), None)
    require(waypoint is not None, 'No distinct interior calibration waypoint')
    waypoint_mapped, _ = rfb.mapped_points({'source': waypoint, 'target': waypoint}, geometry,
                                          {'X': x, 'Y': y, 'Width': width, 'Height': height}, framebuffer)
    proof = {'requestedCGPoint': point, 'mappedRFBPoint': mapped[0], 'geometryScale': scale, 'before': before,
             'waypointCGPoint': waypoint, 'mappedWaypoint': waypoint_mapped[0], 'passed': False, 'mouseDownMessages': 0}
    report['calibration'] = proof
    for stage, target, rfb_point in [('waypoint', waypoint, waypoint_mapped[0]), ('source', point, mapped[0])]:
        peer_guard(owner, lease)
        listener_guard(owner)
        client.pointer(0, rfb_point)
        time.sleep(0.2)
        observed = cursor_probe(owner, probe_path, report)  # Socket stays open for both readbacks.
        error = distance(observed['pointerCG'], target)
        proof[stage + 'Readback'] = observed
        proof[stage + 'MaxLogicalPointError'] = error
        require(error <= 1, 'Move-only native cursor calibration failed; no down permitted')
    proof.update(afterWhileSocketOpen=proof['sourceReadback'], maxLogicalPointError=proof['sourceMaxLogicalPointError'],
                 observedMovement=True, passed=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('owner', 'lease', 'password', 'report'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--cursor-probe', default=PROBE)
    parser.add_argument('--state', type=Path)
    parser.add_argument('--kind', choices=('drop', 'outside'))
    parser.add_argument('--preflight', action='store_true')
    parser.add_argument('--calibrate-point', type=float, nargs=2)
    args = parser.parse_args()
    require(sum([args.preflight, args.calibrate_point is not None, args.state is not None]) == 1, 'Choose auth-only, calibration-only, or frozen drag state')
    require(args.state is None or args.kind is not None, 'Drag kind is missing')
    require(not args.report.exists() and not args.report.is_symlink(), 'Report already exists')
    report = {'inputMethod': 'owned-copy-loopback-directVZ-VNC', 'hostInput': False, 'inputAttempted': False,
              'sequencePosted': False, 'nativeDragVerdict': 'observer-required', 'events': []}
    stream = client = None
    status = 78
    numbers = (signal.SIGHUP, signal.SIGINT, signal.SIGTERM)
    def interrupted(number, frame):
        raise SystemExit(128 + number)
    previous = {number: signal.signal(number, interrupted) for number in numbers}
    try:
        owner, lease = json.loads(args.owner.read_bytes()), json.loads(args.lease.read_bytes())
        report.update(leaseAtUTC=lease['atUTC'], leaseSignedAgeAtCheck=guest_cursor.signed_age(lease['atUTC']), clockSkewToleranceSeconds=1)
        peer_guard(owner, lease)
        listener_guard(owner)
        if args.state is not None:
            plan, geometry, window = state_guard(owner, lease, args.state.read_bytes(), args.kind)
        else:
            geometry = lease['inputGeometry']
        password = private_password(args.password)
        endpoint = (owner['vncHost'], owner['vncPort'])
        stream = socket.socket(socket.AF_INET6 if endpoint[0] == '::1' else socket.AF_INET, socket.SOCK_STREAM)
        stream.settimeout(3)
        stream.connect(endpoint)
        require(stream.getpeername()[:2] == endpoint, 'RFB peer does not match owned VZ listener')
        client = rfb.RFB(stream, report['events'])
        framebuffer = client.handshake(password)
        del password
        report.update(framebufferSize=list(framebuffer), ownedVM=owner['ownedVM'], platformUUID=owner['platformUUID'],
                      vncListenerPID=owner['vncListenerPID'], vncHost=owner['vncHost'], vncPort=owner['vncPort'],
                      vncExecutablePath=owner['vncExecutablePath'])
        if args.preflight:
            report['preflightCompleted'] = True
        else:
            point = dict(zip(('x', 'y'), args.calibrate_point)) if args.calibrate_point else plan['source']
            report['inputAttempted'] = True
            calibrate(client, owner, lease, geometry, framebuffer, point, args.cursor_probe, report)
            if args.state is not None:
                peer_guard(owner, lease)
                listener_guard(owner)
                points, scale = rfb.mapped_points(plan, geometry, window, framebuffer)
                report.update(geometryScale=scale, mappedPoints=points, case=plan['caseName'], pid=plan['pid'], windowID=plan['windowID'])
                rfb.drag(client, points)
                report['sequencePosted'] = True
            else:
                report['calibrationOnlyCompleted'] = True
        status = 0
    except BaseException as error:
        status = error.code if isinstance(error, SystemExit) and isinstance(error.code, int) else 78
        report['errorType'] = type(error).__name__
        report['error'] = str(error) if isinstance(error, ValueError) else 'Input operation did not complete'
    finally:
        for number in numbers:
            signal.signal(number, signal.SIG_IGN)
        if client is not None:
            client.release(report)
        try:
            if stream is not None:
                try:
                    stream.close()
                except OSError:
                    report['socketCloseError'] = True
                    if status == 0:
                        status = 78
            report.update(socketClosed=not report.get('socketCloseError', False), exitCode=status)
            with args.report.open('x') as output:
                json.dump(report, output, indent=2)
                output.write('\n')
        finally:
            for number, handler in previous.items():
                signal.signal(number, handler)
    return status


if __name__ == '__main__':
    raise SystemExit(main())
