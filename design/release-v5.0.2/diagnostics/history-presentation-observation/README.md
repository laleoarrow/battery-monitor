# History presentation-observation diagnostic

This isolated diagnostic tests one difference suggested by the retained failed
probes: the candidate's settling predicate reads every History layer's
`presentation()`, presentation position and shape path, flushes the transaction,
then evaluates the original `!hasChartAnimationForTest`. The original global
`runApplication`, one-second timeout, History inputs and assertions stay intact.

Baseline and candidate share a visibility precondition before the first History
input: activate the test app, order the fixture window forward, and require an
active app plus a visible, unoccluded window on the active Space. This preparation
never occurs after a tested animation starts. `paired-run-1` exited before any
History input because readiness could not be established. Its evidence is
retained. A subsequent run logs unmet readiness and continues only as a
visibility-uncontrolled diagnostic; it cannot claim a visible A/B comparison.

One owned ARM GUI VM runs baseline, candidate and three real `history.stroke`
negative controls: infinite repetition, duration of two seconds, and disabled
automatic removal. Every injected animation has equal source/target paths.
Post-verdict geometry observations cannot change acceptance. Failure stops this
line of wait-mechanism experiments; it is not permission to remove animation
keys or extend deadlines.

```bash
bash design/release-v5.0.2/diagnostics/history-presentation-observation/run-vm.sh \
  "$PWD/design/release-v5.0.2/diagnostics/history-presentation-observation/paired-run-1"
```

Require a new output directory. Preserve native inputs/logs and both guest and
host cleanup audits. This extracted History prefix does not replace the full
interaction matrix or hosted release candidate.

`paired-run-2`: baseline contracted-axis timed out at 1.024988 s; candidate passed
all extracted assertions, with contracted-axis settling at 0.282611 s. Infinite,
long and non-removing real-key controls all timed out. Initial readiness remained
false, although every terminal observation reported an unoccluded window. This
supports full-suite verification of the exact predicate, not a proven root cause.
Guest audit and VM removal confirmed final resources absent; the inner owner's
defaults-delete warning is retained in `summary.json` and its raw log.
