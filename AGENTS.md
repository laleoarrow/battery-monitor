# Battery Power Monitor agent guide

This project is the native AppKit Wattson menu-bar battery power monitor built
with Swift.

## Read first

- Start with `.agent/README.md`.
- Use `.agent/project.md` for architecture and key files.
- Use `.agent/debugging.md` for runtime debugging, layout fixes, and verification.
- Use `.agent/release.md` for packaging, install/deployment steps, and release tagging.

## Project rules

- All project code and assets must live under `/Users/leoarrow/Project/mypackage/agents/电池功率`.
- The canonical user-facing app is `/Applications/Wattson.app`, installed by
  the native PKG together with its privileged helper and package receipt.
- `battery_monitor.py`, `~/.battery_monitor.py`, and
  `~/Applications/电池功率.app` are retired v2 reference/migration surfaces.
  Never copy or launch them as the current product.
- `scripts/install.sh` is only a user-local developer build. It must fail
  closed while `/Applications/Wattson.app` exists so a second app with the same
  bundle identifier cannot be registered. Use a verified release PKG to update
  the canonical installation.
- Verify AppKit layout changes with the real production renderers and the
  charging, full, on-battery, mixed-supply, low-battery, and Low Power states.
  Use the disposable ARM GUI test VM when visible interaction would interfere
  with the user's desktop.
- Keep git repository status clean and update tags/commits appropriately.
