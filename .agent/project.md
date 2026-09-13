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
the Settings sidebar on macOS 26 and later. It defaults off to retain Classic
styling. The switch changes Settings materials/controls and the
popover's native mode chooser,
and requests the system's Dark Aqua appearance for the whole glass popover.
This preserves the requested near-black visual direction without placing an
opaque black overlay over the system material. Classic popovers keep their
existing system Light/Dark adaptation; glass Settings follows system appearance,
while Classic Settings retains its dark composition. It does not change power computation, helper requests, or data
instrumentation.
Off uses Classic styling; shared Settings content improvements apply to both
styles. This is not an operating-system-wide disable of Apple's materials.
Accessibility preferences remain authoritative.

Settings now delegates its glass sidebar to `NSSplitViewController` and a native
sidebar item. The native detail safe area positions the retained content;
appearance changes reparent the existing controls and preserve keyboard focus.
Glass mode uses a transparent NSWindow over the system behind-window material.
Functional Settings groups use NSGlassEffectView; General's shared container
batches its two groups inside the scroll document, not around the fixed heading
or system sidebar. Single-group pages need no additional container. Liquid Glass
belongs to General > Appearance, and only joins that page's keyboard loop.
General scrolls as needed for the added logo choice or expanded recovery help;
keyboard focus brings the logo selector into view. Modules use monochrome SF Symbols, 12-point descriptions, inset
separators and right-aligned switches. See the
[appearance hierarchy review](../design/settings/appearance-hierarchy/README.md)
for actual test-VM window images and verification. This source refinement does
not replace the canonical installed app or constitute a new release.

The main popover footer now replaces the UI4 ordinary segmented
control inside a glass surface with three mutually exclusive native `.glass`
NSButtons and a separate round settings button, sharing one
NSGlassEffectContainerView with spacing 0. UI6's real-window comparison selected
the pure AppKit pattern: labels fit without a SwiftUI bridge, ordinary gray
segmented well, or extra outer glass surface. UI7 passes 829 real GUI assertion
executions in five modes and a 20,000-iteration stress test. Eight versioned
real-window screenshots show the final footer. Classic geometry and Dark Aqua
remain in scope; power flow, ring, lanes and history remain content without
additional glass cards. Earlier UI4 real composited review covers six dark
power fixtures, battery/mixed USB output, one Light-host/Classic comparison
and all three Settings pages; those earlier images are not final-footer evidence.
This is not a full appearance cross-product or manual VoiceOver review. See
[Liquid Glass review](liquid-glass.md) for outstanding acceptance work.

The installed primary icon is separate from this runtime preference. The
4.2.0 source additionally offers an independent **In-App Logo** choice in
General > Appearance. Color/Clear static Icon Composer renditions update the
Settings identity only; Clear follows that window's Light/Dark appearance.
This preference never mutates Finder/Dock icons, menu-bar symbols, or bundle
metadata. The native source and its Mono appearance remain preserved.
An independent **Dock Icon** choice now offers Hidden (the unchanged default),
Color, and Clear. Saving affects only the next process launch. On that launch,
AppDelegate selects a bundled 512px static image with the public
`applicationIconImage` API and opts into regular activation only for a visible
choice; Hidden retains the packaged accessory policy. Clear uses the startup
Light/Dark appearance. The menu-bar item remains, and Dock reopen routes through
the same guarded Settings presenter as Command-Comma. This does not modify
Finder icons, signed bundle contents, helper privileges, or the independent
in-app logo. It is not a native dynamic Clear-icon override or two-installer
variant scheme.
The classic ICNS remains unchanged; `design/icon/liquid-glass/` contains the source
layers for the native `design/icon/WattsonGlass.icon` document. Release builds
compile it with actool and include its layered catalog and a settings preview
before signing. The primary-icon plist selection is separate from the runtime
option; never mutate a signed app bundle to implement a theme switch.
The 4.1.0 primary system icon is `WattsonGlass`, using the compiled layered
catalog and its generated static ICNS fallback; both plist icon keys are
required by release verification. The classic icon remains a preserved resource
and Settings comparison. The runtime appearance switch does not mutate the
signed Finder/Dock icon. A Mono-only white energy fill improves silhouette
separation without changing Default/Dark exports. Small monochrome particles
remain tonal decoration, not guaranteed individually legible at 32 px.
The formerly open Edited Composer document had a different layer order and
background. Its separate saved copy remains preserved under
`dist/liquid-glass-option-20260913/icon-refinement/WattsonGlass-Edited-Preserved.icon`;
the stale editor window is now closed. The canonical three-layer source was
restored and hash-verified after Composer reverted the old document on close.

Successful CI run `34710861967` covers commit `41826300c3f2`, not the
pending native-button and icon revision. New source requires fresh tests and exact-commit CI,
followed by the 4.1.0 packaging and release gates in [release.md](release.md).
These development decisions do not announce or validate a 4.1.0 release.

`BatteryPowerWidgetExtension.swift` and the legacy Python implementation remain
reference/test surfaces; the currently shipped app bundle is the AppKit
menu-bar product.
