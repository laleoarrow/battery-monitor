# Wattson 4.2.0 Liquid Glass review

Primary guidance: [Apple — Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass).
The runtime option is default-off, presentation-only, and requires macOS 26.
The classic path remains available on every supported system.
4.1.0 is the preserved published baseline. The 4.2.0 work integrates the approved
A2 draggable control, Standard/Clear popup choices and the completed Settings
refinement. Validation is in progress; local code and preview are not a published
release or a claim of pixel identity with Apple's Control Center.

## Latest continuation — 13 September 2026

The repeated-open defect is fixed: an already-open host is reused instead of
moving its content into a second glass panel and leaving an empty window.
The preview also avoids a close/reopen merely to change Light/Dark. Its native
popup now exposes Classic, Standard Glass and Clear Glass independently of the
diagnostic backdrop. A red preview run reproduced two visible panels; the
fixed run passed 24 cycles and 120 checks, including delayed close callbacks.

Swift 350/350 and Python 494 tests (four existing opt-in skips) pass. The frozen
source's six-case AppKit matrix passes 1,483 assertions, Settings' full
500-cycle release checks, and 20,000 animation iterations. Compiled-input
manifest SHA-256 is
`0943e9050d5e323b5f3b412515d7b107cf93495116550cf98ba08b88fb5d0be3`.
The Settings construction fix retains focus and attaches each page once;
its interactive hang watchdog is 180 seconds, with the existing iteration,
memory and file-descriptor bounds unchanged. The final run finished its
assertions in 101.305 seconds with approximately 1.81 MiB post-warmup growth
and unchanged file-descriptor count.

Local universal 4.2.0 PKG/DMG verification passes, including byte-identical
apps. [Current real-window samples](../design/releases/v4.2.0/README.md)
include the three styles, a Clear Light/Dark pair and a short recording.
Logs and preserved failed diagnostics are in
`dist/release-4.2.0-20260913/continuation-20260913/`.
The first hosted CI run exposed a test assumption: with system Keyboard
Navigation off, native Tab correctly skips popup controls. The test now
checks AppKit's actual next/previous valid key view, retains the full enabled
keyboard chain assertion, and independently verifies focused popup visibility.
It does not change system preferences or production responder behavior.
GitHub CLI authentication remains invalid. Remote release gates and canonical
installation are pending; neither a 4.2.0 tag nor public assets have been
created by this continuation. Installed app/helper/receipt remain 4.1.0.

## Component decisions

