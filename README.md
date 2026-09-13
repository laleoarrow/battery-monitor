<h1 align="center">Wattson</h1>

<p align="center">
  <strong>See where every watt goes.</strong><br>
  A native macOS menu-bar app for live adapter, battery, and system power flow.
</p>

<p align="center">
  <a href="https://github.com/laleoarrow/battery-monitor/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/laleoarrow/battery-monitor?display_name=tag&amp;sort=semver"></a>
  <a href="https://github.com/laleoarrow/battery-monitor/actions/workflows/ci.yml"><img alt="Headless CI" src="https://github.com/laleoarrow/battery-monitor/actions/workflows/ci.yml/badge.svg?branch=main"></a>
  <img alt="macOS 12 or later" src="https://img.shields.io/badge/macOS-12%2B-111111?logo=apple&amp;logoColor=white">
  <img alt="Apple silicon and Intel" src="https://img.shields.io/badge/universal-arm64%20%2B%20x86__64-2f81f7">
</p>

<p align="center">
  <a href="https://laleoarrow.github.io/battery-monitor/">Website</a>
  ·
  <a href="https://github.com/laleoarrow/battery-monitor/releases/latest">Download</a>
  ·
  <a href="https://github.com/laleoarrow/battery-monitor/releases">Release notes</a>
</p>

<p align="center">
  <img src="docs/og.png" width="960" alt="Wattson power-flow diagram connecting adapter, battery, and system load">
</p>

## Power, made visible

Wattson turns the relationship between your adapter, battery, and Mac into one
calm live map. Open it from the menu bar to see where power is coming from,
where it is going, and how the picture has changed over the last two minutes.

- Four distinct charging, full, on-battery, and mixed-supply states.
- Live system load, adapter input, battery flow, temperature, cycle count, and
  measured attached-device output when the Mac publishes it.
- Auto and Low Power controls, plus High Power on supported Macs.
- Native Liquid Glass on macOS 26 with an AppKit fallback for macOS 12–25.
- System Light/Dark appearance, keyboard, VoiceOver, Reduce Motion,
  Reduce Transparency, and Increase Contrast support.
- Launch-at-login, system battery-icon, and update controls.
- A compact native Settings window for General, Icon, and Modules.
- System, Light, and Dark themes, independent of Classic or Liquid Glass styling.
- No account, analytics, personal telemetry, or external data upload. Optional
  update checks contact only GitHub Releases.

## Releases

