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

    def test_mode_readback_comes_from_pmset_live(self):
        # The preferences plist is lazily written and can lag by a whole mode
        # transition. A verified reply must come from the live value instead.
        self.assertIn('arguments = ["-g", "live"]', self.source)
        self.assertIn('"modeVerified":true', self.source)
        self.assertIn("livePowerMode()", self.source)

    def test_each_request_reads_the_live_mode_only_once(self):
        # A live read costs about 76 ms on the target machine. getMode and
        # setMode must pass that one result into support detection instead of
        # spawning pmset twice.
        self.assertIn("supportsHighPower(current:", self.source)
        get_mode = self.source.split('case "getMode":', 1)[1].split('case "setMode":', 1)[0]
        set_mode = self.source.split('case "setMode":', 1)[1].split(
            'case "getSystemBatteryIconHidden":', 1
        )[0]
        self.assertEqual(get_mode.count("livePowerMode()"), 1)
        self.assertEqual(set_mode.count("livePowerMode()"), 1)

    def test_rejects_anything_outside_the_whitelist(self):
        self.assertIn('case "getMode"', self.source)
        self.assertIn('case "setMode"', self.source)
        self.assertIn('case "getSystemBatteryIconHidden"', self.source)
        self.assertIn('case "setSystemBatteryIconHidden"', self.source)
        self.assertIn("default:", self.source)
        self.assertIn("os_log", self.source)

    def test_system_battery_visibility_uses_fixed_control_center_values(self):
        # 8 keeps Battery in Control Center but removes it from the menu bar;
        # 18 restores it to both. The request supplies only a Boolean.
        self.assertIn('"com.apple.controlcenter"', self.source)
        self.assertIn("hidden ? 8 : 18", self.source)
        self.assertIn("CFPreferencesSetValue", self.source)
        self.assertIn("CFPreferencesSynchronize", self.source)

    def test_control_center_is_restarted_in_the_console_user_domain(self):
        self.assertIn('"/usr/bin/pkill", "-TERM", "-U"', self.source)
        self.assertIn('"\\(uid)", "-x", "ControlCenter"', self.source)
        self.assertIn("launchctl kickstart is rejected by SIP", self.source)

    def test_never_interpolates_input_into_a_command(self):
        for forbidden in ("\\(value)", "\\(op)", "\\(request", "/bin/sh", "-c\""):
            self.assertNotIn(forbidden, self.source)


if __name__ == "__main__":
    unittest.main()
