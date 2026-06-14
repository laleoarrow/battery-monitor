# Battery Power Monitor agent guide

This project is a native macOS floating battery power monitor widget built using Python and Tkinter.

## Read first

- Start with `.agent/README.md`.
- Use `.agent/project.md` for architecture and key files.
- Use `.agent/debugging.md` for runtime debugging, layout fixes, and verification.
- Use `.agent/release.md` for packaging, install/deployment steps, and release tagging.

## Project rules

- All project code and assets must live under `/Users/leoarrow/Project/mypackage/agents/电池功率`.
- The runtime code copied to user's system runs from `~/.battery_monitor.py`. Always sync modifications from the project directory's `battery_monitor.py` to `~/.battery_monitor.py` after editing.
- The user-facing app bundle is located at `~/Applications/电池功率.app/` and wraps the python script.
- Ensure that the canvas has `bd=0` and `highlightthickness=0` to preserve clean transparency with no black corners/borders.
- Any change to the layout must be verified manually with different battery charging/discharging states to avoid overlapping labels and values (especially in the "适配器" connected/fully-charged state which uses wider text).
- Emojis (e.g. 💻, 🔋, 🔌, ⚡) should be rendered as separate canvas items rather than combined in strings to prevent mixed-font width calculation errors in Tkinter on macOS.
- Keep git repository status clean and update tags/commits appropriately.
