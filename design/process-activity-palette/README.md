# Process Activity App palette

Process Activity now uses the same main chart palette as Power History and
the power lanes: green while charging, blue while plugged idle/full or on
mixed supply, and neutral on battery, including low battery and Low Power.
Each complete 0–100 track still runs horizontally from pale to deep; a score
reveals only its measured prefix. There are no new settings or sampling changes.

The selected action capsule uses the complete bar’s deepest 100-point endpoint
for its gradient, native glass tint and pointer glow. This is independent of the
process score. Light/dark appearances update the native surface, glyph and
reflection; unavailable actions remain neutral. All capsules retain 38 × 16 pt
bounds at x=288/y=4. Names, values, sorting, fixed scale and selection are stable.
The existing single pointer overlay is reused; no timer or observer was added.

## Final source and verification

The capsule endpoint source is frozen at `7ec101a`. Its 68 focused Swift tests
pass, covering Process Activity, action cell rendering, appearance and shared
footer hover integration. Tests check exact endpoint RGB, live palette changes
without data updates, real cell green/blue/neutral pixels, dynamic appearance,
opaque accessibility rendering and glyph contrast. See
[action-endpoint/swift-tests.log](action-endpoint/swift-tests.log).

The final [native review](action-endpoint/owned-source-verification.json) passes
15,532 assertions with 172 captures: 48 selected full popups, 48 selected
six-state module crops, 48 charging/full/on-battery hover crops, eight disabled
modules, 12 production-controller confirmations and four presenter confirmations.
All 152 captured action/endpoint/glow color tuples agree within 0.00001.
Each bar’s middle stop is also compared with the actual History stroke, and
live power-state changes preserve readings, selected identity and geometry.
The final harness keeps host colors during reorder/density tests and omits
the early unselected crops. Both themes, Classic/Glass and both densities run
through charging, full, on-battery, mixed, low-battery and Low Power states.
High contrast remains covered by the focused tests rather than this matrix.

Representative production-renderer fixture captures:

- [Dark green with pointer glow](action-endpoint/accepted/results/gui/classic-dark-charging-compact-hover-right-module.png)
- [Light green with details](action-endpoint/accepted/results/gui/glass-light-charging-detailed-module.png)
- [Dark neutral](action-endpoint/accepted/results/gui/classic-dark-on-battery-compact-module.png)

The final package is built from the same `7ec101a` source. Its build workspace,
focused-test workspace and native VM/resources are cleaned; final PKG/DMG bytes
are retained. Native evidence uses fixture readings and spy confirmation, while
the separate helper probe signals only its own child. Production canonical
popup interaction is only accepted when directly observed; a stable process
alone is insufficient. Installation status is tracked in
[the 4.3.22 record](local-preview-v4.3.22/README.md).

## Earlier bar-only checkpoint

The initial `ce08c50` checkpoint passed 44 focused tests and 11,120 native
assertions with 148 captures. Its selected module images verify the same App
bar palette, but still contain the former blue capsule. They are superseded
by the final endpoint review for capsule colors.

The first focused run’s hue-only assertion used too narrow a tolerance for
native NSColor blending across color spaces. Its log is retained as
`swift-tests-first.log`; the semantic hue tolerance is 0.02 turns while exact
App middle-stop RGB, opacity, brightness order and geometry checks stay strict.

The old unselected crops are excluded because they precede scrolled display
refresh. Old disabled captures follow harness-only updates that omitted the
new color argument; they prove button dimensions/disabled appearance only.
The final harness preserves the active host color on these direct updates
and omits the early crops. High contrast is checked by focused tests; native
six-state captures use normal contrast. Battery/process values are fixtures,
and GUI actions use a spy. The separate helper probe signals only its owned
child; it does not exercise the canonical daemon/socket.
