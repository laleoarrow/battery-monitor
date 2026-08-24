import pathlib
import plistlib
import subprocess
import tempfile
import textwrap
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
HELPER_SOURCE = ROOT / "Helper" / "wattson-helper.swift"
HELPER_PLIST = ROOT / "Helper" / "com.leoarrow.wattson.helper.plist"
CLIENT_SOURCE = ROOT / "Core" / "HelperClient.swift"
V5_CLIENT_SOURCE = ROOT / "Core" / "HelperClientPowerObservationV5.swift"
V5_SUPPORT_SOURCE = ROOT / "HelperV5" / "PowerObservationV5Support.swift"
APP_MAIN_SOURCE = ROOT / "main.swift"
PACKAGE_SOURCE = ROOT / "Package.swift"
INSTALL_SCRIPT = ROOT / "scripts" / "install.sh"


class HelperContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = HELPER_SOURCE.read_text(encoding="utf-8")
        cls.client_source = CLIENT_SOURCE.read_text(encoding="utf-8")
        cls.v5_client_source = V5_CLIENT_SOURCE.read_text(encoding="utf-8")
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
        self.assertIn("idleTimeout: TimeInterval = 12", self.source)
        self.assertIn("launchd's default same-job spawn throttle is 10 seconds", self.source)
        main_loop = self.source.split("var lastActivity", 1)[1]
        self.assertIn(
            "idleUptimeNow - lastActivityUptime >= idleTimeoutNanoseconds",
            main_loop,
        )
        self.assertIn("return", main_loop)

    def test_each_request_releases_foundation_temporaries(self):
        main_loop = self.source.split("var lastActivity", 1)[-1]
        self.assertIn("autoreleasepool", main_loop)
        self.assertIn("handle(request)", main_loop)

    def test_spawned_commands_have_a_deadline(self):
        self.assertIn("childTimeout", self.source)
        self.assertIn("WNOHANG", self.source)
        self.assertIn("SIGKILL", self.source)
        run_exit = self.source.split("private func runExitCode", 1)[1].split(
            "private func run(", 1
        )[0]
        self.assertIn("socketRequestContinuousNowNanoseconds()", run_exit)
        self.assertNotIn("Date()", run_exit)

        health_wait = self.source.split(
            "private func newlyInstalledHelperIsHealthy", 1
        )[1].split("private func dropPrivileges", 1)[0]
        self.assertIn("socketRequestContinuousNowNanoseconds()", health_wait)
        self.assertNotIn("Date()", health_wait)

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
        self.assertIn('strictJSONBool(response["health"]) == true', self.source)

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
        # Apple's tri-state setter accepts 0/1 even without High Power support;
        # lowpowermode is only the live-output display alias on those machines.
        run_pmset = self.source.split("private func runPmset", 1)[1].split(
            "private func livePowerMode", 1
        )[0]
        self.assertNotIn('"lowpowermode"', run_pmset)

    def test_mode_readback_comes_from_pmset_live(self):
        # The preferences plist is lazily written and can lag by a whole mode
        # transition. A verified reply must come from the live value instead.
        self.assertIn('runOutput(["/usr/bin/pmset", "-g", "live"])', self.source)
        self.assertIn('"modeVerified":true', self.source)
        self.assertIn("livePowerMode()", self.source)

    def test_pmset_readback_has_deadline_and_stable_locale(self):
        run_output = self.source.split("private func runOutput", 1)[1].split(
            "private func runPmset", 1
        )[0]
        self.assertIn("childTimeout", run_output)
        self.assertIn('"LANG": "C"', run_output)
        self.assertIn('"LC_ALL": "C"', run_output)
        self.assertIn("stopOutputProcess(process)", run_output)
        self.assertIn("SIGKILL", self.source.split("private func stopOutputProcess", 1)[1].split(
            "private func runOutput", 1
        )[0])
        self.assertIn("DispatchTime.now().uptimeNanoseconds", run_output)
        self.assertIn("O_NONBLOCK", run_output)
        self.assertIn("data.count + count <= maximumCommandOutputBytes", run_output)
        self.assertIn("observedChildExit", run_output)
        self.assertNotIn("readDataToEndOfFile()", run_output)

    def test_helper_accepts_both_pmset_live_output_formats(self):
        parser = self.source.split("private func mode(fromLiveOutput", 1)[1].split(
            "/// The app is sandboxed", 1
        )[0]
        self.assertIn('(\"powermode\", 2)', parser)
        self.assertIn('(\"lowpowermode\", 0)', parser)
        self.assertIn('(\"lowpowermode\", 1)', parser)
        self.assertIn('(\"lowpowermode\", _)', parser)

    def test_high_power_support_uses_current_hardware_capabilities(self):
        self.assertIn(
            'runOutput(["/usr/bin/pmset", "-g", "cap"])',
            self.source,
        )
        self.assertIn("capabilitiesOutput:", self.source)
        self.assertNotIn("com.apple.PowerManagement.", self.source)
        self.assertNotIn("NSDictionary(contentsOfFile:", self.source)

        support_detection = self.source.split(
            "private func supportsHighPower(current:", 1
        )[1].split("private func modeReply", 1)[0]
        self.assertIn("if current == .high { return true }", support_detection)

    def test_high_power_capability_parser_executable_fixture(self):
        mode_enum = "private enum Mode" + self.source.split(
            "private enum Mode", 1
        )[1].split("private enum BatteryPreferenceWorkerOperation", 1)[0]
        pure_parser = "private func supportsHighPower(" + self.source.split(
            "private func supportsHighPower(", 1
        )[1].split("private func supportsHighPower(current:", 1)[0]
        harness_source = textwrap.dedent(
            """
            import Darwin
            import Foundation
            """
        ) + mode_enum + pure_parser + textwrap.dedent(
            r'''

            private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
                guard condition() else {
                    FileHandle.standardError.write(Data((message + "\n").utf8))
                    exit(1)
                }
            }

            let supported = """
            Capabilities for Battery Power:
             displaysleep
             lowpowermode
             highpowermode
            """
            let unsupported = """
            Capabilities for Battery Power:
             displaysleep
             lowpowermode
            """

            require(
                supportsHighPower(current: .auto, capabilitiesOutput: supported),
                "highpowermode capability"
            )
            require(
                supportsHighPower(current: .low, capabilitiesOutput: supported),
                "highpowermode capability while low"
            )
            require(
                !supportsHighPower(current: .auto, capabilitiesOutput: unsupported),
                "missing highpowermode"
            )
            require(
                !supportsHighPower(
                    current: .auto,
                    capabilitiesOutput: "highpowermode-legacy\nnot-highpowermode\n"
                ),
                "capability must be an exact token"
            )
            require(
                supportsHighPower(current: .high, capabilitiesOutput: nil),
                "current high mode is proof without capability output"
            )

            print("high power capability self-test passed")
            '''
        )
        with tempfile.TemporaryDirectory() as directory:
            directory_path = pathlib.Path(directory)
            harness_path = directory_path / "main.swift"
            executable_path = directory_path / "high-power-capability-self-test"
            harness_path.write_text(harness_source, encoding="utf-8")
            compile_result = subprocess.run(
                ["/usr/bin/xcrun", "swiftc", str(harness_path), "-o", str(executable_path)],
                check=False,
                text=True,
                capture_output=True,
            )
            self.assertEqual(compile_result.returncode, 0, compile_result.stderr)
            run_result = subprocess.run(
                [str(executable_path)],
                check=False,
                text=True,
                capture_output=True,
                timeout=5,
            )
            self.assertEqual(run_result.returncode, 0, run_result.stderr)
            self.assertIn("high power capability self-test passed", run_result.stdout)

    def test_high_power_capability_cache_executable_fixture(self):
        self.assertIn("private struct HighPowerCapabilityCache", self.source)
        mode_enum = "private enum Mode" + self.source.split(
            "private enum Mode", 1
        )[1].split("private enum BatteryPreferenceWorkerOperation", 1)[0]
        pure_parser = "private func supportsHighPower(" + self.source.split(
            "private func supportsHighPower(", 1
        )[1].split("private func parsedHighPowerCapability", 1)[0]
        capability_cache = "private func parsedHighPowerCapability" + self.source.split(
            "private func parsedHighPowerCapability", 1
        )[1].split("private var highPowerCapabilityCache", 1)[0]
        harness_source = textwrap.dedent(
            """
            import Darwin
            import Foundation
            """
        ) + mode_enum + pure_parser + capability_cache + textwrap.dedent(
            r'''

            private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
                guard condition() else {
                    FileHandle.standardError.write(Data((message + "\n").utf8))
                    exit(1)
                }
            }

            let supported = """
            Capabilities for AC Power:
             displaysleep
             lowpowermode
             highpowermode
            """
            let unsupported = """
            Capabilities for Battery Power:
             displaysleep
             lowpowermode
            """

            var supportedCalls = 0
            let supportedProvider: () -> String? = {
                supportedCalls += 1
                return supported
            }
            private var supportedCache = HighPowerCapabilityCache()
            require(supportedCache.resolve(provider: supportedProvider) == true,
                    "supported capability")
            require(supportedCache.resolve(provider: supportedProvider) == true,
                    "supported capability cache hit")
            require(supportedCalls == 1, "supported provider must run once")

            var unsupportedCalls = 0
            let unsupportedProvider: () -> String? = {
                unsupportedCalls += 1
                return unsupported
            }
            private var unsupportedCache = HighPowerCapabilityCache()
            require(unsupportedCache.resolve(provider: unsupportedProvider) == false,
                    "unsupported capability")
            require(unsupportedCache.resolve(provider: unsupportedProvider) == false,
                    "unsupported capability cache hit")
            require(unsupportedCalls == 1, "unsupported provider must run once")

            var commandResponses: [String?] = [nil, supported]
            var commandCalls = 0
            let flakyCommandProvider: () -> String? = {
                commandCalls += 1
                return commandResponses.removeFirst()
            }
            private var commandFailureCache = HighPowerCapabilityCache()
            require(commandFailureCache.resolve(provider: flakyCommandProvider) == nil,
                    "command failure must stay unknown")
            require(commandFailureCache.resolve(provider: flakyCommandProvider) == true,
                    "command failure must retry")
            require(commandFailureCache.resolve(provider: flakyCommandProvider) == true,
                    "successful retry must then cache")
            require(commandCalls == 2, "command failure must not be cached")

            var parseResponses: [String?] = ["not pmset capability output", unsupported]
            var parseCalls = 0
            let flakyParseProvider: () -> String? = {
                parseCalls += 1
                return parseResponses.removeFirst()
            }
            private var parseFailureCache = HighPowerCapabilityCache()
            require(parseFailureCache.resolve(provider: flakyParseProvider) == nil,
                    "parse failure must stay unknown")
            require(parseFailureCache.resolve(provider: flakyParseProvider) == false,
                    "parse failure must retry")
            require(parseFailureCache.resolve(provider: flakyParseProvider) == false,
                    "successful false retry must then cache")
            require(parseCalls == 2, "parse failure must not be cached")

            print("high power capability cache self-test passed")
            '''
        )
        with tempfile.TemporaryDirectory() as directory:
            directory_path = pathlib.Path(directory)
            harness_path = directory_path / "main.swift"
            executable_path = directory_path / "high-power-capability-cache-self-test"
            harness_path.write_text(harness_source, encoding="utf-8")
            compile_result = subprocess.run(
                ["/usr/bin/xcrun", "swiftc", str(harness_path), "-o", str(executable_path)],
                check=False,
                text=True,
                capture_output=True,
            )
            self.assertEqual(compile_result.returncode, 0, compile_result.stderr)
            run_result = subprocess.run(
                [str(executable_path)],
                check=False,
                text=True,
                capture_output=True,
                timeout=5,
            )
            self.assertEqual(run_result.returncode, 0, run_result.stderr)
            self.assertIn(
                "high power capability cache self-test passed", run_result.stdout
            )

    def test_helper_output_capture_and_mode_parser_executable_self_test(self):
        mode_enum = "private enum Mode" + self.source.split(
            "private enum Mode", 1
        )[1].split("private enum BatteryPreferenceWorkerOperation", 1)[0]
        output_capture = "private let maximumCommandOutputBytes" + self.source.split(
            "private let maximumCommandOutputBytes", 1
        )[1].split("private func runPmset", 1)[0]
        mode_parser = "private func mode(fromLiveOutput" + self.source.split(
            "private func mode(fromLiveOutput", 1
        )[1].split("/// The app is sandboxed", 1)[0]
        harness_source = textwrap.dedent(
            """
            import Darwin
            import Foundation

            private let childTimeout: TimeInterval = 0.4
            """
        ) + mode_enum + output_capture + mode_parser + textwrap.dedent(
            r'''

            private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
                guard condition() else {
                    FileHandle.standardError.write(Data((message + "\n").utf8))
                    exit(1)
                }
            }

            private func openFDCount() -> Int {
                (try? FileManager.default.contentsOfDirectory(atPath: "/dev/fd").count) ?? -1
            }

            require(mode(fromLiveOutput: "powermode 2\n") == .high, "tri-state high")
            require(mode(fromLiveOutput: "lowpowermode 0\n") == .auto, "two-state auto")
            require(mode(fromLiveOutput: "lowpowermode 1\n") == .low, "two-state low")
            require(mode(fromLiveOutput: "lowpowermode 2\n") == nil, "two-state reject high")

            let baselineFDs = openFDCount()
            for _ in 0..<64 {
                require(
                    runOutput(["/usr/bin/printf", "tail-byte"]) == "tail-byte",
                    "direct-child tail bytes must be drained after exit"
                )
            }
            require(
                openFDCount() <= baselineFDs + 2,
                "successful output capture must close pipe descriptors"
            )

            let oversizedStart = Date()
            require(
                runOutput(["/bin/sh", "-c", "head -c 70000 /dev/zero"]) == nil,
                "oversized output must fail while arriving"
            )
            require(Date().timeIntervalSince(oversizedStart) < 1.0, "oversized output deadline")

            let inheritedStart = Date()
            require(
                runOutput(["/bin/sh", "-c", "(sleep 3) & printf inherited-ok"])
                    == "inherited-ok",
                "direct child output"
            )
            require(
                Date().timeIntervalSince(inheritedStart) < 1.0,
                "inherited stdout must not extend the direct-child deadline"
            )
            require(
                openFDCount() <= baselineFDs + 2,
                "all output-capture exits must close pipe descriptors"
            )
            print("helper output self-test passed")
            '''
        )
        with tempfile.TemporaryDirectory() as directory:
            directory_path = pathlib.Path(directory)
            harness_path = directory_path / "main.swift"
            executable_path = directory_path / "helper-output-self-test"
            harness_path.write_text(harness_source, encoding="utf-8")
            compile_result = subprocess.run(
                ["/usr/bin/xcrun", "swiftc", str(harness_path), "-o", str(executable_path)],
                check=False,
                text=True,
                capture_output=True,
            )
            self.assertEqual(compile_result.returncode, 0, compile_result.stderr)
            run_result = subprocess.run(
                [str(executable_path)],
                check=False,
                text=True,
                capture_output=True,
                timeout=5,
            )
            self.assertEqual(run_result.returncode, 0, run_result.stderr)
            self.assertIn("helper output self-test passed", run_result.stdout)

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
        live_mode = self.source.split("private func livePowerMode()", 1)[1].split(
            "private func mode(fromLiveOutput", 1
        )[0]
        self.assertIn('runOutput(["/usr/bin/pmset", "-g", "live"])', live_mode)
        self.assertNotIn("HighPowerCapabilityCache", live_mode)
        self.assertNotIn("highPowerCapabilityCache", live_mode)

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

    def test_v5_dispatch_preserves_raw_frame_and_runs_after_peer_revalidation(self):
        self.assertIn("import WattsonHelperV5Support", self.source)
        socket_request = self.source.split("private struct SocketRequest", 1)[1].split(
            "private enum ReadySocketRequestResult", 1
        )[0]
        self.assertIn("let frame: Data", socket_request)

        execution = self.source.split("private func handle", 1)[1].split("@main", 1)[0]
        peer_revalidation = execution.index("peerUID == consoleUID()")
        strict_v5_dispatch = execution.index("powerObservationV5Service.handle(")
        self.assertLess(peer_revalidation, strict_v5_dispatch)
        self.assertIn("frame: request.frame", execution)
        self.assertIn("case .notV5:", execution)
        self.assertIn('case "getPower":', execution)

    def test_v5_dispatch_keeps_request_cap_and_bounds_newline_response(self):
        self.assertIn("private let maximumSocketMessageBytes = 512", self.source)
        execution = self.source.split("private func handle", 1)[1].split("@main", 1)[0]
        self.assertIn("HelperV5ResponsePayload.maximumResponseBytes", execution)
        self.assertIn('line.last == UInt8(ascii: "\\n")', execution)
        self.assertIn("line.count <=", execution)

    def test_v5_malformed_claim_is_fail_closed_without_entering_v4_switch(self):
        execution = self.source.split("private func handle", 1)[1].split("@main", 1)[0]
        malformed = execution.split("case .malformed:", 1)[1].split(
            "case .notV5:", 1
        )[0]
        self.assertIn('"_wattsonProtocol":5', malformed)
        self.assertIn("return", malformed)
        self.assertNotIn('case "getPower":', malformed)

    def test_v5_client_only_treats_complete_json_at_eof_as_a_frame(self):
        self.assertIn("completeFrameAtEOFOrIncomplete", self.v5_client_source)
        eof_classifier = self.v5_client_source.split(
            "private func completeFrameAtEOFOrIncomplete", 1
        )[1].split("private func incompleteOrNoResponse", 1)[0]
        self.assertIn("JSONSerialization.jsonObject(with: data)", eof_classifier)
        self.assertIn("return .frame(data)", eof_classifier)
        self.assertIn("return .incompleteFrame(data)", eof_classifier)

    def test_smc_power_endpoint_has_fixed_read_only_keys(self):
        self.assertIn("import IOKit", self.source)
        self.assertIn("0x5044_5452", self.source)  # PDTR
        self.assertIn("0x5053_5452", self.source)  # PSTR
        self.assertIn("readBytesCommand: UInt8 = 5", self.source)
        self.assertIn("readKeyInfoCommand: UInt8 = 9", self.source)
        self.assertNotIn('object["key"]', self.source)
        self.assertNotIn("writeKey", self.source)

    def test_smc_power_decoder_is_bounded_and_supports_expected_types(self):
        for data_type in ("smcFloatType", "smcSP78Type", "smcSP96Type"):
            self.assertIn(data_type, self.source)
        self.assertIn("private func decodeSMCWatts", self.source)
        self.assertIn("Float(bitPattern: bits)", self.source)
        self.assertIn("Int16(bitPattern: bits)", self.source)
        self.assertIn("watts.isFinite", self.source)
        self.assertIn("(0 ... 1_000).contains(watts)", self.source)

    def test_smc_decoder_executable_byte_vectors_and_layout(self):
        smc_layout = "private typealias SMCBytes" + self.source.split(
            "private typealias SMCBytes", 1
        )[1].split("private struct FixedSMCPower", 1)[0]
        decoder = "private let smcFloatType" + self.source.split(
            "private let smcFloatType", 1
        )[1].split("private enum FixedSMCPowerReader", 1)[0]
        harness_source = textwrap.dedent(
            """
            import Darwin
            import Foundation
            """
        ) + smc_layout + decoder + textwrap.dedent(
            r'''

            private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
                guard condition() else {
                    FileHandle.standardError.write(Data((message + "\n").utf8))
                    exit(1)
                }
            }

            require(MemoryLayout<SMCKeyData>.size == 80, "SMCKeyData ABI size")
            require(
                decodeSMCWatts(dataType: smcFloatType, bytes: [0x00, 0x00, 0x2a, 0x42])
                    == 42.5,
                "flt little-endian 42.5"
            )
            require(
                decodeSMCWatts(dataType: smcSP78Type, bytes: [0x0a, 0x80]) == 10.5,
                "sp78 10.5"
            )
            require(
                decodeSMCWatts(dataType: smcSP96Type, bytes: [0x02, 0xa0]) == 10.5,
                "sp96 10.5"
            )

            require(
                decodeSMCWatts(dataType: smcFloatType, bytes: [0x00, 0x00, 0xc0, 0x7f]) == nil,
                "NaN rejected"
            )
            require(
                decodeSMCWatts(dataType: smcFloatType, bytes: [0x00, 0x00, 0x80, 0x7f]) == nil,
                "infinity rejected"
            )
            require(
                decodeSMCWatts(dataType: smcFloatType, bytes: [0x00, 0x00, 0x80, 0xbf]) == nil,
                "negative flt rejected"
            )
            require(
                decodeSMCWatts(dataType: smcSP78Type, bytes: [0xff, 0x00]) == nil,
                "negative sp78 rejected"
            )
            require(
                decodeSMCWatts(dataType: smcSP96Type, bytes: [0xff, 0xc0]) == nil,
                "negative sp96 rejected"
            )
            require(
                decodeSMCWatts(dataType: smcFloatType, bytes: [0x00, 0x20, 0x7a, 0x44]) == nil,
                "greater than 1000 rejected"
            )
            require(
                decodeSMCWatts(dataType: smcFloatType, bytes: [0x00, 0x00, 0x7a, 0x44])
                    == 1000,
                "1000 boundary accepted"
            )

            for invalid in [
                [UInt8](),
                [0x00, 0x00, 0x2a],
                [0x00, 0x00, 0x2a, 0x42, 0x00],
            ] {
                require(
                    decodeSMCWatts(dataType: smcFloatType, bytes: invalid) == nil,
                    "wrong flt length rejected"
                )
            }
            for dataType in [smcSP78Type, smcSP96Type] {
                require(
                    decodeSMCWatts(dataType: dataType, bytes: [0x00]) == nil,
                    "short fixed-point length rejected"
                )
                require(
                    decodeSMCWatts(dataType: dataType, bytes: [0x00, 0x00, 0x00]) == nil,
                    "long fixed-point length rejected"
                )
            }
            require(
                decodeSMCWatts(dataType: 0x756e_6b6e, bytes: [0x00, 0x00, 0x2a, 0x42]) == nil,
                "unknown type rejected"
            )
            print("SMC decoder self-test passed")
            '''
        )
        with tempfile.TemporaryDirectory() as directory:
            directory_path = pathlib.Path(directory)
            harness_path = directory_path / "main.swift"
            executable_path = directory_path / "smc-decoder-self-test"
            harness_path.write_text(harness_source, encoding="utf-8")
            compile_result = subprocess.run(
                ["/usr/bin/xcrun", "swiftc", str(harness_path), "-o", str(executable_path)],
                check=False,
                text=True,
                capture_output=True,
            )
            self.assertEqual(compile_result.returncode, 0, compile_result.stderr)
            run_result = subprocess.run(
                [str(executable_path)],
                check=False,
                text=True,
                capture_output=True,
                timeout=5,
            )
            self.assertEqual(run_result.returncode, 0, run_result.stderr)
            self.assertIn("SMC decoder self-test passed", run_result.stdout)

    def test_helper_cross_compiles_for_x86_64_macos12(self):
        sdk_result = subprocess.run(
            ["/usr/bin/xcrun", "--sdk", "macosx", "--show-sdk-path"],
            check=False,
            text=True,
            capture_output=True,
        )
        self.assertEqual(sdk_result.returncode, 0, sdk_result.stderr)
        with tempfile.TemporaryDirectory() as directory:
            build_directory = pathlib.Path(directory)
            executable_path = build_directory / "wattson-helper-x86_64"
            support_object = build_directory / "WattsonHelperV5Support.o"
            support_module = build_directory / "WattsonHelperV5Support.swiftmodule"
            support_result = subprocess.run(
                [
                    "/usr/bin/xcrun",
                    "swiftc",
                    "-target",
                    "x86_64-apple-macosx12.0",
                    "-sdk",
                    sdk_result.stdout.strip(),
                    "-parse-as-library",
                    "-emit-module",
                    "-emit-object",
                    "-module-name",
                    "WattsonHelperV5Support",
                    str(V5_SUPPORT_SOURCE),
                    "-emit-module-path",
                    str(support_module),
                    "-o",
                    str(support_object),
                ],
                check=False,
                text=True,
                capture_output=True,
                timeout=120,
            )
            self.assertEqual(support_result.returncode, 0, support_result.stderr)
            compile_result = subprocess.run(
                [
                    "/usr/bin/xcrun",
                    "swiftc",
                    "-target",
                    "x86_64-apple-macosx12.0",
                    "-sdk",
                    sdk_result.stdout.strip(),
                    "-parse-as-library",
                    "-I",
                    str(build_directory),
                    str(HELPER_SOURCE),
                    str(support_object),
                    "-framework",
                    "IOKit",
                    "-o",
                    str(executable_path),
                ],
                check=False,
                text=True,
                capture_output=True,
                timeout=120,
            )
            self.assertEqual(compile_result.returncode, 0, compile_result.stderr)
            arch_result = subprocess.run(
                ["/usr/bin/lipo", "-archs", str(executable_path)],
                check=False,
                text=True,
                capture_output=True,
            )
            self.assertEqual(arch_result.returncode, 0, arch_result.stderr)
            self.assertEqual(arch_result.stdout.strip(), "x86_64")
            build_version_result = subprocess.run(
                ["/usr/bin/xcrun", "vtool", "-show-build", str(executable_path)],
                check=False,
                text=True,
                capture_output=True,
            )
            self.assertEqual(
                build_version_result.returncode,
                0,
                build_version_result.stderr,
            )
            self.assertIn("platform MACOS", build_version_result.stdout)
            self.assertIn("minos 12.0", build_version_result.stdout)

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
            'echo "  🔑 Installing the privileged helper', 1
        )[1].split("codesign", 1)[0]
        self.assertIn("/usr/bin/swift build", helper_compile)
        self.assertIn("--product wattson-helper", helper_compile)
        self.assertIn("--configuration release", helper_compile)
        self.assertNotIn('xcrun swiftc "$ROOT_DIR/Helper/wattson-helper.swift"', helper_compile)

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
        self.assertIn("socketRequestStartTimeoutNanoseconds", self.source)
        self.assertIn("acceptedAtContinuousTime", self.source)
        self.assertIn("clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)", self.source)
        framing = self.source.split("// MARK: - Socket Framing", 1)[1].split(
            "// MARK: - Console User", 1
        )[0]
        self.assertNotIn("DispatchTime.now().uptimeNanoseconds", framing)
        self.assertIn(
            "DispatchTime.now() + .seconds(timeoutSeconds)", self.client_source
        )
        self.assertIn("(1...15).contains(timeoutSeconds)", self.client_source)

    def test_helper_uses_a_bounded_single_threaded_poll_inbox(self):
        self.assertIn("private let maximumPendingSocketClients = 32", self.source)
        self.assertIn("private let maximumAcceptsPerPollCycle", self.source)
        self.assertIn("private struct SocketRequestInbox", self.source)
        self.assertIn("Darwin.poll", self.source)
        self.assertIn("MSG_DONTWAIT", self.source)
        self.assertIn("takeNextReady", self.source)
        self.assertIn("oldest incomplete", self.source)
        self.assertIn("ready requests are never evicted", self.source)
        self.assertNotIn("DispatchQueue", self.source)
        self.assertNotIn("Thread", self.source)
        self.assertNotIn("fork(", self.source)

    def test_helper_poll_deadline_executable_self_test(self):
        main_loop = self.source.split("var lastActivity", 1)[1]
        self.assertIn(
            "let timeoutMilliseconds = socketPollTimeoutMilliseconds(", main_loop
        )
        self.assertNotIn("now + 1_000_000_000", main_loop)
        self.assertNotIn("UInt64(1_000)", main_loop)

        deadline_function = "private func socketPollTimeoutMilliseconds" + self.source.split(
            "private func socketPollTimeoutMilliseconds", 1
        )[1].split("private struct SocketRequest", 1)[0]
        harness_source = textwrap.dedent(
            """
            import Foundation
            """
        ) + deadline_function + textwrap.dedent(
            r'''

            private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
                guard condition() else {
                    FileHandle.standardError.write(Data((message + "\n").utf8))
                    exit(1)
                }
            }

            let requestContinuousNow: UInt64 = 5_000_000_000
            let idleUptimeNow: UInt64 = 50_000_000_000
            require(
                socketPollTimeoutMilliseconds(
                    requestContinuousNow: requestContinuousNow,
                    nextReadContinuousDeadline: nil,
                    idleUptimeNow: idleUptimeNow,
                    idleUptimeDeadline: 62_000_000_000
                ) == 12_000,
                "idle listener must use only its 12 s uptime deadline"
            )
            require(
                socketPollTimeoutMilliseconds(
                    requestContinuousNow: requestContinuousNow,
                    nextReadContinuousDeadline: 7_000_000_000,
                    idleUptimeNow: idleUptimeNow,
                    idleUptimeDeadline: 50_500_000_000
                ) == 2_000,
                "reader must use only its continuous deadline"
            )
            require(
                socketPollTimeoutMilliseconds(
                    requestContinuousNow: requestContinuousNow,
                    nextReadContinuousDeadline: 4_999_999_999,
                    idleUptimeNow: idleUptimeNow,
                    idleUptimeDeadline: 62_000_000_000
                ) == 0,
                "an overdue reader must be serviced without another sleep"
            )
            require(
                socketPollTimeoutMilliseconds(
                    requestContinuousNow: requestContinuousNow,
                    nextReadContinuousDeadline: nil,
                    idleUptimeNow: idleUptimeNow,
                    idleUptimeDeadline: idleUptimeNow + 1
                ) == 1,
                "sub-millisecond waits must round up"
            )
            require(
                socketPollTimeoutMilliseconds(
                    requestContinuousNow: requestContinuousNow,
                    nextReadContinuousDeadline: nil,
                    idleUptimeNow: 0,
                    idleUptimeDeadline: UInt64(Int32.max) * 1_000_000 + 1
                ) == Int32.max,
                "poll timeout must saturate at Int32.max"
            )

            print("poll deadline self-test passed")
            '''
        )
        with tempfile.TemporaryDirectory() as directory:
            directory_path = pathlib.Path(directory)
            harness_path = directory_path / "main.swift"
            executable_path = directory_path / "poll-deadline-self-test"
            harness_path.write_text(harness_source, encoding="utf-8")
            compile_result = subprocess.run(
                ["/usr/bin/xcrun", "swiftc", str(harness_path), "-o", str(executable_path)],
                check=False,
                text=True,
                capture_output=True,
            )
            self.assertEqual(compile_result.returncode, 0, compile_result.stderr)
            run_result = subprocess.run(
                [str(executable_path)],
                check=False,
                text=True,
                capture_output=True,
                timeout=5,
            )
            self.assertEqual(run_result.returncode, 0, run_result.stderr)
            self.assertIn("poll deadline self-test passed", run_result.stdout)

    def test_ready_requests_keep_the_accept_deadline_until_execution(self):
        socket_request = self.source.split("private struct SocketRequest", 1)[1].split(
            "private struct ReadingSocketClient", 1
        )[0]
        self.assertIn("let continuousDeadline: UInt64", socket_request)
        self.assertIn("continuousDeadline: client.continuousDeadline", self.source)
        self.assertIn("mutating func takeNextReady()", self.source)
        self.assertIn("case expired", self.source)
        self.assertIn('"error":"request expired"', self.source)

        execution = self.source.split("private func handle", 1)[1].split("@main", 1)[0]
        continuous_recheck = (
            "socketRequestContinuousNowNanoseconds() < request.continuousDeadline"
        )
        self.assertIn(continuous_recheck, execution)
        self.assertLess(
            execution.index(continuous_recheck),
            execution.index("switch op"),
        )

    def test_inbox_preserves_shared_framing_and_rechecks_console_uid(self):
        framing = self.source.split("// MARK: - Socket Framing", 1)[1].split(
            "// MARK: - Console User", 1
        )[0]
        self.assertIn("parseSocketFrame", framing)
        self.assertGreaterEqual(framing.count("parseSocketFrame("), 3)
        self.assertIn("object[\"_wattsonProtocol\"] != nil", framing)
        self.assertIn("data.firstIndex(of: UInt8(ascii: \"\\n\"))", framing)

        execution = self.source.split("private func handle", 1)[1].split(
            "@main", 1
        )[0]
        self.assertIn("peerUID == consoleUID()", execution)
        self.assertIn("defer { close(fd) }", execution)

        poll_body = self.source.split(
            "mutating func poll(listener:", 1
        )[1].split("mutating func closeAll", 1)[0]
        self.assertLess(
            poll_body.index("expireReaders(at: requestContinuousNow())"),
            poll_body.index("receiveAvailableBytes(from: descriptor.fd)"),
        )
        self.assertIn("return errno == EINTR ? activity : nil", poll_body)

    def test_pending_inbox_suppresses_monotonic_idle_exit(self):
        main_loop = self.source.split("var lastActivity", 1)[1]
        self.assertIn("DispatchTime.now().uptimeNanoseconds", main_loop)
        self.assertIn("!inbox.hasPending", main_loop)
        self.assertIn("idleTimeoutNanoseconds", main_loop)
        self.assertIn("autoreleasepool", main_loop)

    def test_socket_io_is_sigpipe_partial_and_fragment_safe(self):
        for source in (self.source, self.client_source):
            self.assertIn("SO_NOSIGPIPE", source)
            self.assertIn("writeAll", source)
            self.assertIn("errno == EINTR", source)
            self.assertIn("readJSONObject", source)
            self.assertIn("data.append(contentsOf: buffer.prefix(count))", source)
            self.assertIn("JSONSerialization.jsonObject(with: data)", source)
        self.assertIn("wattsonProtocolVersion", self.client_source)
        self.assertIn("newline", self.client_source)
        self.assertIn("wattsonProtocolVersion", self.source)
        self.assertIn("maximumSocketMessageBytes = 512", self.source)
        self.assertIn("maximumMessageBytes = 512", self.client_source)

    def test_privileged_boolean_requests_require_real_json_booleans(self):
        self.assertIn("private func strictJSONBool", self.source)
        self.assertIn('strictJSONBool(object["hidden"])', self.source)
        self.assertIn('strictJSONBool(object["enabled"])', self.source)
        self.assertNotIn('object["hidden"] as? Bool', self.source)
        self.assertNotIn('object["enabled"] as? Bool', self.source)

    def test_client_socket_io_executable_self_test(self):
        harness_source = textwrap.dedent(
            r'''
            import Darwin
            import Foundation

            private func require(_ condition: Bool, _ message: String) {
                guard condition else {
                    FileHandle.standardError.write(Data((message + "\n").utf8))
                    exit(1)
                }
            }

            var fragmented = [Int32](repeating: 0, count: 2)
            require(socketpair(AF_UNIX, SOCK_STREAM, 0, &fragmented) == 0, "socketpair")
            let readerFD = fragmented[0]
            let writerFD = fragmented[1]
            let writerGroup = DispatchGroup()
            writerGroup.enter()
            DispatchQueue.global(qos: .utility).async {
                for fragment in ["{\"_wattsonProtocol\":4,\"op\"", ":\"health\"}", "\n"] {
                    require(
                        HelperClient.writeAll(Data(fragment.utf8), to: writerFD),
                        "fragment write"
                    )
                    usleep(20_000)
                }
                writerGroup.leave()
            }
            let object = HelperClient.readJSONObject(from: readerFD, maximumBytes: 512)
            writerGroup.wait()
            close(readerFD)
            close(writerFD)
            require(object?["op"] as? String == "health", "fragmented JSON")

            var framedTail = [Int32](repeating: 0, count: 2)
            require(socketpair(AF_UNIX, SOCK_STREAM, 0, &framedTail) == 0, "tail socketpair")
            require(
                HelperClient.writeAll(
                    Data("{\"ok\":true}\nignored-second-frame\n".utf8),
                    to: framedTail[1]
                ),
                "framed tail write"
            )
            let firstFrame = HelperClient.readJSONObject(from: framedTail[0], maximumBytes: 512)
            close(framedTail[0])
            close(framedTail[1])
            require(
                HelperClient.strictJSONBool(firstFrame?["ok"]) == true,
                "first framed response"
            )

            var delayedClosedPeer = [Int32](repeating: 0, count: 2)
            require(
                socketpair(AF_UNIX, SOCK_STREAM, 0, &delayedClosedPeer) == 0,
                "delayed close socketpair"
            )
            require(
                HelperClient.writeAll(
                    Data("{\"ok\":true}\n".utf8), to: delayedClosedPeer[1]
                ),
                "delayed close response write"
            )
            close(delayedClosedPeer[1])
            usleep(50_000)
            let delayedResponse = HelperClient.readJSONObject(
                from: delayedClosedPeer[0], maximumBytes: 512
            )
            close(delayedClosedPeer[0])
            require(
                HelperClient.strictJSONBool(delayedResponse?["ok"]) == true,
                "buffered response survives peer close before delayed read"
            )

            var closedPeer = [Int32](repeating: 0, count: 2)
            require(socketpair(AF_UNIX, SOCK_STREAM, 0, &closedPeer) == 0, "peer socketpair")
            require(HelperClient.configureNoSigPipe(closedPeer[0]), "SO_NOSIGPIPE")
            close(closedPeer[1])
            require(
                !HelperClient.writeAll(Data("reply".utf8), to: closedPeer[0]),
                "closed peer write must fail without terminating"
            )
            close(closedPeer[0])
            require(
                HelperClient.validatedWatts(NSNumber(value: 1)) == 1,
                "numeric one watt must remain numeric"
            )
            require(
                HelperClient.validatedWatts(kCFBooleanTrue as Any) == nil,
                "Core Foundation boolean must be rejected"
            )
            require(HelperClient.strictJSONBool(kCFBooleanTrue as Any) == true, "true bool")
            require(HelperClient.strictJSONBool(kCFBooleanFalse as Any) == false, "false bool")
            require(HelperClient.strictJSONBool(NSNumber(value: 1)) == nil, "numeric one bool")
            require(HelperClient.strictJSONBool(NSNumber(value: 0)) == nil, "numeric zero bool")
            print("socket io self-test passed")
            '''
        )
        with tempfile.TemporaryDirectory() as directory:
            directory_path = pathlib.Path(directory)
            harness_path = directory_path / "main.swift"
            executable_path = directory_path / "socket-io-self-test"
            harness_path.write_text(harness_source, encoding="utf-8")
            compile_result = subprocess.run(
                [
                    "/usr/bin/xcrun",
                    "swiftc",
                    str(CLIENT_SOURCE),
                    str(harness_path),
                    "-o",
                    str(executable_path),
                ],
                check=False,
                text=True,
                capture_output=True,
            )
            self.assertEqual(compile_result.returncode, 0, compile_result.stderr)
            run_result = subprocess.run(
                [str(executable_path)],
                check=False,
                text=True,
                capture_output=True,
                timeout=10,
            )
            self.assertEqual(run_result.returncode, 0, run_result.stderr)
            self.assertIn("socket io self-test passed", run_result.stdout)

    def test_helper_poll_inbox_executable_temp_socket_self_test(self):
        self.assertIn("// MARK: - Socket Framing", self.source)
        self.assertIn("// MARK: - Console User", self.source)
        inbox_source = self.source.split("// MARK: - Socket Framing", 1)[1].split(
            "// MARK: - Console User", 1
        )[0]
        harness_source = textwrap.dedent(
            """
            import Darwin
            import Foundation

            """
        ) + inbox_source + textwrap.dedent(
            r'''

            private func consoleUID() -> uid_t? { getuid() }

            private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
                guard condition() else {
                    FileHandle.standardError.write(Data((message + "\n").utf8))
                    exit(1)
                }
            }

            private func openFDCount() -> Int {
                (try? FileManager.default.contentsOfDirectory(atPath: "/dev/fd").count) ?? -1
            }

            private func maximumResidentBytes() -> UInt64 {
                var usage = rusage()
                guard getrusage(RUSAGE_SELF, &usage) == 0 else { return 0 }
                return UInt64(max(0, usage.ru_maxrss))
            }

            private func socketAddress(_ path: String) -> sockaddr_un {
                var address = sockaddr_un()
                address.sun_family = sa_family_t(AF_UNIX)
                address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
                let bytes = Array(path.utf8)
                require(bytes.count < MemoryLayout.size(ofValue: address.sun_path), "socket path")
                withUnsafeMutableBytes(of: &address.sun_path) { raw in
                    raw.copyBytes(from: bytes)
                }
                return address
            }

            private func makeListener(at path: String) -> Int32 {
                let fd = socket(AF_UNIX, SOCK_STREAM, 0)
                require(fd >= 0, "listener socket")
                var address = socketAddress(path)
                let result = withUnsafePointer(to: &address) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                    }
                }
                require(result == 0, "bind")
                require(listen(fd, 128) == 0, "listen")
                require(configureNonBlocking(fd), "nonblocking listener")
                return fd
            }

            private func connectClient(to path: String) -> Int32 {
                let fd = socket(AF_UNIX, SOCK_STREAM, 0)
                require(fd >= 0, "client socket")
                require(configureNoSigPipe(fd), "client SO_NOSIGPIPE")
                var timeout = timeval(tv_sec: 3, tv_usec: 0)
                let size = socklen_t(MemoryLayout<timeval>.size)
                require(
                    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, size) == 0,
                    "client receive timeout"
                )
                var address = socketAddress(path)
                let result = withUnsafePointer(to: &address) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                    }
                }
                require(result == 0, "connect")
                return fd
            }

            private func roundTrip(
                path: String,
                fragments: [String],
                pauseMicroseconds: useconds_t = 0,
                readDelayMicroseconds: useconds_t = 0
            ) -> [String: Any]? {
                let fd = connectClient(to: path)
                defer { close(fd) }
                for (index, fragment) in fragments.enumerated() {
                    require(writeAll(Data(fragment.utf8), to: fd), "request write")
                    if pauseMicroseconds > 0 && index + 1 < fragments.count {
                        usleep(pauseMicroseconds)
                    }
                }
                if readDelayMicroseconds > 0 { usleep(readDelayMicroseconds) }
                return readJSONObject(from: fd)
            }

            private func reachesEOF(on fd: Int32, by deadline: UInt64) -> Bool {
                var buffer = [UInt8](repeating: 0, count: 256)
                while DispatchTime.now().uptimeNanoseconds < deadline {
                    let count = recv(fd, &buffer, buffer.count, MSG_DONTWAIT)
                    if count == 0 { return true }
                    if count > 0 { continue }
                    if errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR {
                        return false
                    }
                    usleep(10_000)
                }
                return false
            }

            // Model a request that reached the ready FIFO immediately before
            // system sleep. Uptime pauses during sleep; this injected continuous
            // clock jumps, so the accepted request must expire without reaching
            // the mutation execution branch after wake.
            let sleepSocketPath = "/tmp/wattson-inbox-sleep-" + String(getpid())
                + "-" + UUID().uuidString.prefix(8) + ".sock"
            unlink(sleepSocketPath)
            let sleepListener = makeListener(at: sleepSocketPath)
            private var sleepContinuousNow: UInt64 = 10_000_000_000
            private var sleepInbox = SocketRequestInbox(
                requestContinuousNow: { sleepContinuousNow }
            )
            let sleepMutationClient = connectClient(to: sleepSocketPath)
            require(
                writeAll(Data("{\"op\":\"mutateAfterSleep\"}".utf8), to: sleepMutationClient),
                "sleep mutation write"
            )
            require(
                sleepInbox.poll(listener: sleepListener, timeoutMilliseconds: 0) == true,
                "sleep mutation accept"
            )
            require(
                sleepInbox.poll(listener: sleepListener, timeoutMilliseconds: 0) == true,
                "sleep mutation framing"
            )
            require(
                sleepInbox.nextReadContinuousDeadline == nil,
                "sleep mutation must be ready"
            )

            sleepContinuousNow += socketRequestStartTimeoutNanoseconds + 1
            var sleepMutationExecuted = false
            switch sleepInbox.takeNextReady() {
            case let .request(request):
                sleepMutationExecuted = true
                close(request.fd)
            case .expired:
                break
            case .abandoned, .none:
                require(false, "ready sleep mutation must expire")
            }
            let sleepMutationResponse = readJSONObject(from: sleepMutationClient)
            require(
                strictJSONBool(sleepMutationResponse?["ok"]) == false,
                "sleep-expired mutation must fail"
            )
            require(
                sleepMutationResponse?["error"] as? String == "request expired",
                "sleep-expired mutation error"
            )
            require(!sleepMutationExecuted, "sleep-expired mutation must not execute")
            close(sleepMutationClient)
            sleepInbox.closeAll()
            close(sleepListener)
            unlink(sleepSocketPath)

            // Prove the read deadline itself deterministically. The production
            // clock is injected here so runner scheduling cannot move the
            // assertion boundary relative to the server's accept time.
            let expirySocketPath = "/tmp/wattson-inbox-expiry-" + String(getpid())
                + "-" + UUID().uuidString.prefix(8) + ".sock"
            unlink(expirySocketPath)
            let expiryListener = makeListener(at: expirySocketPath)
            let expiryAcceptedAt: UInt64 = 20_000_000_000
            private var expiryContinuousNow = expiryAcceptedAt
            private var expiryInbox = SocketRequestInbox(
                requestContinuousNow: { expiryContinuousNow }
            )
            let expiryClient = connectClient(to: expirySocketPath)
            require(
                expiryInbox.poll(listener: expiryListener, timeoutMilliseconds: 0) == true,
                "expiry client accept"
            )
            let expiryDeadline = expiryAcceptedAt + socketRequestStartTimeoutNanoseconds
            require(
                expiryInbox.nextReadContinuousDeadline == expiryDeadline,
                "expiry deadline starts at accept"
            )
            expiryContinuousNow = expiryDeadline - 1
            _ = expiryInbox.poll(listener: expiryListener, timeoutMilliseconds: 0)
            require(expiryInbox.count == 1, "reader must remain before its deadline")
            expiryContinuousNow = expiryDeadline
            require(
                expiryInbox.poll(listener: expiryListener, timeoutMilliseconds: 0) == true,
                "reader expires at its exact deadline"
            )
            let expiryResponse = readJSONObject(from: expiryClient)
            require(
                strictJSONBool(expiryResponse?["ok"]) == false,
                "expired reader must fail"
            )
            require(
                reachesEOF(
                    on: expiryClient,
                    by: DispatchTime.now().uptimeNanoseconds + 500_000_000
                ),
                "expired reader must close"
            )
            close(expiryClient)
            expiryInbox.closeAll()
            close(expiryListener)
            unlink(expirySocketPath)

            let socketPath = "/tmp/wattson-inbox-" + String(getpid())
                + "-" + UUID().uuidString.prefix(8) + ".sock"
            require(socketPath != "/var/run/wattson-helper.sock", "must use temporary socket")
            unlink(socketPath)
            let baselineFDs = openFDCount()
            let baselineRSS = maximumResidentBytes()
            let listener = makeListener(at: socketPath)
            let finished = DispatchSemaphore(value: 0)
            let prepareBacklogStarted = DispatchSemaphore(value: 0)
            let backlogClientsReady = DispatchSemaphore(value: 0)
            let slowCompleteStarted = DispatchSemaphore(value: 0)
            let slowCompleteFinished = DispatchSemaphore(value: 0)
            let mutationExecuted = DispatchSemaphore(value: 0)
            let abandonedBlockerStarted = DispatchSemaphore(value: 0)
            let releaseAbandonedBlocker = DispatchSemaphore(value: 0)
            let abandonedMutationExecuted = DispatchSemaphore(value: 0)
            let readyBlockerStarted = DispatchSemaphore(value: 0)
            let releaseReadyBlocker = DispatchSemaphore(value: 0)
            let readyAbandonedMutationExecuted = DispatchSemaphore(value: 0)
            let acceptedBeforeBarrier = DispatchSemaphore(value: 0)
            let stallStarted = DispatchSemaphore(value: 0)
            let stallFinished = DispatchSemaphore(value: 0)
            var serverFailure: String?
            var observedMaximumPending = 0

            DispatchQueue(label: "wattson.inbox.self-test").async {
                var inbox = SocketRequestInbox()
                var running = true
                while running {
                    autoreleasepool {
                        observedMaximumPending = max(observedMaximumPending, inbox.count)
                        switch inbox.takeNextReady() {
                        case let .request(request):
                            defer { close(request.fd) }
                            guard request.peerUID == consoleUID() else {
                                serverFailure = "console UID changed"
                                running = false
                                return
                            }
                            guard let operation = request.object["op"] as? String else {
                                _ = writeAll(
                                    Data("{\"ok\":false,\"error\":\"malformed\"}\n".utf8),
                                    to: request.fd
                                )
                                return
                            }
                            if operation == "shutdown" { running = false }
                            if operation == "prepareBacklog" {
                                prepareBacklogStarted.signal()
                                guard backlogClientsReady.wait(timeout: .now() + 1) == .success else {
                                    serverFailure = "backlog clients not ready"
                                    running = false
                                    return
                                }
                            }
                            if operation == "slowComplete" {
                                slowCompleteStarted.signal()
                                usleep(2_100_000)
                                slowCompleteFinished.signal()
                            }
                            if operation == "mutate" { mutationExecuted.signal() }
                            if operation == "abandonedBlocker" {
                                abandonedBlockerStarted.signal()
                                guard releaseAbandonedBlocker.wait(
                                    timeout: .now() + 1
                                ) == .success else {
                                    serverFailure = "abandoned blocker not released"
                                    running = false
                                    return
                                }
                            }
                            if operation == "abandonedMutation" {
                                abandonedMutationExecuted.signal()
                            }
                            if operation == "readyBlocker" {
                                readyBlockerStarted.signal()
                                guard releaseReadyBlocker.wait(
                                    timeout: .now() + 1
                                ) == .success else {
                                    serverFailure = "ready blocker not released"
                                    running = false
                                    return
                                }
                            }
                            if operation == "readyAbandonedMutation" {
                                readyAbandonedMutationExecuted.signal()
                            }
                            if operation == "acceptanceBarrier" {
                                acceptedBeforeBarrier.signal()
                            }
                            if operation == "stall" {
                                stallStarted.signal()
                                usleep(2_100_000)
                                stallFinished.signal()
                            }
                            let reply = operation == "health"
                                ? "{\"ok\":true,\"health\":true}\n"
                                : "{\"ok\":true}\n"
                            let wroteReply = writeAll(Data(reply.utf8), to: request.fd)
                            guard wroteReply
                                    || operation == "abandonedMutation"
                                    || operation == "readyAbandonedMutation" else {
                                serverFailure = "reply write failed"
                                running = false
                                return
                            }
                        case .expired:
                            break
                        case .abandoned:
                            break
                        case .none:
                            if inbox.poll(listener: listener, timeoutMilliseconds: 25) == nil {
                                serverFailure = "poll failed"
                                running = false
                            }
                        }
                        observedMaximumPending = max(observedMaximumPending, inbox.count)
                    }
                }
                inbox.closeAll()
                finished.signal()
            }

            var silentClients: [Int32] = []
            for _ in 0..<64 { silentClients.append(connectClient(to: socketPath)) }
            let oldSerialLowerBound = Double(silentClients.count) * 2.0
            require(oldSerialLowerBound > 1.0, "old serial accept/read loop should fail logically")

            let healthStart = DispatchTime.now().uptimeNanoseconds
            let health = roundTrip(
                path: socketPath,
                fragments: ["{\"_wattsonProtocol\":4,\"op\":\"health\"}\n"]
            )
            let healthSeconds = Double(
                DispatchTime.now().uptimeNanoseconds - healthStart
            ) / 1_000_000_000
            require(strictJSONBool(health?["health"]) == true, "health after silent clients")
            require(healthSeconds < 1.0, "health must not wait behind silent clients")
            require(observedMaximumPending <= maximumPendingSocketClients, "pending cap")

            let peakFDs = openFDCount()
            require(
                peakFDs <= baselineFDs + silentClients.count + maximumPendingSocketClients + 12,
                "file descriptor bound"
            )
            silentClients.forEach { close($0) }
            usleep(200_000)

            // The server writes then closes. Delay the client read by 50 ms to
            // prove buffered bytes survive peer close; on
            // macOS, trying to install SO_RCVTIMEO after that close returns EINVAL.
            let fragmented = roundTrip(
                path: socketPath,
                fragments: ["{\"_wattsonProtocol\":4,\"op", "\":\"health\"}", "\n"],
                pauseMicroseconds: 5_000,
                readDelayMicroseconds: 50_000
            )
            require(strictJSONBool(fragmented?["health"]) == true, "fragmented delayed-read v4")

            let legacy = roundTrip(
                path: socketPath,
                fragments: ["{\"op\":\"health\"}"]
            )
            require(strictJSONBool(legacy?["health"]) == true, "legacy JSON")

            // Both complete frames are parsed into ready FIFO order before the
            // first one blocks. Closing the second caller while it waits in ready
            // must prevent its mutation from executing before its 2 s deadline.
            let readyPrepareClient = connectClient(to: socketPath)
            require(
                writeAll(Data("{\"op\":\"prepareBacklog\"}".utf8), to: readyPrepareClient),
                "ready abandonment prepare write"
            )
            require(
                prepareBacklogStarted.wait(timeout: .now() + 1) == .success,
                "ready abandonment prepare started"
            )
            let readyBlockerClient = connectClient(to: socketPath)
            require(
                writeAll(Data("{\"op\":\"readyBlocker\"}".utf8), to: readyBlockerClient),
                "ready blocker write"
            )
            let readyAbandonedMutationClient = connectClient(to: socketPath)
            require(
                writeAll(
                    Data("{\"op\":\"readyAbandonedMutation\"}".utf8),
                    to: readyAbandonedMutationClient
                ),
                "ready abandoned mutation write"
            )
            backlogClientsReady.signal()
            require(
                strictJSONBool(readJSONObject(from: readyPrepareClient)?["ok"]) == true,
                "ready abandonment prepare response"
            )
            close(readyPrepareClient)
            require(
                readyBlockerStarted.wait(timeout: .now() + 1) == .success,
                "ready blocker started"
            )
            close(readyAbandonedMutationClient)
            releaseReadyBlocker.signal()
            require(
                strictJSONBool(readJSONObject(from: readyBlockerClient)?["ok"]) == true,
                "ready blocker response"
            )
            close(readyBlockerClient)
            let readyAbandonmentBarrier = roundTrip(
                path: socketPath,
                fragments: ["{\"_wattsonProtocol\":4,\"op\":\"health\"}\n"]
            )
            require(
                strictJSONBool(readyAbandonmentBarrier?["health"]) == true,
                "ready abandonment queue drained"
            )
            require(
                readyAbandonedMutationExecuted.wait(timeout: .now() + 0.1) == .timedOut,
                "abandoned ready mutation must not execute"
            )

            // While the serial executor is occupied, this complete mutation is
            // written and its caller closes before the helper reads it. A buffered
            // frame from an abandoned peer must never cause a side effect.
            // Connect the would-be abandoned caller first. Once the blocker
            // behind it starts, FIFO listener admission proves this descriptor
            // is already in the inbox's reading set but has not sent a frame.
            let abandonedMutationClient = connectClient(to: socketPath)
            let abandonedBlockerClient = connectClient(to: socketPath)
            require(
                writeAll(Data("{\"op\":\"abandonedBlocker\"}".utf8), to: abandonedBlockerClient),
                "abandoned blocker write"
            )
            require(
                abandonedBlockerStarted.wait(timeout: .now() + 1) == .success,
                "abandoned blocker started"
            )
            require(
                writeAll(
                    Data("{\"op\":\"abandonedMutation\"}".utf8),
                    to: abandonedMutationClient
                ),
                "abandoned mutation write"
            )
            close(abandonedMutationClient)
            releaseAbandonedBlocker.signal()
            require(
                strictJSONBool(readJSONObject(from: abandonedBlockerClient)?["ok"]) == true,
                "abandoned blocker response"
            )
            close(abandonedBlockerClient)
            let abandonedQueueBarrier = roundTrip(
                path: socketPath,
                fragments: ["{\"_wattsonProtocol\":4,\"op\":\"health\"}\n"]
            )
            require(
                strictJSONBool(abandonedQueueBarrier?["health"]) == true,
                "abandoned queue drained"
            )
            require(
                abandonedMutationExecuted.wait(timeout: .now() + 0.1) == .timedOut,
                "abandoned complete mutation must not execute"
            )

            // Both backlog requests are complete before the serial slow request
            // starts. The following mutation must expire in the ready FIFO and
            // must never reach request execution after its accept-time deadline.
            let prepareClient = connectClient(to: socketPath)
            require(
                writeAll(Data("{\"op\":\"prepareBacklog\"}".utf8), to: prepareClient),
                "prepare backlog write"
            )
            require(
                prepareBacklogStarted.wait(timeout: .now() + 1) == .success,
                "prepare backlog started"
            )
            let slowCompleteClient = connectClient(to: socketPath)
            require(
                writeAll(Data("{\"op\":\"slowComplete\"}".utf8), to: slowCompleteClient),
                "complete slow request write"
            )
            let mutationClient = connectClient(to: socketPath)
            require(
                writeAll(Data("{\"op\":\"mutate\"}".utf8), to: mutationClient),
                "complete mutation request write"
            )
            backlogClientsReady.signal()
            require(
                strictJSONBool(readJSONObject(from: prepareClient)?["ok"]) == true,
                "prepare backlog response"
            )
            close(prepareClient)
            require(
                slowCompleteStarted.wait(timeout: .now() + 1) == .success,
                "complete slow request started"
            )
            require(
                slowCompleteFinished.wait(timeout: .now() + 3) == .success,
                "complete slow request finished"
            )
            require(
                strictJSONBool(readJSONObject(from: slowCompleteClient)?["ok"]) == true,
                "complete slow request response"
            )
            close(slowCompleteClient)
            let expiredMutation = readJSONObject(from: mutationClient)
            close(mutationClient)
            require(
                strictJSONBool(expiredMutation?["ok"]) == false,
                "stale ready mutation must fail"
            )
            require(
                expiredMutation?["error"] as? String == "request expired",
                "stale ready mutation error"
            )
            require(
                mutationExecuted.wait(timeout: .now() + 0.1) == .timedOut,
                "stale ready mutation must not execute"
            )

            // A request that becomes readable only after its accept-time deadline
            // must be rejected before parsing, even when a serial operation kept
            // the event loop occupied past that deadline.
            let overdueClient = connectClient(to: socketPath)
            let barrierClient = connectClient(to: socketPath)
            require(
                writeAll(
                    Data("{\"op\":\"acceptanceBarrier\"}".utf8),
                    to: barrierClient
                ),
                "acceptance barrier write"
            )
            require(
                acceptedBeforeBarrier.wait(timeout: .now() + 1) == .success,
                "overdue client accepted before barrier"
            )
            let acceptanceBarrier = readJSONObject(from: barrierClient)
            close(barrierClient)
            require(
                strictJSONBool(acceptanceBarrier?["ok"]) == true,
                "overdue client acceptance barrier"
            )
            let lateWriter = DispatchGroup()
            let stallClient = connectClient(to: socketPath)
            require(
                writeAll(Data("{\"op\":\"stall\"}".utf8), to: stallClient),
                "stall write"
            )
            require(
                stallStarted.wait(timeout: .now() + 1) == .success,
                "stall started"
            )
            lateWriter.enter()
            DispatchQueue.global(qos: .utility).async {
                usleep(2_050_000)
                _ = writeAll(
                    Data("{\"_wattsonProtocol\":4,\"op\":\"health\"}\n".utf8),
                    to: overdueClient
                )
                lateWriter.leave()
            }
            require(
                stallFinished.wait(timeout: .now() + 3) == .success,
                "stall finished"
            )
            lateWriter.wait()
            let stalled = readJSONObject(from: stallClient)
            close(stallClient)
            require(strictJSONBool(stalled?["ok"]) == true, "serial stall")
            let overdueResponse = readJSONObject(from: overdueClient)
            close(overdueClient)
            require(
                strictJSONBool(overdueResponse?["health"]) != true,
                "post-deadline bytes must not become ready"
            )

            let timeoutClient = connectClient(to: socketPath)
            // connect() only queues the client; the helper's two-second budget
            // intentionally begins at accept(). A FIFO barrier proves this
            // silent client was accepted before starting the real-clock window.
            let timeoutBarrierClient = connectClient(to: socketPath)
            require(
                writeAll(
                    Data("{\"op\":\"acceptanceBarrier\"}".utf8),
                    to: timeoutBarrierClient
                ),
                "timeout acceptance barrier write"
            )
            require(
                acceptedBeforeBarrier.wait(timeout: .now() + 1) == .success,
                "silent client accepted before timeout barrier"
            )
            require(
                strictJSONBool(readJSONObject(from: timeoutBarrierClient)?["ok"]) == true,
                "timeout acceptance barrier response"
            )
            close(timeoutBarrierClient)
            let timeoutDeadline = DispatchTime.now().uptimeNanoseconds + 3_000_000_000
            let reachedEOF = reachesEOF(on: timeoutClient, by: timeoutDeadline)
            close(timeoutClient)
            require(reachedEOF, "silent client must be closed at its monotonic deadline")

            for _ in 0..<128 {
                let response = roundTrip(
                    path: socketPath,
                    fragments: ["{\"op\":\"health\"}"]
                )
                require(strictJSONBool(response?["health"]) == true, "churn health")
            }
            let rssGrowth = maximumResidentBytes() - baselineRSS
            require(rssGrowth < 32 * 1_024 * 1_024, "resident memory bound")

            let shutdown = roundTrip(
                path: socketPath,
                fragments: ["{\"_wattsonProtocol\":4,\"op\":\"shutdown\"}\n"]
            )
            require(strictJSONBool(shutdown?["ok"]) == true, "shutdown response")
            require(finished.wait(timeout: .now() + 3) == .success, "server shutdown")
            close(listener)
            unlink(socketPath)
            require(serverFailure == nil, serverFailure ?? "server failure")
            require(openFDCount() <= baselineFDs + 4, "file descriptors returned to baseline")
            print(
                "poll inbox self-test passed; old serial lower bound "
                    + String(format: "%.0fs", oldSerialLowerBound)
            )
            '''
        )
        with tempfile.TemporaryDirectory() as directory:
            directory_path = pathlib.Path(directory)
            harness_path = directory_path / "main.swift"
            executable_path = directory_path / "poll-inbox-self-test"
            harness_path.write_text(harness_source, encoding="utf-8")
            compile_result = subprocess.run(
                ["/usr/bin/xcrun", "swiftc", str(harness_path), "-o", str(executable_path)],
                check=False,
                text=True,
                capture_output=True,
            )
            self.assertEqual(compile_result.returncode, 0, compile_result.stderr)
            run_result = subprocess.run(
                [str(executable_path)],
                check=False,
                text=True,
                capture_output=True,
                timeout=15,
            )
            self.assertEqual(run_result.returncode, 0, run_result.stderr)
            self.assertIn("poll inbox self-test passed", run_result.stdout)

    def test_get_power_prefers_pstr_and_reads_pdtr_only_as_fallback(self):
        read_body = self.source.split("static func read() -> FixedSMCPower", 1)[1].split(
            "private static func readWatts", 1
        )[0]
        system_read = "let systemW = readWatts(systemKey, connection: connection)"
        adapter_fallback = (
            "adapterW: systemW == nil ? readWatts(adapterKey, connection: connection) : nil"
        )
        self.assertIn(system_read, read_body)
        self.assertIn(adapter_fallback, read_body)
        self.assertLess(read_body.index(system_read), read_body.index(adapter_fallback))
        self.assertIn("service/client for every request is intentional", read_body)

    def test_one_watt_number_is_not_misclassified_as_boolean(self):
        self.assertIn("CFGetTypeID(number) != CFBooleanGetTypeID()", self.client_source)
        self.assertNotIn("!(raw is Bool)", self.client_source)

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
        self.assertIn('operation.rawValue, "\\(uid)"', battery_helpers)
        self.assertIn("CommandLine.arguments.count == 3", battery_helpers)
        self.assertIn("expectedUID == consoleUID()", battery_helpers)
        self.assertIn("dropPrivileges(to: expectedUID)", battery_helpers)
        worker = battery_helpers.split(
            "private func runBatteryPreferenceWorkerIfRequested", 1
        )[1]
        self.assertNotIn("dropHealthProbePrivilegesToConsoleUser()", worker)
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
