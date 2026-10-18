# Process Activity keyboard focus regression

This independent diagnostic compiles the production `Core`, `MenuBar` and
`Popover` sources from an immutable Git archive. It shows a real AppKit window
in a newly owned disposable ARM GUI VM. The host desktop and canonical Wattson
installation are never manipulated. The handler records only mocked identities;
no real process is terminated and the helper is not contacted.

`main.swift` selects mock process A, explicitly makes its row the real window
first responder, and supplies B/A/C on the next update. It checks selection and
first responder separately, then sends Space to the actual first responder.
The native action-button path uses the real `NSButton`, if AppKit accepts it as
first responder; refusal is reported as an unexercised qualified path, never a
passing test. The fixture also checks process removal, Top N truncation,
loading/unavailable/empty readings, Compact view, and focus owned by an unrelated
text field's field editor.

## Immutable baseline

`baseline/frozen-source-commit.txt` records `9ab0c43…`. The focused diagnostic
completed and deliberately recorded `allPassed: false`; a zero runner exit
means diagnostic execution plus cleanup completed, not that the regression
passed. The complete assertions are in `baseline/results/focus-results.json`.

Selection follows A, but keyboard focus remains in the old row and Space
selects B. AppKit also accepted the native action button as first responder;
its focus did not follow A after reranking. Removing A or dropping it below
Top N leaves focus on a rebound row. Compact view has the same rerank defect.
The baseline's status-clearing and unrelated text-editor cases passed.

## Lifecycle and source verification

`run-owned.sh COMMIT NEW_ABSOLUTE_EVIDENCE_DIRECTORY` owns its unique VM,
read-only source archive and project-local scratch. `guest-run.sh` owns the
sandboxed test app, unique preferences/container and source/build workspace.
The shared cleanup library bounds commands, stops owned child processes,
unregisters the exact app and removes only owned resources. A post-execution
35-second preference observation and resource audit precede VM deletion. The
VM inventory proof verifies the two pre-existing VMs remain stopped.

Set `WATTSON_FOCUS_QA_MODE=full` for the patched source: the independent focus
assertions must all pass, followed by all three complete interaction variants
and the 20,000-iteration animation stress test. Final success requires the
focused report, all actual native completion markers and cleanup proofs.

## v2 boundary probe

`main-v2.swift` adds four cases without altering the completed baseline: shrinking
Top N while the focused action's identity remains visible (fall back to that
identity's row), reranking after Escape clears selection but retains row focus,
reusing a PID with a new start time, and loss of the termination identity. The
last two must retire focus safely rather than assign it to the replacement.
`run-owned-v2.sh` freezes that named main and `guest-run-v2.sh` before executing;
its input manifest includes the independent probe source hash.

`baseline/probe-inputs/` preserves the original main and lifecycle scripts used
for the baseline. `preservation.json` confirms the lifecycle script bytes match
the hashes recorded during the baseline run. The main was copied unchanged
before v2 was created; its separately recorded hash is a preservation hash, not
an execution-time attestation. The baseline only exercised v1 cases.

## Patched immutable verification

`patched-df7d4bc/owned-source-verification.json` verifies frozen
`df7d4bcbeb0200e6ee5001182d92f62229aba88f`: the independent v2 probe passed all
34 checks with no qualified focus paths. The complete real interaction variants
passed 456 / 454 / 448 checks (1,358 total), each with its actual completion
marker. The 20,000-iteration animation stress test completed. The source archive's
157 files matched before and after execution; all persistent harness input
hashes remained unchanged. The guest cleanup audit and 35-second preference
observation passed, the owned VM and host snapshot were deleted, and the two
pre-existing VMs stayed stopped.

The tested VM ran macOS 26.6.1 (25G76), ARM, with Swift 6.3.3. This is not a
macOS 27 runtime claim. One pre-existing accessibility-variant limitation is
retained: that system completed closing synchronously, so there was no
mid-close reopening window to exercise. It does not affect the independently
executed focus paths. No actual process was force-terminated in this fixture.
