# Wattson project overview

## Product

Wattson is a native AppKit menu-bar app for macOS. It samples battery state
through IOKit, refreshes whole-machine power from two fixed read-only SMC keys
when the helper is available, and displays the result in a live power-flow
popover.

## Runtime architecture

- `Core/`: sampling, state models, history, settings, and helper client.
- `MenuBar/`: status-item icon, click routing, and application lifecycle.
- `Popover/`: AppKit views, Liquid Glass selector, layers, and animations.
- `Helper/wattson-helper.swift`: root LaunchDaemon with a fixed JSON operation
  whitelist and console-user peer validation.
- `main.swift`: application entry point plus fixed helper health and power probes.
- `Package.swift`: macOS 12 SwiftPM products for the app and helper.

The full PKG installation (also used by Homebrew) installs:

- `/Applications/Wattson.app`
- `/Library/PrivilegedHelperTools/com.leoarrow.wattson.helper`
- `/Library/LaunchDaemons/com.leoarrow.wattson.helper.plist`

The app-only DMG contains the same universal `Wattson.app` and an Applications
shortcut. Dragging the app into `/Applications` installs no helper or package
receipt. Read-only monitoring remains available without the helper, using the
battery data macOS exposes; helper-backed SMC readings and privileged controls
are not implied. Opening the app does not request administrator authorization.
Existing PKG installations must update through PKG so the app, helper, and
receipt stay in sync.

The helper is activated through `/var/run/wattson-helper.sock` and exits after
12 idle seconds. It exposes fixed read-only whole-machine power sensors plus
fixed operations for power mode, the macOS battery icon, and Wattson's
launch-at-login agent. Clients cannot supply an SMC key or SMC write command.

## Distribution architecture

`VERSION` is the release-version source. `scripts/release.sh` builds one
universal app/helper pair, packages the full installation as a native PKG and
the same app as an app-only DMG, verifies their app contents match, and emits
SHA-256 checksums plus truthful signing metadata. Older published DMGs contain
the PKG instead; do not describe those historical assets as app-only downloads.

The script and manually dispatched candidate default is `community-ad-hoc`:
app/helper ad-hoc signed, PKG/DMG unsigned, and not notarized. An app-only install
does not remove Gatekeeper trust requirements. Candidate builds run from tested,
frozen `main`; no persistent candidate or recovery branch is required. Community
publication requires explicit review of the successful candidate and publishes
its exact bytes. Developer ID is an explicit candidate option; its separate
manual promotion additionally requires accepted PKG/DMG notarization and
stapled tickets. Both paths retain the hosted-macOS install matrix and public
Homebrew/Pages gates.

## Compatibility

- Deployment target: macOS 12.
- Architectures: arm64 and x86_64.
- High Power mode is exposed only when the hardware reports support.
- macOS 26 uses native Liquid Glass; macOS 12–25 use the AppKit fallback.

The 4.1.0 development source offers an opt-in **Liquid Glass** presentation in
the Settings sidebar on macOS 26 and later. It defaults off to retain the
4.0.0 presentation. The switch changes Settings materials/controls and the
popover's native mode chooser,
and requests the system's Dark Aqua appearance for the whole glass popover.
This preserves the requested near-black visual direction without placing an
opaque black overlay over the system material. Classic popovers keep their
existing system Light/Dark adaptation; Settings retains its dark composition
in both modes. It does not change power computation, helper requests, or data
instrumentation.
Off restores the original app presentation, not an operating-system-wide
disable of Apple's materials. Accessibility preferences remain authoritative.

The main popover footer provides a distinct floating
navigation capsule: an NSSegmentedControl inside NSGlassEffectView, beside a
separate native `.glass` settings button, both in one
NSGlassEffectContainerView with spacing 0. The classic geometry and Dark Aqua
direction remain in scope; power flow, ring, lanes and history remain content
without additional glass cards. UI4 real composited review covers six dark
power fixtures, battery/mixed USB output, one Light-host/Classic comparison
and all three Settings pages. The isolated UI4b matrix passes 794 assertion
executions across five modes, including accessibility preference overrides.
This is not a full appearance cross-product or manual VoiceOver review. See
[Liquid Glass review](liquid-glass.md) for outstanding acceptance work.

The installed primary icon is separate from this runtime preference. The
classic ICNS remains unchanged; `design/icon/liquid-glass/` contains the source
layers for the native `design/icon/WattsonGlass.icon` document. Release builds
compile it with actool and include its layered catalog and a settings preview
before signing. The primary-icon plist selection is separate from the runtime
option; never mutate a signed app bundle to implement a theme switch.
The shipping primary-system-icon choice is still undecided. Mono/Tinted Dark
contrast and all six native appearances at small sizes need review. The open
Edited Composer document has a different layer order and background from the
disk source. Its separate saved copy is preserved under
`dist/liquid-glass-option-20260913/icon-refinement/WattsonGlass-Edited-Preserved.icon`;
do not discard the original or overwrite the canonical source during review.

Successful CI run `34708726238` covers earlier commit `2f6ae614b1b7`, not the
pending footer revision. New source requires fresh tests and exact-commit CI,
followed by the 4.1.0 packaging and release gates in [release.md](release.md).
These development decisions do not announce or validate a 4.1.0 release.

`BatteryPowerWidgetExtension.swift` and the legacy Python implementation remain
reference/test surfaces; the currently shipped app bundle is the AppKit
menu-bar product.
