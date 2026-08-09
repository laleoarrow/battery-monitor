# Wattson v3 handoff

## Release identity

- Version: `3.0.1`
- Source of truth: `VERSION`
- App: `/Applications/Wattson.app`
- Bundle identifier: `com.leoarrow.wattson`
- Helper: `/Library/PrivilegedHelperTools/com.leoarrow.wattson.helper`
- LaunchDaemon: `/Library/LaunchDaemons/com.leoarrow.wattson.helper.plist`
- Package receipt: `com.leoarrow.wattson.pkg`
- Supported systems: macOS 12 or later, Apple silicon and Intel, with an
  internal battery

## Public artifacts

`scripts/release.sh 3.0.1` builds one universal app/helper pair and produces:

- `Wattson-v3.0.1-macos-universal.pkg`
- `Wattson-v3.0.1-macos-universal.dmg`
- `Wattson-v3.0.1-release-info.txt`
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

- Resting glass is no wider than one segment.
- Only a real drag enlarges the lens.
- Dragging previews continuously and commits on release.
- Clicking another mode follows a visible magnetic path rather than jumping.
- Label brightness cross-fades with the real lens position.
- Native Liquid Glass is used on macOS 26; macOS 12–25 use the tested fallback.
- Reduce Motion, Reduce Transparency, keyboard, VoiceOver, and focus behavior
  remain covered.

## Verification

Headless checks:

```bash
swift test --parallel
python3 -m unittest discover -s tests -v
bash scripts/release.sh 3.0.1
```

Visible AppKit checks must be run only in an available GUI session:

```bash
bash scripts/verify_interaction.sh
bash scripts/verify_animation_stress.sh
```

The manual `Wattson release candidate` workflow first replays the native and
legacy AppKit interaction suites plus the animation stress test on its
disposable macOS 26 build runner. It then builds the artifact set once,
then downloads those exact bytes on macOS 14, 15, and 26 Apple-silicon runners
and macOS 15 and 26 Intel runners. It verifies checksums, universal slices,
first install, disabled-service reinstall, the shipped uninstaller, reinstall,
app-process launch stability, helper health, v2.1.5 upgrade, launch-at-login
migration, and final cleanup. All privileged operations stay on disposable
GitHub-hosted runners.

## Release order

1. Make headless CI green on the final commit.
2. Make the manual release-candidate matrix green on that exact commit.
3. Create the annotated `v3.0.1` tag and stable GitHub release from the exact
   candidate artifacts.
4. Require the Homebrew tap sync and tap CI to finish green.
5. Deploy the English website to GitHub Pages and OpenAI Sites.
6. Announce the release only after every public route resolves to v3.0.1.

## v3.0.1 performance work

The v3.0.1 pass preserves the approved UI while caching closed-popover data
instead of rebuilding invisible AppKit layers, keeping the full-battery breath
phase stable and stopping it on close, reusing unchanged menu-bar images,
skipping unchanged history paths, and deriving history samples and peak in one
pass. The adaptive sampling clock, user-hidden module updates, and helper idle
wakeups remain deliberately deferred until Instruments data justifies their
additional lifecycle risk.