| Component | Adoption decision | Verification scope |
| --- | --- | --- |
| Main popup | Classic retains NSPopover. Glass uses a nonactivating NSPanel with a single NSGlassEffectView, regular or clear, and transparent production content. Regular disables the extra window shadow that caused a second outer outline; Clear retains its accepted treatment. | Real composited windows, all-state layout, screen placement, keyboard/menu/outside-click lifetime and cross-host close/reopen. |
| Power flow, ring, lanes and history | These are the content, not navigation. Retain their production renderers and semantic colors, without extra glass cards. | Charging, full, battery, mixed supply, low battery, Low Power and attached-device output fixtures. |
| Mode chooser | Approved A2 uses SwiftUI clear interactive glass with one moving capsule and one fixed label set. AppKit owns authoritative pending/rollback state. Reduce Motion, Reduce Transparency and Increase Contrast retain C native buttons; Classic stays unchanged. | Real pointer drag and label clicks, once-per-release requests, cancellation, keyboard, disabled/busy and rollback. Pure model hooks are not pointer evidence. |
| Settings/quick-menu trigger | A2 has a separate circular interactive glass button anchored to a real mounted NSView for the standard NSMenu. C and Classic retain existing native menu controls. | Distinct shapes, accessibility, menu anchoring and close/reopen. |
| Settings navigation | Use NSSplitViewController with a native sidebar item and automatic detail safe area. Let AppKit own the floating glass; retain the compact classic sidebar when off. | All three pages, live switching without rebuilding pages or repeating helper requests; preserve focused controls across reparenting. |
| Settings window and groups | Use a transparent NSWindow over NSVisualEffectView `.underWindowBackground` with `.behindWindow` blending. Use one regular NSGlassEffectView per functional group. Batch General's two groups inside its scroll document, leaving the fixed heading and sidebar outside the container. Single-group pages need no extra batching ancestor. Remove opaque group fills. | Actual compositor captures over different backdrops; all three pages, scroll clipping, classic round trip and system Reduce Transparency. |
| Appearance preference | General > Appearance holds the app-wide switch and Standard/Clear popup selection. The saved style survives switching glass off; unsupported/off states disable the style control. Keep navigation free of preferences. | General scrolls as needed for the independent logo choice or recovery help; keyboard focus keeps the logo selector visible and page state is retained. |
| Settings controls | Native NSSwitch and glass button styles when enabled; semantic text and system accessibility. | Unknown states must remain disabled/explicitly unknown; async recovery controls must keep the active Tab chain. |
| System menu-bar glyph | Retain the template/semantic battery glyph, not a miniature textured glass illustration. | Legibility and existing seven-state icon previews. |
| App identity icon | Compose original vector layers in Apple's Icon Composer; use system-generated material and appearance variants. | Native export and asset compilation; primary-system-icon scope is separate from the runtime option. |
| In-app Logo | General > Appearance offers Color/Clear static Icon Composer renditions, saved independently of glass. Clear artwork follows the window's Light/Dark appearance. | Immediate Settings identity update, reopen/persistence, keyboard, no helper calls and unchanged Finder/Dock/menu-bar icons. PNGs are not live glass. |

## Material and accessibility boundaries

- Do not insert another backdrop inside NSPopover. The glass panel replaces
  that host and owns one glass root; it does not paint custom outlines or fake
  refractive gradients. Diagnostic stripes belong only to the preview backdrop.
- Glass windows inherit system Light/Dark appearance; do not pin Dark Aqua
  while the preview or app is Light. Classic Settings retains its original dark
  appearance. Clear is not automatically legible over every backdrop; inspect
  actual composited text on bright, dark and patterned backgrounds.
- The visible preview exposes Classic, Standard Glass and Clear Glass in one
  native popup, starting in Clear Glass. Host Light/Dark and the optional
  diagnostic stripes are independent controls. Shipping Settings retains its
  Liquid Glass switch and Standard/Clear style choice.
- Do not turn every data surface into a glass control. The content remains the
  visual priority, as Apple's guidance requires.
- Reduce Transparency may make the surface opaque; Reduce Motion suppresses
  persistent animation. Increase Contrast and semantic colors remain active.
- Existing view-cache images prove layout only. Native glass claims require
  real composited-window review; motion claims require actual motion evidence.

## Preserved Settings and 4.1.0 verification

- The [appearance hierarchy review](../design/settings/appearance-hierarchy/README.md)
  moves Liquid Glass into General and confines the custom effect container to
  detail controls. It records current source verification and compositor images.
- The [native glass review](../design/settings/native-glass/README.md) records
  the whole-window material revision following the user's Control Center
  reference. It also retains the grouped module rows and monochrome symbols
  from the [intermediate list review](../design/settings/modules-list/README.md).
  Refer to the current review for exact-source test and compositor evidence.
- The earlier [Settings refinement review](../design/settings/liquid-glass-refinement/README.md)
  records the native sidebar, General and Menu Bar Icon changes. Its Modules
  card design is superseded; its screenshots and test results remain historical
  evidence for that source revision.

- UI7 full Swift suite: 308/308 pass with warnings-as-errors. Python: 470
  total, 466 pass and four existing interaction opt-in skips. Native cells
  expose one actionable toggle per mode, without duplicate custom button
  accessibility. A real-window regression found that disabling a focused
  button discarded focus; the group now parks and conditionally restores it.
