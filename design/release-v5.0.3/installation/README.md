# Verify the canonical public 5.0.3 installation

These read-only entrypoints retarget the audited local 5.0.2 payload and canonical
state checks to 5.0.3. They add an explicit frozen source SHA and binding to the exact
anonymous public-download proof and retained public PKG. They never install,
request authorization, contact anyone or launch a GUI.

Run as the logged-in console user, after candidate and public download
verification have completed successfully and cleaned their workspaces:

```bash
pkg="$PWD/dist/public-v5.0.3-verify/Wattson-v5.0.3-macos-universal.pkg"
before="$PWD/design/release-v5.0.3/installation/before-public-install.json"
bash design/release-v5.0.3/installation/verify-installed.sh \
  before "$pkg" "$source_sha" "$before"
```

The source SHA must be the full frozen commit; no historical/default SHA is
accepted. Preserve this baseline before the separately authorized native PKG
installation. Settings values are recorded only as hashes.

After installation finishes, choose a new results directory:

```bash
bash design/release-v5.0.3/installation/verify-installed.sh \
  verify "$pkg" "$source_sha" "$before" \
  "$PWD/design/release-v5.0.3/installation/verified-public-5.0.3"
```

The verifier rechecks all four public files against the accepted candidate,
unchanged provenance and completed download cleanup. It compares canonical App,
helper and daemon bytes with the public PKG; verifies signatures, arm64/x86_64,
App/build/receipt versions, helper health/v5 and every retained setting. The
inner owner uses shared cleanup for expanded payloads, registration and child
processes. The outer finalizer rechecks cleanup, settings and canonical hashes
before writing `public-install-verified.json` with `allPassed=true` and
`publicRelease=true`.

An actual open/close of the canonical menu-bar popup remains a separate manual
acceptance step. This verifier deliberately reports `popupInteractionVerified=false`.

The imported local verifier's version and version-specific error text are
retargeted only in this wrapper's loaded module instance. Historical verifier
files remain unchanged. Offline fixtures confirm that the wrapper accepts a
matching 5.0.3 App/build/receipt tuple and rejects 5.0.2 without reading or
changing the canonical installation.
