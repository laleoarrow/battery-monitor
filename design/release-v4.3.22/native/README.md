# Wattson 4.3.22 native release gates

The accepted run uses the exact tracked inputs from
`b51e12bc87364a8f7ede342302bc5682b3e53c95`. All 157 archived source, test,
script and asset files are byte-identical to release source commit
`fdf6d96d30d30e0aaee709fa8696ce980ea19100`; see
`accepted/release-source-identity.json` and `accepted/frozen-source-inputs.sha256`.

One disposable ARM macOS GUI VM ran the existing release workflow matrix:

| Gate | Result |
| --- | --- |
| Native interaction | Exit 0; 440 checks; `ALL_INTERACTION_CHECKS_PASSED` |
| Legacy control interaction | Exit 0; 438 checks; `ALL_INTERACTION_CHECKS_PASSED` |
| Reduce Motion/Transparency fallback | Exit 0; 432 checks; `ALL_INTERACTION_CHECKS_PASSED` |
| Animation stress | Exit 0; 20000 iterations; reported elapsed 0.097 s |

The three interaction variants use the same environment overrides as
`.github/workflows/macos-helper-install.yml`. A skipped suite, timeout, nonzero
exit or missing full-pass marker fails the gate. No test or production source
was edited for this run. The stress elapsed time is a test result, not an app
performance benchmark.

The guest verified all 157 input hashes before and after the tests. Its existing
test entrypoints use the shared lifecycle helper. The outer runner then checks
full process command paths, LaunchServices registrations, exact test preference
prefixes, containers, Application Scripts and mounts; it observes preference
files for 35 seconds after cleanup. All checks passed. The owned VM was stopped
and deleted, both original TestLab VMs remained stopped, and host snapshot
scratch was removed. No canonical app/helper was installed, and no live user
process was involved.

The display-policy before/after comparison covers the four fields recorded by
`display-probe.swift`; it is not a snapshot of the entire accessibility
preferences domain. Overrides affect only the test processes. No privileged
install, notarization, hosted install matrix or GitHub publishing is claimed by
this local gate.

Reproduce from the project root with a new output directory:

```bash
bash design/release-v4.3.22/native/run-owned.sh \
  fdf6d96d30d30e0aaee709fa8696ce980ea19100 \
  "$PWD/design/release-v4.3.22/native/another-run"
```

The runner uses `git archive` and never builds the moving working tree. It owns
its VM, source snapshot, process groups and guest scratch on success, failure,
timeout and catchable interruption. Final logs, manifests and audit JSON remain.
Original log bytes are preserved in adjacent `.raw.gz` files when trailing
whitespace is normalized.

`attempt-1-runner-argument-order/` preserves an initial QA wrapper failure before
any test started: the custom runner requires `--grace` before `--timeout`.
The first VM was also deleted and the original VM states preserved. This was
corrected in the QA wrapper before the accepted run.
