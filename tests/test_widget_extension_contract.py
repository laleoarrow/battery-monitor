import pathlib
import re
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
EXTENSION_SOURCE = ROOT / "BatteryPowerWidgetExtension.swift"


class WidgetExtensionContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = EXTENSION_SOURCE.read_text(encoding="utf-8")

    def test_extension_samples_battery_directly_via_iokit(self):
        self.assertIn('IOServiceMatching("AppleSmartBattery")', self.source)
        self.assertIn("IORegistryEntryCreateCFProperties", self.source)
        # The sandbox denies fork/exec, so the extension must never spawn ioreg.
        self.assertNotIn("Process()", self.source)

    def test_live_sample_falls_back_to_shared_snapshot_then_preview(self):
        current_match = re.search(
            r"static func current\(\) -> BatteryWidgetSnapshot \{(?P<body>.*?)\n    \}",
            self.source,
            re.DOTALL,
        )
        self.assertIsNotNone(current_match)
        body = current_match.group("body")
        live_index = body.index("WidgetPowerSampler.sample()")
        file_index = body.index("loadShared()")
        preview_index = body.index(".preview")
        self.assertLess(live_index, file_index)
        self.assertLess(file_index, preview_index)

    def test_timeline_uses_current_snapshot_not_file_only(self):
        timeline_match = re.search(
            r"func getTimeline\(in context: Context.*?\{(?P<body>.*?)\n    \}",
            self.source,
            re.DOTALL,
        )
        self.assertIsNotNone(timeline_match)
        self.assertIn("BatteryWidgetSnapshot.current()", timeline_match.group("body"))

    def test_tap_refreshes_in_place_instead_of_launching_app(self):
        self.assertIn("struct RefreshBatteryWidgetIntent: AppIntent", self.source)
        self.assertIn("Button(intent: RefreshBatteryWidgetIntent())", self.source)
        self.assertIn("WidgetRefreshFeedbackStore.markRefreshRequested()", self.source)
        self.assertIn('WidgetCenter.shared.reloadTimelines(ofKind: batteryWidgetKind)', self.source)
        self.assertIn(".buttonStyle(.plain)", self.source)

    def test_tap_has_short_visible_feedback(self):
        self.assertIn("private let refreshFeedbackDuration: TimeInterval = 2.5", self.source)
        self.assertIn("UserDefaults.standard.synchronize()", self.source)
        self.assertIn("struct FlipNumberText", self.source)
        self.assertIn("rotation3DEffect", self.source)
        self.assertIn(".transition(.asymmetric(insertion: .push(from: .top), removal: .push(from: .bottom)))", self.source)
        self.assertIn("let showsRefreshFeedback: Bool", self.source)
        self.assertIn("let refreshAnimationID: Double", self.source)
        self.assertIn("WidgetRefreshFeedbackStore.shouldShowFeedback(at: now)", self.source)
        self.assertIn("now.addingTimeInterval(refreshFeedbackDuration)", self.source)
        self.assertNotIn("已刷新", self.source)

    def test_status_dot_is_solid_blue_with_more_spacing(self):
        self.assertIn("struct StatusDot", self.source)
        self.assertIn("Color(hex: 0x4AA3FF)", self.source)
        self.assertIn("HStack(spacing: 12)", self.source)
        self.assertNotIn("RadialGradient", self.source)
        self.assertNotIn(".shadow(color:", self.source)

    def test_widget_does_not_show_timestamp(self):
        self.assertNotIn("timeView", self.source)
        self.assertNotIn(".dateTime.hour", self.source)


if __name__ == "__main__":
    unittest.main()
