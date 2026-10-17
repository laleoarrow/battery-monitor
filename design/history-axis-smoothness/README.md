# History axis motion — Wattson 4.3.16

Wattson **4.3.16 is installed and running on the maintainer Mac** from frozen
source `f818ae3e06c1fcbd69d506d7631d905a37228ce2`. The native PKG SHA-256 is
`06996376449ee6fe7c68f976bb1211543f8ad6d15d05827012f9fbcd1255f44b`.
The [installation check](host/installed.json) confirms that App and helper match
the PKG payload, both App version fields and the receipt are 4.3.16, signatures
verify, and helper health passes. Canonical PID 18025 replaced 83898 and remained
running in the later postflight. This is a local upgrade; no public release,
GitHub push, or release email was performed.

The upgrade preserves 4.3.15's approved Settings/Power artwork and battery-runtime
settling fix. Production changes for this task are confined to
`Core/HistoryChart.swift` and `Popover/HistoryLayer.swift`; other changed files
are targeted tests, VERSION, and review records. The 60-slot raw history ring,
sample cadence, Peak calculation, quantized scale, eight-second contraction
hysteresis, and 180/350 ms transition durations remain unchanged.

## Rendering change

Stroke, fill and head now use one viewport coordinate system. Removing the
moving affine layer also removes reciprocal gradient compensation and its 257
values. Gradient start/end points only animate when needed. Stroke width stays
1.6 points and the head stays 5.2 points. Stroke/fill construction shares each
cubic calculation; fill reuses the constructed open path before closing to the
baseline. Repeated input still avoids rebuilding the chart.

Retargeting captures the actual presentation curves, matches sampling intervals
and raw anchors, and carries all four cubic points into the next transition.
Queries invert the actual cubic X with bounded Newton/bisection and a verified
uniform-X fast path. Reused curves must be finite and monotone in X. The head
retains 33 base positions, adding exact raw-sample junction times only when
needed; redundant uniform keyTimes arrays are omitted.

Axis changes and interrupted curves use nine explicit path keyframes shared by
stroke and fill; ordinary translation uses a basic animation. No chart timer,
extra sampling, persistent geometry cache, or continuous redraw loop was added.
Closing, hiding, detaching, degraded readings and Reduce Motion cancel motion.

## Pro review and a corrected assumption

