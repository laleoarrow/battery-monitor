# Slider radius regression

The native knob host initialized its layer radius from the preferred 30-point
height. The selector itself followed its actual bounds during layout, but
`updateShadowPath()` returned before updating the host radius on the native
Liquid Glass path. A 31-point display-aligned host therefore retained radius
15 rather than 15.5. The fallback path already performed this update.

The shared host radius now follows its current height before the fallback-only
shadow branch. The assignment disables implicit animation, so geometry updates
do not create another animation. Preferred dimensions and material choices are
unchanged.

The existing strict resting-geometry test now covers both native and forced
fallback renderers, all three detents, and explicit 31- and 38-point resizes.
It preserves the 0.01-point assertions for height, edges, center, width and both
host/selector radii. This makes the regression independent of display rounding.

- Before the production fix, the expanded test failed nine native host-radius
  assertions; fallback assertions passed (`before-fix.log`).
- After the fix, the six `testModeSlider` tests passed (`after-fix.log`).
- Both runs used `scripts/test_swift.sh` and ended with registered preference
  domains 0, remaining 0. No preference suite was needed by this scope.
- `git diff --check` passed for the two changed source/test files.

The release owner runs the complete suite and native release acceptance after
integrating this change. This focused check does not publish or install an App.
