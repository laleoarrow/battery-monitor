# Wattson 4.3.21 local preview

Built from frozen commit `09167f7`, with uniform 38 × 16-point process action
capsules. The release pipeline verified both architectures, signatures,
packaging, checksums and identical PKG/DMG app contents. The native macOS
Installer installed the verified PKG into the canonical app/helper/daemon
locations after the user completed its administrator authorization.

Installed marketing/build/receipt versions are 4.3.21. The payload byte
comparisons, strict signatures, helper health/V5 and real process sampling
passed. All 15 prior saved settings match their fresh pre-install hashes,
including enabled Process Activity, Top 3 and Compact view. No process was
terminated and no extra preview setting was changed.

The uniform-width source passes 31 focused tests and 10,424 native assertions
with 108 retained captures in [the renderer review](../uniform-38/README.md).
Dedicated disabled-state renders confirm the same frame as enabled actions;
the grey appearance continues to denote an unavailable action.

Build and expanded-payload scratch directories and their app registrations
are cleaned. Final distribution files and their checksum manifest remain in
`dist/local-preview-v4.3.21/`. This local preview is not a GitHub release.
App/helper are ad-hoc signed; the PKG is unsigned and not notarized.
