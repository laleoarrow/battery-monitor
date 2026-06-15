import base64
import json
import os
import re
import struct
import subprocess
import sys
import tkinter as tk
import tkinter.font as tkfont
import zlib
from dataclasses import dataclass
from datetime import datetime


# 电池功率 — macOS floating battery power monitor.
# Runtime copy is installed to ~/.battery_monitor.py by scripts/install.sh.

CFG = os.path.expanduser("~/.battery_monitor.cfg")
CONFIG_VERSION = 3

DEFAULT_CONFIG = {
    "config_version": CONFIG_VERSION,
    "x": 200,
    "y": 100,
    "pinned": False,
}

COMPACT_W, COMPACT_H = 319, 90

WINDOW_BG = "systemTransparent"
BG = "#17191F"
BORDER = "#343945"
INNER_BORDER = "#222733"
MUTED = "#A6ABB6"
TEXT = "#F8FAFC"
GREEN = "#34E36E"
BLUE = "#4AA3FF"
ORANGE = "#FF9F0A"
RED = "#FF453A"

anim = {"total": 0.0, "system": 0.0, "charge": 0.0, "discharge": 0.0}
tgt = {"total": 0.0, "system": 0.0, "charge": 0.0, "discharge": 0.0}

items = {}
app_config = dict(DEFAULT_CONFIG)
current_snapshot = None
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

    try:
        saved_version = int(saved.get("config_version", 0))
    except Exception:
        saved_version = 0

    config = dict(DEFAULT_CONFIG)
    for key, default in DEFAULT_CONFIG.items():
        config[key] = saved.get(key, default)

    if saved_version < CONFIG_VERSION:
        config["config_version"] = CONFIG_VERSION

    try:
        config["config_version"] = int(config["config_version"])
        config["x"] = int(config["x"])
        config["y"] = int(config["y"])
        config["pinned"] = bool(config["pinned"])
    except Exception:
        return dict(DEFAULT_CONFIG)
    return config


def save_config(config, path=CFG):
    serializable = dict(DEFAULT_CONFIG)
    for key in DEFAULT_CONFIG:
        if key in config:
            serializable[key] = config[key]
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


def resize_window(width, height):
    match = re.match(r"\d+x\d+([+-]\d+)([+-]\d+)", root.geometry())
    frame_height = height + content_offset_y
    if match:
        root.geometry(f"{width}x{frame_height}{match.group(1)}{match.group(2)}")
    else:
        root.geometry(f"{width}x{frame_height}+{app_config['x']}+{app_config['y']}")


def _bind_widget_events(widget):
    widget.bind("<Button-1>", _start)
    widget.bind("<B1-Motion>", _drag)
    widget.bind("<ButtonRelease-1>", lambda event: persist_window_config())
    widget.bind("<Button-2>", show_context_menu)
    widget.bind("<Button-3>", show_context_menu)
    widget.bind("<Control-Button-1>", show_context_menu)


def _clear_items():
    for child in root.winfo_children():
        if child is not menu:
            child.destroy()


def _inside_round_rect(x, y, width, height, radius):
    if x < 0 or y < 0 or x >= width or y >= height:
        return False
    if x < radius and y < radius:
        return (x - radius) ** 2 + (y - radius) ** 2 <= radius ** 2
    if x >= width - radius and y < radius:
        return (x - (width - radius - 1)) ** 2 + (y - radius) ** 2 <= radius ** 2
    if x < radius and y >= height - radius:
        return (x - radius) ** 2 + (y - (height - radius - 1)) ** 2 <= radius ** 2
    if x >= width - radius and y >= height - radius:
        return (
            (x - (width - radius - 1)) ** 2
            + (y - (height - radius - 1)) ** 2
            <= radius ** 2
        )
    return True


def _hex_to_rgb(color):
    color = color.lstrip("#")
    return tuple(int(color[i:i + 2], 16) for i in (0, 2, 4))


def _png_chunk(kind, data):
    return (
        struct.pack(">I", len(data))
        + kind
        + data
        + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
    )


def _rounded_panel_png(width, height, radius):
    fill = _hex_to_rgb(BG)
    border = _hex_to_rgb(BORDER)
    inner = _hex_to_rgb(INNER_BORDER)
    rows = []
    scale = 4
    samples = scale * scale

    for y in range(height):
        row = bytearray([0])
        for x in range(width):
            red = green = blue = alpha = 0
            for sy in range(scale):
                for sx in range(scale):
                    px = x + (sx + 0.5) / scale
                    py = y + (sy + 0.5) / scale
                    if not _inside_round_rect(px, py, width, height, radius):
                        continue
                    if not _inside_round_rect(px - 1.5, py - 1.5, width - 3, height - 3, radius - 2):
                        color = border
                    elif not _inside_round_rect(px - 3.0, py - 3.0, width - 6, height - 6, radius - 4):
                        color = inner
                    else:
                        color = fill
                    red += color[0]
                    green += color[1]
                    blue += color[2]
                    alpha += 255
            if alpha:
                covered = alpha // 255
                row += bytes((
                    red // covered,
                    green // covered,
                    blue // covered,
                    round(alpha / samples),
                ))
            else:
                row += b"\x00\x00\x00\x00"
        rows.append(bytes(row))

    raw = b"".join(rows)
    png = (
        b"\x89PNG\r\n\x1a\n"
        + _png_chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
        + _png_chunk(b"IDAT", zlib.compress(raw, 9))
        + _png_chunk(b"IEND", b"")
    )
    return base64.b64encode(png).decode("ascii")


