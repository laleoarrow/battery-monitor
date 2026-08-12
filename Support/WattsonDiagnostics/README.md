# Wattson Diagnostics

`Wattson Diagnostics.app` v1.1.0 is a standalone, read-only support tool for macOS 12
or later. It collects a bounded snapshot of Wattson's app bundle, package
receipt, privileged helper, launchd registration, and related installation
logs, then copies the report to the clipboard for the user to review and paste
into a support email.

For power and temperature issues, it also reads only the named
`AppleSmartBattery` fields used by Wattson, reports both raw and decoded
temperature values, interprets both battery-current fields as signed 32-bit
values, and asks the helper's fixed `health` and `getPower`
endpoints for five samples about one second apart. It contacts the helper
socket directly and does not launch the installed Wattson app. The live power
endpoint requires the Wattson v3.0.4 or later helper; older helpers are reported
as unavailable.

The tool has no `sudo` path, repair action, password prompt, network client, or
automatic upload. Its exact executable/argument pairs are allowlisted in
`main.swift`. It does not collect hardware serial numbers, platform UUIDs,
whole battery firmware dictionaries, a complete I/O Registry dump, or a full
process list. Process details are limited to the exact Wattson v3 and legacy
bundle identifiers, and battery telemetry is limited to the named power and
three corresponding accumulator-count fields. Home-directory paths and the
current hostname (with or without its `.local` suffix) are redacted from the
final report, whether macOS supplies the tool with the short or `.local` form.
The user can inspect the bounded text before deciding
whether to paste it into an email.

Build the universal support archive with:

```bash
bash scripts/build_diagnostics.sh
```

The ZIP and its checksum metadata are written to `dist/support/`. Because the
community build is ad-hoc signed and not notarized, macOS 15 or later may block
the first launch. Try opening the app once, then use System Settings → Privacy
& Security → Open Anyway only after verifying that it came from the official
Wattson GitHub release. Older macOS versions may instead offer Finder's
Control-click → Open flow.
