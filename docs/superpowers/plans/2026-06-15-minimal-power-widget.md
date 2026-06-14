# Minimal Power Widget Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the existing Tkinter battery monitor into a tiny desktop-style power widget that shows total power by default, expands details on Cmd-hover, and exposes settings through a right-click menu.

**Architecture:** Keep the current single-file Tkinter app, but make it import-safe and split pure power/config logic from window drawing. Use stdlib `unittest` for pure parsing and calculation tests; verify Tkinter layout and macOS power-state behavior manually because those depend on the host window server and battery state.

**Tech Stack:** Python 3, Tkinter Canvas, macOS `ioreg`, optional macOS `powermetrics`, stdlib `unittest`, existing `scripts/install.sh`.

---

## File Structure

- Modify: `/Users/leoarrow/Project/mypackage/agents/电池功率/battery_monitor.py`
  - Add import-safe `main()`.
  - Add pure telemetry parsing, power calculation, config persistence, and optional advanced-power helpers.
  - Replace fixed 280x110 layout with compact and expanded Canvas layouts.
  - Add right-click menu and Cmd-hover detail behavior.
- Modify: `/Users/leoarrow/Project/mypackage/agents/电池功率/README.md`
  - Update user-facing feature notes after implementation.
- Create: `/Users/leoarrow/Project/mypackage/agents/电池功率/tests/test_battery_monitor.py`
  - Test import guard, parser behavior, total-power calculation, status color selection, config migration, and advanced-power permission handling.
- Use unchanged: `/Users/leoarrow/Project/mypackage/agents/电池功率/scripts/install.sh`
  - Syncs `battery_monitor.py` to `~/.battery_monitor.py` and rebuilds the app bundle.
- Read as reference: `/Users/leoarrow/Project/mypackage/agents/电池功率/docs/superpowers/specs/2026-06-15-minimal-power-widget-design.md`

## Task 1: Make the App Import-Safe

**Files:**
- Modify: `/Users/leoarrow/Project/mypackage/agents/电池功率/battery_monitor.py`
- Create: `/Users/leoarrow/Project/mypackage/agents/电池功率/tests/test_battery_monitor.py`

- [ ] **Step 1: Write the failing import-guard test**

Create `/Users/leoarrow/Project/mypackage/agents/电池功率/tests/test_battery_monitor.py` with:

```python
import importlib.util
import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
APP_PATH = ROOT / "battery_monitor.py"


def load_module():
    spec = importlib.util.spec_from_file_location("battery_monitor_under_test", APP_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class ImportGuardTests(unittest.TestCase):
    def test_source_has_main_guard(self):
        source = APP_PATH.read_text(encoding="utf-8")
        self.assertIn("def main():", source)
        self.assertIn('if __name__ == "__main__":', source)

    def test_import_does_not_create_root_window(self):
        module = load_module()
        self.assertFalse(hasattr(module, "root"))
        self.assertTrue(callable(module.main))


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the test and verify it fails**

Run:

```bash
python3 -m unittest discover -s tests -p 'test_*.py' -v
```

Expected: FAIL because `battery_monitor.py` does not yet define `main()` and creates `root` at import time.

- [ ] **Step 3: Wrap launch code in `main()`**

In `/Users/leoarrow/Project/mypackage/agents/电池功率/battery_monitor.py`, move the block beginning at `# ══════════════════════════════════════` / `#  Build the Window` through `root.mainloop()` into:

