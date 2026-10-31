# Fully Charged — double-orbit design proposal

2026-10-31 design preview requested by the user. This is a proposal awaiting
review: no production App code, installed payload, release, or mail was changed.
The previously selected placement beside the time caption is retained.

The central 8-point planet remains steadily lit in the instrument gradient.
Two smaller stars begin moving immediately and continue without a lap pause.
Their inclined elliptical paths use opposite directions, nominal periods of
8 and 10.6 seconds, and starting positions toward upper left and lower right.
The orbit radii differ, with base inclinations of −34° and +30°.

Smooth speed modulation is limited to ±6%, inclination drift to ±2°, and
radius drift to ±1.2% at the default setting. There is no random frame jitter.
Short tapering tails and faint dust follow the same palette. Front/back depth
changes star brightness and layering while the central light stays constant.

The adjacent comparison retains the existing calculating treatment: one star,
one breath per 2.8-second lap, then a 0.5-second pause. Full charge is explicitly
labelled “Fully Charged”; its motion expresses a stable power state, not a time
estimate source or increased prediction accuracy.

The preview follows system appearance, supports manual light/dark selection,
and exposes optional palette, speed and drift adjustments through the design
controls. Blue is the initial plugged-idle example, not a fixed palette rule.
Reduce Motion freezes both full-charge stars. Animation pauses offscreen or
when the document is hidden.

`full-charge-preview.html` is the interactive source. The four PNGs are browser
design previews, not running-App screenshots. `preview-verification.json`
records 736- and 320-point light/dark rendering without horizontal overflow,
both moving stars, state/appearance controls, static Reduce Motion, and no
JavaScript errors. An isolated browser profile and wrapper were managed by
the shared cleanup owner; the browser closed and scratch was removed.