def _label(text, x, y, font, fg=TEXT, bg=BG, anchor="w"):
    label = tk.Label(
        root,
        text=text,
        fg=fg,
        bg=bg,
        font=font,
        bd=0,
        padx=0,
        pady=0,
        highlightthickness=0,
    )
    label.place(x=x, y=y, anchor=anchor)
    _bind_widget_events(label)
    return label


def _compact_metric_group(x, y, label, value="-- W", value_fill=TEXT):
    label_id = _label(label, x, y, ("Helvetica Neue", 12, "bold"), MUTED)
    value_id = _label(value, x + 34, y, ("Helvetica Neue", 12, "bold"), value_fill)
    return label_id, value_id


def create_compact_items():
    _clear_items()
    panel_image = tk.PhotoImage(
        data=_rounded_panel_png(COMPACT_W, COMPACT_H, 22),
        format="png",
    )
    background = tk.Label(
        root,
        image=panel_image,
        bg=WINDOW_BG,
        bd=0,
        highlightthickness=0,
        padx=0,
        pady=0,
    )
    background.image = panel_image
    background.place(x=0, y=0, width=COMPACT_W, height=COMPACT_H)
    _bind_widget_events(background)

    dot = _label("●", 238, 27, ("Helvetica Neue", 13), MUTED, anchor="center")
    load_label, load_value = _compact_metric_group(20, 70, "负载")
    charge_label, charge_value = _compact_metric_group(142, 70, "充电", value_fill=GREEN)
    return {
        "background": background,
        "total": _label("--", 20, 32, ("Helvetica Neue", 32, "bold"), TEXT),
        "unit": _label("W", 95, 35, ("Helvetica Neue", 15, "bold"), MUTED),
        "dot": dot,
        "pct": _label("--%", 250, 31, ("Helvetica Neue", 17, "bold"), TEXT),
        "load_label": load_label,
        "load": load_value,
        "battery_label": charge_label,
        "battery": charge_value,
        "time": _label("--:--", COMPACT_W - 19, 70, ("Helvetica Neue", 12, "bold"), MUTED, anchor="e"),
    }


def _fmt_w(value):
    return f"{value:.1f} W"


def _fit_text(item_id, text, max_width, sizes, weight="bold"):
    for size in sizes:
        font = ("Helvetica Neue", size, weight)
        if tkfont.Font(font=font).measure(text) <= max_width:
            item_id.config(text=text, font=font)
            return size
    font = ("Helvetica Neue", sizes[-1], weight)
    item_id.config(text=text, font=font)
    return sizes[-1]


def _battery_compact_label(snapshot):
    if snapshot.battery_charge_w > 0.05:
        return "充电", _fmt_w(anim["charge"]), GREEN
    if snapshot.battery_discharge_w > 0.05:
        return "放电", _fmt_w(anim["discharge"]), RED if snapshot.percent <= 20 else TEXT
    return "电池", "0.0 W", MUTED


def _apply_snapshot_to_items(snapshot):
    total_text = f"{anim['total']:.1f}"
    size = _fit_text(items["total"], total_text, 150, (32, 30, 28, 26))
    total_width = tkfont.Font(font=("Helvetica Neue", size, "bold")).measure(total_text)
    items["total"].config(fg=snapshot.hero_color)
    items["unit"].config(fg=MUTED)
    items["unit"].place(x=max(20 + total_width + 8, 95), y=35, anchor="w")
    items["dot"].config(fg=snapshot.status_color)
    items["pct"].config(text=f"{snapshot.percent}%", fg=snapshot.status_color)
    items["load"].config(text=_fmt_w(anim["system"]))

    battery_label, battery_value, battery_color = _battery_compact_label(snapshot)
    items["battery_label"].config(text=battery_label)
    items["battery"].config(text=battery_value, fg=battery_color)
    items["time"].config(text=datetime.now().strftime("%H:%M"))


def show_compact():
    global items
    resize_window(COMPACT_W, COMPACT_H)
    items = create_compact_items()
    if current_snapshot:
        _apply_snapshot_to_items(current_snapshot)


def update_data():
    global current_snapshot
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
    root.attributes("-topmost", bool(app_config["pinned"]))
    root.attributes("-alpha", 1.0)


def toggle_pin_menu():
    app_config["pinned"] = not app_config["pinned"]
    apply_window_mode()
    persist_window_config()


def show_context_menu(event):
    menu.delete(0, "end")
    pin_mark = "✓ " if app_config["pinned"] else ""
    menu.add_command(label=f"{pin_mark}置顶", command=toggle_pin_menu)
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


def _bind_events():
    _bind_widget_events(root)


def reveal_window():
    root.deiconify()
    root.lift()
    apply_window_mode()


def _configure_window_shell(window):
    window.overrideredirect(True)
    window.configure(bg=WINDOW_BG)
    try:
        window.attributes("-transparent", True)
    except tk.TclError:
        pass


def main():
    global root, menu, app_config

    app_config = load_config()
    root = tk.Tk(baseName="BatteryPowerWidget", className="BatteryPowerWidget")
    root.withdraw()
    root.title("电池功率")
    _configure_window_shell(root)
    root.resizable(False, False)
    root.geometry(
        f"{COMPACT_W}x{COMPACT_H + content_offset_y}"
        f"+{app_config['x']}+{app_config['y']}"
    )

    menu = tk.Menu(root, tearoff=0)

    show_compact()
    _bind_events()
    apply_window_mode()
    root.after(0, reveal_window)
    root.after(20, apply_window_mode)
    root.after(50, animate)
    root.after(100, update_data)

    root.mainloop()


if __name__ == "__main__":
    main()
