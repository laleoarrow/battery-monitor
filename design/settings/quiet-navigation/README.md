# Quiet Settings navigation and typography

The user rejected the colored category badges, crowded icon strokes and large
right-side typography. This revision completes the existing uncommitted
monochrome/smaller-type draft rather than treating the prior Pro approval as
acceptance by the user. Earlier galleries remain historical evidence.

## Navigation

Colored badge fills and their additional borders are removed. Each navigation
item has one regular 18-point SF Symbol in a 24-point alignment slot, a
9-point label gap and regular 13-point text. General uses sliders, Display
uses a simple frame, and Modules uses four filled squares. The simple frame
avoids placing another closely spaced line inside the small Display glyph.
Labels supply the meaning and remain the accessible navigation names.

Rows are 32 points high with 4-point spacing. The navigation viewport is
124 points high, and the identity is reduced to a 32-point logo and 14-point
medium name. Glass retains native source-list selection. Classic uses a
neutral semantic-label fill at 7% opacity, strengthened to 14% and a semantic
outline for Increase Contrast. Selection remains visible without adding a
separate border around every icon.

## Right-side typography

| Role | Size and weight |
| --- | --- |
| Classic page heading | 18-point semibold |
| Native toolbar page title | 15-point medium |
| Primary setting labels | 13-point regular |
| Group headings | 12-point semibold |
| Description text | 11-point regular |
| Display preset titles | 12-point medium |

The smaller hierarchy applies across General, Display and Modules. Existing
controls, section ordering, accessibility help and keyboard navigation remain
in the retained AppKit hierarchy. No new settings or explanatory copy are
added.

See the capture notes and source/image manifest in this directory for actual
Light/Dark Classic/Glass renders. Fixtures use in-memory preferences and
mocked system operations in the existing disposable GUI VM. This source
revision does not update the canonical installed app or create a release.

## Validation

The 8 Python Settings contract tests and 13 Swift optical-margin, recovery,
appearance and logo tests pass. The 18 production-renderer captures cover
General, Appearance, Display and Modules in Light/Dark and Classic/Glass,
plus two Glass Increase Contrast views. Original-size inspection shows
separate symbol strokes, clear label spacing and the smaller type hierarchy.
Navigation remains readable with Increase Contrast enabled.
