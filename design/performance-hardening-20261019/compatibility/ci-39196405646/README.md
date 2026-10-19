# Fourth macOS 27 validation: universal verification failed

[Run 39196405646](https://github.com/laleoarrow/battery-monitor/actions/runs/39196405646) completed **failure** on source `67f39101c5ec9582561166a14a04e1970da7fa3d`. The actual runner was macOS 27.0.1 (26A434), Xcode 27.0 (27A266a), SDK 27.0, arm64, image `xcode-27-arm64` version `20261012.0260.1`. Source and environment are confirmed in the job preflight and the matching Swift diagnostics artifact.

| Gate | Actual result |
| --- | --- |
| Swift build and XCTest | Passed; 634 App + 30 helper tests, 0 failures |
| Headless Python | Passed; 612 tests, 0 failures, 4 explicitly opt-in GUI skips, 376.484 s |
| Native baseline / legacy / accessibility | Three actual `ALL_INTERACTION_CHECKS_PASSED` markers; 462 / 460 / 455 successful assertion log lines, with the qualification below |
| Animation stress | Actual `ANIMATION_STRESS_PASSED iterations=20000 elapsed=0.124s` |
| Universal release build | **Failed** at `lipo` argument parsing after both release slice builds completed |
| Website | Build, 7 Node tests, lint and export passed |

At 04:05:05 UTC the first universal verification error was `lipo: -verify_arch requires exactly one input file`; the next line was `build_release.sh: binary is not universal .../universal/Wattson`. The frozen invocation is `scripts/build_release.sh:101`. Both release builds completed (28.58 s and 29.02 s), but this result does **not** establish universal architectures, minimum OS 12, release signatures or packaging acceptance. See `failure-analysis.json` and the raw job log. This monitor made no production or CI edits.

Every native variant logged `⏭ 当前系统同步完成关闭：没有可验证的关闭中途重开窗口`: AppKit closed synchronously, so the mid-close reopen path was unexercised in all three variants. No `PROCESS_ACTION_BUTTON_FOCUS_UNEXERCISED`, screen-lock skip or history-motion skip marker occurred. All variants actually logged the process-row Space events and both action-button focus identity reorder checks; the ALL markers alone were not used to infer these. Exact lines and flags are in `verification.json`.

The raw test job log is `job-117880032535.log`, website log `job-117880032664.log`. Artifact 12162088114 contains the four allowlisted diagnostic text files; its archive SHA-256 matches the GitHub API digest, and the retained file hashes are recorded. Temporary archive/download scratch was owned, automatically cleaned and checked locally. No runnable artifact, source cache, installation or signing secret was fetched.

Remote cleanup claims remain narrow: the existing lifecycle entrypoints configured cleanup for their owned resources, native scripts returned success, and the release entrypoint exited on its verification error. The Swift owned-defaults cleanup regression passed. No independent whole-runner census of residual preferences, containers, registrations, mounts or child processes was performed. Hosted ARM GUI coverage also does not prove physical SMC/battery behavior, real privileged-helper installation/TCC prompts, notarization, Intel runtime or oldest supported runtime behavior. The public-preview runner is not a stable-infrastructure guarantee.
