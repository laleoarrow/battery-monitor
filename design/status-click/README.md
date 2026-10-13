# Second status-item click review

Development review, 13 October 2026, following the user's clarification that
clicking the menu-bar battery icon again sometimes leaves the popup open.
The source version remains 4.3.1. This review does not describe a published
installer or an update to the canonical installed application.

## Reproduction and correction

Actual WindowServer input in the disposable arm64 macOS 26.6.1 VM reproduced
the failure in both Standard Glass and Clear Glass. The production status
button's screen bounds were `(722, 742, 77, 22)`, while its native window's frame
was `(722, 738, 77, 30)`. A top-edge click at `(760.496, 767.512)` belonged to
the status window, outside the shorter button bounds.

The old local outside-click monitor closed the popup first. The button then
received the same mouse-down event and toggled the now-closed popup open again;
the paired mouse-up performed only the existing release action. Standard's
event 43 and Clear's event 50 show this exact sequence. It was a local-monitor
classification error in these traces.

The monitor now leaves events from the anchor's native window, or points within
that window's full screen frame, to the status button's existing toggle. The
paired action routing and host animations retain their existing behavior.
Regression assertions cover both window identity and the frame fallback for
top/bottom points without an event window.

## Real input comparison

The comparison app copies production button/visibility startup wiring and uses
the production `StatusItemController` button, target/action, `ClickRouter`,
popup controller and views. It injects a fixed battery snapshot because the VM
has no physical battery, and replaces privileged control actions with test
callbacks. The separate full-start control is described below. Private RFB
credentials and boot logs are excluded.

| Actual input sequence | Baseline Standard / Clear | Fixed Standard / Clear |
| --- | --- | --- |
| Open, then click status-button center | Closes / closes | Closes / closes |
| Open, then click top edge | Reopens / reopens | Closes / closes |
| Click popup content, then status-button center | Closes / closes | Closes / closes |
| Third click following each fixed sequence | — | Reopens / reopens |
| Four rapid clicks from closed | — | Ends closed / ends closed |
| One 0.8-second held down/up pair | — | Opens once / opens once |

The full-frame images below show the state after the second top-edge click.
Screenshots verify visibility; event traces establish why that visibility changed.
These are interaction checks on one VM OS, not a claim to reproduce every
possible intermittent event sequence on the reporting user's machine.

| Material | Before correction | After correction |
| --- | --- | --- |
| Standard | [Open again](baseline-standard-after-second.png) | [Closed](fixed-standard-after-second.png) |
| Clear | [Open again](baseline-clear-after-second.png) | [Closed](fixed-clear-after-second.png) |

[Evidence](evidence.json) records numeric event excerpts, case outcomes, source
hashes and image hashes. Trace stages 110/111 bracket the local classifier,
200/201 bracket the actual button action, and 202 records its routing intent
(1 = primary toggle; 4 = release). Stage 10 is the QA raw-event observer.
Baseline source is commit `3a057d4`; the fixed popup source SHA-256 starts
`6cbbdbda43b3`, and the regression harness SHA-256 starts `4708d814ea1a`.

## Additional Classic observation

After clicking Classic popup content, the second status-button click closed it,
but a later third click produced raw events in the status window without
invoking the button action. This also occurred after substituting the fixture
for only the initial battery sample and running the actual production `start()`
with its menu and observers. At that point the native popover was fully closed,
its show/close counts matched, and the button was enabled with its target/action
still assigned. A same-process switch to Standard then retained that loss of
action delivery. Its cause is unproven; it is not counted as a passing Classic
reopen or live-switch check. Restoring only the old classifier in the same
full-start fixture reproduced both additional failures, with identical outcomes;
this observation predates this correction. The corrected classifier applies
only while the glass host is open. The fresh-process glass cases above are
independently valid. The comparison and source hashes are retained in the
evidence file; additional product causality remains unproven.

## Verification

- Swift tests with warnings treated as errors: 378 passed.
- Python suite: 503 total, passing with four existing opt-in GUI skips.
- Universal release compilation: arm64 and x86_64, warnings treated as errors;
  both Mach-O slices retain macOS 12.0 as their minimum deployment target.
- The existing real AppKit interaction harness in the test VM: 282 assertions
  in normal mode and 276 with the existing DEBUG Reduce Motion override,
  including the added window-edge regression assertions. Both runs used native
  glass selectors; this override verifies the app's motion policy, not a change
  to the VM's system accessibility preference.
