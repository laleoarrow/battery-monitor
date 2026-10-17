# General icon integration

Local candidate 4.3.13, frozen production commit `8529889597961de756fa57397b1d1149d6d1b536`.

The five General rows now use the approved neutral-and-blue vector family: Launch at Login, Hide System Battery Icon, Check for Updates, Check for Updates on Launch and Send Feedback. Artwork remains 20 points inside the existing 28-point alignment frame. Actions, accessibility identifiers, labels and control geometry are preserved. Effective appearance and Increase Contrast regenerate non-template artwork; decorative gradients disappear under Increase Contrast.

The prior Restore Default Order button, sidebar artwork, five Modules icons and History implementation are retained. The two native reorder classes are byte-identical to the 4.3.11 implementation; this artwork validation does not claim new held-drag runtime coverage.

Editable SVGs and the enlarged/actual-size native offscreen artwork proof are in [General icons](../general-icons-vector/README.md). This integration review contains 12 composited production AppKit windows from the independent macOS 26.6.1 test VM: top and bottom of General in Classic, Standard and Clear, each in Light and Dark. These are fixed test preferences, not screenshots of the host user's preferences.

No public release or Cody notification is performed by this local update. The next validated official release will include versioned design previews, actual screenshots and downloadable SVG originals under the existing release gates.

## Verified integration

Eight real Settings contracts passed in the disposable VM, including 500 reuse and 500 construction cycles. Eight host-safe Settings checks passed separately. The full universal release build verified byte-identical PKG/DMG App payloads. The exact PKG passed fresh installation of previous 4.3.12, disabled-helper upgrade, 4.3.13 fresh installation, reinstall and disabled-helper reinstall, plus payload/receipt/signature/helper-health/v5 and uninstall assertions.

Immediate and 112-second system-monotonic delayed VM audits passed all eight owned-resource and five package-residue checks. The owned GeneralRowIcons VM and temporary transfers were removed; the other task's running NormalSlowDrag VM and the stopped base/test VMs were preserved. This was correctness validation, not a performance measurement.

The canonical App was updated with native Installer using the verified package. Full App, helper and LaunchDaemon contents match that payload; App marketing/build and receipt are 4.3.13, signatures and helper health/v5 passed, and the relaunched process remained stable. The local package is community ad-hoc, not Developer ID signed or notarized. Installation and cleanup details are recorded in `verification.json`.

Raw source manifests, contract logs, package lifecycle results and installation verification are retained in `.build/general-row-icons-review.noindex/`.

Independent post-install host audits also passed: the delayed read began after 100.785 seconds of system-monotonic quiet time, with installed payload identity, receipt, signature and normal PID unchanged. No owned temporary installation files, installer/verification processes, mounts or extra Spotlight/LaunchServices registrations remained.

## Running-window gallery

| Appearance | Top rows | Feedback row |
| --- | --- | --- |
| Classic Light | [Top](classic-light-general-top.png) | [Bottom](classic-light-general-bottom.png) |
| Classic Dark | [Top](classic-dark-general-top.png) | [Bottom](classic-dark-general-bottom.png) |
| Standard Light | [Top](standard-light-general-top.png) | [Bottom](standard-light-general-bottom.png) |
| Standard Dark | [Top](standard-dark-general-top.png) | [Bottom](standard-dark-general-bottom.png) |
| Clear Light | [Top](clear-light-general-top.png) | [Bottom](clear-light-general-bottom.png) |
| Clear Dark | [Top](clear-dark-general-top.png) | [Bottom](clear-dark-general-bottom.png) |
