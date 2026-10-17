# Final PKG verification

Current source **9fef74944447d4753d1edde82997dc41a479ccad**, candidate SHA-256
**72c2e20dcf13e6d69c27e9aee83528241ab58c881b1e1609a28f87b479caf21a**.
The [current summary](final-queued-9fef-verified.json) records actual host,
staging and guest exit zero. The [transfer record](queued-drag-transfer.json)
records a byte-identical content-addressed copy with a separate inode. This
root-owned copy was removed after validation; the canonical package is preserved.

All five modes passed: previous 4.3.10 fresh install, disabled-service upgrade,
4.3.11 fresh install, reinstall, and disabled-service reinstall. Each checks
App/helper/daemon bytes against the exact payload, both App version fields,
receipt, code signatures, helper health/v5 and loaded/enabled launchd state.
The VM has no internal battery, so physical-host App residency is separate.

The [current result archive](package-results-final-queued-9fef-9fef74944447-a4c0377fe0a03c6eef330faeb23f529f6948bc6076f85a3d09f1919b24a5848b.tar.gz)
retains 89 files, each hash verified. Immediate and delayed cleanup audits passed;
the latter waited 5.115211 seconds in its own process and records system
`CLOCK_MONOTONIC` plus UTC. Newly created empty guest project parents were removed
only with `rmdir`; [ownership cleanup](final-queued-9fef-ownership-cleanup.json).
[Current collection manifest](queued-drag-collection-manifest.json) pins the
copied evidence and unchanged sealed tools.

Earlier source **91f9072**, package **d6624c33…49af590**, passed its own five-mode
matrix but later failed a real rapid-gesture UI gate. Its [summary](final-91f-r2-verified.json),
[archive](package-results-final-91f-r2-91f9072d839b-3b5b60b7d65e6bf40b4bf8e43df114ff8cc401de89256321ae2747c28ee84da9.tar.gz)
and [transfer record](final-package-transfer.json) remain superseded evidence.
It was not installed on the maintainer Mac.

The first final attempt rejected stale preliminary bytes served at the reused
VirtioFS filename before any installation. Its [failure annotation](final-91f-first-staging-failed.json)
corrects the raw stage's unconditional verification flag; it is not a successful
matrix. The new content-addressed basename passed actual guest file hashes and
all installed-input records, independently of that flag. No hash check was waived.

The separate preliminary run under `preliminary/` first exposed the newer
`launchctl print-disabled` spelling `disabled` rather than `true`. The reviewed
final parser requires exactly one whole matching helper-label line and accepts
only `true|disabled` or `false|enabled` for the requested state. Missing, duplicate,
unknown and trailing-content values fail closed. The [fixture log](preliminary-c8e-cleanup-failure-injection-v3.log)
covers 30 parser cases and 18 lifecycle cases. Old tools and failed archives are
preserved; the final tool archive is `31596c3f…fd56f`.

[Earlier collection manifest](collection-manifest.json) preserves the prior
compact records and immutable tools. Reproduction requires an owned disposable VM and
the exact packages: unpack the sealed tools, verify all hashes, then use its
owned stage/dispatch entrypoints. Do not run this matrix against a maintainer's
canonical installation or existing user data. This ARM VM check does not replace
the public Intel/macOS distribution matrix.
