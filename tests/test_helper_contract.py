import pathlib
import plistlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
HELPER_SOURCE = ROOT / "Helper" / "wattson-helper.swift"
HELPER_PLIST = ROOT / "Helper" / "com.leoarrow.wattson.helper.plist"
CLIENT_SOURCE = ROOT / "Core" / "HelperClient.swift"
APP_MAIN_SOURCE = ROOT / "main.swift"
PACKAGE_SOURCE = ROOT / "Package.swift"
INSTALL_SCRIPT = ROOT / "scripts" / "install.sh"


class HelperContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = HELPER_SOURCE.read_text(encoding="utf-8")
        cls.client_source = CLIENT_SOURCE.read_text(encoding="utf-8")
        cls.app_main_source = APP_MAIN_SOURCE.read_text(encoding="utf-8")
        cls.package_source = PACKAGE_SOURCE.read_text(encoding="utf-8")
        cls.install_script = INSTALL_SCRIPT.read_text(encoding="utf-8")
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

    def test_spawned_commands_have_a_deadline(self):
        self.assertIn("childTimeout", self.source)
        self.assertIn("WNOHANG", self.source)
        self.assertIn("SIGKILL", self.source)

    def test_verifies_peer_uid_against_console_owner(self):
        self.assertIn("getpeereid", self.source)
        self.assertIn("/dev/console", self.source)
        self.assertIn("peerUID == consoleUID()", self.source)

    def test_installer_health_probe_drops_to_the_console_user(self):
        self.assertIn('"--health-probe"', self.source)
        self.assertIn("dropHealthProbePrivilegesToConsoleUser", self.source)
        self.assertIn("setgid(gid)", self.source)
        self.assertIn("setuid(uid)", self.source)
        self.assertIn('Data(#"{\"op\":\"health\"}"#.utf8)', self.source)
        self.assertIn('response["health"] as? Bool == true', self.source)

    def test_health_request_is_fixed_and_read_only(self):
        health = self.source.split('case "health":', 1)[1].split(
            'case "getMode":', 1
        )[0]
        self.assertIn('#"{\"ok\":true,\"health\":true}"#', health)
        self.assertNotIn("livePowerMode", health)
        self.assertNotIn("powerPreferences", health)
        self.assertNotIn("runPmset", health)
        self.assertNotIn("setSystemBatteryIconHidden", health)
        self.assertNotIn("setLaunchAtLoginEnabled", health)

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
        self.assertIn('case "health"', self.source)
        self.assertIn('case "getPower"', self.source)
        self.assertIn('case "getMode"', self.source)
        self.assertIn('case "setMode"', self.source)
        self.assertIn('case "getSystemBatteryIconHidden"', self.source)
        self.assertIn('case "setSystemBatteryIconHidden"', self.source)
        self.assertIn('case "getLaunchAtLoginEnabled"', self.source)
        self.assertIn('case "setLaunchAtLoginEnabled"', self.source)
        self.assertIn("default:", self.source)
        self.assertIn("os_log", self.source)

    def test_smc_power_endpoint_has_fixed_read_only_keys(self):
        self.assertIn("import IOKit", self.source)
        self.assertIn("0x5044_5452", self.source)  # PDTR
        self.assertIn("0x5053_5452", self.source)  # PSTR
        self.assertIn("readBytesCommand: UInt8 = 5", self.source)
        self.assertIn("readKeyInfoCommand: UInt8 = 9", self.source)
        self.assertNotIn('object["key"]', self.source)
        self.assertNotIn("writeKey", self.source)

    def test_smc_power_decoder_is_bounded_and_supports_expected_types(self):
        for data_type in ('"flt "', '"sp78"', '"sp96"'):
            self.assertIn(data_type, self.source)
        self.assertIn("Float(bitPattern: bits)", self.source)
        self.assertIn("Int16(bitPattern: bits)", self.source)
        self.assertIn("watts.isFinite", self.source)
        self.assertIn("(0 ... 1_000).contains(watts)", self.source)

    def test_smc_power_response_and_client_are_typed_and_validated(self):
        self.assertIn('["ok": true]', self.source)
        self.assertIn('object["adapterW"]', self.source)
        self.assertIn('object["systemW"]', self.source)
        self.assertIn("struct LivePower: Equatable", self.client_source)
        self.assertIn('send(["op": "getPower"])', self.client_source)
        self.assertIn("value.isFinite", self.client_source)
        self.assertIn("adapterW != nil || systemW != nil", self.client_source)

    def test_sandboxed_app_binary_can_probe_the_installed_helper(self):
        self.assertIn('send(["op": "health"])', self.client_source)
        self.assertIn('--helper-health-probe', self.app_main_source)
        self.assertIn('HelperClient.isHealthy()', self.app_main_source)
        self.assertIn('--helper-power-probe', self.app_main_source)
        self.assertIn('HelperClient.livePower()', self.app_main_source)
        self.assertLess(
            self.app_main_source.index('--helper-health-probe'),
            self.app_main_source.index('NSApplication.shared'),
        )

    def test_helper_builds_link_iokit_in_swiftpm_and_installer(self):
        helper_target = self.package_source.split('name: "WattsonHelper"', 1)[1].split(
            ".testTarget", 1
        )[0]
        self.assertIn('.linkedFramework("IOKit")', helper_target)
        helper_compile = self.install_script.split(
            'xcrun swiftc "$ROOT_DIR/Helper/wattson-helper.swift"', 1
        )[1].split("codesign", 1)[0]
        self.assertIn("-framework IOKit", helper_compile)

    def test_launch_agent_is_user_owned_and_opens_the_canonical_app(self):
        self.assertIn(r'"Library/LaunchAgents/\(loginAgentLabel).plist"', self.source)
        self.assertIn('"/Applications/Wattson.app"', self.source)
        self.assertIn("getpwuid(uid)", self.source)
        self.assertNotIn('object["path"]', self.source)

    def test_legacy_login_agent_is_migrated_only_after_exact_validation(self):
        self.assertIn('"Applications/Wattson.app"', self.source)
        self.assertIn("loginAgentIsLegacyCanonical", self.source)
        self.assertIn("loginAgentMatches(account.legacyAppPath", self.source)
        self.assertIn("setLaunchAtLoginEnabled(true, for: uid)", self.source)
        self.assertIn('"--migrate-legacy-login-item"', self.source)
        self.assertIn("migrateLegacyLoginAgentForInstaller", self.source)

    def test_user_owned_agent_is_written_without_root_privileges(self):
        # The console user may replace directories with symlinks. Dropping the
        # effective IDs before touching their home prevents a root overwrite.
        self.assertIn("setegid(account.gid)", self.source)
        self.assertIn("seteuid(account.uid)", self.source)
        self.assertIn("seteuid(0)", self.source)
        self.assertIn("setegid(0)", self.source)
        self.assertIn("initgroups", self.source)
        self.assertIn("restoreSupplementaryGroups", self.source)
        self.assertIn("defer {", self.source)

    def test_login_agent_is_canonical_and_associated_with_wattson(self):
        self.assertIn("lstat(account.agentPath", self.source)
        self.assertIn("S_IFREG", self.source)
        self.assertIn("info.st_uid == account.uid", self.source)
        self.assertIn('"AssociatedBundleIdentifiers"', self.source)
        self.assertIn('"com.leoarrow.wattson"', self.source)

    def test_socket_client_cannot_hold_the_helper_open_forever(self):
        self.assertIn("SO_RCVTIMEO", self.source)
        self.assertIn("SO_SNDTIMEO", self.source)

    def test_login_agent_has_no_shell_or_caller_supplied_command(self):
        self.assertIn('["/usr/bin/open", "-gj", appPath ?? account.appPath]', self.source)
        self.assertIn('["/usr/bin/open", "-gj", appPath]', self.source)
        self.assertIn('"RunAtLoad": true', self.source)
        self.assertIn('"/bin/launchctl", "bootstrap"', self.source)
        self.assertIn('"/bin/launchctl", "bootout"', self.source)

    def test_system_battery_visibility_uses_fixed_control_center_values(self):
        # 8 keeps Battery in Control Center but removes it from the menu bar;
        # 18 restores it to both. The request supplies only a Boolean.
        self.assertIn('"com.apple.controlcenter"', self.source)
        self.assertIn("hidden ? 8 : 18", self.source)
        self.assertIn("CFPreferencesSetValue", self.source)
        self.assertIn("CFPreferencesSynchronize", self.source)

    def test_system_battery_visibility_uses_the_console_users_preferences_daemon(self):
        # A root LaunchDaemon remains in the system bootstrap even after an
        # effective-UID change. Run a fixed internal worker in the console
        # user's bootstrap, then permanently drop that worker's credentials.
        battery_helpers = self.source.split(
            "private func currentUserSystemBatteryIconHidden", 1
        )[1].split("private func handle", 1)[0]
        self.assertIn('"/bin/launchctl", "asuser"', battery_helpers)
        self.assertIn('"--battery-preference-read"', self.source)
        self.assertIn('"--battery-preference-hide"', self.source)
        self.assertIn('"--battery-preference-show"', self.source)
        self.assertIn("dropHealthProbePrivilegesToConsoleUser()", self.source)
        self.assertIn("kCFPreferencesCurrentUser", battery_helpers)
        self.assertNotIn("withUserPrivileges(account)", battery_helpers)
        self.assertNotIn("userName(for:", self.source)
        current_user_read = battery_helpers.split(
            "private func systemBatteryIconHidden", 1
        )[0]
        self.assertLess(
            current_user_read.index("CFPreferencesSynchronize"),
            current_user_read.index("CFPreferencesCopyValue"),
        )

    def test_control_center_is_restarted_in_the_console_user_domain(self):
        self.assertIn('"/usr/bin/pkill", "-TERM", "-U"', self.source)
        self.assertIn('"\\(uid)", "-x", "ControlCenter"', self.source)
        self.assertIn("launchctl kickstart is rejected by SIP", self.source)

    def test_missing_control_center_during_relaunch_is_not_a_write_failure(self):
        restart = self.source.split("private func restartControlCenter", 1)[1].split(
            "private func setSystemBatteryIconHidden", 1
        )[0]
        self.assertIn("runExitCode", restart)
        self.assertIn("exitCode == 0 || exitCode == 1", restart)
        self.assertNotIn("pgrep", restart)

    def test_never_interpolates_input_into_a_command(self):
        for forbidden in ("\\(value)", "\\(op)", "\\(request", "/bin/sh", "-c\""):
            self.assertNotIn(forbidden, self.source)


if __name__ == "__main__":
    unittest.main()
