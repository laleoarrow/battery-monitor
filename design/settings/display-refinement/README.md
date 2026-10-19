# Display settings refinement

The requested direction is consistent with Wattson's native settings: simple,
clear, restrained surfaces and precise alignment. Existing battery artwork and
all four icon-style/percentage combinations remain available.

The page separates the two existing preferences. Two selectable style rows share
seven state headings and use the production BatteryIcon renderer at natural
size. A small Off/On popup controls percentage display in both rows. Selection
uses the existing theme colors, a light fill and a thin outline; high contrast
uses a neutral opaque fill and a stronger label-color outline so the production
battery artwork remains legible. Changes retain controls, keyboard focus and the other
preference, with no helper requests or new saved settings.

Production changes are restricted to the Display section in
`MenuBar/SettingsWindowController.swift`. The canonical installed 4.3.23 app is
not used for testing. The owned VM workflow in [qa](qa/README.md) compares the
old and new production Settings hierarchy at the same window size, captures
Classic/Glass and Light/Dark, and runs the native settings contract. Validation
results and real rendering evidence are recorded alongside this brief.

The shared state titles use neutral equal-width cells, matching the preview
columns without letting native text-field alignment padding alter their widths.
The row and focus outlines are inset within the surrounding Glass surface;
neither content alignment nor the click target moves when selection changes.

Earlier verification runs are retained as rejected evidence:

| Source | Reason rejected | Resolution |
| --- | --- | --- |
| `759ac29` | External window screenshot required unavailable permission. | Capture only the fixture's own window with the SDK's current-process API. |
| `b2f00e4` | Guest Bash 3.2 rejected an empty array; Tart masked the remote failure. | Fix the empty-array expansion and require real capture and contract completion gates. |
| `38984cd` | The test treated native text-field transparent alignment padding as clipped text. | Check actual text alignment, advance and CoreText ink bounds without changing the font. |
| `7b7b923` | Native contract found a real shared-header column offset. Visual review also found a clipped lower selection outline and weak high-contrast selection. | Align header cells with previews and refine only Display's drawing and high-contrast palette. |

The accepted source is `fa6c88f7ce40a7aa435b0334f222098a58d8c057`.
Its fresh owned-VM run is in `evidence-fa6c88f`. On ARM macOS 26.6.1, all 30
real compositor captures and the complete eight-test native Settings contract
passed. All 26 new frames retain natural image sizes and 10.5pt percentage
digits; the maximum header-center difference is 0.75pt. Selection, keyboard,
focus, all four saved combinations and in-place appearance refreshes passed.
The lifecycle contract completed 500 window reuse cycles, 150 warmup controller
creations and 500 stress creations/releases; file descriptors remained 9 and
the memory plateau spread was 999,424 bytes, within the existing gate.

The 12 execution gates, nine guest-resource checks and 35-second preference
observation passed. The owned VM was removed, both existing TestLab VMs were
preserved, and the installed 4.3.23 app, PID, helper, daemon and all 16 settings
remained unchanged. No release or installation is part of this refinement.

See [verification.json](verification.json), [execution gates](evidence-fa6c88f/gate-results.json)
and [geometry review](evidence-fa6c88f/geometry-review.json) for exact evidence.
Raw logs with trailing whitespace are stored losslessly as `.raw.gz`; the
[storage manifest](raw-log-storage.json) records original paths and byte hashes.

Actual production-renderer previews:

- [Glass, dark](evidence-fa6c88f/results/after-baseline/glass-dark-percentage-on.png)
- [Glass, light](evidence-fa6c88f/results/after-baseline/glass-light-percentage-on.png)
- [Classic, light](evidence-fa6c88f/results/after-baseline/classic-light-percentage-on.png)
- [macOS 26 selected](evidence-fa6c88f/results/after-native-selected/glass-light-percentage-on.png)
- [Increased contrast](evidence-fa6c88f/results/after-high-contrast/glass-light-percentage-on.png)
