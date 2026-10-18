# macOS 27 compatibility review

This read-only source review found **no demonstrated macOS 27 regression that
justifies a production patch**. It also cannot establish that Wattson has been
tested on macOS 27. The distinction matters: source inspection and successful
macOS 26 tests do not prove behavior on a different WindowServer, AppKit,
launchd, or kernel.

The official [macOS 27 release notes](https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes)
were checked against the downloaded research input. A fresh public Markdown
fetch matched its SHA-256 exactly; `official-source-verification.json` records
the URL, time, and hash without retaining another copy of the document.

## Available environment

`environment-inventory.json` records macOS **26.5.2 / 25F84**, Xcode **26.6 /
17F113**, and active macOS SDK **26.5**. Neither the active Xcode nor the
Command Line Tools SDK inventory contains a 27 SDK. The existing disposable
focus-test clone reported **26.6.1 / 25G76**, as recorded in
`../focus-native/baseline/results/system.txt`; that observation is not a 27
runtime result.

At the final inventory, Tart listed only the stopped user VMs `macOS-TestLab`
and `macOS-TestLab-Base`. `tart get` identifies the platform as `darwin`, not
the guest product version. Their disks were not mounted and they were not
started. No verifiable macOS 27 environment was found; this does not claim an
exhaustive search of every user disk or remote machine. No OS/SDK download,
upgrade, VM operation, installed-app restart, permission change, or helper
mutation was performed. No temporary artifacts were needed.

## Concrete validation gaps

| Gap | Production boundary | Required evidence on macOS 27 |
| --- | --- | --- |
| Native glass and host composition have only 26 runtime evidence. | `Popover/GlassPopoverMaterialView.swift:60` hosts the system SwiftUI glass; `Popover/GlassPopoverPanel.swift:59` uses a shaped low-alpha backing to retain WindowServer hit testing. | Run the existing production-renderer/native interaction suite on 27: Classic and native glass, Clear/Regular, light/dark, accessibility contrast/transparency/motion, arrow changes, scrolling/clipping, and blank-body hit testing. Test the already-built 26-SDK app and a 27-SDK rebuild separately. No claim is made that the low-alpha technique is broken on 27. |
| Live process and sensor permissions are not verified against a 27 kernel. | `HelperV5/TopProcesses.swift:185` uses `proc_pid_rusage`; `HelperV5/ProcessTermination.swift:155` combines task-name/audit-token identity with a dynamically resolved signal API; `Core/AppleSmartBatteryPowerObservationReader.swift:952` reads allowlisted registry properties. | Read-only sampling on real hardware; then use only an owned disposable child to verify successful termination and stale identity/permission-denial handling. A VM without battery/SMC access cannot validate real sensor success. The current code skips unreadable counters and maps unavailable/denied termination explicitly; no 27 API removal or new entitlement requirement was identified in the reviewed notes. |
| The documented launchd quarantine restriction needs target-OS installation evidence. | `scripts/package_pkg.sh:68` stages without inherited extended attributes and clears payload attributes at line 75; `Helper/wattson-helper.swift:1090` creates the per-user login plist. | Run the existing PKG installation/upgrade and launch-at-login lifecycle on 27, retaining plist quarantine/ownership and actual service/readiness results. Packaging already mitigates the documented condition; no broader quarantine bypass is proposed. The present host's daemon/login plists lack `com.apple.quarantine`, and the Homebrew workflow already asserts its absence at `.github/workflows/homebrew-install-test.yml:381`. |

These are missing target-environment observations, not three established bugs.
The current candidate install matrix lists 14, 15, and 26 at
`.github/workflows/macos-helper-install.yml:310`; it contains no 27 execution.
Do not rename a 26 job or treat a deployment-target setting as 27 validation.
This review does not repeat the separately assigned focus/button/helper-poll
implementation work.

## Release-note changes checked against actual use

- **Menu images:** Apple documents SDK-dependent hiding of `NSMenuItem` images.
  Wattson's module, ring-metric, application, and reorder menu items use text
  titles and do not assign custom menu-item images
  (`Popover/PopoverContentView.swift:1179`,
  `MenuBar/StatusItemController.swift:393`,
  `MenuBar/SettingsWindowController.swift:2990`). Its menu-bar battery graphic
  is `NSStatusBarButton.image` (`MenuBar/StatusItemController.swift:746`), a
  different API. No `preferredImageVisibility` workaround is justified here.
- **System stat names:** The documented conflict involves unqualified `stat`
  calls inside custom `FilePath`/`FileDescriptor` extensions. This project has
  no such extensions or `System` import; its Darwin calls do not meet that
  trigger. No speculative renaming is needed.
- **SIP/TCC:** The reviewed production paths do not read `TCC.db` or another
  developer team's app containers. They use allowlisted IOKit/libproc APIs,
  Wattson-owned files, and a fixed current-user/current-host Control Center
  preference (`Helper/wattson-helper.swift:1221`). The release notes do not
  establish that this preference API is newly forbidden. No new Full Disk
  Access, Accessibility, or SIP changes are warranted from this review.
- **Popover and gestures:** The project combines AppKit hosts with SwiftUI
  interactive glass; it does not subclass `NSGestureRecognizer` or initialize
  the changed `@State` pattern described in the notes. The documented platform
  gesture/keyboard changes make the existing native suite useful on 27; they
  do not establish a code defect by themselves.

Compatibility remains **source-reviewed; SDK 27 build and runtime 27 validation
pending**. Preserve that limit in release and user-facing claims.
