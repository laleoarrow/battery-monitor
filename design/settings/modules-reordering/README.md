# Modules ordering and Ring Gauge icon

The existing five module rows retain their labels and switches. A separate
trailing handle starts native drag-and-drop. Only a valid drop saves the order;
canceling keeps the previous order. Up/Down keys and accessibility Move Up/Down
actions provide another way to reorder. The Settings list, popover sections and
quick module menu share the saved order. Hidden modules retain their positions.
The fixed header and footer stay outside the user-controlled module order.

Reordering moves existing arranged views without detaching History or refreshing
telemetry. It preserves the chart data, animation, scroll offset and focus.
Reduce Motion removes row displacement and the drag return animation.

The current source uses the five reference-faithful neutral-and-blue vector
icons in [the vector artwork review](../module-icons-vector/README.md). All five
non-template images regenerate for appearance and contrast changes. Row dimensions
are unchanged. The captured gallery below predates this five-icon refresh and
shows the earlier glyphs; its original source and image hashes are retained.

## Actual native captures

These are production AppKit renders in a disposable ARM VM running macOS 26.6.1.
They use isolated preferences and read-only system dependencies. The image
manifest records the source commit and SHA-256 of each unedited PNG.

| Appearance | Light | Dark |
| --- | --- | --- |
| Classic | [Light](classic-light.png) | [Dark](classic-dark.png) |
| Standard | [Light](standard-light.png) | [Dark](standard-dark.png) |
| Clear | [Light](clear-light.png) | [Dark](clear-dark.png) |

## Verification

The native Settings contract passes, including keyboard/accessibility reordering,
stable toggle identity, window reopening and lifecycle checks. The eight settings
storage tests and four native view tests pass in the VM. The view tests verify
actual section adjacency using the parent stack coordinate system, plus retained
History objects, data, animations, focus and scroll position.

Actual mouse drag-and-drop verification remains pending. Synthetic queued
NSEvents reached the handle but did not establish a verified destination drop;
that attempt returned 78 and is not counted as a pass. A second disposable VM
opened the passive manual fixture, but the host lock prevented the UI tool from
operating it. No successful system drag-and-drop is claimed from either attempt.

This source change does not install or publish a new application version.
