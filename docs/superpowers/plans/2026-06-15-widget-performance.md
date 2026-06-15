# Widget Performance Optimization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve one-second main-panel telemetry while synchronizing WidgetKit persistence and reloads every five seconds, reducing glow rendering cost, caching time formatting, and moving the status dot four points closer to the percentage.

**Architecture:** Keep the existing AppKit controller and view structure. Add source-level contract tests for the Swift runtime behavior, make snapshot persistence report success, place snapshot persistence and WidgetKit reload behind one five-second controller gate, and adjust only the approved animation and layout constants.

**Tech Stack:** Swift 6, AppKit, WidgetKit, Foundation, Python `unittest`, Xcode command-line build tools.

---

## File Structure

- Modify `BatteryPowerWidget.swift`: runtime timers, cached formatter, status-dot spacing, snapshot save result, and five-second widget synchronization.
- Create `tests/test_swift_runtime_contract.py`: regression checks for the approved Swift timing, layout, and data-flow contracts.
- Modify `docs/superpowers/plans/2026-06-15-widget-performance.md`: check off completed implementation steps during execution.

### Task 1: Lock the Approved Runtime Contract

**Files:**
- Create: `tests/test_swift_runtime_contract.py`
- Test: `tests/test_swift_runtime_contract.py`

- [x] **Step 1: Write the failing source-contract tests**

```python
import pathlib
import re
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
SWIFT_SOURCE = ROOT / "BatteryPowerWidget.swift"


class SwiftRuntimeContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = SWIFT_SOURCE.read_text(encoding="utf-8")

    def test_main_sampling_stays_at_one_second(self):
        self.assertIn("Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true)", self.source)

    def test_widget_snapshot_and_reload_share_five_second_gate(self):
        self.assertIn("widgetReloadRequestInterval: TimeInterval = 5", self.source)
        update_body = re.search(
            r"private func update\(\) \{(?P<body>.*?)\n    \}",
            self.source,
            re.DOTALL,
        ).group("body")
        self.assertNotIn("WidgetSnapshotStore.save", update_body)

        sync_body = re.search(
            r"private func syncWidgetIfNeeded\(\) \{(?P<body>.*?)\n    \}",
            self.source,
            re.DOTALL,
        ).group("body")
        save_index = sync_body.index("WidgetSnapshotStore.save(latestSnapshot)")
        reload_index = sync_body.index("WidgetCenter.shared.reloadTimelines")
        self.assertLess(save_index, reload_index)
        self.assertIn("guard WidgetSnapshotStore.save(latestSnapshot) else", sync_body)

    def test_glow_runs_at_fifteen_fps_with_same_cycle_speed(self):
        self.assertIn("pulsePhase += 0.32", self.source)
        self.assertIn("withTimeInterval: 1.0 / 15.0", self.source)

    def test_status_dot_gap_is_four_points(self):
        self.assertIn("let dotToValueGap: CGFloat = 4", self.source)

    def test_time_formatter_is_cached(self):
        self.assertIn("private static let timeFormatter", self.source)
        self.assertIn("Self.timeFormatter.string(from: Date())", self.source)
        time_body = re.search(
            r"private func timeString\(\) -> String \{(?P<body>.*?)\n    \}",
            self.source,
            re.DOTALL,
        ).group("body")
        self.assertNotIn("DateFormatter()", time_body)


if __name__ == "__main__":
    unittest.main()
```

- [x] **Step 2: Run the new tests and verify failure**

Run:

```bash
python3 -m unittest tests.test_swift_runtime_contract -v
```

Expected: failures for the missing `syncWidgetIfNeeded`, 30 FPS pulse, eight-point gap, and per-draw `DateFormatter` allocation.

- [x] **Step 3: Commit the failing tests**

```bash
git add tests/test_swift_runtime_contract.py
git commit -m "test: define widget performance contract"
```

### Task 2: Synchronize Widget Persistence and Reload

**Files:**
- Modify: `BatteryPowerWidget.swift:270-297`
- Modify: `BatteryPowerWidget.swift:821-877`
- Test: `tests/test_swift_runtime_contract.py`

- [x] **Step 1: Return snapshot persistence success**

Change `WidgetSnapshotStore.save` to return `Bool`:

```swift
@discardableResult
static func save(_ snapshot: PowerSnapshot) -> Bool {
    let payload: [String: Any] = [
        "percent": snapshot.percent,
        "plugged": snapshot.plugged,
        "charging": snapshot.charging,
        "systemW": snapshot.systemW,
        "chargeW": snapshot.chargeW,
        "dischargeW": snapshot.dischargeW,
        "updatedAt": Date().timeIntervalSince1970,
    ]
    let url = snapshotURL
    do {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: payload)
        try data.write(to: url, options: .atomic)
        return true
    } catch {
        return false
    }
}
```

- [x] **Step 2: Move persistence behind the five-second gate**

Replace the widget calls in `update()` and the old reload method with:

```swift
private func update() {
    let snapshot = sampler.sample()
    latestSnapshot = snapshot
    view.snapshot = snapshot
    updateDockTile()
    syncWidgetIfNeeded()
}

private func syncWidgetIfNeeded() {
    let now = Date()
    guard now.timeIntervalSince(lastWidgetReloadRequest) >= widgetReloadRequestInterval else {
        return
    }
    lastWidgetReloadRequest = now
    guard WidgetSnapshotStore.save(latestSnapshot) else {
        return
    }
    WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
}
```

