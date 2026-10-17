# Reference-faithful vector module icons

The five editable SVG masters reconstruct the user-selected Modules reference:

- Energy Flow: a blue curved/downward route and a separate upright neutral arrow.
- Ring Gauge: one circular rim, six short upper ticks, blue northeast needle and hub.
- Power Lanes: three rounded outlined bars; the two taller bars have blue interiors.
- Power History: neutral axes with a blue connected line and three hollow nodes.
- Battery Time: neutral circular rim and a blue rounded clock hand.

Each SVG uses a transparent 24 × 24 artboard and contains only native vector
paths, circles and rounded rectangles. There are no embedded raster images,
fonts or external resources. Edit `currentColor` on the SVG root for a neutral
color when using these masters outside Wattson.

`generate-swift.py` compiles these masters into static AppKit drawing commands in
`MenuBar/ModuleIconArtwork.swift`. Wattson does not parse SVG at runtime or depend
on design files being installed. The existing Settings image view regenerates
the artwork when appearance or contrast changes. Its 28-point alignment slot,
20-point artwork size, row geometry, switches and reordering handles are retained.

## App-aligned fades and trails

Ring Gauge keeps a fully defined neutral contour. Its upper blue sweep uses the
same 0.12-to-1 opacity range as `arcGradient` in
[`Popover/RingGaugeLayer.swift`](../../../Popover/RingGaugeLayer.swift). The
sweep follows the upper circumference and ends on the same radius as the
northeast needle (315 degrees in the SVG coordinate system). It replaces the
previous whole-rim gray brightness gradient and is a static adaptation of the
app's power-arc effect.

Energy Flow retains its subtle route fade-in. Power Lanes now has bright-to-soft
blue fills inside the two taller outlined bars. Power History retains its faint
area fade. Battery Time uses a soft blue quarter-sector between its two hands.
The filled region fades toward the vertical hand and leaves the surrounding
clock face clear; the outline and hands stay fully opaque.

These are static vector details. Increase Contrast removes the decorative Ring
sweep and Clock sector, restores full-opacity Flow and bar fills, and retains the
existing thicker-stroke policy. Row geometry and control behavior are unchanged.

## Regeneration

```sh
python3 design/settings/module-icons-vector/generate-swift.py
bash design/settings/module-icons-vector/render-assets.sh
```

`vector-preview.png` is an offscreen render of the production AppKit paths in
light and dark palettes. Each row includes enlarged and actual 20-point artwork.
It is an artwork proof, not a screenshot of an installed Settings window.
`render-assets.sh` owns a unique project-local scratch directory and automatically
cleans the temporary executable and compiler cache. It opens no windows, writes
no preferences and changes no system settings.

The previous Modules gallery predates this five-icon refresh and remains as
historical evidence of the ordering layout. A fresh VM window capture belongs
to the integrated app validation. No installed application or release is changed
by this vector-source update.

Verification: the five SVGs pass XML/vector-only checks, generated Swift is
deterministic, production Swift typechecking passes with warnings as errors, and
all eight non-interactive Settings contract tests pass. No test assertions were
removed. The new artwork file was added to that harness's explicit compiler
source list. Fresh visible-window validation and installation remain with the
main integrated candidate workflow.

The macOS 12 deployment-target typecheck also passes. `verify-preview.py`
(requires Pillow) reads the unedited native PNG to check flow fade-in, the upper
blue sweep and solid lower rim, needle/end alignment, bar fade, History area
fade, and the Clock sector's fade and clipping.
It compares displayed RGB levels rather than assuming linear alpha mixing.
