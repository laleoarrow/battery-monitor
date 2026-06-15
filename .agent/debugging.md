# Debugging 电池功率

## Fast verification

To run and verify changes locally:
```bash
xcrun swiftc /Users/leoarrow/Project/mypackage/agents/电池功率/BatteryPowerWidget.swift -framework AppKit -framework CoreGraphics -o /tmp/BatteryPowerWidget-test
/tmp/BatteryPowerWidget-test
```
This launches the native widget directly. You can drag it around, verify text layouts, and close it from the right-click menu.

## Required handoff after any code change

Before claiming a fix or feature is ready, complete this checklist:

1. Test the widget locally in different power states:
   - Charging state (plugged in, percentage < 100%)
   - Adapter-only state (plugged in, percentage = 100%)
   - Discharging state (unplugged)
2. Verify that there is no layout overlapping or clipped text in any of these states.
3. Verify that the compact window is visible, readable, and does not show clipped text.
4. Run the install script to deploy the fresh bundle:
   ```bash
   bash /Users/leoarrow/Project/mypackage/agents/电池功率/scripts/install.sh
   ```
5. Quit the currently running instances of the app:
   ```bash
   pkill -f '电池功率.app/Contents/MacOS/applet|BatteryPowerWidget-test'
   ```
6. Launch the installed app bundle to verify runtime stability:
   ```bash
   open ~/Applications/电池功率.app
   ```
7. Verify that no errors are written to `/Users/leoarrow/Project/UKB/p.cataract.met/agents/tmp/battery_app.log` (if shell redirections are active).
8. Ensure `git status` is clean except for the intended tracked changes.

## Common runtime checks and fixes

### 1. Rectangular background around rounded corners
- **Symptom**: The rounded widget has square background color visible around its corners.
- **Root cause**: Tk windows and child widgets remain rectangular at the window layer.
- **Fix**: Use the native Swift/AppKit `NSPanel` entrypoint. It sets `isOpaque = false`, `backgroundColor = .clear`, and draws the rounded widget inside a transparent window.

### 2. Overlapping text and status alignment
- **Symptom**: Total power, status dot, percentage, or lower-row metrics overlap in compact mode.
- **Root cause**: The compact widget uses fixed-position text drawing to keep the window tiny.
- **Fix**: Keep all secondary values in the lower row, and shrink the main wattage text before it reaches the status area.

## Useful commands

- **List running instances**:
  ```bash
  ps aux | grep -i '电池功率.app/Contents/MacOS/applet'
  ```
- **Kill running instances**:
  ```bash
  pkill -f '电池功率.app/Contents/MacOS/applet|BatteryPowerWidget-test'
  ```
- **Launch the app bundle**:
  ```bash
  open ~/Applications/电池功率.app
  ```
