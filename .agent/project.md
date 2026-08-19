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

The public v3 package installs:

- `/Applications/Wattson.app`
- `/Library/PrivilegedHelperTools/com.leoarrow.wattson.helper`
- `/Library/LaunchDaemons/com.leoarrow.wattson.helper.plist`

The helper is activated through `/var/run/wattson-helper.sock` and exits after
12 idle seconds. It exposes fixed read-only whole-machine power sensors plus
fixed operations for power mode, the macOS battery icon, and Wattson's
launch-at-login agent. Clients cannot supply an SMC key or SMC write command.

## Distribution architecture

`VERSION` is the release-version source. `scripts/release.sh` builds one
universal app/helper pair, creates one native PKG, wraps those exact PKG bytes
in a DMG, verifies both, and emits SHA-256 checksums plus truthful signing
metadata.

The local script default is `community-ad-hoc`: app/helper ad-hoc signed,
PKG/DMG unsigned, and no notarization claim. Those builds remain compatibility
test artifacts. Automatic stable promotion requires the protected GitHub
Developer ID path, accepted PKG/DMG notarization, stapled tickets, and the full
hosted-macOS install matrix.

## Compatibility

- Deployment target: macOS 12.
- Architectures: arm64 and x86_64.
- High Power mode is exposed only when the hardware reports support.
- macOS 26 uses native Liquid Glass; macOS 12–25 use the AppKit fallback.

`BatteryPowerWidgetExtension.swift` and the legacy Python implementation remain
reference/test surfaces; the currently shipped v3 app bundle is the AppKit
menu-bar product.