```python
def main():
    global root, canvas
    global close_id, close_x, pin_id
    global txt_time, txt_hero, txt_pct
    global dot_out, dot_mid, dot_core
    global txt_sys_lbl, txt_sys_val, txt_bat_lbl, txt_bat_val

    root = tk.Tk()
    root.withdraw()
    root.title("BatteryMonitor")
    root.overrideredirect(True)
    root.wm_attributes("-transparent", True)
    root.attributes("-topmost", pinned)
    root.attributes("-alpha", 0.0)

    sx, sy = load_pos()
    root.geometry(f"{W}x{H}+{sx}+{sy}")
    root.resizable(False, False)
    root.configure(bg="systemTransparent")

    canvas = tk.Canvas(root, width=W, height=H,
                       bg="systemTransparent", highlightthickness=0, bd=0)
    canvas.pack(fill="both", expand=True)

    rrect(canvas, 0, 0, W, H, r=14, fill="#18181B", outline="#2D2D33", width=1)
    canvas.create_line(14, 78, W-14, 78, fill="#2D2D33", width=1)

    close_id = canvas.create_oval(14, 10, 24, 20, fill="#FF5F56", outline="#E0443E")
    close_x = canvas.create_text(19, 14, text="×", fill="",
                                  font=("Helvetica Neue", 10, "bold"))
    canvas.tag_bind(close_id, "<Button-1>", close_app)
    canvas.tag_bind(close_id, "<Enter>", _enter_close)
    canvas.tag_bind(close_id, "<Leave>", _leave_close)

    pin_id = canvas.create_oval(30, 10, 40, 20, fill="#27C93F", outline="#1AAB2F")
    canvas.tag_bind(pin_id, "<Button-1>", toggle_pin)
    canvas.tag_bind(pin_id, "<Enter>", _enter_pin)
    canvas.tag_bind(pin_id, "<Leave>", _leave_pin)

    txt_time = canvas.create_text(W-14, 15, text="--:--:--", fill="#71717A",
                                  font=("Helvetica Neue", 11), anchor="e")
    txt_hero = canvas.create_text(14, 48, text="-- W", fill="#FFFFFF",
                                  font=("Helvetica Neue", 30, "bold"), anchor="w")

    dot_out = canvas.create_oval(DOT_X-7, DOT_Y-7, DOT_X+7, DOT_Y+7,
                                 fill="#18181B", outline="")
    dot_mid = canvas.create_oval(DOT_X-5, DOT_Y-5, DOT_X+5, DOT_Y+5,
                                 fill="#18181B", outline="")
    dot_core = canvas.create_oval(DOT_X-3, DOT_Y-3, DOT_X+3, DOT_Y+3,
                                  fill="#71717A", outline="")

    txt_pct = canvas.create_text(W-14, 50, text="--%", fill="#FFFFFF",
                                 font=("Helvetica Neue", 18, "bold"), anchor="e")
    txt_sys_lbl = canvas.create_text(18, 92, text="负载:", fill="#71717A",
                                     font=("Helvetica Neue", 11), anchor="w")
    txt_sys_val = canvas.create_text(52, 92, text="--", fill="#A1A1AA",
                                     font=("Helvetica Neue", 11, "bold"), anchor="w")
    txt_bat_lbl = canvas.create_text(148, 92, text="放电:", fill="#71717A",
                                     font=("Helvetica Neue", 11), anchor="w")
    txt_bat_val = canvas.create_text(182, 92, text="--", fill="#A1A1AA",
                                     font=("Helvetica Neue", 11, "bold"), anchor="w")

    canvas.bind("<Button-1>", _start)
    canvas.bind("<B1-Motion>", _drag)
    canvas.bind("<ButtonRelease-1>", lambda e: save_pos())

    root.deiconify()
    root.update()
    update_data()
    animate()
    for i in range(11):
        root.attributes("-alpha", i / 10.0 * 0.95)
        root.update()
        time.sleep(0.012)
    root.mainloop()


if __name__ == "__main__":
    main()
```

Keep `W`, `H`, `pinned`, and helper functions at module scope for this task.

- [ ] **Step 4: Run the test and verify it passes**

Run:

```bash
python3 -m unittest discover -s tests -p 'test_*.py' -v
```

Expected: PASS for both import-guard tests.

- [ ] **Step 5: Commit**

```bash
git add battery_monitor.py tests/test_battery_monitor.py
git commit -m "test: make battery monitor import safe"
```

## Task 2: Add Power Parsing and Total-Power Model

**Files:**
- Modify: `/Users/leoarrow/Project/mypackage/agents/电池功率/battery_monitor.py`
- Modify: `/Users/leoarrow/Project/mypackage/agents/电池功率/tests/test_battery_monitor.py`

- [ ] **Step 1: Add failing parser and calculation tests**

Append these tests to `/Users/leoarrow/Project/mypackage/agents/电池功率/tests/test_battery_monitor.py`:

```python
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
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
python3 -m unittest discover -s tests -p 'test_*.py' -v
```

Expected: FAIL with missing `parse_ioreg_output` and `compute_power_snapshot`.

- [ ] **Step 3: Add the power model code**

In `/Users/leoarrow/Project/mypackage/agents/电池功率/battery_monitor.py`, add imports and pure helpers near the top:

