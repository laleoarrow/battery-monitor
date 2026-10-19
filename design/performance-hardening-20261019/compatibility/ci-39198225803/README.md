# Fifth macOS 27 validation: configured full gate passed

[Run 39198225803](https://github.com/laleoarrow/battery-monitor/actions/runs/39198225803) completed **success** on frozen source `4532daac11c0698ab97f05a6fc47e563b16d4e0e`. App/Core/Helper production source is unchanged from fourth-run source `67f39101c5ec9582561166a14a04e1970da7fa3d`; only the listed lipo verification scripts/workflows and related tests changed. Actual job preflight and the source-matched Swift artifact confirm macOS 27.0.1 (26A434), Xcode 27.0 (27A266a), SDK 27.0, arm64, image `xcode-27-arm64` version `20261012.0260.1`.

| Gate | Actual result |
| --- | --- |
| Swift build and XCTest | Passed; 634 App + 30 helper tests, 0 failures |
| Headless Python | Passed; 613 tests, 0 failures, 4 explicitly opt-in GUI skips, 318.382 s |
| New real Mach-O verifier regression | Explicit `... ok` at raw job log line 2279 |
| Native baseline / legacy / accessibility | Three actual `ALL_INTERACTION_CHECKS_PASSED` markers; 462 / 460 / 455 successful assertion log lines, with the qualification below |
| Animation stress | Actual `ANIMATION_STRESS_PASSED iterations=20000 elapsed=0.149s` |
| Universal release App + helper | Build-only verification completed; arm64 + x86_64, minOS 12.0, bundle and strict signatures enforced by the frozen entrypoint |
| Website | Build, 7 Node tests, lint and export passed |

Every native variant logged `⏭ 当前系统同步完成关闭：没有可验证的关闭中途重开窗口`: AppKit closed synchronously, so the mid-close reopen path was unexercised in all three variants. No `PROCESS_ACTION_BUTTON_FOCUS_UNEXERCISED`, screen-lock skip or history-motion skip marker occurred. All variants actually logged process-row Space events plus both action-button focus identity reorder checks. Exact emitted markers, evidence lines, variant flags and qualifications are in `verification.json`; ALL markers alone were not used to infer focus coverage.

The successful universal step emitted `Verified universal release build for Wattson 4.3.22` at line 3995 and the disposable-release exit marker at line 3999. In the source-frozen scripts, these occur after both App/helper per-architecture lipo and vtool minOS checks, required bundle resources/metadata checks and strict codesign verification. These successful fail-closed checks establish the stated build properties; separate raw vtool/codesign detail dumps were not retained. The App was signed using the configured `BatteryPowerApp.entitlements`, with **ad-hoc** signing. `--build-only` exits before the packaged production-entitlements canonical comparison: that comparison, Developer ID verification, notarization and PKG/DMG installation were **not executed** by this run.

The raw test job log is `job-117885525517.log`, website log `job-117885525769.log`. Artifact 12162797576 contains exactly four allowlisted diagnostic text files; archive SHA-256 matches the GitHub API digest and source.txt matches the frozen commit. Retained hashes and source-frozen validation file hashes are recorded. Download/archive scratch was owned, automatically cleaned and checked locally. No runnable artifact, source cache, installation or signing secret was fetched by this monitoring task. No production/CI edits, dispatch, cancel or install were performed by this monitor.

Remote cleanup claims remain narrow. The existing lifecycle entrypoints configured cleanup for owned resources, native/release scripts completed successfully and the Swift owned-defaults cleanup regression passed. GitHub post-job cleanup additionally logged termination of one orphan `ibtoold`; this is runner cleanup evidence, not an independent whole-runner audit. No final census of residual preferences, containers, registrations, mounts or child processes was performed. Hosted ARM GUI coverage does not prove physical SMC/battery behavior, real privileged-helper installation/TCC prompts, Developer ID/notarization, Intel runtime or oldest supported runtime behavior. The public-preview runner is not a stable-infrastructure guarantee, and these passing configured gates are not a guarantee of zero bugs.
