# Performance and boundary correctness review

Final frozen source **`4532daac11c0698ab97f05a6fc47e563b16d4e0e`** passes the
[complete macOS 27 validation](https://github.com/laleoarrow/battery-monitor/actions/runs/39198225803):
**664 Swift tests, 613 Python tests with four expected opt-in GUI skips, all
three native variants, 20,000 stress iterations, and the universal App/helper
build**. Actual Pro review and its capture follow-up are complete.
The build is ad-hoc validation, not a published/notarized package or an update
to `/Applications/Wattson.app`. See the
[final hosted proof](compatibility/ci-39198225803/verification.json) for exact
OS/SDK/source identity, enforced checks and qualifications.

The three runtime changes are frozen at `df7d4bcbeb0200e6ee5001182d92f62229aba88f`,
after the public 4.3.22 source and its release-evidence commit `9ab0c43`.
Test-only Pro follow-ups are frozen at `163f990`; opt-in macOS 27 CI diagnostics
are frozen at `683bf76`. The later `4bbe066` fixes only test-domain cleanup on
27; `67f3910` makes one existing strong feedback-worker capture explicit for
the new compiler diagnostic. It preserves the outer strong/inner weak lifetime.
The final App runtime source is `67f3910`, with the original three runtime
patches unchanged. Build verification source `4532daa` checks required
architectures separately for cross-version `lipo` compatibility.
The production changes preserve the existing feature set, presentation,
sampling formula, cadence, permission model, helper protocol and deployment
target. This is an unreleased source change, not a canonical installation.

## Evidence-backed changes

| Change | Reproduced problem | Verification |
| --- | --- | --- |
| Refresh action appearance only when `isEnabled` changes; remove the extra per-reading refresh. | Identical enabled assignments replaced the glyph; the row update still replaced it even with the button guard. | The original button fails six image-identity assertions. The original row path, tested with the button guard already present, fails nine. Fixed button/view classes pass all 38 tests, including actual enabled-state action, tint, appearance and accessibility updates. Score and bar changes still occur while image identities remain stable. This measures avoided work, not an app-wide speedup. |
| Preserve owned row/button keyboard focus by full process identity across ranking changes. | The actual first responder stayed in the old physical row while selection followed process A; Space then selected B. The native button, Compact, removal and Top N cases also exposed stale focus. | The independent baseline keeps `allPassed:false`. Fixed-source v2 passes all 34 actual-window checks, with no unexercised native-button path. Same-PID replacement, identity loss, unselected focus, surviving-identity Top N fallback and external field editors are included. Persistent regression coverage was added to the standard interaction harness. All termination handlers are mocked. |
| Use a 100 ms poll wait when idle time has expired but a background worker remains pending and no reader owns a deadline. | A deliberately blocked sampling lock causes the original helper to poll with zero timeout tens of thousands of times per quarter second. | The new executable assertion fails on the original function and passes on the fix; all 53 helper contracts pass. A production-function comparison falls to three polls per roughly 303 ms. Reader priority, round-up/clamping, 12-second idle lifetime and exit predicate remain unchanged. The worker writes its response independently, so only eligible idle-exit checks may wait for the requested 100 ms interval, plus scheduling delay. This is a defensive edge case, not proof of ordinary runtime overhead. |

The target-OS run also exposed a new Swift compiler diagnostic in the existing
feedback worker. One explicit `[self]` on its outer background closure preserves
its existing implicit strong capture and nested weak main callback. The existing
Settings `-warnings-as-errors` executable contract verifies it; see the
[capture follow-up](pro-review/capture-followup/verification.json). No feedback
content, UI, destination or error behavior changes.

See the component evidence in [button](button/README.md),
[helper-poll](helper-poll/README.md), [focus-native](focus-native/README.md),
and the independent [local integration review](integration/review.txt).
The review's three initial coverage gaps are exercised by the fixed-source v2
native report; its earlier pending statements describe the review-time state.

## Retained implementation and limits

The synchronous initial IOKit sample was measured in 24 separate processes:
median 1.024 ms, p95 1.898 ms, maximum 7.527 ms. No production change was made to
that path. This is API cost on the available host with warmed system caches,
not a complete launch/first-frame benchmark. See [startup evidence](startup/README.md).

The initial frozen production source passes full host checks: **664 Swift
tests**, **608 Python tests with four expected interaction skips**, and the
release build for **arm64 + x86_64**, including strict signatures, bundle checks
and the macOS 12 deployment target. Logs and exit codes are in `integration/`. The initial three GUI variants execute **1,358 passing checks**,
plus the independent 34-check focus probe and 20,000-iteration animation stress
test. The later test-only Pro follow-up passes **1,379 checks**, 34 independent
focus checks and 20,000 stress iterations on frozen `163f990`; see its
[native proof](pro-review/focus-followup/native-163f990/owned-source-verification.json).
An existing close/reopen timing path remains qualified because the system
completed closing synchronously; it is not counted as exercised. All new native
focus paths were exercised. Native reports and cleanup proofs are kept separately.

The host is macOS 26.5.2 / SDK 26.5; the owned GUI VM reports 26.6.1.
The [macOS 27 source review](compatibility/README.md) found no demonstrated
regression requiring a speculative patch. Actual SDK 27 builds and all 664 Swift
tests pass on macOS 27.0.1. Target runs then exposed the test cleanup format and
explicit capture diagnostic addressed above. Final hosted native and universal
build gates now pass on frozen `4532daa`, with all earlier failures retained. Physical sensors/process permissions and installation/
login acceptance remain outside those hosted checks.
The temporary full Apple release-note research input was removed after review;
only its URL/hash and relevant source-level conclusions are retained.

## Completed Pro review

The actual [Pro review](https://chatgpt.com/c/6ad58891-d4ac-83ee-9892-4acc9fc80fef)
was completed in the user's existing SunBrowser session after manual unlock.
The selected UI mode was verified as **Pro, 5 of 5** before submission. Pro checked
the three complete files against the supplied patch and matching hashes,
recommended retaining all three minimal production changes, and identified
no mandatory additional production fix. The [decision record](pro-review/decision.md)
distinguishes its source review from our executed tests.

The test-only follow-up adds real window Space/arrow dispatch, independent
focus/selection reranking, both action movement directions, audit-token-only
replacement and external field-editor shrinking/empty states. Helper executable
coverage now includes deadline rounding, worker completion and disconnect
cleanup, listener wakeup, no-activity idle exit and clearly labeled injected
EINTR paths. Existing coverage is mapped instead of duplicated. The four targeted
helper tests pass; see [helper follow-up](pro-review/helper-followup/coverage-mapping.json).

## Preservation and cleanup

All new GUI activity runs in a uniquely owned disposable ARM VM. Shared lifecycle
helpers own build workspaces, child processes, app registrations, test domains,
containers and mounts. Final evidence is retained; disposable runnable apps are
removed. Newly created Python bytecode is removed without deleting pre-existing
caches. The canonical read-only preservation check verifies the original App PID,
all 15 existing settings and absence of the owned universal build in Spotlight
and LaunchServices; it does not contact the production helper.

The development branch was pushed to run the opt-in macOS 27 validation. No
main-branch merge, new release/tag, canonical App/helper installation or system
permission change was made during this review.


## Toolchain verification follow-up

The actual SDK 27 release build exposed a `lipo` argument-parser difference after
both architectures compiled. All 14 affected build/package/verification calls now
check one required architecture per invocation. Both ARM and Intel remain
mandatory; minimum OS, signature and exact-architecture-count checks are retained.
A real Mach-O regression rejects either missing slice and malformed input; it
also covers paths with spaces and the new parser seam. Ninety affected contracts
pass, with the final refined case separately rerun. See
[lipo follow-up](pro-review/lipo-followup/verification.json).

The build-only verification signs with the configured entitlements and performs
strict signature validation. It does not run the later packaged-release canonical
entitlement comparison, Developer ID/notarization or PKG installation gates.
Those checks must not be inferred from the build-only result.
