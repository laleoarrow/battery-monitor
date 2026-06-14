import tkinter as tk
import subprocess
import datetime
import re
import sys
import os
import time
import math

# ═══════════════════════════════════════════
#  电池功率 — macOS Floating Battery Monitor
# ═══════════════════════════════════════════

# ── Position Persistence ──
CFG = os.path.expanduser("~/.battery_monitor.cfg")

def load_pos():
    try:
        with open(CFG) as f:
            x, y = f.read().strip().split(",")
            return int(x), int(y)
    except Exception:
        return 200, 100

def save_pos():
    try:
        with open(CFG, "w") as f:
            f.write(f"{root.winfo_x()},{root.winfo_y()}")
    except Exception:
        pass

# ── Battery Telemetry ──
def get_battery_info():
    try:
        out = subprocess.check_output(
            'ioreg -rd1 -c AppleSmartBattery', shell=True
        ).decode()
    except Exception:
        return {}

    info = {}
    for k in ('CurrentCapacity', 'MaxCapacity', 'Voltage', 'Amperage',
              'ExternalConnected', 'IsCharging'):
        m = re.search(fr'"{k}"\s*=\s*(-?[0-9]+|Yes|No)', out)
        if m:
            v = m.group(1)
            if v == 'Yes':    info[k] = True
            elif v == 'No':   info[k] = False
            else:             info[k] = int(v)

    tel = {}
    m = re.search(r'"PowerTelemetryData"\s*=\s*\{([^}]+)\}', out)
    if m:
        for k2, v2 in re.findall(r'"?(\w+)"?\s*=\s*(-?\d+)', m.group(1)):
            tel[k2] = int(v2)
    info['tel'] = tel
    return info

# ── Smooth Animation State ──
anim = dict(hero=0.0, sys=0.0, bat=0.0)   # current displayed values
tgt  = dict(hero=0.0, sys=0.0, bat=0.0)   # target values
colors = dict(hero="#FFFFFF", bat="#E5E5EA")

# Breathing dot state
breath_phase = 0.0
breath_base_color = (113, 113, 122)   # gray (#71717A)
breath_speed = 0.04                    # radians per frame

def update_data():
    """Fetch battery data every 1 s and set animation targets."""
    info = get_battery_info()
    if not info:
        canvas.itemconfig(txt_hero, text="Error", fill="#FF453A")
        root.after(1000, update_data)
        return

    pct = info.get('CurrentCapacity', 0)
    charging = info.get('IsCharging', False)
    plugged  = info.get('ExternalConnected', False)
    tel = info.get('tel', {})

    # Power in watts
    def mw(key):
        v = tel.get(key)
        return v / 1000.0 if v is not None else None

    sys_w = mw('SystemLoad') or abs(
        info.get('Voltage', 0) * info.get('Amperage', 0) / 1e6)
    bat_w = mw('BatteryPower') or abs(
        info.get('Voltage', 0) * info.get('Amperage', 0) / 1e6)
    chg_w = mw('SystemPowerIn') or (bat_w if charging else 0.0)

    tgt['sys'] = sys_w

    if charging:
        tgt['hero'] = chg_w;   colors['hero'] = "#30D158"
        tgt['bat']  = bat_w;   colors['bat']  = "#30D158"
        lbl_text = "充电:"
        _set_breath(r=48, g=209, b=88, spd=0.08)    # green, fast
    elif plugged:
        tgt['hero'] = sys_w if sys_w > 0 else chg_w
        colors['hero'] = "#0A84FF"
        tgt['bat']  = chg_w;   colors['bat']  = "#0A84FF"
        lbl_text = "电源:"
        _set_breath(r=10, g=132, b=255, spd=0.03)   # blue, slow
    else:
        tgt['hero'] = bat_w;   colors['hero'] = "#FFFFFF"
        tgt['bat']  = bat_w;   colors['bat']  = "#FF453A"
        lbl_text = "放电:"
        if pct <= 20:
            _set_breath(r=255, g=69, b=58, spd=0.15)  # red, urgent
        else:
            _set_breath(r=113, g=113, b=122, spd=0.02) # gray, calm

    # Percentage
    if charging or pct > 80:    cpct = "#30D158"
    elif pct > 20:              cpct = "#FF9F0A"
    else:                       cpct = "#FF453A"
    canvas.itemconfig(txt_pct, text=f"{pct}%", fill=cpct)

    # Time
    canvas.itemconfig(txt_time,
                      text=datetime.datetime.now().strftime("%H:%M:%S"))

    # Bottom labels (2-char max, no emoji)
    canvas.itemconfig(txt_bat_lbl, text=lbl_text)

    root.after(1000, update_data)

def _set_breath(r, g, b, spd):
    global breath_base_color, breath_speed
    breath_base_color = (r, g, b)
    breath_speed = spd

