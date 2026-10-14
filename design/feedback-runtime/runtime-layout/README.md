# Selected runtime layout — 2026-10-14

The user selected the clock-left, title/time-right layout from the Pro-generated
concepts. They then clarified that the blue accent was too prominent and that
an independent module must use the existing section separators, rather than a
filled card. See the [selected layout](selected-reference.png) and
[separator feedback](separator-feedback.png).

The production AppKit view is an independent 88-point module between Ring Gauge
and Power Lanes. Its background is transparent and its top hairline matches the
existing instruments. The next visible section supplies the bottom separator.
The clock well is the only filled element; it uses the existing adaptive well,
border and neutral icon colors. A quiet title sits above a 24-point time reading.
No full-width card background, outline, shadow or blue accent is added.

Hiding the module removes its entire height. The estimate source and saved module
preference are unchanged. The reference's disclosure arrow is omitted because
there is no runtime detail page. The estimate explanation remains available as
tooltip and accessibility help. No new navigation, preferences or timer is added.

## Production renderer previews

- [Dark](dark-battery.png)
- [Light](light-battery.png)

These are production `PopoverContentViewController` AppKit bitmap renders in
hidden windows, with Classic, Reduce Transparency and Reduce Motion enabled.
Readings and history are fixtures; `4h 25m` is not a measurement of this Mac.
External-power states display `External Power`, unknown estimates display
`Estimating…`, and degraded readings display `Unavailable`.

## Validation

The focused runtime tests cover Light → Dark → Light on the retained view and
accessibility changes delivered through the existing display-options notification.
The capture harness covers charging, full, battery, mixed, low battery and Low
Power in Light/Dark. It checks text containment, section separators, transparent
background, module order, exact height removal, no residual gap, and no shadows.

- Eight focused runtime Swift tests passed with warnings treated as errors.
- The complete compiled Swift suite passed: **383 tests, zero failures**.
- Module/settings Python contracts passed: **28 tests**.
- Twelve production-render cases passed **315 assertions, zero failures**.
- The updated real-window interaction harness compiles with warnings treated as
  errors; it was not executed in this layout-only iteration.

[Layout evidence](layout-evidence.json) records geometry, image hashes and
unchanged installed-app/helper/preferences hashes. No hidden capture window
became visible or key, and the foreground application was unchanged.
An earlier capture overlapped an external foreground-app change; every layout
check still passed and the capture process never became foreground. A quiet
rerun passed all protection checks. The earlier evidence is retained only in
the ignored capture directory.

The reusable capture command is documented in
[`runtime-section/README.md`](../runtime-section/README.md); use
`.build/runtime-section-preview.noindex/separator-captures` as the output directory.
All twelve captures remain there; the two on-battery examples are retained here.

Real WindowServer Glass capture is unavailable in the disposable macOS-TestLab
VM (macOS 26.6.1). An attempt during this iteration, before the final separator
refinement, failed ScreenCaptureKit preflight with `CAPTURE_PERMISSION_UNAVAILABLE`
through both Guest Agent and the existing Terminal entry point. No privacy
settings were changed. The temporary preview app and files were cleaned, and both
TestLab and Base are stopped. Attempt logs are in
`.build/runtime-card-review.noindex/`. This final revision has no new composited
Standard/Clear Glass evidence; the images above verify Classic content layout.

The canonical installed Wattson and its package receipt remain unchanged.
