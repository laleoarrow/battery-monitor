# Exact native build-input subset — source 5d5c896b, Wattson 4.3.12

This is an immutable **subset of exact source/build-input bytes**, not the original full source archive and not a product test result. No VM, App, compilation, pointer input, or product acceptance test was run to derive this subset.

`source-5d5c896b7a15-native-build-inputs-subset.tar.gz` contains 58 regular files: all 52 recursive Swift sources under Core, MenuBar, and Popover; VERSION; the two source-side shared lifecycle scripts; and the three production in-app logo PNGs used by the Settings fixture. No historical design screenshots/movies, secrets, native fixture tools, VNC client/control code, app bundles, executable binaries, or build scratch are included.

Each member is byte-for-byte equal to the same path in frozen full source archive SHA-256 `8aa52b90ec8f2e7f93e2ccc7ebc2fd9ab7e89217a95bfd93edccbb3e90156ca3` and to its Git blob in commit `5d5c896b7a1531ce4f9783fa467ff8c8eb62b82e`. `subset-member-mapping.json` records every original archive member, SHA-256, byte length, Git blob object ID, and comparison result. `MEMBER_SHA256SUMS.txt` applies to paths inside the subset archive; `SHA256SUMS.txt` applies to this evidence directory.

The original complete archive remains a caller-owned input at:

`/Users/leoarrow/Project/mypackage/agents/电池功率/.build/modules-default-sidebar-review.noindex/source-5d5c896b7a15.tar.gz`

Its size is 115,241,614 bytes. This directory retains the original archive's identity and the exact relevant members; it does not contain or pretend to reproduce the original `8aa5…` full archive. The distinct subset SHA-256 is recorded in its mapping manifest.

## Source identity and compile scope

The immutable identity comparison covers **52 Swift files recursively**, including five in `Core/Diagnostics`. The actual observed native-fixture compiler invocation uses `Core/*.swift MenuBar/*.swift Popover/*.swift`, which compiles **47 top-level Swift files**. The existing runtime before/after production hash helper also uses top-level globs and therefore audits those same **47 files**. The five Diagnostics files remain included and independently byte-verified here; they were not compiled or re-hashed by that top-level runtime helper. These counts describe different scopes, not interchangeable checks.

The two included source-side lifecycle dependencies are `scripts/lib/local_cleanup.sh` and `scripts/lib/run_owned.py`. They have no additional project helper imports. The run wrapper also consumes VERSION and the three included PNG resources.

## Replay dependencies

The subset is sufficient for the source side of the recorded raw `swiftc` fixture build. It is not a replacement for every recorded stage input:

- Run only in a newly owned, approved disposable ARM GUI macOS test VM. The prepared fixture requires macOS 26 or later, Xcode command-line Swift/Clang, AppKit/CoreGraphics/IOKit, and ad-hoc `codesign`.
- The original frozen v6 test-tools archive has SHA-256 `89343e38e8ce2e0327bef3324d6a0d308dbfa1a99368409454c190dbe913c9a5`. The adapted VNC-labelled fixture archive has SHA-256 `5f65080f39ce54ab40b7971c9a9ef38534847cea8dff538c779b6da85c5c20b5`. Neither is duplicated here; they remain separately sealed parent-owned test inputs.
- The stage also requires its exact `stage-normal-slow-drag.sh`, `verify-production.py`, `validate-archives.py`, and bootstrap `lifecycle` helper files from the fixture evidence, plus the appropriate exact-version VNC client, guest lease probe, controller, ownership record, and authorization. Those separate tools and any credentials are outside this source subset.
- The recorded stage pins the original complete source archive's `8aa5…` hash. It cannot accept this differently hashed subset as that original input. Replaying the exact stage requires the original complete archive at the path above. Replaying only the native compile may use the subset after checking its own manifest and providing the separately sealed fixture tools; any new wrapper must record that derivation and preserve owned lifecycle cleanup.
- No VNC secret, private preference backup, or runnable artifact is a replay dependency to archive here. Credentials must be generated for and cleaned with the newly owned VM.

`build-subset.py` documents the exact member selection and Git/full-archive byte comparisons. Its owned `build-subset.sh` wrapper is a future derivation entrypoint: it uses the repository's shared lifecycle helpers, publishes only verified outputs, cleans temporary output on failure/interruption, and refuses to overwrite an existing immutable subset set. The current archive has already been verified by reopening it and comparing every member to the original bytes.

## Historical input-attempt boundaries

`historical-attempt-input-status.json` freezes only known failed controller-attempt status and hashes of its original raw records. It makes no product PASS claim:

- The v2 controller failed at the guest lease path check before the VNC client ran. Input was not attempted. Its fixture stage exited zero after owned shutdown; that is not an acceptance verdict.
- The v3 VNC client reported `inputAttempted: true`, `sequencePosted: true`, and exit zero, but the controller timed out waiting for the required native completion predicate. Posting is not proof of delivery or a successful native drag. Its fixture stage also exited zero after shutdown. Native acceptance remains unverified for that attempt.

No later attempt's result is asserted or inferred by this subset preparation.
