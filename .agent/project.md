# Wattson project overview

## Product

Wattson is a native AppKit menu-bar app for macOS. It samples battery state
through IOKit, refreshes whole-machine power from two fixed read-only SMC keys
when the helper is available, and displays the result in a live power-flow
popover.

Shared macOS metrics use the system's user-visible values. Battery charge level
and charging status come from one public IOPS description per sample; registry
charge level remains a fallback when IOPS is unavailable. Charging status is
retained separately from runtime estimation so an unavailable time estimate
cannot turn trickle charging into "Full" or "Not Charging". Physical power-flow
topology remains based on measured power, including mixed supply.

Battery Health displays macOS **Maximum Capacity (%)**, read from the official
`system_profiler SPPowerDataType -json` battery health report. A bounded utility
worker caches successful reads for 15 minutes, coalesces refreshes, and retries
failed reads after one minute. A failed refresh clears the health value. Initial
loading and unavailable official values display `—`; raw full-charge/design mAh
ratios never substitute for system health. The separate mAh metrics retain their
battery-controller meaning, explained in tooltips. See the
[system metric authority validation](../design/system-metric-authority/README.md).
The canonical installation is the verified local 4.3.24 candidate from that
record: App/helper/receipt match its PKG and all 16 settings are retained. The
sandboxed production health reader returned the official 84% on this Mac.
Canonical popup visual acceptance remains pending because CUA app access timed
out; this local update does not create a public release.

## Runtime architecture

- `Core/`: sampling, state models, history, settings, and helper client.
- `MenuBar/`: status-item icon, click routing, and application lifecycle.
- `Popover/`: AppKit views, Liquid Glass selector, layers, and animations.
- `Helper/wattson-helper.swift`: root LaunchDaemon with a fixed JSON operation
  whitelist and console-user peer validation.
- `main.swift`: application entry point plus fixed helper health and power probes.
- `Package.swift`: macOS 12 SwiftPM products for the app and helper.

The full PKG installation (also used by Homebrew) installs:

- `/Applications/Wattson.app`
- `/Library/PrivilegedHelperTools/com.leoarrow.wattson.helper`
- `/Library/LaunchDaemons/com.leoarrow.wattson.helper.plist`

The app-only DMG contains the same universal `Wattson.app` and an Applications
shortcut. Dragging the app into `/Applications` installs no helper or package
receipt. Read-only monitoring remains available without the helper, using the
battery data macOS exposes; helper-backed SMC readings and privileged controls
are not implied. Opening the app does not request administrator authorization.
Existing PKG installations must update through PKG so the app, helper, and
receipt stay in sync.

The helper is activated through `/var/run/wattson-helper.sock` and exits after
12 idle seconds. It exposes fixed read-only whole-machine power sensors plus
fixed operations for power mode, the macOS battery icon, and Wattson's
launch-at-login agent. Clients cannot supply an SMC key or SMC write command.

The unreleased [2026-10-19 performance review](../design/performance-hardening-20261019/README.md)
preserves process keyboard focus by identity across ranking changes, avoids
unchanged action-image refreshes, and bounds the helper's poll wait when an
overdue background sample prevents idle exit. Actual SunBrowser Pro review is
complete and recommends retaining the three minimal changes. Test-only follow-ups
strengthen real window key dispatch and helper lifecycle boundaries. A new SDK
diagnostic also required explicitly declaring the existing strong feedback-worker
capture, preserving its nested weak callback. Frozen `4532daa` passes the opt-in
macOS 27.0.1 / SDK 27 gate: 664 Swift tests, 613 Python tests (four expected GUI
skips), three native variants, 20,000 stress iterations, and the ad-hoc universal
App/helper build. Architecture verification now uses separate `lipo` calls for
both required slices. Physical sensor and installation/login acceptance remain
outstanding; no canonical installation or public release was changed.

