# History upgrade evidence — Wattson 4.3.9

The Pro patch is integrated into source commit
`5cefb014b845284ae2dd66be039a6fd9abd3d32e`. The verified PKG was installed in
the canonical `/Applications/Wattson.app` together with its helper and receipt.
This is a local upgrade; no public release is claimed.

| Input or artifact | SHA-256 |
| --- | --- |
| `Wattson-History-Upgrade.zip` | `ab0fe2cb5dc59c6a0a49ebb8e1a2097f77e07d85436be51a1ac2125ac691d7cb` |
| `Wattson-v4.3.9-macos-universal.pkg` | `50c341b2fb684a19a6e406bb6d98b1d393ca4adc8fd30fa7ab8867f63b9fb599` |

[Source and distribution hashes](evidence/source-and-package.json) identify the
frozen production files. [Installation verification](evidence/local-install-verified.json)
confirms matching app/helper/daemon payloads, receipt 4.3.9, signature validation,
helper health and a stable canonical app process.

## Integrated behavior

The chart uses shape-preserving cubic interpolation through the original samples,
a fixed two-minute time axis, a quantized vertical scale with shrink hysteresis,
and a short translation for eligible new samples. It preserves raw values and
Peak, and stops motion when inactive, hidden, detached, degraded or Reduce Motion
is enabled. No sampling-frequency change or additional timer was introduced.

Three small corrections accompany the supplied patch:

- Keep the normal cached time reference while the latest sample is at most six
  seconds old; after a gap, advance the reference so paused readings show their age.
- Animate only when the previous endpoint is within 100 ms of the right edge.
  An aged endpoint receives a static redraw.
- Animate at most one departing sample, matching the renderer's retained context;
  a larger departure receives a static redraw.

PCHIP can recalculate the preceding endpoint tangent when a sample arrives.
The short translation does not promise identical old and new segment shapes.

## Native captures

These are exact production-renderer WindowServer PNGs from the disposable ARM
macOS GUI VM, using deterministic scenario data. Each pair shows real top and
bottom scroll positions in the VM's short viewport. The bottom position contains
the complete History section and clips the upper instrument; the top position
preserves the upper layout. Neither is a full-content, unscrolled screenshot.

| State | Light, History visible | Dark, History visible | Upper layout |
| --- | --- | --- | --- |
| Charging | [Bottom](captures/charging/regular-light-bottom.png) | [Bottom](captures/charging/regular-dark-bottom.png) | [Light](captures/charging/regular-light-top.png) · [Dark](captures/charging/regular-dark-top.png) |
| Full | [Bottom](captures/full/regular-light-bottom.png) | [Bottom](captures/full/regular-dark-bottom.png) | [Light](captures/full/regular-light-top.png) · [Dark](captures/full/regular-dark-top.png) |
| On battery | [Bottom](captures/on-battery/regular-light-bottom.png) | [Bottom](captures/on-battery/regular-dark-bottom.png) | [Light](captures/on-battery/regular-light-top.png) · [Dark](captures/on-battery/regular-dark-top.png) |
| Mixed supply | [Bottom](captures/mixed-supply/regular-light-bottom.png) | [Bottom](captures/mixed-supply/regular-dark-bottom.png) | [Light](captures/mixed-supply/regular-light-top.png) · [Dark](captures/mixed-supply/regular-dark-top.png) |
| Low battery | [Bottom](captures/low-battery/regular-light-bottom.png) | [Bottom](captures/low-battery/regular-dark-bottom.png) | [Light](captures/low-battery/regular-light-top.png) · [Dark](captures/low-battery/regular-dark-top.png) |
| Low Power | [Bottom](captures/low-power/regular-light-bottom.png) | [Bottom](captures/low-power/regular-dark-bottom.png) | [Light](captures/low-power/regular-light-top.png) · [Dark](captures/low-power/regular-dark-top.png) |

All twelve bottom images were visually reviewed: caption and Peak are visible,
curve/fill boundaries and the endpoint align, and History has no text overlap or
clipping. Geometry JSON accompanies every image.

## Measured capture sequence

[Play the recording](motion/history-motion.mp4). The [original metadata](motion/history-motion.json)
and [113 original PNG frames](motion/motion-frames/) are retained unchanged.
The first two updates start transitions; the third finds the previous animation
still active under synchronous capture load and takes the intended cancellation
path. The final state is stopped. The original `motionChecksPassed: false`
records the capture harness's failed expectation that all three updates start;
it is preserved as a limitation.

The MP4 uses measured frame intervals, with no interpolated frames. Its container
duration is 6.520 s versus the recorded 6.5252395 s span because of time-base
quantization. This recording establishes neither FPS nor a measured 180 ms
wall-clock completion. Encoding provenance is in
[motion-encoding.json](evidence/motion-encoding.json).

## Verification and limits

| Check | Result |
| --- | --- |
| Host native Swift suite | 499 tests, zero failures |
| Host Python suite | 599 tests, zero failures, four skipped |
| VM AppKit interaction | 399 assertions, including 34 for History |
| VM animation stress | 20,000 iterations passed |
| Frozen-source static captures | Six states × two themes × two scroll positions; exit 0 |
| Same-PKG VM lifecycle | Fresh install, reinstall and disabled-service reinstall passed |

Logs and provenance are retained under [evidence](evidence/). The VM's
Command Line Tools installation lacks XCTest; the complete Swift suite ran on
the host, while native interaction, rendering, stress and install checks ran in
the VM. A local installation and these results do not replace the public release
matrix, CI or publication gates.

[Final VM verification](evidence/final-native-verification.json) includes cleanup:
all eight immediate and eight delayed checks passed across seven exact owned
preference domains after a 97.708 s quiet interval; all five package residual
checks passed. The VM's canonical installation stayed at its baseline, the
disposable clone was removed, and the caller's other VM states were preserved.
[Host cleanup](evidence/host-cleanup-audit.json) found only the canonical Wattson
application registration and no owned integration scratch.

[manifest.json](manifest.json) records the source commit and each other retained
file's SHA-256. Static captures come from run v6; the load-affected recording comes
from run v5 of the same frozen production source.
