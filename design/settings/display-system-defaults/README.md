# Display: system controls and macOS 27

The previous revision passed its functional checks, but the user rejected its
inconsistent custom corner shapes and visual treatment. This revision removes
the custom row background, outline, radio indicator and focus drawing. AppKit
draws the radio, title and focus. Settings' shared Glass groups retain the
actual `NSGlassEffectView` default corner radius; boxed content reads that
radius instead of guessing a constant. The existing Classic General and
Modules surfaces are outside this visual change.

The native small radio controls keep an eight-point left margin. Their seven
preview columns retain their prior global alignment and natural artwork sizes.

Display now contains three native style choices with one shared seven-state
header and a small percentage popup. Existing `wattson` and `native` saved
values and drawing remain compatible. The new `native27` choice uses a filled
battery body with optional inset digits. It keeps the saved percentage option
while suppressing a duplicate external title. Preview images update in place
only when their embedded percentage changes; the older styles keep their
existing image objects and cache behavior.

The macOS 27 composition is a reference-derived renderer, not a capture of the
system Battery menu or a claim that Apple exposes a public battery drawing API.
It uses the running OS's large bolt/plug assets when available and small vector
fallbacks on older systems. No system artwork is copied into product resources.

Evidence for the platform boundary is in
[macos27-artwork-probe](macos27-artwork-probe/comparison.json): actual macOS
27.0.1, SDK 27 and Xcode 27 on ARM. The four existing macOS 26 assets are
pixel-identical there, while four large bolt/plug resources are newly present.
The probe distinguishes resource inventory from complete system composition.

