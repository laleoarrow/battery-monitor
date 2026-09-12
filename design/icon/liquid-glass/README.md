# Wattson Icon Composer source layers

These editable SVGs derive directly from `../make_icon.swift` at `v4.0.0`.
They contain the original curve and particle geometry, with material styling
left for Icon Composer. They are source artwork, not a compiled Liquid Glass
app icon or a pixel-identical recreation of the classic rendered icon.

## Provenance

- Original generator Git blob: `a877e7eb3e5d327f586b0f71b8b24b219f4211e0`.
- Original `AppIcon.icns` Git blob: `88c60246052a83fa1a9a37d34dc86c0a1c716531`.
- Original `AppIcon.icns` SHA-256: `c222188619927c9a40a6aeac136918a3c51fd41adffe9e66b18b07df1f54f2df`.
- The original generator and ICNS remain unchanged. No AI-generated artwork is
  included.

## Composition, back to front

| Layer | Purpose |
| --- | --- |
| `00-background-reference.svg` | Optional solid background color reference. Prefer setting the final background fill in Icon Composer and omitting this graphic layer. |
| `01-track.svg` | Original dark track, 134 units wide with round caps. |
| `02-energy.svg` | Original energy silhouette, initially colored with `flowCold`; set its blue-to-green treatment in Icon Composer. |
| `03-particles.svg` | Four original particle cores; Composer supplies any material effects. |

Every file has a 1024 × 1024 canvas. Preserve the shared canvas and alignment
when importing; do not independently crop, center, or scale the layers. The
track and energy intentionally share the same silhouette, as in the original
generator. An opaque energy layer covers the track; adjust its treatment in
Composer when assessing the final composition.

The source AppKit cubic is `M 240 352 C 452 352 566 690 784 690`. SVG uses
top-left coordinates, so `ySVG = 1024 - yAppKit` gives
`M 240 672 C 452 672 566 334 784 334`. Particle centers are evaluated from that
same cubic at `t = 0.17, 0.41, 0.64, 0.87`; their radii remain `13, 23, 17, 10`.

## Color reference for Composer

Values below are the original sRGB components; the SVG percentage colors retain
these values without rounding to 8-bit hex.

| Source name | sRGB red, green, blue | Approximate hex |
| --- | --- | --- |
| `backTop` | 0.129, 0.129, 0.149 | `#212126` |
| `backBottom` | 0.043, 0.043, 0.055 | `#0B0B0E` |
| `troughColor` | 0.176, 0.180, 0.204 | `#2D2E34` |
| `flowCold` | 0.039, 0.518, 1.000 | `#0A84FF` |
| `flowWarm` | 0.188, 0.820, 0.345 | `#30D158` |
| `sparkTint` | 0.898, 0.949, 1.000 | `#E5F2FF` |

The classic background ran from `backBottom` at the bottom to `backTop` at the
top. Its energy gradient used the source AppKit angle of 42° with stops
`flowCold / alpha 0.22 @ 0.00`, `flowCold @ 0.32`, `flowWarm @ 0.66`, and
`flowWarm / alpha 0.22 @ 1.00`. These are provenance values for visual comparison,
not assumed equivalents of Composer's gradient coordinates or controls. Apply
and review color, translucency, and lighting in Composer.

The SVGs intentionally omit the old rounded canvas mask and inset, background
gradient, top-edge highlight, energy gradient and opacity stops, and particle
halos. No SVG filters, masks, clipping paths, shadows, or blur are present.
This follows Apple's guidance to leave masking and optical effects to the
system and configure background and material properties in Composer.

## Next step and verification

Import the foreground SVGs into Icon Composer, configure its background and
layer/group effects, and save a native `.icon` document. Review the default,
dark, clear, and tinted appearances, including small sizes. These SVGs alone
do not implement those appearances or change any installed app icon.

Check XML syntax from the repository root with:

```sh
xmllint --noout design/icon/liquid-glass/00-background-reference.svg \
  design/icon/liquid-glass/01-track.svg \
  design/icon/liquid-glass/02-energy.svg \
  design/icon/liquid-glass/03-particles.svg
```

Apple references:

- [Adopting Liquid Glass — App icons](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass#App-icons)
- [Creating your app icon using Icon Composer](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer)
- [Create icons with Icon Composer, WWDC25](https://developer.apple.com/videos/play/wwdc2025/361/)