- The test harness separately verifies active/key-window state before keyboard
  assertions. Cooperative `NSApplication.activate()` did not establish that
  condition in the VM. The harness now uses the existing Settings activation
  sequence; the original assertions and failed-run evidence are retained.
- Final UI7 GUI matrix: native 168, legacy 166, legacy-reduced 160,
  native-reduced-transparency 167 and native-increased-contrast 168 passing
  assertion executions (829 total, zero failures). The single synchronous-close
  skip is pre-existing; no locked-screen checks were skipped. Stress passed
  20,000 iterations. Frozen compiled-input SHA-256:
  `cbec90dc97a85792f998a0eed25da7b3ab2892516de3c63fcb73f07f8e29e1a1`.
  Source hashes match before/after and against the current checkout. TestLab
  was stopped afterward; the base VM and canonical installed app were unchanged.
- Final preview uses production UI7 renderers, binary SHA-256
  `b324913fd9fdec054a6f087c735f5f007adf55111f1b35f391b2c4395346f311`.
  Eight new OS-composited windows cover six power fixtures plus Classic Light
  and Glass over a Light host. See the [versioned gallery](../design/releases/v4.1.0/README.md).
  The left fixture controls are not product UI. These are layout/material
  samples, not every possible state/appearance pair or hardware measurements.
- Local universal 4.1.0 PKG and app-only DMG build and verification pass. These
  local bytes are validation artifacts, not the eventual hosted candidate.

### Preserved earlier evidence

- Completed in the UI4 iteration: native footer surface/grouping, retained
  segmented selection indicator, real composited inspection of nine popover
  images (charging, full, battery, battery USB output, mixed-supply USB output,
  low battery, Low Power, Light-host glass Low Power and classic Light Low
  Power), and all three Settings pages. The 12 images and a 4.008333-second
  video were reviewed; full popover/footer bounds, selected state and active
  Check Now text are readable in these captured fixtures. See
  `dist/liquid-glass-option-20260913/composited-ui4/REVIEW.md`. The production
  views run inside a clearly labeled, isolated fixture app, not the installed
  product. These samples do not cover every state × appearance combination.
- UI4b completed five real AppKit interaction modes: 794 passing assertion
  executions, zero failures, one existing non-applicable synchronous-close
  skip, and 20,000 stress iterations. The snapshot's compiled-input SHA-256
  is `12174ef7e2abf87c4e564f2bb714334ac122484aa8f4ad00f31373dd2237c177`;
  source verification passed before/after. TestLab was stopped afterward.
  `ui4/` preserves the original five failures: only the test's hit-test
  coordinate conversion/diagnostics changed for `ui4b/`, not production code.
- The system compositor captures show the material adapting to its backdrop:
  Dark Aqua looks near-black over a dark window and lighter gray over a white
  window. Do not promise a constant black pixel value or add an opaque scrim.
- The formerly Edited Composer document was successfully saved as a separate
  copy, closed and preserved at
  `dist/liquid-glass-option-20260913/icon-refinement/WattsonGlass-Edited-Preserved.icon`.
  Its `icon.json` SHA-256 is
  `5f21b28365082999d2380ca4eeac2d29165fb4a463961338870d68471e4c086b`:
  blue automatic-gradient (0, 0.53333, 1) and track/energy/particles layer order.
  Before the accepted Mono refinement, canonical remained near-black with
  particles/energy/track order and had `icon.json` SHA-256
  `d998cbd0fca5a73f1e01b03fcb546babed10cbe47915435da9e3aaa4995fd446`.
  `WattsonGlass-MonoCandidate.icon` was a separate refinement copy, not an
  accepted final icon. The final source is recorded below.

## Remaining review work

