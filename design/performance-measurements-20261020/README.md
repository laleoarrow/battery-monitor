# Wattson measured performance review — 2026-10-20

Scope: measure popup opening, background acquisition, and theme changes before
choosing an optimization. Preserve the existing UI, functions, cadence, and
canonical 5.0.0 installation. The current-source baseline is frozen at
`d6b40247cd50c05af4ec9a99956c8ff1937c4894`.

Accepted product change: avoid redundant appearance refreshes while assembling
a Glass popup from detached content. Independent-process ABBA reduces the
synchronous warm-open median by about 30–32 ms in the tested opposite-theme
condition. System/matching-Light controls show no consistent regression;
463 native GUI assertions and the exact-product macOS 27 compatibility gate
pass. Sampling cadence, UI, functions and the canonical installation are
preserved. The detailed scope and contrary observations remain below.

The existing signed-in SunBrowser Pro conversation reviewed the measurement
design: <https://chatgpt.com/c/6ad73e62-83a8-83ec-91e6-8dfd8d374842>.
Pro's review is independent advice; the local evidence below is produced on
macOS, not by the remote reviewer.

## Background acquisition

See [raw data, source hashes, protocol and cleanup](sampling/README.md).
The optimized probe executes the real observation runtime, IOKit/IOPS, the
installed read-only helper, and the default health reader on this physical Mac.
There are 32 observations at the normal two-second cadence; all returned
available snapshots and used helper v5.

| Stage | Median | p95 |
| --- | ---: | ---: |
| Complete acquisition wall time | 2.658 ms | 3.965 ms |
| Probe CPU per acquisition | 0.774 ms | 1.313 ms |
| Helper request branch, including sensor work | 2.578 ms | 3.405 ms |
| Battery branch | 0.576 ms | 1.149 ms |
| Periodic health cache read | 0.958 µs | 2.000 µs |

The health command runs asynchronously: its cold execution took 215.642 ms,
while the initiating cache call returned in 39.417 µs. Exactly one health
command ran, and none ran during the 32 periodic acquisitions. Three independent
Top Processes requests took a median 1170.049 ms, including the intentional
one-second observation window. Changing Top N does not shorten that window.

The derived client acquisition CPU use is 0.040% of one core at this cadence.
This is not whole-app CPU or exclusive helper CPU: the canonical app continued
its normal work during the probe. Thermal and power conditions were not
controlled or recorded. These measurements do not justify changing acquisition
or its observation window.

## UI protocol and retained failures

The UI harness uses optimized production AppKit controllers and fixed readings
inside an owned disposable ARM GUI VM. It drives the normal application run
loop, uses isolated preferences and bundle identifiers, and leaves the installed
App/helper untouched. It skips external helper refreshes and therefore measures
the controller path, not the complete physical menu-bar click path.

Cold-controller construction means a new controller in an already-running
process. Warm Glass opening retains the content but builds a new panel. Neither
is a measurement of process launch or physical display latency.

`call_ms` is synchronous controller time. Forced layout/display/CA submission
is a separate cumulative software boundary. A visible window and presentation
layer are software observations, not a captured physical first frame or FPS.
The named entrance animation's key retirement is also separate from visibility
and from continuous module animations.

- [Smoke run](ui-baseline/smoke-1/manifest.json) completed all host/case groups.
- [Full v1 run](ui-baseline/full-1/manifest.json) completed Classic, then stopped
  after a three-second entrance-key retirement observation timeout in Glass.
  Its partial raw data and failure are retained; it is not a completed matrix.
- [First attempted attribution](ui-attribution/run-1/manifest.json) is invalid
  as attribution: the wrapper's background process received empty patch stdin,
  so no diagnostic checkpoints were installed. The original matrix ran instead
  and encountered the same observation boundary. Its data and cleanup are
  retained, and are not represented as diagnostic results.

The v2 harness records an unobserved animation-key retirement as censored/null,
with window/layer/clock diagnostics, while retaining the controller and software
visibility timings. Actual window closure and animation cleanup remain required
between samples. Diagnostic patches use a named input file and must prove their
checkpoints and executed cases before collecting results.

Classic's completed v1 subset has 30 cold-controller and 60 warm observations:
warm call median/p95 4.91/5.99 ms and software visibility 7.71/9.08 ms. Popup theme
calls have median/p95 15.98/19.76 ms; the forced-submission appearance observation
is 32.08/38.08 ms. These are partial baseline results, not a before/after gain.

