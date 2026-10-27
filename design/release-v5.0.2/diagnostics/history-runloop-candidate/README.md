# Local History settling diagnostic

This directory owns a paired diagnostic on one disposable ARM GUI VM. It
reuses the original History-prefix extractor and managed VM/guest cleanup.
The global `runApplication`, production sources and original assertions stay
unchanged. Only the candidate's local `settleHistoryFixture` wait changes to
bounded run-loop slices and transaction flushes under one `started + 1` deadline.

The VM runs the original wait, candidate control and three negative controls
on the actual `history.stroke` key: infinite repetition, two-second duration,
and disabled automatic removal. All injected paths have identical endpoints.
Geometry/key observations follow an immutable verdict; they cannot convert a
timeout to success. `paired-results.json` is diagnostic evidence, not a release
gate; guest audit and host VM cleanup must also succeed after the owner exits.

```bash
bash design/release-v5.0.2/diagnostics/history-runloop-candidate/run-vm.sh \
  "$PWD/design/release-v5.0.2/diagnostics/history-runloop-candidate/paired-run-1"
```

The output directory must be new. Retained evidence includes extracted sources,
input and binary digests, native geometry/key records and lifecycle cleanup.
This extracted prefix does not replay earlier non-History suite state and does
not replace the full interaction matrix or hosted candidate gate.

`paired-run-1` did not validate the candidate: baseline and candidate both timed
out at contracted-axis. All three real-key negative controls were rejected.
Candidate/control windows reported occluded, unlike the first baseline; this
limits causal conclusions. Guest audit and VM removal confirmed no retained
resources, but the inner owner logged a defaults-delete failure. `summary.json`
preserves that error alongside the final cleanup observations.
