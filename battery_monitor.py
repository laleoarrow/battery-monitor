import tkinter as tk
import subprocess
import datetime
import re
import sys
import os
import time

# ── Screen Position Config ──
CONFIG_PATH = os.path.expanduser("~/.battery_monitor.cfg")

def load_position(screen_w, screen_h):
    if os.path.exists(CONFIG_PATH):
        try:
            with open(CONFIG_PATH, "r") as f:
                line = f.read().strip()
                parts = line.split(",")
                if len(parts) == 2:
                    x, y = int(parts[0]), int(parts[1])
                    # Ensure it's not off-screen
                    if 0 <= x < screen_w and 0 <= y < screen_h:
                        return x, y
        except Exception:
            pass
    return 200, 100

def save_position():
    try:
        x = root.winfo_x()
        y = root.winfo_y()
        with open(CONFIG_PATH, "w") as f:
            f.write(f"{x},{y}")
    except Exception:
        pass

# ── Telemetry Data Fetching ──
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

# ── Animation & Transition State ──
target_hero = 0.0
current_hero = 0.0
hero_color = "#FFFFFF"

target_sys = 0.0
current_sys = 0.0

target_bat = 0.0
current_bat = 0.0
bat_color = "#E5E5EA"

is_charging = False
ext_connected = False
pct = 0

def update_data():
    global target_hero, hero_color, target_sys, target_bat, bat_color, is_charging, ext_connected, pct
    info = get_battery_info()
    if not info:
        canvas.itemconfig(txt_hero, text="Error", fill="#FF453A")
        root.after(1000, update_data)
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

    # Target values for smooth transition
    target_sys = sys_load

    if is_charging:
        target_hero = charger_power
        hero_color = "#30D158"          # green
        
        target_bat = bat_power
        bat_color = "#30D158"
    elif ext_connected:
        # Plugged but fully charged -> show adapter power / system load
        target_hero = sys_load if sys_load > 0 else charger_power
        hero_color = "#0A84FF"          # blue = adapter-powered
        
        target_bat = charger_power
        bat_color = "#0A84FF"
    else:
        target_hero = bat_power
        hero_color = "#FFFFFF"          # white = battery
        
        target_bat = bat_power
        bat_color = "#FF453A"

    # Static elements update
    # Battery Percentage color
    if is_charging or pct > 80:
        color_pct = "#30D158"
    elif pct > 20:
        color_pct = "#FF9F0A"
    else:
        color_pct = "#FF453A"
    canvas.itemconfig(txt_pct, text=f"{pct}%", fill=color_pct)

    # Time update
    canvas.itemconfig(txt_time, text=datetime.datetime.now().strftime("%H:%M:%S"))

    # Bottom bar state texts (Strictly 2 characters)
    if is_charging:
        canvas.itemconfig(txt_bat_icon, text="⚡")
        canvas.itemconfig(txt_bat_lbl, text="充电:")
    elif ext_connected:
        canvas.itemconfig(txt_bat_icon, text="🔌")
        canvas.itemconfig(txt_bat_lbl, text="电源:")
    else:
        canvas.itemconfig(txt_bat_icon, text="🔋")
        canvas.itemconfig(txt_bat_lbl, text="放电:")

    root.after(1000, update_data)

# ── Smooth Number Transition Loop (50ms) ──
def animate_values():
    global current_hero, current_sys, current_bat
    
    # Interpolation factor (higher = faster transition)
    k = 0.2
    
    current_hero += (target_hero - current_hero) * k
    current_sys += (target_sys - current_sys) * k
    current_bat += (target_bat - current_bat) * k

    # Format values for display (snap if very close)
    disp_hero = current_hero if abs(target_hero - current_hero) > 0.05 else target_hero
    disp_sys = current_sys if abs(target_sys - current_sys) > 0.05 else target_sys
    disp_bat = current_bat if abs(target_bat - current_bat) > 0.05 else target_bat

    # Update Hero power text and color
    canvas.itemconfig(txt_hero, text=f"{disp_hero:.1f} W", fill=hero_color)
    
    # Update bottom bar values
    canvas.itemconfig(txt_sys_val, text=f"{disp_sys:.1f} W")
    canvas.itemconfig(txt_bat_val, text=f"{disp_bat:.1f} W", fill=bat_color)

    # Re-calculate alignments dynamically
    bbox_sys_icon = canvas.bbox(txt_sys_icon)
    if bbox_sys_icon:
        canvas.coords(txt_sys_lbl, bbox_sys_icon[2] + 4, 93)
    bbox_sys_lbl = canvas.bbox(txt_sys_lbl)
    if bbox_sys_lbl:
        canvas.coords(txt_sys_val, bbox_sys_lbl[2] + 4, 93)

    bbox_bat_icon = canvas.bbox(txt_bat_icon)
    if bbox_bat_icon:
        canvas.coords(txt_bat_lbl, bbox_bat_icon[2] + 4, 93)
    bbox_bat_lbl = canvas.bbox(txt_bat_lbl)
    if bbox_bat_lbl:
        canvas.coords(txt_bat_val, bbox_bat_lbl[2] + 4, 93)

    root.after(50, animate_values)

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
    # Smooth fade out animation
    for i in range(10, -1, -1):
        try:
            root.attributes("-alpha", i / 10.0 * 0.95)
            root.update()
            time.sleep(0.015)
        except Exception:
            break
    root.destroy()
    sys.exit(0)