Power History retains the original 60-slot, two-minute sample ring and its
sampling cadence. Ordered monotonic timestamps travel with the cached readings
to a fixed 120-second viewport. Shape-preserving cubic segments pass through
the original samples and break across gaps longer than six seconds. It keeps
the sample-aligned viewport during normal cadence; after a sampling gap, the
viewport ages the cached readings with the current monotonic time. Peak uses
the original values; the chart scale adds quantized headroom and waits eight
seconds before a reduction of at least 25%. Contiguous changes use a 180 ms
horizontal translation or a 350 ms eased, baseline-anchored axis transition.
The stroke is rendered in viewport coordinates so its 1.6-point width stays
constant while the fill moves through the changing axis range.
Interrupted transitions continue from the presentation layers. All four cubic
points may blend only after matching their exact sampling intervals and raw
anchors. Stroke and fill share viewport coordinates and cubic construction;
the gradient uses its actual presented start/end band without reciprocal
transform compensation. Bounded departure context keeps left-edge intervals
intact. Axis changes and interrupted motion use nine shared path keyframes;
ordinary translation uses basic animation. The head retains 33 base positions
and adds exact sample-junction times when needed. Queries invert actual cubic X
with bounded Newton/bisection, checking monotonicity before presentation reuse.
CAShapeLayer may interpolate off-line controls nonlinearly: nine frames are a
native-tested error bound, not a universal Cartesian interpolation guarantee.
History joins the existing presentation and accessibility animation policy;
closing, hiding, detaching, degraded readings and Reduce Motion stop animations.
No chart timer is used. The [4.3.16 axis motion review](../design/history-axis-smoothness/README.md)
records the corrected independent native probe, ABBA preparation measurements,
explicit construction counts, Pro review, and exact installation evidence.
Wattson 4.3.22 is now the stable [public GitHub release](https://github.com/laleoarrow/battery-monitor/releases/tag/v4.3.22)
from frozen `7f41533b017d26519a69d541d3ffd2dea587f413`; exact candidate,
Homebrew, Pages and anonymous public-asset checks passed. The
[publication record](../design/release-v4.3.22/publication/final-release-verification.json)
keeps maintainer synchronization separate: the verified public PKG is ready,
but installation is waiting for the Mac to be unlocked.
A preceding verified local preview installation was Wattson 4.3.22. Its
[installation record](../design/process-activity-palette/local-preview-v4.3.22/local-install-verified.json)
verifies matching App/helper/daemon payloads, all 15 retained settings and actual
sampling. Process bars follow the App chart palette; the uniform 38 × 16-point
glass action capsules and pointer glow follow the full-scale bar endpoint.
Process Activity remains enabled with Top 3 and Compact view retained.
Canonical popup interaction was not directly re-observed in this upgrade;
the source passes the six-state production-renderer matrix. The preceding
[4.3.21 installation](../design/process-action-capsule/local-preview-v4.3.21/local-install-verified.json)
records the initial uniform capsule update. The preceding
[4.3.20 installation](../design/process-action-capsule/local-preview-v4.3.20/local-install-verified.json)
records the user-opened popup and initial preview enablement. These records
describe local preview packages; public releases use the separately validated
candidate artifacts.
The preceding 4.3.19
[Process Activity installation record](../design/top-energy-processes/compact-popup/local-installation-v4.3.19.json)
verifies the native PKG, helper, actual process sampling and retained settings.
The [compact selector review](../design/top-energy-processes/compact-popup/README.md)
records the small Off/On popup matching Processes shown.
The preceding 4.3.17
[popup recovery review](../design/installed-popup-recovery/README.md) records the
hidden-launch regression, conditional unhide on explicit opening, native and
canonical click acceptance, and cleanup. It preserves the 4.3.16 History changes
and final 4.3.15 Settings and Power artwork, whose earlier evidence remains in the
[all-icons integration review](../design/popover/all-icons-integration/README.md).
The [4.3.11 performance review](../design/history-performance/README.md) retains
the preceding implementation and its verification limits.
The retained 4.3.14 battery runtime settling fix and its earlier package evidence
are recorded in the [runtime calculation review](../design/battery-runtime-calculating/README.md).
The [General icon integration review](../design/settings/general-icons-integration/README.md)
preserves the preceding 4.3.13 artwork and installation evidence.
The [4.3.10 axis transition review](../design/history-axis-upgrade/README.md)
preserves the earlier native motion, fixed-width stroke and installation evidence. The
[4.3.9 History review](../design/history-upgrade/README.md) preserves the initial
curve upgrade and its verification boundaries.

The system battery-icon control keeps read progress separate from its optional
last-known value. Opening a popup or Settings starts a coalesced helper read;
only a settled failure shows an unavailable status. Refreshing preserves the
last trusted value for write rollback but disables the checkbox until the newest
request settles. Cross-window notifications carry progress as well as the value.
A canceled refresh still settles when a following write fails. The fixed getter
returns allowlisted failure reasons for the console-user worker and the single
Control Center preference; missing or unfamiliar values are never guessed.
Feedback diagnostics include the displayed phase and an independent read result
without changing shared UI state. Its four-second socket deadline starts after
the shared worker becomes available; it is not an end-to-end queue deadline.
Native checkbox actions invert the current authoritative value, rather than
AppKit's intermediate mixed state. A failed readback after a successful write
clears authority and publishes the actual failure. Settings completions render
the current shared state so an older callback cannot restore stale UI state.

`Support/SystemBatteryIcon/` provides a double-click, read-only collector that
also works with the public 4.3.6 helper. `scripts/build_system_battery_support.sh`
packages its source, metadata and checksum under `dist/support`. It observes
only fixed helper getters and the single current-user/current-host Battery
preference, producing a local ZIP for the user to review and attach to an issue.
Collection and packaging share a 45-second monotonic deadline. Each stage owns
a process group before starting its command; signal-safe registration and group
cleanup also cover interrupted launches and descendants. File cleanup has a
separate budget after process termination. The collector does not require Python
or administrator authorization.

## Distribution architecture

`VERSION` is the release-version source. `scripts/release.sh` builds one
universal app/helper pair, packages the full installation as a native PKG and
the same app as an app-only DMG, verifies their app contents match, and emits
SHA-256 checksums plus truthful signing metadata. Older published DMGs contain
the PKG instead; do not describe those historical assets as app-only downloads.

The script and manually dispatched candidate default is `community-ad-hoc`:
app/helper ad-hoc signed, PKG/DMG unsigned, and not notarized. An app-only install
does not remove Gatekeeper trust requirements. Candidate builds run from tested,
frozen `main`; no persistent candidate or recovery branch is required. Community
publication requires explicit review of the successful candidate and publishes
its exact bytes. Developer ID is an explicit candidate option; its separate
manual promotion additionally requires accepted PKG/DMG notarization and
stapled tickets. Both paths retain the hosted-macOS install matrix and public
Homebrew/Pages gates.

## Compatibility

- Deployment target: macOS 12.
- Architectures: arm64 and x86_64.
- High Power mode is exposed only when the hardware reports support.
- macOS 26 and later use native Liquid Glass; macOS 12–25 use the AppKit fallback.

General > Appearance provides an opt-in **Liquid Glass** presentation on
macOS 26 and later. Classic remains the default. Its material choice is
independent of **Theme**: System, Light, or Dark. The saved theme applies
immediately to Settings and both popover hosts; System removes each window's
appearance override so later macOS appearance changes propagate normally.
Classic Settings has a light palette alongside its existing dark palette.
Theme changes retain windows, controls, focus, scroll position and readings,
and never refresh or mutate privileged controls. The menu-bar icon continues
to follow the system menu bar. Accessibility preferences remain authoritative.
This preference does not change macOS appearance or modify signed bundle icons.

General > Appearance also provides **Transparency** (0–100%) when Liquid Glass
is enabled. 0% supplies a solid background; 100% retains the selected native
material and is the unchanged default. Intermediate values adjust background
fills in the popup and Settings content; text and controls stay fully opaque.
The value persists across themes, material choices, and turning glass off.
Reduce Transparency and Increase Contrast override the fill and disable the
slider while preserving its saved value. A separate typed notification redraws
backgrounds without rebuilding hosts, moving focus, or querying the helper.
Settings uses its existing AppKit fill surfaces so native glass batching cannot
lift the fill above controls. The popup retains one native material over a
non-interactive backing view.

The popup's foreground viewport is a sibling above its hosted SwiftUI
`glassEffect`, whose continuous shape includes the menu-bar arrow. A transparent
rounded container clips scrolling and animated content to the body, without
changing the shared content root when it returns to Classic.
`NSGlassEffectView` only supplies a rounded rectangle, so the small hosting
bridge owns the background shape while AppKit keeps the content and lifetime.
The transparency backing uses the same outline and retains one 8-bit alpha
step at maximum transparency so WindowServer includes the glass in mouse hit
testing; SwiftUI glass alone lets blank pixels click through. The optical
margin stays fully transparent. General > Appearance > Show Popover Arrow is
an independent, default-on Liquid Glass preference. Disabling it removes the
12-point arrow from the material, backing mask and placement allowance, moving
the body upward and returning space to short-screen viewports. An open panel
updates in place, retaining its content, focus and event handlers. Classic keeps
its native arrow and disables this control while retaining the preference.
Keep the backdrop and backing
frames aligned when resizing; the foreground excludes the 12-point arrow.
Nesting the footer inside the backdrop flattens its interactive material into
solid fills. The footer uses Clear in Dark appearance
and Regular in Light so its selection stays visible on white backgrounds.

`FooterHoverFeedbackView` adds neutral pointer feedback only over the footer's
visible mode controls and settings button. Its transparent, non-hit-testing
overlay follows the SwiftUI glass, native glass and Classic control geometry;
it does not change their materials, actions, focus or accessibility nodes.
Disabled modes, gaps and rounded outside corners do not glow. Hover follows
the existing presentation lifecycle, including Classic's non-key first open.
Soft surface and rim reflections follow the current pointer within each
capsule, including the selected glass control. Reduce Motion, Reduce
Transparency and Increase Contrast use static feedback. Dismissal, hiding,
losing key status, changing appearance or detaching clears feedback and its
animations immediately. The settings-window buttons and system-battery
checkbox retain their existing presentation.

Global mouse-down delivery can repeat a press already routed to the Classic
popup. Dismissal ignores the current content window's identity, or its positive
window number when the event omits the object. A different window at the same
screen coordinates still dismisses the popup; its rectangle is not an exemption.

An independently selectable section prioritizes macOS battery time estimates,
following Stats' system-data approach. On battery it uses the public IOPS
internal-battery `Time to Empty` field; while charging it uses `Time to Full
Charge`. Both are minutes. One IOPS description supplies the estimate and its
charging state; `Is Charged` distinguishes completion from external power without
charging. Mixed supply suppresses a charge countdown. Both startup sampling and
the normal observation reader enrich their visible snapshots; the pure registry
parser remains deterministic. Direction mismatches and failed readings clear the
previous estimate. When IOPS has no number, a reader-owned fallback first uses
the matching battery-controller `AvgTimeToEmpty` or `AvgTimeToFull` in minutes,
rejecting the SBS unknown sentinel 65535. Fallback waits for 60 seconds of
continuous, direction-consistent sampling after startup, a direction change,
wake or a sampling gap. This is Wattson's stabilization policy, not an Apple
promise about when IOPS will return a number. If the controller also has no time,
discharge runtime can use remaining raw mAh divided by a time-smoothed discharge
current; its display carries an approximation sign. Percentage capacities are
never used as mAh. Charging has no invented linear/taper formula. If inputs are
still insufficient after the settling period, the section shows Unavailable and
continues checking for recovery. Diagnostics record the estimate's source. No
extra timer is used, and unrelated telemetry resets do not clear this history.
See [battery time estimation](../docs/battery-time-estimate.md) for the formula,
stabilization policy and pinned source references.
The runtime section is an independent 88-point module below Power History
and above the footer controls. It shares the transparent content surface and inset
hairline separators of the existing instruments. A neutral clock well sits on
the left, with a quiet title and prominent time both right-aligned. Well, border and
icon colors resolve against the view's current appearance, including high contrast. Non-numeric
states use smaller secondary text. Disabling it removes its entire height. The rounded
glass backing owns the solid accessibility fallback; the
foreground stays transparent in an actual glass host and refreshes on reparenting.
See the [selected runtime layout review](../design/feedback-runtime/runtime-layout/README.md)
for theme and layout evidence, and the [4.3.2 release gallery](../design/releases/v4.3.2/README.md)
for the installed Standard Glass composited capture.

Process Activity is an independent, default-on module appended to existing
module orders. Settings > Modules selects 1–10 processes (default 3), and the
six-row module list scrolls without replacing its reorder controls. It uses a
fixed helper read for two native process-counter snapshots; the displayed
theme-colored gradient bars show Wattson's independently calculated Activity Score on a
fixed 0–100 scale, alongside CPU percent and idle wakeups per second. Each full
track runs horizontally from pale to deep within the same hue; the score reveals only the
matching prefix. The optional Compact view hides the CPU/wakeup line and uses
28-point rows instead of 44-point rows, preserving readings and the fixed scale.
Bars follow the Power History/Lanes palette: green while charging, blue while
plugged idle or on mixed supply, and neutral on battery. Palette changes update
independently of process data; existing appearance refresh resolves the adaptive
colors again for light/dark and high contrast without adding observers or timers.
An
information control explains Activity Score and the one-core CPU convention; these
are never per-process watts or battery shares. Sampling shares the popup clock,
runs only while open and enabled, and
waits ten seconds after completion before refreshing. A successful in-memory
sample can be reused when reopening within that deadline; wake and force-quit
intent clear it. Closed/disabled generations discard pending results. See [process energy ranking](../docs/top-energy-processes.md)
for the formula, helper requirement and attribution limits.

Selecting a Process Activity row replaces its right-hand score with a small
38 × 16-point glass × capsule with the same fixed width in both display modes,
without moving the name or bar. The capsule gradient, native glass tint and
pointer glow use the full-scale bar's deepest endpoint color and follow the
App palette and appearance; unavailable actions remain neutral.
A shared pointer reflection follows the existing footer's lifecycle and
accessibility policy. Row tooltips use two short lines with rounded values;
the full metric explanation stays behind the information control. The popup
closes before a native force-quit confirmation with no default
action; Escape cancels and Return does not signal a process.
The target retains its complete kernel identity across ranking changes. Only
the authenticated console user's processes with supported identity access are
eligible; a permanently unprivileged helper worker validates and sends the fixed
identity-bound signal. Older helpers or systems keep readable rows with the
action disabled. See the same document for the operation's exact boundaries.

General includes a Send Feedback group below Appearance. Report saves a
reviewable text attachment and opens an official GitHub Issue draft. Collection
runs off the UI thread and includes app/system/build/model/architecture,
preferences, accessibility, bounded helper health, displayed-reading freshness
and allowlisted raw battery inputs. Serial numbers, account/host names, personal
paths and logs are excluded. The user attaches and submits the report on GitHub.
The General scroll viewport extends through the existing 20-point detail margins
so native group shadows are not cut into an interior rectangle. Matching document
insets retain group and control positions; feedback keyboard focus reveals the
expanded optical bounds. The scroll background is explicitly clear. Verify
geometry after AppKit has settled its overlay/legacy scroller layout.

Settings now delegates its glass sidebar to `NSSplitViewController` and a native
sidebar item. The native detail safe area positions the retained content;
appearance changes reparent the existing controls and preserve keyboard focus.
Glass Settings uses an `NSToolbar` with `.unified` window style. AppKit owns the
traffic-light positions and window/sidebar corner relationship. A tracking
separator aligns the unbordered page title with the detail pane; page titles
are inline only in Classic. Sidebar identity and detail content respect the
toolbar safe area. Group fills share the glass surface's radius. See the
[native window chrome review](../design/settings/native-window-chrome/README.md).
The native sidebar has no custom backing fill. The behind-window detail
material fills the entire detail view, including the area beneath the floating
sidebar. The window backing is clear so no separate dark strip appears around
the sidebar's rounded edges. See the
[continuous backdrop correction](../design/settings/continuous-backdrop/README.md).
Functional Settings groups use NSGlassEffectView; General's shared container
batches its Startup & Menu Bar, Updates, Appearance and Support groups inside the scroll document, not around the toolbar
or system sidebar. Single-group pages need no additional container. Liquid Glass
belongs to General > Appearance, and only joins that page's keyboard loop.
Display separates icon style and percentage with three native radio rows:
Wattson, macOS 26 and macOS 27. They share seven state headings and the production
renderer at natural size. A small Off/On popup controls the percentage; macOS 27
embeds its digits inside the glyph while the older choices retain external text.
The controls and settings remain in place when selection changes. Display uses
system radio/focus drawing and the shared Glass groups retain the system's
default corner radius. See the
[system controls review](../design/settings/display-system-defaults/README.md).
Frozen `03ca506` adds the final accessibility-label and preview-spacing
follow-ups. Settings uses one fixed 800 × 520-point window across its pages;
the seven preview cells are about 70.5 points wide. The top two styles retain
their original fonts and natural glyphs, with at least 14 points between the
preceding glyph and the next percentage's text ink. Complete CI passes on macOS
26.6.2 / SDK 26.5 and actual macOS 27.0.1 / SDK 27: 700 Swift and 626 Python tests
per platform (four expected opt-in GUI skips). The 27 gate also passes 34 real
800 × 520 frames, eight native Settings tests, three interaction variants,
20,000 animation iterations and the universal App/helper build. Details are in the
[integration record](../design/settings/display-system-defaults/integration-verification.json).
This Display work performs no additional installation or public release. The
recorded local 4.3.24 installation contains the three visual styles, but precedes
the final accessibility-label and spacing follow-ups.
General scrolls as needed for the added logo choice or expanded recovery help;
keyboard focus brings the logo selector into view. Modules use monochrome SF Symbols, 12-point descriptions, inset
separators and right-aligned switches. See the
[appearance hierarchy review](../design/settings/appearance-hierarchy/README.md)
for actual test-VM window images and verification. This source refinement does
not replace the canonical installed app or constitute a new release.

General's functional groups share external 13-point headings.
General and Modules use 20-point vector artwork in 28-point alignment frames without
decorative icon tiles. Appearance aligns Theme, Liquid Glass, In-App Logo and
Dock Icon as peers; only glass background and transparency are indented.
Recovery follows the startup controls in both the visual and keyboard order.
See the [native settings hierarchy review](../design/settings/native-hierarchy/README.md)
for Apple references, Pro review, production-renderer captures and validation.

Settings navigation uses unframed vector sliders, a window and a four-tile grid
from `design/settings/sidebar-icons-vector`, matching the approved module icon
family. Neutral contours and blue details render at 18 points in the existing
24-point frames, beside regular 13-point labels. Native emphasized selection
uses white artwork; deselection restores neutral-and-blue colors. Appearance
and Increase Contrast updates regenerate the static images. Glass retains
native source-list selection; Classic uses a
subtle neutral fill with a semantic outline for Increase Contrast. The
124-point navigation viewport accommodates three 32-point rows and AppKit's
source-list spacing. The identity artwork is 32 points. Settings uses 13-point
primary labels, 12-point group titles, 11-point descriptions, an 18-point
Classic page heading and a 15-point native toolbar title. See the
[quiet navigation and typography review](../design/settings/quiet-navigation/README.md).

General's login, system battery, update, automatic update and feedback icons
share this family through editable masters in `design/settings/general-icons-vector`.
They use static blue action marks with faint local areas or arc fades, while
retaining the existing controls and layout. Increase Contrast removes decorative
fills and fades without removing the functional contours or action marks.

Runtime power motifs in `design/popover/power-icons-vector` use the same vector
language with neutral contours and state-dependent accent regions, resolved
through `PopoverStyle` in each view's appearance. `PowerIconImageView` shares
the Adapter/System/Battery artwork across Flow and Lanes and retains only its
last resolved image. Mixed supply keeps adapter/system blue and battery amber.
Both battery placements share the existing capacity bands and charging bolt.
The port/cable fallbacks, node and lane geometry, values and motion are retained.

Modules retains its five rows and switches, with a separate trailing drag handle.
Only a successful local drop saves `popover.moduleOrder`; canceled previews leave
preferences untouched. Up/Down keys and accessibility move actions use the same
order. Hidden modules retain their positions. The Settings list, popover sections
and quick menu share that order, while the header and footer stay at the ends.
The Modules subtitle row includes `Restore Default Order`, which resets only
the order and preserves module visibility. The always-enabled native action is
last in the page's keyboard loop; restoring an already-default order is a no-op.
See the [default-order and sidebar review](../design/settings/default-order-sidebar/README.md)
for the 4.3.12 candidate's focused validation and real-window captures.
Reordering moves existing arranged views without detaching History, changing its
samples, or refreshing telemetry. Reduce Motion removes row movement and drag
return animation. All five module icons follow the approved neutral-and-blue
vector reference. Editable SVG masters in `design/settings/module-icons-vector`
generate the static AppKit paths in `MenuBar/ModuleIconArtwork.swift`. Non-template
images regenerate on appearance and contrast changes. Icon slots and row
geometry remain unchanged; the artwork preview is an offscreen render.
In `e627969`, the fourth icon (Power History) extends its area gradient to the
horizontal axis end; the line, nodes and control geometry are unchanged. Two
new Standard light/dark own-window captures record this fill-only revision.
This approved icon family also guides future Wattson in-app icons and logo
additions: use precise rounded neutral contours with system-blue accents and
restrained local gradient regions. Keep small-size silhouettes legible, align
decorative arc endpoints with their pointer, and adapt neutral ink and contrast
to the system appearance. Keep editable vector masters and derive production
artwork from them. Do not introduce unrelated icon styles or change the app's
existing identity as part of adding a module icon.
Native Settings captures and verification notes are in
`design/settings/modules-reordering/README.md`. Pointer-driven keyboard/mouse focus switching is verified: only keyboard
interaction retains a focus outline. Integrated source `402991a` passes eight
Settings contracts and 12 Modules tests, and 12 own-window icon captures were
reviewed. Several real native drop/cancel cases passed, but rapid Classic/Standard
drops left a live session and half-opacity row in the instrumented VM. Those
failures and the original observation records remain preserved; successful
retries do not supersede them.
Candidate `e627969` includes `b5fcedd`: left-button state is checked before and
after preparing the row snapshot, before registering any drag state. The eight
Settings contracts pass in the VM, including all five DEBUG preflight cases,
500 reuse cycles and 500 constructed-window lifecycle checks (141.524 seconds
of runtime; 149.185 seconds for the test suite). These preflight cases stop at
the native-session boundary and do not prove an actual pointer drag. The initial
CUA `noWindowsAvailable` condition recovered. Four subsequent real-input cases
verified rejection of a released left-button gesture before a native session,
with unchanged order, zero preference writes and cleared state; none counts as
a successful native drop or cancellation. `standard-fast-1` missed the handle
and remains unverified. `standard-held-drop` received no input before the
600-second fixture deadline (exit 124); the window had automatically closed
before the user could try it. At that stage, normal held-button dragging remained
unverified on that source. No new live-session hang was observed in the four
rejected cases. The separately coordinated, user-authorized local candidate
installation is not a public release or a claim of complete drag acceptance.

The 2026-10-17 [normal slow-drag follow-up](../design/settings/modules-reordering/normal-slow-drag-4.3.12/README.md)
closes that narrow interaction gap on frozen `5d5c896` / 4.3.12: Classic,
Standard and Clear each pass a genuine held native drop and outside cancellation
in the disposable ARM VM. Drops save once; cancellation saves nothing; identities,
visibility and final row opacity remain correct. The Modules implementation is
source-equivalent to installed 4.3.13. Earlier failed/unverified observations remain
preserved. This is guest VNC input with AppKit callbacks, without host input or an
FPS/human-mouse claim.

The main popover footer now replaces the UI4 ordinary segmented
control inside a glass surface with three mutually exclusive native `.glass`
NSButtons and a separate round settings button, sharing one
NSGlassEffectContainerView with spacing 0. UI6's real-window comparison selected
the pure AppKit pattern: labels fit without a SwiftUI bridge, ordinary gray
segmented well, or extra outer glass surface. UI7 passes 829 real GUI assertion
executions in five modes and a 20,000-iteration stress test. Eight versioned
real-window screenshots show the final footer. Classic geometry and Dark Aqua
remain in scope; power flow, ring, lanes and history remain content without
additional glass cards. Earlier UI4 real composited review covers six dark
power fixtures, battery/mixed USB output, one Light-host/Classic comparison
and all three Settings pages; those earlier images are not final-footer evidence.
This is not a full appearance cross-product or manual VoiceOver review. See
[Liquid Glass review](liquid-glass.md) for outstanding acceptance work.

The installed primary icon is separate from this runtime preference. The
4.2.0 source additionally offers an independent **In-App Logo** choice in
General > Appearance. Color/Clear static Icon Composer renditions update the
Settings identity only; Clear follows that window's Light/Dark appearance.
This preference never mutates Finder/Dock icons, menu-bar symbols, or bundle
metadata. The native source and its Mono appearance remain preserved.
An independent **Dock Icon** choice now offers Hidden (the unchanged default),
Color, and Clear. Saving affects only the next process launch. On that launch,
AppDelegate selects a bundled 512px static image with the public
`applicationIconImage` API and opts into regular activation only for a visible
choice; Hidden retains the packaged accessory policy. Clear uses the startup
Light/Dark appearance. The menu-bar item remains, and Dock reopen routes through
the same guarded Settings presenter as Command-Comma. This does not modify
Finder icons, signed bundle contents, helper privileges, or the independent
in-app logo. It is not a native dynamic Clear-icon override or two-installer
variant scheme.
The classic ICNS remains unchanged; `design/icon/liquid-glass/` contains the source
layers for the native `design/icon/WattsonGlass.icon` document. Release builds
compile it with actool and include its layered catalog and a settings preview
before signing. The primary-icon plist selection is separate from the runtime
option; never mutate a signed app bundle to implement a theme switch.
The 4.1.0 primary system icon is `WattsonGlass`, using the compiled layered
catalog and its generated static ICNS fallback; both plist icon keys are
required by release verification. The classic icon remains a preserved resource
and Settings comparison. The runtime appearance switch does not mutate the
signed Finder/Dock icon. A Mono-only white energy fill improves silhouette
separation without changing Default/Dark exports. Small monochrome particles
remain tonal decoration, not guaranteed individually legible at 32 px.
The formerly open Edited Composer document had a different layer order and
background. Its separate saved copy remains preserved under
`dist/liquid-glass-option-20260913/icon-refinement/WattsonGlass-Edited-Preserved.icon`;
the stale editor window is now closed. The canonical three-layer source was
restored and hash-verified after Composer reverted the old document on close.

Successful CI run `34710861967` covers commit `41826300c3f2`, not the
pending native-button and icon revision. New source requires fresh tests and exact-commit CI,
followed by the 4.1.0 packaging and release gates in [release.md](release.md).
These development decisions do not announce or validate a 4.1.0 release.

`BatteryPowerWidgetExtension.swift` and the legacy Python implementation remain
reference/test surfaces; the currently shipped app bundle is the AppKit
menu-bar product.
