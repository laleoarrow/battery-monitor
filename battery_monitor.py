import json
import os
import re
import subprocess
import sys
import tkinter as tk
from dataclasses import dataclass


# 电池功率 — macOS floating battery power monitor.
# Runtime copy is installed to ~/.battery_monitor.py by scripts/install.sh.

CFG = os.path.expanduser("~/.battery_monitor.cfg")

DEFAULT_CONFIG = {
    "x": 200,
    "y": 100,
    "pinned": True,
    "desktop_mode": False,
    "advanced_power": False,
}

COMPACT_W, COMPACT_H = 238, 58
EXPANDED_W, EXPANDED_H = 330, 132

BG = "#17191D"
BORDER = "#30343B"
MUTED = "#8A8F9B"
SUBTLE = "#71717A"
TEXT = "#F8FAFC"
GREEN = "#30D158"
BLUE = "#0A84FF"
ORANGE = "#FF9F0A"
RED = "#FF453A"

anim = {"total": 0.0, "system": 0.0, "charge": 0.0, "discharge": 0.0}
tgt = {"total": 0.0, "system": 0.0, "charge": 0.0, "discharge": 0.0}

items = {}
app_config = dict(DEFAULT_CONFIG)
current_snapshot = None
advanced_power = {"status": "disabled"}
details_visible = False
cmd_down = False
_dx = _dy = 0
content_offset_y = 0


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


def load_config(path=CFG):
    try:
        with open(path, encoding="utf-8") as f:
            raw = f.read().strip()
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
    for key, default in DEFAULT_CONFIG.items():
        config[key] = saved.get(key, default)

    try:
        config["x"] = int(config["x"])
        config["y"] = int(config["y"])
        config["pinned"] = bool(config["pinned"])
        config["desktop_mode"] = bool(config["desktop_mode"])
        config["advanced_power"] = bool(config["advanced_power"])
    except Exception:
        return dict(DEFAULT_CONFIG)
    return config


def save_config(config, path=CFG):
    serializable = dict(DEFAULT_CONFIG)
    serializable.update(config)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(serializable, f, ensure_ascii=False)


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
    for key in (
        "CurrentCapacity",
        "MaxCapacity",
        "Voltage",
        "Amperage",
        "ExternalConnected",
        "IsCharging",
        "FullyCharged",
    ):
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


def get_battery_info():
    try:
        out = subprocess.check_output(
            "ioreg -rd1 -c AppleSmartBattery", shell=True
        ).decode(errors="replace")
    except Exception:
        return {}
    return parse_ioreg_output(out)


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
        if system_in is not None:
            system_w = max(system_in - charge_w, 0.0)
        else:
            system_w = _battery_fallback_w(info)

    discharge_w = _discharge_power_w(info, plugged)
    total_w = max(system_w, 0.0) + max(charge_w, 0.0)

    if charging:
        state = "charging"
        status_label = "充电"
        status_color = GREEN
        hero_color = GREEN
    elif plugged:
        state = "plugged_full"
        status_label = "外接电源"
        status_color = BLUE
        hero_color = BLUE
    elif percent <= 20:
        state = "low_battery"
        status_label = "低电量"
        status_color = RED
        hero_color = TEXT
    else:
        state = "discharging"
        status_label = "放电"
        status_color = MUTED
        hero_color = TEXT

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
    return format_advanced_summary(
        app_config.get("advanced_power", False), advanced_power
    )


def resize_window(width, height):
    match = re.match(r"\d+x\d+([+-]\d+)([+-]\d+)", root.geometry())
    frame_height = height + content_offset_y
    if match:
        root.geometry(f"{width}x{frame_height}{match.group(1)}{match.group(2)}")
    else:
        root.geometry(f"{width}x{frame_height}+{app_config['x']}+{app_config['y']}")
    panel.config(width=width, height=frame_height)


def _clear_panel():
    for child in panel.winfo_children():
        child.destroy()


def _bind_widget_events(widget):
    widget.bind("<Button-1>", _start)
    widget.bind("<B1-Motion>", _drag)
    widget.bind("<ButtonRelease-1>", lambda event: persist_window_config())
    widget.bind("<Button-2>", show_context_menu)
    widget.bind("<Button-3>", show_context_menu)
    widget.bind("<Control-Button-1>", show_context_menu)
    widget.bind("<Enter>", _enter_widget)
    widget.bind("<Motion>", _motion_widget)
    widget.bind("<Leave>", _leave_widget)


def _label(text, x, y, font, fg=TEXT, anchor="w"):
    label = tk.Label(
        panel,
        text=text,
        fg=fg,
        bg=BG,
        font=font,
        bd=0,
        padx=0,
        pady=0,
    )
    label.place(x=x, y=y, anchor=anchor)
    _bind_widget_events(label)
    return label


