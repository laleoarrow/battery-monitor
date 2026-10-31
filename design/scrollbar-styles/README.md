# Scrollbar styles — design proposal

Latest user corrections, 2026-10-31: preserve all existing App body design and
the original **right-side** scrollbar placement. Default to **Hidden**. Simple
means the original **gray native scrollbar**. Replace the rejected orbit with
a theme-colored flowing treatment inspired by the first section's power-flow
line: unevenly spaced white points move only downward and fade at the bottom.
This is a reviewable proposal, not a native implementation or release.

## Settings

Add **Settings → General → Appearance → Scrollbar** using the existing small
native popup menu. Options: **Hidden / Simple / Flow** (隐藏 / 简洁 / 流光).
All three are preferences to ship together. Both the proposed product default
and the preview's first-load selection are Hidden.

- Hidden: no visible scrollbar; trackpad, wheel and keyboard scrolling remain.
- Simple: keep the current gray native scrollbar, including its system behavior.
  The preview's gray capsule is a local illustration, not a replacement renderer.
- Flow: a 6px capsule blends from subdued theme color toward brighter color,
  with five small white points of varying size and deliberately uneven spacing.
  Each travels downward over 3.4 seconds, fades out before reaching the bottom,
  and reappears at the top only after an invisible reset. No upward motion,
  orbit, external halo, or evenly spaced particle train.

The flow is decorative: thumb position and length always represent the viewport.
No separate breathing cycle or ring pause is part of this scrollbar proposal.
Earlier battery-time-source indicator timing is unrelated and remains unchanged.

## Scope and appearance

- Keep the existing right gutter and App geometry. No changes to body icons,
  power-flow paths, fonts, chart, instruments, footer, or shared scroll document.
- Only show a scrollbar when content overflows. Switching styles preserves the
  reading position. Dragging and track clicks use the same vertical mapping.
- The Flow palette follows existing charging green, plugged/mixed blue and
  battery neutral colors, with Light/Dark contrast adjustments. Simple stays
  gray regardless of palette. All flow highlights stay clipped inside the thumb.
- Reduce Motion holds a static gradient and points. Hidden, offscreen, closed,
  and no-overflow states stop motion. Native implementation must also honor
  increased-contrast and reduced-transparency policies.
- A 26px invisible interaction area is demonstrated around the 6px artwork.
  Native integration must preserve content hit targets and the existing gutter.

`scrollbar-style-preview.html` shows only the settings row and an isolated
scrollbar component. Top/middle/bottom labels are abstract scroll-position
markers, not App content. The earlier approximate recreation of the App body
was removed after the user explicitly rejected changes to other design areas.
The actual dropdown, wheel scrolling and dragging remain interactive. Optional
preview controls adjust appearance, Flow palette, local height and reduced
motion. No production preference or installed App is changed.

The original right-side placement is verified by the real WindowServer capture
`../battery-time-indicator/implementation/native/captures/classic-dark-full-3-top.png`
and its light counterpart (`composited=true` in their `evidence.json`). Native
`Popover/PopoverContentView.swift` uses `NSScrollView`, enables its vertical
scroller for insufficient height, and sets `autohidesScrollers=true`; it has no
left-side relocation override.

## Native implementation, after design review

`Core/Settings.swift` owns the persisted enum/default and change notification.
`MenuBar/SettingsWindowController.swift` owns the appearance row. Update relevant
exhaustive setting switches when adding the notification case.
`Popover/PopoverContentView.swift` owns viewport sizing, scroll offsets and
lifecycle. Preserve its native gray scroller for Simple; scope custom artwork
and dragging to Flow. Reuse the existing motion/accessibility policy and palette.

Native acceptance must cover 240pt short screens, all three styles, default
Hidden and preference persistence, exact top/bottom dragging, no jump when
switching, Classic/Glass, overlay/legacy, Light/Dark, reduced motion and closed
animation cleanup. Compare all six production battery states to ensure the
rest of the App is unchanged. Browser checks are only design-preview evidence.

## Preview verification

`render-preview.sh` owns its isolated browser profile and temporary resources
through the shared cleanup helpers. `render-preview.mjs` checks Light/Dark at
736px and 320px, default Hidden, all three styles, scrolling, dragging, style
changes, gray Simple, right-side Flow, uneven downward points, clipping and
live Reduce Motion. Current results and source identity are in
`verification.json`; retained design captures are in `previews/`.