# ── Hover Events ──
def on_enter_close(event):
    canvas.config(cursor="hand2")
    canvas.itemconfig(close_btn_id, fill="#FF7B72")
    canvas.itemconfig(close_sym_id, fill="#4C0000") # Dark red symbol

def on_leave_close(event):
    canvas.config(cursor="")
    canvas.itemconfig(close_btn_id, fill="#FF5F56")
    canvas.itemconfig(close_sym_id, fill="") # Hide symbol

def on_enter_pin(event):
    canvas.config(cursor="hand2")
    canvas.itemconfig(pin_btn_id, fill="#34D399" if is_pinned else "#9CA3AF")

def on_leave_pin(event):
    canvas.config(cursor="")
    canvas.itemconfig(pin_btn_id, fill="#27C93F" if is_pinned else "#4B5563")

# ── Widget Hover Glow ──
def on_enter_widget(event):
    for sid in bg_shapes:
        try:
            obj_type = canvas.type(sid)
            if obj_type in ("arc", "rectangle"):
                fill_val = canvas.itemcget(sid, "fill")
                if fill_val == "#18181B":
                    canvas.itemconfig(sid, fill="#1F1F24")
                outline_val = canvas.itemcget(sid, "outline")
                if outline_val == "#2D2D33":
                    canvas.itemconfig(sid, outline="#4B5563")
            elif obj_type == "line":
                fill_val = canvas.itemcget(sid, "fill")
                if fill_val == "#2D2D33":
                    canvas.itemconfig(sid, fill="#4B5563")
        except Exception:
            pass

def on_leave_widget(event):
    for sid in bg_shapes:
        try:
            obj_type = canvas.type(sid)
            if obj_type in ("arc", "rectangle"):
                fill_val = canvas.itemcget(sid, "fill")
                if fill_val == "#1F1F24":
                    canvas.itemconfig(sid, fill="#18181B")
                outline_val = canvas.itemcget(sid, "outline")
                if outline_val == "#4B5563":
                    canvas.itemconfig(sid, outline="#2D2D33")
            elif obj_type == "line":
                fill_val = canvas.itemcget(sid, "fill")
                if fill_val == "#4B5563":
                    canvas.itemconfig(sid, fill="#2D2D33")
        except Exception:
            pass

# ── Drag Window ──
_dx = _dy = 0
def start_drag(event):
    global _dx, _dy
    _dx, _dy = event.x, event.y

def drag_window(event):
    root.geometry(f"+{root.winfo_x() + event.x - _dx}+{root.winfo_y() + event.y - _dy}")

# ── Rounded Rect Helper ──
def rrect(cv, x1, y1, x2, y2, r, **kw):
    f = kw.get("fill", ""); o = kw.get("outline", ""); w = kw.get("width", 1)
    ids = []
    if f:
        ids.append(cv.create_arc(x1, y1, x1+2*r, y1+2*r, start=90, extent=90, style="pieslice", fill=f, outline=""))
        ids.append(cv.create_arc(x2-2*r, y1, x2, y1+2*r, start=0, extent=90, style="pieslice", fill=f, outline=""))
        ids.append(cv.create_arc(x1, y2-2*r, x1+2*r, y2, start=180, extent=90, style="pieslice", fill=f, outline=""))
        ids.append(cv.create_arc(x2-2*r, y2-2*r, x2, y2, start=270, extent=90, style="pieslice", fill=f, outline=""))
        ids.append(cv.create_rectangle(x1+r, y1, x2-r, y2, fill=f, outline=""))
        ids.append(cv.create_rectangle(x1, y1+r, x2, y2-r, fill=f, outline=""))
    if o:
        ids.append(cv.create_arc(x1, y1, x1+2*r, y1+2*r, start=90, extent=90, style="arc", outline=o, width=w))
        ids.append(cv.create_arc(x2-2*r, y1, x2, y1+2*r, start=0, extent=90, style="arc", outline=o, width=w))
        ids.append(cv.create_arc(x1, y2-2*r, x1+2*r, y2, start=180, extent=90, style="arc", outline=o, width=w))
        ids.append(cv.create_arc(x2-2*r, y2-2*r, x2, y2, start=270, extent=90, style="arc", outline=o, width=w))
        ids.append(cv.create_line(x1+r, y1, x2-r, y1, fill=o, width=w))
        ids.append(cv.create_line(x2, y1+r, x2, y2-r, fill=o, width=w))
        ids.append(cv.create_line(x1+r, y2, x2-r, y2, fill=o, width=w))
        ids.append(cv.create_line(x1, y1+r, x1, y2-r, fill=o, width=w))
    return ids

