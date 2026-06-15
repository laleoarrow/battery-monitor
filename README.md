<h1 align="center">电池功率</h1>

<div align="center">
  <a href="https://github.com/laleoarrow/battery-monitor/releases">
    <img src="https://img.shields.io/badge/RELEASE-V1.0.0-1565c0?style=for-the-badge&logo=github&logoColor=white" alt="Release V1.0.0" />
  </a>
  <a href="https://github.com/laleoarrow/battery-monitor">
    <img src="https://img.shields.io/badge/PLATFORM-macOS%2012%2B-111111?style=for-the-badge&logo=apple&logoColor=white" alt="Platform macOS 12+" />
  </a>
</div>

<div align="center">
  <a href="./README.md">English</a> | <a href="./README_zh.md">简体中文</a>
</div>

## What is 电池功率?

A minimal macOS floating widget that shows real-time total power, battery level, system load, and battery charge/discharge power at a glance.

Built with Python + Tkinter, it renders a compact floating window with no Dock icon — designed to stay out of your way while keeping power data visible.

### Features

- **Real-time total power display** — shows system load plus battery charging power, updated every second via `ioreg`
- **Minimal desktop widget mode** — compact rounded widget with right-click settings
- **Inline power breakdown** — shows system load and battery charge/discharge power without an expanded mode
- **Three-state awareness** — distinguishes charging, plugged-full, and battery-only states with a small status dot
- **macOS-native floating window** with no title bar
- **Always-on-top and desktop-mode toggles** via the right-click menu
- **Drag anywhere** to reposition

### Screenshot

<!-- TODO: add screenshot -->

## Install

```bash
git clone https://github.com/laleoarrow/battery-monitor.git
cd battery-monitor
./scripts/install.sh
```

Then open from `~/Applications/电池功率.app`, or:

```bash
open ~/Applications/电池功率.app
```

### Requirements

- macOS 12+
- Python 3 with Tkinter. On this Mac, `/usr/local/bin/python3` is preferred because the Xcode Python Tk runtime does not render child widgets reliably.

## Development

The entire app is a single Python script:

```
battery_monitor.py    # Main application
scripts/install.sh    # Installer (creates .app bundle)
design/icon/          # App icon assets
```

Run directly for development:

```bash
/usr/local/bin/python3 battery_monitor.py
```

## License

MIT
