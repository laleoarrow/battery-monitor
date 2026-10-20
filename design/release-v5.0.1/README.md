# Wattson 5.0.1 release

This patch release combines the process whitelist with the measured Glass warm
opening optimization already retained in main. The native AppKit UI, power
sampling cadence and theme semantics retain their existing behavior apart from
the requested whitelist controls and filtered process list.

- [Release notes](release-notes.md)
- [Whitelist implementation and native validation](../process-whitelist/README.md)
- [Measured performance and independent Pro reviews](../performance-measurements-20261020/README.md)
- [Versioned approved artwork gallery](../releases/v5.0.1/README.md)
- [Artwork provenance](artwork-verification.json)

The Glass comparison measures synchronous warmed opens in an opposite-appearance
ARM GUI VM: about 68–69 ms becomes 37–38 ms. It is not a cold-launch, physical
latency, frame-rate, whole-machine CPU or battery-life claim. Background sampling
and theme switching are retained; the 2.66 ms sampling observation is baseline
context rather than a new improvement.

Community distribution uses ad-hoc App/helper signatures, unsigned PKG/DMG and
no notarization. The complete PKG synchronizes App/helper/receipt. The app-only
DMG does not add helper-backed process monitoring or privileged controls.

Publication and canonical package synchronization completed on 2026-10-20.
The stable [GitHub release](https://github.com/laleoarrow/battery-monitor/releases/tag/v5.0.1)
is Latest, and the [public gallery](https://laleoarrow.github.io/battery-monitor/design/v5.0.1/)
matches frozen source `f2f225f5889ba1ec5cae41ee2d8fca4b80406ed6`.
Exact-source Headless CI, macOS 27 software validation, the candidate build and
five hosted install jobs, the tap's CI, public Intel/Apple-silicon Homebrew
lifecycles and Pages deployment passed. All four anonymous public downloads
match the reviewed candidate bytes. All 37 gallery resources, four SVG ZIPs and
19 SVG masters match the frozen source.

The canonical App, helper and receipt are 5.0.1 and match the verified public
PKG; signatures, helper health, v5 negotiation and real process sampling passed.
All 16 existing settings were retained. Direct CUA access timed out, so actual
canonical menu-bar click/open/close acceptance remains unverified. A stable
process alone is not GUI acceptance; the disposable-VM production-renderer and
native-input whitelist checks are separate evidence.

- [Final release verification](publication/final-release-verification.json)
- [Anonymous public artifact provenance](publication/artifact-public-provenance.json)
- [Public website and artwork verification](publication/public-site-verification.json)
- [Canonical installation verification](installation/local-install-verified.json)
- [Canonical UI access limitation](installation/canonical-ui-access.json)

Post-release evidence commits do not change the frozen tag or distribution
artifacts. Temporary verification resources were cleaned; the canonical App,
helper, receipt and production preferences remain installed.
