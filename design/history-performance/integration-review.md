# Integrated source review

Integrated freeze: **9fef74944447d4753d1edde82997dc41a479ccad**, integrating
Modules source **e627969**. The HistoryChart and HistoryLayer hashes remain
exactly those of performance candidate 9325876. Full host suites pass 535 Swift
and 601 Python tests (four skipped). The [queued-drag review](queued-drag-review.md)
and [raw review record](queued-drag-review.json) retain the narrower follow-up.

Real rapid mouse testing of superseded source 91f9072 found that an already
queued drag event could start a native session after physical mouse release,
leaving the row dimmed. The correction checks `NSEvent.pressedMouseButtons & 1`
before snapshot preparation and again before session-state registration. An
early return writes no drag state, alpha, settings or notification. Tests cover
released, right-button-only, released-during-preparation and continuously-held
states; new test hooks are DEBUG-only. The Modules chat's
actual already-released gesture observations confirm safe early rejection;
normal held native drop remains unverified because of the automation's short
input batch. Those observations are separate from this source review.

The handle retains the original mouse-down event until its four-point threshold,
consumes it once, and dims the row only after the native session begins. Existing
end/cancel, window-close, hiding and focus-loss paths restore state. Mouse focus
no longer draws the keyboard focus indicator; keyboard navigation retains it.
No timer, polling or telemetry/helper work was added. The fourth icon's fill
extends only from x21 to x22 at the axis edge; its curve, node and other four
icons are unchanged. The generator, Swift artwork and ZIP exports match.

Artwork drawing closures capture values without retaining a view or listener.
The existing arranged views are retained, preserving History's view, data and
animation ownership. Programmatic order tests and real-pointer acceptance remain
separate evidence.

One bounded inefficiency remains: appearance refresh can recreate identical
NSImages because the existing window/section traversals overlap, and transparency
notifications also reach the five icons. No display-performance regression was
measured. The owning chat kept the candidate frozen rather than adding a render
key cache in this change. This review does not claim every possible allocation
has been eliminated; the measured History hot-path reduction is documented
separately.
