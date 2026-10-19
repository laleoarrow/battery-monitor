# Second macOS 27 validation attempt

[Run 39195186472](https://github.com/laleoarrow/battery-monitor/actions/runs/39195186472)
tested source `683bf7699f4ee612896406325eb03a4af74b474a` and finished with a
**failed Swift test gate**. No cancellation or rerun was performed by the
monitoring agent.

The actual runner logs identify macOS 27.0.1 (26A434), Xcode 27.0 (27A266a),
SDK 27.0, arm64, and image `xcode-27-arm64` / `20261012.0260.1`. These are
observed run values, rather than substitutions from image documentation.

Ordinary package build and the separate `swift build --build-tests --jobs 2`
succeeded. The latter completed in 25.32 seconds. `swift test --skip-build`
then ran and exited normally: the app XCTest target executed **634 tests with
155 failures** in 28.290 seconds; the helper XCTest target executed **30 tests
with zero failures**. This was not a six-minute timeout or an incomplete test
summary. The trailing Swift Testing output with zero tests does not replace
the failed XCTest outcome.

All 155 error assertions in the retained raw log concern test cleanup: 149
report an owned test domain was not found, using the quoted-domain message
format; six assertions belong to
`TestDefaultsCleanupTests.testPersistedSuiteFileStaysRemovedAfterDaemonReads`
at `SwiftTests/TestDefaultsCleanup.swift:78/84`. See `failure-analysis.json`.
This record locates the test boundary; it does not diagnose product settings
or UI behavior as broken. Test preference cleanup is not marked verified.

The Python suite, three native interaction variants, stress run, and universal
release build were skipped after the Swift failure. None is counted as passed.
The independent website job succeeded.

Both job raw logs, final job/run metadata, and the always-uploaded diagnostic
artifact are retained. Artifact **12162036130** was verified by its reported
SHA-256 and exact source identity, and only its four allowlisted text files
were saved under `swift-diagnostics/`. The archive and CLI temporary downloads
lived inside shared-lifecycle-owned project scratch and were removed. No
runnable app, installer, or source cache was downloaded. `verification.json`
records the complete qualified result and retained-file hashes.
