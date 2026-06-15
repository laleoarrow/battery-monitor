import importlib.util
import pathlib
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
APP_PATH = ROOT / "battery_monitor.py"


def load_module():
    spec = importlib.util.spec_from_file_location(
        "battery_monitor_under_test", APP_PATH
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


SAMPLE_CHARGING = '''
    "CurrentCapacity" = 78
    "Voltage" = 12600
    "Amperage" = 1500
    "ExternalConnected" = Yes
    "IsCharging" = Yes
    "ChargerData" = {"ChargingVoltage"=12600,"ChargingCurrent"=1500}
    "PowerTelemetryData" = {"SystemLoad"=18500,"BatteryPower"=6400,"SystemPowerIn"=37400}
'''

SAMPLE_FULL = '''
    "CurrentCapacity" = 100
    "Voltage" = 12800
    "Amperage" = 0
    "ExternalConnected" = Yes
    "IsCharging" = No
    "FullyCharged" = Yes
    "ChargerData" = {"ChargingVoltage"=4318,"ChargingCurrent"=0}
    "PowerTelemetryData" = {"SystemLoad"=31819,"BatteryPower"=0,"SystemPowerIn"=31819}
'''

SAMPLE_DISCHARGING = '''
    "CurrentCapacity" = 19
    "Voltage" = 12400
    "Amperage" = -920
    "ExternalConnected" = No
    "IsCharging" = No
    "PowerTelemetryData" = {"SystemLoad"=11408,"BatteryPower"=11408}
'''


class ImportGuardTests(unittest.TestCase):
    def test_source_has_main_guard(self):
        source = APP_PATH.read_text(encoding="utf-8")
        self.assertIn("def main():", source)
        self.assertIn('if __name__ == "__main__":', source)

    def test_import_does_not_create_root_window(self):
        module = load_module()
        self.assertFalse(hasattr(module, "root"))
        self.assertTrue(callable(module.main))


class PowerModelTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.module = load_module()

    def test_parse_ioreg_output_extracts_nested_power_fields(self):
        info = self.module.parse_ioreg_output(SAMPLE_CHARGING)
        self.assertEqual(info["CurrentCapacity"], 78)
        self.assertTrue(info["ExternalConnected"])
        self.assertTrue(info["IsCharging"])
        self.assertEqual(info["charger"]["ChargingVoltage"], 12600)
        self.assertEqual(info["charger"]["ChargingCurrent"], 1500)
        self.assertEqual(info["tel"]["SystemLoad"], 18500)

    def test_total_power_prefers_system_load_plus_battery_charge_power(self):
        info = self.module.parse_ioreg_output(SAMPLE_CHARGING)
        snapshot = self.module.compute_power_snapshot(info)
        self.assertEqual(snapshot.state, "charging")
        self.assertAlmostEqual(snapshot.system_w, 18.5, places=1)
        self.assertAlmostEqual(snapshot.battery_charge_w, 18.9, places=1)
        self.assertAlmostEqual(snapshot.total_w, 37.4, places=1)

    def test_full_external_power_does_not_add_battery_charge(self):
        info = self.module.parse_ioreg_output(SAMPLE_FULL)
        snapshot = self.module.compute_power_snapshot(info)
        self.assertEqual(snapshot.state, "plugged_full")
        self.assertAlmostEqual(snapshot.system_w, 31.819, places=3)
        self.assertAlmostEqual(snapshot.battery_charge_w, 0.0, places=1)
        self.assertAlmostEqual(snapshot.total_w, 31.819, places=3)

    def test_discharging_total_uses_system_load_and_exposes_battery_discharge(self):
        info = self.module.parse_ioreg_output(SAMPLE_DISCHARGING)
        snapshot = self.module.compute_power_snapshot(info)
        self.assertEqual(snapshot.state, "low_battery")
        self.assertAlmostEqual(snapshot.system_w, 11.408, places=3)
        self.assertAlmostEqual(snapshot.battery_charge_w, 0.0, places=1)
        self.assertAlmostEqual(snapshot.battery_discharge_w, 11.408, places=3)
        self.assertAlmostEqual(snapshot.total_w, 11.408, places=3)


class ConfigTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.module = load_module()

    def test_load_config_migrates_old_position_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = pathlib.Path(tmp) / "cfg"
            path.write_text("222,333", encoding="utf-8")
            config = self.module.load_config(path)
        self.assertEqual(config["x"], 222)
        self.assertEqual(config["y"], 333)
        self.assertFalse(config["pinned"])
        self.assertTrue(config["desktop_mode"])
        self.assertEqual(config["config_version"], self.module.CONFIG_VERSION)

    def test_old_json_config_keeps_position_but_moves_to_desktop_widget(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = pathlib.Path(tmp) / "cfg"
            path.write_text(
                '{"x": 444, "y": 555, "pinned": true, "desktop_mode": false}',
                encoding="utf-8",
            )
            config = self.module.load_config(path)
        self.assertEqual(config["x"], 444)
        self.assertEqual(config["y"], 555)
        self.assertFalse(config["pinned"])
        self.assertTrue(config["desktop_mode"])

    def test_default_config_starts_as_desktop_widget(self):
        self.assertFalse(self.module.DEFAULT_CONFIG["pinned"])
        self.assertTrue(self.module.DEFAULT_CONFIG["desktop_mode"])

    def test_source_does_not_use_unsafe_objc_bridge(self):
        source = APP_PATH.read_text(encoding="utf-8")
        self.assertNotIn("ctypes", source)
        self.assertNotIn("objc_msgSend", source)

    def test_save_and_load_config_round_trip(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = pathlib.Path(tmp) / "cfg"
            self.module.save_config(
                {
                    "x": 44,
                    "y": 55,
                    "pinned": False,
                    "desktop_mode": True,
                },
                path,
            )
            config = self.module.load_config(path)
        self.assertEqual(config["x"], 44)
        self.assertEqual(config["y"], 55)
        self.assertFalse(config["pinned"])
        self.assertTrue(config["desktop_mode"])


if __name__ == "__main__":
    unittest.main()
