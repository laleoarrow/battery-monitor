# Wattson v3 handoff

## Release identity

- Candidate version: `3.0.23`
- Current public release: `3.0.17`
- Source of truth: `VERSION`
- App: `/Applications/Wattson.app`
- Bundle identifier: `com.leoarrow.wattson`
- Helper: `/Library/PrivilegedHelperTools/com.leoarrow.wattson.helper`
- LaunchDaemon: `/Library/LaunchDaemons/com.leoarrow.wattson.helper.plist`
- Package receipt: `com.leoarrow.wattson.pkg`
- Supported systems: macOS 12 or later, Apple silicon and Intel, with an
  internal battery

## Release artifacts

`scripts/release.sh 3.0.23` builds one universal app/helper pair and produces:

- `Wattson-v3.0.23-macos-universal.pkg`
- `Wattson-v3.0.23-macos-universal.dmg`
- `Wattson-v3.0.23-release-info.txt`
- `SHA256SUMS.txt`

The DMG contains exactly one visible item: a byte-identical copy of the PKG.
The same PKG is used for the direct download and Homebrew cask.

The default test-package build follows the iData community distribution model. The
app and helper are ad-hoc signed; the PKG and DMG are not Developer ID signed
or Apple-notarized. Release metadata and the website state this explicitly.

## Installation lifecycle

The native PKG already installs the canonical app at
`/Applications/Wattson.app` and retires only the exact Wattson app at
`~/Applications/Wattson.app` as part of its established lifecycle. It also
stops any existing helper, clears a stale disabled state, bootstraps the new
helper, and performs a read-only health probe without changing the current
power mode.

The v3 upgrade path retires the former `~/Applications/Wattson.app`. Before
deleting it, the installer asks the root-only helper to migrate only an exact,
user-owned v2 launch-at-login plist to `/Applications/Wattson.app`. Arbitrary
or malformed LaunchAgents are left untouched.

The user-local `scripts/install.sh` path remains a developer build. It fails
closed while `/Applications/Wattson.app` exists, preventing a second app with
the same bundle identifier from being registered. Canonical updates use the
verified native PKG.

## User interface

All shipped user-facing copy is English. The settings menu shows the exact
`CFBundleShortVersionString` as `Wattson Version <version>`.

Settings uses a fixed 720×520 window. The dedicated Menu Bar Icon page places
all four complete appearances vertically, one full-width option per row:
Wattson icon only, Wattson with percentage, macOS 26 icon only, and macOS 26
with percentage. Every row previews seven real production-rendered states:
Battery, Full, Charging, Low, Low + AC, Saver, and Saver + AC. Every preview
uses the real BatteryIcon renderer; percentage rows show matching per-state
values to the left of each glyph. The macOS 26 rows use full-size macOS 26
Control Center battery parts from the running system, including the 23×12
outline and 11×14 bolt, instead of smaller Control Center artwork or generic SF
Symbols. Every connected state uses the system bolt. In Low Power Mode, only
the battery fill is yellow; the outline, cap, and bolt keep the menu-bar
foreground colour. General adds Check for Updates and Check for Updates on
Launch. Manual checks read GitHub Latest Release and open its trusted release
page; launch checks default on, stay quiet when current or offline, and never
download or install automatically. The sidebar identity uses a PNG derived
during packaging from the same `AppIcon.icns` that Finder displays, rather than
a separate ECG-style drawing.

The Adapter, System, and Battery power-flow nodes use the approved A1 direction
with a slightly smaller, lighter finish: 21-point Regular symbols and 1.6-point
custom outlines inside the existing 36-point wells. Their real visible extents
target 19.25–21.5 points and measure 20–21.25 points across the production
states. The diagonal adapter plug, simplified matching System chip, bracketed
charging battery, and established semantic state colours remain intact.

When firmware publishes usable measured per-port output, Wattson reads only
`PowerOutDetails.Watts` and sums its milliwatt values. `PDPowermW`,
`FilteredPower`, and `Configured*` remain excluded because they are negotiated
capabilities or differently scaled data, not measured output. Device Output is
an auxiliary breakdown of `systemW`, never an additional sink.

The fixed 138-point power summary reuses its trailing Cycle Count slot for
Device Output. A valid zero remains visible as `0.0 W`. On battery, only a
positive coherent measurement activates the existing three-node, two-pipe
split from Battery to Mac Load and Device Output. Zero keeps the standard flow
while the summary continues to show `Device Output 0.0 W`; only missing or
incoherent output restores Cycle Count.

