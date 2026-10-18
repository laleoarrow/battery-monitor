# Fresh native release gates with independent History clocks

Exact tested and release source:
`7f41533b017d26519a69d541d3ffd2dea587f413`.

| Gate | Result |
| --- | --- |
| Native interaction | Exit 0; 442 checks; full pass |
| Legacy interaction | Exit 0; 440 checks; full pass |
| Accessibility fallback | Exit 0; 434 checks; full pass |
| Animation stress | Exit 0; 20,000 iterations; reported elapsed 0.095 s |

The 1,316 interaction checks include the paused exact first-frame/tangent proof
and independent automatic completion on a new, never-paused production History
layer tree. All three modes pass the baseline-presentation check, finite
0.35-second stroke/fill/head configuration check, and unchanged one-second
automatic key-removal deadline. Complete presented stroke/fill paths and head
position match their model targets, and the retained midpoint keeps its
original 0.000001-point tolerance. No completion-timeout or tail-settle failure
diagnostic occurred. No production History implementation changed.

All 157 archived inputs match this exact commit and the guest before/after
execution. `accepted/release-source-identity.json` records per-file hashes.
The host and guest shared cleanup library is
`9b2a5313c1cd52a0893b2e3b0ebcc132209230d6fc66ee0255d60bcfa22c3249`.
The archive came from the immutable commit, not a later moving checkout.

The bounded diagnostic at `../../history-fixture-probe/` ran first in the same
owned ARM GUI VM and did not reproduce the hosted retained-key failure. It
does not prove the cause of that failure. The complete native gate then ran
from a separate exact-commit archive. Its logs, exit codes, source manifests,
display-policy comparison and guest resource audit are under `accepted/`.

All owned source/build scratch, child processes, app registrations, exact test
preference domains, newly created containers/Application Scripts and mounts
passed cleanup. The shared VM was deleted, the two original TestLab VMs stayed
stopped, and host snapshot scratch is empty. `accepted/shared-vm-cleanup/`
preserves the outer runner's exit 0 and VM cleanup records. Canonical app,
helper and user processes were untouched. No runnable bundles or source
archives remain in this evidence directory.

`owned-source-verification.json` was written atomically after the full gate and
cleanup. It exposes `allPassed`, exact `testedCommit`/`releaseSourceCommit`,
`guestResourceCleanupPassed`, `ownedVMDeleted`, `originalVMsStopped` and
`hostSnapshotScratchEmpty` for independent release-gate review. Earlier proofs
remain intact. Original bytes of logs with trailing-space normalization are
retained as `.raw.gz` files.

Local native validation does not replace the hosted candidate/install matrix.
The display-policy comparison covers four probe fields rather than the entire
accessibility preferences domain. Stress elapsed time is not an app benchmark.

For a fresh independent run, use the ordinary native runner with the matching
host lifecycle library and a new output directory:

```bash
bash design/release-v4.3.22/native/run-owned.sh \
  7f41533b017d26519a69d541d3ffd2dea587f413 \
  "$PWD/design/release-v4.3.22/native/after-clock-split/another-run"
```