```python
from dataclasses import dataclass


@dataclass(frozen=True)
class PowerSnapshot:
    percent: int
    plugged: bool
    charging: bool
    state: str
    system_w: float
    battery_charge_w: float
    battery_discharge_w: float
    total_w: float
    status_label: str
    status_color: str
    hero_color: str


def _extract_int_map(name, text):
    match = re.search(rf'"{name}"\s*=\s*\{{([^}}]+)\}}', text)
    values = {}
    if not match:
        return values
    for key, raw in re.findall(r'"?(\w+)"?\s*=\s*(-?\d+)', match.group(1)):
        values[key] = int(raw)
    return values


def parse_ioreg_output(text):
    info = {}
    for key in ("CurrentCapacity", "MaxCapacity", "Voltage", "Amperage",
                "ExternalConnected", "IsCharging", "FullyCharged"):
        match = re.search(fr'"{key}"\s*=\s*(-?[0-9]+|Yes|No)', text)
        if not match:
            continue
        raw = match.group(1)
        if raw == "Yes":
            info[key] = True
        elif raw == "No":
            info[key] = False
        else:
            info[key] = int(raw)

    info["tel"] = _extract_int_map("PowerTelemetryData", text)
    info["charger"] = _extract_int_map("ChargerData", text)
    return info


def _mw_from_map(values, key):
    value = values.get(key)
    return value / 1000.0 if value is not None else None


def _battery_fallback_w(info):
    return abs(info.get("Voltage", 0) * info.get("Amperage", 0) / 1e6)


def _charge_power_w(info, charging):
    charger = info.get("charger", {})
    voltage = charger.get("ChargingVoltage")
    current = charger.get("ChargingCurrent")
    if charging and voltage and current and current > 0:
        return abs(voltage * current / 1e6)
    if not charging:
        return 0.0

    tel_power = _mw_from_map(info.get("tel", {}), "BatteryPower")
    if tel_power is not None:
        return abs(tel_power)
    return _battery_fallback_w(info)


def _discharge_power_w(info, plugged):
    if plugged:
        return 0.0
    tel_power = _mw_from_map(info.get("tel", {}), "BatteryPower")
    if tel_power is not None:
        return abs(tel_power)
    return _battery_fallback_w(info)


def compute_power_snapshot(info):
    percent = int(info.get("CurrentCapacity", 0))
    plugged = bool(info.get("ExternalConnected", False))
    charging = bool(info.get("IsCharging", False))
    tel = info.get("tel", {})

    charge_w = _charge_power_w(info, charging)
    system_w = _mw_from_map(tel, "SystemLoad")
    if system_w is None:
        system_in = _mw_from_map(tel, "SystemPowerIn")
        system_w = max(system_in - charge_w, 0.0) if system_in is not None else _battery_fallback_w(info)

    discharge_w = _discharge_power_w(info, plugged)
    total_w = max(system_w, 0.0) + max(charge_w, 0.0)

    if charging:
        state = "charging"
        status_label = "充电"
        status_color = "#30D158"
        hero_color = "#30D158"
    elif plugged:
        state = "plugged_full"
        status_label = "外接电源"
        status_color = "#0A84FF"
        hero_color = "#0A84FF"
    elif percent <= 20:
        state = "low_battery"
        status_label = "低电量"
        status_color = "#FF453A"
        hero_color = "#FFFFFF"
    else:
        state = "discharging"
        status_label = "放电"
        status_color = "#A1A1AA"
        hero_color = "#FFFFFF"

    return PowerSnapshot(
        percent=percent,
        plugged=plugged,
        charging=charging,
        state=state,
        system_w=system_w,
        battery_charge_w=charge_w,
        battery_discharge_w=discharge_w,
        total_w=total_w,
        status_label=status_label,
        status_color=status_color,
        hero_color=hero_color,
    )
```

Update `get_battery_info()` to use the parser:

```python
def get_battery_info():
    try:
        out = subprocess.check_output(
            "ioreg -rd1 -c AppleSmartBattery", shell=True
        ).decode()
    except Exception:
        return {}
    return parse_ioreg_output(out)
```

- [ ] **Step 4: Run tests and verify pass**

Run:

```bash
python3 -m unittest discover -s tests -p 'test_*.py' -v
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add battery_monitor.py tests/test_battery_monitor.py
git commit -m "feat: calculate total battery widget power"
```

## Task 3: Add Config Persistence for Modes

**Files:**
- Modify: `/Users/leoarrow/Project/mypackage/agents/电池功率/battery_monitor.py`
- Modify: `/Users/leoarrow/Project/mypackage/agents/电池功率/tests/test_battery_monitor.py`