See [GitHub Releases](https://github.com/laleoarrow/battery-monitor/releases)
for version-specific changes and downloads. A newer source version does not
mean an update has been published.

## Install

Choose an asset from the [latest published release](https://github.com/laleoarrow/battery-monitor/releases/latest).
The app-only DMG route below applies to images containing `Wattson.app`.
Older published DMGs, including v3.0.28, contain a PKG instead: opening that
installer performs the full installation and requires administrator approval.
Source changes alone do not mean a new app-only DMG has been published.

| Route | Best for | What to do |
| --- | --- | --- |
| **DMG** | Read-only monitoring | Open the universal DMG and drag `Wattson.app` to `Applications`. This installs no helper or package receipt and does not request administrator authorization to start monitoring. |
| **PKG** | Full installation and existing PKG upgrades | Open the universal PKG and follow macOS Installer to install or update the app and helper together. |
| **Homebrew** | Full installation and terminal updates | Run `brew install --cask laleoarrow/tap/wattson`; the cask uses the PKG. |

Both artifacts contain the same universal app for `/Applications/Wattson.app`.
Without the helper, Wattson monitors the battery data macOS makes available;
helper-backed SMC readings and privileged controls are not available merely
because the app is installed. PKG and Homebrew also install the on-demand
helper at `/Library/PrivilegedHelperTools/com.leoarrow.wattson.helper` and require
the standard macOS administrator prompt. Opening the app-only version does not
automatically install the helper.
Copying into the system Applications folder can still require administrator
approval if your account lacks write access; that and Gatekeeper approval are
separate from Wattson's helper setup.

**Already installed with PKG or Homebrew?** Update through PKG or Homebrew.
Dragging in a new App does not update the existing helper or package receipt.

> [!IMPORTANT]
> Wattson.app and its privileged helper are ad-hoc signed. The PKG and DMG are
> unsigned and not Apple-notarized. App-only monitoring does not remove
> Gatekeeper's trust checks. On macOS 15 or later, first try to open the App or
> installer, then use System Settings → Privacy & Security → Open Anyway only
> when you trust this repository. Older macOS releases may instead offer
> Control-click → Open. Verify the provided
> SHA-256 manifest from the same release
> before installation.

### Requirements

- macOS 12 Monterey or later.
- A battery-equipped Apple silicon or Intel Mac.
- High Power mode requires supported Apple hardware.

The v3 installer safely migrates a strictly validated v2 launch-at-login entry
to `/Applications/Wattson.app` before removing the retired user-local app.

## Update or uninstall

Homebrew users can update and uninstall with:

```bash
brew upgrade --cask laleoarrow/tap/wattson
brew uninstall --cask laleoarrow/tap/wattson
```

For a PKG installation (including older DMGs containing a PKG), open a newer PKG
to update both the app and helper. For an app-only installation with no helper
or receipt, quit Wattson and replace `/Applications/Wattson.app` with the App
from a newer app-only DMG; to uninstall only that App, move it to Trash. Use the
PKG to move from read-only monitoring to the full installation.

For complete cleanup of a full installation, download or clone this repository
and run the included tested uninstaller from the repository root:

```bash
bash scripts/uninstall.sh
```

The script removes Wattson, its launch-at-login entry, privileged helper,
LaunchDaemon, socket, and package receipt. It leaves per-user preferences and
support data untouched.

<details>
<summary><strong>Troubleshooting</strong></summary>

### The menu-bar item is hidden

macOS may hide status items when the menu bar is crowded, especially on Macs
with a camera notch. Relaunch Wattson with:

```bash
open "/Applications/Wattson.app"
```

If it remains hidden, reduce other menu-bar items in System Settings. Wattson
cannot override macOS status-item placement.

### High Power is unavailable

The control remains disabled when the Mac does not expose High Power mode. This
is expected on unsupported hardware.

### macOS blocks the App or installer

Review the community-build notice above and the release checksums first. On
macOS 15 or later, try opening the App or installer once, then go to System Settings →
Privacy & Security and choose Open Anyway. Older macOS releases may offer
Finder’s Control-click → Open.

### Installation still fails

Download the read-only
[Wattson Diagnostics tool](https://github.com/laleoarrow/battery-monitor/releases/download/support-diagnostics-v1.1.0/Wattson-Diagnostics-v1.1.0-macos-universal.zip),
open it using the same Gatekeeper flow above, and click **Collect & Copy
Diagnostics**. The tool requests no administrator password, changes no setting,
and uploads nothing. Review the copied report before pasting it into a support
email.

</details>

## Build and verify

Run the headless development checks:

```bash
swift test
/usr/bin/python3 -m unittest discover -s tests -v
```

Build the community release artifacts using the repository version:

```bash
bash scripts/release.sh "$(tr -d '\r\n' < VERSION)"
```

The release build produces a universal `arm64` + `x86_64` app targeting macOS
12, a full App/helper PKG, an app-only DMG with an Applications shortcut, release
metadata, and `SHA256SUMS.txt`. The App in the DMG must be byte-identical to the
App in the same PKG. Building these artifacts does not publish a release.

## Project links

- [Product website](https://laleoarrow.github.io/battery-monitor/)
- [Latest release](https://github.com/laleoarrow/battery-monitor/releases/latest)
- [Liquid Glass adoption review](.agent/liquid-glass.md)
- [4.1.0 real-window gallery](design/releases/v4.1.0/README.md)
- [Issues and feedback](https://github.com/laleoarrow/battery-monitor/issues)
- [Release and deployment notes](.agent/release.md)

---

<p align="center">
  Wattson is an independent community project and is not affiliated with Apple Inc.
</p>
