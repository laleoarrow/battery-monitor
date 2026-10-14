# Optional battery runtime module

Development review, 13 October 2026, following the request to make estimated
battery runtime a selectable item alongside Energy Flow, Ring Gauge, Power
Lanes and Power History. The source version remains 4.3.1; this does not describe
a published installer or an update to the installed application.

The 14 October [independent runtime section](../runtime-section/README.md)
supersedes the 24-point visual layout below. This page retains the earlier
module-selection and real-window interaction evidence.

`Est. Battery Runtime` is the fifth item in the existing module menu and in
Settings → Modules. Both use the same saved `popover.module.runtime` preference.
Missing or invalid preferences default to enabled, preserving the existing
display and all four older saved module choices.

The row is a separate 24-point production view below the 48-point header.
Together they retain the original 72-point layout and text position. Disabling
runtime removes only that row; reopening preserves the choice, and enabling it
renders the newest cached state. The macOS estimate source, sampling and text
formatting remain unchanged. Hidden runtime skips view updates.

Settings uses five 72-point rows within the existing 720×520 window. This keeps
the fifth option and its description visible in Classic without adding a
scrolling layer or enlarging the window.

The Swift suite passed 380 tests with warnings treated as errors. The Python
suite passed with 503 total tests and four existing opt-in GUI skips, including
the settings persistence and native layout contracts. Universal release
compilation passed for arm64 and x86_64; both retain macOS 12.0 as their minimum
deployment target.

The final VM AppKit harness passed 300 assertions in normal mode and 294 with
the DEBUG Reduce Motion override. One animation-interruption stage was skipped
because the OS closed synchronously. In both modes, production Classic,
Standard and Clear hosts shrank exactly 24 points when runtime was hidden;
Energy Flow moved up 24 points, reopening preserved the hidden choice, and
enabling runtime restored the original geometry. The runtime renderer also
passed charging, full, battery, mixed-supply, low-battery, Low Power and failed
reading layout checks.

Independent WindowServer input passed six cases and 105 assertions: actual
fifth-item menu actions and Settings checkbox actions in all three styles.
All five settings rows remained visible. Input uses the existing footer button;
native keyboard navigation scrolls a clipped fifth menu item into view before
the actual pointer click. Early QA setup attempts remain recorded separately.

| Verified state | Capture |
| --- | --- |
| Default runtime displayed | [Enabled](default-runtime.png) |
| Cancelled choice remains hidden after reopening | [Hidden](runtime-hidden.png) |
| Fifth option in Settings, corrected artwork | [AppKit render](logo-verification/settings-classic-light-color.png) |

The original Settings VM screenshot contained a system placeholder because its
QA bundle omitted the logo resources. The 14 October [logo verification](logo-verification/README.md)
reproduced that omission, checked the corrected bundle against the real PNGs,
and provides four verified Classic AppKit renders. The original screenshot is
retained as before evidence. The replacement is an offscreen production-view
render; it is not a new WindowServer glass capture.

The VM has no physical battery, so the fixture supplies the sample shown in
these captures and disables privileged changes. To measure window height below
the short screen's viewport cap, tests disable History while toggling Runtime;
the default and older saved History preference are preserved in production.
[Evidence](evidence.json) retains source and image hashes, action counts,
geometry measurements, case outcomes and the bounded QA setup attempts.

The test VM was cleaned and stopped; its temporary apps, preferences and QA
registrations were removed. The Base VM remained untouched. Installed Wattson,
its helper, package receipt and process remained at the verified 4.3.1 baseline.
