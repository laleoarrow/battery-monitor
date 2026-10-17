#!/usr/bin/env python3
"""Pinned disposable-guest RFB pointer input. Native observer owns the verdict."""
from pathlib import Path, PurePosixPath
from datetime import datetime, timezone
import argparse, ctypes, hashlib, json, math, os, re, signal, socket, stat, struct, time

VM = 'Wattson-NormalSlowDrag-20261017'
IP = '192.168.64.24'
UUID = '602C7F68-8019-5DD5-ABC9-C96B4696157A'
PREFIX = '/Users/admin/Project/Wattson-NormalSlowDrag-QA/.build/'


def require(condition, message):
    if not condition:
        raise ValueError(message)


def password_file(path):
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    try:
        info = os.fstat(fd)
        require(stat.S_ISREG(info.st_mode) and stat.S_IMODE(info.st_mode) == 0o600
                and info.st_uid == os.geteuid() and info.st_nlink == 1, 'Password file must be private owned regular 0600')
        value = os.read(fd, 32)
        require(1 <= len(value) <= 8 and all(32 <= b <= 126 for b in value), 'Password must be 1–8 printable ASCII bytes without newline')
        return value
    finally:
        os.close(fd)


def des_ecb(key, data):
    require(len(key) == 8 and len(data) % 8 == 0, 'Invalid DES block size')
    crypto = ctypes.CDLL('/usr/lib/system/libcommonCrypto.dylib')
    crypt = crypto.CCCrypt
    crypt.argtypes = [ctypes.c_uint32, ctypes.c_uint32, ctypes.c_uint32, ctypes.c_void_p,
                     ctypes.c_size_t, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_size_t,
                     ctypes.c_void_p, ctypes.c_size_t, ctypes.POINTER(ctypes.c_size_t)]
    crypt.restype = ctypes.c_int32
    key_buffer = ctypes.create_string_buffer(key)
    data_buffer = ctypes.create_string_buffer(data)
    output = ctypes.create_string_buffer(len(data))
    moved = ctypes.c_size_t()
    # SDK CommonCryptor.h: encrypt=0, DES=1, ECB=2; no padding.
    status = crypt(0, 1, 2, key_buffer, 8, None, data_buffer, len(data), output, len(data), ctypes.byref(moved))
    require(status == 0 and moved.value == len(data), 'CommonCrypto DES operation failed')
    return output.raw[:moved.value]


def vnc_response(password, challenge):
    # RFC 6143 verified erratum 4951: reverse each key byte's bits.
    key = bytes(int(f'{b:08b}'[::-1], 2) for b in password[:8].ljust(8, b'\0'))
    require(len(challenge) == 16, 'Invalid VNC challenge')
    return des_ecb(key, challenge)


class RFB:
    def __init__(self, stream, journal):
        self.stream, self.journal = stream, journal
        self.held = False
        self.point = None
        self.ready = False

    def read(self, count):
        data = bytearray()
        while len(data) < count:
            part = self.stream.recv(count - len(data))
            if not part:
                raise ConnectionError('RFB connection closed')
            data.extend(part)
        return bytes(data)

    def handshake(self, password):
        banner = self.read(12)
        require(re.fullmatch(rb'RFB 003\.\d{3}\n', banner) is not None, 'Unsupported RFB banner')
        offered = int(banner[8:11])
        minor = offered if offered in (3, 7, 8) else 3
        self.stream.sendall(f'RFB 003.{minor:03d}\n'.encode())
        if minor == 3:
            require(struct.unpack('>I', self.read(4))[0] == 2, 'Server did not offer classic VNC authentication')
        else:
            count = self.read(1)[0]
            require(count > 0 and 2 in self.read(count), 'Server did not offer classic VNC authentication')
            self.stream.sendall(b'\x02')
        self.stream.sendall(vnc_response(password, self.read(16)))
        require(struct.unpack('>I', self.read(4))[0] == 0, 'VNC authentication failed')
        self.stream.sendall(b'\x01')  # shared ClientInit, no clipboard or keyboard.
        header = self.read(24)
        width, height = struct.unpack('>HH', header[:4])
        name_length = struct.unpack('>I', header[20:24])[0]
        require(width > 0 and height > 0 and name_length <= 65536, 'Invalid RFB ServerInit')
        self.read(name_length)
        self.ready = True
        return width, height

    def pointer(self, mask, point):
        require(self.ready and mask in (0, 1), 'RFB pointer is not initialized')
        self.point = point
        if mask == 1:
            self.held = True  # A partial failed send still requires an up attempt.
        self.journal.append({'mask': mask, 'x': point[0], 'y': point[1],
                             'attemptedAtSystemMonotonic': time.clock_gettime(time.CLOCK_MONOTONIC), 'sent': False})
        self.stream.sendall(struct.pack('>BBHH', 5, mask, *point))
        self.journal[-1]['sent'] = True
        if mask == 0:
            self.held = False

    def release(self, report):
        report['releaseAttempted'] = self.held
        if self.held:
            try:
                self.stream.settimeout(1)
                self.pointer(0, self.point)
                report['releaseSent'] = True
            except BaseException:
                report['releaseSent'] = False


