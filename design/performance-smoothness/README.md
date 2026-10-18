# Behavior-preserving performance review

Baseline: public Wattson 4.3.19, `0ec6a855351edc99826c6f3f6060b10267d85c06`.
This is an unreleased source change. It does not update the canonical app,
installers, release tag, version, settings, visible content or functionality.

## Changes

- Process Activity skips formatting, accessibility writes and layout invalidation
  when the complete process state, normalized count and compact preference are
  unchanged. The first loading state still initializes, and appearance/layout
  callbacks remain independent of this content cache.
- Process ranking retains ten numeric candidates instead of allocating names for
  every valid PID and sorting the whole list. The original formula, filtering,
  score/PID ordering, native snapshots, wait, credentials and wire format stay
  intact. Native snapshot dictionaries reserve their known bounded capacity.
- General, Modules and sidebar icon owners retain their last resolved sRGB
  colors and contrast configuration. Repeated refreshes reuse the existing
  image; theme, material, contrast and selection colors still invalidate it.
  There is no global image cache.
- Flow and Lane gradient stop locations are initialized once. The stops, colors,
  geometry, animations and timings are unchanged. History code is untouched.

## Verification

- Before changes: 582 Swift tests passed.
- After changes: 592 Swift tests passed, including exact ranking equivalence,
  process content invalidation and Settings image reuse/pixel comparisons.
- Final default Python suite: 601 tests run, four environment skips, no failures.
  [Headless results and prior failure records](headless/validation.json) retain
  the exact commands and compressed logs. The earlier parser and blocked-stage
  failures are preserved rather than superseded by successful reruns.
- A separate local static review found no blocking runtime or macOS 12
  compatibility issue. Independent Pro feedback is recorded below.
- The periodic-gradient Python contract now reads the unchanged locations from
  initialization as well as self-qualified assignments. The blocked-support-stage
  fixture limits only its injected target to 0.5 seconds; setup retains production
  budgets, while exit code 124, the seven-second observation and cleanup assertions
  remain intact. No support collector or production deadline changes.

## Native verification and remaining gate

[Native validation](native/native-validation.json) preserves every successful and
failed run. Legacy interaction passes 436 assertions; reduced-motion interaction
passes 430. The full six-state Light/Dark Classic/Glass renderer matrix passes
6,508 assertions; compact rendering passes 2,168. The 20,000-iteration animation
stress test passes. [Eighteen image selections](native/visual-review.json) were
inspected; a suspected Ring text overlap was withdrawn after original-resolution
inspection found clean pixels with the same hash.

**The normal-motion interaction gate is partial.** Its first run passes 437
checks but fails the History matched-tail animation-key removal check after
1.074 seconds, although the presented curve has reached its target. Extracted
baseline and candidate fixtures both exhibit a different contracted-axis key
retirement timeout; the exact initial matched-tail failure is not reproduced.
Explicit commits during polling do not cure it. A flush after the fixture event
loop exits retires the keys, supporting a fixture/commit-boundary hypothesis,
without proving the root cause. No animation key is forcibly removed, no deadline
is widened, and History runtime/test code is unchanged. This is not an all-green
native gate or release acceptance.

A later [continuous-loop diagnostic](native/continuous-loop-provenance.json)
uses one narrow matched-tail sequence and fresh History instances. Both revisions,
with normal and frozen/resumed clocks, reach the complete path and head target
by approximately 0.46 seconds and remain unchanged at 0.85 and 0.98 seconds.
All four instances still have three animation keys at the first observation;
those keys retire by the second. No candidate-only or frozen-clock-only anomaly
is observed. The uninterrupted loop does not reproduce the original preceding
suite state or contracted-axis sequence. The host was unlocked for this later
run; that environment difference is not established as a cause. This evidence
shows key presence can outlive complete presented motion, without closing the
original failure or replacing the partial gate.

All four owned VM clones were deleted; process, preferences, app registrations,
containers and scratch audits pass. The original VMs, canonical host app and
system accessibility settings are preserved. Current production sources match
the [frozen candidate](native/current-runtime-equivalence.json). Captures use
fixed telemetry fixtures and do not validate physical hardware power accuracy.

## Ranking measurement

`tests/performance/perf-rank.swift` compares the original full-sort reference
algorithm with production bounded ranking in one optimized executable. It uses
the same dictionary instances, equality preflight, twenty warmups and three
ABBA rounds of 300 calls per batch, compiled with Swift 6.3.3 `-O` on ARM.

| Process counters | Full sort median, µs | Bounded median, µs |
| ---: | ---: | ---: |
| 10 | 0.583 | 0.355 |
| 100 | 5.755 | 1.773 |
| 1,000 | 65.952 | 17.591 |
| 10,000 | 909.364 | 211.822 |

These are ranking-only timings. They exclude native counter collection, the
one-second sampling interval, IPC, rendering and WindowServer. They do not
establish whole-app CPU, memory, FPS or battery-life improvements. [Raw batch
readings](ranking/rank-abba.jsonl), [summary](ranking/rank-summary.json), source
hashes and compiler identity are retained in `ranking/`.

## Production-view measurement

The same optimized AppKit harness runs against frozen baseline and candidate
source archives in one disposable ARM GUI VM (macOS 26.6.1, Swift 6.3.3,
`-O -D DEBUG -swift-version 5`). Three ABBA blocks provide six runs per revision,
with 200 warmups and 1,200 timed invocations per case/run. The table reports
the median of the six run medians, in microseconds.

| Synchronous operation | Baseline | Candidate |
| --- | ---: | ---: |
| Process update, identical input | 15.729 | 0.041 |
| Process update, changed input | 15.730 | 16.375 |
| Eleven Settings icons, identical resolved appearance | 99.104 | 26.104 |
| Eleven Settings icons, changed contrast | 98.292 | 98.605 |

The changed-input controls retain the full update work. Their candidate point
estimates increase by about 0.65 microseconds (4.1%) for Process updates and
0.31 microseconds (0.32%) for contrast changes. The AppKit harness uses DEBUG,
so changed Process input also executes the new test counter; the difference
cannot be assigned entirely to equality comparison. These small differences
are not a claim of statistically established regressions. Repeated unchanged
input benefits from avoiding the original work.
These measurements time production methods plus an autorelease pool, without
a per-call layer flush. The 41-nanosecond cached case is close to the measurement
floor. They do not measure layout/display completion, Settings opening, frame
delivery, sampling or whole-app resource use. Sidebar artwork is verified by
focused tests but is not part of the eleven-icon timed batch.

[Production-view results](native/benchmark-summary.json), the harness, analyzer,
compressed raw readings and source identities are retained in `native/`.

The [independent Pro review](pro/review.md), performed in the user's preferred
SunBrowser session with Pro selected, found no concrete runtime must-fix under
the supplied contracts. It retains the normal-motion gate as partial and the
measurement limits above. Broader artifacts and private UI evidence are under
`.build/performance-smoothness-review.noindex/`. This is not release approval.
