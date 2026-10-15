# Sidebar refinement capture evidence

Eighteen actual production Settings compositor captures verify the refined sidebar on frozen source `1f85a47a038edb8bb347951556ea4815252e7132127ae8f0ecdf20607145ea77`.

| Viewport | Glass Light / Dark | Classic Light / Dark |
| --- | --- | --- |
| General top | [Light](settings-glass-general-light.png) · [Dark](settings-glass-general-dark.png) | [Light](settings-classic-general-light.png) · [Dark](settings-classic-general-dark.png) |
| Appearance | [Light](settings-glass-appearance-light.png) · [Dark](settings-glass-appearance-dark.png) | [Light](settings-classic-appearance-light.png) · [Dark](settings-classic-appearance-dark.png) |
| Display | [Light](settings-glass-menu-bar-icon-light.png) · [Dark](settings-glass-menu-bar-icon-dark.png) | [Light](settings-classic-menu-bar-icon-light.png) · [Dark](settings-classic-menu-bar-icon-dark.png) |
| Modules | [Light](settings-glass-modules-light.png) · [Dark](settings-glass-modules-dark.png) | [Light](settings-classic-modules-light.png) · [Dark](settings-classic-modules-dark.png) |

Increased Contrast, Glass General: [Light](increased-contrast/settings-glass-general-light.png) · [Dark](increased-contrast/settings-glass-general-dark.png).

Every frame asserts the retained selected page, native table selection, attached selected row and containment of all three navigation rows. All eighteen images were inspected for badge/glyph rendering, full Modules visibility, control alignment and contrast. The Appearance-only fixture positions its heading near the viewport top and reflects the scroller; this avoids a partial Updates heading without changing product scrolling.

Captured in the existing disposable ARM `macOS-TestLab` on macOS 26.6.1 GUI session with the accepted own-window compositor bridge. Preferences are in memory; system/update operations are mocked. Increased Contrast is forced through test hooks. No production installation, host desktop, privacy setting, macOS accessibility preference or prior evidence was changed. Owned preview processes, bundle registrations, containers, Application Scripts and scratch were removed; the caller-owned VM remains running.

[Source/image manifest](capture-manifest.json) · [Capture-only fixture patch](capture-fixture.patch)
