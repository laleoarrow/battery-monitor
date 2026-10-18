# Wattson 4.3.20 local preview

Built from frozen commit `1533a0c` with the project release pipeline. Both
architectures, signatures, packaging and identical PKG/DMG app contents passed.
The native macOS Installer installed the verified PKG into the canonical
`/Applications/Wattson.app` with its matching helper and LaunchDaemon.

The installed marketing/build/receipt versions are 4.3.20. Payload bytes,
signatures, helper health/V5, actual process sampling and all 15 prior settings
passed the installation check. The canonical PID remained stable. The user
opened the actual popup and its menu displayed 4.3.20.

Process Activity was then enabled through its native module menu for the
requested preview. Top 3 and Compact view remain enabled; the other 14 saved
settings remain unchanged. The user supplied the running-app screenshot used
for the subsequent uniform-width request. No process was terminated.

The build and expanded-payload scratch directories and their app registrations
were removed; the canonical installation remains. Final PKG/DMG artifacts and
checksums are retained under `dist/local-preview-v4.3.20/`.

This is a local preview, not a public release. App/helper are ad-hoc signed;
the PKG is unsigned and not notarized. No GitHub release or email was sent.