- [ ] **Step 1: Add failing config tests**

Append these tests:

```python
import tempfile


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
        self.assertTrue(config["pinned"])
        self.assertFalse(config["desktop_mode"])
        self.assertFalse(config["advanced_power"])

    def test_save_and_load_config_round_trip(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = pathlib.Path(tmp) / "cfg"
            self.module.save_config({
                "x": 44,
                "y": 55,
                "pinned": False,
                "desktop_mode": True,
                "advanced_power": True,
            }, path)
            config = self.module.load_config(path)
        self.assertEqual(config["x"], 44)
        self.assertEqual(config["y"], 55)
        self.assertFalse(config["pinned"])
        self.assertTrue(config["desktop_mode"])
        self.assertTrue(config["advanced_power"])
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
python3 -m unittest discover -s tests -p 'test_*.py' -v
```

Expected: FAIL because `load_config` and `save_config` do not exist.

- [ ] **Step 3: Implement JSON config with old file migration**

In `battery_monitor.py`, add `json` import and replace `load_pos()` / `save_pos()` with:

```python
import json


DEFAULT_CONFIG = {
    "x": 200,
    "y": 100,
    "pinned": True,
    "desktop_mode": False,
    "advanced_power": False,
}


def load_config(path=CFG):
    try:
        raw = open(path, encoding="utf-8").read().strip()
    except Exception:
        return dict(DEFAULT_CONFIG)

    if "," in raw and not raw.startswith("{"):
        try:
            x, y = raw.split(",", 1)
            config = dict(DEFAULT_CONFIG)
            config["x"] = int(x)
            config["y"] = int(y)
            return config
        except Exception:
            return dict(DEFAULT_CONFIG)

    try:
        saved = json.loads(raw)
    except Exception:
        return dict(DEFAULT_CONFIG)

    config = dict(DEFAULT_CONFIG)
    for key in DEFAULT_CONFIG:
        if key in saved:
            config[key] = saved[key]
    return config


def save_config(config, path=CFG):
    serializable = dict(DEFAULT_CONFIG)
    serializable.update(config)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(serializable, f, ensure_ascii=False)
```

Keep compatibility wrappers during this task so old code keeps running:

```python
def load_pos():
    config = load_config()
    return int(config["x"]), int(config["y"])


def save_pos():
    try:
        config = load_config()
        config["x"] = root.winfo_x()
        config["y"] = root.winfo_y()
        save_config(config)
    except Exception:
        pass
```

- [ ] **Step 4: Run tests and verify pass**

Run:

```bash
python3 -m unittest discover -s tests -p 'test_*.py' -v
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add battery_monitor.py tests/test_battery_monitor.py
git commit -m "feat: persist widget display modes"
```

## Task 4: Build Compact and Expanded Widget Layouts

**Files:**
- Modify: `/Users/leoarrow/Project/mypackage/agents/电池功率/battery_monitor.py`

- [ ] **Step 1: Replace legacy dimensions and animation targets**

In `battery_monitor.py`, replace the old `W, H = 280, 110`, `anim`, `tgt`, `colors`, and breathing-dot state with:

```python
COMPACT_W, COMPACT_H = 238, 58
EXPANDED_W, EXPANDED_H = 292, 118
BG = "#17191D"
BORDER = "#30343B"
MUTED = "#8A8F9B"
TEXT = "#F8FAFC"

anim = dict(total=0.0, system=0.0, charge=0.0, discharge=0.0)
tgt = dict(total=0.0, system=0.0, charge=0.0, discharge=0.0)
current_snapshot = None
details_visible = False
cmd_down = False
```

- [ ] **Step 2: Add layout item creation helpers**

Add these functions before `main()`:

