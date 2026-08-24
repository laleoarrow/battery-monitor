# Design QA — website and compact Settings

## Source and implementation

- Selected visual target: `/Users/leoarrow/.codex/generated_images/019fef52-5670-7671-bf0b-a280dc3aa9be/exec-ce5b37e5-78bc-4c26-a768-1b03e832ad84.png`
- Target raster: 1511 × 1041 px.
- Desktop implementation capture: `/tmp/wattson-install-option1-implementation.png`
- Desktop viewport/capture: 1280 × 720 CSS px at 1× screenshot density.
- Mobile implementation capture: `/tmp/wattson-install-option1-mobile.png`
- Mobile viewport: 390 × 844 CSS px at 1× screenshot density.
- Combined comparison: `/tmp/wattson-install-option1-comparison.png`

## Comparison

The implementation preserves the selected direction: one grouped installation surface, three horizontal routes with a single recommended treatment, compact actions, a separate trust disclosure, and a restrained dark macOS-oriented palette. The panel is intentionally narrower and denser than the source mock because the reported defect was excessive element and section scale.

The generated mock's illustrative glyphs were replaced with Lucide library icons rather than text or handcrafted approximations. Typography, borders, radii, semantic green/blue/orange accents, release status, command copy action, and disclosure hierarchy remain consistent with the target.

At 1280 px the install section is 768.5 px tall and the grouped panel is 760 × 311.6 px. At 390 px it has no horizontal overflow (`scrollWidth == clientWidth == 390`); each route reflows to a readable stacked action while preserving the grouping and hierarchy.

## QA history

1. Initial implementation matched the row structure but used `DMG`, `PKG`, and terminal text as glyphs. This was visibly less faithful and was replaced with real icon-library assets.
2. Desktop and mobile captures were rechecked after icon integration. No clipped text, broken spacing, incorrect radii, horizontal overflow, or console warnings remain.
3. The Homebrew control transitions to `Copied` after activation, and the rendered/static-site contracts cover all three routes and the real-app hero image.

## Real AppKit hero replacement

- Reported fake-UI baseline: `/Users/leoarrow/.codex/attachments/3627013a-68b6-414f-ad08-c23865ec719e/image-1.png`.
- Current 1280×720 browser capture: `/tmp/wattson-current-hero.png`.
- Side-by-side comparison: `/tmp/wattson-hero-before-after.png`.
- Shipping source capture: `website/public/wattson-popover-real.png`
  (864×1530 pixels at 2×, representing 432×765 points).

The old web-drawn monitor has been removed. Browser inspection of the final
hero found zero `.app-window`, `.power-map`, or `.history-bars` mock nodes. The
only product image is the screenshot generated from the current AppKit source,
and its visible caption identifies it as a current Wattson AppKit capture.

## Compact Settings window

### Source and implementation

- Oversized General baseline: `/tmp/wattson-settings-general-native-icon-final.png` (792 × 794 content points at Retina density).
- Oversized Modules baseline: `/tmp/wattson-settings-modules-feat2.png` (792 × 794 content points at Retina density).
- Compact General capture: `/tmp/wattson-settings-final.40kryD/settings-general.png`.
- Compact Modules capture: `/tmp/wattson-settings-final.40kryD/settings-modules.png`.
- Final compositor captures: 1576 × 1176 pixels including the native window shadow; content is 720 × 520 points at Retina density.
- General comparison: `/tmp/wattson-settings-general-before-after-preview.png`.
- Modules comparison: `/tmp/wattson-settings-modules-before-after-preview.png`.

### Comparison

The same dark visual language, information hierarchy, system state, and accessibility semantics are preserved. The layout is a true compact reflow rather than a scaled image: 176-point sidebar, 22/14/11-point typography, 38-point navigation rows, four 68-point General rows, a dedicated four-preset Menu Bar Icon page, and 233 × 166-point module cards with 12-point gaps. Native AppKit traffic-light controls replace the oversized painted proxies.

