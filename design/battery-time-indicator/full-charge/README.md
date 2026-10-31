# Fully Charged — 3D double-orbit design proposal

2026-10-31 design preview requested by the user. This is a proposal awaiting
review: no production App code, installed payload, release, or mail was changed.
The previously selected placement beside the time caption is retained.

The initial draft was rejected because its projected ellipses remained outside
the sphere, so the front/back layering did not produce visible occlusion. Its
separate tail dots also gave the stars an irregular appearance.

Revision 2 uses actual 3D circular orbit coordinates projected onto a 2D canvas.
The opaque central sphere has radius 4 points. The two orbit radii are 8.4 and
7.4 points, inclined 78° and 76° to the screen, then rolled +35° and −32°.
Perspective uses camera distance 70. Both projected paths cross inside the
sphere silhouette: the near side passes in front and the far side is occluded.
The stars remain outside the solid sphere in 3D.

Every trail segment has its own depth; segments crossing z=0 are split there.
All geometry is depth-sorted, with the opaque shaded sphere drawn between back
and front geometry. This also masks the rear star's glow. Head position and
diameter use the same perspective scale, retaining a circular bright core.
Continuous tapering trails sample the actual historical orbit at t−δ, including
its smooth drift, instead of moving a disconnected collection of tail dots.
Subtle complete orbit lines clarify depth and can be hidden in design controls.

Both stars start immediately and loop without pauses, at nominal periods of
8 and 10.6 seconds in opposite directions. Smooth speed modulation is ±6%,
inclination drift ±0.8° and roll drift ±1.4° at the default setting. There is
no random jitter. Central lighting remains steady and follows the theme.

The adjacent comparison preserves the calculating rhythm: one star, one breath
per 2.8-second lap, then a 0.5-second pause, using the preview's revised renderer.
Full charge is explicitly
labelled “Fully Charged”; its motion expresses a stable power state, not a time
estimate source or increased prediction accuracy.

The preview follows system appearance, supports manual light/dark selection,
and exposes optional palette, speed, drift and orbit-line adjustments through the design
controls. Blue is the initial plugged-idle example, not a fixed palette rule.
Reduce Motion freezes both full-charge stars. Animation pauses offscreen or
when the document is hidden.

`full-charge-preview.html` is the interactive source. The four PNGs are browser
design previews, not running-App screenshots. `preview-verification.json`
records 736- and 320-point light/dark rendering without horizontal overflow,
front/back crossings for both orbits, split and sorted depth segments, an opaque
sphere, state/appearance controls, static Reduce Motion, and no JavaScript errors.
Six `orbit-depth-*.png` samples show different moments of the revised orbit.
Canvas backing resolution accounts for enlargement, with at least two pixels
per displayed point. A scratch-only inspection hook exposed the original
geometry/draw functions without changing their behavior. The isolated browser
profile and wrapper were managed by the shared cleanup owner; the browser
closed and scratch was removed.
