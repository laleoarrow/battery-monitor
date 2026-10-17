# History performance — Wattson 4.3.11

This local upgrade reduces History's update preparation work while retaining
the 4.3.10 presentation-based axis transitions. Raw readings, Peak, the 60-slot
ring, sampling cadence and animation policy remain unchanged.

Status at this closeout: **Wattson 4.3.11 was installed and running on the maintainer
Mac**, from frozen source **9fef74944447d4753d1edde82997dc41a479ccad** and exact
PKG SHA-256 `72c2e20dcf13e6d69c27e9aee83528241ab58c881b1e1609a28f87b479caf21a`.
The [canonical installation check](host/local-install-verified.json) exited zero:
App/helper/daemon match that payload, both App version fields and the receipt
are 4.3.11, signatures verify, helper health/v5 pass, and the new canonical PID
remained stable for ten seconds. The previous PID exited before relaunch.
[Postflight](host/local-install-postflight.json) found only the canonical
production LaunchServices registration and no verifier scratch or Installer
process. This is a local candidate update, without a public release.

Complete host regression, native interaction checks and the five-mode exact-byte
ARM VM PKG matrix pass. Actual already-released gestures leave no dimmed row or
wrong order. Normal held native drop was unverified at that stage: automation batches drag
events in about 18 ms, and the fixture expired before the prepared human check.
The [local installation decision](host/local-install-gates.json) and original
unverified cases retain this boundary; successful held native drop or
cancellation was not claimed for that preflight source.

The later [normal slow-drag follow-up](../settings/modules-reordering/normal-slow-drag-4.3.12/README.md)
passes all six genuine held native drop/cancellation cases across Classic,
Standard and Clear on frozen 4.3.12 source, whose Modules implementation matches
installed 4.3.13. It preserves the earlier failures and zero-input timeouts and
does not add an FPS claim or rerun the complete History/installation matrix.

Earlier candidate 91f9072 is superseded: real rapid mouse testing reproduced a
queued drag starting after release and leaving a row dimmed. The correction
checks physical left-button state before and after snapshot preparation. All
unsuccessful or unverified native cases remain evidence, without being counted
as successful held-drop or cancellation tests.

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

The final integrated host regression on **9fef74944447** completed with
**535 Swift tests** and **601 Python tests, four skipped**, with zero failures.
[Current verification](host/queued-drag-verification.json) retains compressed
logs. The earlier [91f9072 verification](host/final-verification.json) remains
historical; [fixture diagnosis](host/verification.json) preserves the interruption
output-pipe issue and its test-only correction.
A separate [four-test cleanup check](host/preview-registration-fix.json) passed
after the final full suite: the preview fixture's existing unregister stub now
also unregisters its exact real LaunchServices path before deleting the bundle.
This test-only four-line change preserves the event assertions, changes no
production source or package bytes, and is not counted as another full suite.
An older absent fixture registration was also [removed precisely](resources/host-preview-registration-cleanup.json);
its particular historical run cannot be established from the retained record.

The [resource audit](resources/first-session-resource-audit-summary.json) found
all twelve owned test preference domains and ten temporary app paths absent,
including registrations, processes, staging directories and mounts, immediately
and again after 158 seconds. The benchmark/native VM exited zero and was deleted;
the other chat's VM and the originally stopped TestLab VMs kept their states.
The final [package-session audit](resources/final-package-vm-summary.json) also
passed before and after 95.10 seconds, then deleted the second owned clone with
lifecycle exit zero. Its [sealed evidence](resources/vm-lifecycle-final-evidence.json)
preserves the first two VM sessions. The corrected package used a third fresh
clone: its [independent audit](resources/queued-drag-vm-summary.json) also passed
immediately and after 95.15 seconds, with actual lifecycle exit zero and the
owned clone deleted. Its [38-file sealed evidence](resources/vm-lifecycle-queued-drag-evidence.json)
is retained. No benchmark/package VM remains owned by this chat; the other
chat's GUI VM remained under its own lifecycle owner.

## Integration and installation

Modules ordering and the five module icons are coordinated with their owning
chat and share the same candidate version. Their acceptance evidence lives in
[Modules reordering](../settings/modules-reordering/README.md). The [compact
Modules closeout](modules/summary.json) seals the current native contract,
released-gesture observations, original failed/unverified cases and final GUI
VM cleanup as 100 unedited raw records plus manifests. Its owner exited zero;
immediate and 115.9-second delayed checks passed and its clone was deleted before
the host installer began. No held native drop/cancel pass is inferred. The narrow
[integrated source review](integration-review.md) also records the bounded
appearance-refresh allocation that remains outside History's measured hot path.

The initial universal build blocked inside SwiftPM's Xcode build service while
its clang discovery child waited in a pipe write. The owned invocation was
interrupted; its scratch and three precisely identified escaped descendants
were removed. This did not affect the installed app. SwiftPM 6.3.3 forces the
Xcode engine for multiple architecture arguments, so the formal release entry
now builds one native slice at a time and merges them before existing universal,
macOS 12, signing and packaging checks. [Sixty-eight related checks](build/test-summary.json),
including second-slice and lipo failure cleanup, passed. A real preliminary
build then passed, including byte-identical PKG/DMG app verification; its
[record](build/preliminary-native-release.json) explicitly awaits final Modules
acceptance and does not claim installation.

The [corrected final build](build/queued-drag-release.json) uses frozen source
**9fef74944447d4753d1edde82997dc41a479ccad**. Its universal App/helper target
macOS 12, and the App is byte-identical across the PKG and DMG. Both binaries
are ad-hoc signed; PKG/DMG are unsigned and not notarized. The [final ARM VM
PKG matrix](package/README.md) passed all five installation modes and cleanup
audits on exact PKG SHA-256
`72c2e20dcf13e6d69c27e9aee83528241ab58c881b1e1609a28f87b479caf21a`.
The [91f9072 build](build/final-release.json) and its matrix are retained solely
as superseded evidence and were not installed on the maintainer Mac.

The [installation collection](host/local-install-collection.json) pins the
verifier, output and before/after records. The post-build test-only cleanup
commit and later evidence merges change no production package bytes.

This local candidate installation does not publish a GitHub release or substitute
for the public exact-SHA CI and hosted platform matrix described in the repository
release guide.
