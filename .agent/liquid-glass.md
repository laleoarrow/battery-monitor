# Wattson 4.1.0 Liquid Glass review

Primary guidance: [Apple — Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass).
The runtime option is default-off, presentation-only, and requires macOS 26.
The classic path remains available on every supported system.

## Component decisions

| Component | Adoption decision | Verification required |
| --- | --- | --- |
| Main popover | Use the existing standard NSPopover. Its content, scroll view and sections remain transparent. Request Dark Aqua for the entire glass popover, not only its content. | Real composited window; dark glass under both host appearances; same geometry and data before/after toggling. |
| Power flow, ring, lanes and history | These are the content, not navigation. Retain their production renderers and semantic colors, without extra glass cards. | Charging, full, battery, mixed supply, low battery, Low Power and attached-device output fixtures. |
| Mode chooser | Use the standard NSSegmentedControl in glass mode; retain the established classic control and reduced-motion fallback. | Pointer, keyboard, disabled modes, in-flight operations and focus transfer. |
| Settings/quick-menu trigger | Use the native glass button style in glass mode and the standard NSMenu. | Active/inactive readability, keyboard opening, menu anchoring and close/reopen. |
| Settings navigation | Keep the compact sidebar, system sidebar material and native selection. Retain the classic sidebar when off. | All three pages, live switching without rebuilding pages or repeating helper requests. |
| Settings controls | Native NSSwitch and glass button styles when enabled; semantic text and system accessibility. | Unknown states must remain disabled/explicitly unknown; async recovery controls must keep the active Tab chain. |
| System menu-bar glyph | Retain the template/semantic battery glyph, not a miniature textured glass illustration. | Legibility and existing seven-state icon previews. |
| App identity icon | Compose original vector layers in Apple's Icon Composer; use system-generated material and appearance variants. | Native export and asset compilation; primary-system-icon scope is separate from the runtime option. |

## Material and accessibility boundaries

- Do not add another visual-effect view over the popover. Apple specifically
  recommends removing custom popover backgrounds that interfere with its material.
- Near-black means system Dark Aqua, not a solid black scrim or a fake blur.
- Do not turn every data surface into a glass control. The content remains the
  visual priority, as Apple's guidance requires.
- Reduce Transparency may make the surface opaque; Reduce Motion suppresses
  persistent animation. Increase Contrast and semantic colors remain active.
- Existing view-cache images prove layout only. Native glass claims require
  real composited-window review; motion claims require actual motion evidence.

## Release boundary

Source version 4.1.0 is not proof of publication. Keep published 4.0.0 bytes
unchanged. Require the headless tests, real AppKit interaction, local packaging,
exact-commit hosted installation matrix, public Homebrew lifecycle and Pages
gates from `release.md` before announcing or installing 4.1.0.
