#!/usr/bin/env python3
"""Owned guest Screen Sharing, explicit empirical wire scale, native cursor gate."""
from pathlib import Path
from datetime import datetime, timezone
import argparse, hashlib, importlib.util, ipaddress, json, math, os, signal, socket, struct, subprocess, time, uuid
from calibration_core import calibrate_moves

BASE = Path(__file__).resolve().parent
FROZEN = BASE / 'direct_vz_20378286.py'
assert hashlib.sha256(FROZEN.read_bytes()).hexdigest() == '203782868882f8e523e149e8cc6cff8b8b16ffc1c424f9f8263a078692f5eb34'
spec = importlib.util.spec_from_file_location('reviewed_vz_helpers', FROZEN)
shared = importlib.util.module_from_spec(spec)
spec.loader.exec_module(shared)
rfb, require = shared.rfb, shared.require


def signed_age(at_utc):
    return (datetime.now(timezone.utc) - datetime.fromisoformat(at_utc.replace('Z', '+00:00'))).total_seconds()


def peer_guard(owner, lease):
    require(owner['vncBackend'] == 'guestScreenSharing', 'Only owned guest Screen Sharing is allowed')
    require(owner['vncHost'] == owner['guestIP'] and owner['vncPort'] == 5900, 'Unexpected guest VNC endpoint')
    address = ipaddress.ip_address(owner['guestIP'])
    require(address.version == 4 and address.is_private and not address.is_loopback
            and not address.is_link_local and not address.is_unspecified, 'Guest must have a literal private NAT IPv4 address')
    require(owner['ownedVM'].startswith('Wattson-NormalSlowDrag-'), 'Unexpected owned VM name')
    uuid.UUID(owner['platformUUID'])
    for key in ('ownedVM', 'platformUUID', 'guestIP'):
        require(owner[key] == lease[key], 'Owner/guest VM identity mismatch')
    require(owner['hwModel'].startswith('VirtualMac') and lease['hwModel'].startswith('VirtualMac'), 'Not a VirtualMac')
    require(lease['inputAuthorized'] is True, 'Guest input authorization missing')
    age = signed_age(lease['atUTC'])
    require(-1 <= age <= 30, 'Guest lease is stale or exceeds one-second clock skew')


