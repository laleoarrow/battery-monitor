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

The same dark visual language, information hierarchy, system state, and accessibility semantics are preserved. The layout is a true compact reflow rather than a scaled image: 176-point sidebar, 22/14/11-point typography, 38-point navigation rows, two 68-point General rows, a dedicated four-preset Menu Bar Icon page, and 233 × 166-point module cards with 12-point gaps. Native AppKit traffic-light controls replace the oversized painted proxies.

The final result removes the large unused General canvas and reduces overall content area by about 35% while retaining readable labels and standard macOS control density. The Modules page keeps both rows in bounds without clipping or crowding.

### QA history

1. The first compact capture exposed a Modules navigation glyph that crowded its label. The custom oversized glyph path was removed and the screen was recaptured.
2. A stale second-page snapshot was fixed by giving AppKit a full layout/display turn before capture.
3. Icon style and percentage are now combined into four complete presets on the dedicated Menu Bar Icon page. General retains only Launch at Login and Hide System Battery Icon.
4. Real AppKit minimize, keyboard navigation, AX/key-loop behavior, retained-window reuse, 1,000 lifecycle iterations, weak release, and FD/RSS bounds passed.
5. The fixed-size window keeps all three native traffic lights while correctly disabling the zoom control instead of advertising a resize action that cannot change the layout.

## Dedicated Menu Bar Icon settings

### Source and implementation

- User-reported incomplete-state capture: `/var/folders/jc/p8qsvpfd6t71pngj51n4yvvh0000gn/T/codex-clipboard-7b0490dd-18e1-40aa-a911-7ca2473723fe.png`.
- Superseded four-card implementation: `/tmp/wattson-settings-menu-bar-icon-four-presets.png`.
- Final four-row, seven-state implementation: `/tmp/wattson-settings-native-system-assets-vm.png` (1440 × 1040 pixels from the shipping AppKit hierarchy).
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
exact percentage fill plus the distinct system plug and charging-bolt
adornments. Low Power colours only the interior fill yellow while the outline,
cap, plug, and bolt remain in the menu-bar foreground colour; the native glyph
does not inherit Wattson's whole-glyph tint semantics.

The macOS choices compose the running system's Control Center outline, cap,
plug, bolt, and knockout-mask resources at their native proportions; no Apple
artwork is copied into the app. A resolution-independent vector fallback keeps
older supported systems usable if a system asset is unavailable. The concise
visible copy fits at the compact width, while each AX radio exposes the complete
preset name and a truthful description. General is reduced to exactly two
68-point rows, removing the duplicate percentage control.

### Required fidelity surfaces

- Fonts and typography: the 22-point heading and 11-point subtitle keep the established hierarchy. Row titles use 13-point semibold system type, details use 11-point system type, state labels use compact 9-point medium type, and percentage previews use an 11-point menu-bar font with tabular digits and verified safe chip insets.
- Spacing and layout rhythm: the 176-point sidebar and 503-point content width remain unchanged. Each option row is 503 × 80 points; four rows use eight-point gaps. Each row contains seven approximately 64 × 38-point state chips separated by five-point gaps.
- Colors and visual tokens: content, sidebar, state tiles, unselected borders, semantic green selection fill, and high-contrast variants reuse the existing Settings tokens. High Contrast strengthens borders without changing geometry.
- Image quality and asset fidelity: all 28 glyphs are production `NSImage` outputs at the real 23 × 14-point menu-bar size. No emoji, text-symbol substitute, handcrafted SVG, screenshot, or enlarged approximation is used.
- Copy and content: all four appearances and all seven states are explicitly visible in every row. The percentage rows use every fixture's actual value rather than one repeated example.
- Interaction and accessibility: the whole 503 × 80-point row remains one radio button and one hit target. State chips are non-interactive and do not add 28 Tab or VoiceOver stops. Up/Down and Left/Right navigate rows; Home, End, Space, AX press, focus redraw, notification syncing, and atomic two-key persistence remain covered.

### QA history

1. [P1] The first implementation exposed only Wattson and System style cards. The next pass exposed all four appearances but compressed them into one horizontal row and showed only one renderer state per appearance. Fix: retained the four-value product order but converted it to four full-width rows, each containing all seven meaningful production-rendered states.
2. [P1] A global count alone could have allowed the 28 previews to collect in the wrong row. Fix: the executable contract now requires exactly seven chips, seven visible labels, and seven renderer images inside every individual option row, in production order.
3. [P1] General duplicated percentage as a separate switch after complete appearances moved to their own page. Fix: removed that row and its observer/action; the list remains exactly 136 points with two 68-point rows.
4. [P2] The first four-row capture showed the radio circles underneath the final state chip. Fix: made the radio Y position respect the button's flipped coordinate system and recaptured. The final image visibly shows all four circles and the selected inner dot.
5. Percentage-to-glyph pairing is asserted by matching complete identifiers, a shared direct parent, and left-to-right frame order for all 14 percentages. No percentage overlaps its glyph.
6. The host Swift suite, hidden AppKit contract, and the real visible AppKit interaction/lifecycle contract passed. The latter ran inside the ARM VM so the maintainer desktop was never activated or disturbed.
7. [P1] The first macOS rows used generic `battery.*percent` SF Symbols. Those are not the Battery menu extra's artwork and also omitted the idle-AC plug. Fix: compose the current OS's small Control Center battery assets, preserve exact percentage fill, use the plug for connected-idle states, and reserve the bolt for actual charging. The corrected hierarchy and 500-cycle lifecycle contract passed again in the ARM VM.
8. [P1] The first Low Power preview left the entire native icon neutral. Fix: match macOS 26 by colouring only the battery's interior fill yellow while keeping the outline, cap, plug, and bolt in the menu-bar foreground colour.

### Follow-up polish

No P3 item is required for this correction.

final result: passed
