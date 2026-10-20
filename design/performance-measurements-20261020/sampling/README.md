# Real background sampling measurements

Frozen product source: `d6b40247cd50c05af4ec9a99956c8ff1937c4894`.
Measured on 2026-10-20, macOS 26.5.2 (25F84), arm64, Swift 6.3.3,
with `-O -whole-module-optimization -swift-version 5`.

The optimized standalone CLI compiles 15 exact frozen Core files. It calls the
real `PowerObservationRuntimeController.sample(event: .normal)` on a
user-initiated serial queue. Existing dependency-injection hooks wrap the real
AppleSmartBattery/IOPS reads, health cache and helper v5 fetch to record branch
durations and call counts. All data acquisition remains real and read-only.
Only durations, availability and row counts are retained; battery percentages,
sensor values, process names, process IDs and audit tokens are omitted.

The 69.923-second host window had no concurrent benchmark compilation, VM
startup or stress test. There were 32 samples at a two-second target interval,
then three separate Process Activity reads. Health cold latency was measured
before regular samples; all 32 regular calls used the genuinely populated
production health cache. The fixed profiler reader ran exactly once in that
probe process, on an instrumented utility queue. No clock or health result was
mocked. Cold refers to an empty in-process cache, not flushed OS caches.

| Real stage | Calls | Median | p95 nearest rank | Maximum |
| --- | ---: | ---: | ---: | ---: |
| Whole runtime sample | 32 | 2.658 ms | 3.965 ms | 6.829 ms |
| Helper v5 IPC | 32 | 2.578 ms | 3.405 ms | 6.666 ms |
| Complete battery branch | 32 | 0.576 ms | 1.149 ms | 1.615 ms |
| Allowlisted registry read | 32 | 0.248 ms | 0.624 ms | 1.127 ms |
| IOPS system reading | 32 | 0.214 ms | 0.352 ms | 0.357 ms |
| Regular health-cache access | 32 | 0.958 µs | 2.000 µs | 2.375 µs |
| Process Activity | 3 | 1170.049 ms | 1187.650 ms | 1187.650 ms |

All 32 snapshots were available and all helper results were v5. Both acquisition
branches run concurrently, so stage times must not be added as serialized work.
The helper branch determines most of this measured path's latency, but the
entire acquisition runs off AppKit's event loop. This is not evidence of a
visible UI stall.

Whole sample client CPU was 0.774 ms median and 1.313 ms p95; mean CPU at a
two-second cadence is approximately 0.040% of one core. This excludes helper
and profiler child CPU. The health cold read took 215.6 ms of background wall
time and 40.7 ms of direct-child CPU; `currentPercent()` itself returned in
39.4 µs. No profiler was launched in the regular sample or hot-cache phases.
Ten batches of 10,000 real cache reads measured 25.4 ns per read median; that
hot-loop figure has different cache/scheduling conditions from periodic reads.

Process Activity returns all ten helper rows even when the UI displays Top 3.
Its approximately 1.17-second request includes the deliberate one-second
interval required to compute CPU and wakeup deltas. Client CPU was only 0.436 ms
median. Reducing the number of visible rows cannot remove that sampling
interval. The existing ten-second refresh/cache policy remains unchanged.

The canonical App PID and RSS (137840 KiB) stayed unchanged. Coarse cumulative
`ps` CPU increased by 0.06 seconds for the App and 0.15 seconds for the helper
over this window. Those processes were also serving normal product work, so
these deltas are shared-window observations, not exclusive attribution. No
installed App/helper was stopped, replaced or restarted by the harness.

## Evidence and reproduction

- `metadata.json`: environment, exact source hashes, scope and limitations.
- `measurements.jsonl`: individual real measurements with branch call counts.
- `summary.json`: distributions, cache launch counts and process continuity.
- `compiled-inputs.sha256`: exact compiled input and binary hashes.
- `warmup.jsonl`: separately marked preflight; excluded from the summary.
- `cleanup.json`: owned-process and scratch cleanup verification.
- `lifecycle-handler-checks.json`: actual cleanup handler exercised on success,
  failure, timeout and HUP/INT/TERM, with scratch and coordination files gone.

Run `bash scripts/measure_background_sampling.sh NEW_OUTPUT_DIRECTORY`. An
existing output path is rejected so prior evidence cannot be overwritten. After build
and preflight, the script writes `OUTPUT_DIRECTORY/ready` and waits at most 150
seconds. Stop other benchmarks and create `OUTPUT_DIRECTORY/go` to begin the
quiet host window. Coordination files, all children and the unique project-local
`.noindex` workspace are cleaned on success, failure, timeout and catchable
interruption using the shared lifecycle. No App bundle or preferences are used.

Thermal state and power-source state were not recorded or experimentally
controlled. One host/session, an unsandboxed CLI and 32 samples do not establish display
FPS, battery-life improvement, rare percentile tails or physical macOS 27
hardware behavior. No product behavior or performance optimization was changed
by these measurements.