The final result removes the large unused General canvas and reduces overall content area by about 35% while retaining readable labels and standard macOS control density. The Modules page keeps both rows in bounds without clipping or crowding.

### QA history

1. The first compact capture exposed a Modules navigation glyph that crowded its label. The custom oversized glyph path was removed and the screen was recaptured.
2. A stale second-page snapshot was fixed by giving AppKit a full layout/display turn before capture.
3. Icon style and percentage are now combined into four complete presets on the dedicated Menu Bar Icon page. General retains Launch at Login and Hide System Battery Icon and now also exposes the two update controls.
4. Real AppKit minimize, keyboard navigation, AX/key-loop behavior, retained-window reuse, 1,000 lifecycle iterations, weak release, and FD/RSS bounds passed.
5. The fixed-size window keeps all three native traffic lights while correctly disabling the zoom control instead of advertising a resize action that cannot change the layout.

## Dedicated Menu Bar Icon settings

### Source and implementation

- User-reported incomplete-state capture: `/var/folders/jc/p8qsvpfd6t71pngj51n4yvvh0000gn/T/codex-clipboard-7b0490dd-18e1-40aa-a911-7ca2473723fe.png`.
- Superseded four-card implementation: `/tmp/wattson-settings-menu-bar-icon-four-presets.png`.
- Superseded small-resource implementation: `/tmp/wattson-settings-native-system-assets-vm.png`.
- Corrected full-size implementation: `/tmp/wattson-settings-macos26-full-size-assets-vm.png` (1440 × 1040 pixels from the shipping AppKit hierarchy).
- Final packaged-app identity implementation: `/tmp/wattson-settings-png-app-icon.png` (1440 × 1040 pixels from the shipping AppKit hierarchy, with the packaged app icon resource loaded at 40 points).
- Capture environment: the generic `macOS-TestLab` ARM VM on macOS 26.6.1, rendered at Retina 2× density from the fixed 720 × 520-point window.
- Capture method: the retained Settings window stayed hidden and non-key; `cacheDisplay` rendered the real hierarchy without touching the maintainer desktop.
- State: dark appearance with the default complete preset, Wattson with percentage, selected.

### Comparison

The final page preserves the compact shell, heading, subtitle, dark palette,
radii, and green radio-row selection language. The four complete appearances
are now listed vertically, one full-width option per row: Wattson icon only,
Wattson with percentage, macOS 26 icon only, and macOS 26 with percentage. Each row
contains seven visibly named production states: Battery, Full, Charging, Low,
Low + AC, Saver, and Saver + AC.

All 28 glyphs come directly from
`BatteryIcon.image(for:mode:pressed:style:)`. The two percentage rows show the
matching values `75%`, `100%`, `72%`, `10%`, `20%`, `42%`, and `42%` to the
left of their corresponding glyphs using the menu-bar font with tabular
digits. The Wattson rows visibly cover normal, red low-battery, green charging,
yellow Low Power, and plugged-bolt combinations. The macOS 26 rows use the
exact percentage fill and the system bolt for every connected state. Low Power
colours only the interior fill yellow while the outline, cap, and bolt remain
in the menu-bar foreground colour; the native glyph does not inherit Wattson's
whole-glyph tint semantics.

The macOS choices compose the running system's full-size Control Center outline,
cap, bolt, and knockout-mask resources at their native proportions; no Apple
artwork is copied into the app. A resolution-independent vector fallback keeps
older supported systems usable if a system asset is unavailable. The concise
visible copy fits at the compact width, while each AX radio exposes the complete
preset name and a truthful description. General has four 68-point rows,
including the two update controls without restoring the duplicate percentage
control.

### Required fidelity surfaces

