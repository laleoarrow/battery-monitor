# Widget standalone refresh & status glow design

Date: 2026-07-07

## Problem

The macOS system widget (WidgetKit extension) has three issues:

1. **Stale data without the app.** The extension only reads
   `~/Library/Application Support/电池功率/widget-snapshot.json`, which is written
   by the floating app. When the app is not running, the widget never updates.
2. **Tapping launches the app.** WidgetKit's default tap behavior opens the host
   app, so users who just want fresh numbers get the floating window popped up.
3. **Flat status dot.** The widget renders the status dot as a plain circle with
   a shadow, visually inferior to the app's layered pulsing glow.

## Design

### 1. Direct battery sampling in the extension

The sandboxed extension cannot spawn `/usr/sbin/ioreg` (fork/exec is denied),
but reading IORegistry properties is allowed. Add a `WidgetPowerSampler` that
calls `IOServiceGetMatchingService` + `IORegistryEntryCreateCFProperties` on
`AppleSmartBattery` and reuses the same power math as the app's `PowerSampler`
(SystemLoad / SystemPowerIn / ChargerData / BatteryPower, with the
voltage×amperage fallback).

Snapshot resolution order: live IOKit sample → shared snapshot file → preview.
The app keeps writing the snapshot file (unchanged, contract-tested) so the file
remains a fallback and preview source.

### 2. Tap-to-refresh interactive widget

Wrap the widget content in `Button(intent: RefreshBatteryWidgetIntent())` with
`.buttonStyle(.plain)`. The intent performs in the extension process and returns
immediately; WidgetKit reloads the timeline after the intent completes, which
re-samples live data. Tapping therefore refreshes in place and no longer
launches the app. Requires macOS 14 (already the extension's deployment target).

### 3. Layered status glow + freshness time

Replace the flat dot with a `StatusGlowDot` view: radial-gradient outer glow +
mid halo + solid core with a specular highlight, glowing only when plugged or
charging — matching the app's drawing (the app pulses; the widget is static by
platform constraint, so it renders a mid-pulse frame).

Show the snapshot time (`HH:mm`) in both families, mirroring the app's
bottom-right clock, so users can see how fresh the data is.

## Out of scope

- The floating app's sampling/reload cadence (contract-tested, unchanged).
- The legacy Python implementation.
