# Debugging 电池功率

## Fast verification

To run and verify changes locally:
```bash
python3 /Users/leoarrow/Project/mypackage/agents/电池功率/battery_monitor.py
```
This launches the widget directly. You can drag it around, verify text layouts, and close it using the red traffic light button on the top-left.

## Required handoff after any code change

Before claiming a fix or feature is ready, complete this checklist:

1. Test the widget locally in different power states:
   - Charging state (plugged in, percentage < 100%)
   - Adapter-only state (plugged in, percentage = 100%)
   - Discharging state (unplugged)
2. Verify that there is no layout overlapping or clipped text in any of these states.
3. Verify that the outer corners of the window are fully transparent (no black rectangle background or corners).
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

### 1. Black rectangle border or black corners
- **Symptom**: The widget is drawn on a transparent background, but a thin black rectangle outline is visible around the window boundaries, and the four corners outside the rounded rectangle are filled with black.
- **Root cause**: The default `borderwidth` (or `bd`) of `tk.Canvas` defaults to `1` or `2` pixels on macOS. This draws a solid rectangular border around the canvas, which breaks transparency at the edges.
- **Fix**: Ensure the canvas is created with `bd=0` and `highlightthickness=0`:
  ```python
  canvas = tk.Canvas(root, ..., highlightthickness=0, bd=0)
  ```

### 2. Overlapping text and emoji alignment in the bottom bar
- **Symptom**: When the battery is fully charged, the label becomes `"🔌 适配器:"` (3 Chinese characters) and overlaps with the value text. Alternatively, the plug emoji `🔌` overlaps with `"适配器"`.
- **Root cause**: 
  1. Emojis and standard text combined in a single string trigger mixed-font width calculation errors in Tkinter's renderer on macOS, causing character overlapping.
  2. Statistically positioned label and value items do not scale to text of different lengths (e.g. `"放电:"` has 2 characters, `"适配器:"` has 3 characters).
- **Fix**:
  - Separate emojis, labels, and values into independent canvas text items: `txt_bat_icon`, `txt_bat_lbl`, and `txt_bat_val`.
  - Calculate and update coordinates dynamically after updating text items using `canvas.bbox()`:
    ```python
    bbox_icon = canvas.bbox(txt_bat_icon)
    if bbox_icon:
        canvas.coords(txt_bat_lbl, bbox_icon[2] + 4, 93)
    bbox_lbl = canvas.bbox(txt_bat_lbl)
    if bbox_lbl:
        canvas.coords(txt_bat_val, bbox_lbl[2] + 4, 93)
    ```

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
