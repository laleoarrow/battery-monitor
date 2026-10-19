# Wattson 4.3.23 exact-candidate tools

These are local review tools. They do not dispatch workflows, publish a release,
install an App, change production code, or send mail. The artifact entrypoint is
read-only against GitHub. `tap-sync.sh` **does commit and push the cask when
explicitly invoked**, after its public-release gates pass.

Fixed source: `23185f299ce61b8e373ebf5115b461ad2aa01226`.
Fixed successful main Headless run: `39218951312`.
The dispatched candidate is `39220053878`.

After the entire candidate build + five installation jobs have succeeded:

```bash
/bin/bash design/release-v4.3.23/publication/artifact-verify.sh 39220053878
```

There is exactly one readiness query and no polling or implicit dispatch. A
pending candidate returns without downloading. The entrypoint requires a
successful same-source main/push Headless run, still-frozen main, exact workflow
identity/attempt, all six successful jobs, one unexpired source-bound candidate
artifact, its API archive digest/size, exactly four safe ZIP members, CRC checks,
all three manifest entries and exact community metadata. It runs the frozen
standalone release/DMG verifiers and supplements both slices' ad-hoc signatures,
absence of debug entitlements and App entitlements matching the frozen plist.
Canonical installed file/receipt hashes are checked before and after static
inspection. Nothing is built, installed or launched.

Successful output is retained as caller-owned inputs in:
`dist/github-candidate-v4.3.23-39220053878/`.
A pre-existing output is refused. Each attempt retains a separate
`artifact-RUN-review.XXXXXX/` evidence directory; it includes `artifact-proof.json`
and `artifact-workspace.txt`. Download authorization and signed URLs remain only
inside private owned scratch and are not printed or retained as evidence.

Only after GitHub publication has created this version's `release-created.json`
and root has confirmed the candidate/public digests, the trusted cask sync is:

```bash
/bin/bash design/release-v4.3.23/publication/tap-sync.sh VERIFIED_PKG_SHA256
```

The cask sync is fixed to candidate 39220053878. It checks the local reviewed four
files/manifest against both saved and current release API digests/sizes, the
annotated tag's source and frozen main. It then owns a disposable main-only tap
checkout, changes exactly the version and SHA lines from 4.3.22 to 4.3.23, checks
Ruby/diff/commit scope, uses an ordinary non-force push and verifies remote main
matches the resulting commit. `tap-sync-review.XXXXXX/tap-commit.txt` records the
exact tap SHA. It does not dispatch tap CI, public lifecycle or Pages.

After release publication, the anonymous public provenance check is:

```bash
/bin/bash design/release-v4.3.23/publication/artifact-public-verify.sh
```

It refuses to overwrite `dist/public-v4.3.23-verify` or
`artifact-public-provenance.json`. Anonymous REST/CDN downloads must match all
four saved/current API digests and sizes, accepted candidate bytes and strict
manifest. The public annotated tag must point to the frozen source. This reuses
the completed candidate signature/bundle inspection through exact byte equality;
it does not repeat static bundle verification. Only after all comparisons pass
are the public four files retained and `artifact-public-provenance.json` created.
That JSON exposes `sourceCommit`, `packageSHA256`,
`publicAssetsMatchCandidate=true` and `packageVerified=true` for installation.
Public transport uses urllib with default TLS verification and no token,
Authorization header, cookies or netrc. Its offline fixtures are separately
recorded in `artifact-public-tool-checks.json`.

All entrypoints disable inherited Python optimization and use the shared
cleanup owner in the actual shell. On normal exit, failure, timeout or catchable
interruption the owner stops/reaps tool processes, unregisters expanded Apps,
detaches owned mounts and removes only owned scratch/checkouts. Retained
candidate inputs and evidence are not cleanup targets. A caller must require
exit status zero and check the workspace path from the record no longer exists;
no independent whole-machine cleanup census is claimed. No signing secret is
imported and community files are not represented as notarized or Developer ID
signed.

Preparation checks are recorded in `artifact-tool-checks.json` and
`artifact-tool-preparation.json`. They are offline/static tests, not evidence
that the actual candidate or public release has already passed these tools.
