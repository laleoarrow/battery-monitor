# Wattson 5.0.0 exact-candidate verification

These tools adapt the previous audited release checks for version 5.0.0. They
never dispatch workflows, publish, install, launch the app, edit Git refs or
send mail. The source SHA and workflow IDs must be supplied explicitly after
the release commit is frozen:

```bash
/bin/bash design/release-v5.0.0/publication/artifact-verify.sh \
  CANDIDATE_RUN_ID SOURCE_SHA HEADLESS_PUSH_RUN_ID
```

There is one readiness check, with no polling. The candidate must be the first
attempt of a successful manual `main` run of `macos-helper-install.yml`. The
supplied Headless run must be a successful `main` **push** at the same SHA, and
remote main must still equal that SHA. All six candidate jobs must succeed.
Pending runs return before download; wrong identity, failed or expired artifacts
are rejected.

The download must match GitHub's artifact archive digest and size, contain
exactly the four versioned release files, and pass ZIP safety/CRC, strict
three-entry checksums and exact community metadata. The frozen source's
standalone verifier checks PKG/DMG byte-identical apps; supplemental inspection
checks both architectures' ad-hoc signatures and frozen App entitlements.
Canonical installed file/receipt hashes must remain unchanged.

Accepted files are retained at `dist/github-candidate-v5.0.0-RUN_ID/`, with
evidence in a new `artifact-RUN_ID-review.XXXXXX/` directory. Existing candidate
outputs are refused. Only the shared owner manages temporary `.noindex`
workspaces, subprocesses, app registrations and mounts; credentials and signed
URLs stay private inside that scratch. Require exit zero and absence of the
recorded workspace after the shell finishes. No whole-machine cleanup census
is claimed.

After publishing those exact bytes and recording the release API response in
`release-created.json`, verify the public download anonymously:

```bash
/bin/bash design/release-v5.0.0/publication/artifact-public-verify.sh \
  CANDIDATE_RUN_ID SOURCE_SHA
```

This requires the accepted candidate proof, unchanged evidence and candidate
bytes, a matching stable release/annotated tag, API asset digests and sizes,
anonymous public byte equality, and a strict checksum manifest. It retains
`dist/public-v5.0.0-verify/` and `artifact-public-provenance.json`; it refuses to
overwrite either. Exact byte equality inherits the completed candidate bundle
inspection without rebuilding or repeating it.

The Python helpers read the validated shell inputs through
`WATTSON_RELEASE_SOURCE_SHA`, `WATTSON_RELEASE_HEADLESS_RUN_ID` (candidate
transfer) and `WATTSON_RELEASE_CANDIDATE_RUN_ID` (public verification).
They have no historical source/run defaults. The fixed 5.0.0 community contract
requires App/helper ad-hoc, PKG/DMG unsigned, and no notarization.

Offline preparation checks:

```bash
env -u PYTHONOPTIMIZE python3 \
  design/release-v5.0.0/publication/test-artifact-tools.py
```

`artifact-tool-checks.json` records 27 passing syntax, identity, archive,
manifest, metadata, canonical-file and public-provenance acceptance/rejection
cases. Fixtures never access the network or installed app and automatically
remove their project-local temporary directory. These tests are preparation
evidence, not a claim that the actual release candidate has passed.
