# macOS system metric authority — 4.3.24 local candidate

The user reported System Settings Maximum Capacity at 84% while Wattson showed
Battery Health at 80%. The previous implementation divided AppleRawMaxCapacity
by DesignCapacity. On this Mac those raw controller values were 6895 / 8579 mAh
(80.37%); the official power report returned 84%. These are different metrics.

## Source policy

- Battery Health now uses only `SPPowerDataType` → `spbattery_information` →
  `sppower_battery_health_info` → `sppower_battery_health_maximum_capacity` from
  `/usr/sbin/system_profiler -json`. Initial/unavailable health is `—`.
- The fixed read-only command runs off the UI/sample path, with a 7.5-second
  deadline, a 256 KiB output limit, and TERM/KILL/reap cleanup. Concurrent reads
  coalesce. Success is cached for 15 minutes; failed refreshes clear the value
  and retry after one minute. No raw-capacity health fallback is allowed.
- One public IOPS reading supplies charge percentage and charging state for
  startup and continuing samples. Registry percentage remains the fallback
  when the system percentage is unavailable.
- Charging state survives an unavailable runtime estimate. The header,
  macOS 27 charging adornment and Wattson charging tint use the reported state;
  100% alone no longer implies full. Power flow retains its physical topology,
  including mixed supply. The existing macOS 26 external-power artwork is retained.
- Controller mAh values and runtime estimates have source tooltips. The existing
  observed-discharge runtime approximation keeps its `≈` marker. Power, current
  and temperature remain hardware readings/derived values, not claims about
  equivalent System Settings fields. Activity Score remains Wattson's own score.

The permanent rule is recorded in `AGENTS.md`. Apple's power-management source
[gates health data on the calling process's entitlement](https://github.com/apple-oss-distributions/PowerManagement/blob/main/pmconfigd/BatteryTimeRemaining.m#L4632).
The public IOPS description on this Mac has no official health percentage;
`system_profiler` provides it without adding entitlements to Wattson or its helper.

## Verification

- Full Swift suite: 698 tests, zero failures (`swift-tests.log`).
- Production hidden AppKit renderers: 46 cases, 658 assertions, zero failures
  (`production-captures/evidence.json`); six states in light/dark. These are
  fixture-driven layout renders, not live WindowServer or Liquid Glass captures.
- Production reader on this Mac: 84% (`live-system-comparison.json`).
- Exact shipping App Sandbox entitlements: the same production reader returned
  84% in 0.222 seconds, with a confirmed sandbox home (`sandbox-health.json`).
  `sandbox-probe.sh` owns and cleans its temporary app, process, preferences,
  registrations and newly created container.
- Full Python suite: 625 tests, four expected GUI skips. Its first run exposed
  two isolated harness compile lists missing the new reader and one obsolete
  source assertion for the old charging rule. Those test contracts were updated;
  all 26 tests in the two affected modules pass on recheck (`python-recheck.log`).
  The original run remains in `python-tests.log`.
- Universal arm64/x86_64 App/helper build, PKG/DMG payload verification and
  checksums pass (`package-build.log`, `package-checksums.txt`). This is the
  existing community ad-hoc signing mode: unsigned PKG/DMG, not notarized.
- A fresh pre-install record retains the canonical 4.3.23 identity and hashes of
  all 16 stored product settings (`before-install.json`). Installation is a
  separate step requiring macOS administrator authentication.

## Canonical installation

The verified local 4.3.24 PKG was installed successfully through the macOS
administrator authorization flow. `install-verification.json` confirms matching
App/helper/daemon payloads, app/build/receipt versions, strict signatures, exact
production entitlements, both architectures and fixed helper health/v5 probes.
All 16 product-setting hashes are unchanged. `installed-process.json` confirms
one stable canonical process after the upgrade.

The first verifier attempt passed payload checks but its inline Python finalizer
received empty stdin through the background process owner. It produced no success
manifest. The finalizer now runs from an owned scratch file; the corrected
verifier passed and cleaned its payload directory. The separate first-attempt
record is retained. Both attempts were read-only installation verification.

Actual canonical popup acceptance remains unverified: CUA app access timed out
twice. No claim is made that the new installed popup was clicked or visually
inspected. The successful six-state production renders and sandboxed live 84%
reading are separate evidence, as described above.

The local candidate is not a public release. No public tag, Homebrew change,
Pages deployment or release email is implied by these checks. Pre-existing
untracked Display validation evidence is outside this change and is preserved.
