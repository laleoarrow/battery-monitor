import tkinter as tk
import subprocess
import datetime
import re
import sys

def get_battery_info():
    try:
        out = subprocess.check_output('ioreg -rd1 -c AppleSmartBattery', shell=True).decode('utf-8')
    except Exception:
        return {}
    
    info = {}
    basic_keys = ['CurrentCapacity', 'MaxCapacity', 'DesignCapacity', 'CycleCount',
                  'Temperature', 'Voltage', 'Amperage', 'ExternalConnected', 'IsCharging']
    for k in basic_keys:
        match = re.search(fr'"{k}"\s*=\s*(-?[0-9]+|Yes|No|"[^"]*")', out)
        if match:
            val = match.group(1).strip()
            if val == 'Yes':
                info[k] = True
            elif val == 'No':
                info[k] = False
            elif val.startswith('"') and val.endswith('"'):
                info[k] = val[1:-1]
            else:
                try:
                    info[k] = int(val)
                except ValueError:
                    try:
                        info[k] = float(val)
                    except ValueError:
                        info[k] = val

    telemetry = {}
    match = re.search(r'"PowerTelemetryData"\s*=\s*\{([^\}]+)\}', out)
    if match:
        content = match.group(1)
        pairs = re.findall(r'"?([A-Za-z0-9_]+)"?\s*=\s*(-?[0-9]+)', content)
        for k, v in pairs:
            telemetry[k] = int(v)
    info['telemetry'] = telemetry
    return info

def update_label():
    info = get_battery_info()
    if not info:
        canvas.itemconfig(txt_hero, text="Error", fill="#FF453A")
        root.after(1000, update_label)
        return

    pct = info.get('CurrentCapacity', 0)
    is_charging = info.get('IsCharging', False)
    ext_connected = info.get('ExternalConnected', False)

    # Power Metrics (mW -> W)
    telemetry = info.get('telemetry', {})

    sys_load_mw = telemetry.get('SystemLoad')
    if sys_load_mw is not None:
        sys_load = sys_load_mw / 1000.0
    else:
        sys_load = abs(info.get('Voltage', 0) * info.get('Amperage', 0) / 1000000.0)

    bat_power_mw = telemetry.get('BatteryPower')
    if bat_power_mw is not None:
        bat_power = bat_power_mw / 1000.0
    else:
        bat_power = abs(info.get('Voltage', 0) * info.get('Amperage', 0) / 1000000.0)

    charger_power_mw = telemetry.get('SystemPowerIn')
    if charger_power_mw is not None:
        charger_power = charger_power_mw / 1000.0
    else:
        charger_power = bat_power if is_charging else 0.0

    # ── Hero Power Logic ──
    # Three states: charging / plugged-full / battery-only
    if is_charging:
        hero_power = charger_power
        hero_color = "#30D158"          # green
    elif ext_connected:
        # Plugged in but NOT charging → fully charged, show adapter power
        hero_power = sys_load if sys_load > 0 else charger_power
        hero_color = "#0A84FF"          # blue = adapter-powered
    else:
        hero_power = bat_power
        hero_color = "#FFFFFF"          # white = battery

    canvas.itemconfig(txt_hero, text=f"{hero_power:.1f} W", fill=hero_color)

    # Battery Percentage color
    if is_charging or pct > 80:
        color_pct = "#30D158"
    elif pct > 20:
        color_pct = "#FF9F0A"
    else:
        color_pct = "#FF453A"
    canvas.itemconfig(txt_pct, text=f"{pct}%", fill=color_pct)

    # Time
    canvas.itemconfig(txt_time, text=datetime.datetime.now().strftime("%H:%M:%S"))

    # ── Bottom bar ──
    canvas.itemconfig(txt_sys_val, text=f"{sys_load:.1f} W")

    if is_charging:
        canvas.itemconfig(txt_bat_lbl, text="⚡ 充电:")
        canvas.itemconfig(txt_bat_val, text=f"{bat_power:.1f} W", fill="#30D158")
    elif ext_connected:
        canvas.itemconfig(txt_bat_lbl, text="🔌 适配器:")
        canvas.itemconfig(txt_bat_val, text=f"{charger_power:.1f} W", fill="#0A84FF")
    else:
        canvas.itemconfig(txt_bat_lbl, text="🔋 放电:")
        canvas.itemconfig(txt_bat_val, text=f"{bat_power:.1f} W", fill="#FF453A")

    root.after(1000, update_label)

# ── State ──
is_pinned = True

def toggle_pin(event=None):
    global is_pinned
    is_pinned = not is_pinned
    root.attributes("-topmost", is_pinned)
    canvas.itemconfig(pin_btn_id,
                      fill="#27C93F" if is_pinned else "#4B5563",
                      outline="#1AAB2F" if is_pinned else "#374151")
    return "break"

def close_app(event=None):
    root.destroy()
    sys.exit(0)

def on_enter_close(event):
    canvas.config(cursor="hand2")
    canvas.itemconfig(close_btn_id, fill="#FF7B72")
def on_leave_close(event):
    canvas.config(cursor="")
    canvas.itemconfig(close_btn_id, fill="#FF5F56")
def on_enter_pin(event):
    canvas.config(cursor="hand2")
    canvas.itemconfig(pin_btn_id, fill="#34D399" if is_pinned else "#9CA3AF")
