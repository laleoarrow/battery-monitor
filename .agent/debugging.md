# Debugging Wattson

## Safe headless checks

```bash
swift test --parallel
python3 -m unittest discover -s tests -v
bash -n scripts/*.sh Packaging/pkg/preinstall Packaging/pkg/postinstall
git diff --check
```

The default Python suite skips real AppKit interaction. It is safe for an
active desktop and must keep `WATTSON_RUN_INTERACTION` unset in ordinary CI.

## Real AppKit interaction

Run only when the user has made the desktop available or in a disposable GUI
session:

```bash
bash scripts/verify_interaction.sh
bash scripts/verify_animation_stress.sh
```

The interaction harness drives real `NSStatusItem`, `NSPopover`, mouse,
keyboard, VoiceOver, Reduce Motion, and legacy/native selector paths. It does
not use system event injection or Accessibility permission.

## Release structure

```bash
WATTSON_RELEASE_VERSION="$(tr -d '\r\n' < VERSION)"
bash scripts/release.sh "$WATTSON_RELEASE_VERSION"
bash scripts/verify_release.sh \
  "dist/Wattson-v${WATTSON_RELEASE_VERSION}-macos-universal.pkg" \
  "dist/Wattson-v${WATTSON_RELEASE_VERSION}-macos-universal.dmg"
```

This builds and mounts artifacts but does not install them. Privileged install,
upgrade, disabled-service reinstall, helper health, app readiness, and cleanup
belong on fresh GitHub-hosted macOS runners unless the user explicitly makes a
local admin test session available.

## Common failures

- `Bootstrap failed: 5`: inspect disabled launchd state, stale job state,
  helper/plist ownership and mode, then use the native PKG lifecycle test. The
  v3 pre/postinstall hooks boot out stale jobs, enable the label, retry
  bootstrap, and trust verified loaded/health state over a misleading return.
- Missing menu-bar item: launch `/Applications/Wattson.app`, then reduce other
  status items if macOS has hidden it behind a notch.
- No power mode: monitoring still works; confirm helper registration and socket
  health rather than prompting during each user action.
- Visual regression: test charging, full, battery, mixed supply, light/dark,
  Reduce Motion, and Reduce Transparency without changing geometry constants
  merely to fix one state.
