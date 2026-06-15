<h1 align="center">电池功率</h1>

<div align="center">
  <a href="https://github.com/laleoarrow/battery-monitor/releases">
    <img src="https://img.shields.io/badge/RELEASE-V1.3.0-1565c0?style=for-the-badge&logo=github&logoColor=white" alt="Release V1.3.0" />
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

Built as a small native Swift/AppKit app, it renders a compact floating window with no Dock icon — designed to stay out of your way while keeping power data visible.

### Features

- **Real-time total power display** — shows system load plus battery charging power, updated every second via `ioreg`
- **System widget gallery support** — installs a WidgetKit extension so 电池功率 appears in macOS Widgets
- **Widget snapshot sharing** — the floating app writes the latest power snapshot for the system widget to read
- **Inline power breakdown** — shows system load and battery charge/discharge power without an expanded mode
- **Three-state awareness** — distinguishes charging, plugged-full, and battery-only states with a small status dot
- **macOS-native floating window** with no title bar
- **Optional always-on-top toggle** via the right-click menu
- **Drag anywhere** to reposition

### Screenshot

<!-- TODO: add screenshot -->

## Install

Download the latest `.dmg` from [GitHub Releases](https://github.com/laleoarrow/battery-monitor/releases), open it, and drag `电池功率.app` to Applications.

To build from source:

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
- macOS 14+ for the system Widgets gallery extension
- Xcode command line tools with `swiftc` and `xcodebuild`

## Development

The installed app is built from the native Swift entrypoint:

```
BatteryPowerWidget.swift  # Native AppKit widget
BatteryPowerWidgetExtension.swift  # WidgetKit extension for macOS Widgets
BatteryPowerWidgetExtension.xcodeproj/  # Xcode target that builds the .appex
battery_monitor.py        # Legacy Python/Tkinter implementation
scripts/install.sh        # Installer (builds the .app bundle)
scripts/package_dmg.sh    # Release packager (builds a drag-install .dmg)
design/icon/              # App icon assets
```

Build and install for development:

```bash
./scripts/install.sh
open ~/Applications/电池功率.app
```

The floating window updates every second. The macOS system widget reads the latest saved snapshot and refreshes on WidgetKit's schedule; the host app requests a timeline reload periodically, but macOS may still throttle desktop widget updates.

Build a release DMG:

```bash
./scripts/package_dmg.sh 1.3.0
```

## License

MIT