def _lerp_hex(base, factor):
    """Blend base color toward white by factor (0..1)."""
    bg = (24, 24, 27)  # #18181B background
    r = int(bg[0] + (base[0] - bg[0]) * factor)
    g = int(bg[1] + (base[1] - bg[1]) * factor)
    b = int(bg[2] + (base[2] - bg[2]) * factor)
    return f"#{r:02x}{g:02x}{b:02x}"

def animate():
    """50 ms loop — interpolate displayed values toward targets."""
    global breath_phase
    k = 0.2
    for key in ('hero', 'sys', 'bat'):
        anim[key] += (tgt[key] - anim[key]) * k
        if abs(tgt[key] - anim[key]) < 0.05:
            anim[key] = tgt[key]

    canvas.itemconfig(txt_hero,
                      text=f"{anim['hero']:.1f} W", fill=colors['hero'])
    canvas.itemconfig(txt_sys_val, text=f"{anim['sys']:.1f} W")
    canvas.itemconfig(txt_bat_val,
                      text=f"{anim['bat']:.1f} W", fill=colors['bat'])

    # ── Breathing dot animation ──
    breath_phase += breath_speed
    t = (math.sin(breath_phase) + 1.0) / 2.0   # 0..1
    # Core dot (bright)
    canvas.itemconfig(dot_core, fill=_lerp_hex(breath_base_color, 0.4 + 0.6 * t))
    # Middle glow
    canvas.itemconfig(dot_mid,  fill=_lerp_hex(breath_base_color, 0.2 + 0.4 * t))
    # Outer halo
    canvas.itemconfig(dot_out,  fill=_lerp_hex(breath_base_color, 0.05 + 0.15 * t))

    root.after(50, animate)

# ── Pin / Close ──
pinned = True

def toggle_pin(e=None):
    global pinned
    pinned = not pinned
    root.attributes("-topmost", pinned)
    canvas.itemconfig(pin_id,
                      fill="#27C93F" if pinned else "#4B5563",
                      outline="#1AAB2F" if pinned else "#374151")
    return "break"

def close_app(e=None):
    for i in range(10, -1, -1):
        try:
            root.attributes("-alpha", i / 10.0 * 0.95)
            root.update(); time.sleep(0.012)
        except Exception:
            break
    root.destroy(); sys.exit(0)

# ── Hover helpers ──
def _enter_close(e):
    canvas.config(cursor="hand2")
    canvas.itemconfig(close_id, fill="#FF7B72")
    canvas.itemconfig(close_x,  fill="#4C0000")

def _leave_close(e):
    canvas.config(cursor="")
    canvas.itemconfig(close_id, fill="#FF5F56")
    canvas.itemconfig(close_x,  fill="")

def _enter_pin(e):
    canvas.config(cursor="hand2")
    canvas.itemconfig(pin_id, fill="#34D399" if pinned else "#9CA3AF")

def _leave_pin(e):
    canvas.config(cursor="")
    canvas.itemconfig(pin_id, fill="#27C93F" if pinned else "#4B5563")

# ── Drag ──
_dx = _dy = 0
def _start(e):
    global _dx, _dy; _dx, _dy = e.x, e.y
def _drag(e):
    root.geometry(f"+{root.winfo_x()+e.x-_dx}+{root.winfo_y()+e.y-_dy}")

# ── Rounded‑rect helper (returns canvas item ids) ──
def rrect(cv, x1, y1, x2, y2, r, **kw):
    f = kw.get("fill",""); o = kw.get("outline",""); w = kw.get("width",1)
    ids = []
    if f:
        ids += [
            cv.create_arc(x1, y1, x1+2*r, y1+2*r, start=90,  extent=90,
                          style="pieslice", fill=f, outline=""),
            cv.create_arc(x2-2*r, y1, x2, y1+2*r, start=0,   extent=90,
                          style="pieslice", fill=f, outline=""),
            cv.create_arc(x1, y2-2*r, x1+2*r, y2, start=180, extent=90,
                          style="pieslice", fill=f, outline=""),
            cv.create_arc(x2-2*r, y2-2*r, x2, y2, start=270, extent=90,
                          style="pieslice", fill=f, outline=""),
            cv.create_rectangle(x1+r, y1, x2-r, y2, fill=f, outline=""),
            cv.create_rectangle(x1, y1+r, x2, y2-r, fill=f, outline=""),
        ]
    if o:
        ids += [
            cv.create_arc(x1, y1, x1+2*r, y1+2*r, start=90,  extent=90,
                          style="arc", outline=o, width=w),
            cv.create_arc(x2-2*r, y1, x2, y1+2*r, start=0,   extent=90,
                          style="arc", outline=o, width=w),
            cv.create_arc(x1, y2-2*r, x1+2*r, y2, start=180, extent=90,
                          style="arc", outline=o, width=w),
            cv.create_arc(x2-2*r, y2-2*r, x2, y2, start=270, extent=90,
                          style="arc", outline=o, width=w),
            cv.create_line(x1+r, y1, x2-r, y1, fill=o, width=w),
            cv.create_line(x2, y1+r, x2, y2-r, fill=o, width=w),
            cv.create_line(x1+r, y2, x2-r, y2, fill=o, width=w),
            cv.create_line(x1, y1+r, x1, y2-r, fill=o, width=w),
        ]
    return ids

