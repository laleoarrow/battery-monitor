# General settings vector icons

Five icons extend the approved neutral-and-blue family to the General page:

- Launch at Login: an open power ring, blue stem and restrained arc fade.
- Hide System Battery Icon: a rounded menu-bar window with a blue battery at
  the right and a faint blue content region.
- Check for Updates: a neutral circular contour, blue download arrow and soft
  blue fill toward the bottom.
- Check for Updates on Launch: a neutral loop with a blue upper sweep ending
  exactly at the clockwise arrowhead.
- Send Feedback: two overlapping speech bubbles, blue dots and a faint filled
  reply region.

SVG masters are transparent 24-unit vector artboards without embedded raster,
text, fonts or external resources. The shared generator emits static native
paths in `MenuBar/ModuleIconArtwork.swift`. `GeneralSettingsIconView` updates
its non-template image for effective appearance and Increase Contrast. The
existing 20-point artwork, 28-point alignment frames, row geometry, labels and
control actions are retained. The Appearance row keeps its existing layout.
Decorative fades and areas disappear in Increase Contrast while the contours,
blue action marks and feedback dots remain. All artwork is static.

Regenerate with:

```sh
python3 design/settings/module-icons-vector/generate-swift.py
bash design/settings/module-icons-vector/render-assets.sh
```

`general-vector-preview.png` comes from the actual production drawing methods,
rendered offscreen in Dark and Light with enlarged and actual 20-point icons.
It is an artwork proof, not a screenshot of an installed Settings window.

The existing five module and three sidebar SVGs, rendering functions and native
PNG proofs remain unchanged. The non-interactive Settings contracts now also
compare each General row with its matching production artwork and retain the
alignment and text-column checks. Production typechecking targets macOS 12
with warnings as errors. Verification results are in `verification.json`.

These changes are on the isolated `codex/sidebar-vector-icons` branch together
with the previous sidebar designs, without modifying another task's source,
VM or package. No canonical application is installed or released by this task.
Fresh visible-window validation belongs to the final integrated candidate.
