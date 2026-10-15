# Settings redesign capture evidence

The production AppKit Settings controller and popup renderers were captured in the disposable ARM macOS 26.6.1 GUI VM. The capture source includes the Settings redesign with SHA-256 `01bbc8e74feddd2360468d11179b2f99349aa68db00998a0f7721adce326aa46`.

These **116 actual own-window compositor images** include native window chrome, shadows and Liquid Glass. Power readings, estimates, history and helper availability are fixed samples. Settings preferences are in memory; helper, login, system-battery-icon and update operations are mocked. The host desktop, canonical installation, guest macOS accessibility preferences and capture permissions were not changed by this workflow.

| Settings viewport | Light | Dark |
| --- | --- | --- |
| General top | [Glass](settings-glass-general-light.png) · [Classic](settings-classic-general-light.png) | [Glass](settings-glass-general-dark.png) · [Classic](settings-classic-general-dark.png) |
| Appearance | [Glass](settings-glass-appearance-light.png) · [Classic](settings-classic-appearance-light.png) | [Glass](settings-glass-appearance-dark.png) · [Classic](settings-classic-appearance-dark.png) |
| Support bottom | [Glass](settings-glass-feedback-light.png) · [Classic](settings-classic-feedback-light.png) | [Glass](settings-glass-feedback-dark.png) · [Classic](settings-classic-feedback-dark.png) |
| Display | [Glass](settings-glass-menu-bar-icon-light.png) · [Classic](settings-classic-menu-bar-icon-light.png) | [Glass](settings-glass-menu-bar-icon-dark.png) · [Classic](settings-classic-menu-bar-icon-dark.png) |
| Modules | [Glass](settings-glass-modules-light.png) · [Classic](settings-classic-modules-light.png) | [Glass](settings-glass-modules-dark.png) · [Classic](settings-classic-modules-dark.png) |

The real GUI Settings contract passed all eight tests in 140.341 seconds, including 500 retained-window reuse cycles, 500 creation/release cycles, focus and keyboard checks, and the original RSS/file-descriptor assertions. The final native harness completed in 133.914 seconds with four descriptors before and after stress. See [GUI test log](settings-interaction.log).

`power-fixtures/` contains all six states—charging, full, on battery, mixed supply, low battery and Low Power—in Classic, Standard Glass and Clear Glass, each in Light and Dark (36 images). `accessibility/` repeats the twenty Settings viewports with Reduce Transparency, Increase Contrast and Reduce Motion independently forced through test hooks (60 images). Static screenshots do not establish motion quality or a manual VoiceOver review.

The test-only compatibility patch uses the deprecated public `CGWindowListCreateImage` symbol for the calling app's own `NSWindow` only. Apple documents the own-window capture permission boundary in [WWDC19, Advances in macOS Security](https://developer.apple.com/videos/play/wwdc2019/701/). The normal ScreenCaptureKit permission preflight and guest whole-screen capture were unavailable; no privacy setting or authentication method was changed. This compatibility bridge is absent from production code.

The patch also adds the complete Classic power-state fixtures and Support viewport, injects test contrast, and reflects the programmatic General scroll offset into the scroller before capture. These are fixture changes only. The original production source hashes were verified in the VM; the GUI Settings contract result is recorded in `capture-manifest.json` after completion.

For reproduction, stage `source.tar` containing the paths and bytes in `sourceSHA256`, the same JSON mapping as `source-manifest.json`, `capture-owned-windows.patch`, and a `lifecycle/` directory copied from `scripts/lib/` in a caller-owned VM share. Run the saved `capture-evidence.sh SHARED_INPUT_DIRECTORY` inside the existing disposable GUI session. It verifies the archive, applies only the fixture patch, builds a unique sandboxed preview, captures the matrix, runs the GUI Settings contract, then unregisters the preview and removes owned processes, container and scratch on completion or catchable interruption. Input archive, logs and requested images are caller-owned outputs.

[Capture/source manifest](capture-manifest.json) · [Image checksums](SHA256SUMS.txt) · [Capture fixture patch](../capture-owned-windows.patch) · [Owned orchestration](../capture-evidence.sh)