def guard_peer(owner, lease, now=None):
    for data in (owner, lease):
        require(data['ownedVM'] == VM and data['guestIP'] == IP and data['platformUUID'] == UUID,
                'Owned VM lease does not match the pinned guest')
        require(data['hwModel'].startswith('VirtualMac'), 'Lease is not a VirtualMac')
    require(lease['inputAuthorized'] is True, 'Guest input authorization missing')
    age = ((now or datetime.now(timezone.utc)) - datetime.fromisoformat(lease['atUTC'].replace('Z', '+00:00'))).total_seconds()
    require(0 <= age <= 30, 'Guest lease is stale or future-dated')


def guard(owner, lease, state_bytes, kind, now=None):
    guard_peer(owner, lease, now)
    state = json.loads(state_bytes)
    require(hashlib.sha256(state_bytes).hexdigest() == lease['stateSHA256'], 'Frozen state hash mismatch')
    require(lease['executablePath'].startswith(PREFIX) and '..' not in PurePosixPath(lease['executablePath']).parts,
            'Target executable is outside the owned guest fixture')
    plan = state['inputTargets'][kind]
    require(lease['bundleID'].startswith('com.leoarrow.wattson.modules-slow.'), 'Unexpected fixture bundle ID')
    require(type(lease['pid']) is int and lease['pid'] > 1 and type(lease['windowID']) is int and lease['windowID'] > 0,
            'Invalid fixture PID/window')
    require(lease['frontmostPID'] == lease['pid'] and state['visible'] and state['keyWindow'], 'Fixture is not foreground')
    require(state['pressedMouseButtons'] == 0, 'Guest already has a pressed pointer button')
    for key in ('pid', 'bundleID', 'windowID'):
        require(plan[key] == state[key] == lease[key], 'Fixture identity mismatch')
    require(plan['hardwareUUID'] == state['hardwareUUID'] == UUID, 'Fixture hardware UUID mismatch')
    window = lease['window']
    require(window['kCGWindowNumber'] == lease['windowID'] and window['kCGWindowOwnerPID'] == lease['pid'], 'Window ownership mismatch')
    require(all(window[key] == state['cgWindow'][key] for key in ('kCGWindowNumber', 'kCGWindowOwnerPID', 'kCGWindowBounds')),
            'Frozen CG window does not match the lease')
    geometry = lease['inputGeometry']
    require(all(geometry[key] == state['inputGeometry'][key] for key in ('coordinateSpace', 'displayID', 'screenCount', 'displayBoundsCG', 'screenFrameAppKit'))
            and geometry['coordinateSpace'] == 'CG-global-top-left'
            and geometry['screenCount'] == 1, 'Unverified guest display geometry')
    require(plan['duration'] == 1.5 and plan['holdBefore'] == 0.3 and plan['holdAfter'] == 0.5, 'Unexpected fixed drag timing')
    return plan, geometry, window['kCGWindowBounds']


