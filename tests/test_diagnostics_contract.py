import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "Support" / "WattsonDiagnostics" / "main.swift").read_text(
    encoding="utf-8"
)
BUILD_SCRIPT = (ROOT / "scripts" / "build_diagnostics.sh").read_text(
    encoding="utf-8"
)
SUPPORT_README = (ROOT / "Support" / "WattsonDiagnostics" / "README.md").read_text(
    encoding="utf-8"
)


class WattsonDiagnosticsContractTests(unittest.TestCase):
    def test_tool_is_explicitly_read_only_and_does_not_upload(self):
        self.assertIn("readOnlyCommandArguments", SOURCE)
        self.assertIn("No password was requested", SOURCE)
        self.assertNotIn("sudo", SOURCE)
        self.assertNotIn("URLSession", SOURCE)
        self.assertNotIn("curl", SOURCE)
        self.assertNotIn("temporaryDirectory", SOURCE)
        self.assertIn("maximumCapturedBytes = 100_000", SOURCE)
        self.assertIn("String(decoding: data, as: UTF8.self)", SOURCE)
        self.assertNotIn("bootstrap", SOURCE)
        self.assertNotIn("bootout", SOURCE)
        self.assertNotIn("launchctl\", arguments: [\"enable", SOURCE)
        self.assertNotIn("launchctl\", arguments: [\"disable", SOURCE)
        self.assertNotIn("IORegistryEntryCreateCFProperties", SOURCE)
        self.assertNotIn('"/usr/sbin/ioreg"', SOURCE)
        self.assertNotIn('"/usr/sbin/system_profiler"', SOURCE)
        self.assertNotIn('"/bin/ps"', SOURCE)
        self.assertNotIn("IOPlatformUUID", SOURCE)
        self.assertNotIn('"BatteryData"', SOURCE)

    def test_one_click_path_copies_a_bounded_report(self):
        self.assertIn('title: "Collect & Copy Diagnostics"', SOURCE)
        self.assertIn("#selector(collectAndCopy)", SOURCE)
        self.assertIn("NSPasteboard.general", SOURCE)
        self.assertIn("maximumCharacters: 50_000", SOURCE)
        self.assertIn("maximumCharacters: 100_000", SOURCE)
        self.assertIn("applicationShouldTerminate", SOURCE)
        self.assertIn(".terminateCancel", SOURCE)
        self.assertIn("Review it before sending", SOURCE)

    def test_report_covers_the_public_v3_installation_path(self):
        self.assertIn("/Applications/Wattson.app", SOURCE)
        self.assertIn('"-dlnO@"', SOURCE)
        self.assertIn("/Library/PrivilegedHelperTools/com.leoarrow.wattson.helper", SOURCE)
        self.assertIn("/Library/LaunchDaemons/com.leoarrow.wattson.helper.plist", SOURCE)
        self.assertIn('"--pkg-info", "com.leoarrow.wattson.pkg"', SOURCE)
        self.assertIn('"-n", "600", "/var/log/install.log"', SOURCE)
        self.assertIn('"show", "--last", "15m"', SOURCE)
        self.assertIn('subsystem == \\"com.leoarrow.wattson\\"', SOURCE)
        self.assertNotIn('eventMessage CONTAINS', SOURCE)

    def test_report_identifies_stale_and_duplicate_installations_without_full_ps(self):
        self.assertIn('diagnosticsVersion = "1.1.0"', SOURCE)
        self.assertIn('"/Applications/Wattson.app"', SOURCE)
        self.assertIn('home + "/Applications/Wattson.app"', SOURCE)
        self.assertIn('home + "/Applications/电池功率.app"', SOURCE)
        self.assertIn('com.leoarrow.wattson.login.plist', SOURCE)
        self.assertIn('com.leoarrow.battery-monitor.agent.plist', SOURCE)
        self.assertIn('com.leoarrow.battery-monitor.plist', SOURCE)
        self.assertIn('runningApplications(withBundleIdentifier:', SOURCE)
        self.assertIn('application.processIdentifier', SOURCE)
        self.assertIn('application.bundleURL?.path', SOURCE)
        self.assertIn('application.executableURL?.path', SOURCE)
        self.assertIn('CFBundleShortVersionString', SOURCE)
        self.assertIn('CFBundleVersion', SOURCE)
        self.assertIn('"-n", "hw.model"', SOURCE)

    def test_battery_probe_reads_only_named_properties_and_decodes_temperature(self):
        self.assertIn('IOServiceMatching("AppleSmartBattery")', SOURCE)
        self.assertIn("IORegistryEntryCreateCFProperty", SOURCE)
        for key in (
            "CurrentCapacity",
            "ExternalConnected",
            "IsCharging",
            "FullyCharged",
            "CycleCount",
            "Temperature",
            "VirtualTemperature",
            "Voltage",
            "Amperage",
            "InstantAmperage",
            "PowerTelemetryData",
            "SystemPowerIn",
            "SystemLoad",
            "BatteryPower",
            "SystemPowerInAccumulatorCount",
            "SystemLoadAccumulatorCount",
            "BatteryPowerAccumulatorCount",
        ):
            self.assertIn(f'"{key}"', SOURCE)
        self.assertIn("Double(raw) / 10.0 - 273.15", SOURCE)
        self.assertIn("Double(raw) / 100.0", SOURCE)
        self.assertIn("selected power and accumulator fields only", SOURCE)
        self.assertIn("String(number.uint64Value)", SOURCE)
        self.assertIn(
            "Int32(bitPattern: UInt32(truncatingIfNeeded: number.uint64Value))",
            SOURCE,
        )
        self.assertIn("signed_int32", SOURCE)
        for excluded_key in (
            "AdapterEfficiencyLossAccumulatorCount",
            "BatteryDischargeAccumulatorCount",
            "AccumulatedWallEnergyEstimate",
            "AccumulatedSystemLoad",
            "AccumulatedSystemEnergyConsumed",
            "AccumulatedBatteryPower",
            "AccumulatedAdapterEfficiencyLoss",
            "AccumulatedSystemPowerIn",
            "AccumulatedBatteryDischarge",
        ):
            self.assertNotIn(f'"{excluded_key}"', SOURCE)

    def test_helper_probe_uses_fixed_socket_without_launching_wattson(self):
        self.assertIn("HelperClient.isHealthy()", SOURCE)
        self.assertIn("HelperClient.livePower()", SOURCE)
        self.assertIn("private static let sampleCount = 5", SOURCE)
        self.assertIn("private static let sampleInterval: TimeInterval = 1.0", SOURCE)
        self.assertIn("unique_power_samples", SOURCE)
        self.assertIn("elapsed_ms", SOURCE)
        self.assertIn("getPower requires a v3.0.4+ helper", SOURCE)
        self.assertNotIn('arguments: ["--helper-health-probe"]', SOURCE)
        self.assertNotIn('arguments: ["--helper-power-probe"]', SOURCE)

    def test_build_produces_a_universal_macos_12_app_archive(self):
        self.assertIn("arm64 x86_64", BUILD_SCRIPT)
        self.assertIn("-apple-macos${MIN_MACOS_VERSION}", BUILD_SCRIPT)
        self.assertIn("-verify_arch arm64 x86_64", BUILD_SCRIPT)
        self.assertIn("Wattson-Diagnostics-v${DIAGNOSTICS_VERSION}-macos-universal.zip", BUILD_SCRIPT)
        self.assertIn("codesign --verify --deep --strict", BUILD_SCRIPT)
        self.assertIn("--norsrc --noextattr --noqtn --noacl", BUILD_SCRIPT)
        self.assertIn("archive contains AppleDouble metadata", BUILD_SCRIPT)
        self.assertIn("EXTRACTED_APP", BUILD_SCRIPT)
        self.assertIn("shasum -a 256 -c", BUILD_SCRIPT)
        self.assertIn('DIAGNOSTICS_VERSION="1.1.0"', BUILD_SCRIPT)
        self.assertIn('HELPER_CLIENT_SOURCE="$ROOT_DIR/Core/HelperClient.swift"', BUILD_SCRIPT)
        self.assertIn('"$HELPER_CLIENT_SOURCE"', BUILD_SCRIPT)
        self.assertIn("-framework IOKit", BUILD_SCRIPT)

    def test_macos_15_gatekeeper_guidance_uses_open_anyway(self):
        self.assertIn("macOS 15 or later", SUPPORT_README)
        self.assertIn("System Settings → Privacy", SUPPORT_README)
        self.assertIn("Open Anyway", SUPPORT_README)

    def test_privacy_documentation_matches_the_minimal_probe(self):
        self.assertIn("v1.1.0", SUPPORT_README)
        self.assertIn("does not launch the installed Wattson app", SUPPORT_README)
        self.assertIn("five samples", SUPPORT_README)
        self.assertIn("v3.0.4 or later helper", SUPPORT_README)
        self.assertIn("does not collect hardware serial numbers", SUPPORT_README)
        self.assertIn("complete I/O Registry dump", SUPPORT_README)
        self.assertIn("process list", SUPPORT_README)
        self.assertIn("redactPrivateMachineDetails", SOURCE)
        self.assertIn("NSHomeDirectory()", SOURCE)
        self.assertIn("ProcessInfo.processInfo.hostName", SOURCE)
        self.assertIn("hasSuffix(localSuffix)", SOURCE)
        self.assertIn("redactedHostVariants(for hostName: String)", SOURCE)
        self.assertIn("let candidates = [shortName, shortName + localSuffix, original]", SOURCE)
        self.assertIn("seen.insert($0.lowercased()).inserted", SOURCE)
        self.assertIn("$0.count > $1.count", SOURCE)
        self.assertIn('hostName: "cody-mac"', SOURCE)
        self.assertIn('hostName: "cody-mac.local"', SOURCE)
        self.assertIn('in: "installer host=CODY-MAC.LOCAL"', SOURCE)
        self.assertIn('in: "installer host=CoDy-MaC"', SOURCE)
        self.assertIn('with: "<redacted-host>"', SOURCE)
        self.assertIn("options: .caseInsensitive", SOURCE)
        self.assertIn("current hostname", SUPPORT_README)
        self.assertIn('"$EXECUTABLE_PATH" --host-redaction-self-test', BUILD_SCRIPT)


if __name__ == "__main__":
    unittest.main()