def on_leave_pin(event):
    canvas.config(cursor="")
    canvas.itemconfig(pin_btn_id, fill="#27C93F" if is_pinned else "#4B5563")

# ── Drag ──
_dx = _dy = 0
def start_drag(event):
    global _dx, _dy
    _dx, _dy = event.x, event.y
def drag_window(event):
    root.geometry(f"+{root.winfo_x() + event.x - _dx}+{root.winfo_y() + event.y - _dy}")

# ── Rounded rect helper ──
def rrect(cv, x1, y1, x2, y2, r, **kw):
    f = kw.get("fill", ""); o = kw.get("outline", ""); w = kw.get("width", 1)
    if f:
        cv.create_arc(x1, y1, x1+2*r, y1+2*r, start=90, extent=90, style="pieslice", fill=f, outline="")
        cv.create_arc(x2-2*r, y1, x2, y1+2*r, start=0, extent=90, style="pieslice", fill=f, outline="")
        cv.create_arc(x1, y2-2*r, x1+2*r, y2, start=180, extent=90, style="pieslice", fill=f, outline="")
        cv.create_arc(x2-2*r, y2-2*r, x2, y2, start=270, extent=90, style="pieslice", fill=f, outline="")
        cv.create_rectangle(x1+r, y1, x2-r, y2, fill=f, outline="")
        cv.create_rectangle(x1, y1+r, x2, y2-r, fill=f, outline="")
    if o:
        cv.create_arc(x1, y1, x1+2*r, y1+2*r, start=90, extent=90, style="arc", outline=o, width=w)
        cv.create_arc(x2-2*r, y1, x2, y1+2*r, start=0, extent=90, style="arc", outline=o, width=w)
        cv.create_arc(x1, y2-2*r, x1+2*r, y2, start=180, extent=90, style="arc", outline=o, width=w)
        cv.create_arc(x2-2*r, y2-2*r, x2, y2, start=270, extent=90, style="arc", outline=o, width=w)
        cv.create_line(x1+r, y1, x2-r, y1, fill=o, width=w)
        cv.create_line(x2, y1+r, x2, y2-r, fill=o, width=w)
        cv.create_line(x1+r, y2, x2-r, y2, fill=o, width=w)
        cv.create_line(x1, y1+r, x1, y2-r, fill=o, width=w)

# ── Window setup ──
W, H = 280, 120
root = tk.Tk()
root.withdraw()
root.title("")
root.overrideredirect(True)
root.wm_attributes("-transparent", True)
root.attributes("-topmost", is_pinned)
root.geometry(f"{W}x{H}+200+100")
root.resizable(False, False)
root.configure(bg="systemTransparent")

# ── Canvas ──
canvas = tk.Canvas(root, width=W, height=H, bg="systemTransparent", highlightthickness=0)
canvas.pack(fill="both", expand=True)

# Outer rounded background
rrect(canvas, 1, 1, W-1, H-1, r=14, fill="#18181B", outline="#2D2D33", width=1)

# Bottom bar
rrect(canvas, 10, 80, W-10, H-10, r=8, fill="#1E1E22", outline="#27272A", width=1)

# Traffic lights
close_btn_id = canvas.create_oval(14, 11, 24, 21, fill="#FF5F56", outline="#E0443E")
canvas.tag_bind(close_btn_id, "<Button-1>", close_app)
canvas.tag_bind(close_btn_id, "<Enter>", on_enter_close)
canvas.tag_bind(close_btn_id, "<Leave>", on_leave_close)

pin_btn_id = canvas.create_oval(30, 11, 40, 21, fill="#27C93F", outline="#1AAB2F")
canvas.tag_bind(pin_btn_id, "<Button-1>", toggle_pin)
canvas.tag_bind(pin_btn_id, "<Enter>", on_enter_pin)
canvas.tag_bind(pin_btn_id, "<Leave>", on_leave_pin)

# ── Text items ──
txt_time = canvas.create_text(W-14, 16, text="00:00:00", fill="#71717A",
                              font=("Helvetica Neue", 11), anchor="e")
txt_hero = canvas.create_text(14, 50, text="-- W", fill="#FFFFFF",
                              font=("Helvetica Neue", 32, "bold"), anchor="w")
txt_pct  = canvas.create_text(W-14, 52, text="--%", fill="#FFFFFF",
                              font=("Helvetica Neue", 18, "bold"), anchor="e")

txt_sys_lbl = canvas.create_text(18, 93, text="💻 负载:", fill="#A1A1AA",
                                 font=("Helvetica Neue", 11), anchor="nw")
txt_sys_val = canvas.create_text(84, 93, text="--", fill="#E5E5EA",
                                 font=("Helvetica Neue", 11, "bold"), anchor="nw")
txt_bat_lbl = canvas.create_text(148, 93, text="🔋 放电:", fill="#A1A1AA",
                                 font=("Helvetica Neue", 11), anchor="nw")
txt_bat_val = canvas.create_text(214, 93, text="--", fill="#E5E5EA",
                                 font=("Helvetica Neue", 11, "bold"), anchor="nw")

# ── Drag ──
canvas.bind("<Button-1>", start_drag)
canvas.bind("<B1-Motion>", drag_window)

# ── Launch ──
root.deiconify()
update_label()
root.mainloop()
