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

Publication requires successful exact-main Headless CI, the candidate build and
five hosted install jobs, checked candidate/public byte equality, the exact tap
commit's CI, public Intel/Apple-silicon Homebrew lifecycle and Pages deployment.
Canonical installation uses that exact verified public PKG. These stages are
recorded separately in publication/ and installation/; their completion must be
verified before the release is announced.
