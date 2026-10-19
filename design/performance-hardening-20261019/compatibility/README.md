# macOS 27 compatibility review

The initial read-only source review found **no demonstrated macOS 27 regression that
justifies a production patch**. That inspection alone cannot establish that Wattson has been
tested on macOS 27. Subsequent target-runner attempts are recorded below. The distinction matters: source inspection and successful
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

At the initial local inventory, Tart listed only the stopped user VMs `macOS-TestLab`
and `macOS-TestLab-Base`. `tart get` identifies the platform as `darwin`, not
the guest product version. Their disks were not mounted and they were not
started. No verifiable macOS 27 environment was found locally; this does not claim an
exhaustive search of every user disk or remote machine. No OS/SDK download,
upgrade, VM operation, installed-app restart, permission change, or helper
mutation was performed. No temporary artifacts were needed.

## Original target validation plan

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

The initial source review is not a compatibility pass. The following hosted
runs add actual SDK 27 compilation and runtime evidence, with each incomplete
or failed gate preserved under its exact source commit.


## Subsequent hosted validation

Official GitHub runner documentation subsequently identified the opt-in
`xcode-27` ARM preview image; `macos-latest` was not substituted for 27. The
[availability record](runner-27-availability.json) identifies the official source.
The manual CI path checks actual OS/SDK major version, architecture and source
commit before validation. Normal CI retains its macOS 26 runner.

The [first target attempt](ci-39193369041/README.md), source `000fdeb`, passed
its macOS 27 / SDK 27 / arm64 environment guard and Swift package build. Its
Swift test phase did not finish during the observation period and the run was
cancelled. GitHub returned no Swift job logs in either the job API or run-level
archive. The last test case and cause are unknown. Python, native interaction
and universal release verification did not execute in that run. This cancelled
attempt is neither an application test failure nor a compatibility pass.

Source `683bf76` adds bounded test-bundle compilation and execution as separate
phases with retained artifacts. Test compilation uses two jobs to bound compiler
concurrency; this does not assert that memory pressure caused the first run.
The [second target attempt](ci-39195186472/README.md) completed test compilation
and executed all 664 Swift tests on macOS **27.0.1 / 26A434**, Xcode **27.0 /
27A266a**, SDK **27.0**, arm64, image **20261012.0260.1**. The 30 helper tests
passed. The App target reported 155 failures: 149 exact missing-domain cleanup
messages and six retained-file assertions in the cleanup fixture. Its old parser
recognized `Domain (name) not found.`; macOS 27 reports `Domain 'name' not found.`.
The guard returned before leftover-file removal. No other failure category was
observed. Python/native/stress/universal gates did not execute. Raw failure
records are retained rather than replaced by a successful retry.

Test-only `4bbe066` accepts that new exact-domain message, retaining the old format,
test-domain allowlist and all other failure handling. The focused cleanup test
passes on 26 with owned scratch removed; a third hosted run verifies 27 and the
remaining gates. This fixture correction is not a change to production behavior.
Physical battery/SMC readings, installed helper privileges, PKG upgrades and
launch-at-login still require their own target-environment acceptance.


The [third attempt](ci-39195603040/README.md), `4bbe066`, passes all **664 Swift
tests**. Python executes **612 tests** with four expected skips and one failure:
its Settings standalone compiler treats a new `ImplicitStrongCapture` warning
as an error. The normal Swift build reports the same warning without failing.
Native/stress/universal did not execute.

The compiler explicitly recommends making the outer capture explicit.
Production `67f3910` adds only `[self]` to that feedback-worker closure, preserving
its original strong capture and nested weak main callback. Independent source
review and an actual Pro follow-up agree; the targeted Settings executable
contract passes on 26. The fourth run checks that final source on 27.


The [fourth attempt](ci-39196405646/README.md), final App source `67f3910`, passes
all **664 Swift tests**, the **612 Python tests** (four expected opt-in GUI skips),
three native variants with actual completion markers, and the **20,000-iteration
animation stress gate**. Actual focus/button/Space cases execute. Each native
variant retains only the existing synchronous-close mid-reopen qualification.
This is hosted functional evidence, not full physical sensor or installer evidence.

The remaining gate failed after both release architectures compiled: the new
`lipo` reported that `-verify_arch` had more than one input for the existing
combined-architecture invocation. This is not evidence of an App compilation
or interaction failure. Packaging verification is being made portable by
checking each required architecture in a separate invocation, keeping both
requirements, deployment target and signature verification intact.


## Final hosted result

[Frozen `4532daa`](ci-39198225803/verification.json) passes the complete opt-in
workflow on the actual macOS 27.0.1 / Xcode 27 / SDK 27 ARM runner. The final
source passes all 664 Swift tests, 613 Python tests (four expected opt-in GUI
skips), all three native interaction variants, 20,000 animation stress
iterations and the universal App/helper build. The new real Mach-O verifier
regression executes successfully. App runtime files remain byte-identical to
the already tested `67f3910`.

All earlier cancelled and failed runs remain under their original source
identities. Native timing qualifications and exact build-only verification
boundaries remain in the final proof; a passing workflow is not a claim of
packaged entitlement comparison, Developer ID/notarization, PKG upgrades,
launch-at-login or physical battery/SMC acceptance. The released 26-SDK binary
on 27 and a full appearance cross-product are also separate observations.
