# Wattson 5.0.0 release

This release combines the completed native Display settings work, macOS 27
battery style, final preview spacing and accessible percentage with the
system battery-health and charging-status corrections.

`VERSION` is the sole product version source. Previous 4.3.24 installation
and 03ca506 validation records remain historical evidence; they do not attest
to a 5.0.0 package.

- [Release notes](release-notes.md)
- [Versioned approved artwork gallery](../releases/v5.0.0/index.html)
- [Display implementation and prior validation](../settings/display-system-defaults/README.md)
- [System metric implementation](../system-metric-authority/README.md)

The `publication` directory records the frozen main commit, exact-SHA CI,
candidate matrix, checksummed public artifacts, Homebrew and Pages gates.
The `installation` directory separately records canonical App/helper/receipt
synchronization and retained preferences. A running process alone does not
confirm visible menu-bar interaction.

Community distribution uses ad-hoc App/helper signatures, unsigned PKG/DMG
and no notarization. Candidate verification and public-byte verification run
before publication is treated as complete. No older release asset is replaced.
