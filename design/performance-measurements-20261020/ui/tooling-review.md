# Independent measurement-tooling review

Read-only review on 2026-10-20 of `scripts/measure_ui_latency.sh`,
`scripts/measure_ui_vm.sh`, `tests/performance/ui-vm-guest.sh`,
`tests/performance/ui_vm.py` and the UI harness's measurement labels. This review
did not compile code or start, stop or modify a VM.

One confirmed failure-boundary issue was reproduced without Tart: with an owned
synthetic inventory declaring `macOS-TestLab` running, `ui_vm.py preflight`
correctly exited 1 under ordinary Python but incorrectly exited 0 under
`python -O`. Critical preflight, inventory-preservation and guest archive-hash
checks used `assert`, which an inherited `PYTHONOPTIMIZE` can disable. The runner
owns the explicit-check fix and its ordinary/optimized rejection tests.
The runner subsequently reported all four tests in
`tests/test_ui_vm_validation.py` passing: ordinary Python, `-O`, and inherited
`PYTHONOPTIMIZE=1` reject incorrect inventories and hashes; an uninstrumented
result cannot pass the diagnostic gate; a dangling output symlink is rejected
before VM access. This finding does not establish
that an existing measurement was performed with optimization enabled.

The reviewed design freezes product source through `git archive`, records tool
and archive hashes, compiles guest-local copies, and keeps baseline/candidate
ABBA runs on one disposable clone. The host preserves partial measurement logs
on failures and cleans only its unique clone; guest scratch, app registration,
containers, preferences and child groups use the shared lifecycle. Existing
baseline cleanup evidence passed. Apart from the confirmed assertion issue, no
additional cleanup blocker was identified by this static review. The runner
was also told to reject dangling symlinks as existing output paths.

Interpret results within their labels: controller-cold includes fixture priming
in an existing process; external helper refreshes are skipped for UI timing;
window/layer and effective-appearance observations are software milestones,
not physical first-frame delivery. `total_including_construction_ms` includes
entrance-animation completion. A diagnostic patch is an attribution experiment,
not an unchanged-production baseline or a shipped optimization.
