# Scrollbar styles — design proposal

User request, 2026-10-31: the compact popup scrolls vertically and exposes three
user-selectable scrollbar styles, including a flowing star-ring treatment on
the left. This is a reviewable proposal, not a native implementation or release.

## Settings

Add **Settings → General → Appearance → Scrollbar** as a peer appearance row,
using the existing small native popup menu. Options: **Hidden / Simple / Orbit**
(隐藏 / 简洁 / 星环). Simple remains the default for existing and new users.
All three options ship together; they are preferences, not competing designs
from which only one will be implemented. The preview initially selects Orbit
to show the proposed new treatment.

- Hidden: no visible scrollbar; trackpad, wheel and keyboard scrolling remain.
- Simple: a quiet proportionate thumb with a light-to-deep theme-color gradient,
  positioned left.
- Orbit: the same 6px gradient capsule contains the entire curved light path,
  white leading point and short dust tail. The point travels down the near
  curve and returns along the dimmer far curve, wholly inside the thumb.

User correction, 2026-10-31: the first proposal's outward ellipse was rejected.
The revised ring is an internal material detail, clipped by the rounded capsule.
No ring, dust or glow protrudes beyond the bar. Simple also uses a theme-color
gradient. The 26px transparent hit region is unchanged and is not visible art.

The thumb's position and length encode the actual viewport. Decorative motion
never moves content or changes that geometry. Dragging is linear vertically,
even though the artwork curves. A 2.8-second lap and 0.5-second rest echo the
existing time-source animation; there is no separate blinking cycle.

## Behavior and boundaries

- Display the bar only when content exceeds the viewport. Changing styles does
  not reset the scroll position. All popup content, including header and footer,
  remains in the current shared scroll document; no new fixed bars are proposed.
- Reserve only the existing left gutter. Keep the 360pt popup and 328pt
  instrument geometry intact. A wider invisible hit target must not capture
  interactions with content. Do not use global RTL to relocate a scrollbar.
- Use the existing instrument palette: charging green, plugged/mixed blue,
  battery neutral, with Light/Dark contrast adjustments. No fixed blue palette.
- Keep the stationary gradient capsule as the position indicator in Orbit.
  White points sit over that colored fill, with highlights clipped inside it.
  Hover/drag may strengthen the highlight,
  without widening the content layout or continuously changing its position.
- Reduce Motion preserves a static ring and thumb. Close, hide, detach and
  no-overflow states stop motion. Honor higher-contrast and reduced-transparency
  policies when implementing the native view.

`scrollbar-style-preview.html` is the interactive design fragment. Its sample
readings are illustrative, not live telemetry. The actual dropdown switches all
three options; wheel/touch scroll and dragging the left thumb move the same
document. Optional preview controls adjust appearance, palette, viewport height
and reduced motion. No production preference or installed app is changed.

## Native implementation touchpoints, after design review

`Core/Settings.swift` owns the persisted enum and change notification.
`MenuBar/SettingsWindowController.swift` owns the appearance row. Update the
relevant exhaustive setting switches when adding a new notification case.
`Popover/PopoverContentView.swift` owns viewport sizing, scroll offsets and
presentation lifecycle. A narrowly scoped scroller owns the artwork and drag
mapping. Reuse the battery-time indicator's motion/accessibility policy and
palette rather than introducing a sampling timer.

Native acceptance must cover 240pt short screens, all three styles, exact
top/bottom dragging, preference persistence, no offset jump on switching,
Classic/Glass and overlay/legacy behavior, Light/Dark, Reduce Motion and closed
animation cleanup. A browser preview does not substitute for these checks.

## Preview verification

The isolated browser check passed at 736px and 320px in both Light and Dark:
four layouts without horizontal overflow and twelve style/appearance/width
interaction cases. All modes scroll; both visible thumbs drag to the bottom;
switching preserves the reading position. The star moves in normal mode and
remains stationary after a live Reduce Motion change. There were no JavaScript
errors. Five cropped design screenshots and `verification.json` retain the
revised results, including the gradient Simple style in Light and Dark.
The complete 3.4-second orbit observation sampled 1,435 star/tail bounds, with
none outside the visible capsule; the rounded container also clips their glow.
The original preview-only media-event correction remains in revision history.

The browser owner exited successfully, then its scratch, referencing processes
and temporary preview directories were confirmed absent. No installed App,
production preferences or user browser profile was touched.
