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
  <a href="#whats-new-in-v3027">v3.0.27 notes</a>
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
- Keyboard, VoiceOver, Reduce Motion, and Reduce Transparency support.
- Launch-at-login, system battery-icon, and update controls.
- A compact native Settings window for General, Menu Bar Icon, and Modules.
- No account, analytics, personal telemetry, or external data upload. Optional
  update checks contact only GitHub Releases.

## What's new in v3.0.27

- One sampling clock now serves both visible updates and history, avoiding
  independent timer phases while retaining immediate event-driven refreshes.
  Hidden polling stays at two seconds; slow reads do not create catch-up work.
- Identical power-flow curves reuse particle paths and running animations.
  Real split changes still retarget them without restarting particle phases;
  speed, topology, and animation accessibility changes remain live.
- Preference defaults register once per store, not on every read. Settings
  changes refresh only affected presentation; preference values are not cached.
- Wake immediately marks pre-sleep readings stale until fresh data arrives.
  Opening refreshes survive periodic timer rearming, while callbacks from a
  closed panel cannot affect a later reopening.
- Existing artwork, layout, measured-only Device Output and evidence-gated
  fusion are unchanged. These reduce redundant work; they are not claims of
  universally higher FPS, lower RAM use, or improved sensor accuracy.

## What's new in v3.0.26

- A disconnected adapter never becomes the power-flow source at low or zero
  battery load. Zero-watt branches do not animate as active power transfers.
- Last-known readings stop moving when acquisition fails and resume only after
  fresh data arrives. Plugged-in batteries below 100% say Not Charging/Idle,
  rather than Full.
- Valid instantaneous discharge is retained when telemetry totals and average
  current are missing. Anonymous USB output entries no longer collide with
  explicitly numbered ports merely because their array order changes.
- Partial USB measurements retain their known sum without masquerading as a
  complete output total or being subtracted to produce an exact Mac Load.
- History and peak now expire after 120 real seconds even when sampling slows
  down or stops. Existing layout, artwork, and evidence-gated fusion remain.

## What's new in v3.0.25

- Completed samples keep updating the display and history during a sustained
  stream of power-source notifications, while one fresh follow-up remains
  coalesced. A notification no longer indefinitely suppresses every result.
- Wake events still invalidate a sample started before wake and transfer its
  history request to the fresh sample, avoiding stale post-wake publication.
- Keeps the v3.0.24 shared acquisition, measured-only Device Output, and
  selected port artwork. This fixes software refresh starvation; firmware
  measurement delays and absolute accuracy are not claimed to be solved.

## What's new in v3.0.24

The Download link above always points to the latest release that has completed
the public installation gates; a source version alone is not a published update.

- Shares one allowlisted battery acquisition between the visible display and
  shadow observer. Each sample now requests 12 registry properties instead of
  19, with one service lookup instead of two. The helper still runs concurrently.
  This reduces duplicate work and cross-read disagreement, not firmware update
  latency; it is not a measured battery-life improvement.
- Rejects malformed or oversized Device Output arrays without inventing a
  zero-watt reading. Missing measurements remain unavailable, while valid
  measured zero is preserved.
- Includes the v3.0.23 improvements below, including the selected closed-port
  icon. Existing power-flow geometry and the evidence-gated display policy stay
  unchanged.

## What's new in v3.0.23

- Device Output now uses one closed port template extracted from the selected
  visual source. The compact plugged-state accessory and the existing
  on-battery Device Output node reuse that same template, replacing their
  inconsistent cable-connector glyphs. The existing inline readout, three-node
  and two-pipe layouts, popover height, power totals, and conservation math are
  unchanged. This presentation-only correction does not accelerate firmware
  publication or hardware recognition.

- Uses signed battery voltage × current to govern battery-flow direction when
  direct adapter and system rails arrive asynchronously. This prevents an
  attached iPhone reported as Device Output from being paired with a false
  Battery Assist or Mixed Power state. It corrects flow consistency only and
  does not claim external-meter absolute accuracy.

- Adds the strict, read-only helper protocol v5 for fixed `PDTR`, `PSTR`, and
  `PPBR` observations. Complete and typed partial v5 responses are
  authoritative; malformed or truncated claimed-v5 frames fail closed, while
  an older helper receives exactly one compatible v4 fallback.
- Runs the evidence-backed power resolver in production shadow mode. Direct
  observations can feed the established display resolver, but unproven PSTR
  band correction remains disabled and any missing, stale, or invalid evidence
  falls back without changing the visible power model.
- Preserves measured Device Output as an auxiliary breakdown of System Load,
  never an additional load. In plugged, charging, and mixed-supply states, a
  positive coherent Device Output is now clear in the main Power Flow as an
  auxiliary readout: it is included in System Total and never double-counted.
  On battery, the existing positive-coherent three-node split into Mac Load and
  Device Output continues unchanged. A valid zero remains visible in the power
  summary; unavailable or incoherent readings restore Cycle Count. Firmware
  publication can still be delayed. This presentation change does not claim
  external-meter absolute accuracy.
- Makes the native PKG verify both the existing v4 helper health surface and
  the strict v5 observation surface after installation.

