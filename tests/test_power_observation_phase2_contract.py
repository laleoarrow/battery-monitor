import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
CORE = ROOT / "Core"
HELPER_V5 = ROOT / "HelperV5" / "PowerObservationV5Support.swift"
PACKAGE = ROOT / "Package.swift"
STATUS = ROOT / "MenuBar" / "StatusItemController.swift"


class PowerObservationPhase2ContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.package = PACKAGE.read_text(encoding="utf-8")
        cls.wire = (CORE / "PowerObservationWireV5.swift").read_text(encoding="utf-8")
        cls.client = (CORE / "HelperClientPowerObservationV5.swift").read_text(encoding="utf-8")
        cls.fusion = (CORE / "PowerObservationFusion.swift").read_text(encoding="utf-8")
        cls.shadow = (CORE / "PowerObservationShadow.swift").read_text(encoding="utf-8")
        cls.replay = (CORE / "PowerObservationFusionReplay.swift").read_text(encoding="utf-8")
        cls.reader = (CORE / "AppleSmartBatteryPowerObservationReader.swift").read_text(encoding="utf-8")
        cls.runtime = (CORE / "PowerObservationRuntimeController.swift").read_text(encoding="utf-8")
        cls.status = STATUS.read_text(encoding="utf-8")
        cls.helper = HELPER_V5.read_text(encoding="utf-8")

    def test_package_compiles_helper_v5_support_without_changing_existing_helper_source(self):
        self.assertIn('name: "WattsonHelperV5Support"', self.package)
        self.assertIn('path: "HelperV5"', self.package)
        self.assertRegex(
            self.package,
            r'name: "WattsonHelper"[\s\S]*?dependencies: \["WattsonHelperV5Support"\][\s\S]*?sources: \["wattson-helper.swift"\]',
        )
        self.assertIn('name: "WattsonHelperV5SupportTests"', self.package)

    def test_v5_wire_uses_fixed_protocol_operation_clock_and_frame_limit(self):
        for token in (
            'static let protocolVersion = 5',
            'static let operation = "getPowerObservation"',
            'static let clockName = "CLOCK_MONOTONIC_RAW"',
            'static let maximumFrameBytes = 4_096',
        ):
            self.assertIn(token, self.wire)
        self.assertIn(
            'public static let maximumResponseBytes = 4_096',
            self.helper,
        )
        self.assertIn(
            'guard data.count < Self.maximumResponseBytes else { return nil }',
            self.helper,
        )

    def test_v5_wire_requires_exact_three_key_order_and_required_nullable_fields(self):
        self.assertIn('static let requiredKeyOrder = ["PDTR", "PSTR", "PPBR"]', self.wire)
        for token in (
            'decodeRequiredNullable(String.self, forKey: .dataTypeFourCC)',
            'decodeRequiredNullable(String.self, forKey: .rawBytesHex)',
            'decodeRequiredNullable(Double.self, forKey: .decodedWatts)',
            'decodeRequiredNullable(Int32.self, forKey: .ioReturn)',
            'decodeRequiredNullable(String.self, forKey: .validationIssue)',
        ):
            self.assertIn(token, self.wire)

    def test_helper_support_opens_once_reads_fixed_order_and_continues_per_key(self):
        self.assertIn('public enum HelperV5FixedSMCKey: String, CaseIterable', self.helper)
        self.assertIn('case PDTR', self.helper)
        self.assertIn('case PSTR', self.helper)
        self.assertIn('case PPBR', self.helper)
        self.assertIn('let opened = backend.open()', self.helper)
        self.assertIn('for key in HelperV5FixedSMCKey.allCases', self.helper)
        self.assertIn('Self.normalized(backend.read(key), for: key)', self.helper)
        self.assertNotIn('break', self.helper.split('for key in HelperV5FixedSMCKey.allCases', 1)[1].split('backend.close()', 1)[0])

    def test_helper_support_strictly_decodes_fixed_v5_request_without_caller_key(self):
        for token in (
            'public struct HelperV5RequestPayload',
            'public struct HelperV5RequestDecoder',
            '"_wattsonProtocol", "op", "clientSequence"',
            '"getPowerObservation"',
            'Set(object.keys) == Self.requiredKeys',
        ):
            self.assertIn(token, self.helper)
        self.assertNotIn('requestedKey', self.helper)

    def test_helper_support_exposes_no_caller_selected_smc_key_or_write_command(self):
        for forbidden in (
            'callerKey',
            'requestedKey',
            'writeKey',
            'writeBytesCommand',
            'SMC write',
        ):
            self.assertNotIn(forbidden, self.helper)
        self.assertIn('HelperV5FixedSMCKey', self.helper)

    def test_helper_support_preserves_raw_bytes_type_timing_and_nonfinite_failure(self):
        for token in (
            'dataTypeFourCC',
            'rawBytes',
            'decodedWatts',
            'startedNs',
            'endedNs',
            'value.isFinite',
            'status: .invalidValue',
        ):
            self.assertIn(token, self.helper)
        for fixed_issue in (
            '"connection unavailable"',
            '"key unavailable"',
            '"key info failed"',
            '"value read failed"',
            '"unsupported type"',
            '"invalid value"',
        ):
            self.assertIn(fixed_issue, self.helper)
        self.assertNotIn('opened.validationIssue ??', self.helper)

    def test_client_performs_at_most_one_v5_then_one_v4_request(self):
        self.assertEqual(self.client.count('transport.exchange('), 2)
        self.assertIn('return fetchLegacyV4()', self.client)
        self.assertNotIn('while ', self.client.split('struct PowerObservationV5Client', 1)[1].split('#if os(macOS)', 1)[0])

    def test_valid_or_partial_v5_is_never_spliced_with_v4(self):
        self.assertIn('case let .response(response):', self.client)
        response_case = self.client.split('case let .response(response):', 1)[1].split('case .legacyOrUnsupportedProtocol:', 1)[0]
        self.assertIn('return .v5(response)', response_case)
        self.assertNotIn('fetchLegacyV4', response_case)
        malformed_case = self.client.split('case let .malformed(failure):', 1)[1].split('}', 1)[0]
        self.assertNotIn('fetchLegacyV4', malformed_case)

    def test_fusion_foundation_is_shadow_only_and_does_not_reference_ui_or_power_snapshot(self):
        self.assertIn('let userVisibleEligible: Bool', self.fusion)
        self.assertGreaterEqual(self.fusion.count('userVisibleEligible: false'), 3)
        for forbidden in (
            'PowerSnapshot',
            'StatusItemController',
            'Popover',
            'refreshPresentation',
            'snapshot.adapterW =',
        ):
            self.assertNotIn(forbidden, self.fusion + self.shadow + self.replay)

    def test_fusion_never_adds_device_output_to_system_or_uses_ppbr_for_direction(self):
        self.assertIn('deviceOutputAuxiliary', self.fusion)
        self.assertIn('batteryDischargeMagnitude', self.fusion)
        self.assertIn('batteryDirectionUnavailable', self.fusion)
        for forbidden_pattern in (
            r'system[^\n]*\+[^\n]*deviceOutput',
            r'deviceOutput[^\n]*\+[^\n]*system',
            r'signedWatts:\s*smcPPBR',
        ):
            self.assertIsNone(re.search(forbidden_pattern, self.fusion))

    def test_pstr_anchor_selection_is_semantic_and_freshness_policy_is_explicit(self):
        anchor_function = self.fusion.split(
            'static func anchors(from observation:', 1
        )[1].split('static func resolve(', 1)[0]
        self.assertIn('systemLoad', anchor_function)
        self.assertNotIn('systemPowerIn.presence', anchor_function)
        self.assertIn('maximumUnchangedAnchorMilliseconds: Double?', self.fusion)
        self.assertIn('case .unknown, .stale:', self.fusion)

    def test_fusion_has_no_default_band_policy_or_magic_hardware_threshold(self):
        self.assertNotIn('static let default', self.fusion)
        self.assertNotIn('PSTRBandPolicy(', self.fusion.split('struct PSTRBandPolicy', 1)[0])
        self.assertIn('policy: PSTRBandPolicy?', self.fusion)
        self.assertIn('return .policyUnavailable', self.fusion)

    def test_fusion_preserves_nonzero_residual_instead_of_repairing_inputs(self):
        self.assertIn('nonzero-residual-preserved', self.fusion)
        self.assertIn('adapter.watts - system.watts - signedWatts', self.fusion)
        for forbidden in (
            'adapter.watts = system',
            'system.watts = adapter',
            'battery.signedWatts = adapter',
            'abs(telemetry.systemLoad',
        ):
            self.assertNotIn(forbidden, self.fusion)

    def test_v5_raw_reader_does_not_add_uncontracted_upper_watt_clamp(self):
        combined = self.wire + self.helper
        self.assertNotIn('watts <= 1_000', combined)
        self.assertNotIn('(0...1_000)', combined)
        self.assertIn('key != .PPBR || watts >= 0', self.helper)
        self.assertIn('if key == "PPBR", watts < 0', self.wire)

    def test_phase2_foundation_adds_no_network_upload_analytics_or_privileged_mutation(self):
        combined = self.wire + self.client + self.fusion + self.shadow + self.replay + self.helper
        for forbidden in (
            'URLSession',
            'NWConnection',
            'Network.framework',
            'curl',
            'upload',
            'analytics',
            'pmset',
            'launchctl',
            'setMode',
            'IOConnectCallStructMethod' + '(connection, 5',
        ):
            self.assertNotIn(forbidden, combined)

    def test_offline_replay_is_pure_shadow_and_uses_no_default_policy(self):
        self.assertIn('struct PowerObservationFusionReplay', self.replay)
        self.assertIn('policy: PSTRBandPolicy?', self.replay)
        self.assertIn('PowerObservationFusion.resolve(', self.replay)
        self.assertIn('PowerObservationShadowEvaluator.compare(', self.replay)
        for forbidden in ('PowerSnapshot', 'StatusItemController', 'os_log', 'UserDefaults'):
            self.assertNotIn(forbidden, self.replay)

    def test_shadow_comparison_is_pure_and_keeps_legacy_values_explicit(self):
        self.assertIn('struct LegacyVisiblePower', self.shadow)
        self.assertIn('struct PowerShadowComparison', self.shadow)
        self.assertIn('userVisibleValuesUnchanged: !resolution.userVisibleEligible', self.shadow)
        self.assertNotIn('os_log', self.shadow)
        self.assertNotIn('UserDefaults', self.shadow)

    def test_production_reader_is_allowlisted_and_never_materializes_registry_dictionary(self):
        for required in (
            '"ExternalConnected"',
            '"IsCharging"',
            '"Voltage"',
            '"InstantAmperage"',
            '"Amperage"',
            '"PowerTelemetryData"',
            '"PowerOutDetails"',
            'IORegistryEntryCreateCFProperty',
            'maximumTrackingGapNanoseconds',
            'resetFreshness()',
        ):
            self.assertIn(required, self.reader)
        self.assertNotIn('IORegistryEntryCreateCFProperties', self.reader)
        for forbidden in (
            '"Serial"', '"SerialNumber"', '"UUID"',
            '"DeviceName"', '"ProductName"', '"VendorName"',
            '"IORegistryPath"',
        ):
            self.assertNotIn(forbidden, self.reader)

    def test_runtime_keeps_nil_policy_shadow_only_and_uses_no_ppbr_direction(self):
        self.assertIn('policy: nil', self.runtime)
        self.assertIn('assert(!resolution.userVisibleEligible)', self.runtime)
        self.assertIn('PowerObservationShadowEvaluator.compare(', self.runtime)
        self.assertIn('let adapter = watts("PDTR")', self.runtime)
        self.assertIn('let system = watts("PSTR")', self.runtime)
        self.assertIn('source: .batteryVoltageTimesCurrent', self.runtime)
        self.assertIn('if residual != 0', self.runtime)
        visible = self.runtime.split('private func resolvedLegacySnapshot', 1)[1].split(
            'private static func monotonicNow', 1
        )[0]
        self.assertNotIn('PPBR', visible)
        self.assertNotIn('PSTRBandPolicy(', self.runtime)

    def test_status_controller_never_publishes_shadow_resolution(self):
        finish = self.status.split('private func finishSample', 1)[1].split(
            'private func refreshPresentation', 1
        )[0]
        self.assertIn('result.visibleSnapshot', finish)
        self.assertNotIn('result.resolution', finish)
        self.assertIn('requiresFreshFollowUp', finish)

    def test_runtime_preserves_v4_and_failure_paths_and_parallelizes_acquisition(self):
        self.assertIn('case let .legacyV4(power):', self.runtime)
        self.assertIn('case .failed:', self.runtime)
        self.assertIn('guard let livePower else { return snapshot }', self.runtime)
        self.assertEqual(self.runtime.count('acquisitionQueue.async'), 3)
        self.assertIn('group.wait()', self.runtime)

    def test_no_phase1_raw_schema_or_existing_helper_file_is_redeclared(self):
        combined = self.wire + self.client + self.fusion + self.shadow + self.replay + self.helper
        self.assertNotIn('struct RawPowerObservation {', combined)
        self.assertNotIn('enum BatterySampler', combined)
        self.assertNotIn('private func handle(_ request: SocketRequest)', combined)


if __name__ == "__main__":
    unittest.main()
