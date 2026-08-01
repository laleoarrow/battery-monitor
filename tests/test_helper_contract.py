import pathlib
import plistlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
HELPER_SOURCE = ROOT / "Helper" / "wattson-helper.swift"
HELPER_PLIST = ROOT / "Helper" / "com.leoarrow.wattson.helper.plist"


class HelperContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = HELPER_SOURCE.read_text(encoding="utf-8")
        with HELPER_PLIST.open("rb") as handle:
            cls.plist = plistlib.load(handle)

    def test_is_socket_activated_not_always_running(self):
        self.assertIn("Sockets", self.plist)
        self.assertNotIn("RunAtLoad", self.plist)
        self.assertNotIn("KeepAlive", self.plist)

    def test_socket_path_matches_the_client(self):
        listener = self.plist["Sockets"]["Listener"]
        self.assertEqual(listener["SockPathName"], "/var/run/wattson-helper.sock")

    def test_helper_exits_when_idle(self):
        self.assertIn("idleTimeout", self.source)
        self.assertIn("exit(0)", self.source)

    def test_verifies_peer_uid_against_console_owner(self):
        self.assertIn("getpeereid", self.source)
        self.assertIn("/dev/console", self.source)

    def test_pmset_arguments_are_constants(self):
        # The whole security argument rests on this: the request selects which
        # constant to run, and no caller-supplied value ever reaches the
        # argument vector.
        for value in ("0", "1", "2"):
            self.assertIn(f'"/usr/bin/pmset", "-a", "powermode", "{value}"', self.source)
        self.assertIn("Mode(rawValue: raw)", self.source)

    def test_rejects_anything_outside_the_whitelist(self):
        self.assertIn('case "getMode"', self.source)
        self.assertIn('case "setMode"', self.source)
        self.assertIn("default:", self.source)
        self.assertIn("os_log", self.source)

    def test_never_interpolates_input_into_a_command(self):
        for forbidden in ("\\(value)", "\\(op)", "\\(request", "/bin/sh", "-c\""):
            self.assertNotIn(forbidden, self.source)


if __name__ == "__main__":
    unittest.main()
