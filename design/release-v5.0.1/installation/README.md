# Canonical 5.0.1 installation verification

These scripts do not install, launch or quit Wattson, or change preferences.
They verify the canonical App, helper and package receipt after installation of
the exact public 5.0.1 PKG. GUI interaction remains a separate check.

Before installation, collect the console user's current App and settings:

```bash
/usr/bin/env -u PYTHONOPTIMIZE PYTHONDONTWRITEBYTECODE=1 \
  /usr/bin/python3 design/release-v5.0.1/installation/installation_state.py \
  FULL_FROZEN_SOURCE_SHA \
  --output "$PWD/design/release-v5.0.1/installation/before-install.json"
```

The source argument identifies the intended release, not the installed version.
The baseline hashes product settings in both preference locations without
logging their values or contacting the helper. All baseline settings are later
compared; the count is read from the baseline rather than fixed in the verifier.
Existing evidence is never overwritten.
The baseline includes `popover.processWhitelist` whenever that setting exists;
the new key is optional for a 5.0.0 installation that has never used it. Every
existing product key, including a saved whitelist, must retain the same value
hash after the upgrade.

After installation, run as the console user:

```bash
/bin/bash design/release-v5.0.1/installation/verify-installed.sh \
  /absolute/path/to/Wattson-v5.0.1-macos-universal.pkg \
  APPROVED_PACKAGE_SHA256 \
  FULL_FROZEN_SOURCE_SHA \
  /absolute/path/to/public-package-verification.json \
  "$PWD/design/release-v5.0.1/installation/before-install.json"
```

The PKG directory must contain the public `SHA256SUMS.txt` and all three files
it lists. The provenance JSON must be produced by completed public verification,
with the following fields; do not create a success record just to satisfy this
verifier:

```json
{
  "sourceCommit": "the full frozen source SHA",
  "packageSHA256": "the approved public PKG SHA256",
  "publicAssetsMatchCandidate": true,
  "packageVerified": true
}
```

Verification requires public manifest checksums, payload byte equality, version
and receipt equality, strict signatures, both architecture slices, fixed helper
health/v5 probes, a bounded read-only Activity Score sample, and all retained
settings. Process names, per-process values and raw preference values are not
logged.

The inner shell owns its expanded payload and children through the shared
lifecycle helper. It unregisters only its expanded App and removes its project
`.noindex` scratch on success, failure or catchable interruption. No mount is
created. The outer verifier waits for that cleanup before checking registration
absence and writing `local-install-verified.json`. The canonical installation
and production preferences are never cleanup targets.

`preparation-verification.json` records parsing and rejection checks only.
It is not evidence of installation, helper health, GUI behavior or release
publication. Actual baseline and post-install records are added only when their
corresponding commands succeed.