## v3.0.18 measured attached-device output (historical)

- Shows measured power delivered to attached devices when the Mac publishes a
  usable reading. Device Output is an auxiliary breakdown of System Load, not
  an additional load.
- Keeps the popover geometry unchanged: Device Output reuses the existing Cycle
  Count slot, and a positive coherent on-battery reading splits the existing
  three-node flow into Mac Load and Device Output. A measured zero remains
  visible; unavailable or incoherent readings restore the previous presentation.

## v3.0.17 lighter power-flow node family (historical)

- Refines the approved A1 power-flow icon direction with a slightly smaller,
  lighter treatment: 21-point Regular symbols and 1.6-point custom outlines
  inside the existing 36-point wells.
- Adapter, System, and Battery remain on one optical scale. Their real visible
  extents target 19.25–21.5 points and measure 20–21.25 points across the
  production states, while semantic source and load colours remain unchanged.
- Retains the clear diagonal adapter plug, simplified matching System chip,
  and green bracketed charging battery with a central lightning mark.

## v3.0.16 unified power-flow node scale (historical)

- v3.0.16 first placed the Adapter, System, and Battery power-flow node icons
  on one shared optical scale. System adopted a simplified matching chip glyph,
  while the existing semantic source and load colours remained unchanged.

## v3.0.15 restored power-flow node artwork

- Restores the earlier power-flow node artwork: the adapter is again a clear
  diagonal plug, while an actively charging battery uses the green bracketed
  battery with a central lightning mark. Idle, full, discharging, and mixed
  states keep their real state-specific battery levels and colours.
- The restored power glyphs use a 24-point Medium treatment inside the existing
  36-point wells, so the diagram geometry, motion, and spacing do not change.

- General adds Check for Updates and Check for Updates on Launch. Manual checks
  read GitHub Latest Release and open its trusted release page; launch checks
  default on, stay quiet when current or offline, and never download or install
  automatically.

- The dedicated Menu Bar Icon page now lists all four complete menu-bar
  appearances vertically, one full-width option per row: Wattson icon only,
  Wattson with percentage, macOS 26 icon only, and macOS 26 with percentage.
- Every row previews seven real production-rendered states: Battery, Full,
  Charging, Low, Low + AC, Saver, and Saver + AC. Every preview uses the real
  BatteryIcon renderer; percentage rows show matching per-state values to the
  left of each glyph. The macOS 26 rows use full-size macOS 26 Control Center
  battery parts from the running system, including the 23×12 outline and 11×14
  bolt, instead of smaller Control Center artwork or generic SF Symbols. Every
  connected state uses the system bolt. In Low Power Mode, only the battery
  fill is yellow; the outline, cap, and bolt keep the menu-bar foreground
  colour.
- Settings keeps its compact, fixed 720×520 window for General, Menu Bar Icon,
  and Modules.
- The Settings sidebar now uses the real packaged Wattson app icon instead of
  a separate ECG-style drawing.

## Install v3.0.17

| Route | Best for | What to do |
| --- | --- | --- |
| **DMG** · Recommended | Guided installation | [Download the universal DMG](https://github.com/laleoarrow/battery-monitor/releases/download/v3.0.17/Wattson-v3.0.17-macos-universal.dmg), open it, then double-click the enclosed PKG. |
| **PKG** | Direct installation | [Download the universal PKG](https://github.com/laleoarrow/battery-monitor/releases/download/v3.0.17/Wattson-v3.0.17-macos-universal.pkg) and follow macOS Installer. |
| **Homebrew** | Terminal installation and updates | Run `brew install --cask laleoarrow/tap/wattson`. |

All three routes install the same universal app at
`/Applications/Wattson.app` and the same on-demand helper at
`/Library/PrivilegedHelperTools/com.leoarrow.wattson.helper`. The standard
macOS administrator prompt is required to install the helper.

> [!IMPORTANT]
> Wattson.app and its privileged helper are ad-hoc signed. The PKG and DMG are
> unsigned and not Apple-notarized. On macOS 15 or later, first try to open the
> installer, then use System Settings → Privacy & Security → Open Anyway only
> when you trust this repository. Older macOS releases may instead offer
> Control-click → Open. Verify the provided
> [SHA-256 manifest](https://github.com/laleoarrow/battery-monitor/releases/download/v3.0.17/SHA256SUMS.txt)
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

For a direct DMG or PKG installation, open a newer PKG to update. To uninstall,
download or clone this repository and run the included tested uninstaller from
the repository root:

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

### macOS blocks the installer

Review the community-build notice above and the release checksums first. On
macOS 15 or later, try opening the installer once, then go to System Settings →
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
12, a PKG, a DMG containing that exact PKG, release metadata, and
`SHA256SUMS.txt`.

## Project links

- [Product website](https://laleoarrow.github.io/battery-monitor/)
- [Latest release](https://github.com/laleoarrow/battery-monitor/releases/latest)
- [Issues and feedback](https://github.com/laleoarrow/battery-monitor/issues)
- [Release and deployment notes](.agent/release.md)

---

<p align="center">
  Wattson is an independent community project and is not affiliated with Apple Inc.
</p>
