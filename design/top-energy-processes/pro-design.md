# Pro redesign specification

The user rejected the first thin relative-bar candidate and explicitly asked
for Pro to redesign it. The request was submitted in ChatGPT with its model
selector visibly set to **Pro, 5 of 5**. The completed response was read on
2026-10-17 from [the design conversation](https://chatgpt.com/c/6ad3462b-e22c-83e8-b29e-a7b87e97a101).
This identifies the verified UI mode, not an unverified underlying model ID.
The three supplied images were the user's style reference, the rejected native
module, and the Settings icon orientation correction.

## Selected direction

Pro recommends **Process Activity**: process name, a short thick bar and activity
points on the first line, with CPU percent and platform idle wakeups per second
on the second. Ranking, numeric value and bar length use the same formula:

```
activity points = CPU % + 0.05 × platform idle wakeups / second
```

Bars use a fixed 0–100-point reference. At zero they are empty; small nonzero
values are not inflated to a minimum visible fill. Above 100 the real value
remains visible and an overflow mark accompanies the full bar. The scale does
not follow the first-ranked process or the selected row count.

## Native layout

For 328 points of content width:

| Element | Specification |
| --- | --- |
| Header | Process Activity; 0–100 pts and a native information control |
| Rows | 44 points each; two lines; no row card or background |
| Name | x=0, width 132; 13-point text; trailing truncation; full name/PID tooltip |
| Bar | x=144, width 116; height 12; corner radius 3; 1-point outline |
| Main value | x=272, width 56; right aligned; 13-point semibold monospaced digits |
| Details | 11-point secondary text; CPU percent and idle wakeups/s |
| Gradient | Vertical, opaque: #9CDCFF at 0, #2C9DFF at .45, #0B69D9 at 1 |
| Outline | Light #AAC7DE; dark #DCEEFF at .75 opacity |
| Accessibility | High contrast uses label outline and opaque system blue; no motion |

The information control explains the formula, one-core CPU convention, roughly
one-second sampling window and lack of GPU or measured-watt attribution. The
existing open-popup sampling cadence remains unchanged. Invalid data shows
Unavailable rather than zero. Existing count-dependent reserved height avoids
moving the popup when a read returns fewer rows.

The Settings icon uses three horizontal bars, descending in length, as the user
explicitly requested. This is separate from the Power Lanes icon.

## Subsequent user color refinement

After reviewing the native Pro implementation, the user requested a color
gradient that reflects low-to-high activity and explicitly limited it to one
color family. The implementation therefore uses the same fixed 0–100-point
scale to deepen the blue palette as activity rises, while retaining a vertical
highlight. This user-directed refinement supersedes the uniform blue stop
colors above. It does not change measurement, bar lengths or layout.

The vertical stop palettes interpolate using `min(activity / 100, 1)`:

| Stop | Low activity | 100 points or above |
| --- | --- | --- |
| Top | #D4ECFF | #78BCFF |
| Middle | #90C9F5 | #187DE0 |
| Bottom | #5BA5E3 | #0754B0 |

Every stop stays within the blue family and becomes darker as activity rises.
The same colors remain in light and dark appearances; high contrast retains
the solid system-blue alternative.

## Acceptance status

Native implementation evidence is linked from the accompanying README.
The previous `module-dark.png` and `module-light.png` remain rejected evidence;
they do not demonstrate this Pro redesign or imply user approval.
