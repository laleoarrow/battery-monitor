# Harness diagnosis retained for review

The `pre-default-button` log and image came from an early harness assumption that
Return should cancel the alert. That requirement was incorrect: Wattson now
intentionally uses a native alert with no default action. Cancel and Escape
close it; Return leaves it open and sends no signal. The final four-action
production-presenter probe verifies that behavior, with a spy for explicit Force
Quit. A temporary explicit Return default broke Escape and was removed before
the accepted production run.

The accepted harness also waits for a visible, WindowServer-capturable modal
and asserts that every production-controller confirmation was observed, its
safe dismissal was delivered, and Return stayed open until explicit Cancel.
There are 12 distinct production-controller confirmation captures in the final
72-image matrix.

An early failure-capture EXIT trap omitted `set +e`, which prevented shared
cleanup after a failed test. The final trap preserves the failure code and still
runs cleanup. `cleanup-trap-validation.json` exercises an intentional exit 23;
the accepted guest and VM audits independently verify cleanup. Failed VM clones
were deleted. Redundant failed-run screenshots and temporary source archives
were removed after retaining these diagnostics.
