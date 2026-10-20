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

Publication and canonical installation completed on 2026-10-20. The stable
[GitHub release](https://github.com/laleoarrow/battery-monitor/releases/tag/v5.0.0)
and [public gallery](https://laleoarrow.github.io/battery-monitor/design/v5.0.0/)
use frozen source `39c48e3e0564384f4aefb4aff1c1f6e99c6a9c7b`. Main/tag CI,
macOS 27 validation, the five-platform candidate installation matrix, Homebrew
and Pages gates passed. Public artifacts match the verified candidate bytes.

The canonical App, helper and receipt are all 5.0.0; 16 settings were retained.
The user confirmed normal popup and Display rendering. This is user acceptance,
not direct CUA observation. macOS 27 validation covers software tests, not
physical battery hardware or a macOS 27 package installation matrix.

- [Final release verification](publication/final-release-verification.json)
- [Public website and download verification](publication/public-site-verification.json)
- [Canonical installation verification](installation/local-install-verified.json)
- [Launch and user acceptance](installation/startup-verification.json)
- [Authorized promotion email verification](publication/email-verification.json)

The promotion email was sent and read back from Sent, with matching plain-text
and HTML alternatives and verified public links. Recipient details remain
outside this public repository. Post-release evidence commits do not change
the frozen tag or distribution artifacts.