def create_compact_items():
    _clear_panel()
    y = content_offset_y
    return {
        "total": _label("-- W", 14, y + 29, ("Helvetica Neue", 24, "bold")),
        "dot": _label("●", COMPACT_W - 68, y + 29, ("Helvetica Neue", 14), MUTED, "center"),
        "pct": _label("--%", COMPACT_W - 14, y + 29, ("Helvetica Neue", 16, "bold"), TEXT, "e"),
    }


def create_expanded_items():
    _clear_panel()
    y = content_offset_y
    divider = tk.Frame(panel, bg="#2D323A", bd=0, height=1)
    divider.place(x=14, y=y + 58, width=EXPANDED_W - 28, height=1)
    return {
        "total": _label("-- W", 14, y + 30, ("Helvetica Neue", 24, "bold")),
        "dot": _label("●", EXPANDED_W - 68, y + 30, ("Helvetica Neue", 14), MUTED, "center"),
        "pct": _label("--%", EXPANDED_W - 14, y + 30, ("Helvetica Neue", 16, "bold"), TEXT, "e"),
        "system": _label("整机 -- W", 16, y + 76, ("Helvetica Neue", 12), MUTED),
        "battery": _label("电池 -- W", 16, y + 97, ("Helvetica Neue", 12), MUTED),
        "state": _label("--", EXPANDED_W - 16, y + 76, ("Helvetica Neue", 12), MUTED, "e"),
        "advanced": _label("高级分项关闭", 16, y + 118, ("Helvetica Neue", 11), SUBTLE),
    }


def _fmt_w(value):
    return f"{value:.1f} W"


def _fit_text(item_id, text, max_width, sizes, weight="bold"):
    del max_width
    size = sizes[0]
    if len(text) >= 8 and len(sizes) > 2:
        size = sizes[2]
    elif len(text) >= 7 and len(sizes) > 1:
        size = sizes[1]
    item_id.config(text=text, font=("Helvetica Neue", size, weight))


def _battery_detail_text(snapshot):
    if snapshot.battery_charge_w > 0.05:
        return f"电池充电 {_fmt_w(anim['charge'])}"
    if snapshot.battery_discharge_w > 0.05:
        return f"电池放电 {_fmt_w(anim['discharge'])}"
    return "电池 0.0 W"


def _apply_snapshot_to_items(snapshot):
    total_text = _fmt_w(anim["total"])
    max_total_width = (EXPANDED_W if details_visible else COMPACT_W) - 112
    _fit_text(items["total"], total_text, max_total_width, (24, 22, 20, 18))
    items["total"].config(fg=snapshot.hero_color)
    items["dot"].config(fg=snapshot.status_color)
    items["pct"].config(text=f"{snapshot.percent}%", fg=snapshot.status_color)

    if details_visible:
        items["system"].config(text=f"整机 {_fmt_w(anim['system'])}")
        items["battery"].config(text=_battery_detail_text(snapshot))
        items["state"].config(text=snapshot.status_label, fg=snapshot.status_color)
        items["advanced"].config(text=get_advanced_summary())


def show_compact():
    global details_visible, items
    details_visible = False
    resize_window(COMPACT_W, COMPACT_H)
    items = create_compact_items()
    if current_snapshot:
        _apply_snapshot_to_items(current_snapshot)


def show_details():
    global details_visible, items, advanced_power
    details_visible = True
    resize_window(EXPANDED_W, EXPANDED_H)
    items = create_expanded_items()
    advanced_power = sample_advanced_power(app_config.get("advanced_power", False))
    if current_snapshot:
        _apply_snapshot_to_items(current_snapshot)


def update_data():
    global current_snapshot, advanced_power
    info = get_battery_info()
    if not info:
        if "total" in items:
            items["total"].config(text="Error", fg=RED)
        root.after(1000, update_data)
        return

    snapshot = compute_power_snapshot(info)
    current_snapshot = snapshot
    tgt["total"] = snapshot.total_w
    tgt["system"] = snapshot.system_w
    tgt["charge"] = snapshot.battery_charge_w
    tgt["discharge"] = snapshot.battery_discharge_w
    if details_visible:
        advanced_power = sample_advanced_power(app_config.get("advanced_power", False))
    _apply_snapshot_to_items(snapshot)
    root.after(1000, update_data)


