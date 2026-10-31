# Wattson 5.0.3 publication tools

These version-specific tools retain the audited 5.0.2 candidate, public-byte,
signature, manifest and cleanup checks. They target 5.0.3; tap synchronization
accepts only the previous public cask version 5.0.2. No successful publication
is implied by preparing or testing these tools.

Commit this entire directory, the 5.0.3 release notes and versioned gallery
before freezing the release commit. Every source SHA and workflow run ID below
must identify that new frozen commit; there are no historical run defaults.
Keep remote `main` at that commit through candidate, Homebrew and Pages gates.
Do not publish the separately built local-preview package as candidate bytes.

## Preparation

```bash
env -u PYTHONOPTIMIZE PYTHONDONTWRITEBYTECODE=1 /usr/bin/python3 \
  design/release-v5.0.3/publication/test-artifact-tools.py
```

The offline fixtures test source/run binding, pending and failed candidates,
expired artifacts, archive safety, byte checksums, community signing metadata,
canonical-file preservation, public tag/release identity and tap version guards.
They do not access GitHub, credentials, the canonical app or helper. Their
unique project-local `.noindex` fixture directory and child processes are owned
by `tests/local_runtime.py`, including interruption and timeout cleanup. Success
is reported after the runtime owner exits and the fixture directory is absent.
The retained `offline-tool-tests.json` records 38 passing offline checks,
including the 5.0.3 installed-version binding and previous-cask 5.0.2 guard.

After freezing the gallery into the release commit, its source-only check is:

```bash
bash design/release-v5.0.3/publication/verify-public-artwork.sh \
  --source-sha "$source_sha" --source-only
```

## Hosted candidate and exact bytes

Push frozen `main` and wait for `ci.yml`'s successful **main push** run on that
exact SHA. A manually dispatched Headless run does not replace this gate.
Dispatch `macos-helper-install.yml` on `main` with `version=5.0.3` and
`distribution_mode=community-ad-hoc`. Require the build and all five install
jobs to succeed. The optional `ci.yml` dispatch with `macos27=true` provides the
same additional software compatibility evidence used for 5.0.1.

```bash
bash design/release-v5.0.3/publication/artifact-verify.sh \
  "$candidate_run_id" "$source_sha" "$headless_push_run_id"
```

This performs one readiness check, downloads GitHub's digest-bound archive,
requires exactly the four release files, checks the strict three-entry checksum
manifest, runs the frozen standalone PKG/DMG verifier, inspects both architecture
signatures and frozen entitlements, and confirms the canonical installation was
unchanged. It retains accepted files in
`dist/github-candidate-v5.0.3-RUN_ID/`. Require exit zero and absence of the
recorded temporary workspace after the shell returns. Candidate rerun attempts
are rejected: use a fresh manual run if a previous candidate failed.

## Publication and anonymous verification

After reviewing that exact artifact set, create an annotated `v5.0.3` tag at
the frozen SHA and publish those same four files as a stable release with
`--latest=false`. Use the prepared release-notes file; preserve the factual
community signing statement: App/helper ad-hoc, PKG/DMG unsigned, no notarization.
Do not use the Developer-ID-only `promote-release.yml` path for this candidate.
Save the complete release API response to this directory's `release-created.json`.
Do not replace an existing tag, release or asset.

```bash
bash design/release-v5.0.3/publication/artifact-public-verify.sh \
  "$candidate_run_id" "$source_sha"
```

This anonymously checks release/tag identity, API asset digests and sizes,
unchanged candidate proof, all four public files and exact byte equality to the
accepted candidate. The output is `dist/public-v5.0.3-verify/` plus
`artifact-public-provenance.json`. If public CDN transfer fails, the preserved
HTTP/1.1 retry changes only the transport and retains the frozen verification
guards:

```bash
bash design/release-v5.0.3/publication/artifact-public-curl-retry.sh \
  "$candidate_run_id" "$source_sha"
```

The retry requires successful first-range probes, validates every HTTP 206
range boundary and size, checks assembled bytes against API digests, and records
that the validation main is byte-identical to the frozen source. Neither public
entrypoint overwrites an accepted output. Partial transport scratch is cleaned
on failure before a retry. Authorization and signed redirect URLs are never
retained in public evidence.

## Homebrew and Pages

If repository `HOMEBREW_TAP_TOKEN` is configured, the existing
`homebrew-tap.yml` dispatch accepts `release_tag=v5.0.3`, synchronizes the cask,
waits for its exact-SHA `tests.yml` run, and dispatches the public install tests.
The 5.0.2 release used the maintainer route because that token was unavailable:

```bash
bash design/release-v5.0.3/publication/tap-sync.sh \
  "$verified_public_pkg_sha256" "$source_sha" "$candidate_run_id"
```

Unlike the verification entrypoints, **tap-sync writes externally when invoked**:
after all unchanged candidate/public checks pass, it clones the tap into owned
scratch, changes only the cask version and PKG SHA, commits, and pushes tap main.
It never dispatches a workflow. Wait for `laleoarrow/homebrew-tap`'s `tests.yml`
**push** run on that exact new tap commit, then dispatch
`homebrew-install-test.yml` on frozen main with `release_tag=v5.0.3`.

Both public Intel and Apple-silicon install lifecycles must pass. That workflow
then marks the release Latest and dispatches `pages.yml` automatically. Do not
duplicate these actions. Wait for Pages success on the same frozen source, then:

```bash
bash design/release-v5.0.3/publication/verify-public-artwork.sh \
  --source-sha "$source_sha" --pages-confirmed-success \
  --pages-head-sha "$source_sha" --pages-run-id "$pages_run_id" \
  --output "$PWD/design/release-v5.0.3/publication/public-site-verification.json"
```

This checks anonymous Latest, version-specific homepage downloads, the full
frozen gallery and editable SVG ZIPs. Only after these public gates pass should
release announcements and the authorized Cody email describe 5.0.3 as released.
The maintainer Mac must then be synchronized with the verified **public** PKG
bytes, even if a separate local 5.0.3 preview was already installed; retain and
compare existing settings, helper, receipt and canonical popup acceptance.

## Animated promotional artwork

The versioned Pages gallery includes 13 previews: the seven retained approved
previews, the full-charge GIF and poster, full-charge light/dark cards, and
scrollbar light/dark cards. The GIF is embedded in the release description and
email using its public gallery URL. These are gallery resources, separate from
the strict four-file installer artifact set; do not append them as GitHub
Release assets. The frozen gallery checksum and public-byte verifier cover
every promotional image, including the animation.