The valid [diagnostic run](ui-attribution/run-2/attribution-summary.json) has
20 measured warm opens per host, all completed, with no entrance endpoint
censoring. Median synchronous calls are 4.840 ms Classic, 66.678 ms Regular,
and 66.463 ms Clear. For Regular, panel initialization is 29.407 ms, including
27.975 ms for background creation/content attachment; positioning the arrow,
applying appearance, and installing callbacks together take 13.061 ms;
ordering the window front takes 11.412 ms. The combined positioning/appearance
stage does **not** isolate the appearance setter. Material hosting initialization
itself is only 0.185 ms and is not the observed bottleneck. Nested stages are
not additive to their parent. The [stage accounting](ui/attribution/run-2-stage-accounting.json)
closes to within 0.018 ms of the complete call.

The v3 [natural A/A run](ui-baseline/aa-v3-dark-1/aa-summary.json) measures two
independent processes using the same baseline and harness, 20 warm opens per
host per process, plus six theme alternations per surface. The actual app
inherits Aqua, with no application override, and the popup explicitly requests
Dark. Median open calls in process 1/2 are Classic 5.002/4.806 ms, Regular
67.377/67.982 ms, and Clear 67.452/68.943 ms. The corresponding Glass median
drifts are 0.605/1.490 ms. This is a noise screen with two process clusters,
not a confidence interval or a precise tail-latency estimate.

Process 2 retains 6/20 Regular and 8/20 Clear entrance-key retirement censored
endpoints; call and software visibility timings remain available, and all
subsequent closes passed the original host/key cleanup conditions. Censored
records include active MainActor polls, advancing CA clocks, visible windows,
and presentation opacity 1. They do not prove physical animation or frame
delivery, and are not recoded as zero or three-second completion times.

## Candidate screening rule