- The Menu Bar Icon page still exposes nested same-named radio view/cell
  entries in AX inspection. Source history shows the same structure in 4.0.0
  and since 3.0.10; this is not introduced by UI7 or an assertion that the old
  installed app was re-tested. Track a separate narrow accessibility fix:
  keep one native actionable cell per card, then verify selection and keyboard
  behavior. Do not treat the current samples as a full VoiceOver acceptance.
- Complete any still-required all-state × Light/Dark × Classic/Glass visual
  combinations; the inspected UI4 samples are accepted within their recorded
  scope, not an exhaustive cross-product or hardware-accuracy measurement.
- Complete full manual keyboard/VoiceOver and active/inactive accessibility
  review across Settings General, Menu Bar Icon and Modules, including
  unknown/disabled and async states. Live switching, active text readability
  and the automated focus/accessibility contracts already have evidence; the
  five process-local override modes do not constitute full manual VoiceOver or
  system-wide accessibility acceptance. Recheck affected surfaces if later
  icon or production changes alter them.
- Final canonical Mono-only white energy fill and all six native appearances
  at 32/64 px have passed native export and asset compilation. Default/Dark
  exports remain byte-identical to the earlier black-ground icon. The root
  accepted the stronger silhouette and retained
  subtle particles as decorative detail; independent review still records their
  limited separation. Do not claim every small particle is individually clear.
- Keep the archived Edited copy. Closing its stale window reverted the original
  package to an early empty group; the canonical source and all three SVGs were
  immediately restored from the verified independent candidate. Final JSON SHA
  is `e2ded3dbf98d2da0597af36445e5a5125c16de822bf6a013744d108a31647c26`.
- The primary system app icon is selected as `WattsonGlass`, per the user's
  request to replace the app icon too. The runtime option controls the app UI,
  not the signed Finder/Dock icon; the original ICNS and 4.0 release stay intact.
- Run the 4.2.0 validation and release gates on the final source and artifacts.

## Release boundary

The later Dock-icon request is independent of the earlier UI-material and
in-app-logo switches: General > Appearance now offers Hidden/Color/Clear,
applied at the next launch only. Hidden keeps the menu-bar-only default;
visible choices add a running Dock tile using the public AppKit runtime image
property and static native 512px exports. Finder and bundle signatures remain
untouched. Clear selects its Light/Dark rendition at startup; it does not gain
live refraction. The disposable Dock probe passed seven separate sandboxed
launches and 110 checks, including persistence and unchanged bundle hashes.
Real preview Settings checked the selector and help in both Light and Dark;
the runtime probe validated API image state, not compositor-visible Dock pixels.
The full Settings gate now passes locally on the exact final source: two fresh
macOS-TestLab runs each passed all eight Settings checks, including every
original creation/reuse/release, RSS and descriptor assertion. Only the opt-in
GUI hang watchdog changed to 180 seconds after measured completion slightly
exceeded the old limit; default headless and compilation remain at 120 seconds,
with unoptimized builds and all thirteen one-second settling intervals intact.
See `dist/release-4.2.0-20260913/settings-triage-analysis.md` for exact hashes,
full resource curves and rejected experiments. This is local resource/functional
validation, not a production speedup claim; final exact-commit hosted validation
has not yet executed for these changes.

The recorded CI baseline is successful run
[34710861967](https://github.com/laleoarrow/battery-monitor/actions/runs/34710861967)
for commit `41826300c3f2b726c5129cced98bd40a89d3a214`. That result predates the
UI7 native-button and icon integration. Require hosted CI on the final new frozen commit;
the earlier hosted run does not validate these working-tree changes.

4.1.0 was subsequently released from `e90deb3920b249514cc86e7cd6ad1a6282cee614`.
Source version 4.2.0 is not proof of publication. Keep published 4.0.0 and 4.1.0
bytes unchanged. Require headless tests, real AppKit interaction, local packaging,
exact-commit hosted installation matrix, public Homebrew lifecycle and Pages
gates from `release.md` before announcing or installing 4.2.0.