```python
def resize_window(width, height):
    root.geometry(f"{width}x{height}+{root.winfo_x()}+{root.winfo_y()}")
    canvas.config(width=width, height=height)


def clear_canvas():
    canvas.delete("all")


def draw_shell(width, height):
    rrect(canvas, 0, 0, width, height, r=18, fill=BG, outline=BORDER, width=1)


def create_compact_items():
    clear_canvas()
    draw_shell(COMPACT_W, COMPACT_H)
    return {
        "total": canvas.create_text(14, 29, text="-- W", fill=TEXT,
                                    font=("Helvetica Neue", 24, "bold"), anchor="w"),
        "dot": canvas.create_oval(COMPACT_W - 72, 25, COMPACT_W - 64, 33,
                                  fill=MUTED, outline=""),
        "pct": canvas.create_text(COMPACT_W - 14, 29, text="--%", fill=TEXT,
                                  font=("Helvetica Neue", 16, "bold"), anchor="e"),
    }


def create_expanded_items():
    clear_canvas()
    draw_shell(EXPANDED_W, EXPANDED_H)
    canvas.create_line(14, 58, EXPANDED_W - 14, 58, fill="#2D323A", width=1)
    return {
        "total": canvas.create_text(14, 30, text="-- W", fill=TEXT,
                                    font=("Helvetica Neue", 24, "bold"), anchor="w"),
        "dot": canvas.create_oval(EXPANDED_W - 72, 26, EXPANDED_W - 64, 34,
                                  fill=MUTED, outline=""),
        "pct": canvas.create_text(EXPANDED_W - 14, 30, text="--%", fill=TEXT,
                                  font=("Helvetica Neue", 16, "bold"), anchor="e"),
        "system": canvas.create_text(16, 78, text="整机 -- W", fill=MUTED,
                                     font=("Helvetica Neue", 12), anchor="w"),
        "battery": canvas.create_text(16, 99, text="电池 -- W", fill=MUTED,
                                      font=("Helvetica Neue", 12), anchor="w"),
        "state": canvas.create_text(EXPANDED_W - 16, 99, text="--", fill=MUTED,
                                    font=("Helvetica Neue", 12), anchor="e"),
        "advanced": canvas.create_text(EXPANDED_W - 16, 78, text="高级分项关闭",
                                       fill="#71717A", font=("Helvetica Neue", 11), anchor="e"),
    }
```

- [ ] **Step 3: Add render functions**

Add:

```python
items = {}


def _fmt_w(value):
    return f"{value:.1f} W"


def _apply_snapshot_to_items(snapshot):
    canvas.itemconfig(items["total"], text=_fmt_w(anim["total"]), fill=snapshot.hero_color)
    canvas.itemconfig(items["dot"], fill=snapshot.status_color)
    canvas.itemconfig(items["pct"], text=f"{snapshot.percent}%", fill=snapshot.status_color)

    if details_visible:
        canvas.itemconfig(items["system"], text=f"整机 {_fmt_w(anim['system'])}")
        if snapshot.battery_charge_w > 0:
            battery_text = f"电池充电 {_fmt_w(anim['charge'])}"
        else:
            battery_text = f"电池放电 {_fmt_w(anim['discharge'])}"
        canvas.itemconfig(items["battery"], text=battery_text)
        canvas.itemconfig(items["state"], text=snapshot.status_label, fill=snapshot.status_color)
        canvas.itemconfig(items["advanced"], text=get_advanced_summary())


def show_compact():
    global items, details_visible
    details_visible = False
    resize_window(COMPACT_W, COMPACT_H)
    items = create_compact_items()
    if current_snapshot:
        _apply_snapshot_to_items(current_snapshot)


def show_details():
    global items, details_visible
    details_visible = True
    resize_window(EXPANDED_W, EXPANDED_H)
    items = create_expanded_items()
    if current_snapshot:
        _apply_snapshot_to_items(current_snapshot)
```

- [ ] **Step 4: Update data and animation loops**

Replace `update_data()` body with:

```python
def update_data():
    global current_snapshot
    info = get_battery_info()
    if not info:
        if "total" in items:
            canvas.itemconfig(items["total"], text="Error", fill="#FF453A")
        root.after(1000, update_data)
        return

    snapshot = compute_power_snapshot(info)
    current_snapshot = snapshot
    tgt["total"] = snapshot.total_w
    tgt["system"] = snapshot.system_w
    tgt["charge"] = snapshot.battery_charge_w
    tgt["discharge"] = snapshot.battery_discharge_w
    _apply_snapshot_to_items(snapshot)
    root.after(1000, update_data)
```

Replace `animate()` body with:

```python
def animate():
    k = 0.2
    for key in ("total", "system", "charge", "discharge"):
        anim[key] += (tgt[key] - anim[key]) * k
        if abs(tgt[key] - anim[key]) < 0.05:
            anim[key] = tgt[key]
    if current_snapshot:
        _apply_snapshot_to_items(current_snapshot)
    root.after(50, animate)
```

- [ ] **Step 5: Update `main()` to draw compact first**

In `main()`, replace old fixed-size setup with:

```python
config = load_config()
width, height = COMPACT_W, COMPACT_H
root.geometry(f"{width}x{height}+{config['x']}+{config['y']}")
root.attributes("-topmost", bool(config["pinned"]) and not bool(config["desktop_mode"]))
root.attributes("-alpha", 0.86 if config["desktop_mode"] else 0.95)

canvas = tk.Canvas(root, width=width, height=height,
                   bg="systemTransparent", highlightthickness=0, bd=0)
canvas.pack(fill="both", expand=True)
show_compact()
```

Remove old traffic-light and bottom-row item creation. The right-click menu in Task 5 replaces visible controls.

- [ ] **Step 6: Run smoke checks**

Run:

```bash
python3 -m unittest discover -s tests -p 'test_*.py' -v
python3 battery_monitor.py
```

Expected:
- Tests PASS.
- App launches as a compact strip.
- No black border or black corners.
- No visible text overlap in the current power state.

Close the app from the terminal with `Ctrl-C` after the visual check.

- [ ] **Step 7: Commit**

```bash
git add battery_monitor.py
git commit -m "feat: add compact power widget layout"
```

## Task 5: Add Cmd-Hover Details and Right-Click Settings

**Files:**
- Modify: `/Users/leoarrow/Project/mypackage/agents/电池功率/battery_monitor.py`

- [ ] **Step 1: Add menu and mode functions**

Add:

```python
menu = None
app_config = dict(DEFAULT_CONFIG)


def persist_window_config():
    app_config["x"] = root.winfo_x()
    app_config["y"] = root.winfo_y()
    save_config(app_config)


def apply_window_mode():
    root.attributes("-topmost", bool(app_config["pinned"]) and not bool(app_config["desktop_mode"]))
    root.attributes("-alpha", 0.86 if app_config["desktop_mode"] else 0.95)


def toggle_desktop_mode():
    app_config["desktop_mode"] = not app_config["desktop_mode"]
    if app_config["desktop_mode"]:
        app_config["pinned"] = False
    apply_window_mode()
    persist_window_config()


def toggle_pin_menu():
    app_config["pinned"] = not app_config["pinned"]
    apply_window_mode()
    persist_window_config()


def toggle_advanced_power():
    app_config["advanced_power"] = not app_config["advanced_power"]
    persist_window_config()
    if current_snapshot:
        _apply_snapshot_to_items(current_snapshot)


def show_context_menu(event):
    menu.delete(0, "end")
    menu.add_checkbutton(label="桌面模式", onvalue=True, offvalue=False,
                         variable=tk.BooleanVar(value=app_config["desktop_mode"]),
                         command=toggle_desktop_mode)
    menu.add_checkbutton(label="置顶", onvalue=True, offvalue=False,
                         variable=tk.BooleanVar(value=app_config["pinned"]),
                         command=toggle_pin_menu)
    menu.add_checkbutton(label="高级分项", onvalue=True, offvalue=False,
                         variable=tk.BooleanVar(value=app_config["advanced_power"]),
                         command=toggle_advanced_power)
    menu.add_separator()
    menu.add_command(label="退出", command=close_app)
    menu.tk_popup(event.x_root, event.y_root)
```

- [ ] **Step 2: Add Cmd tracking and hover behavior**

Add:

```python
def _cmd_pressed(event=None):
    global cmd_down
    cmd_down = True
    if root.winfo_pointerx() >= root.winfo_rootx() and root.winfo_pointerx() <= root.winfo_rootx() + root.winfo_width():
        if root.winfo_pointery() >= root.winfo_rooty() and root.winfo_pointery() <= root.winfo_rooty() + root.winfo_height():
            show_details()


def _cmd_released(event=None):
    global cmd_down
    cmd_down = False
    show_compact()


def _enter_widget(event=None):
    if cmd_down:
        show_details()


def _leave_widget(event=None):
    if details_visible:
        show_compact()
```

In `main()`, after creating the canvas and menu:

```python
menu = tk.Menu(root, tearoff=0)
canvas.bind("<Button-2>", show_context_menu)
canvas.bind("<Button-3>", show_context_menu)
canvas.bind("<Control-Button-1>", show_context_menu)
canvas.bind("<Enter>", _enter_widget)
canvas.bind("<Leave>", _leave_widget)

for sequence in ("<KeyPress-Meta_L>", "<KeyPress-Meta_R>",
                 "<KeyPress-Command_L>", "<KeyPress-Command_R>"):
    root.bind_all(sequence, _cmd_pressed)
for sequence in ("<KeyRelease-Meta_L>", "<KeyRelease-Meta_R>",
                 "<KeyRelease-Command_L>", "<KeyRelease-Command_R>"):
    root.bind_all(sequence, _cmd_released)
```

