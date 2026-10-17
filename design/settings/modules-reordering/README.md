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
are unchanged. Mouse interaction no longer leaves a blue outline around the
drag handle. Keyboard navigation still exposes the focus cue.

## Integrated icon and focus captures

Source `402991a57fcbfa715e053b636cc54aceeb0a0a83` was compiled without production
source changes and rendered in the disposable ARM VM. All 12 unedited own-window
captures were visually reviewed (three styles, two appearances, both contrast
settings); no clipped artwork or persistent default focus outline was found.
[Capture manifest](integrated/capture-manifest.json) records original hashes.

| Appearance | Light | Dark | Increased contrast |
| --- | --- | --- | --- |
| Classic | [Light](integrated/contrast-0/classic-light.png) | [Dark](integrated/contrast-0/classic-dark.png) | [Light](integrated/contrast-1/classic-light.png) / [Dark](integrated/contrast-1/classic-dark.png) |
| Standard | [Light](integrated/contrast-0/standard-light.png) | [Dark](integrated/contrast-0/standard-dark.png) | [Light](integrated/contrast-1/standard-light.png) / [Dark](integrated/contrast-1/standard-dark.png) |
| Clear | [Light](integrated/contrast-0/clear-light.png) | [Dark](integrated/contrast-0/clear-dark.png) | [Light](integrated/contrast-1/clear-light.png) / [Dark](integrated/contrast-1/clear-dark.png) |

Actual keyboard Up input shows the [focus cue](integrated/focus/keyboard-focus-visible.png).
A subsequent mouse click removes the [outline](integrated/focus/mouse-focus-hidden.png)
while retaining the same first responder. Paired JSON snapshots preserve the
read-only state, input events, unchanged order and zero preference writes.

## Earlier native captures

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

The eight Settings contracts and 12 Modules tests pass on the integrated source.
Real pointer cases passed for Classic drop and outside cancellation, Standard
outside cancellation, Clear drop, and Clear outside cancellation with Reduce
Motion. These passes require real AppKit source begin/end callbacks, unchanged
view identities, exact preference write counts and cleared drag state.

Overall drag acceptance remains blocked. Rapid Classic and Standard drops left
a half-opacity source row and a live drag session until Escape. The passive
observer writes JSON synchronously around native callbacks, which could perturb
timing; a separate lower-overhead observation is prepared before attributing a
production cause. Original failures are retained, and successful retries do not
replace them. The host locked during the remaining check, so no further mouse
coverage is claimed. Detailed evidence is retained under
`.build/modules-drag-review.noindex/final-4311-ui-v2-review.noindex`.

This source change does not install or publish a new application version.
