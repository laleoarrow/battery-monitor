# Production-renderer microbenchmark

Run in a disposable logged-in macOS GUI VM, not the user's active desktop.
From a frozen source checkout:

```bash
xcrun swiftc Core/*.swift Popover/*.swift tests/performance/main.swift \
  -O -D DEBUG -D WATTSON_PERF_COUNTERS \
  -framework AppKit -framework CoreGraphics -framework IOKit \
  -o /tmp/wattson-render-benchmark
/usr/bin/time -l /tmp/wattson-render-benchmark 2000
```

For the 3.0.26 baseline, copy this harness into that checkout and omit
`-D WATTSON_PERF_COUNTERS` (the baseline has no particle work counters).
Keep the compiler, OS, VM, optimization flags, fixtures and iteration count
identical. Alternate baseline/candidate order across at least three runs;
retain raw JSON lines and compare medians rather than a single fastest run.

Each renderer iteration uses the actual offscreen PowerFlowView, layout and
CATransaction flush. Fixed curves should avoid additional particle ride installs;
moving splits must retain their geometry updates. Settings use an isolated
UserDefaults suite that is removed after the run.

This measures synchronous update/commit cost, not display FPS, WindowServer
frame delivery, sensor I/O, whole-app CPU, RAM reduction or battery life.
It does not benchmark sampling cadence; that has deterministic regression tests.

## Native popup and theme latency

`scripts/measure_ui_latency.sh --compile-only` verifies the optimized UI harness
without opening a window. In a disposable logged-in GUI VM, run
`scripts/measure_ui_latency.sh --run-gui NEW_OUTPUT.jsonl`; the entrypoint owns
its temporary app, unique preferences suite, container and process cleanup.

The default is 20 warm reopens per Classic/Regular/Clear host, with three
additional recorded warmups. `WATTSON_PERF_COLD_COUNT`,
`WATTSON_PERF_WARM_COUNT` and `WATTSON_PERF_THEME_COUNT` select 0–200 samples;
zero skips a case. A cold sample means a new controller in the same process,
not a new process or cleared system caches. The fixed popup fixture theme is
`WATTSON_PERF_COLOR_SCHEME=system|light|dark` (default `dark`); this never changes
the system appearance. Theme-switch results are summarized by target direction.

`WATTSON_PERF_SUBMISSION=forced` (the default) measures an explicit
layout/display/CA submission; `natural` adds no harness submission. Both retain
the continuous `NSApp.run` loop. Window visibility, presentation-layer existence
and effective appearance are software observations, not physical display-frame
delivery. Entrance-key retirement is observed for at most three seconds;
unobserved completion is retained as censored with null completion latency and
window/layer/clock diagnostics. Native close must still remove the key.

Keep independent process runs separate when comparing A/A noise or ABBA source
revisions; individual events within one run are not independent cold starts.