In plugged, charging, and mixed-supply states, a coherent positive Device
Output is also clear in the main Power Flow as an auxiliary readout. It remains
included in System Total and is never double-counted; the existing on-battery
split is unchanged. Firmware can still delay publishing the measurement. This
presentation change does not claim external-meter absolute accuracy.

The mode selector keeps the v2.1.5 interaction contract:

- The resting selection is no wider than one segment.
- The selection capsule stays at 1× while dragging.
- Dragging previews continuously and commits on release.
- Clicking another mode follows a visible magnetic path rather than jumping.
- Label brightness cross-fades with the real selection position.
- The refined 2A airy-glass control is the default: macOS 26 uses native Liquid
  Glass, while macOS 12–25 use the tested optical fallback.
- macOS system Reduce Motion automatically swaps in a native 2C segmented
  control without adding an app setting or saved preference.
- Reduce Motion, Reduce Transparency, keyboard, VoiceOver, and focus behavior
  remain covered.

## Verification

Headless checks:

```bash
swift test
python3 -m unittest discover -s tests -v
bash scripts/release.sh 3.0.23
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

v3.0.23 is the current release candidate. v3.0.17 remains the current public
release until the new candidate completes every release gate. The candidate
commit, artifact set, local canonical installation, and repository `VERSION`
must remain aligned with the exact tested bytes.

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
   annotated `v3.0.23` tag on the frozen SHA, and publish those unchanged bytes
   with explicit ad-hoc/unsigned/not-notarized wording.
5. Synchronize the Homebrew cask to that exact PKG checksum and require both
   tap CI and the public Intel/Apple-silicon lifecycle tests before marking the
   release latest and deploying the tag-pinned GitHub Pages site.
6. Announce the release only after every public route resolves to v3.0.23.

## v3.0.23 strict power observation runtime

Device Output now uses one closed port template extracted from the selected
visual source. The compact plugged-state accessory and the existing on-battery
Device Output node reuse that same template, replacing their inconsistent
cable-connector glyphs. The existing inline readout, three-node and two-pipe
layouts, node and pipe positions, popover height, power totals, and conservation
math remain unchanged. This is a presentation-only correction; it does not
accelerate firmware publication or hardware recognition.

The visible resolver now uses signed battery voltage × current to govern
battery direction when direct adapter and system rails arrive
asynchronously. This prevents an iPhone measured under Device Output from being
paired with an invented Battery Assist or Mixed Power state when signed battery
current is zero. This corrects flow consistency only; it does not claim
external-meter absolute accuracy.

The helper now exposes a strict, read-only `getPowerObservation` protocol v5
surface. It reads only the fixed `PDTR`, `PSTR`, and `PPBR` SMC keys, preserves
their raw bytes, data types, decoded values, and timing, and emits a bounded
newline-terminated response. Complete and typed partial v5 responses are
authoritative. Claimed-v5 malformed or truncated frames fail closed; a new app
talking to an older helper receives exactly one v4 compatibility fallback.

The app runs these observations through the production shadow runtime while
keeping the evidence-derived `PSTRBandPolicy` nil and the user-visible fusion
gate closed. Direct observations may feed the established legacy display
resolver, but missing, stale, partial, ambiguous, or invalid evidence cannot
activate band correction or conservation repair. `PPBR` remains a nonnegative
magnitude only, battery direction comes only from signed voltage × current,
and nonzero residuals remain observable rather than being repaired away.

Device Output remains measured auxiliary data from `PowerOutDetails.Watts`,
not an additional sink and never a value synthesized from `PDPowermW`,
`FilteredPower`, `Configured*`, `PPBR`, or a residual. It remains an auxiliary
breakdown of `systemW`. The fixed 138-point summary preserves a valid zero and
reuses the Cycle Count slot. Only a positive coherent value no greater than
the current system total can affect presentation; no value is silently
clamped. On battery, it activates the existing three-node, two-pipe split into
Mac Load and Device Output. In plugged, charging, and mixed-supply states, it
appears in the main Power Flow as an auxiliary readout, remains included in
System Total, and is never double-counted. Ring and lane views keep the
unsplit rail as System Total, while missing or incoherent readings restore the
prior presentation. Firmware publication delay remains explicit. This UI
change does not claim external-meter absolute accuracy.

The native PKG postinstall path keeps the v4 health check and additionally
requires the installed app and helper to complete the strict v5 observation
probe in an interactive console session. The release verifier checks both
protocol surfaces in the built and packaged bytes.

## v3.0.18 measured attached-device output (historical)

Wattson reads only measured per-port `PowerOutDetails.Watts` values and sums
their milliwatt readings. `PDPowermW`, `FilteredPower`, and `Configured*`
values remain excluded because they are negotiated capabilities or differently
scaled data, not measured output. Device Output remains an auxiliary breakdown
of `systemW`, never an additional sink.

The fixed 138-point power summary reuses its trailing Cycle Count slot for
Device Output. A valid zero remains visible as `0.0 W`. On battery, only a
positive coherent measurement activates the existing three-node, two-pipe
split from Battery to Mac Load and Device Output. Zero output keeps the
standard flow while the summary continues to show `Device Output 0.0 W`;
missing or incoherent data restores Cycle Count.

## v3.0.17 lighter power-flow node family (historical)

The v3.0.17 release refines the approved A1 power-flow icon direction with a
slightly smaller, lighter finish. Adapter, System, and Battery now use 21-point
Regular symbols and 1.6-point custom outlines inside the existing 36-point
wells. Their real visible extents target 19.25–21.5 points and measure
20–21.25 points across the production states. The clear diagonal adapter plug,
simplified matching System chip, green bracketed charging battery with its
central lightning mark, and semantic source and load colours remain unchanged.

## v3.0.16 unified power-flow node scale (historical)

The superseded v3.0.16 release first gave the Adapter, System, and Battery
power-flow node icons one shared optical scale. System used a simplified
matching chip glyph, while the established semantic source and load colours
remained unchanged. v3.0.17 keeps that family and reduces its weight and scale.

## v3.0.15 restored power-flow node artwork

The v3.0.15 release restores the earlier power-flow node artwork approved from
the product references: the adapter is again a clear diagonal plug, while an
actively charging battery uses the green bracketed battery with a central
lightning mark. Both use a 24-point Medium treatment inside the existing
36-point wells. Idle, full, discharging, and mixed states retain their real
state-specific battery levels and colours, and the flow geometry, motion, and
spacing are unchanged. The release also includes Check for Updates and the
v3.0.14 launch update checks,
the four-by-seven Menu Bar Icon selector, the macOS 26 native battery artwork,
and the packaged app icon in Settings.

## v3.0.14 update checks

The v3.0.14 candidate adds Check for Updates and Check for Updates on Launch to
General while retaining Launch at Login and Hide System Battery Icon. Manual
checks read GitHub Latest Release and open its trusted release page; launch
checks default on, stay quiet when current or offline, and never download or
install automatically. The preference is stored with the existing typed
Settings change notifications. Release parsing rejects drafts, prereleases,
non-semantic tags, and release links outside the Wattson GitHub repository.

## v3.0.13 macOS 26 native icon correction

The v3.0.13 candidate corrects the macOS 26 menu-bar appearance against the
system icon shown on the right side of the maintainer's direct comparison. The
dedicated Menu Bar Icon page still lists all four complete appearances
vertically, one full-width option per row: Wattson icon only, Wattson with
percentage, macOS 26 icon only, and macOS 26 with percentage. Every row
previews seven real production-rendered states: Battery, Full, Charging, Low,
Low + AC, Saver, and Saver + AC. Every preview uses the real BatteryIcon
renderer; percentage rows show matching per-state values to the left of each
glyph. The
macOS 26 rows use full-size macOS 26 Control Center battery parts from the
running system, including the 23×12 outline and 11×14 bolt, instead of the
smaller Control Center artwork or generic SF Symbols. Every connected state
uses the system bolt. Full charge uses the opaque system fill. In Low Power
Mode, only the battery fill is yellow; the outline, cap, and bolt keep the
menu-bar foreground colour. Settings previews retain each production image's
native canvas. The sidebar identity now uses the packaged Wattson app icon
instead of the superseded ECG-style drawing. The native previews retain their
25×14 canvas instead of compressing it to Wattson's 23-point width. The
four-row, seven-state layout and compact 720×520 Settings window remain
unchanged. General contains only Launch at Login and Hide System Battery Icon.

## v3.0.12 complete runtime-state previews

The v3.0.12 candidate corrects the dedicated Menu Bar Icon page so the user can
see and select all four complete menu-bar appearances vertically, one
full-width option per row: Wattson icon only, Wattson with percentage, macOS 26
icon only, and macOS 26 with percentage. Every row previews seven real
production-rendered states: Battery, Full, Charging, Low, Low + AC, Saver, and
Saver + AC. Every preview uses the real BatteryIcon renderer; percentage rows
show matching per-state values to the left of each glyph. The macOS 26 rows use
Control Center battery parts from the running system, with exact percentage
fill, an idle-AC plug, and a charging bolt instead of generic SF Symbols. In
Low Power Mode, only the battery fill is yellow; the outline, cap, plug, and
bolt keep the menu-bar foreground colour. General contains only Launch at Login
and Hide System Battery Icon. The Settings
window remains fixed at 720×520. This release superseded the v3.0.11 test
package. The v3.0.13 candidate corrects the native-icon fidelity issue found
after v3.0.12 was published.

## v3.0.11 complete menu-bar appearance presets

The v3.0.11 candidate first exposed all four complete appearances directly but
placed the four options together in one horizontal row and showed only one
renderer state per option. General was reduced to Launch at Login and Hide
System Battery Icon, and the Settings window remained fixed at 720×520. The
v3.0.12 release superseded this test package.

## v3.0.10 Settings and website work

The v3.0.10 candidate adds a dedicated Menu Bar Icon page with previews from
the real Wattson and System renderers; the percentage control remains in
General. Settings now uses the compact fixed 720×520 window. The compact
grouped website install panel keeps DMG, PKG, and Homebrew together, and the
real AppKit popover hero replaces the recreated web mock. Earlier selector and
rendering work remains recorded below rather than being restated as new.

## v3.0.9 selector and rendering work

The v3.0.9 pass makes the refined 2A airy-glass selector the normal power-mode
control and keeps its capsule at 1× during direct drag. When macOS system
Reduce Motion is enabled, Wattson automatically swaps in the native 2C
segmented control without adding an app setting or saved preference. Both
controls now share one request generation, so a stale async completion from one
cannot overwrite a newer selection from the other. The legacy optical fallback
refreshes refraction only during a real drag. Reusable telemetry drawing inputs
are cached, and redundant layer updates are removed for identical telemetry
samples.

## v3.0.8 dynamic Reduce Motion and transaction work

The v3.0.8 pass makes runtime accessibility changes deterministic. Dynamically
enabling Reduce Motion stops both the native display-link and legacy settle
drivers immediately and snaps the selector to its committed target. When the
setting changes during an active drag, the enlarged capsule returns to 1× size
immediately while the drag itself remains valid. Each animation frame also
applies selector geometry and label opacity in one explicit transaction instead
of two, reducing transaction overhead without asserting a fixed CPU-percentage
improvement. The cached optical AppKit fallback and the v3.0.7 nearly transparent
Liquid Glass appearance remain unchanged.

## v3.0.7 Liquid Glass clarity and synchronization

The v3.0.7 pass makes the macOS 26 power-mode selector nearly transparent by
removing Wattson's duplicate white rim, caustic, and haze overlays from the
native Clear Liquid Glass surface. Click-to-change motion now advances the real
AppKit glass view, selector boundary, and label blend from the same
window-synchronized display callback, preventing the glass and its outline from
moving on different timelines. Reverse clicks, mid-animation re-grabs, failed
mode changes, Reduce Motion, Reduce Transparency, and the macOS 12–25 optical
fallback keep their existing semantics.

## v3.0.6 Settings fidelity and runtime robustness

The v3.0.6 pass rebuilds General and Modules Settings to match the approved
C+E reference with a stable high-contrast dark palette. It preserves the
reference layout on normal displays and proportionally scales the complete
composition when the visible screen is constrained. General Settings can also
switch Wattson's status item between the original mark and a macOS-style
battery glyph without changing Apple's separate system icon. The lifted
power-mode selector now uses glass refraction through native Liquid Glass on
macOS 26 and a cached optical AppKit fallback on macOS 12–25. Launch-at-login
refreshes complete every queued waiter across availability changes and stale
in-flight writes. The helper also caches successfully parsed `pmset -g cap`
results for its lifetime, while retrying failed probes and keeping live
power-mode reads fresh.

## v3.0.5 settings, performance, and compatibility work

The v3.0.5 pass adds the native C+E Settings window for the application's
existing controls without changing the monitoring popover. It centralizes
module visibility and system-backed state, hardens helper framing and queue
fairness, coalesces settings operations, fixes cross-hardware battery capacity,
temperature, signed-current, and power-mode parsing, and reduces hidden-state
rendering and timer work. The release keeps one retained Settings window,
supports keyboard and VoiceOver navigation, and preserves Reduce Motion,
macOS 12, Apple-silicon, and Intel fallbacks.

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
