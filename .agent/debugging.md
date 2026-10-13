# Debugging Wattson

## Safe headless checks

```bash
swift test
python3 -m unittest discover -s tests -v
bash -n scripts/*.sh Packaging/pkg/preinstall Packaging/pkg/postinstall
git diff --check
```

The default Python suite skips real AppKit interaction. It is safe for an
active desktop and must keep `WATTSON_RUN_INTERACTION` unset in ordinary CI.

## Local app-bundle hygiene

Keep disposable preview apps under `.build/preview.noindex`, using
`scripts/build_glass_preview.sh`. Its staging directory is removed on exit;
rebuilding replaces the previous preview only after verification. Do not retain
`previous-*.app` backups or unpacked app bundles in ordinary `dist` directories:
Spotlight and LaunchServices can expose them as extra applications.

After local preview or release verification, unregister disposable apps with
`lsregister -u <exact-app-path>` before removing them. Preserve required historic
app bytes in a verified compressed archive, alongside their original-path
manifest; retain screenshots, Icon Composer sources, logs, and signed installers.
Package expansion and scratch builds belong in hidden or `.noindex` directories
and must be cleaned when verification ends.

Local cleanup is complete only after checking both Spotlight application search
and LaunchServices registrations for Wattson. Confirm that the canonical
`/Applications/Wattson.app`, helper, package receipt, and running process remain
intact. Do not run the full uninstaller or reset the system-wide application
database to clean up development copies.

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
- Second status-item click closes then reopens: trace the local/global monitor
  and the actual button action together. The native status window's hit area
  extends beyond the shorter button bounds. Its own window and entire frame in
  screen coordinates belong to the button's toggle; a local monitor must not
  close first. Verify the menu bar's top/bottom edges with actual input, as well
  as center clicks, content-then-reclick and closing-animation reuse.
- No power mode: monitoring still works; confirm helper registration and socket
  health rather than prompting during each user action.
- Visual regression: test charging, full, battery, mixed supply, light/dark,
  Reduce Motion, and Reduce Transparency without changing geometry constants
  merely to fix one state.
