# Disposable UI measurement protocol

The measurement wrapper leaves the user's installed Wattson and preferences
untouched. It creates one uniquely named clone of the stopped `macOS-TestLab-Base`,
starts it without graphics/audio/clipboard sharing, mounts this repository
read-only, and exposes a separate invocation-owned task share.

```sh
WATTSON_UI_VM_SMOKE_ONLY=1 bash scripts/measure_ui_vm.sh NEW_SMOKE_DIR BASELINE_REF
bash scripts/measure_ui_vm.sh NEW_BASELINE_DIR BASELINE_REF
bash scripts/measure_ui_vm.sh NEW_COMPARISON_DIR BASELINE_REF CANDIDATE_REF
WATTSON_PERF_SUBMISSION=natural WATTSON_PERF_COLD_COUNT=0 \
    WATTSON_PERF_WARM_COUNT=20 WATTSON_PERF_THEME_COUNT=6 \
    WATTSON_PERF_REPEAT_BASELINE=2 \
    bash scripts/measure_ui_vm.sh NEW_AA_DIR BASELINE_REF
WATTSON_PERF_SUBMISSION=natural bash scripts/measure_ui_vm.sh \
    NEW_DIAGNOSTIC_DIR BASELINE_REF --diagnostic-patch DIAGNOSTIC.patch
WATTSON_UI_VM_SINGLE_DIAGNOSTIC=1 WATTSON_PERF_SUBMISSION=natural \
    WATTSON_PERF_COLOR_SCHEME=dark bash scripts/measure_ui_vm.sh \
    NEW_PAIRED_DIAGNOSTIC_DIR BASELINE_REF --diagnostic-patch ui-move-attribution.patch
WATTSON_UI_VM_APPEARANCE_CONTROLS=1 WATTSON_PERF_SUBMISSION=natural \
    WATTSON_PERF_COLD_COUNT=0 WATTSON_PERF_WARM_COUNT=8 \
    WATTSON_PERF_THEME_COUNT=0 bash scripts/measure_ui_vm.sh \
    NEW_CONTROL_DIR BASELINE_REF CANDIDATE_REF
```

Production sources are archived from fixed Git commits. The current latency
harness and its lifecycle helpers are archived separately so the same measurement
code can test both revisions. Each manifest records commit IDs and SHA-256 hashes.
The guest verifies archive hashes and copies sources/tools to its own local
`.noindex` workspace before compiling or timing. Compilation is outside the
reported latency intervals.

Ordinary invocations first run an independent 1/1/1 smoke result. Default baseline
blocks use 30 cold-controller opens, 60 warm opens, and 60 theme switches per
surface, plus the harness's three warmup samples per case. Explicit count,
submission, and baseline-repeat environment settings are frozen in the manifest;
zero disables that case family. Diagnostic invocations use only 0/1/0 smoke and
0/20/0 traced opens. The patch has a separate SHA, is applied using a named input
file, and must add diagnostic metadata and actual warm-only trace rows for all
three hosts before smoke can pass. Runtime source markers are also checked.
The paired assembly diagnostic selects a single compilation and application
process. Its patched driver compares `original` and `foreground_first` assembly
orders (or the explicitly labeled `early_window_first` combined experiment) and
must emit exactly 20 measured traces for each of the two variants in
all three hosts. It retains normal warmups, reports callbacks and inclusive
substage times, and is a diagnostic rather than pristine A/B performance proof.
Python validation uses explicit exceptions, including under `-O` or
`PYTHONOPTIMIZE`, and records its actual optimization flag. A comparison runs
baseline/candidate/candidate/baseline on the same clone and display. Raw JSONL,
environment, controller milestones, and summary quantiles remain caller-owned
evidence. The smoke samples are separate from those blocks.

The final appearance controls are a narrow follow-up to a successful dark ABBA:
one baseline/candidate pair under System, then one pair under Light, each with
0/8/0 natural opens and the normal warmups. They reuse the established harness
without another smoke compilation. The same clone then runs the candidate's
existing `verify_interaction.sh` once. Its two additional source files are archived
from the same candidate revision; its unique preference and app ID prefixes are
included in the guest audit. The short controls check for regressions rather
than estimating a precise cross-theme speedup.

These are AppKit/controller and window/layer software milestones under a real
`NSApplication.run()` loop. They measure synchronous UI work and include the
existing entrance animation as a separate milestone. They do not measure
physical display delivery or FPS, and fixture-based popup opening excludes live
helper/sampling refreshes, which are measured separately on the host.

The latency script owns its unique app ID, defaults suite, children, registrations,
and any newly created containers. After a settled guest execution, a filesystem-only
35-second observation checks for delayed preference recreation; process,
LaunchServices, container, canonical-install absence, and source-scratch checks
are recorded separately. The host always stops and deletes only its unique clone,
then compares all pre-existing VM states. Operator cancellation disposes the entire owned clone; it does not claim a
completed guest delayed-write audit. Final result files survive; transport
archives and invocation scratch are removed on exit, failure, timeout, and
catchable HUP/INT/TERM. A killed VM or power loss cannot run a shell exit handler;
identifiable remaining clone/scratch names must then be inspected rather than
silently reused.
