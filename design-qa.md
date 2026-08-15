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
- Shipping source capture: `website/public/wattson-popover-real.png` (432×765 pixels).

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

The same dark visual language, information hierarchy, four General controls, four module cards, system state, and accessibility semantics are preserved. The layout is a true compact reflow rather than a scaled image: 176-point sidebar, 22/14/11-point typography, 38-point navigation rows, four 68-point General rows, and 233 × 166-point module cards with 12-point gaps. Native AppKit traffic-light controls replace the oversized painted proxies.

The final result removes the large unused General canvas and reduces overall content area by about 35% while retaining readable labels and standard macOS control density. The Modules page keeps both rows in bounds without clipping or crowding.

### QA history

1. The first compact capture exposed a Modules navigation glyph that crowded its label. The custom oversized glyph path was removed and the screen was recaptured.
2. A stale second-page snapshot was fixed by giving AppKit a full layout/display turn before capture.
3. The last General row was clarified to `Use System Icon` / `Follows the battery symbol supplied by your macOS`, accurately describing the macOS 27 behavior without inventing unavailable Apple artwork.
4. Real AppKit minimize, keyboard navigation, AX/key-loop behavior, retained-window reuse, 1,000 lifecycle iterations, weak release, and FD/RSS bounds passed.
5. The fixed-size window keeps all three native traffic lights while correctly disabling the zoom control instead of advertising a resize action that cannot change the layout.

## Final result

passed
