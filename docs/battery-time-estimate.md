# Battery time estimates

Wattson prefers the internal battery's public IOPS time in minutes. A valid
system estimate appears immediately. Full and paused charging are states, not
times inferred from the displayed percentage.

When that time is missing, the normal sampling reader uses this order:

1. The battery controller's matching `AvgTimeToEmpty` or `AvgTimeToFull`.
2. During discharge only, remaining raw capacity divided by a smoothed discharge
   current: `minutes = 60 × remaining_mAh / average_discharge_mA`.
3. `Unavailable` if neither source can support an estimate. Sampling continues,
   so a later valid reading restores the time automatically.

Fallback starts after 60 seconds of continuous, consistent sampling. A gap over
10 seconds, backwards clock, source/direction change, failed sample or wake
clears its history. Invalid optional measurements do not restart an indefinite
`Estimating…` loop. IOPS notifications that do not actually change direction,
and unrelated power-telemetry freshness resets, do not discard this history.

The discharge calculation uses an exponential moving average with a 60-second
time constant. Values of at least five minutes are rounded to five minutes and
displayed with `≈`; its tooltip and diagnostic report identify the source.
The actual controller estimate is not filtered again. These are Wattson's
stability choices, not promised macOS timing or a copy of Stats' algorithm.

Only the paired `AppleRawCurrentCapacity` and `AppleRawMaxCapacity` are used as
mAh. Ordinary capacity fields can be percentages on Apple silicon. Invalid
capacity pairs, nonnumeric values, opposite-sign, zero or tiny discharge
currents cannot produce a local estimate. The controller's unsigned 16-bit
unknown value `65535` is rejected. Mixing units or reusing an estimate from a
previous power direction is never a fallback.

There is no linear capacity-gap/current fallback while charging: current falls
during the constant-voltage phase, and charging may be paused or limited. A
linear extrapolation could substantially understate time to full. The controller
estimate remains available as the first backup for that state. Mixed supply
shows `Not Charging`, and a displayed 100% alone does not mean `Fully Charged`.

## Source review

- [Stats reader](https://github.com/exelban/stats/blob/c9e7ebe3390a84e3075946ffe39dda709c4747b1/Modules/Battery/readers.swift#L87-L94)
  and [popup](https://github.com/exelban/stats/blob/c9e7ebe3390a84e3075946ffe39dda709c4747b1/Modules/Battery/popup.swift#L302-L360):
  Stats reads the two IOPS times and shows Unknown/Calculating when missing; it
  does not calculate a backup time from its capacity/current measurements.
- [Apple battery driver](https://github.com/apple-oss-distributions/PowerManagement/blob/d415e45501842834a280930c3eed9186544a67f0/AppleSmartBatteryManager/AppleSmartBattery.cpp#L1483-L1514):
  average current and the two controller time values are separate from
  instantaneous current; the controller times already account for average load.
- [Smart Battery Data Specification 1.1](https://www.sbs-forum.org/specs/sbdat110.pdf),
  sections 5.1.11–12 and 5.1.19–20: signed current in mA, average time in minutes,
  rolling averaging and the invalid 65535 sentinel.
- [Apple lithium-ion charging](https://www.apple.com/batteries/why-lithium-ion/):
  charging slows at high charge levels; a constant-current extrapolation is not
  a general time-to-full model.

The raw registry keys are optional implementation details. Their absence must
not stop normal monitoring or cause a new privileged request. No extra timer,
helper operation, or complete registry dump is required by the fallback.
