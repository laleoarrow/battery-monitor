# Debugging Wattson

## Safe headless checks

```bash
bash scripts/test_swift.sh
python3 -m unittest discover -s tests -v
bash -n scripts/*.sh Packaging/pkg/preinstall Packaging/pkg/postinstall
git diff --check
```

The default Python suite skips real AppKit interaction. It is safe for an
active desktop and must keep `WATTSON_RUN_INTERACTION` unset in ordinary CI.

Run Swift tests through `scripts/test_swift.sh`, including filtered and
`--skip-build` runs. Running preference-writing tests without its manifest
exits before creating a suite and reports the required command.
Create test preference domains with `testDefaultsSuite`;
existing injected domains use `registerTestDefaultsSuite`. Each domain is
recorded before use in that invocation's manifest. After the test process group
stops, the parent clears those exact domains from the real user's preferences
on success, failure, timeout or catchable interruption.
It does not sweep domains belonging to previous or concurrent runs. The runner
removes inherited `CFFIXED_USER_HOME`; that variable can redirect Foundation's
home lookup while macOS still writes UserDefaults into the real user directory.

## Local app-bundle hygiene

`scripts/build_glass_preview.sh` verifies the preview without opening UI and
removes its bundles on exit. Use `--keep-app` only for an explicit handoff to
later visual review; it retains one verified app under `.build/preview.noindex`.
The reviewer then owns its cleanup. `script/build_and_run.sh` owns its preview
session until the app closes; `--verify` stops and cleans its preview after the
readiness check. Never retain `previous-*.app` backups or unpacked app bundles
in ordinary `dist` directories.

Shell entrypoints use `scripts/lib/local_cleanup.sh` and its owned-process
runner. Register only resources created by that invocation before using them.
Cleanup stops and waits for owned processes, unregisters apps while their paths
still exist, clears exact test preference domains, newly created containers and
their matching Application Scripts directories,
detaches owned disk images, and removes scratch directories. A failed detach
must return failure and preserve the mounted directory for recovery. Never
recursively delete a mounted filesystem or stop a process by a global app name.

Python runtime fixtures use `tests/local_runtime.py` for unique project-local
workspaces, bounded process groups, and signal handling. Wrapping a lifecycle
shell script requires `run(..., cleanup_grace=65)` so the outer test waits for
the inner script's bounded unmount and unregister cleanup; ordinary commands
retain the three-second termination grace. `CFFIXED_USER_HOME`
alone does not isolate macOS UserDefaults: inject a unique parent-owned suite
and clear that exact domain at exit using the real account's home directory.
Sandboxed test apps need unique bundle IDs
and cleanup of only their newly created containers and Application Scripts
directories. Keep the production app's
preferences, sandbox, support directory and login agent intact.

After local preview or release verification, unregister disposable apps with
`lsregister -u <exact-app-path>` before removing them. Preserve required historic
app bytes in a verified compressed archive, alongside their original-path
manifest; retain screenshots, Icon Composer sources, logs, and signed installers.
Package expansion and scratch builds belong in hidden or `.noindex` directories
and must be cleaned when verification ends.

Regression tests must exercise repeated success, failure, timeout, and external
HUP/INT/TERM, including children that outlive their parent. SIGKILL and power
loss cannot run an exit handler; inspect the identifiable scratch directories
after such interruptions before declaring cleanup complete. Keep compiler
caches, source snapshots, review evidence and packaged releases distinct from
disposable runnable apps.

Local cleanup is complete only after checking both Spotlight application search
and LaunchServices registrations for Wattson. Confirm that the canonical
`/Applications/Wattson.app`, helper, package receipt, and running process remain
intact. Do not run the full uninstaller or reset the system-wide application
database to clean up development copies.

Settings capture bundles must include the three `design/icon/in-app-logo`
PNGs in `Contents/Resources`, as the release build does. Verify the displayed
Color and Clear artwork in light and dark appearances before accepting a
capture; missing artwork can silently fall back to the system app placeholder.

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

History-specific geometry and renderer checks live in `HistoryChartTests` and
`HistoryViewTests`. The interaction harness also exercises real-window History
animation completion and cancellation. Check startup and irregular sample
spacing, retained peaks, sampling gaps, scale contraction, close/reopen,
module visibility and accessibility motion policy. Keep six-state light/dark
production-renderer captures and an actual short motion capture with the
verified source identity; an HTML algorithm preview alone is insufficient.

After an authorized canonical PKG upgrade, use `/usr/bin/open -g
/Applications/Wattson.app`, matching the native postinstall path. Do not add
`-j` (launch hidden) merely to avoid activating the app: `-g` already requests
background launch. A stable PID verifies process lifetime, not menu-bar popup
readiness. Confirm an actual canonical status-item click opens and closes the
visible popup before marking that behavior accepted. When host input is
unavailable, keep that final check explicitly pending. The `popup-events` info
log records `source=status-action openBefore=false openAfter=true` on opening.
For a silent-click report, preserve that log and a process sample before any
restart; restarting only Wattson can recover its presentation state without
resetting preferences or reinstalling the package.

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
- Classic clicks stop reaching the button after content focus: trace the native
  window, button and target/action separately. A matching hit test does not
  prove delivery. Use semi-transient behavior and retire a closing native host
  before reopening so a queued show cannot supersede a later close. Verify four
  rapid clicks end closed, then reopen. Semi-transient behavior needs a local
  mouse monitor for clicks in other Wattson windows; preserve the content,
  status anchor and native menu windows. For remote keyboard checks, confirm the
  actual key code/modifiers and foreground change before classifying a failure.
- No power mode: monitoring still works; confirm helper registration and socket
  health rather than prompting during each user action.
- Visual regression: test charging, full, battery, mixed supply, light/dark,
  Reduce Motion, and Reduce Transparency without changing geometry constants
  merely to fix one state.
