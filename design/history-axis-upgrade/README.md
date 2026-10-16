# History axis upgrade — Wattson 4.3.10

Production source: **`4c31f01b3cae07a2ae59e32fc8d7a1534b9bd161`**.
The verified PKG is installed at `/Applications/Wattson.app`; app, helper and
daemon match its payload, receipt 4.3.10 and helper health pass, and one app PID
remained stable for ten seconds. This is a local upgrade, with no public release
or push. See [installation verification](evidence/local-install-verified.json)
and [source/package hashes](evidence/approved-provenance.json).

[Pro's review](https://chatgpt.com/c/6ad23678-eaf8-83ee-b2f8-2d98419b6742)
identified why affine movement alone cannot preserve PCHIP's changing terminal
interval. This version matches actual presentation controls by sample timestamps,
retains bounded departure context, and moves the viewport around the zero-watt
baseline. Stroke stays at 1.6 pt; fill, gradient band and endpoint follow the
same transition. Raw readings and Peak remain unchanged. The review is design
input; the macOS checks below provide runtime evidence.

## Native evidence

The disposable GUI VM runs **macOS 26.6.1 (25G76), arm64, Swift 6.3.3, SDK 26.5**.
The [environment](evidence/guest-environment.json), [frozen source](evidence/source-freeze.json)
and [native input hashes](evidence/native-inputs.sha256) identify the exact run.
The VM has Command Line Tools rather than full Xcode; the full XCTest suite ran
on the host.

| Check | Recorded result |
| --- | --- |
| Host Swift suite | 521 tests; zero failures |
| Full Python suite | 599 tests; four skipped; run began before the final renderer changes |
| Final affected Python contracts | 27 tests passed on the final renderer |
| VM AppKit interaction | 434 assertions passed |
| VM animation stress | 20,000 iterations passed |
| Ordinary `NSApplication.run` motion pass | 236 scalar checks across eleven stages passed |

The [scalar analysis](evidence/scalar-analysis.json) reads actual presentation
paths, transforms, mask and gradient. Recorded maximum head-to-stroke deviation
was **0.03320 pt**; maximum gradient-band drift was **below 0.00443 pt**. These are
sampled measurements, not a display-frame benchmark or a claim of exact pixel
continuity. [Native pixel checks](motion/native-pixel-review.json) found 3–4
thresholded pixels in all fifteen sampled flat-stroke cases at 2×, consistent
with the 1.6 pt stroke; all seven comparable outlier-fill samples passed.
The [final VM report](evidence/final-qa-report.json) records the complete scope
and limitations.

### Six states, Light and Dark

These exact WindowServer captures use deterministic fixtures. They show the
bottom scroll position of the short-screen popup so History is complete; the
upper power-flow instrument is intentionally outside the viewport.
All twelve images were individually inspected for complete History labels,
aligned stroke/fill/endpoint and text overlap; see the
[visual review](evidence/gallery-visual-review.json).

| State | Light | Dark |
| --- | --- | --- |
| Charging | [PNG](captures/charging-light.png) | [PNG](captures/charging-dark.png) |
| Full | [PNG](captures/full-light.png) | [PNG](captures/full-dark.png) |
| On battery | [PNG](captures/on-battery-light.png) | [PNG](captures/on-battery-dark.png) |
| Mixed supply | [PNG](captures/mixed-supply-light.png) | [PNG](captures/mixed-supply-dark.png) |
| Low battery | [PNG](captures/low-battery-light.png) | [PNG](captures/low-battery-dark.png) |
| Low Power | [PNG](captures/low-power-light.png) | [PNG](captures/low-power-dark.png) |

### Independent native recordings

The movie pass is separate from the ordinary run-loop scalar pass. It records
real own-window frames on a background capture task and writes to the VM share.
The requested 30 Hz capture interval is not the achieved capture rate, and
neither measures the app's display FPS. **These recordings do not establish
60 FPS.** VFR encoding uses measured timestamps without synthetic interpolation.

| Selected recording | Captured frames | Measured capture span |
| --- | ---: | ---: |
| [Scale expansion](motion/scale-expansion.mp4) | 7 | 0.796 s |
| [Scale contraction](motion/scale-contraction.mp4) | 7 | 0.765 s |
| [Interrupted scale](motion/interrupted-scale-50.mp4) | 7 | 0.859 s |
| [Departing peak](motion/departing-outlier-contraction.mp4) | 8 | 0.825 s |
| [Gradient alpha contraction](motion/gradient-alpha-contraction.mp4) | 7 | 0.835 s |

[Movie metadata](motion/movies.json) covers all eleven recorded phases. The
[contact sheet](motion/selected-native-frames.png) has fifteen selections from
fourteen original frames; its first two entries select the same nearest frame.
[Selection timestamps](motion/selected-native-frames.json) and the
[original PNG subset](motion/frames/) preserve that fact. The subset also retains
every frame used by the pixel audit: twenty-five originals in total, rather than
the full recording sequence. Movies crop to the History section, including its
right capture boundary.

## Reproducibility and installation

Host logs, original measurement JSON compressed losslessly with gzip, input
hashes and [QA action sources](evidence/actions/) are retained under
[evidence](evidence/). Action sources belong to the frozen checkout's owned
lifecycle wrapper. [Collection provenance](evidence/collection-provenance.json)
records original paths and hashes; no earlier freeze's captures are included.

The exact installed PKG SHA-256 is
`396d713f61e027d4a1ef552a3af2eb267114fe1d29ce4b497495b4f3e92fbe06`.
VM fresh-install, reinstall and disabled-service reinstall validate matching
payloads, code signatures, receipts and helper health. The VM has no
`AppleSmartBattery`; the production app follows its designed no-battery exit
path there. These VM checks do not establish three-second app survival or
battery readiness. The ten-second stable app observation belongs to the
physical host's actual battery-equipped installation.

The [package evidence archive](evidence/package-results-final-1a455c8ad423594c2e8c177bb46636e2b837e7bd05815c7822eade24acc226d7.tar.gz)
retains the original three-mode health/payload matrix and the inapplicable
stay-running diagnostic. Guest/host archive SHA-256 and all 52 inner file hashes
were verified. Final immediate and delayed audits passed all eight owned-resource
and five package-residual checks after **111.366 s** of quiet time. Canonical
state remained unchanged. The [owned VM clone was removed](evidence/vm-cleanup-summary.json)
and the caller's other VM states were preserved; the wrapper's exit 143 reflects
the intentional TERM that ran cleanup. [Host residual audit](evidence/host-residual-audit.json)
found only the canonical Wattson installation/registration.

Verify the retained files from this directory with
`shasum -a256 -c SHA256SUMS.txt`.
