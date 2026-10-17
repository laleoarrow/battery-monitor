# Theme- and state-aware power icons

The highlighted Adapter, System and Battery motifs use the same rounded vector
family as Settings, with independent neutral contours and semantic accents.
Both the flow nodes and the two lane icons use these masters and native paths.
The Adapter follows the selected Pro B artwork. Connected and disconnected
states share the shell, prong and cable geometry; only their palette and faint
local fill differ. On Battery retains the existing 0.28 opacity applied by its
view, without baking it into the artwork. Original Pro SVGs and their uniform
fit normalization are preserved in `source`.

| Supply state | Adapter accent | System core | Battery accent |
| --- | --- | --- | --- |
| Charging | Green | Green | Green, with charging bolt |
| Plugged in, full or idle | Blue | Blue | Blue |
| On battery | Neutral, disconnected and dimmed | Neutral | Neutral |
| Mixed supply | Blue | Blue | Amber for battery assistance |

Colors come from `PopoverStyle`, resolved in each image view's effective
appearance. Light and Dark use the existing deeper or brighter state colors.
The SVG blue is the generator's accent placeholder; the runtime supplies its
actual color. Increase Contrast removes decorative areas and slightly thickens
functional contours. No global appearance or system preference is changed.

`PowerIconImageView` caches only its last symbol, resolved palette, contrast and
size. Wattage and caption-only updates reuse the image while updating its
accessibility description. A palette, appearance, capacity or symbol change
rebuilds it. No icon animation or refresh timer is added.

Flow keeps its 32-point canvas with a four-point inset inside the existing
36-point well. Lanes retain their 16-point artwork and existing wells. Existing
optical bounds tests pass without widening their size, centering or margin
limits. Capacity retains the original 25/50/75/100 bands, now shared by both
placements. Charging bolts and neutral disconnected styling remain distinct.
Mixed-supply battery icons use amber in both placements. Bar lengths, fill
colors, values, captions, flow topology and existing animation schedules are
retained. The unhighlighted device-output port and cable fallbacks are retained.

Editable 24-unit SVG masters contain no raster, text or external resource.
`data-battery-level` marks the capacity fill width; the generator emits its
runtime fraction into the native path. There is no runtime SVG parser.

```sh
python3 design/popover/power-icons-vector/source/normalize.py
python3 design/settings/module-icons-vector/generate-swift.py
bash design/popover/power-icons-vector/render-assets.sh
```

`power-vector-preview.png` shows four supply states in Dark and Light.
`power-state-matrix.png` also includes low battery and Low Power. Both read the
actual production Flow and Lane image views after updating real `PowerSnapshot`
fixtures. Enlarged icons and their actual 32/16-point canvases are included;
the existing disconnected/full-node opacity is applied. These are offscreen
artwork proofs, not composited screenshots of an installed popover.

Verification includes the unchanged optical-size test, five runtime tests
covering six snapshots in both appearances, palette/description cache changes,
capacity bands, charging/disconnected styling, role colors and Increase Contrast.
A rendered-geometry regression check also requires both plug states to match
when drawn in one ink with decorative fills removed. Twelve
topology contracts and eight non-interactive Settings contracts also pass.
The preview entrypoint compiles all production sources for macOS 12 with
warnings as errors and owns and cleans its temporary executable and cache.
SwiftPM check scratch, package caches and compiler caches were also isolated
and cleaned. The final Swift log and hashes are recorded alongside these files.

The prior 13 Settings icons and native preview PNGs are unchanged. This remains
an isolated candidate source update: no canonical installation, VM, package or
release was modified. Visible popover validation belongs to the final shared
candidate before installation or publication.

The source pair is the Pro concept-calibrated B package. It replaces the earlier
direction-only NE draft: exposed pins are 5.325 source units, the shell has a
continuous rounded end, and the cable starts at the shell's outside edge. Both
supply states share all geometry. The authoring converter bakes the northeast
40-degree transform and uniformly fits paths, stroke widths and gradient into
the existing canvas; it does not reshape the plug or hide an interior cable dot
under opaque fill. Original SVG bytes remain in `source` for comparison.
Native offscreen checks do not replace final visible-window validation or user
approval of the integrated shared candidate.
