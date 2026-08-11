# Wattson Diagnostics

`Wattson Diagnostics.app` is a standalone, read-only support tool for macOS 12
or later. It collects a bounded snapshot of Wattson's app bundle, package
receipt, privileged helper, launchd registration, and related installation
logs, then copies the report to the clipboard for the user to review and paste
into a support email.

The tool has no `sudo` path, repair action, password prompt, network client, or
automatic upload. Its exact executable/argument pairs are allowlisted in
`main.swift`.

Build the universal support archive with:

```bash
bash scripts/build_diagnostics.sh
```

The ZIP and its checksum metadata are written to `dist/support/`. Because the
community build is ad-hoc signed and not notarized, a downloaded copy may need
Finder's Control-click → Open flow.
