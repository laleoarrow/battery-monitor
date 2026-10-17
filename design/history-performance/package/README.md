# Final PKG verification

Source **91f9072d839badc8da4273d56d8215ef776d7d9a**, final candidate SHA-256
**d6624c334c8501b39d8c9b1bcea766c2cc5d661948574068b33be195149af590**.
The [verified summary](final-91f-r2-verified.json) records actual host, staging
and guest exit zero. The content-addressed transfer copy is byte-identical to
the canonical package filename; [transfer record](final-package-transfer.json).

All five modes passed: previous 4.3.10 fresh install, disabled-service upgrade,
4.3.11 fresh install, reinstall, and disabled-service reinstall. Each checks
App/helper/daemon bytes against the exact payload, both App version fields,
receipt, code signatures, helper health/v5 and loaded/enabled launchd state.
The VM has no internal battery, so physical-host App residency is separate.

The [result archive](package-results-final-91f-r2-91f9072d839b-3b5b60b7d65e6bf40b4bf8e43df114ff8cc401de89256321ae2747c28ee84da9.tar.gz)
retains 89 files, each hash verified. Immediate and delayed cleanup audits passed;
the latter waited 5.047064 seconds in its own process and records system
`CLOCK_MONOTONIC` plus UTC. Newly created empty guest project parents were removed
only with `rmdir`; [ownership cleanup](final-91f-r2-ownership-cleanup.json).

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

[Collection manifest](collection-manifest.json) verifies the compact copied
files and immutable tools. Reproduction requires an owned disposable VM and
the exact packages: unpack the sealed tools, verify all hashes, then use its
owned stage/dispatch entrypoints. Do not run this matrix against a maintainer's
canonical installation or existing user data. This ARM VM check does not replace
the public Intel/macOS distribution matrix.
