# Wattson

Wattson is a native macOS menu-bar monitor that turns adapter input, battery
flow, and system load into a live power map.

## Highlights

- Native AppKit menu-bar app with a compact real-time power-flow panel.
- Charging, full, battery, and mixed-supply states with state-aware colors.
- Ring gauge, power lanes, animated particles, and two-minute history.
- Auto, Low Power, and supported High Power modes in one fluid glass control.
- Optional system battery-icon visibility and launch-at-login controls.
- Reduce Motion, Reduce Transparency, keyboard, and VoiceOver support.
- No account, analytics, telemetry, or uploaded data.

## Install v3.0.0

Choose one route from the [latest release](https://github.com/laleoarrow/battery-monitor/releases/latest):

### DMG

1. Open `Wattson-v3.0.0-macos-universal.dmg`.
2. Double-click the enclosed `Wattson-v3.0.0-macos-universal.pkg`.
3. Follow macOS Installer and approve the standard administrator prompt.
4. Open Wattson from `/Applications` after installation finishes.

### Direct PKG

Download and open `Wattson-v3.0.0-macos-universal.pkg`. It is the exact same
installer package contained in the DMG.

### Homebrew

```bash
brew install --cask laleoarrow/tap/wattson
```

All three routes install the same universal app at `/Applications/Wattson.app`
and the same on-demand helper at
`/Library/PrivilegedHelperTools/com.leoarrow.wattson.helper`.

The v3 installer upgrades the former `~/Applications/Wattson.app` layout. A
strictly validated v2 launch-at-login entry is migrated to the canonical v3
path during installation, before the retired v2 app is removed.

## Community-build trust note

The current public artifacts follow the same community distribution model as
iData: the app and helper are ad-hoc signed, while the PKG and DMG are not
Developer ID signed or Apple-notarized. macOS may therefore show an
unidentified-developer warning. Use Control-click → Open, or the corresponding
Privacy & Security override, only when you trust this repository and release.
Compare downloads with `SHA256SUMS.txt` before installation.

The release metadata states the signing and notarization status explicitly; it
never describes a community artifact as notarized.

## Requirements

- macOS 12 or later.
- Apple silicon or Intel Mac with an internal battery.
- High Power mode appears only on hardware that supports it.

## When the menu-bar item is hidden

macOS can hide status items when the menu bar is crowded, especially on Macs
with a camera notch. Relaunch Wattson with:

```bash
open "/Applications/Wattson.app"
```

If it remains hidden, reduce other menu-bar items in System Settings. Wattson
cannot override macOS status-item placement.

## Uninstall

```bash
./scripts/uninstall.sh
```

The script removes the canonical app, v2 user-local app, launch-at-login entry,
privileged helper, LaunchDaemon, socket, and package receipt. It intentionally
keeps settings under `~/Library/Application Support/Wattson`.

## Build and verify from source

Headless development checks:

```bash
swift test --parallel
python3 -m unittest discover -s tests -v
```

Build the exact community release artifacts:

```bash
bash scripts/release.sh 3.0.0
```

Outputs:

- `dist/Wattson-v3.0.0-macos-universal.pkg`
- `dist/Wattson-v3.0.0-macos-universal.dmg`
- `dist/Wattson-v3.0.0-release-info.txt`
- `dist/SHA256SUMS.txt`

The release build is universal (`arm64` + `x86_64`) and targets macOS 12.
