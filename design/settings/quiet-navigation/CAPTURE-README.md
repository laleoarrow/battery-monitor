# Monochrome Settings capture evidence

Eighteen production Settings compositor images bind to frozen source `511d566f0e8ff7ebb33dd27b3eb81a0235e5c22197868da4aebbfb6aaa22497e`. The preexisting draft was preserved throughout capture.

| Viewport | Glass Light / Dark | Classic Light / Dark |
| --- | --- | --- |
| General top | [Light](settings-glass-general-light.png) · [Dark](settings-glass-general-dark.png) | [Light](settings-classic-general-light.png) · [Dark](settings-classic-general-dark.png) |
| Appearance | [Light](settings-glass-appearance-light.png) · [Dark](settings-glass-appearance-dark.png) | [Light](settings-classic-appearance-light.png) · [Dark](settings-classic-appearance-dark.png) |
| Display | [Light](settings-glass-menu-bar-icon-light.png) · [Dark](settings-glass-menu-bar-icon-dark.png) | [Light](settings-classic-menu-bar-icon-light.png) · [Dark](settings-classic-menu-bar-icon-dark.png) |
| Modules | [Light](settings-glass-modules-light.png) · [Dark](settings-glass-modules-dark.png) | [Light](settings-classic-modules-light.png) · [Dark](settings-classic-modules-dark.png) |

Increased Contrast, Glass General: [Light](increased-contrast/settings-glass-general-light.png) · [Dark](increased-contrast/settings-glass-general-dark.png).

All eighteen images were inspected at original pixel size. Slider strokes and knob holes remain separate, sidebar glyphs have no colored badge container, and the regular text has a calmer hierarchy. Actual rendered NSViews measure sidebar/body labels at 13pt Regular, group headings 12pt Semibold, appearance popups 12pt Regular and Display preset titles 12pt Medium. Native table cells pad the icon-view frames to 24×28/30pt; the intrinsic symbol images are 17/19pt high. The review checked visible ink rather than assuming those frames must be 24×24pt.

Every capture retains native selection, all three visible navigation rows and three template icons with zero background/border. Font and symbol metrics are recorded per image in the manifest. Appearance uses the accepted near-heading test framing; product scrolling is unchanged.

The existing caller-owned ARM `macOS-TestLab` on macOS 26.6.1 VM hosted the unique sandboxed preview. Settings were in memory and helper/system/update operations were mocked. No host desktop, production installation, privacy setting or system accessibility preference changed. Owned apps, processes, LaunchServices registrations, preference files, containers, Application Scripts and scratch were removed. The VM remains running.

[Source and image manifest](capture-manifest.json) · [Image checksums](SHA256SUMS.txt) · [Main capture fixture](capture-fixture.patch) · [Four-frame Display fixture](display-capture-fixture.patch)