Visual references are the firsthand macOS 27 screenshots in
[Zac Hall's design report](https://9to5mac.com/2026/08/18/macos-27-golden-gate-makes-one-design-decision-that-i-would-change-for-macbooks/).
The [Apple Mac User Guide](https://support.apple.com/guide/mac-help/monitor-your-macs-battery-mchlp1115/27/mac/27)
and [macOS 27 release notes](https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes)
provide the official platform context. These sources do not establish the
result of testing Wattson itself.

Verification pins each source commit: real production-renderer
captures and native settings interaction on the owned macOS 26 VM, plus actual
macOS 27 / SDK 27 rendering, settings interaction and the existing full CI gate.
The canonical installed App, helper, daemon and user preferences are preserved.
Run identities, results, cleanup evidence and remaining limits are in the
[verification index](verification.json). No release or installation is performed.

The first `40a1493` VM attempt is retained as rejected evidence: all 38 frames
were captured, but the selected Command Line Tools could not import XCTest,
so the following native contract was never reached. The frames also exposed
the flush-left regular radio that prompted the small-control/inset correction.
The revised VM runner keeps the 38 real frames and eight native contract tests;
the 14 new Swift tests run with full Xcode on both hosted OS versions.

At `a8b7679`, the owned macOS 26.6.1 run passed 38 captures, all eight native
tests, source gates and cleanup, preserving the canonical installation and 16
settings. Full-Xcode macOS 26.6.2 passed all 678 Swift tests. Its Python run
exposed an obsolete assertion counting CI steps; the replacement verifies the
manual guard on each required macOS 27 step instead. The timeout stub also
keeps a two-second startup budget after a local one-second cold-start failure.

The same source produced 34 source-matched real macOS 27.0.1 frames with no
visual blocker, but its native contract exceeded 180 seconds. Cleanup then
masked the captured phase trace with a signal-zero permission error. This is
rejected runtime acceptance, not a successful full gate. The test-runtime fix
distinguishes a denied existence probe from a denied TERM/KILL, preserves the
original timeout and its stderr, and retains failed-stop ownership for retry.
Fifteen targeted lifecycle regressions and all 41 workflow tests pass locally.
No production code changed after `a8b7679`; the next macOS 27 run retains the
same 180-second watchdog to recover concrete phase evidence before any budget
change.

At `7c7705f`, macOS 26 passed the owned 38-frame/eight-test GUI run again and
completed full CI: 678 Swift, 625 Python (four expected GUI skips), and seven
website tests plus lint/export. The macOS 27 timeout now preserves progress:
functional assertions finish at 24.057s, native keyboard/reopen at 42.760s,
500 reuse cycles at 43.796s, 150 warmup releases at 96.481s, and fresh-window
stress reaches 300/500 at 178.293s. No assertion or cleanup failure occurs;
the 180s watchdog interrupts the remaining stress. The interactive budget is
therefore 300s, with a 480s outer budget for compilation, execution and cleanup.
All cycle counts, release checks, 8 MiB plateau and +2 descriptor bounds remain
unchanged. Completion still requires a new successful macOS 27 execution.

At `2dbe973`, full macOS 26 CI passes again. The macOS 27 workload completes
all 500 stress creations at 225.776s, then fails the old bidirectional RSS
flatness assertion: its range is 32,391,168 bytes, while RSS falls from
760,872,960 at cycle 100 to 730,333,184 at cycle 500. The cause of that fall
is not established. FDs remain nine, window count remains three, and object
release assertions pass. This failed run remains rejected.

The revised memory assertion bounds the maximum **upward** RSS excursion from
any earlier minimum at the same 8 MiB. It keeps the raw spread as a diagnostic,
the final-versus-warm and reuse RSS limits, weak-object release checks, +2 FD
bound, sample schedule and every cycle. Pure regression sequences distinguish
decreases, cumulative rises, a rise after a large drop, and a peak followed by
a fall. This intentionally tests bounded sampled growth rather than flatness;
RSS alone cannot establish absence of leaks. The fresh complete run below
validates the revised assertion and every remaining gate.

## Accepted Display verification

This Display validation freezes `5b5ab47753fd6cbba971ccb0dd892b99c0b116d0`.

| Actual environment | Result | Evidence |
| --- | --- | --- |
| macOS 26.6.1 owned GUI VM | 38 composited frames, eight native Settings tests, source and cleanup gates pass | [GUI report](native-macos26-7c7705f/gate-results.json) |
| macOS 26.6.2, Xcode 26.6, SDK 26.5 | 678 Swift and 625 Python tests, four expected opt-in GUI skips; seven website tests, lint and export pass | [Full CI](native-macos26-ci-5b5ab47/execution-audit.json) |
| macOS 27.0.1, Xcode 27.0, SDK 27.0 | 34 composited frames, eight native Settings tests, 678 Swift and 625 Python tests, four expected opt-in skips; three native variants, 20,000 animation iterations and universal App/helper build pass | [Full CI](native-macos27-5b5ab47/execution-audit.json) |

Both final GitHub runs and both jobs in each run conclude `success`:
[macOS 26](https://github.com/laleoarrow/battery-monitor/actions/runs/39372822015),
[macOS 27](https://github.com/laleoarrow/battery-monitor/actions/runs/39372862325).
The macOS 27 XCTest total is 648 App tests plus 30 helper-support tests, counted
once. Its RSS ledger is independently recomputed from every earlier/later
sample pair: maximum upward growth is 147,456 bytes against the 8 MiB bound;
the raw downward-inclusive spread remains recorded. All 16 test lifecycle
checks pass, including real Foundation preference cleanup.

The macOS 26 GUI run uses `7c7705f`, which passed the former stricter 180-second
watchdog and bidirectional RSS bound. Its 69 production/fixture files are
[byte-identical to final source](production-source-continuity.json); only the
test watchdog and sampled-memory policy changed afterward. The owned VM was
removed, existing VM states were preserved, and canonical Wattson 4.3.23,
its helper/daemon, process and 16 retained settings were unchanged.

[Actual macOS 27 preview](native-macos27-5b5ab47/display/after-macos27-selected/glass-dark-percentage-on.png)
and [native acceptance audit](native-macos27-5b5ab47/display/independent-display-audit.json)
remain directly viewable. Superseded attempts are preserved in
[byte-verified run archives](archives/index.json), with per-file hashes;
extract an archive into this review directory to restore its original paths.
[Raw log storage](raw-log-storage.json) maps losslessly compressed logs to
their original byte hashes, including members inside those archives.

This validates software rendering, lifecycle, compatibility and build gates.
Physical macOS 27 battery hardware, installation/login acceptance and
notarization are outside this UI change. The universal build is ad hoc signed.
That frozen source has `VERSION` 4.3.23. This Display work does not install the
App or publish a release.

## Concurrent metric update

During evidence cleanup, the shared branch received `0ae7ee0` and `98d53c1`
from the separate [system metric authority work](../../system-metric-authority/README.md).
They update battery health/charging authority and install a local 4.3.24
candidate. Those commits and their installation are preserved. The 5b5ab47
reports above do not cover that later production delta. An integrated source
is being frozen for complete macOS 26/27 CI before final acceptance of the
combined branch; the Display Settings controller and capture fixture remain
unchanged. No additional local installation is performed by this Display work.