Before the A/B run, the sole product candidate is frozen at
`2248c8ec8f4d4a55f1cddd69506d83135117c561`: pass the existing optional appearance
into the new panel before attaching its children; retain System as nil and keep
the existing live-theme observer and host teardown. This is an experiment, not
an accepted optimization. [Pro's supplied-data review](pro-data-review.json)
supports this conditional experiment and recommends keeping acquisition and
Settings traversal unchanged.

Use natural observation and independent processes. First measure the same
baseline twice, then compare baseline/candidate/candidate/baseline with the
same frozen harness, fixture, scheme, and VM. Treat each process as a cluster;
do not present individual opens as independent process launches.

For this screening round, require both candidate process medians to improve the
complete open call by at least 3 ms and by more than the observed A/A median
drift. This is a practical acceptance threshold, not a statistical minimum
detectable effect or a display-frame guarantee. Inspect p95, software-visible
observations, theme directions, completion/censor counts, and reversed temporal
order as well; a displaced cost or material regression rejects the candidate.
System and matching explicit appearance are separate controls if the main
experiment shows a benefit. A candidate without clear net benefit is withdrawn.

### Appearance-only candidate rejected

The completed A1/B1 screen in [the attempted ABBA run](ui-comparison/dark-abba-1/screening-decision.json)
has Regular median call 65.878 → 66.984 ms and Clear 65.684 → 67.466 ms.
It fails the predeclared minimum net saving, so the remaining run was stopped
during B2. The ABBA matrix is explicitly incomplete. Original and partial data
are preserved; exit 143 is an operator termination, not a product test failure.
Only the owned VM was stopped/deleted, and the two pre-existing VM states were
preserved. This interrupted run did not finish the guest's delayed audit;
deleting the entire disposable clone disposed of its guest resources.

The candidate is withdrawn by commit
`e25ca2f` and is not an accepted runtime optimization. Its System/Light controls
and interaction acceptance were canceled because there was no performance
benefit to accept. The next bounded diagnostic examines whether attaching the
foreground to the hidden window before attaching the existing content avoids
an intermediate windowless-parent refresh. It keeps the original late appearance
assignment, isolating the attachment order rather than combining hypotheses.

### Attachment order alone rejected; interaction identified

The [paired source-copy diagnostic](ui-attribution/run-3-move/move-attribution-summary.json)
compares original assembly with foreground-first assembly, retaining late
appearance assignment. Each host/variant has 20 measured opens. Regular median
call changes 66.383 → 66.058 ms and Clear 66.006 → 65.823 ms, below A/A drift.
Neither variant reduces the three appearance refreshes. This candidate was not
applied to production.

The [event timeline](ui/attribution/run-3-event-timeline.json) places the nil-window
effective-appearance callback inside content attachment in all 80 Glass traces;
there are no nil-window move callbacks. Even after attaching the empty foreground
to the window, the child receives Aqua during its attachment, before its window
pointer is established. The subsequent window move uses Aqua, then late window
appearance changes to Dark. This provides a specific interaction hypothesis:
both the target window appearance and the windowed parent must be ready before
attaching the existing content.

The [combined diagnostic](ui-attribution/run-4-combined/combined-attribution-summary.json)
tests exactly those two conditions together, retaining the final same-value
appearance assignment. It is one instrumented process, not the final A/B result.

| Host | Original call median | Combined call median | Original/combined p95 |
| --- | ---: | ---: | ---: |
| Classic control | 4.489 ms | 4.664 ms | See raw summaries |
| Glass Regular | 69.878 ms | 36.784 ms | 72.969 / 40.895 ms |
| Glass Clear | 66.022 ms | 36.819 ms | 71.654 / 40.177 ms |

Both Glass variants reduce three refreshes to one in every measured open: the
combined path has one attached Dark refresh and no intermediate Aqua/nil-window
appearance refresh. Panel initialization and the late setter both decrease;
arrow positioning remains below 0.03 ms. [Independent accounting](ui/attribution/run-4-combined-analysis.json)
checks all 120 measured traces; their complete calls and exclusive stages close
within 0.041 ms. Nested callback times are not added to those stages.

### Combined product candidate

Frozen candidate `5d5391a96aa9465eb1beaa3bf6bcb2bea1208067` applies early optional
window appearance and foreground-first attachment only for detached content.
An input still attached to another window retains the original windowless-parent
transition, protecting the existing History/selection cleanup. There is no panel
cache, synthetic lifecycle callback, additional reset, child appearance override,
or animation change. System remains nil; live theme propagation is unchanged.

The local Swift suite passes 701 tests, including both materials in a real
hidden-window live transfer test: selection clears before an identical-state
update, and a late old force-quit button action cannot submit a request. The
separate default Python run passes 631 tests with four expected opt-in skips.
Those Python results precede the final combined source change; CI must verify
the final source/contracts before acceptance.

The host's [read-only saved preference observation](host-theme-observation.json)
is Glass Regular/System with global Dark. It is not an effective-appearance
measurement. The main opposite-theme experiment is not a claim about this
current configuration; System/matching-theme controls remain required.

Pro's [combined-source review](pro-final-candidate-review.json) found no specific
substantive objection to the conditional live-window fallback. It requested a
positive control for the regression test; the strengthened test proves the old
button is enabled, visible and dispatches the mock action before transfer, then
rejects it after transfer. Its separate rerun passes. Pro reviewed source and
supplied measurements, without executing macOS or independently measuring this
Mac.

### Exact-source uninstrumented ABBA

The [complete natural ABBA](ui-comparison/dark-combined-abba-1/abba-summary.json)
compares baseline `d6b4024` with exact product candidate `5d5391a`, using the
same frozen v3 harness. Four independent processes execute A1–B1–B2–A2;
each process has 20 measured warm opens per host and six theme alternations per
surface, after three warmups. All four blocks complete 132 measured observations.

| Host | A1 call median | B1 call median | B2 call median | A2 call median |
| --- | ---: | ---: | ---: | ---: |
| Classic control | 5.995 ms | 4.846 ms | 4.359 ms | 4.808 ms |
| Glass Regular | 67.844 ms | 37.881 ms | 38.033 ms | 68.319 ms |
| Glass Clear | 68.401 ms | 37.473 ms | 37.176 ms | 69.607 ms |

Both independent B processes save at least 29.8 ms for each Glass material,
exceeding the predeclared 3 ms screen and the earlier A/A median drift. The
reversed order retains the gain. Classic code was not changed; its smaller
variation is a control, not an attributed improvement.

The following pooled observations summarize 40 warm opens per source/material;
the independent replication unit remains the process, not each opening.

| Host | Call median A → B | Call p95 A → B | Software-visible layer median A → B |
| --- | ---: | ---: | ---: |
| Glass Regular | 68.319 → 38.033 ms | 73.427 → 42.271 ms | 78.246 → 47.055 ms |
| Glass Clear | 69.166 → 37.473 ms | 73.575 → 45.455 ms | 79.213 → 45.806 ms |

This is approximately 44–46% less synchronous warm-open work under the tested
opposite-appearance condition: the app inherits Aqua and the popup requests
Dark. All 40 measured popups per source/material reach Dark. Cold-process
launch, physical frame delivery, whole-app CPU and power consumption were not
measured by this comparison.

All 288 theme changes retain controller/view identities and reach the requested
Light/Dark appearance. There are only three observations per direction, surface
and process. No direction shows a repeatable candidate setter regression above
3 ms; this is not evidence of faster theme switching. Software appearance-poll
timings vary: Regular Modules→Light medians are 11.055/7.553 ms in A1/A2 and
23.246/24.954 ms in B1/B2, while their setters remain approximately 3.7–4.2 ms
and the Settings path is unchanged. This small fixture does not identify a
physical visual regression or justify a Settings optimization.

Entrance-key retirement
is censored in 8/40 baseline Regular, 7/40 baseline Clear, 0/40 candidate Regular
and 7/40 candidate Clear observations. These endpoints remain null, with raw
window/layer/clock diagnostics. Uncensored key-removal medians are later in B
(Regular 494.915 → 524.525 ms; Clear 493.086 → 561.519 ms), but come from unequal
observed subsets and drift across process order. They do not establish either
faster animation or an unchanged physical animation duration. Every actual close
clears its window and animation key.
The delayed filesystem audit passes after 37.7 seconds, the owned clone is
removed, and both original VM states are preserved.

### Controls and behavior acceptance

The [short controls](ui-comparison/system-light-controls-1/controls-summary.json)
use the same baseline/candidate source and v3 harness. System A/B then matching
Light A/B each run in separate processes, with eight warm opens per host. Both
the application and resulting popup actually use Aqua. These single-pair, small
controls screen for regression; they do not estimate a universal theme benefit.

| Scheme/material | Baseline call median/p95 | Candidate call median/p95 |
| --- | ---: | ---: |
| System Regular | 36.173 / 39.457 ms | 35.199 / 38.550 ms |
| System Clear | 35.304 / 49.779 ms | 35.995 / 38.488 ms |
| Light Regular | 35.060 / 57.737 ms | 37.432 / 37.900 ms |
| Light Clear | 35.273 / 39.432 ms | 34.187 / 37.210 ms |

System differences are below 1 ms. Light Regular's median increases 2.372 ms,
while its p95 decreases and Clear improves; this does not show a consistent
cross-material regression. One candidate Light/Clear entrance-key endpoint is
censored; all others complete. The original closes and final appearance checks
pass. These controls do not measure the physical host's current System/Dark
configuration.

After timing finishes, the exact candidate runs the existing
`scripts/verify_interaction.sh` in the GUI VM: **463 assertions pass, zero fail**.
It exercises actual native windows, theme propagation, close/reopen, History
transition cancellation, preserved layout/readings, process actions, and removal
of cross-host listeners. The final delayed audit passes after 37.7 seconds and
the owned clone is deleted. The [final VM audit](vm/final-owned-cleanup.json)
records no owned clone or scratch remaining and both original VMs stopped.

The independent raw-data review confirms the ABBA saving against even the
fastest A process, and finds no new candidate-specific entrance censor increase.
The retained key-retirement limitations above prevent a physical animation
speed or FPS claim. No animation constants, sampling/Top Processes window,
Settings traversal, panel cache, or feature behavior are changed.

### Verification and installation boundary

The [macOS 27 CI gate](https://github.com/laleoarrow/battery-monitor/actions/runs/39419420785)
passes on exact product `5d5391a`: **macOS 27.0.1 (26A434), Xcode 27.0,
SDK 27.0, arm64**. It passes 701 Swift tests (671 + a separate 30-test group),
627 Python tests with four expected opt-in skips, system battery artwork and
Display checks, three native interaction variants, 20,000 animation-stress
iterations, and the universal App/helper build. [Run metadata](verification/macos27-ci.json)
and [selected log lines](verification/macos27-ci-excerpts.log) are retained.
The earlier ordinary push CI was canceled by the same-branch manual dispatch's
configured concurrency rule, not by a failing test.

The strengthened positive-control unit test passes locally after this frozen
product commit. The current product source remains identical to `5d5391a`;
remaining changes add measurement tooling, validation and evidence. The ordinary
[main CI](https://github.com/laleoarrow/battery-monitor/actions/workflows/ci.yml?query=branch%3Amain)
checks the combined tree; use its exact commit result for those later tooling
changes instead of treating the frozen product's macOS 27 run as their coverage.

Measurement entrypoints reject existing output paths and own scratch, child
groups, test registrations, suites and containers. Optimized Python cannot
disable their critical validation: UI checks use explicit exceptions, and the
sampling aggregator rejects optimized interpreters before starting a probe.
The [sampling entrypoint follow-up](sampling/entrypoint-boundary-review.json)
records old/current harness hashes and independently revalidates 20 raw-data
invariants without changing existing measured evidence. Interrupted/failed runs
remain explicitly identified above.

The final [read-only canonical comparison](verification/canonical-after.json)
matches public 5.0.0's complete app tree, helper, daemon, package receipt,
running PID and all 16 setting hashes. No install, launch, settings write or
helper request is performed by that comparison. This work does not publish
a release or install the unreleased performance patch.