- Fonts and typography: the 22-point heading and 11-point subtitle keep the established hierarchy. Row titles use 13-point semibold system type, details use 11-point system type, state labels use compact 9-point medium type, and percentage previews use an 11-point menu-bar font with tabular digits and verified safe chip insets.
- Spacing and layout rhythm: the 176-point sidebar and 503-point content width remain unchanged. Each option row is 503 × 80 points; four rows use eight-point gaps. Each row contains seven approximately 64 × 38-point state chips separated by five-point gaps.
- Colors and visual tokens: content, sidebar, state tiles, unselected borders, semantic green selection fill, and high-contrast variants reuse the existing Settings tokens. High Contrast strengthens borders without changing geometry.
- Image quality and asset fidelity: all 28 glyphs are production `NSImage` outputs. Wattson retains its 23 × 14-point canvas; the macOS 26 choices retain the system composition's 25 × 14-point canvas with a 23 × 12 outline and 11 × 14 bolt. No emoji, text-symbol substitute, handcrafted SVG, screenshot, or enlarged approximation is used.
- Copy and content: all four appearances and all seven states are explicitly visible in every row. The percentage rows use every fixture's actual value rather than one repeated example.
- Interaction and accessibility: the whole 503 × 80-point row remains one radio button and one hit target. State chips are non-interactive and do not add 28 Tab or VoiceOver stops. Up/Down and Left/Right navigate rows; Home, End, Space, AX press, focus redraw, notification syncing, and atomic two-key persistence remain covered.

### QA history

1. [P1] The first implementation exposed only Wattson and System style cards. The next pass exposed all four appearances but compressed them into one horizontal row and showed only one renderer state per appearance. Fix: retained the four-value product order but converted it to four full-width rows, each containing all seven meaningful production-rendered states.
2. [P1] A global count alone could have allowed the 28 previews to collect in the wrong row. Fix: the executable contract now requires exactly seven chips, seven visible labels, and seven renderer images inside every individual option row, in production order.
3. [P1] General duplicated percentage as a separate switch after complete appearances moved to their own page. Fix: removed that row and its observer/action. The current list is 272 points with four 68-point rows after adding the two update controls.
4. [P2] The first four-row capture showed the radio circles underneath the final state chip. Fix: made the radio Y position respect the button's flipped coordinate system and recaptured. The final image visibly shows all four circles and the selected inner dot.
5. Percentage-to-glyph pairing is asserted by matching complete identifiers, a shared direct parent, and left-to-right frame order for all 14 percentages. No percentage overlaps its glyph.
6. The host Swift suite, hidden AppKit contract, and the real visible AppKit interaction/lifecycle contract passed. The latter ran inside the ARM VM so the maintainer desktop was never activated or disturbed.
7. [P1] The first macOS rows used generic `battery.*percent` SF Symbols. Those are not the Battery menu extra's artwork and also omitted the idle-AC plug. Fix: compose the current OS's small Control Center battery assets, preserve exact percentage fill, use the plug for connected-idle states, and reserve the bolt for actual charging. The corrected hierarchy and 500-cycle lifecycle contract passed again in the ARM VM.
8. [P1] The first Low Power preview left the entire native icon neutral. Fix: match macOS 26 by colouring only the battery's interior fill yellow while keeping the outline, cap, plug, and bolt in the menu-bar foreground colour.
9. [P1] Direct comparison with the live macOS 26 battery icon showed that the previous native choice still used the 19 × 10 small Control Center outline, a plug for connected-idle states, and a translucent full fill. Fix: load the full-size 23 × 12 outline and 11 × 14 bolt from the running Control Center bundle, use the bolt for every connected state, make normal fill opaque, and preserve the resulting 25 × 14 canvas in Settings previews.
10. [P1] Replacing the sidebar ECG drawing with `AppIcon.icns` directly produced a dark, detail-free square at 40 points in the offscreen AppKit capture. Fix: packaging derives `AppIconSettings.png` from the exact same ICNS source, and the sidebar loads that representation without adding a second authored brand asset. The ARM VM capture shows the blue-green Wattson mark clearly at the original 40-point footprint.

## Restored power-flow node artwork

