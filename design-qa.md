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

- Source visual truth: `/var/folders/jc/p8qsvpfd6t71pngj51n4yvvh0000gn/T/codex-clipboard-7b0490dd-18e1-40aa-a911-7ca2473723fe.png` (1452 × 1052 pixels, active dark window with a six-pixel outer capture margin).
- Normalized source: `/tmp/wattson-settings-menu-bar-icon-source-normalized.png` (1440 × 1040 pixels after removing only the six-pixel outer margin).
- Final implementation: `/tmp/wattson-settings-menu-bar-icon-four-presets.png` (1440 × 1040 pixels from the shipping AppKit frame hierarchy).
- General two-row implementation: `/tmp/wattson-settings-general-two-rows.png` (1440 × 1040 pixels).
- Full-view same-input comparison: `/tmp/wattson-settings-menu-bar-icon-comparison.png` (2880 × 1040 pixels; normalized source left, implementation right).
- Focused same-input comparison: `/tmp/wattson-settings-menu-bar-icon-focused-comparison.png` (2080 × 430 pixels; card region, source left and implementation right).
- Viewport and density normalization: both compared surfaces are 720 × 520 AppKit points at Retina 2× density. No resampling was used; the source was cropped to the exact content/frame extent.
- State: dark appearance at the default complete preset, Wattson with percentage. The reference has the former System style selected; selecting the second preset is an intentional product requirement, not design drift. The implementation traffic lights are inactive because the capture is deliberately hidden and non-key so it cannot interrupt the user's desktop.

### Comparison

The final page preserves the reference shell, heading, subtitle, dark palette, radii, and green radio-card selection language. The former two broad style cards are deliberately replaced by four equal 119.75 × 166-point cards in one 503-point row with three eight-point gaps: Wattson icon only, Wattson with percentage, macOS icon only, and macOS with percentage. Every card contains an image returned by the shipping `BatteryIcon.image(for:mode:pressed:style:)` renderer for the same static 42% snapshot. The two percentage presets additionally render the real `42% ` status title to the glyph's left using `NSFont.menuBarFont` with tabular digits.

The macOS choices continue to use the public battery symbol supplied by the running system; there is no copied or hand-drawn Apple artwork. The concise visible copy fits at the compact width, while each AX radio exposes the complete preset name and a truthful description. General is reduced to exactly two 68-point rows, removing the duplicate percentage control.

### Required fidelity surfaces

- Fonts and typography: the 22-point heading and 11-point subtitle match the source hierarchy. Card titles use 13-point semibold system type, details use 11-point system type, and percentage previews use the real menu-bar font with tabular digits. The executable AppKit contract verifies no visible card title or preset copy is truncated.
- Spacing and layout rhythm: the 176-point sidebar, 503-point content width, 166-point card height, ten-point radii, and aligned heading/subtitle remain unchanged. The four cards are equal width, share one baseline, stay entirely inside the content host, and retain an eight-point rhythm without crowding.
- Colors and visual tokens: content, sidebar, preview tile, unselected border, semantic green selection fill, and high-contrast variants all reuse the existing Settings tokens. High Contrast strengthens borders without shifting geometry.
- Image quality and asset fidelity: all four glyphs are production `NSImage` outputs from `BatteryIcon`; the macOS glyph is a public SF Symbol resolved by the current OS. No emoji, text-symbol substitute, handcrafted SVG, or enlarged screenshot is used.
- Copy and content: all four complete appearances are named explicitly. `Icon only` and `With percentage` remain fully visible, and the percentage examples show the exact visible value `42%` rather than describing it abstractly.

### QA history

1. [P1] The first implementation exposed only Wattson and System style cards, so users could not see or directly select all complete menu-bar appearances. Fix: replaced the two-card style dictionary with the four-value `MenuBarIconAppearance` product order while continuing to persist the existing style and percentage keys. Post-fix evidence: both comparison images visibly show all four choices in one row; the AppKit contract requires four cards and four renderer images.
2. [P1] General duplicated percentage as a separate switch after complete appearances moved to their own page. Fix: removed that row and its observer/action; the list is now exactly 136 points with two 68-point rows. Post-fix evidence: `/tmp/wattson-settings-general-two-rows.png` and executable row geometry assertions.
3. [P2] The first compact preview layout placed the trailing-space percentage frame two points over the image frame (`percentage=(-2,0,36,16)`, `glyph=(32,1,23,14)`). Fix: added the status-presentation two-point inter-item spacing. Post-fix evidence: the strict AppKit assertion requires the percentage frame's maximum X to be no greater than the matching renderer glyph's minimum X.
4. Selection was made atomic across the two existing persisted settings before either existing notification is emitted. Mouse, Space, arrow/Home/End, Tab order, AX radio values, external style/percentage notifications, high contrast, focus redraw, and full-card hit testing pass without an intermediate selected preset.
5. The final captures were produced through `cacheDisplay` without ordering the window front or making it key. This avoids stealing focus while still rendering the real shipping AppKit view hierarchy. Full and focused same-input comparisons show no remaining P0/P1/P2 visual issue. The inactive traffic-light color and missing WindowServer shadow are capture-state differences outside the app-owned settings content.

### Follow-up polish

No P3 item is required for this correction.

final result: passed
