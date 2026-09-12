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

The Settings sidebar also offers an opt-in **Liquid Glass** presentation on
macOS 26 and later. It defaults off to retain the 4.0.0 presentation. The switch
changes Settings materials/controls and the popover's native mode chooser,
and requests the system's Dark Aqua appearance for the whole glass popover.
This preserves the requested near-black visual direction without placing an
opaque black overlay over the system material. Classic popovers keep their
existing system Light/Dark adaptation; Settings retains its dark composition
in both modes. It does not change power computation, helper requests, or data
instrumentation.
Off restores the original app presentation, not an operating-system-wide
disable of Apple's materials. Accessibility preferences remain authoritative.

The installed primary icon is separate from this runtime preference. The
classic ICNS remains unchanged; `design/icon/liquid-glass/` contains the source
layers for the native `design/icon/WattsonGlass.icon` document. Release builds
compile it with actool and include its layered catalog and a settings preview
before signing. The primary-icon plist selection is separate from the runtime
option; never mutate a signed app bundle to implement a theme switch.

`BatteryPowerWidgetExtension.swift` and the legacy Python implementation remain
reference/test surfaces; the currently shipped app bundle is the AppKit
menu-bar product.
