# Canonical 4.3.23 installation verification

These scripts collect or verify the canonical installation. They do not install
software, open the App GUI, quit the running App, change preferences, or use the
user-local developer installer.

`before.json` was collected read-only for intended release source
`23185f299ce61b8e373ebf5115b461ad2aa01226`. It records the existing 4.3.22 App,
PID 80435, App/helper/daemon hashes, package receipt and 15 product-setting value
hashes. The source SHA identifies the intended upgrade, not the currently
installed preview's source. Raw setting values are not written. Both sandbox
and legacy preference locations are read; any additional stored product settings
are also preserved if present. Window geometry and other AppKit keys are omitted.
The collector did not contact the helper or change canonical lifecycle.

To collect a fresh baseline immediately before an installation, preserve the
existing record and choose a new output path:

```bash
/usr/bin/env -u PYTHONOPTIMIZE PYTHONDONTWRITEBYTECODE=1 \
  /usr/bin/python3 design/release-v4.3.23/installation/installation_state.py \
  23185f299ce61b8e373ebf5115b461ad2aa01226 \
  --output "$PWD/design/release-v4.3.23/installation/before-fresh.json"
```

After the root agent has installed the exact approved public PKG, run as the
console user (without sudo):

```bash
/bin/bash design/release-v4.3.23/installation/verify-installed.sh \
  '/absolute/path/to/Wattson-v4.3.23-macos-universal.pkg' \
  'APPROVED_64_CHARACTER_LOWERCASE_SHA256' \
  '23185f299ce61b8e373ebf5115b461ad2aa01226' \
  '/absolute/path/to/public-package-verification.json'
```

An optional fifth argument selects the fresh baseline file. The public PKG's
directory must also contain the verified public `SHA256SUMS.txt` and its listed
DMG/release-info files. The provenance JSON must come from the root agent's
completed public-asset verification and contain:

```json
{
  "packageSHA256": "the approved 64-character PKG digest",
  "sourceCommit": "the full frozen source SHA",
  "publicAssetsMatchCandidate": true,
  "packageVerified": true
}
```

Do not create that provenance record merely to satisfy the verifier. Its fields
represent prior completed release verification. The approved public PKG digest,
PKG path and provenance path remain pending until root supplies them.

The post-install verifier checks all public manifest hashes and the independently
approved PKG digest, then expands the PKG under an owned project-local `.noindex`
directory. It requires the installed App bundle to match the payload recursively,
the helper and daemon to match byte-for-byte, marketing/build/receipt versions to
be 4.3.23, valid strict signatures, and exactly arm64 plus x86_64 slices in each
binary (each architecture is checked separately). Fixed CLI health/v5 probes exit
before `NSApplication` is created. One bounded fixed process-sampling read checks
the Activity Score formula; raw PIDs, names, audit tokens and frames are not
persisted. All 15 baseline settings are compared by value hash.

The outer entry calls `verify-payload.sh` through `wattson_run_script` and waits
for that inner shell to exit, including its shared EXIT cleanup. The inner shell
is the actual parent of all payload-check runners; its shared lifecycle helper
waits for owned commands, unregisters only the expanded App and removes scratch
on success, failure and catchable interruption. Both shells retain the shared
EXIT trap; cleanup is never moved to a subshell. No
mount is created. A per-attempt evidence directory retains check output and exit
codes. `local-install-verified.json` is created only after cleanup succeeds and
LaunchServices/Spotlight no longer list the expanded App. Canonical App/helper/
daemon presence is checked again after cleanup. Existing verification records
are never overwritten. Popup interaction and post-launch PID stability remain
separate root-agent checks; these scripts do not claim them.

Preparation validation: Python source parsing and `bash -n` passed. The real
before collector succeeded with 15 hashes and unchanged canonical PID 80435.
The post-install script has not been run against the current 4.3.22 installation.

## Cleanup / interpreter revision

`preparation-verification.json` preserves the original preparation snapshot and
its original script hashes. `revision-verification.json` records the corrected
owner-shell design, current script hashes, shell/Python parsing and six rejection
checks. Inherited `PYTHONOPTIMIZE=1` and `2` are cleared by both shell entrypoints;
the invalid-provenance fixture still fails at its actual assertion. Direct
optimized Python entry is explicitly rejected before it can read canonical data
or bypass assertions. `PYTHONDONTWRITEBYTECODE=1` is set and no project pycache
was left. The original before record remains byte-identical. These were rejection
checks only: no install attempt directory, helper contact or App lifecycle
change occurred. The existing PID 80435 remained running.

`independent-review.json` records a separate agent's static trap/ownership and
interpreter-gate review with no blocking finding. Its four reviewed script
hashes match `revision-verification.json`. The original preparation hashes are
historical only and must not be used to attest the revised verifier. Neither
that review nor the rejection checks executed installation, canonical helper
probes or an actual post-install verification.

## Finalize-only resume after the first real installation

The successful inner checks and owner-shell cleanup from
`checks-20261019T090950Z-65536` compared the exact public package and 16 settings
from the fresh `before-install.json`. The original 15-setting `before.json` is
unchanged. Only the final read-only LaunchServices observation timed out after
15 seconds. `finalize-budget-adjustment.json` and its patch retain the reason,
old/new hashes and the two changed budget constants: LaunchServices 45 seconds,
total runner 90 seconds; Spotlight stays at 15 seconds. Every assertion stays
in place and no automatic retry was added.

Root may resume only finalization using the completed stage below. This does
not re-expand the PKG, repeat helper probes, install, or start/stop the App.
The failed original `finalize.err` and logs must remain unchanged. Redirect to
new resume logs when executing, if desired.

```bash
/usr/bin/env -u PYTHONOPTIMIZE PYTHONDONTWRITEBYTECODE=1 \
  /usr/bin/python3 "$PWD/scripts/lib/run_owned.py" --timeout 90 -- \
  /usr/bin/python3 "$PWD/design/release-v4.3.23/installation/verify_details.py" finalize \
  "$PWD/design/release-v4.3.23/installation/checks-20261019T090950Z-65536/checks-passed-before-cleanup.json" \
  "$PWD/design/release-v4.3.23/installation/local-install-verified.json"
```

The budget revision was parsed and shell-syntax checked. Its author did not
execute finalization or contact the canonical App/helper.
