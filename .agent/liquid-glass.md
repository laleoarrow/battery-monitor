# Wattson 4.1.0 Liquid Glass review

Primary guidance: [Apple — Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass).
The runtime option is default-off, presentation-only, and requires macOS 26.
The classic path remains available on every supported system.
This is an in-progress 4.1.0 review. The footer now has an explicit native glass
capsule after the user found that the ordinary mode chooser did not read as a
floating control layer. Local implementation and review are not a published
release or a claim of pixel identity with Apple's iPhone navigation examples.

## Component decisions

| Component | Adoption decision | Verification scope |
| --- | --- | --- |
| Main popover | Use the existing standard NSPopover. Its content, scroll view and sections remain transparent. Request Dark Aqua for the entire glass popover, not only its content. | Real composited window; dark glass under both host appearances; same geometry and data before/after toggling. |
| Power flow, ring, lanes and history | These are the content, not navigation. Retain their production renderers and semantic colors, without extra glass cards. | Charging, full, battery, mixed supply, low battery, Low Power and attached-device output fixtures. |
| Mode chooser | Place the standard NSSegmentedControl inside an explicit NSGlassEffectView in glass mode so the footer has a distinct floating capsule. Share one NSGlassEffectContainerView with the separate settings button, using spacing 0. Retain the established classic geometry, control and reduced-motion fallback. | Real composited capsule and its bounds; pointer, keyboard, disabled modes, in-flight operations and focus transfer. |
| Settings/quick-menu trigger | Keep a separate native `.glass` button beside the mode capsule in the same NSGlassEffectContainerView; retain the standard NSMenu. | Distinct button/capsule shapes, active/inactive readability, keyboard opening, menu anchoring and close/reopen. |
| Settings navigation | Keep the compact sidebar, system sidebar material and native selection. Retain the classic sidebar when off. | All three pages, live switching without rebuilding pages or repeating helper requests. |
| Settings controls | Native NSSwitch and glass button styles when enabled; semantic text and system accessibility. | Unknown states must remain disabled/explicitly unknown; async recovery controls must keep the active Tab chain. |
| System menu-bar glyph | Retain the template/semantic battery glyph, not a miniature textured glass illustration. | Legibility and existing seven-state icon previews. |
| App identity icon | Compose original vector layers in Apple's Icon Composer; use system-generated material and appearance variants. | Native export and asset compilation; primary-system-icon scope is separate from the runtime option. |

## Material and accessibility boundaries

- Do not cover the whole popover with another background visual-effect view.
  The explicit NSGlassEffectView belongs to the footer navigation capsule;
  the popover continues to supply its own background material.
- Near-black means system Dark Aqua, not a solid black scrim or a fake blur.
- Do not turn every data surface into a glass control. The content remains the
  visual priority, as Apple's guidance requires.
- Reduce Transparency may make the surface opaque; Reduce Motion suppresses
  persistent animation. Increase Contrast and semantic colors remain active.
- Existing view-cache images prove layout only. Native glass claims require
  real composited-window review; motion claims require actual motion evidence.

## Current verification

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
  Canonical `design/icon/WattsonGlass.icon` remains near-black with
  particles/energy/track order; its unchanged `icon.json` SHA-256 is
  `d998cbd0fca5a73f1e01b03fcb546babed10cbe47915435da9e3aaa4995fd446`.
  `WattsonGlass-MonoCandidate.icon` is a separate copy of canonical for the
  next refinement; creating these copies does not accept a final icon.

## Remaining review work

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
- Resolve the icon's Mono/Tinted Dark contrast, which currently appears too
  dark, and review all six native appearance variants at small icon sizes.
  A large Composer preview or successful asset compilation is insufficient.
- Refine only the independent candidate and preserve the archived Edited copy
  and canonical source. The saved blue-background document and canonical
  near-black document differ in both background and layer order; reconciliation
  and final appearance acceptance are still separate decisions.
- The primary system app-icon choice remains undecided. The runtime option
  and the Settings logo comparison do not select a shipping Dock/Finder icon.
- Run the 4.1.0 validation and release gates on the final source and artifacts
  only after these UI and icon decisions are resolved.

## Release boundary

The recorded CI baseline is successful run
[34708726238](https://github.com/laleoarrow/battery-monitor/actions/runs/34708726238)
for commit `2f6ae614b1b7ff7df591e5cdaaf25b144f52a42b`. That result predates the
new footer implementation. Require hosted CI on the final new frozen commit;
UI4b now supplies local exact-source interaction evidence,
but the earlier hosted run does not validate the uncommitted UI4 changes.

Source version 4.1.0 is not proof of publication. Keep published 4.0.0 bytes
unchanged. Require the headless tests, real AppKit interaction, local packaging,
exact-commit hosted installation matrix, public Homebrew lifecycle and Pages
gates from `release.md` before announcing or installing 4.1.0.
