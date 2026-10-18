# Wattson 4.3.22 publication evidence

The user explicitly requested a stable GitHub release. The final frozen source is
recorded in `release-source-commit.txt`; `state.json` tracks the publication gates.
Public installer files must be the exact successful candidate bytes, with a
three-entry installer checksum manifest. Design previews and SVG ZIPs are
separate assets.

## Preserved failed attempts

- Candidate 39132846417 (`fdf6d96`) failed a real background-runner registration
  race during interruption. No installers were built. The narrow shared cleanup
  fix and three deterministic regressions are documented in `../cleanup-fix/`.
- Candidate 39135559350 (`d1e72bd`) passed all 662 Swift and 604 Python tests
  (four Python skips), then failed the baseline matched-tail History fixture.
  Its displayed curve matched the target, but three finite 0.35-second animation
  keys remained after the fixture's one-second deadline. No installers were built.
  Logs and run metadata are retained with `candidate-after-cleanup-fix-*` names.

The latter fixture artificially pauses its view layer. Its resume transaction
uniquely lacked the explicit flush used by the fixture's other transitions.
`9d157d4` adds that submission barrier before timing completion and logs root-layer
clock values on timeout. The one-second bound, exact target geometry and empty
animation-key requirement remain unchanged. No production History, Process
Activity or palette implementation changed. Apple's [transaction documentation](https://developer.apple.com/documentation/quartzcore/catransaction/flush())
explains submission of pending implicit transactions; flushing is not compositor
acknowledgment, so the proposed correction is independently revalidated rather
than treated as proof of the hosted failure's underlying scheduling cause.

The original local short-deadline Python fixture failure remains recorded under
`../headless/`; clean hosted suites subsequently passed that fixture. Local logs
are not rewritten as passing results.

## Distribution policy

This is the established credential-free Community route: ad-hoc App/helper,
unsigned PKG/DMG, no notarization or stapling. The release body discloses this.
Homebrew tap credentials are absent from repository Actions secrets, so the
trusted maintainer fallback changes only the verified version and public PKG
checksum, requires exact-tap-commit CI, and then dispatches the public lifecycle.
That workflow alone marks latest and dispatches Pages after both architectures
pass. Main stays frozen through Pages.

## Maintainer sync

The installed local preview is not counted as the public package. After public
assets are downloaded and matched against the candidate, `verify-installed.sh`
compares App/helper/daemon bytes, receipt and versions, universal architectures,
helper health/V5/process-score formula, and hashes of existing settings. Only
aggregate process sampling details are retained; raw process identities and
frames are not written. A running PID proves launch stability, not direct menu
bar interaction acceptance.

## Source-only cleanup compatibility correction

Candidate `39137918718` passed headless/native/build stages, but is withheld.
The new pending-signal state was unset in workflow consumers that source the
shared runners while retaining custom EXIT traps. All five matrix jobs exited
early; two Intel jobs reported success despite missing completion messages.
The DMG copy stage was also incomplete. None is accepted as a passed lifecycle.
The detailed five-platform logs and diagnosis are in `candidate-final-*`.
Artifact signature/PKG-DMG review was not completed after bounded download
failures, and no tag or public release was created.

`67b3f60` changes the shared registration guard to an unset-safe read without
replacing caller traps. The source-only regression fails all three public
runners against immutable `9d157d4`; the repaired 28-test scope passes. The
workflow now emits completion outputs only at the actual ends of DMG, PKG and
conditional ARM v2 lifecycles. An independent always-running step requires
those outputs and clean paths, receipt, helper/login services and enabled
helper state. Behavioral regression tests reject missing completion outputs
and unexpected launchd query errors; all 66 workflow/migration tests pass.
These changes are release tooling and tests; production App code is unchanged.

## Portable completion guard correction

Exact-67 push CI `39139882106` passed Swift 662 but rejected the newly added
completion regression (three subcases among Python 607). No candidate was
dispatched. System Bash 3.2 does not apply the expected `set -e` behavior to
these false `[[ ]]` compound commands. On the maintainer Mac, the later explicit
receipt failure had masked this weak test. `bash-completion-guard-proof.json`
reproduces the three guard prefixes in a clean shell environment without any
canonical filesystem/service queries: old guards continue with status zero,
while explicit guards exit one with the precise missing-stage error.

`8300cab` adds explicit failure exits for completion markers and residual paths.
The strengthened tests assert the intended error rather than any nonzero exit;
an owned residual fixture also proves rejection before receipt/service queries.
All 67 workflow/migration tests pass. This commit changes only the candidate
workflow and its Python regression tests; native App/helper/interaction inputs
are unchanged from the fully passed `67b3f60` native gate.

## Remaining History fixture investigation

The exact `8300cab` Headless CI run `39141158685` passed 662 Swift and 608
Python checks (four Python skips). Candidate `39141992490` passed baseline and
legacy native interaction variants, then failed the third accessibility
variant at the artificially paused/resumed matched-tail History fixture. The
root model and presentation clocks both reported resumed speed 1; the previous
flush change did not establish a fix. A zero midpoint difference proves only
that retained cubic midpoint reached its target, not that the whole chart is
stationary. No installer was built in this attempt, and no tag or release
was created. The independent owner-local-clock probe is retained under
`../history-fixture-probe/`; production behavior must remain unchanged.

The reviewed harness-only commit `7f41533` separates the exact paused first-frame
geometry assertion from automatic completion on a fresh, never-paused
production layer tree. It preserves actual animation startup, the one-second
removal deadline and the `1e-6` retained-midpoint tolerance, and additionally
checks the complete stroke/fill control geometry and head within 0.01 points.
No update, cancellation, hiding or removal occurs during its completion wait.
Production App/helper/renderers are unchanged. Exact-source native execution
and hosted candidate gates are still required; the pause failure's internal
mechanism remains unproven.

Fresh exact-`7f41533` native replay passed 442/440/434 checks (1,316 total),
including every first-frame/startup/completion assertion, and 20,000 stress
iterations. All 157 archived input hashes matched the frozen commit before
and after execution. The owned VM was deleted and guest/host cleanup audited.
The bounded 36-case probe did not reproduce the hosted failure; all normal
and paused cases retired keys within one second. No causal claim is made.
Exact push Headless CI `39143941668` passed Swift 662 and Python 608
(with four configured skips). A new exact-source candidate remains required.

## Published outcome

[Wattson 4.3.22](https://github.com/laleoarrow/battery-monitor/releases/tag/v4.3.22)
is published as a stable latest release with eight verified assets from frozen
`7f41533b017d26519a69d541d3ffd2dea587f413`. Exact candidate `39145124379`,
tap CI `39147269521`, public Homebrew lifecycle `39147785416`, and automatic
Pages deployment `39147879672` all passed. The public four installer files
were downloaded anonymously and match the candidate byte for byte; the local
curl browser routes timed out, while the official public asset API/CDN route
succeeded without authentication. Prior failed download attempts remain recorded.
The anonymous gallery audit passed 33 checks, plus four independent homepage,
latest-release and annotated-tag requests. No Cody email was sent.

Maintainer public-PKG synchronization is still pending: noninteractive sudo
requires authorization and CUA reports the Mac locked. The already-installed
4.3.22 local preview, helper, receipt and settings remain unchanged. The exact
public PKG is retained in `dist/public-v4.3.22-verify/`, and `before.json` records
15 current setting hashes. After the user unlocks the Mac, open that PKG in
Installer, obtain any real OS authorization, and run `verify-installed.sh` with
the frozen source and public SHA before claiming canonical synchronization.
`final-release-verification.json` deliberately distinguishes completed GitHub
publication from the pending maintainer step.