- User references: the earlier green diagonal adapter plug and the earlier
  green bracketed charging battery with a central lightning mark.
- Final production capture:
  `/tmp/wattson-power-icons-restored-charging-final.png` (656 × 404 pixels,
  rendered from the real `PowerFlowView` hierarchy).
- Capture method: hidden `cacheDisplay`; no window was ordered front and the
  maintainer desktop was not activated.
- Both restored glyphs use 24-point Medium artwork inside the existing
  36-point wells. Adapter, battery, and system positions, pipe geometry,
  animation timing, labels, and hit areas are unchanged.
- The charging glyph is used only for active charging. Idle/full, discharging,
  and mixed-supply states retain the production battery levels and their
  established blue, green, neutral, and amber state colours.
- Swift (81 tests), Python (407 tests), the release build, and the hidden AppKit
  capture all passed after the final rendering change.

## Refined A1 power-flow node icon family

- Selected direction: A1, adjusted slightly smaller and thinner after the
  user rejected the initial A treatment as too heavy and oversized.
- Adapter, System, and Battery use a shared 21-point Regular treatment inside
  the existing 36-point wells. The custom chip, charging battery, and
  disconnected-plug slash use 1.6-point outlines.
- The alpha-bounds contract targets 19.25–21.5-point real visible extents. The
  production renderer measures 20–21.25 points across the plug, disconnected
  plug, System chip, static battery levels, and bracketed charging battery.
- The A1 silhouette language remains intact: a clear diagonal adapter plug, a
  simplified matching System chip, and a bracketed charging battery with a
  central lightning mark. No node position, flow path, animation, label, or
  hit-area geometry changed.
- Semantic colour remains intentional: System is neutral, active sources use
  the state colour, and mixed supply keeps Adapter blue and Battery amber.
- Final production captures:
  `/tmp/wattson-v317-flow.LvNkns/{charging,idle,battery,mixed,website}.png`
  (656 × 404 pixels each). The same production sources rendered byte-identical
  PNGs in the macOS 26 ARM test VM, and all three AppKit interaction modes plus
  the 20,000-iteration animation stress test passed there.

## v3.0.16 unified power-flow node icon family (historical)

- User reference: the Adapter, System, and Battery wells looked like three
  unrelated icon families because their visible extents were approximately
  17, 14.5, and 28 points despite sharing the same 36-point container.
- Final four-state production captures:
  `/tmp/wattson-node-icons-unified.ElX4Uo/charging.png`, `idle.png`,
  `battery.png`, and `mixed.png` (656 × 404 pixels each).
- Adapter retains the approved diagonal plug and charging Battery retains the
  approved bracket-and-lightning silhouette. System now uses a simplified
  rounded chip drawn with the same 2.2-point line treatment. Static battery
  levels and the adapter are optically normalised instead of merely sharing an
  `NSImageView` frame.
- A real AppKit alpha-bounds test covers the plug, disconnected plug, System,
  all four static battery levels, and the charging battery. Every glyph is
  centred on a 32-point canvas, has a 20.5–24.5-point maximum visible extent,
  keeps at least a 2-point margin, and the largest-to-smallest extent ratio is
  at most 1.18.
- Semantic colour remains intentional: System is neutral, active sources use
  the state colour, and mixed supply keeps Adapter blue and Battery amber.
- `website/public/wattson-popover-real.png` was refreshed from the same
  production `PowerFlowView` hierarchy so the public screenshot no longer
  shows the obsolete horizontal plug.

## Update settings

- Candidate capture: `/tmp/wattson-settings-v3.0.14-general.png` (1440 ×
  1040 pixels from the real 720 × 520-point AppKit hierarchy).
- General contains four equal 68-point rows: Launch at Login, Hide System
  Battery Icon, Check for Updates, and Check for Updates on Launch.
- The manual action uses a compact native 88 × 28-point button. Its
  checking, current, failed, available, and View Update states remain inside
  the same row without resizing the window.
