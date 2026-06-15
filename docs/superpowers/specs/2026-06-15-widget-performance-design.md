# Widget Performance and Status Dot Design

## Goal

Reduce idle CPU and unnecessary disk activity while preserving the current user experience and refresh behavior.

## Scope

- Keep the main AppKit panel sampling and displaying power data once per second.
- Keep the macOS WidgetKit desktop widget requesting refreshes every five seconds.
- Move the blue or green status dot four points closer to the battery percentage value.
- Reduce the status glow animation from 30 FPS to 15 FPS.
- Cache the time formatter instead of creating one during every panel redraw.
- Do not change any other UI dimensions, typography, colors, content, or interactions.

## Design

### Main App Sampling

The existing one-second sampling timer remains unchanged. Each sample updates the main panel and any enabled dynamic Dock display immediately, preserving the app's real-time purpose.

### WidgetKit Data Flow

The app stops writing `widget-snapshot.json` after every one-second sample. A single five-second gate controls both widget actions:

1. Write the latest in-memory `PowerSnapshot` to `widget-snapshot.json`.
2. Immediately call `WidgetCenter.shared.reloadTimelines(ofKind:)`.

The snapshot write must succeed before the reload request is sent. This ensures the extension reads the data associated with that request and removes four unnecessary atomic file replacements during each five-second period.

The WidgetKit extension's five-minute fallback timeline remains unchanged. It is only a fallback when the host app is not actively requesting refreshes.

### Glow Animation

The pulse timer interval changes from 1/30 second to 1/15 second. The pulse phase increment changes proportionally so a complete pulse cycle keeps approximately the same duration and visual rhythm.

The existing glow sizes, opacity ranges, colors, and activation rules remain unchanged.

### Status Dot Position

The spacing between the maximum glow radius and the percentage value changes from eight points to four points. Percentage text placement remains fixed, so only the dot and its glow move four points to the right.

### Time Formatting

`BatteryView` uses one cached `DateFormatter` configured with `HH:mm`. Redrawing the panel reuses that formatter rather than allocating and configuring a new formatter each frame.

## Error Handling

- If writing the widget snapshot fails, skip the corresponding WidgetKit reload request.
- The next five-second interval retries with the latest in-memory sample.
- Main panel updates continue even if widget snapshot persistence fails.

## Verification

1. Build the native AppKit app and WidgetKit extension successfully.
2. Run all existing Python tests.
3. Verify the status dot is four points closer in charging and fully charged states, with no overlap at one-, two-, and three-digit percentages.
4. Verify the main panel values still change once per second.
5. Verify snapshot file and WidgetKit timeline timestamps advance together at approximately five-second intervals.
6. Verify the glow still pulses smoothly and completes a cycle at approximately the previous rate.
7. Measure CPU over at least ten consecutive samples after launch and compare it with the previous 10-13% single-core baseline.
8. Install and launch the rebuilt app, verify WidgetKit reloads succeed, and confirm no bundle-version errors appear.

## Non-Goals

- No changes to the main panel's one-second telemetry sampling.
- No attempt to force WidgetKit below its observed five-second foreground refresh throttle.
- No event-driven battery framework migration.
- No changes to settings, Dock modes, release packaging, or WidgetKit visual layout.
