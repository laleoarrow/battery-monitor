# Canonical public 5.0.2 installation

The user explicitly authorized unattended installation. The exact anonymously
downloaded public PKG was installed with the native macOS installer; its exit
status was zero. No user-local duplicate app or manual bundle replacement was
used. The canonical app was then opened from `/Applications/Wattson.app`.

The first sudo authentication attempt stalled before the installer started.
Its task-owned sudo process was terminated (exit 137). Apple's documented
askpass route then completed password authentication and the upgrade. The
temporary reader held the supplied credential only in memory, with terminal
echo disabled; no credential was written into the helper, logs or repository.
Its managed scratch was removed and the invocation's sudo timestamp invalidated.
No PAM, authorization or privacy settings were changed.

`verified-public-5.0.2/public-install-verified.json` confirms:

- App, build and package receipt all report 5.0.2.
- App, privileged helper and daemon match the verified public payload.
- Universal architecture and ad-hoc signatures pass verification.
- Helper health and v5 negotiation pass, and the canonical App is running.
- All 18 existing settings are unchanged; only hashes were recorded.
- Verification scratch and its app registrations are absent after owner exit.

CUA could not open the canonical menu-bar popup because the Mac was locked.
That interaction remains explicitly unverified, as recorded in
`canonical-ui-access.json`; the separate native GUI VM acceptance remains valid.
