# Wattson 4.1.0 Liquid Glass review

Primary guidance: [Apple — Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass).
The runtime option is default-off, presentation-only, and requires macOS 26.
The classic path remains available on every supported system.
This is an in-progress 4.1.0 review. The UI4 outer glass capsule still contained
an ordinary segmented well. UI7 replaces it with genuine native glass buttons;
the production integration is complete and release validation is in progress.
Local implementation and review are not a published
release or a claim of pixel identity with Apple's iPhone navigation examples.

## Component decisions

| Component | Adoption decision | Verification scope |
| --- | --- | --- |
| Main popover | Use the existing standard NSPopover. Its content, scroll view and sections remain transparent. Request Dark Aqua for the entire glass popover, not only its content. | Real composited window; dark glass under both host appearances; same geometry and data before/after toggling. |
| Power flow, ring, lanes and history | These are the content, not navigation. Retain their production renderers and semantic colors, without extra glass cards. | Charging, full, battery, mixed supply, low battery, Low Power and attached-device output fixtures. |
| Mode chooser | Use three mutually exclusive NSButton `.glass` controls, with native selection emphasis and one shared NSGlassEffectContainerView. Remove the ordinary segmented well and extra enclosing glass view. Retain established classic geometry, control and reduced-motion fallback. | Real composited buttons and bounds; pointer, keyboard, disabled modes, in-flight operations and focus transfer. |
| Settings/quick-menu trigger | Keep a separate round native `.glass` button beside the mode buttons in the same NSGlassEffectContainerView; retain the standard NSMenu. | Distinct button shapes, active/inactive readability, keyboard opening, menu anchoring and close/reopen. |
| Settings navigation | Use NSSplitViewController with a native sidebar item and automatic detail safe area. Let AppKit own the floating glass; retain the compact classic sidebar when off. | All three pages, live switching without rebuilding pages or repeating helper requests; preserve focused controls across reparenting. |
| Settings window and groups | Use a transparent NSWindow over NSVisualEffectView `.underWindowBackground` with `.behindWindow` blending. Use one regular NSGlassEffectView per functional group. Scope NSGlassEffectContainerView to the detail content, leaving the system sidebar outside it. Remove opaque group fills. | Actual compositor captures over different backdrops; all three pages, classic round trip and system Reduce Transparency. |
| Appearance preference | Place the app-wide Liquid Glass switch in General > Appearance with the same row alignment as other controls. Keep the navigation sidebar free of preferences. | Normal form fits without scrolling; expanded recovery help remains reachable; other pages' Tab loops return to navigation. |
| Settings controls | Native NSSwitch and glass button styles when enabled; semantic text and system accessibility. | Unknown states must remain disabled/explicitly unknown; async recovery controls must keep the active Tab chain. |
| System menu-bar glyph | Retain the template/semantic battery glyph, not a miniature textured glass illustration. | Legibility and existing seven-state icon previews. |
| App identity icon | Compose original vector layers in Apple's Icon Composer; use system-generated material and appearance variants. | Native export and asset compilation; primary-system-icon scope is separate from the runtime option. |

## Material and accessibility boundaries

- Do not cover the whole popover with another background visual-effect view.
  Native glass buttons supply the footer control material without an extra
  enclosing glass effect; the popover supplies its own background material.
- Near-black means system Dark Aqua, not a solid black scrim or a fake blur.
- Do not turn every data surface into a glass control. The content remains the
  visual priority, as Apple's guidance requires.
- Reduce Transparency may make the surface opaque; Reduce Motion suppresses
  persistent animation. Increase Contrast and semantic colors remain active.
- Existing view-cache images prove layout only. Native glass claims require
  real composited-window review; motion claims require actual motion evidence.

## Current verification

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
- Run the 4.1.0 validation and release gates on the final source and artifacts
  only after these UI and icon decisions are resolved.

## Release boundary

The recorded CI baseline is successful run
[34710861967](https://github.com/laleoarrow/battery-monitor/actions/runs/34710861967)
for commit `41826300c3f2b726c5129cced98bd40a89d3a214`. That result predates the
UI7 native-button and icon integration. Require hosted CI on the final new frozen commit;
the earlier hosted run does not validate these working-tree changes.

Source version 4.1.0 is not proof of publication. Keep published 4.0.0 bytes
unchanged. Require the headless tests, real AppKit interaction, local packaging,
exact-commit hosted installation matrix, public Homebrew lifecycle and Pages
gates from `release.md` before announcing or installing 4.1.0.
