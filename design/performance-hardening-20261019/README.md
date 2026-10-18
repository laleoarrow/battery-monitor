# Performance and boundary correctness review

Production/test source is frozen at `df7d4bcbeb0200e6ee5001182d92f62229aba88f`,
after the public 4.3.22 source and its release-evidence commit `9ab0c43`.
The three production changes preserve the existing feature set, presentation,
sampling formula, cadence, permission model, helper protocol and deployment
target. This is an unreleased source change, not a canonical installation.

## Evidence-backed changes

| Change | Reproduced problem | Verification |
| --- | --- | --- |
| Refresh action appearance only when `isEnabled` changes; remove the extra per-reading refresh. | Identical enabled assignments replaced the glyph; the row update still replaced it even with the button guard. | The original button fails six image-identity assertions. The original row path, tested with the button guard already present, fails nine. Fixed button/view classes pass all 38 tests, including actual enabled-state action, tint, appearance and accessibility updates. Score and bar changes still occur while image identities remain stable. This measures avoided work, not an app-wide speedup. |
| Preserve owned row/button keyboard focus by full process identity across ranking changes. | The actual first responder stayed in the old physical row while selection followed process A; Space then selected B. The native button, Compact, removal and Top N cases also exposed stale focus. | The independent baseline keeps `allPassed:false`. Fixed-source v2 passes all 34 actual-window checks, with no unexercised native-button path. Same-PID replacement, identity loss, unselected focus, surviving-identity Top N fallback and external field editors are included. Persistent regression coverage was added to the standard interaction harness. All termination handlers are mocked. |
| Use a 100 ms poll wait when idle time has expired but a background worker remains pending and no reader owns a deadline. | A deliberately blocked sampling lock causes the original helper to poll with zero timeout tens of thousands of times per quarter second. | The new executable assertion fails on the original function and passes on the fix; all 53 helper contracts pass. A production-function comparison falls to three polls per roughly 303 ms. Reader priority, round-up/clamping, 12-second idle lifetime and exit predicate remain unchanged. The worker writes its response independently, so only eligible idle-exit checks can be delayed by up to 100 ms. This is a defensive edge case, not proof of ordinary runtime overhead. |

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

Full host checks pass: **664 Swift tests**, **608 Python tests with four expected
interaction skips**, and the release build for **arm64 + x86_64**, including
signatures, entitlements and the macOS 12 deployment target. Logs and exit codes
are in `integration/`. The three GUI variants execute **1,358 passing checks**,
plus the independent 34-check focus probe and 20,000-iteration animation stress
test. An existing close/reopen timing path remains qualified because the system
completed closing synchronously; it is not counted as exercised. All new native
focus paths were exercised. Native reports and cleanup proofs are kept separately.

The host is macOS 26.5.2 / SDK 26.5; the owned GUI VM reports 26.6.1.
The [macOS 27 source review](compatibility/README.md) found no demonstrated
regression requiring a speculative patch. A 27 SDK build and 27 runtime checks
for glass, input, real sensors/process permissions and installation/login
lifecycle remain pending. No zero-bug or macOS 27 acceptance claim is made.
The temporary full Apple release-note research input was removed after review;
only its URL/hash and relevant source-level conclusions are retained.

## Pro handoff

Actual Pro review is **not yet performed**. SunBrowser app inventory reported
the Mac was locked; a manual-unlock request is pending. No alternative browser
account was used and no Pro response was invented. The bounded review prompt
and explicit submission status are in [pro-review](pro-review/status.json).
After unlock, verify the running SunBrowser and selected Pro mode, submit the
prepared prompt, assess its advice against the source, and rerun affected
checks if another change is warranted.

## Preservation and cleanup

All new GUI activity runs in a uniquely owned disposable ARM VM. Shared lifecycle
helpers own build workspaces, child processes, app registrations, test domains,
containers and mounts. Final evidence is retained; disposable runnable apps are
removed. Newly created Python bytecode is removed without deleting pre-existing
caches. The canonical read-only preservation check verifies the original App PID,
all 15 existing settings and absence of the owned universal build in Spotlight
and LaunchServices; it does not contact the production helper.

No source changes were pushed, no new release/tag was created and no canonical
App/helper installation or system permission was changed during this review.
