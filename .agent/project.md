# Project overview

## Goal

`电池功率` is a native macOS floating battery power monitor widget. It displays real-time total power, battery percentage, charging state, system load, and battery charge/discharge power in a minimal floating window.

## Current behavior

- **Real-time monitor**: Fetches system telemetry and battery details every second.
- **Window characteristics**: Compact rounded widget, draggable window, right-click settings, desktop-mode and always-on-top toggles.
- **Controls**: No permanent traffic-light controls; right-click menu provides desktop mode, pinning, and exit.
- **Dynamic layout**: The compact layout avoids mixed emoji/text strings and shrinks the main wattage text when necessary.
- **Three Power States**:
  - **Charging**: Green total power and green status dot.
  - **Plugged in (fully charged)**: Blue total/system power and blue status dot.
  - **Battery only**: Neutral total/system power with neutral or red status dot depending on battery percentage.

## External dependencies

- **`ioreg` tool**: Standard macOS command-line utility used to query battery status (`ioreg -rd1 -c AppleSmartBattery`).
- **Python 3 & Tkinter**: The main programming language and GUI framework used to draw the custom widget interface.

## Key files

- `battery_monitor.py` — Main python script containing transparent window setup, generated PNG rounded background, label layout, drag bindings, and telemetry updating logic.
- `scripts/install.sh` — Bash installation script that creates the macOS app wrapper bundle `电池功率.app` under `~/Applications/` and copies the monitor script to `~/.battery_monitor.py`.
- `design/icon/AppIcon.icns` — Pre-compiled macOS icns file containing resolutions from 16x16 to 512x512, used as the app bundle's application icon.

## Application Architecture

The app is packaged as a standard macOS wrapper bundle (`电池功率.app`) which contains a bash launcher at `Contents/MacOS/applet`.
When the user launches the app, macOS runs this launcher script, which executes:
```bash
exec "$PYTHON_BIN" "$HOME/.battery_monitor.py"
```
The launcher selects the first available Python 3 binary from `/usr/local/bin/python3`, `/usr/bin/python3`, and `/opt/homebrew/bin/python3`. `/usr/local/bin/python3` is preferred on this Mac because the Xcode Python Tk runtime can show the window shell without rendering child widgets. The application runs as a background process with no Dock icon (`LSUIElement=true` in `Info.plist`), and presents its custom Tkinter window on screen.
