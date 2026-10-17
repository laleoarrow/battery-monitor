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