- The automatic preference uses the existing compact switch style, defaults
  on, and remains reachable in the keyboard loop after the manual action.
- The AppKit runtime contract verified every state transition, persistence,
  full-row hit testing, focus order, accessibility copy, and the trusted update
  link. The full Swift and Python suites passed after the visual capture.

### Follow-up polish

No P3 item is required for this correction.

## v3.0.22 inline Device Output icon

### Source and implementation

- Selected visual truth: `/Users/leoarrow/.codex/generated_images/01a01de2-549c-7111-8c6d-56eb04196ce7/exec-11bac02a-59e7-48be-8fe0-9c997944981c.png`.
- Source raster: 908 × 1732 pixels. The relevant flow region was normalized to
  656 × 448 pixels for comparison.
- Production AppKit capture: `/tmp/wattson-inline-icon-qa/idle-device-horizontal.png`
  (656 × 448 pixels, representing the 328 × 224-point `PowerFlowView`
  at Retina 2× density).
- Full flow comparison: `/tmp/wattson-inline-icon-qa/combined-flow-comparison.png`.
- Focused readout comparison: `/tmp/wattson-inline-icon-qa/combined-row-comparison.png`.
- State: dark appearance, plugged and full, with a positive coherent measured
  Device Output. The source uses 35.5 W / 3.1 W presentation values; the
  production fixture intentionally uses the hardware regression values
  48.7 W / 14.083 W. Geometry and formatting, rather than numeric equality,
  are the comparison target.

### Comparison

The implementation preserves the current Wattson composition exactly: three
power nodes, two cubic pipes, the 176-point plot, the existing 22-point readout
slot, and the 224-point section height. The only new visible element is a
compact connector well immediately to the left of the existing
`Device Output · W` text. The 26 × 26-point continuous-radius well and
16-point SF Symbol follow the same compact token used by the production lanes.
The icon and content-hugging text are centred as one group with an eight-point
gap.

The focused comparison confirms that the connector is a real horizontal SF
Symbol rather than a text glyph or drawn approximation. Its exact silhouette
is intentionally the system `cable.connector.horizontal`, with runtime fallback
to `cable.connector`; the generated mock's port-like outline is not copied as
custom artwork. The well and icon are decorative for accessibility. The
existing text remains the sole static-text element with label `Device Output`
and the formatted wattage as its value.

### Required fidelity surfaces

- Fonts and typography: the existing 11-point regular monospaced readout,
  secondary text colour, baseline, wording, and one-line behavior are unchanged.
- Spacing and layout rhythm: the accessory uses the selected compact treatment;
  the icon/text group is centred, the gap is eight points, and all node, pipe,
  separator, ring, lane, history, and footer positions remain unchanged.
- Colors and visual tokens: the well reuses `PopoverStyle.well`; its hairline
  and icon follow the existing blue, green, or amber power-state tint.
- Image quality and asset fidelity: the icon is a vector SF Symbol rendered by
  AppKit, with a semantic fallback chain. No emoji, text symbol, handcrafted
  SVG, raster placeholder, or new custom asset is used.
- Copy and content: `Device Output · <watts>` is unchanged. Invalid, absent,
  zero, non-finite, or greater-than-System output still hides the complete
  accessory. On-battery mode retains its existing full Device Output node and
  does not duplicate the inline icon.
- Interaction and accessibility: no new hit target or VoiceOver stop was added.
  Tests cover show/hide/show transitions, invalid values, on-battery duplicate
  prevention, unchanged topology, and unchanged power totals/conservation.

### QA history

1. [P2] The first production capture used vertical `cable.connector`. At the
   compact size it collapsed into a thin vertical mark and did not match the
   selected horizontal connector treatment. Fix: use
   `cable.connector.horizontal` first, with runtime fallback to the original
   connector and then the existing safe symbol fallback.
2. The post-fix production capture was rendered again from the real
   `PowerFlowView` hierarchy. The combined full-region and focused-row
   comparisons show no remaining actionable P0, P1, or P2 differences.
