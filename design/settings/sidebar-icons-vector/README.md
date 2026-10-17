# Settings sidebar vector family

The General, Display and Modules icons extend the user-approved module family:
rounded neutral contours, system-blue details and restrained static gradients.

- General retains three sliders with blue knobs and subtle active-track fades.
- Display uses a rounded window, a short blue title-bar mark on the right and a soft blue
  content region.
- Modules uses four rounded tiles with one blue gradient tile.

Editable SVG masters use transparent 24-unit artboards and contain no raster,
font or external resource. Native AppKit paths are generated into
`MenuBar/ModuleIconArtwork.swift` alongside the five unchanged module icons.
The app uses 18-point sidebar artwork in its existing 24-point alignment frames.
Navigation spacing, row heights, labels and selection behavior are retained.

`SettingsSidebarCellView` regenerates artwork when native background emphasis,
appearance or Increase Contrast changes. Emphasized selection uses white ink
and accents so blue details remain visible on the native blue highlight.
Deselection restores semantic neutral ink and system blue. Increase Contrast
removes the Display's decorative fill, makes gradient accents solid and slightly
thickens contours. No animation, timer or additional interaction is introduced.

Regenerate both icon families with:

```sh
python3 design/settings/module-icons-vector/generate-swift.py
bash design/settings/module-icons-vector/render-assets.sh
```

`sidebar-vector-preview.png` is a native offscreen render of the production
artwork in Dark, Light and emphasized colors, including the actual 18-point
size. Its blue cards demonstrate contrast; they do not replace the native
selection background or represent an installed Settings window screenshot.

The full production sources pass macOS 12 deployment-target typechecking with
warnings as errors. All eight non-interactive Settings contracts pass, including
matching sidebar artwork, switching to white under emphasis and restoring the
normal artwork afterward. Existing alignment and text-fit assertions remain.
The first attempt identified a test fixture still conforming to the former
symbol-name property; both contract and interaction fixtures now use the typed
sidebar icon property. No assertion was removed to bypass that failure.

This work is isolated on `codex/sidebar-vector-icons`, based on integrated
candidate `9fef74944447d4753d1edde82997dc41a479ccad`. It does not change the
canonical installation, another task's source, VM or package. Fresh visible
window captures and integration into the shared candidate remain with the main
coordinator after this design is reviewed.
