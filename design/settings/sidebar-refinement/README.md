# Settings sidebar refinement

The user requested a stricter overall Pro review, particularly of the left
navigation. The current Light/Dark Appearance captures were supplied alongside
the earlier General and Modules images in the same
[Pro review conversation](https://chatgpt.com/c/6ad05ec4-72b8-83ec-8be1-bcc63c247292).
The browser's Pro selector was verified before submission.

Pro identified weak, undersized navigation symbols and a heavy selection
background. It compared small colored category badges with a monochrome
Finder-style treatment and recommended the former, using muted colors. The
implementation follows that recommendation; the palette and dimensions are
aesthetic choices rather than requirements in Apple's HIG.

| Element | Implementation |
| --- | --- |
| General | White `gearshape.fill` on graphite |
| Display | White `menubar.rectangle` on blue-gray |
| Modules | White `square.grid.2x2.fill` on teal |
| Badge | 24-point square, 6-point corner radius, 16-point medium SF Symbol |
| Label | Existing 13-point medium text, 9-point badge-to-text gap |
| Rows | 40-point height, 4-point spacing, 12-point gap below identity |
| Glass selection | Retained native AppKit source-list selection |
| Classic selection | System accent at 14% opacity; 28% and a 2-point outline for Increase Contrast |
| Badge contrast | 1-point semantic outline for Increase Contrast; theme-aware opaque fills |

The logo and app name retain their existing size. Badge colors establish three
stable category identities, while Classic selection follows the user's system
accent. The white-glyph palette contrast ratios are 4.99/3.83 for graphite,
4.52/3.43 for blue-gray and 4.69/3.68 for teal (Light/Dark). These calculated
palette ratios do not constitute a complete accessibility audit.

The original all-rows-visible test caught a native source-list layout detail:
40-point rows give Modules a 142-point extent, so the navigation viewport was
increased to 144 points. Labels, keyboard navigation, focus and selected-page
state remain owned by the existing table and section controllers.

On the right, Popup background, Transparency and its value use 12-point type.
Existing semantic separators are retained. Pro's partially visible Updates
heading came from the previous Appearance screenshot's scroll position; the
new fixture aligns the Appearance heading near the viewport top. It does not
change product scrolling or hide partially visible content.

Apple references consulted for this pass:

- [Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars)
  — familiar symbols, purposeful icon colors and native sidebar behavior.
- [Icons](https://developer.apple.com/design/human-interface-guidelines/icons)
  — clear imagery and consistent visual weight.

See [capture evidence](CAPTURE-README.md) for actual production-renderer
screenshots and source/image hashes. Capture preferences and system operations
are isolated fixtures. This is a source refinement, not an installed update or
a new release.

Validation on the final source: eight Python Settings contracts and thirteen
related Swift tests passed. The contracts verify badge geometry, symbol
resolution, text fit, semantic accent selection, live contrast changes,
native selection, keyboard navigation and retained appearance behavior.
Eighteen production-renderer compositor captures cover all three pages and
Appearance in Classic/Glass, Light/Dark, plus the Glass contrast pair. Source,
image and capture-patch hashes were checked; all owned temporary resources
were cleaned. A separate code review found no actionable regression.

For the final Pro pass, the inspected General Light/Dark Glass images and
Light Glass Appearance image were submitted. Pro judged the sidebar more
coherent, with clearer icon weight, alignment and brand spacing, and recommended
shipping this refinement without further decoration or geometry changes.
It also confirmed that normal card clipping at the scroll edge needs no change.
