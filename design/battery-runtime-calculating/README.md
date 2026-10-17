# Battery runtime calculation state — 4.3.14

After unplugging a full battery, the charged flag can disagree with the new
power source. The old guards rejected that sample and displayed `Unavailable`.
This condition is reproduced with fixed inputs; the user's original raw sample
was not captured, so it is not a retrospective hardware diagnosis.

The runtime row now shows `Calculating…` during the bounded settling window.
An unplugged, noncharging battery can collect discharge samples while its raw
full flag remains set. An inconsistent IOPS charged description contributes no
old minute value. Opposite IOPS direction gets at most the initial 60-second
window, without resetting that window on every sample. If valid discharge
current resumes later, collecting its new window also shows `Calculating…`.
Degraded readings and settled missing inputs remain `Unavailable` and can recover
on a later valid sample. Existing system estimates still appear immediately.

Frozen production source: `d8abc3598f727c0b6f25db453100a3089032d934`.
The root integration also retains the independent normal-drag verification docs;
its production files match the frozen source.

Validation:

- Original algorithm fails the new transition/recovery assertions; the fixed
  36 algorithm tests pass. Ten sampler Python contracts also pass.
- A disposable ARM VM executes 48 native tests and 16 real-window state captures
  across light/dark appearances. All text, layout and retained-content assertions
  pass; all 16 original images were visually reviewed.
- Five package cases cover the previous 4.3.13 install, disabled-helper upgrade,
  fresh 4.3.14, reinstall and disabled-helper reinstall. Exact payload, signature,
  receipt, helper health/v5 and uninstall checks pass. PKG and DMG App bytes match.
- VM cleanup passes immediately and after 113 seconds; its VM and transfer copies
  are removed. Other tasks' VMs are preserved.
- The normal system Installer completes the canonical 4.3.14 update. Installed
  App/helper/daemon bytes match the approved package; marketing/build/receipt,
  signatures, helper health/v5 and normal App process stability are verified.
- Canonical cleanup passes immediately and after 99.247454 seconds of system
  monotonic time: no installation processes, scratch, mounts or extra App
  registrations remain. The prior 4.3.13 evidence hashes are unchanged.

The first two private QA wrappers encountered cleanup failures. Their original
nonzero results are preserved. Corrected v3 wrappers rerun both complete tests
and captures with successful cleanup; no production source change was required.

Final records are in `.build/runtime-calculating-review.noindex/`; the compact
[verification record](verification.json) binds their checksums. Internal native
captures remain validation evidence and are not publication artwork. This is a
local candidate, not a GitHub release or a real-battery timing/performance claim.
