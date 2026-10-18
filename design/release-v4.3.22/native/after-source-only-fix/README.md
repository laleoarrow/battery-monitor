# Native release gates after the source-only cleanup fix

Accepted source and release commit:
`67b3f60138074823857a3f86f4d517c87f2ac9e2`.

| Gate | Result |
| --- | --- |
| Native interaction | Exit 0; 440 checks; full pass |
| Legacy interaction | Exit 0; 438 checks; full pass |
| Reduce Motion/Transparency fallback | Exit 0; 432 checks; full pass |
| Animation stress | Exit 0; 20000 iterations; reported elapsed 0.102 s |

The previously failing matched-tail assertion passes in all three modes, with
no completion timeout or tail-settle failure diagnostics. The one-second
deadline, exact geometry and automatic key removal checks remain intact.

All 157 archived inputs match the frozen release commit and match before and
after execution. Relative to the prior native run, only the cleanup library and
two Python test files changed among those inputs; the separate workflow change
is recorded in `accepted/release-source-identity.json`. No production AppKit,
History, process palette or helper implementation changed. Host and guest use
the fixed cleanup library with SHA256
`9b2a5313c1cd52a0893b2e3b0ebcc132209230d6fc66ee0255d60bcfa22c3249`.

One owned ARM GUI VM ran the existing three release interaction configurations
and animation stress. Full-command-path processes, scratch, app registrations,
test preferences (including 35 seconds of observation), containers, Application
Scripts and mounts all passed cleanup. The VM was deleted, both original
TestLab VMs remained stopped, and host snapshot scratch is empty. Canonical
installations and user processes were untouched. Earlier evidence is preserved.

`owned-source-verification.json` is written atomically only after the complete
gate and cleanup checks pass. It includes top-level `allPassed`, exact
`releaseSourceCommit`, `guestResourceCleanupPassed`, `ownedVMDeleted`,
`hostSnapshotScratchEmpty` and the preserved VM-state checks.

Local native gates do not replace the hosted installer/candidate matrix. The
display-policy comparison covers only the four `DisplayProbe` fields; stress
elapsed time is not an app performance benchmark.

Reproduce with a matching host lifecycle library and a new output directory:

```bash
bash design/release-v4.3.22/native/run-owned.sh \
  67b3f60138074823857a3f86f4d517c87f2ac9e2 \
  "$PWD/design/release-v4.3.22/native/after-source-only-fix/another-run"
```

Full logs, source manifests, matched-tail results and cleanup reports are under
`accepted/`. Original bytes of normalized logs are retained in `.raw.gz` files.
