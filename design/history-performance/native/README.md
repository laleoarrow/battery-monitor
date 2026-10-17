# Native History performance regression evidence

The production renderer is frozen at **`855fc308f8864940a72ca77c93b0221d4e305a33`**, version 4.3.11. Its HistoryChart/HistoryLayer hashes match the isolated performance candidate `9325876`. These checks ran in the benchmark owner's disposable ARM GUI VM, after timing measurements ended. Packaging and installation are separate evidence.

| Check | Actual result |
| --- | --- |
| Combined AppKit interaction | 434 assertions passed |
| Animation stress | 20,000 iterations passed |
| Original eleven motion phases | 236 checks passed |
| Corrected natural eighteen-phase geometry analysis | 376 checks passed |
| Same-phase comparison with 4.3.10 | 33 checks passed |
| Requested natural 25/50/90% retarget timing | **Five of six targets missed; not accepted as fraction coverage** |
| Synthetic controlled-clock native retarget test | 57 checks passed |
| Six states in Light/Dark | Twelve actual PNGs individually reviewed |

[Native report](evidence/native-report.json), [source identity](evidence/source-freeze.json), [visual review](evidence/gallery-visual-review.json).

The natural scalar pass uses ordinary `NSApplication.run` and performs no PNG work. Maximum sampled head-to-stroke deviation was **0.075976 pt** and gradient-band drift **0.004016 pt**. Each original phase passed the predeclared comparison allowance of its 4.3.10 result plus 0.05 pt. This is presentation-coordinate evidence, not pixel identity or display FPS. [Analysis](evidence/natural-v2-scalar-analysis.json), [comparison](evidence/natural-v2-baseline-comparison.json).

The first full pass retained two generic composite-phase timing failures (374/376); deep inspection before short retarget deadlines also missed the intended fractions. The narrow correction removed that inspection and derived only the new composite-phase bounds from actual retarget time plus configured duration plus 150 ms observation allowance. Original eleven phase limits were unchanged. Natural timing still missed five targets, and a stale animation key also failed the settled-boundary gate. Both runs and their failures remain preserved. [First-run diagnosis](evidence/first-run-fixture-failures.json), [strict natural fraction results](evidence/natural-v2-branch-analysis.json).

The final **synthetic** native fixture pauses only the test parent CALayer using `speed/timeOffset`, commits real presentation layers, seeks the exact fractions, then calls unmodified production `update`. It verifies production-captured `fromTransform/tx`, retained anchors, actual non-knot path interiors and endpoint continuity. Both basic→scaled and basic→basic captures recovered q = **0.250000, 0.500000, 0.899991274**; maximum q error was 8.72612e−6 against the fixed 1e−5 limit. Maximum retained-anchor/interior discontinuity was below 5.9e−14 pt; endpoint discontinuity was 0.000307 pt. The completed-axis→basic boundary also passed. This supplements natural motion evidence; it does not establish natural scheduling at those fractions. [Controlled report](evidence/controlled-analysis.json).

Actual media: [contact sheet](motion/selected-native-frames.png), [six selected native VFR movies](motion/movies.json), [twelve state captures](captures/). The retained twenty-eight original frames include every pixel-audit input. Eighteen flat-stroke checks showed 3–4 thresholded pixels at 2×, and all seven comparable fill checks passed. [Pixel audit](evidence/native-pixel-review.json). Movies use measured capture timestamps without generated frames; capture cadence is not display FPS. Bottom-scroll state captures deliberately exclude the upper power-flow instrument.

Original scalar JSON and interaction/stress logs are retained losslessly as `evidence/*.gz`. [Collection provenance](evidence/collection-provenance.json) records their uncompressed hashes. Each of the three [sealed tool archives](evidence/tools/) includes its exact probe, runner and analyzers; the adjacent `tools-freeze-*.json` manifests identify inputs. Reproduce in an owned disposable GUI VM by exporting source commit 855fc308, verifying the manifest's source-file hashes, unpacking the corresponding tool archive to guest-native storage and running its lifecycle entrypoint with `WATTSON_HISTORY_SOURCE_ROOT`, `WATTSON_HISTORY_TOOLS_DIR`, `WATTSON_HISTORY_RESULTS` and `WATTSON_HISTORY_SOURCE_COMMIT` set. Entries are `run-axis-qa.sh`, `run-axis-capture-only.sh` and `run-controlled-retarget.sh`, respectively. Never execute a mutable share script directly.

All three guest stages exported with actual exit 0 and removed their owned staging trees. Exact domains/app paths feed the VM owner's separate immediate/delayed cleanup audit. Cleanup fault/signal evidence and its [scope](evidence/lifecycle-scope.json) are retained. The 102 MB source archive and redundant unselected images/movies are excluded from this compact bundle; immutable source identities remain recorded.

Verify this directory with `shasum -a 256 -c SHA256SUMS.txt`.
