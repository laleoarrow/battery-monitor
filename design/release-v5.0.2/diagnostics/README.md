# Contracted-axis release diagnostic

This is a read-only diagnostic of the frozen 5.0.2 app sources and an extracted
copy of the original History interaction fixture. It does not modify the app,
the original test, release workflows or release correspondence.

`extract-contracted-axis.py` retains the History section from its original setup
through the contracted-axis assertion: ordinary update, cancellation/restoration
cycles, interrupted expansion, 60 immediate low-power updates, the existing
0.3-second wait, and four immediate timestamped sample updates. No fixture clock
pause is reached. The preceding non-History portions of the full interaction
suite are not replayed; this limits reproduction fidelity.

The original `runApplication` poll condition and one-second deadline stay intact.
Only the contracted-axis wait receives a read-only terminal-poll callback. It
records presentation/model path points, topology and maximum point error, head
position error, remaining keys/timing, window visibility/occlusion, the view's
visible rect and current lock state **before** the original application loop
stops. After it returns, the probe records the state before and after one
explicit diagnostic `CATransaction.flush()`. Neither observation changes the
original pass flag. No diagnostic call forcibly removes an animation key.

The presentation recorder follows the existing continuous-loop diagnostic in
`design/performance-smoothness/native/continuous-loop-probe.swift`. Its original
path/head observations are reused here on the contracted-axis sequence, rather
than on a fresh matched-tail pair. The original one-second wait remains one
continuous `NSApp.run`; earlier fixture lifecycle waits retain their original
loop boundaries. This does not establish that loop boundaries cause a failure.

`run-vm.sh NEW_OUTPUT_DIRECTORY` is a narrow adaptation of the existing
`scripts/verify_process_whitelist_vm.sh` owner. It freezes the current source,
clones the stopped ARM GUI base, runs only `guest-probe.sh`, audits guest resources
and deletes its clone. Host GUI interaction is not used. Both owners use the
shared lifecycle helpers, exact registered preference domains and `.noindex`
scratch. Original failures remain failures, with evidence copied out on exit.

Geometry equality is a Core Animation observation, not proof of physical frame
delivery, FPS, hardware behavior or a passing release gate. A successful local
probe cannot supersede the original hosted-CI failure.

## Single-run observation, 2026-10-27

The [summary](summary.json) and [raw labeled records](local-probe-1/contracted-axis.json)
preserve a reproduced contracted-axis key-retirement failure. At the terminal
poll of the original one-second deadline (1.022921 seconds), `history.fill`,
`history.stroke` and `history.head` remained. All three observed paths had
matching topology and zero model/presentation point error; head error was also
zero. The window was visible, not occluded, on the active space and unlocked,
with a 328 × 112 visible rect. The application itself was not active.

Immediately after the original `NSApp.run` returned (1.025042 seconds), the
three keys remained. After one diagnostic flush (1.026445 seconds), they were
absent and geometry was unchanged. No key was forcibly removed and the original
failed assertion and exit code 1 were retained. This establishes a local
instance of completed property geometry coexisting with late key retirement;
it does not close the root cause or replace the original CI gate.

The raw records are sequential reads, not atomic display frames. Their terminal
callback runs after the original poll has decided its result. The old
`HISTORY_COMPLETION_TIMEOUT`/owner-clock text is emitted after the added flush;
use the three explicitly labeled records for before/after attribution. The
timing association does not establish that the loop boundary or flush caused
the delayed retirement. Earlier non-History suite state was not replayed.

The [guest audit](local-probe-1/guest-cleanup-audit.json) passes after 37.631 seconds
of preference-file observation: no owned preferences, containers, processes,
registrations or scratch remain. The [VM audit](local-probe-1/vm-cleanup-summary.json)
confirms the owned clone was deleted and both original VM states were preserved;
the host's owned scratch is empty. No second diagnostic run was performed.
