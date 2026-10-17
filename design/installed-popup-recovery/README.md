# Installed popup recovery — Wattson 4.3.17

The canonical `/Applications/Wattson.app` is now **4.3.17**, from frozen source
`2e1884803bedc25a4877d7693e323af48a8e58bc`. The user confirmed that its main
popup opens and closes normally. Actual canonical status-button events also
record three opens and one close for PID 21641. App/helper payloads, signatures,
both App version fields, and package receipt verify against the exact native
PKG, SHA-256 `194d0e971521899a79d75633b787d17257a900e7b0691fa091922fadbbb93ddc`.
See [verification.json](verification.json) and the retained
[evidence archive](evidence.tar.gz).

## Failure and recovery

The user reported that installed 4.3.16 showed its normal battery icon and
percentage but never opened the popup. Actual events reached PID 18025 and
repeatedly recorded `openBefore=false openAfter=false`. Its main thread was
idle in the AppKit event loop. NSRunningApplication reported `isHidden=false`;
the failing process's internal NSApplication hidden state was not captured.

Stopping only that exact process with TERM, observing its exit, and relaunching
with `/usr/bin/open -g /Applications/Wattson.app` restored normal behavior.
The user confirmed visible opening and closing, and PID 19893 recorded three
opens and two closes. Preferences were not reset. No host mouse or keyboard
events were injected.

The installation verifier had used `open -g -j`. **A separate, controlled native
VM comparison reproduces failure specifically with the hidden-launch `-j`
option:** normal and `-g` launch open the real glass panel, while `-g -j` leaves
NSApplication hidden and the popup absent, despite a valid, visible status
anchor and valid placement. After the fix, all three launch modes show the
popup; the hidden case explicitly changes hidden→unhidden.

This establishes a reproducible trigger and a defect in the prior verification
path. It does not fully reconstruct the original host instance: the host's
NSRunningApplication observation and the VM's internal NSApplication state are
different observations. The exact original presentation guard remains unproven.

## Minimal fix and acceptance

`PopoverController.open` now calls `unhideWithoutActivation()` when an explicit
open request finds NSApplication hidden. This adds one conditional on opening,
without adding sampling, timers or per-frame work. The install verifier drops
`-j` and retains the native postinstall's existing `-g` launch. The debugging
guide requires actual canonical popup acceptance separately from stable PID
checks. [verification-launch.patch](verification-launch.patch) records the
one-off verifier correction; the earlier archived verifier remains historical.

The release changes only PopoverController, VERSION and a targeted interaction
regression. History geometry and animation sources match frozen 4.3.16 exactly.
Native regression tests establish real hidden state and verify visible opening
for both Classic and Liquid Glass hosts. The full production-renderer suite
passes **438 AppKit assertions**, and **55 focused Python contracts** pass.
The separate launch-mode diagnostic is a DEBUG, unoptimized fixture, not a
performance benchmark. The canonical user confirmation tests the actual release
binary on macOS 26.5.2; the disposable ARM GUI VM runs macOS 26.6.1.

Universal arm64/x86_64 artifacts build and verify. The PKG and helper-free DMG
contain byte-identical Apps. The exact PKG installs in the VM with healthy
helper; its battery-free VirtualMac intentionally exits the real App at startup,
and that limit is explicit in the VM receipt. Host installation verifies a
new stable PID, healthy helper and exact payloads. The user then confirms the
canonical popup's actual opening and closing.

This is a local candidate update. App/helper are ad-hoc signed, PKG/DMG unsigned
and not notarized. No public CI, GitHub publication or release email is claimed.
The four final artifacts remain in `dist/popup-open-fix-v4.3.17`; the prior final
4.3.16 set is retained once for recovery.

## Cleanup and evidence

The VM audit finds no remaining owned test preferences, containers, executables,
project directories or registrations across eleven recorded domains and two
executable paths. It also scans the task's UUID prefixes for the first wrapper's
unrecorded prelaunch resources. The owner exits zero, deletes only its own VM,
and leaves macOS-TestLab and its Base stopped. The guest's native package fixture
belongs to that deleted clone.

After hashing and preserving the final evidence, this task removes its source
worktree, the previous History task's redundant scratch, repeated raw extraction
trees, compiler outputs and abandoned installer prototypes. Only final installer
sets and one canonical copy of necessary review evidence remain. The cleanup
scope and directory accounting are recorded in [cleanup.json](cleanup.json).

`evidence.tar.gz` contains the before/after event logs, narrow process sample,
launch-mode red/green records and exact fixture inputs, native source/tool
manifests and transfer archive, build and installation logs, and ownership audits.
The initial diagnostic wrapper failed on an empty array under Bash 3.2 `set -u`;
its corrected nonempty command array is used for both recorded red/green runs.
That setup failure is not counted as a product failure. One inherited audit
description had the old fixture version; its explicit annotation is corrected
against the independent 4.3.17 installed-payload receipt, without changing audit
findings. All retained files are covered by `SHA256SUMS.txt`.
