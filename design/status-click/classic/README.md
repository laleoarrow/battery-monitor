# Classic third-click correction

Development review, 13 October 2026. This resolves the Classic observation in
the [earlier status-click review](../README.md). The application version remains
4.3.1; this review does not represent a published installer or an update to the
canonical installed application.

## Reproduction and correction

In the disposable arm64 macOS 26.6.1 VM, opening Classic, clicking its content,
then clicking the battery icon twice reproduced the failure. The second icon
click closed the popup, but the third did not reopen it. Native traces showed
the status window receiving both events and hit-testing the enabled button,
while the button's mouse-down and target/action were not called. Its target,
action and event mask remained assigned. Restoring the action mask, sending
actions only on mouse-up, and resetting the public button state each failed to
restore delivery.

Classic now uses [`NSPopover.Behavior.semitransient`](https://developer.apple.com/documentation/appkit/nspopover/behavior-swift.enum/semitransient).
The same input sequence
reaches the existing button action, which closes and reopens the popup. A
separate rapid-click experiment found that AppKit could queue a show during an
unfinished close, then execute it after the user's next close. Before reopening
during that interval, the controller retires the closing native popover and
attaches the existing content to a fresh instance. Old delegate callbacks are
already excluded by native-instance identity.

Classic also uses the existing workspace activation, Space and session
observers so switching applications closes it. A controlled semi-transient
variant without those observers stayed open after a verified Command-Tab.
The existing local mouse monitor now also closes Classic for clicks in other
normal Wattson windows. It protects the native status anchor and Classic
content, leaves native menu windows to AppKit, and passes Classic key events
through unchanged.

## Verification

The tracked AppKit harness posts mouse-down/up events to the actual status
window and runs AppKit dispatch through the button target/action and existing
`ClickRouter`. It focuses Classic content before checking the second close and
third reopen, then checks four rapid clicks end fully closed. It restores the
button target, action and mask after the test. These are queued native events;
the independent RFB runs supply real WindowServer mouse and keyboard input.

The RFB fixture runs production startup, status-button target/action, menus and
popup views with a fixed battery sample because the VM has no physical battery.
It uses a separate QA bundle identifier and disables privileged changes. Trace
hooks are confined to the QA source copy. No reset occurs within the continuous
three-cycle or rapid-click sequences. Private RFB credentials and boot logs
are excluded from the retained evidence.

The final WindowServer run passed all 16 cases and 74 assertions, including
three continuous content/close/reopen cycles, an early reopen followed by a
late close, four rapid clicks, a held click, other-window and desktop dismissal,
Escape, verified Command-Tab, native menu Escape/drag cancellation, right-click,
Control-click, and Classic → Standard → Clear → Classic in the same process.
The desktop case runs last to avoid macOS Show Desktop hiding windows used by
later fixture input. No case assertions were removed.

| State after the third icon click | Native screenshot |
| --- | --- |
| Original transient behavior: stays closed | [Before](before-third-click.png) |
| Final correction: opens again | [After](after-third-click.png) |

The final tracked harness passed 289 assertions in normal mode and 283 with
the DEBUG Reduce Motion override. One reduced-motion stage was skipped because
AppKit completed the close synchronously; the actual rapid-click closure and
other-window checks passed. The first motion run timed out on an existing A2
settings-button blank-area click, while its other sample and all new Classic
checks passed. One bounded repeat of the same source and binary passed. Both
attempts remain in the evidence; this is not a claim that every run passed.

Before the additional same-process-window correction, the harness passed 287
assertions in normal mode and 281 with the DEBUG Reduce Motion override.
Reduce Motion skipped one
in-flight-close stage because AppKit completed the close synchronously; its
actual rapid-click closed-state test still passed. Restoring only the two old
`.transient` assignments, with all other source and harness bytes of that run held
constant, produced five failures: two behavior expectations and three actual
interaction checks (second button close, third reopen, rapid-click closure).

The Swift suite passed 378 tests. The Python suite passed with 503 total tests
and four existing opt-in GUI skips. Universal release compilation passed with
warnings treated as errors for arm64 and x86_64; both retain macOS 12.0 as the
minimum deployment target.

The [evidence file](evidence.json) records source hashes, numeric event excerpts,
native input outcomes and screenshot hashes. These checks establish the
reproduction and correction on the tested VM OS; they do not claim coverage of
every macOS release or every intermittent sequence on the reporting machine.