- [x] **Step 3: Run the widget synchronization contract test**

Run:

```bash
python3 -m unittest tests.test_swift_runtime_contract.SwiftRuntimeContractTests.test_widget_snapshot_and_reload_share_five_second_gate -v
```

Expected: `OK`.

- [x] **Step 4: Compile the native app**

Run:

```bash
xcrun swiftc BatteryPowerWidget.swift -framework AppKit -framework CoreGraphics -framework WidgetKit -o /tmp/BatteryPowerWidget-test
```

Expected: exit code 0 with `/tmp/BatteryPowerWidget-test` created.

- [x] **Step 5: Commit widget synchronization**

```bash
git add BatteryPowerWidget.swift
git commit -m "perf: synchronize widget snapshot refresh"
```

### Task 3: Reduce Rendering Cost and Adjust Dot Spacing

**Files:**
- Modify: `BatteryPowerWidget.swift:300-428`
- Modify: `BatteryPowerWidget.swift:735-741`
- Test: `tests/test_swift_runtime_contract.py`

- [x] **Step 1: Cache the time formatter**

Add this property to `BatteryView`:

```swift
private static let timeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    return formatter
}()
```

Replace `timeString()` with:

```swift
private func timeString() -> String {
    Self.timeFormatter.string(from: Date())
}
```

- [x] **Step 2: Apply the approved four-point dot gap**

Change:

```swift
let dotToValueGap: CGFloat = 4
```

Keep `percentValueX`, `maximumPulseRadius`, glow diameter, and dot center Y unchanged.

- [x] **Step 3: Reduce pulse rendering to 15 FPS without slowing the pulse**

Change `advancePulse()` and the timer setup to:

```swift
pulsePhase += 0.32
```

```swift
pulseTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in
    self?.view.advancePulse()
}
```

- [x] **Step 4: Run all source-contract tests**

Run:

```bash
python3 -m unittest tests.test_swift_runtime_contract -v
```

Expected: all five tests pass.

- [x] **Step 5: Run the full Python suite**

Run:

```bash
python3 -m unittest discover -s tests -p 'test_*.py'
```

Expected: all legacy and Swift contract tests pass.

- [x] **Step 6: Commit rendering optimization**

```bash
git add BatteryPowerWidget.swift
git commit -m "perf: reduce status glow rendering cost"
```

### Task 4: Build, Install, and Measure Runtime Behavior

**Files:**
- Modify: `docs/superpowers/plans/2026-06-15-widget-performance.md`
- Verify: `BatteryPowerWidget.swift`
- Verify: `scripts/install.sh`

- [x] **Step 1: Build the WidgetKit extension**

Run:

```bash
xcrun xcodebuild \
  -project BatteryPowerWidgetExtension.xcodeproj \
  -scheme BatteryPowerWidgetExtension \
  -configuration Release \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Expected: `** BUILD SUCCEEDED **`.

- [x] **Step 2: Install and launch the fresh app bundle**

Run:

```bash
./scripts/install.sh
open "$HOME/Applications/电池功率.app"
```

Expected: installation succeeds and the AppKit panel appears.

- [x] **Step 3: Verify five-second snapshot and WidgetKit synchronization**

Observe the snapshot and timeline modification times for at least 15 seconds:

```bash
for i in {1..16}; do
  date '+%H:%M:%S'
  stat -f 'snapshot=%Sm' -t '%H:%M:%S' "$HOME/Library/Application Support/电池功率/widget-snapshot.json"
  stat -f 'timeline=%Sm' -t '%H:%M:%S' "$HOME/Library/Containers/com.leoarrow.battery-monitor.widget/Data/SystemData/com.apple.chrono/timelines/BatteryPowerSystemWidget"/* | tail -n 1
  sleep 1
done
```

Expected: both timestamps advance together approximately every five seconds; the snapshot no longer advances every second.

- [x] **Step 4: Verify successful WidgetKit reloads**

Run:

```bash
/usr/bin/log show --last 2m --style compact \
  --predicate '(process == "chronod" OR process == "BatteryPowerWidgetExtension") AND (eventMessage CONTAINS[c] "com.leoarrow.battery-monitor" OR eventMessage CONTAINS[c] "BatteryPowerSystemWidget")' \
  | rg 'Reload success|Reload failed|Bundle version'
```

Expected: recent `Reload success` entries and no new bundle-version mismatch.

- [x] **Step 5: Verify the visual states manually**

Check charging, adapter-full, and discharging states. Confirm the dot and glow moved four points toward the percentage without touching it, all text remains unclipped, and no other UI changed.

- [x] **Step 6: Measure CPU after warm-up**

Run:

```bash
PID=$(pgrep -f "$HOME/Applications/电池功率.app/Contents/MacOS/applet" | head -n 1)
for i in {1..10}; do
  ps -p "$PID" -o %cpu=,rss=,etime=
  sleep 1
done
```

Expected: sustained CPU is materially below the previous 10-13% single-core baseline, with memory remaining in the same general range.

- [x] **Step 7: Check repository state and commit plan completion**

Update the task checkboxes in this plan, then run:

```bash
git diff --check
git status --short
git add docs/superpowers/plans/2026-06-15-widget-performance.md
git commit -m "docs: complete widget performance plan"
```

Expected: only intended commits exist and the worktree is clean.
