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
