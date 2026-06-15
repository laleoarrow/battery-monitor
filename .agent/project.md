# Project overview

## Goal

`电池功率` is a native macOS floating battery power monitor widget. It displays real-time total power, battery percentage, charging state, system load, and battery charge/discharge power in a minimal floating window.

## Current behavior

- **Real-time monitor**: Fetches system telemetry and battery details every second.
- **Window characteristics**: Compact rounded floating monitor, draggable window, right-click settings, and an always-on-top toggle.
- **System Widgets support**: Installs a WidgetKit app extension so the app appears in the macOS widget gallery on macOS 14+.
- **Controls**: No permanent traffic-light controls; right-click menu provides pinning and exit.
- **Dynamic layout**: The compact layout avoids mixed emoji/text strings and shrinks the main wattage text when necessary.
- **Three Power States**:
  - **Charging**: Green total power and green status dot.
  - **Plugged in (fully charged)**: Blue total/system power and blue status dot.
  - **Battery only**: Neutral total/system power with neutral or red status dot depending on battery percentage.

## External dependencies

- **`ioreg` tool**: Standard macOS command-line utility used to query battery status (`ioreg -rd1 -c AppleSmartBattery`).
- **Swift & AppKit**: The installed app uses a transparent native `NSPanel` so rounded corners are transparent at the window layer.
- **WidgetKit & SwiftUI**: The system widget gallery entry is a separate app extension embedded under `Contents/PlugIns`.
- **Python 3**: `battery_monitor.py` is retained as a legacy/reference implementation for parsing and tests.

## Key files

- `BatteryPowerWidget.swift` — Native AppKit widget containing transparent window setup, drawing, drag/menu handling, and telemetry updating logic.
- `BatteryPowerWidgetExtension.swift` — WidgetKit extension used by the macOS Widgets gallery. It shows a snapshot and refreshes on WidgetKit's schedule rather than every second.
- `BatteryPowerWidgetExtension.xcodeproj` — Minimal Xcode project used to build the WidgetKit `.appex`; do not replace this with hand-rolled `swiftc` packaging because macOS WidgetKit needs the app-extension entry point.
- `BatteryPowerApp.entitlements` and `BatteryPowerWidgetExtension.entitlements` — Sandbox entitlements for the host app and widget extension.
- `battery_monitor.py` — Legacy/reference Python implementation used by tests.
- `scripts/install.sh` — Bash installation script that compiles the Swift executable, builds the WidgetKit extension with Xcode, embeds the `.appex`, signs both bundles, and creates the macOS app bundle `电池功率.app` under `~/Applications/`.
- `design/icon/AppIcon.icns` — Pre-compiled macOS icns file containing resolutions from 16x16 to 512x512, used as the app bundle's application icon.

## Application Architecture

The app is packaged as a standard macOS app bundle (`电池功率.app`) with a native Swift executable at `Contents/MacOS/applet`.
The application runs as a background process with no Dock icon (`LSUIElement=true` in `Info.plist`) and presents a transparent borderless AppKit panel on screen.
The system widget is packaged as `Contents/PlugIns/BatteryPowerWidgetExtension.appex` with `NSExtensionPointIdentifier=com.apple.widgetkit-extension`. The extension must be built by the Xcode target so its executable uses the WidgetKit app-extension entry point.
The AppKit app writes the latest WidgetKit-readable snapshot to `~/Library/Application Support/电池功率/widget-snapshot.json`; the sandboxed WidgetKit extension reads that file instead of directly querying IORegistry.
