# Wattson v3 handoff

## Release identity

- Version: `3.0.4`
- Source of truth: `VERSION`
- App: `/Applications/Wattson.app`
- Bundle identifier: `com.leoarrow.wattson`
- Helper: `/Library/PrivilegedHelperTools/com.leoarrow.wattson.helper`
- LaunchDaemon: `/Library/LaunchDaemons/com.leoarrow.wattson.helper.plist`
- Package receipt: `com.leoarrow.wattson.pkg`
- Supported systems: macOS 12 or later, Apple silicon and Intel, with an
  internal battery

## Public artifacts

`scripts/release.sh 3.0.4` builds one universal app/helper pair and produces:

- `Wattson-v3.0.4-macos-universal.pkg`
- `Wattson-v3.0.4-macos-universal.dmg`
- `Wattson-v3.0.4-release-info.txt`
- `SHA256SUMS.txt`

The DMG contains exactly one visible item: a byte-identical copy of the PKG.
The same PKG is used for the direct download and Homebrew cask.

The default public build follows the iData community distribution model. The
app and helper are ad-hoc signed; the PKG and DMG are not Developer ID signed
or Apple-notarized. Release metadata and the website state this explicitly.

## Installation lifecycle

The native PKG installs the app and helper with macOS Installer, stops any
existing helper, clears a stale disabled state, bootstraps the new helper, and
performs a read-only health probe. It never changes the current power mode.

The v3 upgrade path retires the former `~/Applications/Wattson.app`. Before
deleting it, the installer asks the root-only helper to migrate only an exact,
user-owned v2 launch-at-login plist to `/Applications/Wattson.app`. Arbitrary
or malformed LaunchAgents are left untouched.

The user-local `scripts/install.sh` path remains a developer build. It does not
expose launch-at-login controls, so it cannot accidentally control a separate
system installation.

## User interface

All shipped user-facing copy is English. The settings menu shows the exact
`CFBundleShortVersionString` as `Wattson Version <version>`.

The mode selector keeps the v2.1.5 interaction contract:

- The resting selection is no wider than one segment.
- Only a real drag enlarges the selection capsule.
- Dragging previews continuously and commits on release.
- Clicking another mode follows a visible magnetic path rather than jumping.
- Label brightness cross-fades with the real selection position.
- One native Liquid Glass track is used on macOS 26 with a neutral selection
  capsule; macOS 12–25 use the tested fallback.
- Reduce Motion, Reduce Transparency, keyboard, VoiceOver, and focus behavior
  remain covered.

## Verification

Headless checks:

```bash
swift test --parallel
python3 -m unittest discover -s tests -v
bash scripts/release.sh 3.0.4
```

Visible AppKit checks must be run only in an available GUI session:

```bash
bash scripts/verify_interaction.sh
bash scripts/verify_animation_stress.sh
```

Pushing the frozen `main` commit unchanged to `release-candidate` starts the
`Wattson release candidate` workflow. It first replays the native and legacy
AppKit interaction suites plus the animation stress test on its disposable
macOS 26 build runner. It then builds the artifact set once, then downloads
those exact bytes on macOS 14, 15, and 26 Apple-silicon runners and macOS 15
and 26 Intel runners. It verifies checksums, universal slices, first install,
disabled-service reinstall, the shipped uninstaller, reinstall, app-process
launch stability, helper health, v2.1.5 upgrade, launch-at-login migration, and
final cleanup. All privileged operations stay on disposable GitHub-hosted
runners.

## Release order

1. Freeze one final commit, push that exact SHA to `main`, and require Headless
   CI to pass.
2. Push the same SHA to `release-candidate`. That push intentionally exercises
   the credential-free `community-ad-hoc` build and five-platform install
   matrix without starting signed-only promotion.
3. If Developer ID and notary credentials are configured, use a manual
   `developer-id-notarized` candidate on `main`; its successful run may enter
   the fail-closed promotion workflow. Never send a community candidate into
   that signed-only promotion path.
4. For a community release, download the exact artifact set from the successful
   branch candidate, verify its manifest and checksums again, create the
   annotated `v3.0.4` tag on the frozen SHA, and publish those unchanged bytes
   with explicit ad-hoc/unsigned/not-notarized wording.
5. Synchronize the Homebrew cask to that exact PKG checksum and require both
   tap CI and the public Intel/Apple-silicon lifecycle tests before marking the
   release latest and deploying the tag-pinned GitHub Pages site.
6. Announce the release only after every public route resolves to v3.0.4.

## v3.0.4 telemetry compatibility work

The v3.0.4 pass corrects Smart Battery temperature units, falls back to the
Apple-silicon virtual temperature field, and distinguishes unavailable
temperature from a real 0°C. It also moves sampling off AppKit's main thread
and uses the fixed read-only SMC helper path for responsive whole-machine power
without deriving false battery-flow spikes from independently timed SMC keys.
During the short battery-to-adapter transition where the system telemetry is
still stale, the signed instantaneous battery current supplies the flow state
until the coherent telemetry catches up.

## v3.0.3 selector and support work

The v3.0.3 pass removes the resting selector's inset gap at the first and last
detents and keeps the selector and track on matching continuous capsule corners.
It also adds a separate, universal read-only diagnostics support app that copies
a bounded installation report without requesting a password, changing settings,
or uploading data.

## v3.0.2 selector work

The v3.0.2 pass moves click and release motion to Core Animation's compositor,
keeps direct dragging one-to-one, shortens magnetic release, and blends label
brightness from the visible capsule position. It also handles re-grabbing an
active animation and rejected mode writes without a one-frame jump, including
the Reduce Motion path.

## v3.0.1 performance work

The v3.0.1 pass preserves the approved UI while caching closed-popover data
instead of rebuilding invisible AppKit layers, keeping the full-battery breath
phase stable and stopping it on close, reusing unchanged menu-bar images,
skipping unchanged history paths, and deriving history samples and peak in one
pass. The adaptive sampling clock, user-hidden module updates, and helper idle
wakeups remain deliberately deferred until Instruments data justifies their
additional lifecycle risk.
