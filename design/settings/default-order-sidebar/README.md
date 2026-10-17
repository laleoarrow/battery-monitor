# Modules default order and sidebar artwork

Local candidate 4.3.12, frozen production commit `5d5c896b7a1531ce4f9783fa467ff8c8eb62b82e`.

- Modules now provides **Restore Default Order** beside the subtitle. It restores the five-module order only; switches and existing module views remain unchanged. Repeated restoration is a no-op.
- General, Display, and Modules use the approved sidebar vector family. The Display title-bar accent is on the right. Emphasized selection uses white artwork, with light/dark and increased-contrast refresh.
- The restore control remains reachable by keyboard after the final reorder handle. Its 22-point height fits Classic, Standard, and Clear layouts.

## Evidence

The ten PNGs are real composited AppKit windows in the disposable headless macOS 26.6.1 VM, with production geometry and fixed fixture preferences. They are not images of the user's host preferences. Source state was frozen before building.

Settings contracts: 8 passed, including actual `performClick` restoration, one change notification, unchanged hidden-module choices, repeated restoration without another change, retained row/switch identities, accessibility, keyboard loop, and readable non-overlapping controls. The four ModuleOrderView tests passed, including restoration with retained History state, module view identity, focus, scroll, and quick-menu order. Eight storage tests and seven static contracts passed separately.

The exact PKG passed previous-version install (4.3.11), disabled-helper upgrade to 4.3.12, fresh install, reinstall, and disabled-helper reinstall. Each checked payload identity, receipt, app/helper signatures, helper health and v5. PKG and DMG contain byte-identical app payloads.

The first screenshot fixture mistakenly used `display` instead of `menu-bar-icon`, so its two mislabeled Display captures showed General. Those are retained in ignored raw evidence and excluded here. Only the two corrected Display captures are included. The first test-source compile also used `.standard` instead of the production enum's `.regular`; the corrected contract compiled and passed in the VM. Neither harness correction changed production code.

Existing native-held drag validation remains **unverified** from the previous work; these checks do not claim new pointer-driven drag coverage. No public release or Cody notification is part of this candidate.

Raw logs and lifecycle records: `.build/modules-default-sidebar-review.noindex/`. Final installation and cleanup status are recorded separately in `verification.json`.

The canonical local installation completed successfully through native Installer. App, helper and LaunchDaemon matched the candidate payload, receipt and versions read back as 4.3.12, signatures and helper v5 passed, and the relaunched app stayed alive. Independent read-only immediate and delayed host audits found no owned scratch, installer processes, mounts or extra App registrations; the installed app and process remained unchanged after 99.919 seconds of system-monotonic quiet time.
