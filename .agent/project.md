# Project overview

## Goal

`电池功率` is a native macOS floating battery power monitor widget. It displays real-time battery wattage, system load, charging state, and battery percentage in a minimal, premium, transparent rounded window that floats on top of other applications.

## Current behavior

- **Real-time monitor**: Fetches system telemetry and battery details every second.
- **Window characteristics**: Transparent background, rounded corners, draggable window, always-on-top mode (toggleable).
- **Traffic light controls**: Includes custom-rendered buttons for closing the app and pinning/unpinning the widget (always-on-top).
- **Dynamic layout**: Elements are dynamically arranged using bounding boxes (`canvas.bbox()`) to prevent overlapping text and emojis in different languages and states.
- **Three Power States**:
  - **Charging**: Green hero power (adapter input power) and green charging status.
  - **Plugged in (fully charged)**: Blue hero power (system load) and blue adapter status.
  - **Battery only**: White hero power (battery output power) and red discharging status.

## External dependencies

- **`ioreg` tool**: Standard macOS command-line utility used to query battery status (`ioreg -rd1 -c AppleSmartBattery`).
- **Python 3 & Tkinter**: The main programming language and GUI framework used to draw the custom widget interface.

## Key files

- `battery_monitor.py` — Main python script containing window setup, canvas drawing, drag bindings, and telemetry updating logic.
- `scripts/install.sh` — Bash installation script that creates the macOS app wrapper bundle `电池功率.app` under `~/Applications/` and copies the monitor script to `~/.battery_monitor.py`.
- `design/icon/AppIcon.icns` — Pre-compiled macOS icns file containing resolutions from 16x16 to 512x512, used as the app bundle's application icon.

## Application Architecture

The app is packaged as a standard macOS wrapper bundle (`电池功率.app`) which contains a bash launcher at `Contents/MacOS/applet`.
When the user launches the app, macOS runs this launcher script, which executes:
```bash
exec /usr/local/bin/python3 "$HOME/.battery_monitor.py"
```
The application runs as a background process with no Dock icon (`LSUIElement=true` in `Info.plist`), and presents its custom transparent Tkinter window on screen.
