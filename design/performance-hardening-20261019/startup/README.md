# Startup battery acquisition measurement

The synchronous first `BatterySampler.sampleResult()` call was measured in 24
fresh, optimized command-line processes on arm64 macOS 26.5.2 (25F84), Swift
6.3.3. Each process made exactly one acquisition on its main thread; process
starts were spaced at least two seconds apart. The probe compiled only the
production `PowerSnapshot.swift`, `BatterySampler.swift`, and
`BatteryRuntimeEstimate.swift` with `-O -whole-module-optimization`. The exact
input hashes and source commit are in `metadata.json`.

| First-call API elapsed time | Milliseconds |
| --- | ---: |
| First process | 1.306 |
| Minimum | 0.807 |
| Median | 1.024 |
| p95, nearest rank | 1.898 |
| Maximum | 7.527 |

All 24 calls produced a valid snapshot; none exceeded the 16.67 ms budget for
60 Hz or the 8.33 ms budget for 120 Hz. Median process CPU consumed inside the
measurement was 0.598 ms (maximum 1.266 ms). The larger wall-time outlier may
include scheduling or service latency; this experiment does not attribute its
cause. These results do not justify moving the startup read into a new
asynchronous state machine. No production code was changed for this candidate.

This measures the first sampler API call in each process, not total process
launch, dyld initialization, NSApplication startup, status-item construction,
or time to first visible frame. OS/IOKit caches were not flushed. The CLI is
unsandboxed and has a smaller image than the app. This is one host/session with
uncontrolled background load, and is not a macOS 27 compatibility result.

`measurements.jsonl` retains every measurement, `summary.json` the calculation,
and `build.log` the compiler output. The probe emits no battery readings. The
installed Wattson remained running with the same PID. No helper calls, app
registration, test preferences, containers, or GUI launches were performed.
`cleanup.json` confirms the shared owned-process runner exited successfully,
no owned probe processes or scratch remained, and its empty scratch parent was
removed.

To repeat this read-only measurement from the project root:

```bash
/bin/bash design/performance-hardening-20261019/startup/run.sh
```

The runner bounds compilation and collection, owns its executable/module-cache
scratch through `scripts/lib/local_cleanup.sh`, and stops child processes on
failure, timeout, or catchable interruption. Evidence files are intentional
retained outputs. A repeat replaces this directory's measurement outputs.
