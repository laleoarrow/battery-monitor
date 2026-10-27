# Full History presentation-wait verification

This owner runs the complete production interaction harness, including the
preceding non-History sections, through the unchanged
`scripts/verify_interaction.sh` lifecycle. It uses one disposable ARM GUI VM and
three independently owned app invocations: normal; legacy controls; legacy
controls with Reduce Motion and Reduce Transparency forced on. The History
section retains its existing local motion override to exercise its animations.

The source change is confined to `settleHistoryFixture`: each original
one-second poll reads the hosted layer presentation tree (including masks),
position and shape path, flushes pending transactions, then applies the original
no-live-animation-key predicate. The global runner, deadline, production
renderers and existing duration/intermediate-frame/cancellation checks stay
unchanged.

After a genuine contraction settles, three identical-geometry animations are
injected under its actual `history.stroke` key: infinite repeat, two-second
duration and retained completion. Every one must remain rejected at the
original one-second deadline. Only each injected test key is removed afterward.
Normal animations are never removed to obtain a passing result.

`run-vm.sh NEW_OUTPUT_DIRECTORY` freezes the current working source and uses
the existing shared VM lifecycle and resource audit. Each app invocation uses
the original owner for its unique preferences, registration, container and
processes. Logs, exact source hashes and results are retained even on failure;
the clone, host scratch and guest scratch are cleaned. No host desktop UI is
used. This directory was prepared for review before starting the run.

The preceding extracted comparison observed completed presentation geometry
and key retirement under the revised wait, but did not satisfy its full
application-active visibility preparation. These observations do not establish
frame delivery or the final Core Animation root cause. A full local pass also
does not replace the hosted release gate.