An early prototype and its first probe both assumed uniformly spaced cubic X.
Independent inspection disproved that assumption. Apple's installed
`CAShapeLayer.h`, lines 24–29, explicitly allows nonlinear interpolation of
off-line control points; matching topology and linear timing do not promise
Cartesian interpolation of every control point. The public API reference is
[CAShapeLayer.path](https://developer.apple.com/documentation/quartzcore/cashapelayer/path).

Pro [retracted the earlier assumption](pro/native-correction.md), suggested a
small, measured path-frame set and required independent inversion of actual X.
The [narrow closeout](pro/closeout.md) accepted the supplied e78fdf4 native results
within their error gates. Pro did not execute the tests. Final f818ae3 then
shared stroke/fill construction and repeated the complete native suite on that
exact source. Nine frames remain a measured error-control choice: native
interpolation between them is not a universal Cartesian guarantee.

Earlier small head-error reports from the shared uniform-X probe are invalid
and excluded from acceptance. The retained [red/green regression](regression/)
uses 75 independent nonuniform-X checks: old prototype 15146fe fails 40, with
maximum error 1.61204 pt; final f818ae3 fails zero, maximum 1.31e-11 pt. These
deterministic geometry results are separate from native compositor error.

## Native verification

The exact final source ran in a disposable ARM GUI VM, macOS 26.6.1. The
[485-check analysis](native/native-analysis-v4.json) passes across 18 natural
phases and ten controlled transitions sampled at 32 non-knot positions each.
The independent probe reads one presentation tree and uses its own 40-step
bisection of actual cubic X, without calling the production inverse.

- 1,358 native metric samples; maximum head/stroke deviation **0.123163 pt**, below
  the predeclared **0.15 pt** gate; sampled fill/stroke deviation **0**.
- All checked common raw intervals retain all four control points at retarget
  time within **0.001 pt**; actual X remains monotone and checked Y extrema have
  no overshoot beyond the **0.001 pt** gate.
- Real-time completion/cancellation passes. Controlled parent-clock checks test
  convergence; their paused clock is not evidence of real-time auto-removal.
- [Dense payload analysis](native/head-trajectory-analysis-v4.json) checks another
  40,950 progress values over ten transitions. This numerical analysis does not
  replace actual native presentation measurements.
- **434** production-renderer AppKit interaction assertions and **20,000**
  animation stress iterations pass, including hide, close, module reordering,
  degraded readings and Reduce Motion.
- **457 actual WindowServer frames** are retained in the compressed native
  evidence, with capture timestamps. Capture has overhead; this is not an FPS
  benchmark. Six supply states have Light/Dark top/bottom captures. The final
  charging, full, on-battery, mixed-supply, low-battery and Low Power states were
  visually inspected in twelve selected captures, alongside eight motion frames.
  [Visual review](native/visual-review.json) identifies those selections; all 24
  state captures remain in the archive. These are internal runtime validation,
  not release artwork.

This verifies position continuity (C0) and the stated fixtures/error gates.
It does not establish velocity continuity (C1), arbitrary-input exactness,
display FPS, CPU time, or energy savings.

## Preparation cost and removed work

The [frozen ABBA measurements](benchmark/paired-abba-comparison.json) time the
complete optimized production `HistoryView.update` call in the same visible
native VM window. A is dc8d0c2 (its History files match 4.3.15); B is f818ae3.
Each block has eight warmups followed by 32 measured rounds per scenario, giving
64 round medians per version. Unchanged-input rounds summarize 512 correlated
calls each. No flush, image capture or logging runs inside the timed interval.

| Update, microseconds | A1 | B1 | B2 | A2 | B pooled median | B vs A2 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Ordinary movement | 254.521 | 176.688 | 174.354 | 178.021 | 174.667 | −1.9% |
| Axis expansion | 407.980 | 226.583 | 197.021 | 264.479 | 211.979 | −19.9% |
| Axis contraction | 297.021 | 200.709 | 175.854 | 253.104 | 182.000 | −28.1% |
| Interrupted scaling | 318.917 | 191.105 | 179.459 | 261.604 | 185.458 | −29.1% |
| Unchanged input | 0.667 | 0.542 | 0.542 | 0.542 | 0.542 | unchanged |

A1 was substantially slower than A2. Pooled A/B differences are descriptive,
not a precise causal estimate; the table also exposes the comparison with the
faster final baseline block. These are main-thread wall-clock preparation
measurements including scheduling and clock reads, not CPU or compositor cost.

Separate instrumented copies count explicit `CGMutablePath` factories:
**34→18** for expansion and **35→18** for contraction/retargeting. Ordinary
movement is **3→4**, a tradeoff for shared stroke/fill coordinates. Each changing
update also makes one rectangular CGPath in both versions; no-op makes none.
The [records and injection diffs](benchmark/construction-counts.json) retain this
boundary. Zero uninjected helper counters do not mean zero helper calls, path
counts are not allocated bytes, and instrumented durations are excluded above.

## Build, install and cleanup

Full final host suites pass: **540 Swift tests**, and **601 Python tests run,
four default GUI skips, zero failures**. Separate native checks cover the relevant
GUI behavior. Universal arm64/x86_64 App/helper artifacts build and verify, and
the DMG App matches the PKG App byte for byte. The four retained installers and
their hashes are in [artifacts.json](package/artifacts.json) and project-local
`dist/history-axis-smoothness-v4.3.16`. App/helper are ad-hoc signed; PKG/DMG are
unsigned and not notarized. Public CI/distribution gates were not run.

The exact PKG also installs in the disposable VM with healthy helper. The real
App intentionally exits there because VirtualMac has no AppleSmartBattery;
the VM check records that explicit limit. Actual battery-equipped launch
stability is checked on the maintainer Mac. An initial QA health probe
half-closed a legacy request and was corrected to the current framed client
protocol; this changed no production helper code.

All visible acceptance ran in the VM without host mouse/keyboard use. The
native installer updated the authorized canonical installation in place.
The [guest audit](resources/audit-before-stop-final.json) finds no remaining
owned preferences, containers, test executables, project directories or
LaunchServices entries across 15 domains and 14 test apps. All three owned VM
leases exited zero and deleted their clones; macOS-TestLab and its Base remain
stopped. The VM's installed package fixture belonged to its deleted clone.
Final installers, review evidence and the requested host installation are
preserved. Host test registrations and mounts are checked separately.

## Evidence and reproduction

`native/results-native-paired-full-*.tar.gz` retains exact raw presentation
curves, events, captures, logs, input hashes and original source provenance.
`inputs/` retains frozen source/tool archives and manifests. Benchmark archives
include per-round values and deterministic-count diffs. `host/` retains suite,
build and installed-payload verification logs. `resources/` records ownership
and cleanup. `SHA256SUMS.txt` covers every retained evidence file.

To repeat the independent analysis without launching any app, extract the
native evidence into a new caller-owned directory, then run:

```sh
python3 tools/analyze-native-v4.py /absolute/path/to/extracted/results
python3 tools/analyze-head-trajectory-v4.py /absolute/path/to/extracted/results
```

The files under `inputs/qa-snapshot.tar.gz` are the exact one-off VM/bootstrap
and installation scripts, including the corrected and initial QA probes. Their
absolute paths describe this owned test session; they are not generic installer
entrypoints. Use the project's lifecycle helpers for any new executable run.
