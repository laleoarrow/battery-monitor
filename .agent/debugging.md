# Debugging 电池功率

## Fast verification

To run and verify changes locally:
```bash
/usr/local/bin/python3 /Users/leoarrow/Project/mypackage/agents/电池功率/battery_monitor.py
```
This launches the widget directly. You can drag it around, verify text layouts, and close it from the right-click menu.

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
   pkill -f battery_monitor.py
   ```
6. Launch the installed app bundle to verify runtime stability:
   ```bash
   open ~/Applications/电池功率.app
   ```
7. Verify that no errors are written to `/Users/leoarrow/Project/UKB/p.cataract.met/agents/tmp/battery_app.log` (if shell redirections are active).
8. Ensure `git status` is clean except for the intended tracked changes.

## Common runtime checks and fixes

### 1. Window shell appears but text is missing
- **Symptom**: The window frame appears, but power text and status labels do not render.
- **Root cause**: On this Mac, the Xcode Python Tk runtime can show the window shell without reliably rendering child widgets.
- **Fix**: Use `/usr/local/bin/python3` first. The installer intentionally prefers `/usr/local/bin/python3` before `/usr/bin/python3`.

### 2. Overlapping text and status alignment
- **Symptom**: Total power, status dot, or percentage overlap in compact mode, or detail labels clip in expanded mode.
- **Root cause**: The compact widget uses fixed-size Label placements to keep the window tiny.
- **Fix**: Keep compact mode to the three primary elements only: total power, status dot, and percentage. Put secondary details only in the expanded view.

## Useful commands

- **List running instances**:
  ```bash
  ps aux | grep -i battery_monitor.py
  ```
- **Kill running instances**:
  ```bash
  pkill -f battery_monitor.py
  ```
- **Launch the app bundle**:
  ```bash
  open ~/Applications/电池功率.app
  ```
