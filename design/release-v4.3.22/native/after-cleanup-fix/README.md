# Native release gates after the cleanup fix

Accepted source and release commit:
`d1e72bd31675121e2729f84cff37efb33fdddbeb`.

| Gate | Accepted result |
| --- | --- |
| Native interaction | Exit 0; 440 checks; full pass |
| Legacy interaction | Exit 0; 438 checks; full pass |
| Reduce Motion/Transparency fallback | Exit 0; 432 checks; full pass |
| Animation stress | Exit 0; 20000 iterations; reported elapsed 0.095 s |

The same three interaction configurations as the release workflow ran in one
new disposable ARM GUI VM. The guest archive and its cleanup library came from
the exact commit above. The host cleanup library was also checked byte for byte
against that commit before starting.

All 157 archived inputs matched before and after execution and matched the
release commit. Relative to the earlier native gate, exactly two input files
changed: `scripts/lib/local_cleanup.sh` and
`tests/test_run_preview_cleanup.py`. The earlier evidence is retained unchanged
in `../accepted/`; this run is the native release-gate evidence for the new
cleanup implementation.

Guest scratch, full-command-path processes, app registrations, test preferences
(including a 35-second observation), containers, Application Scripts and mounts
all passed cleanup checks. The owned VM was stopped and deleted; both original
TestLab VMs remained stopped. Host snapshot scratch is empty. No canonical app,
helper, socket or user process was modified.

The display-policy comparison covers the four `DisplayProbe` fields, not the
entire accessibility preferences domain. The stress elapsed time is not an app
benchmark. These local gates do not replace the hosted candidate/install matrix
or publishing gates.

Reproduce from a checkout with the matching lifecycle library, using a new
output directory:

```bash
bash design/release-v4.3.22/native/run-owned.sh \
  d1e72bd31675121e2729f84cff37efb33fdddbeb \
  "$PWD/design/release-v4.3.22/native/after-cleanup-fix/another-run"
```

See `owned-source-verification.json`, `accepted/release-source-identity.json`,
`accepted/results/gate-results.json` and the resource/VM audit JSON files.
Unmodified log bytes are preserved in adjacent `.raw.gz` files when whitespace
normalization was needed.