- [ ] **Step 3: Keep drag and position persistence**

Replace the old button-release binding with:

```python
canvas.bind("<Button-1>", _start)
canvas.bind("<B1-Motion>", _drag)
canvas.bind("<ButtonRelease-1>", lambda e: persist_window_config())
```

- [ ] **Step 4: Run manual interaction checks**

Run:

```bash
python3 battery_monitor.py
```

Expected:
- Right-click or Control-click opens a menu with 桌面模式, 置顶, 高级分项, 退出.
- Toggling 桌面模式 makes the widget non-topmost and slightly more transparent.
- Toggling 置顶 updates always-on-top behavior when not in desktop mode.
- Holding Cmd while moving the pointer onto the widget expands details.
- Releasing Cmd or leaving the widget restores the compact strip.

- [ ] **Step 5: Commit**

```bash
git add battery_monitor.py
git commit -m "feat: add widget detail interactions"
```

## Task 6: Add Optional Advanced Power Sampling

**Files:**
- Modify: `/Users/leoarrow/Project/mypackage/agents/电池功率/battery_monitor.py`
- Modify: `/Users/leoarrow/Project/mypackage/agents/电池功率/tests/test_battery_monitor.py`

- [ ] **Step 1: Add failing tests for permission-safe advanced sampling**

Append:

```python
class AdvancedPowerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.module = load_module()

    def test_advanced_power_disabled_summary(self):
        self.assertEqual(
            self.module.format_advanced_summary(False, {"status": "disabled"}),
            "高级分项关闭",
        )

    def test_advanced_power_needs_root_summary(self):
        self.assertEqual(
            self.module.format_advanced_summary(True, {"status": "needs_root"}),
            "高级分项需要管理员权限",
        )

    def test_parse_powermetrics_extracts_estimated_values(self):
        text = "CPU Power: 1200 mW\\nGPU Power: 450 mW\\nANE Power: 80 mW\\n"
        parsed = self.module.parse_powermetrics_output(text)
        self.assertAlmostEqual(parsed["CPU"], 1.2, places=1)
        self.assertAlmostEqual(parsed["GPU"], 0.45, places=2)
        self.assertAlmostEqual(parsed["ANE"], 0.08, places=2)
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
python3 -m unittest discover -s tests -p 'test_*.py' -v
```

Expected: FAIL with missing advanced-power helpers.

- [ ] **Step 3: Implement advanced helpers**

Add:

```python
advanced_power = {"status": "disabled"}


def parse_powermetrics_output(text):
    values = {}
    patterns = {
        "CPU": r"CPU Power:\s*([0-9.]+)\s*mW",
        "GPU": r"GPU Power:\s*([0-9.]+)\s*mW",
        "ANE": r"ANE Power:\s*([0-9.]+)\s*mW",
    }
    for label, pattern in patterns.items():
        match = re.search(pattern, text)
        if match:
            values[label] = float(match.group(1)) / 1000.0
    return values


def sample_advanced_power(enabled):
    if not enabled:
        return {"status": "disabled"}
    if hasattr(os, "geteuid") and os.geteuid() != 0:
        return {"status": "needs_root"}
    try:
        out = subprocess.check_output(
            [
                "powermetrics",
                "--samplers",
                "cpu_power,gpu_power,ane_power",
                "--sample-rate",
                "1000",
                "--sample-count",
                "1",
            ],
            stderr=subprocess.STDOUT,
            timeout=3,
        ).decode(errors="replace")
    except Exception:
        return {"status": "unavailable"}

    values = parse_powermetrics_output(out)
    if not values:
        return {"status": "unavailable"}
    values["status"] = "ok"
    return values


def format_advanced_summary(enabled, values):
    status = values.get("status")
    if not enabled or status == "disabled":
        return "高级分项关闭"
    if status == "needs_root":
        return "高级分项需要管理员权限"
    if status == "unavailable":
        return "高级分项不可用"
    parts = []
    for label in ("CPU", "GPU", "ANE"):
        if label in values:
            parts.append(f"{label}估算 {values[label]:.1f} W")
    return " · ".join(parts) if parts else "高级分项不可用"


def get_advanced_summary():
    return format_advanced_summary(app_config.get("advanced_power", False), advanced_power)
```

In `update_data()`, after computing `snapshot`, refresh advanced data only when details are visible:

