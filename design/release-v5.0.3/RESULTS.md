# Wattson 5.0.3 — completed publication and installation

[Release](https://github.com/laleoarrow/battery-monitor/releases/tag/v5.0.3)
· [Design gallery](https://laleoarrow.github.io/battery-monitor/design/v5.0.3/)
· [Full-charge GIF](https://laleoarrow.github.io/battery-monitor/design/v5.0.3/previews/full-charge-orbit.gif)

The release includes themed 3D full-charge double orbits with front/back
occlusion, different continuous slow periods and tapered trails, the integrated
scrollbar styles, and the power-mode slider corner-radius correction. The GIF
is a 32-second seamless design preview, 600×360 at 20 fps, 323,535 bytes. It is
embedded in both GitHub Release notes and the Cody promotional card email.

## Immutable product and public gates

- Product/tag source: `aaa50d1ee1e8b04ded88706bb8e65e035034d7b7`.
- Headless push: [41170522147](https://github.com/laleoarrow/battery-monitor/actions/runs/41170522147), success.
- Candidate: [41171291351](https://github.com/laleoarrow/battery-monitor/actions/runs/41171291351), first attempt; build and all five install jobs succeeded.
- Candidate Swift 748 tests, Python 653 tests (four expected GUI skips), all passed. Native normal/legacy/accessibility checks 523/521/516 and 20,000 animation-stress iterations passed. All 188 Swift test domains cleaned.
- Local production renderers and disposable GUI VM acceptance passed; details in `validation/local-summary.json`.
- Four exact candidate assets were published and anonymously compared byte for byte. PKG SHA256: `e0b97f9c21f8c0c0488133af421306be7eb9c2b48a4eb61c1ef59d76cda39fd5`.
- Tap source `7050d7cc1444fe9f353d1dff8ed76222fd4db629`; [Tap CI 41173276704](https://github.com/laleoarrow/homebrew-tap/actions/runs/41173276704) succeeded.

The first public Homebrew run was stopped by Homebrew's new Cask trust
requirement before ARM installation. A narrowly scoped CI repair and 44 passing
workflow tests resolved it. The immutable tag and all installer bytes stayed
unchanged; `publication/deployment-source-proof.json` verifies product and gallery
equality. See `publication/homebrew-trust-recovery.md` for the incident.

- Deployment source: `7ab4b6f71a72119647d678781299fb4840990e5a`.
- Recovery [Headless 41174031390](https://github.com/laleoarrow/battery-monitor/actions/runs/41174031390), success.
- Fresh [public Homebrew 41174651687](https://github.com/laleoarrow/battery-monitor/actions/runs/41174651687), success on Intel and ARM, including scoped trust cleanup.
- Automatic Latest promotion and [Pages 41174710259](https://github.com/laleoarrow/battery-monitor/actions/runs/41174710259), success.
- Anonymous site verification passed: 51 checksummed resources plus the checksum manifest, four SVG ZIPs and all 20 exact SVG masters; no stale installer links. GIF HTTP 200, `image/gif`, exact expected bytes.

Community distribution remains App/helper ad-hoc signed, PKG/DMG unsigned and
not notarized. The GIF is a design preview, not an App recording.

## Canonical Mac and mail

The native installer upgraded `/Applications/Wattson.app` from the verified
public PKG. App/build/receipt are 5.0.3; App, helper and daemon match the public
payload, signatures and both architectures pass, helper health/v5 pass, and all
18 prior settings are unchanged. The App stays running. Credential handling
was memory-only; temporary reader/scratch were removed and sudo invalidated.

The Mac was locked and a subsequent CUA access timed out. Canonical popup
open/close is explicitly unverified; disposable VM and hosted native UI checks
are complete. See `installation/RESULTS.md`.

The Chinese card email “Wattson 5.0.3｜满电，自有节奏” was sent once after all
public gates and link checks. Sent-message readback verified both confirmed
recipients, subject, matching HTML/plain bodies and the embedded GIF. Personal
recipient addresses are excluded from the repository. See
`communication/sent-receipt.json`.

## Cleanup

Task-owned builds, tests, VM, browser profiles, preferences, containers, mounts,
downloads, Tap checkout, authorization and verification scratch are removed.
Only the canonical Wattson remains registered. Remote app and Tap repositories
have only `main`; no temporary release branch was created. Final distributions,
validation records and the diagnostic failed-run history are intentionally
retained. See `cleanup-audit.json`.
