# Whitelist verification

Production source was frozen before the final runs. The retained source hashes
also match the VM's compiled renderer inputs.

- `swift test`: 728 tests, zero failures (`swift-tests.log`).
- `bash scripts/build_release.sh`: arm64 and x86_64 App/helper builds,
  universal architecture checks and ad-hoc signature verification passed
  (`universal-build.log`). Disposable app bundles were removed automatically.
- Python full suite: 631 tests, four expected opt-in skips; one existing support
  archive lifecycle timing test failed because its blocked stage was not reached
  before a deadline (`python-tests.log`). Its isolated rerun passed all six
  injected archive/output stages in 9.743 seconds (`python-support-rerun.log`).
  No unrelated production or test deadline was changed.
- Related Settings store/window and status-item Python checks: 56 passed
  (`python-targeted.log`). The earlier development full run had a compiler
  source-modification race; the final frozen-source Settings check passed.
- Focused final Swift checks: 65 passed, including the hidden Settings-window
  focus/scroll regression (`swift-targeted.log`).
- Shell syntax checks and `git diff --check`: passed.

The final ARM GUI VM separately passed 6,926 renderer assertions and 463 native
interaction checks. Its cleanup audit and unchanged TestLab/Base inventory are
retained in the parent folder. Screenshots use fixture readings and are internal
validation evidence. This is unreleased development source using the unchanged
5.0.0 version marker; the public release and installed canonical app were not
updated, and no new release tag was created.
