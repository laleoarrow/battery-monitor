# History performance — Wattson 4.3.11

This local upgrade reduces History's update preparation work while retaining
the 4.3.10 presentation-based axis transitions. Raw readings, Peak, the 60-slot
ring, sampling cadence and animation policy remain unchanged.

The implementation emits the final stroke directly, without intermediate
geometry, unused fills or transformed path copies. When the actual captured
viewport has `scaleY == 1`, matched cubic path endpoints use `CABasicAnimation`.
Any other scale retains 33 stroke keyframes. Head and gradient retain their
existing 33 and 257 keyframes. No timer, polling loop or persistent cache was
added. Multiple disconnected runs retain their separate subpaths.

[Pro's two reviews](pro-review.md) informed the strict scale condition and the
interpretation of the measurements. Its follow-up identified no new concrete
History blocker from the supplied summary, while retaining the integration and
native acceptance gates. It did not independently execute the candidate.

## Measured preparation work

The [ABBA report](benchmark/RESULTS.md) compares unmodified production renderers
`27b069e704f9` and `9325876f70dc` in one disposable ARM GUI VM, using the same
frozen harness, optimized compilation and visible `NSWindow`. Each version has
128 measured round medians per scenario, after eight warmups per run/scenario.

| Update | Baseline median, µs | Candidate median, µs | Change |
| --- | ---: | ---: | ---: |
| Ordinary scrolling | 307.8 | 220.1 | −28.5% |
| Axis expansion | 342.6 | 366.0 | +6.8% |
| Axis contraction | 371.5 | 255.9 | −31.1% |
| Interrupted scaling | 386.6 | 316.9 | −18.0% |
| Unchanged input | 0.625 | 0.625 | unchanged |

These are descriptive main-thread wall-clock preparation measurements, including
scheduling and clock reads. There is substantial variation between runs; axis
expansion did not improve. They do not establish CPU time, compositor cost,
display FPS or energy savings. No-op calls within a round are correlated.

Separate instrumented copies counted explicit `CGMutablePath` constructions:
ordinary scrolling **136 → 3**, expansion **136 → 34**, contraction and retargeting
**144 → 35**. Each non-noop update also constructs one rectangular `CGPath` in
both versions. Counts are not allocated bytes, and instrumented timings are
excluded from the timing comparison. Original records, hashes and the injection
diff are retained in the [benchmark evidence](benchmark/README.md).

## Native verification

Native verification uses the production source from `855fc308f886`; the later
`d95bb63e988d` change only redirects an interruption test's child output to its
fixture-owned log, avoiding an undrained-pipe deadlock. It changes no production
code or timeout. Full host and final installation evidence are recorded below
when complete.

The native run includes 434 AppKit interaction assertions, 20,000 animation
stress iterations and twelve real WindowServer captures covering charging,
full, on-battery, mixed supply, low battery and Low Power in Light and Dark.
The revised natural-run scalar pass has 376 passing checks across eighteen
phases; the original eleven phases also pass their 33 baseline-comparison
checks. In that corrected pass, maximum sampled head-to-stroke distance is
0.07598 pt and gradient-band drift 0.00402 pt; the original eleven phases remain
within their predeclared baseline-plus-0.05-pt comparison allowance. These are
sampled geometric observations, not pixel identity.

The first eighteen-phase pass retained two failed generic total-phase duration
checks, which included preparation and two animations. A narrower driver
separated preparation from the retarget deadline. Its natural timer still did
not reach five of six requested 25/50/90% interruption points within the preset
fraction gate; those records remain failures of that fixture's timing coverage.
An additional **synthetic** native-presentation test freezes only the test parent
layer's local clock. Its 57 checks pass at the requested fractions, with maximum
recovered progress error 0.00000873, and verify raw anchors, cubic interiors and
endpoint continuity. Production source is unmodified. This deterministic test
does not establish natural-time fraction coverage or frame rate.

The [native evidence](native/README.md) keeps the distinct runs, tools and
limitations separate. Real recordings use measured frame timestamps, without
invented frames; capture cadence is not product display FPS.

The full host regression completed with **535 Swift tests** and **599 Python
tests, four skipped**, with zero failures. [Host verification](host/verification.json)
retains the final logs and the interruption-fixture diagnosis. Subsequent
build-entrypoint checks and final Modules acceptance are recorded separately.

The [resource audit](resources/first-session-resource-audit-summary.json) found
all twelve owned test preference domains and ten temporary app paths absent,
including registrations, processes, staging directories and mounts, immediately
and again after 158 seconds. The benchmark/native VM exited zero and was deleted;
the other chat's VM and the originally stopped TestLab VMs kept their states.

## Integration and installation

Modules ordering and the Ring Gauge icon are coordinated with their owning
chat and share the same candidate version. Their acceptance evidence lives in
[Modules reordering](../settings/modules-reordering/README.md).

This is a local candidate and installation workflow. It does not publish a
GitHub release or substitute for the public exact-SHA CI and hosted platform
matrix described in the repository release guide.
