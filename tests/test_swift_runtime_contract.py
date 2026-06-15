import pathlib
import re
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
SWIFT_SOURCE = ROOT / "BatteryPowerWidget.swift"


class SwiftRuntimeContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = SWIFT_SOURCE.read_text(encoding="utf-8")

    def test_main_sampling_stays_at_one_second(self):
        self.assertIn(
            "Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true)",
            self.source,
        )

    def test_widget_snapshot_and_reload_share_five_second_gate(self):
        self.assertIn("widgetReloadRequestInterval: TimeInterval = 5", self.source)
        update_body = re.search(
            r"private func update\(\) \{(?P<body>.*?)\n    \}",
            self.source,
            re.DOTALL,
        ).group("body")
        self.assertNotIn("WidgetSnapshotStore.save", update_body)

        sync_match = re.search(
            r"private func syncWidgetIfNeeded\(\) \{(?P<body>.*?)\n    \}",
            self.source,
            re.DOTALL,
        )
        self.assertIsNotNone(sync_match)
        sync_body = sync_match.group("body")
        save_index = sync_body.index("WidgetSnapshotStore.save(latestSnapshot)")
        reload_index = sync_body.index("WidgetCenter.shared.reloadTimelines")
        self.assertLess(save_index, reload_index)
        self.assertIn(
            "guard WidgetSnapshotStore.save(latestSnapshot) else",
            sync_body,
        )

    def test_glow_runs_at_fifteen_fps_with_same_cycle_speed(self):
        self.assertIn("pulsePhase += 0.32", self.source)
        self.assertIn("withTimeInterval: 1.0 / 15.0", self.source)

    def test_status_dot_gap_is_four_points(self):
        self.assertIn("let dotToValueGap: CGFloat = 4", self.source)

    def test_time_formatter_is_cached(self):
        self.assertIn("private static let timeFormatter", self.source)
        self.assertIn("Self.timeFormatter.string(from: Date())", self.source)
        time_body = re.search(
            r"private func timeString\(\) -> String \{(?P<body>.*?)\n    \}",
            self.source,
            re.DOTALL,
        ).group("body")
        self.assertNotIn("DateFormatter()", time_body)


if __name__ == "__main__":
    unittest.main()
