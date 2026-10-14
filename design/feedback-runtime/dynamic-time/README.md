# Dynamic battery time — 2026-10-15

The independent 88-point section now switches with the power source. It remains
below Power History, with the same neutral clock, transparent background,
hairline separators, right-aligned text and unchanged footer controls.

| Power state | Title | Reading |
| --- | --- | --- |
| Internal battery, discharging | Estimated Battery Runtime | macOS Time to Empty |
| External power, charging | Estimated Time to Full | macOS Time to Full Charge |
| External power, system reports charged | Estimated Time to Full | Fully Charged |
| External power, not charging | Estimated Time to Full | Not Charging |
| Mixed supply / battery assist | Estimated Time to Full | Not Charging |
| Valid direction, no usable time yet | Corresponding title | Estimating… |
| Unavailable, stale or contradictory data | Corresponding title | Unavailable |

The module menu and Settings call this **Battery Time Estimate**. The saved
`popover.module.runtime` key is unchanged, so existing visibility choices persist.

## Data source and reference

[Stats' battery reader](https://github.com/exelban/stats/blob/c9e7ebe3390a84e3075946ffe39dda709c4747b1/Modules/Battery/readers.swift)
reads the two public IOPS time fields. Its
[popup](https://github.com/exelban/stats/blob/c9e7ebe3390a84e3075946ffe39dda709c4747b1/Modules/Battery/popup.swift)
switches the displayed time with the power source. These files match Stats
v3.0.21 at the time of this review.

[Apple's IOPS definitions](https://github.com/apple-oss-distributions/IOKitUser/blob/323ead896d04424f87184d8f6ff0cce811aab106/ps.subproj/IOPSKeys.h)
specify integer minutes. Time to Full Charge is valid while Is Charging is true;
Time to Empty is valid while running on battery without charging. The negative
unknown value does not represent a countdown. Is Charged is a system state and
must not be inferred solely from a displayed 100 percent or from a zero time.

Wattson reads one present internal-battery IOPS description per sample. The time
and direction travel together in `BatteryTimeEstimate`; the registry snapshot's
plugged state must agree. Every acquisition clears the preceding estimate before
applying the new one. Near-full low-wattage charging uses the IOPS charging flag,
while measured mixed supply suppresses a charge countdown. UPS values cannot
substitute for the internal battery. No capacity/power formula, extra timer or
private charging-control API is added.

Unknown minutes in a valid direction show Estimating. Zero valid minutes retain
the existing `<1m` formatting. Missing states, invalid source combinations and
degraded telemetry do not reuse an old number. Without evidence for optimized
charging, the UI says Not Charging rather than inventing a reason.

Feedback diagnostics now include the time kind and the corresponding remaining
or charging minutes. The collection's privacy scope is unchanged.

## Verification

The full Swift suite passes 394 tests with warnings treated as errors; the Python
suite passes 503 tests with four expected skips. The updated production renderer
passes 315 assertions across twelve Light/Dark power-state fixtures. Tests
cover direction changes on a retained view, accessibility label/help updates,
source disagreement, unknown and malformed times, charged/not-charging states,
mixed supply, near-full low-wattage charging, one IOPS read per valid sample, and
showing the newest direction after the module was hidden.

The [4.3.2 gallery](../../releases/v4.3.2/README.md) labels deterministic layout
fixtures separately from installed-app screen captures. Earlier release candidate
38590861130 passed before this addition and was never publicly released; it does
not validate or distribute this revision.