def animate():
    k = 0.2
    for key in ("total", "system", "charge", "discharge"):
        anim[key] += (tgt[key] - anim[key]) * k
        if abs(tgt[key] - anim[key]) < 0.05:
            anim[key] = tgt[key]
    if current_snapshot and items:
        _apply_snapshot_to_items(current_snapshot)
    root.after(50, animate)


def persist_window_config():
    try:
        app_config["x"] = root.winfo_x()
        app_config["y"] = root.winfo_y()
        save_config(app_config)
    except Exception:
        pass


def apply_window_mode():
    topmost = bool(app_config["pinned"]) and not bool(app_config["desktop_mode"])
    root.attributes("-topmost", topmost)
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
    global advanced_power
    app_config["advanced_power"] = not app_config["advanced_power"]
    advanced_power = sample_advanced_power(app_config["advanced_power"])
    persist_window_config()
    if current_snapshot:
        _apply_snapshot_to_items(current_snapshot)


def show_context_menu(event):
    menu.delete(0, "end")
    desktop_mark = "✓ " if app_config["desktop_mode"] else ""
    pin_mark = "✓ " if app_config["pinned"] else ""
    advanced_mark = "✓ " if app_config["advanced_power"] else ""
    menu.add_command(label=f"{desktop_mark}桌面模式", command=toggle_desktop_mode)
    menu.add_command(label=f"{pin_mark}置顶", command=toggle_pin_menu)
    menu.add_command(label=f"{advanced_mark}高级分项", command=toggle_advanced_power)
    menu.add_separator()
    menu.add_command(label="退出", command=close_app)
    try:
        menu.tk_popup(event.x_root, event.y_root)
    finally:
        menu.grab_release()


def close_app(event=None):
    persist_window_config()
    root.destroy()
    sys.exit(0)


def _start(event):
    global _dx, _dy
    _dx, _dy = event.x, event.y


def _drag(event):
    root.geometry(f"+{root.winfo_x() + event.x - _dx}+{root.winfo_y() + event.y - _dy}")


def _event_has_cmd(event):
    # Tk maps Command differently across macOS builds; accept common mod masks.
    return bool(event and getattr(event, "state", 0) & (0x0008 | 0x0010 | 0x0040 | 0x0080))


def _pointer_inside_root():
    x = root.winfo_pointerx()
    y = root.winfo_pointery()
    return (
        root.winfo_rootx() <= x <= root.winfo_rootx() + root.winfo_width()
        and root.winfo_rooty() <= y <= root.winfo_rooty() + root.winfo_height()
    )


def _cmd_pressed(event=None):
    global cmd_down
    cmd_down = True
    if _pointer_inside_root():
        show_details()


def _cmd_released(event=None):
    global cmd_down
    cmd_down = False
    if details_visible:
        show_compact()


def _enter_widget(event=None):
    if cmd_down or _event_has_cmd(event):
        show_details()


def _motion_widget(event=None):
    if not details_visible and (cmd_down or _event_has_cmd(event)):
        show_details()


def _leave_widget(event=None):
    if details_visible:
        show_compact()


def _bind_events():
    _bind_widget_events(panel)

    for sequence in (
        "<KeyPress-Meta_L>",
        "<KeyPress-Meta_R>",
        "<KeyPress-Command_L>",
        "<KeyPress-Command_R>",
    ):
        try:
            root.bind_all(sequence, _cmd_pressed)
        except tk.TclError:
            pass
    for sequence in (
        "<KeyRelease-Meta_L>",
        "<KeyRelease-Meta_R>",
        "<KeyRelease-Command_L>",
        "<KeyRelease-Command_R>",
    ):
        try:
            root.bind_all(sequence, _cmd_released)
        except tk.TclError:
            pass


def main():
    global root, panel, menu, app_config

    app_config = load_config()
    root = tk.Tk(baseName="BatteryPowerWidget", className="BatteryPowerWidget")
    root.withdraw()
    root.title("电池功率")
    root.overrideredirect(True)
    root.configure(bg=BG)
    root.resizable(False, False)
    root.geometry(
        f"{COMPACT_W}x{COMPACT_H + content_offset_y}"
        f"+{app_config['x']}+{app_config['y']}"
    )

    panel = tk.Frame(
        root,
        width=COMPACT_W,
        height=COMPACT_H + content_offset_y,
        bg=BG,
        highlightthickness=0,
        bd=0,
    )
    panel.pack(fill="both", expand=True)
    menu = tk.Menu(root, tearoff=0)

    show_compact()
    _bind_events()
    apply_window_mode()
    root.after(0, root.deiconify)
    root.after(10, root.lift)
    root.after(20, apply_window_mode)
    root.after(50, animate)
    root.after(100, update_data)

    root.mainloop()


if __name__ == "__main__":
    main()
