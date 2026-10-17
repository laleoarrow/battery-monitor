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
In `e627969`, the fourth icon (Power History) extends only its area gradient to
the horizontal axis end. The line, nodes and row geometry are unchanged. The
`402991a` gallery below predates this fill-only adjustment.

## Latest fill-only captures

Source `e62796901dae2255d7645840c21e0ee9b6b8f8c3` was rendered in the disposable
ARM VM using the production Settings renderer. These two unedited own-window
captures show the updated fill in Standard appearance, without Increase Contrast:
[Light](integrated/fill-extension/standard-light.png) and
[Dark](integrated/fill-extension/standard-dark.png).
Both are 1472 × 1072 pixels. Source identity and original hashes are retained in
`.build/modules-drag-review.noindex/rapid-native-ui3-review.noindex/icons-e62796901dae-delta/`.
They record appearance only, not successful drag interaction.

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

On `402991a`, overall drag acceptance remained blocked. Rapid Classic and
Standard drops left a half-opacity source row and a live drag session until
Escape. That observer wrote JSON synchronously around native callbacks, which
could perturb timing; a separate lower-overhead observation was prepared before
attributing a production cause. Original failures are retained, and successful
retries do not replace them. The host locked during that remaining check, so no
further mouse coverage is claimed for that run. Detailed evidence is retained under
`.build/modules-drag-review.noindex/final-4311-ui-v2-review.noindex`.

## Current candidate verification

Candidate `e627969` includes the `b5fcedd` drag preflight fix. It checks the left
mouse-button bit before creating the row snapshot and again immediately before
registering the original order and dragged module. A gesture already released,
or released while preparing that snapshot, cannot start a new native session.
Keyboard, accessibility and menu reordering use the unchanged `move` path.

All eight Settings contracts pass in the disposable VM with interaction enabled.
The native harness completed its assertions in 141.524 seconds; the full test
suite took 149.185 seconds. This includes 500 window reuse cycles, 500 constructed
window lifecycle checks and five DEBUG preflight cases: button masks `0`, `2`,
`1 → 0`, `1 → 2`, and `1 → 1`. The first four reject a gesture without a held
left button; the last preserves the original mouse-down event at the
session-start boundary.
The test callback returns before starting a native drag, so these checks do not
prove real pointer delivery or successful native drag-and-drop. The last three
cases require `WATTSON_RUN_INTERACTION=1`. Logs and exit codes are retained in
`.build/modules-drag-review.noindex/rapid-native-ui3-review.noindex/contract-e62796901dae-v6/`.

The initial CUA `noWindowsAvailable` condition later recovered. Its zero-input
record, `cua-no-windows-before-input-e627.json`, remains historical evidence in
`.build/modules-drag-review.noindex/rapid-native-ui3-review.noindex/`; it is
neither a product pass nor a product failure.

The subsequent real-input observations have these narrower results:

| Case | Result | Scope |
| --- | --- | --- |
| `classic-fast-1` | Released-before-native rejection verified | The actual drag handler observed the left button already released. |
| `classic-diagonal` | Released-before-native rejection verified | The actual drag handler observed the left button already released. |
| `standard-diagonal-2` | Released-before-native rejection verified | The actual drag handler observed the left button already released. |
| `standard-outside` | Released-before-native rejection verified | Rejection before any native session; not a native outside cancellation. |
| `standard-fast-1` | Unverified | The starting input did not reach the reorder handle. |
| `standard-held-drop` | Unverified | No input arrived before the 600-second fixture deadline; exit 124. |

For the four verified rejection cases, the original handler was forwarded once,
the mouse-up handler was observed, no native begin/end callback occurred, and
order, visibility, row identities, window and scroll position stayed unchanged.
All row alphas stayed at 1, drag state stayed clear, and preference writes and
notifications remained zero. Their `independent-rejection-verification.json`
records pass all rejection assertions in `cases-e62796901dae-v6/` under the same
review directory. The original native-drop/cancel evaluations remain unverified;
these rejection results do not replace them or count as successful native drops
or cancellations. No new live-session hang was observed in these four cases.

For `standard-held-drop`, the fixture window had automatically closed before
the user could try the held-button gesture. Its zero-input timeout is retained
in `manual-e62796901dae-v6/drag/manual-classic-0/`. Normal held-button dragging
remains unverified on this source, and the earlier `402991a` failures are
preserved. Fixture cleanup and its audit are handled by the owning stage.

The separately coordinated local candidate installation has explicit user
authorization. This record does not claim complete drag acceptance or announce
a public release.
