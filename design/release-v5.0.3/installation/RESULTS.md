# Canonical public 5.0.3 installation

The user authorized unattended installation. The native macOS installer
upgraded the canonical `/Applications/Wattson.app` from the anonymously
verified public PKG, SHA256
`e0b97f9c21f8c0c0488133af421306be7eb9c2b48a4eb61c1ef59d76cda39fd5`.
Its exit status was zero. The App was then opened from that canonical path.

The one-use askpass reader held the supplied credential only in memory.
Terminal echo was disabled; no credential was written into a file, environment,
argument or installation log. Its managed scratch was removed and the sudo
timestamp invalidated. No PAM, authorization or privacy settings changed.

`verified-public-5.0.3/public-install-verified.json` confirms:

- App, build and package receipt report 5.0.3.
- App, helper and daemon match the accepted public payload.
- Universal architectures and ad-hoc signatures verify.
- Helper health and v5 negotiation pass; canonical App is running.
- All 18 existing settings are unchanged; only hashes were recorded.
- Owned verification scratch and temporary App registrations are absent.

The Mac was locked when CUA was first queried; a second attempt after
installation returned a Computer Use timeout. An actual canonical menu-bar
popup open/close is therefore explicitly unverified. The separate disposable
GUI VM and hosted native interaction/animation acceptance remain valid.

This direct-PKG installation completed while the independent Homebrew CI trust
compatibility fix was being validated. The email remains gated on successful
public Homebrew validation, Latest promotion and Pages deployment.