def cursor_probe(owner, path, report):
    # Guest-only copy of reviewed 203 probe; tolerate measured <=1s guest clock lead.
    require(path == shared.PROBE, 'Unexpected guest cursor probe path')
    caught = (signal.SIGHUP, signal.SIGINT, signal.SIGTERM)
    previous_mask = signal.pthread_sigmask(signal.SIG_BLOCK, caught)
    try:
        child = subprocess.Popen([shared.TART, 'exec', owner['ownedVM'], path, '--cursor'],
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True,
                                 preexec_fn=lambda: signal.pthread_sigmask(signal.SIG_SETMASK, previous_mask))
    except BaseException:
        signal.pthread_sigmask(signal.SIG_SETMASK, previous_mask)
        raise
    try:
        signal.pthread_sigmask(signal.SIG_SETMASK, previous_mask)
        output, _ = child.communicate(timeout=5)
        require(child.returncode == 0, 'Guest cursor probe failed')
        value = json.loads(output)
        age = signed_age(value['atUTC'])
        value['signedAgeAtReturn'] = age
        value['clockSkewToleranceSeconds'] = 1
        report.setdefault('cursorProbeObservations', []).append(value)
        require(value['ownedVM'] == owner['ownedVM'] and value['platformUUID'] == owner['platformUUID']
                and value['hwModel'].startswith('VirtualMac'), 'Cursor probe VM mismatch')
        require(value['pressedMouseButtons'] == 0, 'Guest pointer is already held')
        require(all(math.isfinite(float(value['pointerCG'][key])) for key in ('x', 'y')), 'Invalid guest cursor coordinates')
        require(-1 <= age <= 5, 'Cursor probe is stale or exceeds one-second clock skew')
        return value
    finally:
        if child.poll() is None:
            try:
                os.killpg(child.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                child.communicate(timeout=1)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(child.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                child.communicate(timeout=1)


def state_guard(owner, lease, state_bytes, kind):
    # Reuse reviewed 203 state checks with this transport's peer validation.
    peer_guard(owner, lease)
    require(hashlib.sha256(state_bytes).hexdigest() == lease['stateSHA256'], 'Frozen state hash mismatch')
    state = json.loads(state_bytes)
    plan = state['inputTargets'][kind]
    require(lease['executablePath'].startswith(rfb.PREFIX) and '..' not in Path(lease['executablePath']).parts, 'Target is outside owned guest fixture')
    require(lease['bundleID'].startswith('com.leoarrow.wattson.modules-slow.'), 'Unexpected fixture bundle')
    require(type(lease['pid']) is int and lease['pid'] > 1 and type(lease['windowID']) is int and lease['windowID'] > 0, 'Invalid fixture PID/window')
    require(lease['frontmostPID'] == lease['pid'] and state['visible'] and state['keyWindow'] and state['pressedMouseButtons'] == 0, 'Fixture is not foreground/button-up')
    for key in ('pid', 'bundleID', 'windowID'):
        require(plan[key] == state[key] == lease[key], 'Fixture identity mismatch')
    require(plan['hardwareUUID'] == state['hardwareUUID'] == owner['platformUUID'], 'Fixture UUID mismatch')
    window = lease['window']
    require(window['kCGWindowNumber'] == lease['windowID'] and window['kCGWindowOwnerPID'] == lease['pid'], 'Window ownership mismatch')
    require(all(window[key] == state['cgWindow'][key] for key in ('kCGWindowNumber', 'kCGWindowOwnerPID', 'kCGWindowBounds')), 'Frozen CG window mismatch')
    geometry = lease['inputGeometry']
    require(all(geometry[key] == state['inputGeometry'][key] for key in ('coordinateSpace', 'displayID', 'screenCount', 'displayBoundsCG', 'screenFrameAppKit')), 'Display geometry mismatch')
    require(plan['duration'] == 1.5 and plan['holdBefore'] == 0.3 and plan['holdAfter'] == 0.5, 'Unexpected drag timing')
    return plan, geometry, window['kCGWindowBounds']


def point_mapper(geometry, framebuffer, mode):
    require(geometry['coordinateSpace'] == 'CG-global-top-left' and geometry['screenCount'] == 1, 'Single verified guest display required')
    x, y, width, height = map(float, geometry['displayBoundsCG'])
    appkit = list(map(float, geometry['screenFrameAppKit']))
    require(all(math.isfinite(v) for v in (x, y, width, height, *appkit)) and width > 0 and height > 0
            and appkit[2:] == [width, height], 'NSScreen/CG geometry mismatch')
    measured = [framebuffer[0] / width, framebuffer[1] / height]
    require(math.isclose(*measured, rel_tol=1e-9) and 0 < measured[0] <= 4, 'Ambiguous framebuffer/display ratio')
    scale = measured[0] if mode == 'display-ratio' else 1
    def mapped(point):
        px, py = float(point['x']), float(point['y'])
        require(math.isfinite(px) and math.isfinite(py) and x <= px < x + width and y <= py < y + height, 'Point leaves guest display')
        value = (round((px - x) * scale), round((py - y) * scale))
        require(0 <= value[0] < framebuffer[0] and 0 <= value[1] < framebuffer[1], 'Wire point exceeds framebuffer')
        return value
    return mapped, measured, scale


def initialize_view(client, framebuffer, report):
    # RFC 6143 7.5.1–3, 7.6.1, 7.7.1: one bounded Raw update (Apple may expand the requested 1x1 to 3x3).
    proof = {'requestedRegion': [0, 0, 1, 1], 'clientMessages': [], 'completed': False, 'budgetSeconds': 3}
    report['viewInitialization'] = proof
    deadline = time.monotonic() + 3
    def remaining():
        value = deadline - time.monotonic()
        require(value > 0, 'Initial framebuffer update exceeded three-second budget')
        client.stream.settimeout(value)
    def read(count):
        data = bytearray()
        while len(data) < count:
            remaining()
            part = client.stream.recv(count - len(data))
            require(bool(part), 'Initial framebuffer update truncated')
            data.extend(part)
        return bytes(data)
    pixel_format = struct.pack('>BBBBHHHBBBxxx', 32, 24, 0, 1, 255, 255, 255, 16, 8, 0)
    try:
        for message in (bytes(4) + pixel_format, struct.pack('>BBHi', 2, 0, 1, 0),
                        struct.pack('>BBHHHH', 3, 0, 0, 0, 1, 1)):
            entry = {'type': message[0], 'bytes': len(message), 'sent': False}
            proof['clientMessages'].append(entry)
            remaining()
            client.stream.sendall(message)
            entry['sent'] = True
        proof['serverMessageType'] = read(1)[0]
        require(proof['serverMessageType'] == 0, 'Expected initial FramebufferUpdate')
        _, count = struct.unpack('>BH', read(3))
        proof['rectangleCount'] = count
        require(count == 1, 'Expected exactly one initial Raw rectangle')
        x, y, width, height, encoding = struct.unpack('>HHHHi', read(12))
        proof['rectangle'] = [x, y, width, height]
        proof['encoding'] = encoding
        require(x == y == encoding == 0 and 1 <= width <= 16 and 1 <= height <= 16
                and width <= framebuffer[0] and height <= framebuffer[1], 'Unexpected initial Raw rectangle')
        pixel_bytes = width * height * 4
        payload = read(pixel_bytes)
        proof.update(completed=True, pixelBytes=pixel_bytes, pixelSHA256=hashlib.sha256(payload).hexdigest())
    finally:
        proof['elapsedSeconds'] = 3 - (deadline - time.monotonic())
        client.stream.settimeout(3)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('owner', 'lease', 'password', 'report'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--wire-scale', choices=('display-ratio', '1'), default='display-ratio')
    parser.add_argument('--cursor-probe', default=shared.PROBE)
    parser.add_argument('--preflight', action='store_true')
    parser.add_argument('--initialize-view', action='store_true')
    parser.add_argument('--calibrate-point', nargs=2, type=float)
    parser.add_argument('--state', type=Path)
    parser.add_argument('--kind', choices=('drop', 'outside'))
    args = parser.parse_args()
    require(sum([args.preflight, args.calibrate_point is not None, args.state is not None]) == 1, 'Choose auth-only, calibration-only, or frozen drag state')
    require(args.state is None or args.kind is not None, 'Drag kind missing')
    require(not args.report.exists() and not args.report.is_symlink(), 'Report already exists')
    report = {'inputMethod': 'guest-VNC-calibrated', 'hostInput': False, 'wireScaleMode': args.wire_scale,
              'inputAttempted': False, 'sequencePosted': False, 'nativeDragVerdict': 'observer-required', 'events': []}
    stream = client = None
    status = 78
    numbers = (signal.SIGHUP, signal.SIGINT, signal.SIGTERM)
    def interrupted(number, frame):
        raise SystemExit(128 + number)
    previous = {number: signal.signal(number, interrupted) for number in numbers}
    try:
        owner, lease = json.loads(args.owner.read_bytes()), json.loads(args.lease.read_bytes())
        report.update(leaseAtUTC=lease['atUTC'], leaseSignedAgeAtCheck=signed_age(lease['atUTC']), clockSkewToleranceSeconds=1)
        peer_guard(owner, lease)
        if args.state is not None:
            state_bytes = args.state.read_bytes()
            plan, geometry, window = state_guard(owner, lease, state_bytes, args.kind)
        else:
            geometry = lease['inputGeometry']
        password = rfb.password_file(args.password)
        endpoint = (owner['guestIP'], 5900)
        stream = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        stream.settimeout(3)
        stream.connect(endpoint)
        require(stream.getpeername()[:2] == endpoint, 'RFB peer is not the owned guest')
        client = rfb.RFB(stream, report['events'])
        framebuffer = client.handshake(password)
        del password
        mapped, measured, scale = point_mapper(geometry, framebuffer, args.wire_scale)
        report.update(ownedVM=owner['ownedVM'], platformUUID=owner['platformUUID'], guestIP=owner['guestIP'],
                      framebufferSize=list(framebuffer), measuredFramebufferScale=measured, chosenWireScale=scale)
        if args.initialize_view:
            initialize_view(client, framebuffer, report)
        if args.preflight:
            report['preflightCompleted'] = True
        else:
            point = dict(zip(('x', 'y'), args.calibrate_point)) if args.calibrate_point else plan['source']
            mapped(point)
            if args.state is not None:
                require(window['X'] <= point['x'] < window['X'] + window['Width'] and window['Y'] <= point['y'] < window['Y'] + window['Height'], 'Source leaves owned fixture window')
                mapped(plan['target'])
            report['inputAttempted'] = True
            calibrate_moves(client, point, geometry['displayBoundsCG'], mapped,
                            lambda: cursor_probe(owner, args.cursor_probe, report), lambda: peer_guard(owner, lease), report)
            if args.state is not None:
                state_guard(owner, lease, state_bytes, args.kind)
                points = [mapped(plan[name]) for name in ('source', 'target')]
                report.update(mappedPoints=points, case=plan['caseName'], pid=plan['pid'], windowID=plan['windowID'])
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