# ── Window Setup ──
W, H = 280, 120
root = tk.Tk()
root.withdraw()
root.title("BatteryMonitor")
root.overrideredirect(True)
root.wm_attributes("-transparent", True)
root.attributes("-topmost", is_pinned)
root.attributes("-alpha", 0.0) # Start fully transparent for fade-in

# Load saved position
screen_w = root.winfo_screenwidth()
screen_h = root.winfo_screenheight()
x, y = load_position(screen_w, screen_h)
root.geometry(f"{W}x{H}+{x}+{y}")
root.resizable(False, False)
root.configure(bg="systemTransparent")

# ── Canvas ──
canvas = tk.Canvas(root, width=W, height=H, bg="systemTransparent", highlightthickness=0, bd=0)
canvas.pack(fill="both", expand=True)

# Outer rounded background
bg_shapes = rrect(canvas, 1, 1, W-1, H-1, r=14, fill="#18181B", outline="#2D2D33", width=1)

# Bottom bar
rrect(canvas, 10, 80, W-10, H-10, r=8, fill="#1E1E22", outline="#27272A", width=1)

# Traffic lights
close_btn_id = canvas.create_oval(14, 11, 24, 21, fill="#FF5F56", outline="#E0443E")
canvas.tag_bind(close_btn_id, "<Button-1>", close_app)
canvas.tag_bind(close_btn_id, "<Enter>", on_enter_close)
canvas.tag_bind(close_btn_id, "<Leave>", on_leave_close)

close_sym_id = canvas.create_text(19, 15, text="×", fill="", font=("Helvetica Neue", 11, "bold"))

pin_btn_id = canvas.create_oval(30, 11, 40, 21, fill="#27C93F", outline="#1AAB2F")
canvas.tag_bind(pin_btn_id, "<Button-1>", toggle_pin)
canvas.tag_bind(pin_btn_id, "<Enter>", on_enter_pin)
canvas.tag_bind(pin_btn_id, "<Leave>", on_leave_pin)

# ── Text Items ──
txt_time = canvas.create_text(W-14, 16, text="00:00:00", fill="#71717A",
                              font=("Helvetica Neue", 11), anchor="e")
txt_hero = canvas.create_text(14, 50, text="-- W", fill="#FFFFFF",
                              font=("Helvetica Neue", 32, "bold"), anchor="w")
txt_pct  = canvas.create_text(W-14, 52, text="--%", fill="#FFFFFF",
                              font=("Helvetica Neue", 18, "bold"), anchor="e")

# Separate items for bottom bar to handle layout robustly
txt_sys_icon = canvas.create_text(18, 93, text="💻", fill="#A1A1AA",
                                  font=("Helvetica Neue", 11), anchor="nw")
txt_sys_lbl  = canvas.create_text(34, 93, text="负载:", fill="#A1A1AA",
                                  font=("Helvetica Neue", 11), anchor="nw")
txt_sys_val  = canvas.create_text(66, 93, text="--", fill="#E5E5EA",
                                  font=("Helvetica Neue", 11, "bold"), anchor="nw")

txt_bat_icon = canvas.create_text(148, 93, text="🔋", fill="#A1A1AA",
                                  font=("Helvetica Neue", 11), anchor="nw")
txt_bat_lbl  = canvas.create_text(164, 93, text="放电:", fill="#A1A1AA",
                                  font=("Helvetica Neue", 11), anchor="nw")
txt_bat_val  = canvas.create_text(196, 93, text="--", fill="#E5E5EA",
                                  font=("Helvetica Neue", 11, "bold"), anchor="nw")

# ── Bindings ──
canvas.bind("<Button-1>", start_drag)
canvas.bind("<B1-Motion>", drag_window)
canvas.bind("<ButtonRelease-1>", lambda event: save_position())

# Bind hover events to canvas for glow effect
canvas.bind("<Enter>", on_enter_widget)
canvas.bind("<Leave>", on_leave_widget)

# ── Launch ──
root.deiconify()
root.update()

update_data()
animate_values()

# Smooth fade in animation
for i in range(11):
    root.attributes("-alpha", i / 10.0 * 0.95)
    root.update()
    time.sleep(0.015)

root.mainloop()
