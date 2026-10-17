"""No real listener/VM/UI: synthetic socketpairs and mocked cursor readback."""
from pathlib import Path
from datetime import datetime, timedelta, timezone
from unittest.mock import patch
import copy, importlib.util, json, shlex, signal, socket, sys, tempfile, unittest
import test_slow_vnc as synthetic

BASE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('direct_vz', BASE / 'direct_vz_loopback.py')
direct = importlib.util.module_from_spec(spec)
spec.loader.exec_module(direct)
DRAG = direct.rfb.drag


class Server(synthetic.FakeServer):
    def __init__(self, host='127.0.0.1', **kwargs):
        self.host = host
        super().__init__(**kwargs)

    def connect(self, endpoint):
        assert endpoint == (self.host, 50001)

    def getpeername(self):
        return (self.host, 50001, 0, 0) if self.host == '::1' else (self.host, 50001)


def data():
    owner, lease, state = synthetic.fixture()
    owner.update(vncBackend='directVZ', vncHost='127.0.0.1', vncPort=50001, vncListenerPID=12345,
                 vncExecutablePath=str(direct.OWNED_COPY_ROOT / 'tart.app/Contents/MacOS/tart'))
    return owner, lease, state


class Tests(unittest.TestCase):
    def run_cli(self, server, mode='drag', reached=True, action=None, before_at_source=False):
        with tempfile.TemporaryDirectory(prefix='synthetic-vz.', dir=BASE) as directory:
            root = Path(directory)
            owner, lease, state = data()
            owner['vncHost'] = server.host
            (root / 'owner').write_text(json.dumps(owner))
            (root / 'lease').write_text(json.dumps(lease))
            (root / 'state').write_bytes(state)
            (root / 'password').write_bytes(b'testpass-long-private-passphrase')
            (root / 'password').chmod(0o600)
            argv = ['direct_vz.py', '--owner', str(root / 'owner'), '--lease', str(root / 'lease'),
                    '--password', str(root / 'password'), '--report', str(root / 'report')]
            if mode == 'preflight':
                argv += ['--preflight']
            elif mode == 'calibrate':
                argv += ['--calibrate-point', '320', '240']
            else:
                argv += ['--state', str(root / 'state'), '--kind', 'drop']
            probes = []
            def probe(observed_owner, path, report):
                self.assertFalse(server.closed, 'Cursor was queried after closing RFB')
                self.assertFalse(server.down, 'A down was posted before cursor readback')
                source = {'x': 320, 'y': 240} if mode == 'calibrate' else {'x': 200, 'y': 200}
                initial = source if before_at_source else {'x': 10, 'y': 10}
                point = ({'x': 256, 'y': 192} if len(probes) == 1 else source) if reached and probes else initial
                probes.append(point)
                return {**lease, 'pointerCG': point, 'pressedMouseButtons': 0}
            clock = synthetic.Clock()
            drag = action or (lambda c, p: DRAG(c, p, clock.clock, clock.sleep))
            with patch.object(sys, 'argv', argv), patch.object(direct.socket, 'socket', return_value=server) as create, \
                 patch.object(direct, 'listener_guard'), patch.object(direct, 'cursor_probe', probe), \
                 patch.object(direct.time, 'sleep'), patch.object(direct.rfb, 'drag', drag):
                status = direct.main()
            family = socket.AF_INET6 if server.host == '::1' else socket.AF_INET
            self.assertEqual(create.call_args.args[0], family)
            record = json.loads((root / 'report').read_text())
            return status, record, probes

    def test_calibration_keeps_socket_open_and_never_down(self):
        for host in ('127.0.0.1', '::1'):
            server = Server(host)
            try:
                status, record, probes = self.run_cli(server, 'calibrate')
                self.assertEqual(status, 0)
                self.assertTrue(record['calibrationOnlyCompleted'])
                self.assertEqual(record['calibration']['mappedRFBPoint'], [400, 300])
                self.assertEqual(len(probes), 3)
            finally:
                server.finish()
            self.assertEqual([event[0] for event in server.events], [0, 0])

    def test_ignored_move_prevents_every_down_even_if_already_at_source(self):
        for before_at_source in (False, True):
            server = Server()
            try:
                status, record, _ = self.run_cli(server, reached=False, before_at_source=before_at_source)
                self.assertEqual(status, 78)
                self.assertFalse(record['calibration']['passed'])
                self.assertFalse(record['sequencePosted'])
            finally:
                server.finish()
            self.assertEqual([event[0] for event in server.events], [0])

    def test_drag_only_after_readback(self):
        server = Server()
        try:
            status, record, probes = self.run_cli(server)
            self.assertEqual(status, 0)
            self.assertTrue(record['calibration']['passed'] and record['sequencePosted'])
            self.assertEqual(len(probes), 3)
            self.assertEqual(len(record['events']), 65)
        finally:
            server.finish()
        self.assertEqual([event[0] for event in server.events[:4]], [0, 0, 0, 1])

    def test_preflight_has_no_move_or_cursor_probe(self):
        server = Server()
        try:
            status, record, probes = self.run_cli(server, 'preflight')
            self.assertEqual(status, 0)
            self.assertTrue(record['preflightCompleted'])
            self.assertEqual(probes, [])
            self.assertEqual(record['events'], [])
        finally:
            server.finish()
        self.assertEqual(server.events, [])

    def test_signal_during_drag_releases(self):
        server = Server()
        def interrupt(client, points):
            client.pointer(1, points[0])
            signal.getsignal(signal.SIGTERM)(signal.SIGTERM, None)
        try:
            status, record, _ = self.run_cli(server, action=interrupt)
            self.assertEqual(status, 143)
            self.assertTrue(record['releaseSent'] and record['socketClosed'])
        finally:
            server.finish()
        self.assertEqual([event[0] for event in server.events], [0, 0, 1, 0])

    def test_listener_bind_and_vm_ownership(self):
        owner, _, _ = data()
        command = shlex.quote(owner['vncExecutablePath']) + ' run --vnc-experimental --no-graphics --no-audio --no-clipboard ' + owner['ownedVM']
        direct.listener_output_guard(owner, command, 'p12345\nn127.0.0.1:50001\n')
        owner['vncHost'] = '::1'
        direct.listener_output_guard(owner, command, 'p12345\nn[::1]:50001\n')
        for listing in ['p999\nn[::1]:50001\n', 'p12345\nn*:50001\n', 'p12345\nn0.0.0.0:50001\n',
                        'p12345\nn[::]:50001\n', 'p12345\nn192.168.1.2:50001\n', 'p12345\nn[::1]:50002\n',
                        'p12345\nn127.0.0.1:50001\n', 'p12345\nn[::1]:50001\nn*:50001\n']:
            with self.assertRaises(ValueError):
                direct.listener_output_guard(owner, command, listing)
        with self.assertRaises(ValueError):
            direct.listener_output_guard(owner, command.replace(owner['ownedVM'], 'OtherVM'), 'p12345\nn[::1]:50001\n')

    def test_listener_requires_exact_owned_runtime_path(self):
        owner, _, _ = data()
        tail = ' run --vnc-experimental --no-graphics --no-audio --no-clipboard ' + owner['ownedVM']
        listing = 'p12345\nn127.0.0.1:50001\n'
        direct.listener_output_guard(owner, shlex.quote(owner['vncExecutablePath']) + tail, listing)
        for path in ['/opt/homebrew/bin/tart', str(direct.OWNED_COPY_ROOT / 'other.app/Contents/MacOS/tart')]:
            with self.assertRaises(ValueError):
                direct.listener_output_guard(owner, shlex.quote(path) + tail, listing)
        for path in ['/opt/homebrew/bin/tart', str(direct.OWNED_COPY_ROOT / '../foreign/tart')]:
            wrong_owner = {**owner, 'vncExecutablePath': path}
            with self.assertRaises(ValueError):
                direct.listener_output_guard(wrong_owner, shlex.quote(path) + tail, listing)

    def test_lease_clock_bound_and_reused_guest_cursor_helper(self):
        owner, lease, _ = data()
        for age, accepted in [(-0.167, True), (-1.01, False), (30.01, False)]:
            lease['atUTC'] = (datetime.now(timezone.utc) - timedelta(seconds=age)).isoformat()
            if accepted:
                direct.peer_guard(owner, lease)
            else:
                with self.assertRaises(ValueError):
                    direct.peer_guard(owner, lease)
        report, observed = {}, {'proof': 'cursor'}
        with patch.object(direct.guest_cursor, 'cursor_probe', return_value=observed) as probe:
            self.assertIs(direct.cursor_probe(owner, direct.PROBE, report), observed)
        probe.assert_called_once_with(owner, direct.PROBE, report)

    def test_peer_refuses_other_backend_and_host(self):
        for change in ({'vncBackend': 'hostScreenSharing'}, {'vncHost': '0.0.0.0'}, {'vncHost': 'localhost'},
                       {'vncHost': '192.168.64.24'}, {'vncPort': 590}, {'platformUUID': 'different'}):
            owner, lease, _ = data()
            owner.update(change)
            with self.assertRaises(ValueError):
                direct.peer_guard(owner, lease)

    def test_long_private_password_uses_protocol_prefix_only(self):
        with tempfile.TemporaryDirectory(prefix='private-vz.', dir=BASE) as directory:
            path = Path(directory) / 'secret'
            path.write_bytes(b'testpass-example-passphrase')
            path.chmod(0o600)
            self.assertEqual(direct.private_password(path), b'testpass')
            path.chmod(0o644)
            with self.assertRaises(ValueError):
                direct.private_password(path)


if __name__ == '__main__':
    unittest.main(verbosity=2)
