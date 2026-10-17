# Integrated source review

Integrated freeze: **91f9072d839badc8da4273d56d8215ef776d7d9a**. Modules source
**402991a57fcb** adds the five approved vector icons and the drag/focus corrections.
The HistoryChart and HistoryLayer hashes remain exactly those of performance
candidate 9325876. Full integrated host suites pass 535 Swift and 601 Python tests
(four skipped); native gesture acceptance is owned by the Modules chat.

The narrow independent source review found no correctness or lifecycle blocker.
The handle retains the original mouse-down event until the four-point drag
threshold, consumes it once, and dims the row only after the native session
begins. Existing end/cancel, window-close, hiding and focus-loss paths restore
state. Mouse focus no longer draws the keyboard focus indicator; keyboard
navigation retains it. No timer, polling or telemetry/helper work was added.

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