def mapped_points(plan, geometry, window, framebuffer):
    x, y, width, height = map(float, geometry['displayBoundsCG'])
    appkit = list(map(float, geometry['screenFrameAppKit']))
    require(all(math.isfinite(v) for v in (x, y, width, height, *appkit))
            and width > 0 and height > 0 and appkit[2:] == [width, height], 'NSScreen/CG display geometry mismatch')
    sx, sy = framebuffer[0] / width, framebuffer[1] / height
    require(math.isclose(sx, sy, rel_tol=1e-9) and 0 < sx <= 4, 'RFB/display scale is ambiguous')
    points = []
    for name in ('source', 'target'):
        px, py = float(plan[name]['x']), float(plan[name]['y'])
        require(math.isfinite(px) and math.isfinite(py) and x <= px < x + width and y <= py < y + height,
                'Drag point leaves the guest display')
        if name == 'source':
            require(window['X'] <= px < window['X'] + window['Width'] and window['Y'] <= py < window['Y'] + window['Height'], 'Source leaves the owned fixture window')
        point = (round((px - x) * sx), round((py - y) * sy))
        require(0 <= point[0] < framebuffer[0] and 0 <= point[1] < framebuffer[1], 'Mapped pointer exceeds framebuffer')
        points.append(point)
    return points, [sx, sy]


def drag(client, points, clock=time.monotonic, sleep=time.sleep):
    source, target = points
    client.pointer(0, source)
    client.pointer(1, source)
    sleep(0.3)
    start = clock()
    for step in range(1, 61):
        sleep(max(0, start + 1.5 * step / 60 - clock()))
        fraction = step / 60
        client.pointer(1, tuple(round(a + (b - a) * fraction) for a, b in zip(source, target)))
    sleep(0.5)
    client.pointer(0, target)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('owner', 'lease', 'password', 'report'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--state', type=Path)
    parser.add_argument('--kind', choices=('drop', 'outside'))
    parser.add_argument('--preflight', action='store_true', help='Authenticate and read ServerInit only; never posts a pointer message')
    args = parser.parse_args()
    require(args.preflight or args.state is not None and args.kind is not None, 'Input requires frozen state and kind')
    require(not args.report.exists() and not args.report.is_symlink(), 'Report already exists')
    report = {'inputMethod': 'guest-VNC', 'hostInput': False, 'inputAttempted': False,
              'sequencePosted': False, 'nativeDragVerdict': 'observer-required', 'events': []}
    stream = None
    client = None
    status = 78
    numbers = (signal.SIGHUP, signal.SIGINT, signal.SIGTERM)
    def interrupted(number, frame):
        raise SystemExit(128 + number)
    previous = {number: signal.signal(number, interrupted) for number in numbers}
    try:
        owner, lease = json.loads(args.owner.read_bytes()), json.loads(args.lease.read_bytes())
        guard_peer(owner, lease)
        if not args.preflight:
            plan, geometry, window = guard(owner, lease, args.state.read_bytes(), args.kind)
        password = password_file(args.password)
        stream = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        stream.settimeout(3)
        stream.connect((IP, 5900))  # No alternate endpoint, DNS, keyboard or clipboard API.
        require(stream.getpeername()[:2] == (IP, 5900), 'RFB peer is not the pinned guest')
        client = RFB(stream, report['events'])
        framebuffer = client.handshake(password)
        del password
        report['framebufferSize'] = list(framebuffer)
        if args.preflight:
            report['preflightCompleted'] = True
        else:
            points, scale = mapped_points(plan, geometry, window, framebuffer)
            guard_peer(owner, lease)  # Authentication must not outlive the short input lease.
            report.update(geometryScale=scale, mappedPoints=points,
                          case=plan['caseName'], pid=plan['pid'], windowID=plan['windowID'], inputAttempted=True)
            drag(client, points)
            report['sequencePosted'] = True
        status = 0
    except BaseException as error:
        status = error.code if isinstance(error, SystemExit) and isinstance(error.code, int) else 78
        report['errorType'] = type(error).__name__  # Never print credential/server data.
        report['error'] = str(error) if isinstance(error, ValueError) else 'Input sequence did not complete'
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
