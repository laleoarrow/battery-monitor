from __future__ import annotations

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MAIN = ROOT / "main.swift"
DIAGNOSTICS = ROOT / "Core" / "Diagnostics"
DIAGNOSTIC_FILES = (
    DIAGNOSTICS / "PowerObservationCaptureCommand.swift",
    DIAGNOSTICS / "PowerObservationCollector.swift",
    DIAGNOSTICS / "AppleSmartBatteryObservationReader.swift",
    DIAGNOSTICS / "DirectSMCObservationReader.swift",
    DIAGNOSTICS / "PowerObservationJSONLWriter.swift",
)


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def diagnostic_source() -> str:
    return "\n".join(read(path) for path in DIAGNOSTIC_FILES)


class PowerObservationCaptureContractTests(unittest.TestCase):
    def test_capture_branch_is_debug_only_and_precedes_nsapplication_shared(self) -> None:
        source = read(MAIN)
        marker = '"--power-observation-capture"'
        capture_index = source.index(marker)
        app_index = source.index("NSApplication.shared")
        self.assertLess(capture_index, app_index)

        prefix = source[:capture_index]
        self.assertGreater(prefix.rfind("#if DEBUG"), prefix.rfind("#endif"))
        branch_end = source.index("#endif", capture_index)
        self.assertLess(capture_index, branch_end)
        self.assertIn("PowerObservationCaptureCommand.run", source[capture_index:branch_end])
        self.assertIn("exit(exitCode)", source[capture_index:branch_end])

    def test_all_diagnostics_sources_are_wrapped_in_debug_guards(self) -> None:
        self.assertEqual({path.name for path in DIAGNOSTIC_FILES}, {
            "PowerObservationCaptureCommand.swift",
            "PowerObservationCollector.swift",
            "AppleSmartBatteryObservationReader.swift",
            "DirectSMCObservationReader.swift",
            "PowerObservationJSONLWriter.swift",
        })
        for path in DIAGNOSTIC_FILES:
            source = read(path)
            stripped = source.strip()
            self.assertTrue(stripped.startswith("#if DEBUG"), path)
            self.assertTrue(stripped.endswith("#endif"), path)
            self.assertEqual(source.count("#if DEBUG"), 1, path)

        writer = read(DIAGNOSTICS / "PowerObservationJSONLWriter.swift")
        for required in (
            "fdopendir(",
            "readdir(",
            "fstatat(",
            "AT_SYMLINK_NOFOLLOW",
            "O_NONBLOCK",
            "fstat(inputFD",
            "errno == EEXIST",
            "throw PowerObservationWriterError.cannotCreate",
            'entry.name.hasSuffix(".recovered.partial")',
            'let temporaryName = stem + ".recovered.partial"',
            "let inputCloseResult = close(inputFD)",
            "guard inputCloseResult == 0 else",
            "private static func readAll(",
            ") throws -> Data",
            "data = try readAll(",
            "let streamCloseResult = closedir(stream)",
            "guard streamCloseResult == 0 else",
            "let scanCloseResult = close(scanFD)",
        ):
            self.assertIn(required, writer)
        self.assertNotIn("contentsOfDirectory(", writer)

        recovery_start = writer.index("static func recoverEligiblePartials")
        recovery_end = writer.index("private func encodedLine", recovery_start)
        recovery = writer[recovery_start:recovery_end]
        self.assertIn("throw error", recovery)
        self.assertIn("outputIsOpen", recovery)
        self.assertNotIn("guard inputFD >= 0 else { continue }", recovery)
        self.assertNotIn("guard let data,", recovery)
        self.assertNotIn('let temporaryName = stem + ".recovering"', recovery)
        self.assertNotIn("if errno == EEXIST { continue }", recovery)
        self.assertNotIn("defer { closedir(stream) }", writer)

        cleanup_start = writer.index("private static func cleanupDirectory")
        cleanup_end = writer.index(
            "private static func directoryCaptureBytes",
            cleanup_start,
        )
        cleanup = writer[cleanup_start:cleanup_end]
        self.assertIn(
            "guard unlinkat(directoryFD, entry.name, 0) == 0 else {",
            cleanup,
        )
        self.assertNotIn(
            "if unlinkat(directoryFD, entry.name, 0) == 0",
            cleanup,
        )

    def test_diagnostics_do_not_reference_helper_or_helper_socket(self) -> None:
        source = diagnostic_source()
        for forbidden in (
            "HelperClient",
            "/var/run/wattson-helper.sock",
            "wattson-helper.sock",
            '"getPower"',
            '"getPowerObservation"',
        ):
            self.assertNotIn(forbidden, source)

    def test_diagnostics_do_not_reference_network_upload_or_clipboard(self) -> None:
        source = diagnostic_source()
        for forbidden in (
            "URLSession",
            "NWConnection",
            "Network.framework",
            "NSPasteboard",
            "pbcopy",
            "curl ",
            "upload",
        ):
            self.assertNotIn(forbidden, source)

    def test_diagnostics_do_not_reference_sudo_launchctl_or_pmset(self) -> None:
        source = diagnostic_source()
        for forbidden in ("sudo", "launchctl", "pmset"):
            self.assertNotIn(forbidden, source)

    def test_registry_reader_uses_a_fixed_property_allowlist(self) -> None:
        source = read(DIAGNOSTICS / "AppleSmartBatteryObservationReader.swift")
        match = re.search(
            r"static let topLevelPropertyAllowlist = \[(.*?)\n    \]",
            source,
            flags=re.S,
        )
        self.assertIsNotNone(match)
        keys = re.findall(r'"([A-Za-z0-9]+)"', match.group(1))
        self.assertEqual(keys, [
            "CurrentCapacity",
            "MaxCapacity",
            "ExternalConnected",
            "IsCharging",
            "Voltage",
            "InstantAmperage",
            "Amperage",
            "PowerTelemetryData",
            "AdapterDetails",
            "PowerOutDetails",
        ])
        self.assertIn(
            "readAllowlistedProperties(\n            Self.topLevelPropertyAllowlist",
            source,
        )
        for allowlist in (
            "telemetryPropertyAllowlist",
            "adapterPropertyAllowlist",
            "powerOutPropertyAllowlist",
        ):
            self.assertGreaterEqual(source.count(allowlist), 2, allowlist)
        self.assertIn("allowlistedDictionaryValue(", source)
        self.assertNotRegex(
            source,
            r"for\s*\(\s*key\s*,\s*value\s*\)\s*in\s*dictionary",
        )

    def test_registry_reader_does_not_create_full_registry_dictionary(self) -> None:
        source = diagnostic_source()
        self.assertNotIn("IORegistryEntryCreateCFProperties", source)
        self.assertIn("IORegistryEntryCreateCFProperty", source)

    def test_diagnostics_do_not_reference_sensitive_registry_keys(self) -> None:
        source = diagnostic_source()
        for forbidden in (
            '"LocationID"',
            '"Serial"',
            '"SerialNumber"',
            '"BatterySerialNumber"',
            '"UUID"',
            '"DeviceName"',
            '"ProductName"',
            '"VendorName"',
            '"IORegistryPath"',
        ):
            self.assertNotIn(forbidden, source)
        self.assertIn("locationIdentifierWasPresent", source)

    def test_pdpowermw_is_not_used_as_measured_fallback(self) -> None:
        source = read(DIAGNOSTICS / "AppleSmartBatteryObservationReader.swift")
        measured_start = source.index("private func portMeasuredWatts")
        measured_end = source.index("private func portPDPowerRaw", measured_start)
        measured_block = source[measured_start:measured_end]
        self.assertIn('key: "Watts"', measured_block)
        self.assertNotIn("PDPowermW", measured_block)

        pd_start = measured_end
        pd_end = source.index("private func integerPowerReading", pd_start)
        pd_block = source[pd_start:pd_end]
        self.assertIn('key: "PDPowermW"', pd_block)
        self.assertIn("kind: .raw", pd_block)
        self.assertIn("semantic: .unknown", pd_block)
        self.assertIn("watts: nil", pd_block)

    def test_adapter_details_watts_is_classified_as_capability(self) -> None:
        source = read(DIAGNOSTICS / "AppleSmartBatteryObservationReader.swift")
        start = source.index("private func adapterRatedWatts")
        end = source.index("private func portMeasuredWatts", start)
        block = source[start:end]
        self.assertIn('key: "Watts"', block)
        self.assertIn("kind: .capability", block)
        self.assertIn("semantic: .adapterCapability", block)
        self.assertNotIn("semantic: .adapterInput", block)

    def test_diagnostics_do_not_call_existing_fusion_functions(self) -> None:
        source = diagnostic_source()
        for forbidden in (
            "resolvedPower",
            "resolvedLivePower",
            "PowerSnapshot(",
            "PowerSnapshot.state",
            "PowerSnapshot.epsilon",
        ):
            self.assertNotIn(forbidden, source)


if __name__ == "__main__":
    unittest.main()
