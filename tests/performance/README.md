# Production-renderer microbenchmark

The default only compiles and removes its temporary executable:

```bash
bash scripts/measure_renderers.sh --compile-only
```

From a frozen source checkout in a disposable logged-in macOS GUI VM,
explicitly run the benchmark (never on the user's active desktop):

```bash
bash scripts/measure_renderers.sh --run-gui 2000 > renderer-results.jsonl
```

The entrypoint owns the executable, unique preferences suite and process group;
it cleans them on success, failure, timeout and catchable interruption. Compilation
is limited to 300 seconds and execution to 120 seconds. Measurements remain on
stdout and `/usr/bin/time -l` diagnostics on stderr; the caller retains redirected
results. The harness refuses direct execution without the parent's suite.

For the 3.0.26 baseline, copy this harness, `scripts/measure_renderers.sh` and
`scripts/lib` into that checkout and omit `-D WATTSON_PERF_COUNTERS` in the copied
entrypoint (the baseline has no particle work counters).
Keep the compiler, OS, VM, optimization flags, fixtures and iteration count
identical. Alternate baseline/candidate order across at least three runs;
retain raw JSON lines and compare medians rather than a single fastest run.

Each renderer iteration uses the actual offscreen PowerFlowView, layout and
CATransaction flush. Fixed curves should avoid additional particle ride installs;
moving splits must retain their geometry updates. Settings use an isolated
UserDefaults suite that the parent removes after the run, including abnormal exit.

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