# ══════════════════════════════════════
#  Build the Window
# ══════════════════════════════════════
W, H = 280, 110
root = tk.Tk()
root.withdraw()
root.title("BatteryMonitor")
root.overrideredirect(True)
root.wm_attributes("-transparent", True)
root.attributes("-topmost", pinned)
root.attributes("-alpha", 0.0)          # start invisible for fade-in

sx, sy = load_pos()
root.geometry(f"{W}x{H}+{sx}+{sy}")
root.resizable(False, False)
root.configure(bg="systemTransparent")

canvas = tk.Canvas(root, width=W, height=H,
                   bg="systemTransparent", highlightthickness=0, bd=0)
canvas.pack(fill="both", expand=True)

# ── Background rounded rect ──
rrect(canvas, 0, 0, W, H, r=14, fill="#18181B", outline="#2D2D33", width=1)

# ── NO bottom bar border — just plain text below a thin separator ──
# Thin horizontal divider line
canvas.create_line(14, 78, W-14, 78, fill="#2D2D33", width=1)

# ── Traffic lights ──
close_id = canvas.create_oval(14, 10, 24, 20, fill="#FF5F56", outline="#E0443E")
close_x  = canvas.create_text(19, 14, text="×", fill="",
                               font=("Helvetica Neue", 10, "bold"))
canvas.tag_bind(close_id, "<Button-1>", close_app)
canvas.tag_bind(close_id, "<Enter>",    _enter_close)
canvas.tag_bind(close_id, "<Leave>",    _leave_close)

pin_id = canvas.create_oval(30, 10, 40, 20, fill="#27C93F", outline="#1AAB2F")
canvas.tag_bind(pin_id, "<Button-1>", toggle_pin)
canvas.tag_bind(pin_id, "<Enter>",    _enter_pin)
canvas.tag_bind(pin_id, "<Leave>",    _leave_pin)

# ── Main text ──
txt_time = canvas.create_text(W-14, 15, text="--:--:--", fill="#71717A",
                              font=("Helvetica Neue", 11), anchor="e")

txt_hero = canvas.create_text(14, 48, text="-- W", fill="#FFFFFF",
                              font=("Helvetica Neue", 30, "bold"), anchor="w")

# Breathing dot (3 layered circles for glow effect)
DOT_X, DOT_Y = W - 58, 50
dot_out  = canvas.create_oval(DOT_X-7, DOT_Y-7, DOT_X+7, DOT_Y+7,
                              fill="#18181B", outline="")
dot_mid  = canvas.create_oval(DOT_X-5, DOT_Y-5, DOT_X+5, DOT_Y+5,
                              fill="#18181B", outline="")
dot_core = canvas.create_oval(DOT_X-3, DOT_Y-3, DOT_X+3, DOT_Y+3,
                              fill="#71717A", outline="")

txt_pct  = canvas.create_text(W-14, 50, text="--%", fill="#FFFFFF",
                              font=("Helvetica Neue", 18, "bold"), anchor="e")

# ── Bottom info row (no border, just text) ──
# Left group: system load
txt_sys_lbl = canvas.create_text(18, 92, text="负载:", fill="#71717A",
                                 font=("Helvetica Neue", 11), anchor="w")
txt_sys_val = canvas.create_text(52, 92, text="--", fill="#A1A1AA",
                                 font=("Helvetica Neue", 11, "bold"), anchor="w")

# Right group: battery / charging status (no emoji)
txt_bat_lbl  = canvas.create_text(148, 92, text="放电:", fill="#71717A",
                                  font=("Helvetica Neue", 11), anchor="w")
txt_bat_val  = canvas.create_text(182, 92, text="--", fill="#A1A1AA",
                                  font=("Helvetica Neue", 11, "bold"), anchor="w")

# ── Bindings ──
canvas.bind("<Button-1>",        _start)
canvas.bind("<B1-Motion>",       _drag)
canvas.bind("<ButtonRelease-1>", lambda e: save_pos())

# ══════════════════════════════════════
#  Launch
# ══════════════════════════════════════
root.deiconify()
root.update()

update_data()
animate()

# Fade in
for i in range(11):
    root.attributes("-alpha", i / 10.0 * 0.95)
    root.update()
    time.sleep(0.012)

root.mainloop()
