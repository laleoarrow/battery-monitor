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

Verification is performed on one frozen source: real production-renderer
captures and native settings interaction on the owned macOS 26 VM, plus actual
macOS 27 / SDK 27 rendering, settings interaction and the existing full CI gate.
The canonical installed App, helper, daemon and user preferences are preserved.
Run identities, results, cleanup evidence and remaining limits will be recorded
after those executions complete. No release or installation is requested here.

The first `40a1493` VM attempt is retained as rejected evidence: all 38 frames
were captured, but the selected Command Line Tools could not import XCTest,
so the following native contract was never reached. The frames also exposed
the flush-left regular radio that prompted the small-control/inset correction.
The revised VM runner keeps the 38 real frames and eight native contract tests;
the 14 new Swift tests run with full Xcode on both hosted OS versions.
