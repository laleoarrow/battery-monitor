# Process action button refresh reduction

Only `ProcessActionButton.isEnabled` changed: its own appearance refresh now runs when the enabled value changes. AppKit still receives the assignment. No image cache, layout, color, behavior or accessibility policy was added or changed.

The new behavioral regression holds the resolved image and glyph color through 50 identical enabled assignments per stage, covering enabled → disabled → enabled in Aqua and Dark Aqua (300 no-op assignments). On the original production button it fails all six image-identity assertions; with the guard it passes. The full eight-test button class also passes, including real action enable/disable, tint/theme updates and opaque accessibility colors. Image identity proves avoided glyph replacement; these elapsed test times are not a controlled performance benchmark.

Commands used `xcrun swift test --scratch-path <owned .noindex>/swiftpm --filter ProcessActionButtonTests.testRepeatedEnabledStatePreservesTheResolvedGlyph` for baseline, then the full `ProcessActionButtonTests` filter for the fix. `scripts/lib/local_cleanup.sh` and its bounded runner owned each build directory and module cache, and removed them on exit. SwiftPM managed its standard temporary files; no GUI windows, app registrations or test preferences were created by these tests.

The first setup attempt used a project-local TMPDIR and Swift 6.3.3 failed before compilation. The compiler separately trapped on `swiftc -print-target-info` with that TMPDIR. Its log and exit code remain preserved separately; they are not counted as the baseline regression. Standard TMPDIR with owned build/module cache paths succeeded.

See `verification.json`, the baseline/fixed input SHA-256 records and both complete test logs. The immutable baseline source is retained as evidence. Root owns the separate TopProcessesView update-path optimization and integration checks.
