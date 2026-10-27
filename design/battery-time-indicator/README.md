# Battery time source indicator — approved implementation

The user approved the caption-adjacent design on 2026-10-27 and requested its
implementation in Wattson. Product source is frozen at
`a7621f735b01308ae8299b946da83f2c13dcd2e5` (local version 5.0.2).
This is local implementation and installation work, not a public release.

## Approved behavior

- Official system time: steady theme-colored planet.
- Battery-controller or observed-discharge fallback: smooth 3.6-second breathing.
- Calculating: starts orbiting immediately. One inclined 2.8-second lap shares
  one dim–bright–dim breath, followed by a shared 0.5-second dim pause. Planet,
  halo, comet and tapered dust use one timeline. Routine samples preserve phase.
- Unavailable/failed reading: soft red 2.4-second breathing.

The 8-point planet sits in a 20-point area immediately before the runtime title.
The gradient clock retains its 24-point artwork and 44-point rounded well:
neutral outline, theme-colored hands/center, subtle diagonal face gradient and
lightly tinted border. The clock stays static, including during a source error.
Colors follow the existing instrument palette: green while charging, blue while
plugged idle/full or on mixed supply, neutral silver/gray on battery. The browser
preview's color controls demonstrate the design; they do not add product settings.

The existing 88-point runtime module, estimate text and source-priority rules are
preserved. Closing/hiding/detaching the view or enabling Reduce Motion stops
animations. High contrast reduces decorative treatment. No timer was added.

## Source and artwork

- `Popover/BatteryTimeIndicatorView.swift`: source semantics and Core Animation.
- `Popover/PopoverContentView.swift`: runtime integration, palette and lifecycle.
- `design/popover/power-icons-vector/clock.svg`: editable clock artwork.
- `design/settings/module-icons-vector/generate-swift.py`: generated
  `ModuleIconArtwork.PowerIcon.clock`, shared with the upper Power icon family.

`planet-source-preview.html`, its standalone copy and `clock-rhythm-preview.png`
retain the approved browser design. They are design previews, not evidence of
native rendering. Earlier preview images and the interrupted prototype capture
are historical records superseded by `implementation/native/`.

## Verification

- `implementation/swift-tests-final.log`: **735 tests, zero failures**; all 183
  registered test preference domains removed (`remaining=0`). The initial full
  run hit the existing 50 ms Settings relay timing assertion under concurrent
  load; the isolated recheck and final full run passed without changing that test.
- `implementation/python-tests.log`: **652 tests, OK, 4 expected skips**.
- `implementation/animation-stress.log`: **20,000 iterations passed**.
- `implementation/native/captures/evidence.json`: **6,926 assertions, zero
  failures**, six-state light/dark production-renderer and real Classic/Glass
  WindowServer captures. Battery/process inputs are deterministic fixtures.
- `implementation/native/interaction.log`: **ALL_INTERACTION_CHECKS_PASSED**,
  including shared animation epoch, immediate first orbit, one breath per lap,
  half-second dim pause, lifecycle, and appearance checks.
- `implementation/native/battery-time-indicator/evidence.json`: 98 WindowServer
  captures, 18 assertions, zero failures. Four production runtime rows in
  light/dark plus 96 frames at 8 fps (12 seconds) of actual Core Animation output.
  The fixture window does not itself validate physical battery telemetry or the
  canonical installed status item.
- `implementation/runtime-motion.gif`: viewing copy of native frames 001–080,
  covering about 10 seconds and three normal calculation cycles. The raw capture
  has a 0.752-second collection gap after frame 083 and frame 000 precedes the
  restarted animation's compositor commit; both are excluded from this viewing
  copy. The complete PNG sequence and actual timing metadata remain the evidence.
  Eight fps supports cycle review, not a claim about display-rate smoothness.
- `implementation/native/guest-cleanup-audit.json`: all checks passed, including
  delayed preference writes, scratch, process and application-registration cleanup.
  The owned VM clone was deleted; both pre-existing VM states were preserved.

## Local installation

The local universal PKG/DMG passed structural and checksum verification.
`installation/local-artifacts.json` records their hashes and completed scratch
cleanup. The preview installation was still waiting for administrator
authentication when the user requested public release. Its owned authorization
request was stopped before an installer began, avoiding a duplicate upgrade;
the canonical 5.0.1 payload and settings were verified unchanged. See
`installation/preview-install-deferred.json`. Canonical synchronization will use
the exact reviewed public 5.0.2 PKG after its public release gates pass.