```python
global advanced_power
if details_visible:
    advanced_power = sample_advanced_power(app_config.get("advanced_power", False))
```

- [ ] **Step 4: Run tests and verify pass**

Run:

```bash
python3 -m unittest discover -s tests -p 'test_*.py' -v
```

Expected: PASS.

- [ ] **Step 5: Manual check without root**

Run:

```bash
python3 battery_monitor.py
```

Expected:
- With 高级分项 off, expanded details show `高级分项关闭`.
- With 高级分项 on from the right-click menu, expanded details show `高级分项需要管理员权限` on a normal launch.
- Compact total power continues updating.

- [ ] **Step 6: Commit**

```bash
git add battery_monitor.py tests/test_battery_monitor.py
git commit -m "feat: add optional advanced power details"
```

## Task 7: Install and Verify the App Bundle

**Files:**
- Modify: `/Users/leoarrow/Project/mypackage/agents/电池功率/battery_monitor.py`
- Use: `/Users/leoarrow/Project/mypackage/agents/电池功率/scripts/install.sh`

- [ ] **Step 1: Run the full unit test suite**

Run:

```bash
python3 -m unittest discover -s tests -p 'test_*.py' -v
```

Expected: PASS.

- [ ] **Step 2: Run the app directly**

Run:

```bash
python3 /Users/leoarrow/Project/mypackage/agents/电池功率/battery_monitor.py
```

Expected:
- Compact strip launches.
- It shows total power, battery percentage, and a status dot.
- No emoji or text overlap appears.
- Canvas has clean transparent rounded corners.
- Right-click menu works.
- Cmd-hover details work.

- [ ] **Step 3: Verify available current power state**

Use the current hardware state first:

```bash
ioreg -rd1 -c AppleSmartBattery | sed -n '/PowerTelemetryData/,/}/p'
```

Expected:
- If plugged and full, details show battery charge near `0.0 W`.
- If charging, details show both system power and battery charging power.
- If discharging, details show system power and battery discharge power.

- [ ] **Step 4: Manually verify the other power states**

Change the Mac power state and repeat direct launch checks:

```bash
python3 /Users/leoarrow/Project/mypackage/agents/电池功率/battery_monitor.py
```

Expected:
- Charging: green status dot, total power includes system plus battery charge, no overlap.
- Plugged and full: blue status dot, battery charge `0.0 W` or near zero, no overlap.
- Discharging: neutral or red status dot depending on battery percentage, no overlap.

- [ ] **Step 5: Install the app bundle**

Run:

```bash
bash /Users/leoarrow/Project/mypackage/agents/电池功率/scripts/install.sh
```

Expected:
- Script copies `battery_monitor.py` to `~/.battery_monitor.py`.
- Script updates `~/Applications/电池功率.app/`.

- [ ] **Step 6: Restart installed app**

Run:

```bash
pkill -f battery_monitor.py || true
open ~/Applications/电池功率.app
```

Expected:
- Installed app launches without a Dock icon.
- Widget position and mode settings persist after drag/toggle/reopen.
- No errors appear in the launch terminal if launched directly.

- [ ] **Step 7: Commit final implementation**

```bash
git add battery_monitor.py tests/test_battery_monitor.py
git commit -m "feat: ship minimal power widget"
```

## Task 8: Final Project Hygiene

**Files:**
- Modify: `/Users/leoarrow/Project/mypackage/agents/电池功率/README.md`

- [ ] **Step 1: Update README feature notes**

In `/Users/leoarrow/Project/mypackage/agents/电池功率/README.md`, add these bullets under `### Features` after the existing real-time power display bullet:

```markdown
- **Minimal desktop widget mode** — compact total-power strip with right-click settings
- **Cmd-hover details** — temporarily expands to show system and battery power
- **Optional advanced estimates** — CPU/GPU/ANE estimates are off by default and require administrator sampling
```

- [ ] **Step 2: Run final status check**

Run:

```bash
git status --short
git log --oneline -5
```

Expected:
- `git status --short` is empty.
- Recent commits show the task commits above.

- [ ] **Step 3: Final handoff summary**

Report:

```text
Implemented the minimal power widget design.
Verified unit tests with python3 -m unittest discover -s tests -p 'test_*.py' -v.
Verified direct launch and installed app bundle.
Current limitations: advanced CPU/GPU/ANE estimates require administrator sampling; SSD wattage is not shown because the data source is not reliable.
```
