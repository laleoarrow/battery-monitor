# Bounded History fixture diagnostic

This probe did **not** reproduce the hosted one-second retained-animation-key
failure. It does not establish that the fixture's artificial root clock caused
that failure. Production sources were not edited.

The probe uses frozen `8300cabcb5859fcc74c3ff613a2c530a47c01f30` production
`HistoryView` and captures all three animation owners, including the fill mask.
Thirty-six cases pair a normal clock with an artificially paused/resumed root:
normal/accessibility policy, original/centered/covered placement, and three
repetitions. The same `[0, 0, 100]` to appended `150` transition installs finite
0.35-second stroke, fill and head animations.

All cases removed the three keys before one second. First observed removal
ranged from 0.278 to 0.483 seconds after observation started. Every final full
stroke/fill path and head position matched its model exactly. No sampled key's
begin time changed after installation. Covered cases were genuinely occluded
at observation start and still cleared their keys before the cover was removed
at 1.25 seconds.

Four cases briefly retained all three keys beyond their configured owner-local
active duration while complete presentation geometry already equaled the
target. This occurred with both normal and paused clocks; the largest sampled
owner elapsed time was 0.429621 seconds. All subsequently cleared by the next
observed removal, at most 0.483 seconds. This distinguishes retained objects
from ongoing movement in these samples without explaining the hosted failure.

`diagnostic-analysis.json` records grouped results and caveats.
`accepted/results/probe/` retains every complete model/presentation path vector,
per-owner local clock, animation configuration, root clock and visibility
sample. Observation polls use the actual AppKit run loop. Removal times are
sampled, not exact compositor timestamps. Each case observed until at least
1.6 seconds with no remaining keys; the five-second diagnostic ceiling was
never required.

The owned ARM GUI VM then ran the newly frozen clock-split interaction harness
and stress gate without rebuilding a moving checkout. Final native evidence
is kept separately under `../native/after-clock-split/`. Cleanup and exact
source identity are recorded in the verification JSON files.

To reproduce, use a matching shared lifecycle library and a new output
directory. The diagnostic source remains fixed; the optional second argument
selects an immutable commit for the subsequent full native gate:

```bash
bash design/release-v4.3.22/history-fixture-probe/run-owned.sh \
  "$PWD/design/release-v4.3.22/history-fixture-probe/another-run" \
  7f41533b017d26519a69d541d3ffd2dea587f413
```
