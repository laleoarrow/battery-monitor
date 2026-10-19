# Third macOS 27 validation attempt

[Run 39195603040](https://github.com/laleoarrow/battery-monitor/actions/runs/39195603040)
tested source `4bbe06679be64bf192157a47ebce135e250f107d`. The actual environment
was macOS 27.0.1 (26A434), Xcode 27.0 (27A266a), SDK 27.0, arm64, image
`xcode-27-arm64` / `20261012.0260.1`.

Swift builds and all **664 XCTest tests passed**: 634 app tests with zero
failures in 29.142 seconds, plus 30 helper tests with zero failures in 0.049
seconds. The prior owned-domain cleanup failures did not recur. Artifact
12161927190 was checked against its reported SHA-256 and exact source identity;
its four text files are retained in `swift-diagnostics/`.

The Python suite ran **612 tests with one failure and four skips** in 284.632
seconds. The failure was the standalone settings-window compiler fixture,
`test_appkit_window_layout_state_and_release_contract`. The compiler reported
`ImplicitStrongCapture` at `SettingsWindowController.swift:2077:50`: the nested
weak `self` capture differs from the implicit strong outer capture at line
2072. The precise traceback is in `failure-analysis.json` and the complete job
raw log. This was a completed failure, not a timeout.

Native interaction, animation stress, and universal release-build validation
were not executed after the Python failure. No success is claimed for those
gates. The independent website job passed. This attempt therefore does not
establish full macOS 27 acceptance.

`verification.json` records qualified gate results and hashes. Metadata,
both raw job logs, and verified diagnostic text are retained. Download ZIPs
and temporary files used shared-lifecycle-owned project scratch and were
removed; no app, installer, or source cache was downloaded. No production/CI
edits, cancellation, or rerun were performed by this monitoring agent.
