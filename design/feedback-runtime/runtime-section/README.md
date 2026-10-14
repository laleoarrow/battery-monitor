# Independent battery-runtime section

This historical centered layout is superseded by the
[selected clock-left runtime layout](../runtime-layout/README.md), which follows
the user's theme and separator corrections. The evidence below belongs to the
earlier revision.

The runtime module occupies its own 64-point instrument below the power header.
A centered clock symbol and 24-point time reading sit above a quiet 10.5-point
caption. Non-numeric states use 16-point secondary text. The existing top
separator and the next visible section's separator define the section without
adding a card, outline or background. Hiding runtime removes exactly 64 points without leaving a gap;
runtime can also remain visible with every other optional module hidden.

This revision follows the user's preference for a prominent time reading and
subtle caption consistent with the existing gauges, replacing the earlier
44-point label/value row.

## Actual AppKit previews

- [Dark](runtime-section-dark-battery.png)
- [Light](runtime-section-light-battery.png)

These images come from the production `PopoverContentViewController`, rendered
into AppKit bitmap caches in hidden windows. They show Classic with Reduce
Transparency and Reduce Motion enabled. They verify content layout, not the
WindowServer-composited Liquid Glass material, native popover outline or shadow.

All displayed power readings, the 265-minute runtime (`4h 25m`), battery details
and history are deterministic fixtures, not measurements of this computer.
The system-battery-icon state is a presentation fixture (`false`). Footer energy
mode uses the process's existing cached/default mode; the Low Power snapshot
case does not change or simulate the computer's power-mode setting.

## Verification

On 2026-10-14, the reusable
[`capture_runtime_sections.swift`](../../../tests/visual/capture_runtime_sections.swift)
harness passed **279 assertions across 12 cases**: Light and Dark for charging,
full, on-battery, mixed supply, low battery and Low Power snapshots. Checks cover
header and runtime text fitting, centered icon/readout geometry, caption
hierarchy, the runtime separator and padding, full popup/footer containment,
runtime visibility, exact height
removal and no residual gap when only runtime or no optional modules remain.

The full Swift suite passed 381 tests with warnings treated as errors, and the
focused Python module contracts passed 27 tests. After a final vertical-alignment
adjustment using the text field’s intrinsic height, all six runtime tests and
the 279 capture assertions passed again. The real-window interaction
harness now uses the new section height; it was not rerun for this layout-only
revision. Earlier host-click evidence remains in the linked runtime-module review.

All windows stayed hidden and never became key. The foreground application was
unchanged. Hashes of the installed app, helper and existing preference files
were unchanged. The temporary settings suite was removed. The harness performs
no live battery sampling, helper IPC, status-item creation or app activation;
the production footer only checks whether the helper socket exists.

[`evidence.json`](evidence.json) records per-case checks, frame geometry, source
and executable hashes, image hashes and the unchanged protected-file hashes.
Only the two full battery images are retained here; the other ten captured
images remain in ignored `.build/runtime-section-preview.noindex/instrument-captures`.
The first harness run used bottom-up root coordinates for top-down adjacency
checks; the capture harness was corrected to normalize coordinates and rerun.
No production change was needed for that test-harness correction.

To reproduce from the repository root:

```bash
mkdir -p .build/runtime-section-preview.noindex
xcrun swiftc Core/*.swift MenuBar/*.swift Popover/*.swift \
  tests/visual/capture_runtime_sections.swift \
  -D DEBUG -warnings-as-errors \
  -framework AppKit -framework CoreGraphics -framework IOKit \
  -o .build/runtime-section-preview.noindex/capture_runtime_sections
WATTSON_FORCE_REDUCE_TRANSPARENCY=1 WATTSON_FORCE_REDUCE_MOTION=1 \
  .build/runtime-section-preview.noindex/capture_runtime_sections \
  .build/runtime-section-preview.noindex/instrument-captures
```
