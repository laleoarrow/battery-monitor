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

## Final user clarification

The user clarified that each individual bar should contain a low-to-high
gradient within one color family. Every filled bar therefore uses a complete
horizontal gradient: pale blue #9CDCFF at its left edge, #2C9DFF at 45%, and
deep blue #0B69D9 at its right edge. Short bars retain the same complete gradient.
Activity changes the bar's length and value. All rows share the palette.
High contrast retains the solid system-blue alternative.

The title remains **Process Activity** and the numeric column is labelled
**Activity Score**. The information popover starts with the user's wording:

> Activity Score combines CPU usage and idle wakeups. Higher scores indicate
> greater process activity, not measured power consumption.

It also explains the fixed 0–100 scale, overflow mark and one-logical-core CPU
convention. Formula provenance stays in developer documentation and source
comments. The app independently samples `libproc` counters and calculates its
own score; the product UI does not attribute observations to `top`.

This clarification supersedes the earlier vertical gradient and per-score tint
interpretation. Sampling, numeric calculations and layout remain unchanged.

## Acceptance status

Native implementation evidence is linked from the accompanying README.
The previous `module-dark.png` and `module-light.png` remain rejected evidence;
they do not demonstrate this Pro redesign or imply user approval.
