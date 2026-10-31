# Full-charge native integration

Approved and implemented 2026-10-31. Native runtime verification passed.

The new indicator applies only to the runtime section's `Fully Charged` state.
It preserves the approved sphere occlusion, two continuous slow orbits with
different periods, and tapered continuous trails. All component colors derive
from the runtime's existing power-state tint and resolve in its current
appearance; no independent blue-only palette or new theme setting is added.

The existing system/fallback/calculating/unavailable indicators retain their
meaning. Full charge expresses a power state rather than an estimate source.
Reduced Motion keeps a static double-orbit mark. Hidden or detached views and
closed presentation retain no animation work.

`FullChargeOrbit.swift` projects two circular 3D orbits through a camera at 70
points, retaining the approved radii, inclinations and opposite rolls. The
8-second and 10.6-second revolutions run continuously in opposite directions,
with a closed ±6% speed variation. Orbital planes stay fixed; the preview's
additional plane drift is not needed for the native motion's gentle variation.
Historical 0.52-second ribbons taper continuously and split at the front/back
boundary. Concentric fixed-radius geometry determines the ordering between
orbits as well as the opaque central sphere. Round cores scale uniformly with
perspective. Core Animation interpolates cached keyframes; there is no frame
timer. Palette changes preserve the animation epoch.

Native interaction caught an implicit-animation issue in `isHidden` updates.
`setVisible` now disables implicit actions and skips unchanged assignments.
The final run confirms that repeated telemetry and theme refreshes preserve
phase and leaving full charge removes every animation, including masks.

## Verification and limits

- Final focused Swift run: **23 tests, 0 failures** across the indicator and
  runtime presentation suites; registered preference domains **3, remaining 0**.
- After both feature commits were integrated, current source `6de93c1` also
  compiled and passed the same **23 tests**, with **3 registered / 0 remaining**
  preference domains (`integrated-swift-tests.log`).
- Final real-window interaction: **524 checks, 0 failures**, including actual
  presentation-layer crossings before and behind the sphere, round heads,
  continuous phase, hiding, detaching, closing, and Reduce Motion.
- Final live WindowServer capture: **96 frames at 8 fps / 12 seconds**, plus
  light/dark state sheets; **22 assertions, 0 failures**.
- The six-state production Classic/Regular Glass × light/dark matrix passed
  **6,926 assertions**, with 158 images. It ran before the final visibility-only
  fix; geometry/layout did not change. The final five-state live capture and
  interaction were repeated after that fix.
- Final universal App/helper build passed for **arm64 and x86_64**. This is
  an ad-hoc build verification, not notarization or a published package.

The earlier full Swift run executed 739 tests: one unchanged slider test failed
three assertions (`15.0` versus `15.5` corner radius). A separate run on baseline
`cce72f9551ce5023153dfc88c4f85bd2c2a7bb08` reproduced those exact failures.
The full-suite log remains a failure; it is not reported as green. The final
visibility fix was verified by the 23 focused tests and the complete native
interaction run. The unrelated slider test is left for its own follow-up.

The working tree was also receiving a separate scrollbar implementation.
Verification therefore used an immutable baseline plus this feature's precise
patch. `verified-source.json`, `verified-source.tar.gz`, and `source.patch.gz`
identify the final source. Shared working files retain the other task's edits.

`accepted/` is the final runtime/build acceptance. `lifecycle-regression/`
retains the successful static matrix and the three native assertions that
exposed the implicit-animation bug. `verified-final/` retains the full Swift
run and an earlier native test compilation error, subsequently corrected.
One earlier VM inventory audit also observed another task creating its own VM;
our owned clone was removed and its guest audit passed. The final owner audit
passed normally, with both baseline VMs preserved and the owned clone removed.

`full-charge-native-motion.mp4` is a crop of the final unmodified WindowServer
frames. `orbit-pixel-review.png` samples one frame per second and enlarges the
original pixels 8× for inspection; its visible pixel grid is deliberate.
Selected native screenshots remain in this directory. The full raw image
matrix, all motion frames and earlier diagnostics are retained in the local
review archive identified by `raw-evidence-archive.json`, under project `dist/`.
The evidence JSON image paths can be resolved by extracting that archive.

Guest cleanup audited delayed preference writes, scratch, processes, app
registrations and containers. Host cleanup verifies no owned scratch, app
registrations or Spotlight entries remain. The canonical App/helper are
preserved; the installed App remains **5.0.2**. No installer, release, tag,
production settings or email was changed for this integration.

Reproduce all checks with `bash run-verification.sh NEW_OUTPUT_DIRECTORY`, or
the final focused runtime/build checks with
`bash run-runtime-verification.sh NEW_OUTPUT_DIRECTORY`, from this directory.
Both use the retained immutable source and shared cleanup owner. Fixture
telemetry verifies presentation, not real-hardware battery prediction accuracy.