3. Missing, invalid, zero, charging, full, mixed, edge-equal-to-System, and
   on-battery states are executable regression cases. The graph remains three
   nodes and two pipes in every state.

### Follow-up polish

No P3 item is required for the selected micro-adjustment.

final result: passed

## v3.0.23 shared Device Output port template

### Source and implementation

- Selected visual truth: `/Users/leoarrow/.codex/generated_images/01a01de2-549c-7111-8c6d-56eb04196ce7/exec-11bac02a-59e7-48be-8fe0-9c997944981c.png`.
- Extracted source asset: `design/icon/device-output-port-template.png`
  (64 × 64 pixels; SHA-256
  `66bec3f39703faf1d5bf135d9e0dda919c95ce6e8450ec0d3e25091039797f4c`).
- Plugged production capture: `/tmp/wattson-port-template-qa/idle-device.png`
  (656 × 448 pixels, representing the 328 × 224-point
  `PowerFlowView` at Retina 2× density).
- On-battery production capture:
  `/tmp/wattson-port-template-qa/battery-device.png` (656 × 448 pixels).
- Full source/plugged/on-battery comparison:
  `/tmp/wattson-port-template-qa/source-idle-battery-comparison.png`.
- Focused icon comparison:
  `/tmp/wattson-port-template-qa/focused-icons-comparison.png`.

### Comparison

The previous candidate used two different system cable glyphs: a horizontal
connector for the compact plugged-state accessory and a vertical connector for
the full on-battery Device Output node. Neither reproduced the selected
design's closed horizontal port outline consistently. v3.0.23 replaces both
call sites with one `device.output.port` template extracted from the selected
visual source.

The real AppKit captures confirm that the compact plugged-state icon now reads
as a closed device port rather than a short blue line or dot. The on-battery
node uses the same silhouette at the existing full-node scale and neutral tint.
The icon therefore changes scale and semantic colour with its established
context, but not its visual language.

### Required fidelity surfaces

- Layout and typography: the existing three-node/two-pipe topologies,
  176-point plot, 22-point plugged readout slot, 224-point section height,
  node and pipe positions, labels, fonts, and watt formatting are unchanged.
- Colors and visual tokens: plugged output keeps the current state tint in its
  26 × 26-point compact well; the on-battery node keeps the same neutral
  treatment as the other downstream load node.
- Image fidelity: both render paths consume the same extracted closed-port
  raster template. The runtime does not substitute either
  `cable.connector.horizontal` or `cable.connector` at the Device Output call
  sites.
- Power semantics: Device Output remains an auxiliary breakdown of System
  Total. The correction does not change totals, conservation math, recognition
  timing, or the eligibility of any reading.
- Accessibility: the compact icon remains decorative and the existing
  `Device Output` readout remains the sole plugged-state accessibility element.
  The on-battery node retains its existing label and value. Runtime regression
  tests cover uniqueness and ghost cleanup; the screenshots alone are not a
  complete accessibility audit.

### QA history

1. [P2 resolved] The v3.0.22 SF Symbols did not match the selected closed-port
   design and differed between plugged and on-battery presentations. The shared
   extracted template removes that inconsistency.
2. The final visual audit compared the selected source, real plugged-state
   render, and real on-battery render in one normalized image. It found
   P0 = 0, P1 = 0, and P2 = 0.
3. [P3 accepted] The selected mock uses a slightly wider icon well and softer
   shadow. Production retains the tighter 26 × 26-point near-square well and
   more restrained shadow to preserve the requested micro-adjustment scope and
   the current Wattson layout.
4. Focused Swift regression testing verifies one shared port template in both
   states, unchanged accessibility and ghost cleanup, and exactly three nodes
   and two pipes. Static topology testing separately locks the shared token and
   unchanged geometry/math contract.

### Follow-up polish

No P0, P1, or P2 item remains. The single P3 difference is accepted and does
not require another layout change.

final result: passed
