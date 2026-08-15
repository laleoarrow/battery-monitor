# Wattson Settings Window Design

Date: 2026-08-13
Status: Superseded on 2026-08-15 by the compact 720×520 native layout
Scope: Historical design record for the original oversized Settings window

The current geometry is defined by `MenuBar/SettingsWindowController.swift`
and its executable contract in `tests/test_settings_window_contract.py`.
The measurements below are retained as the implementation history for the
original 792×794 design and are no longer current acceptance criteria.

Visual reference: `assets/wattson-settings-c-plus-e.png`. The left state is
General; the right state is Modules. This image was the implementation target
for the v3.0.6–v3.0.9 layout, and the measurements and behavior below were its
authoritative criteria when raster details were ambiguous.

## Context

Wattson is an `LSUIElement` AppKit menu-bar application targeting macOS 12 and
newer. Its current footer button opens a compact menu that mixes module
visibility, menu-bar percentage, launch-at-login, version, and quit actions.
The popover also contains a direct system-battery-icon checkbox and the live
Auto/Low/High power-mode control.

The new Settings window makes the existing infrequently changed controls easier
to find without changing the popover's primary power-monitoring experience.
The existing quick controls and menu remain available.

## Goals

- Add a native single-instance Settings window reachable from `Settings…` and
  the standard Command-Comma shortcut.
- Organize all seven existing persistent or system-backed choices into two
  compact sidebar pages: General and Modules.
- Keep the current popover controls and their behavior unchanged.
- Synchronize changes immediately between the Settings window, popover, and
  menu-bar presentation.
- Preserve current macOS 12+, arm64, x86_64, accessibility, reduced-motion,
  and helper-degradation behavior.
- Provide a small section-registration boundary for adding future settings
  without changing window lifecycle code.
- Add no periodic work, sampling, or rendering while the Settings window is
  hidden.

## Non-goals

- No visual redesign of the monitoring popover.
- No new power, sensor, sampling-frequency, theme, notification, or update
  settings.
- No migration to SwiftUI application lifecycle.
- No Dock icon or activation-policy change.
- No copy of Auto/Low/High in Settings; power mode remains an immediate system
  control in the popover and status-item right-click flow.
- No localization framework in this release; strings remain English, matching
  the existing application.
- No requirement that at least one monitoring module stay visible. All four
  may remain hidden, as they can today.

## User Experience

### Entry points

The existing footer sliders button continues to open its current quick menu.
The menu gains a `Settings…` item above version and quit. Wattson also installs a
minimal standard application menu so Command-Comma invokes the same action
while Wattson is active.

Opening Settings first dismisses the popover, allowing its existing delegate
path to stop the one-second display clock, animations, and outside-click
monitor. The application remains an `LSUIElement`; it activates only to bring
the Settings window forward and does not gain a Dock icon.

### Window

The window is a standard titled AppKit Settings window with a fixed two-column
layout. Its 20-, 20-, and 19-point reference traffic-light controls retain
explicit accessibility semantics and forward their actions to AppKit's native
close, minimize, and zoom controls. Identical minimum and maximum content sizes
prevent the measured composition from being distorted at its default scale. It
is centered only on first presentation, uses one
frame-autosave name to preserve a user-moved position across launches, does not
restore visibility, and never opens automatically at application launch.

The content size is 792×794 points. A fixed 232-point sidebar contains a
54-point traffic-light safe area, a 96-point Wattson identity row, and exactly
two 56-point navigation rows, each with 16-point horizontal insets and 4 points
between rows. The content pane is separated by the native one-point divider
and has 25-point horizontal insets, leaving 509 points of usable width. General
is selected on first construction;
the last page selected while the process remains alive is preserved across
close/reopen, but page selection is not persisted across launches.

On a display whose visible frame cannot contain the reference window, one
constraint-free viewport scales the entire 792×794 composition uniformly down
to the available area (as low as 60%). The inner layout remains in reference
coordinates, so proportions, hit testing, keyboard order, and accessibility
semantics do not reflow or crop. Returning to a larger display restores 1:1
geometry.

Closing hides the window without terminating Wattson. Reopening, repeated
menu commands, and repeated Command-Comma actions all reuse the same window and
bring it forward.

### Content

The window uses custom-drawn pill switches with native checkbox accessibility
and keyboard semantics, system typography, subtle separator/card layers, and
concise secondary descriptions. The sidebar
has exactly two registered pages:

1. **General** — one compact inset list with four rows:
   - Show Battery Percentage in Menu Bar
   - Launch at Login
   - Hide System Battery Icon
   - Use macOS-Style Icon
2. **Modules** — a 2×2 grid of compact visual cards:
   - Energy Flow
   - Ring Gauge
   - Power Lanes
   - Power History

General uses a 30-point semibold heading and one 509×400-point inset list with
four 100-point rows and a 13-point corner radius. Each row contains a 50-point
icon tile, primary and secondary labels, and a right-aligned 56×32-point switch.

Modules uses a 30-point semibold heading and a 2×2 grid across the same
509-point width. Horizontal and vertical gaps are 16 points; each equal-width
card is 246.5×258 points with a 13-point corner radius and a 112×108-point static
preview region. Each card contains a lightweight code-native preview glyph,
primary label, an explicit two-line secondary label, and a
right-aligned switch. The glyphs communicate flow, ring, lanes, and history
without rendering live data or starting animation. The reference raster's
wrapped descriptions are authoritative.

The fixed dark reference appearance uses explicit sRGB text, surface, divider,
and preview colors so it does not vary with wallpaper or transparency settings.
Preview/enabled accents use the reference green; the selected sidebar row uses
the reference green-gray fill in addition to its selected state,
label, and symbol, so color is never the sole state cue. The current version
and Quit remain commands in the quick menu, not settings.

When macOS Increase Contrast is enabled, only contrast-sensitive strokes and
inactive/selected surfaces switch to a stronger fixed palette and heavier
outlines. The normal appearance remains pixel-identical to the reference; the
system accessibility-display notification applies and removes the alternate
palette live without polling or animation.

The sidebar is an `NSTableView` with `.sourceList` style and disallows an empty
selection. It is the first responder on first show; native Up/Down navigation
changes sections. Tab enters the visible section at its first switch, follows
the visual switch order, and Shift-Tab returns to the sidebar. All controls
expose explicit accessibility labels and help. Dynamic checking, unavailable,
read-failure, and mutation-error text is included in the affected switch's
`accessibilityHelp`. A mutation error additionally posts one
`.announcementRequested` accessibility notification. The design does not add
custom motion.

## Architecture

### Window ownership

`StatusItemController` remains the UI lifetime root and strongly owns one lazy
`SettingsWindowController`. `AppDelegate` and `main.swift` keep their current
roles. The controller accepts injected dependencies and an optional frame
autosave name:

`init(sections:dependencies:frameAutosaveName:)`

The production default is `"WattsonSettingsWindow"`; tests pass `nil`, which
must skip both reading and writing frame autosave state. The controller creates
one `NSWindow`, sets
`isReleasedWhenClosed = false` and `isRestorable = false`, and exposes one
idempotent `show(activateApp:)` operation. Tests can pass `activateApp: false`
to avoid stealing focus.

The presentation callback crosses the existing hierarchy:

`PopoverFooterView -> PopoverContentViewController -> PopoverController -> StatusItemController`

`PopoverController` closes the popover before invoking the Settings presenter.

### Section extension boundary

The sidebar and content host consume an ordered collection of objects
conforming to a narrow
`SettingsSectionController` protocol:

- stable identifier;
- user-facing title;
- an AppKit page view and sidebar symbol;
- `refresh()` for authoritative state when the window opens.

The default registry contains `GeneralSettingsSectionController` and
`ModuleSettingsSectionController`, in that order. Selecting a sidebar row
swaps the single content host; it never constructs a second window. A future
section is appended to the registry and automatically gains a navigation row;
it does not modify window ownership, activation, layout, or menu commands.
This is the only extension interface added now. There is no generic schema,
plugin loader, or speculative settings DSL.

### App-owned preferences

`Settings` becomes the single API for app-owned persistent choices:

- `menubar.showsPercentage`;
- `popover.module.flow`;
- `popover.module.ring`;
- `popover.module.lanes`;
- `popover.module.history`.

It retains existing keys and defaults, adds typed module visibility accessors,
and emits `Settings.didChange` after effective changes. It does not post for an
idempotent write.

`PopoverContentViewController` stops keeping an independently writable source
of truth. It reloads visibility through `Settings` on `Settings.didChange`, then
reuses the existing `applyModuleVisibility()` path to update hidden state,
animations, and popover height. Both the quick menu and Settings window write
through the same API.

### System-backed settings

Launch at Login remains authoritative in `LoginItemController`; no UserDefaults
mirror is introduced. General refreshes it when Settings opens and maps its
existing states as follows:

- `enabled` / `notRegistered`: checked / unchecked and enabled;
- `checking`: disabled with a checking description;
- `unavailable`: disabled with a full-installer-required description;
- `readFailed`: disabled with a status-unavailable description.

The existing controller's coalesced serial worker, generation guards, and
readback behavior remain the only mutation path.

System battery icon visibility remains authoritative in Control Center through
`SystemBatteryIconController`. That controller gains a shared cached state and
one `didChange` notification posted only when the state actually changes, so
StatusItem, popover, and Settings observe one result. Refresh and mutation
continue through the existing shared helper worker. An unknown state is never
represented as unchecked.

Wattson's own menu-bar glyph style is an app-owned typed setting, independent
of Control Center visibility. It defaults to the existing Wattson mark and can
switch to a public macOS-style template battery glyph. The native style uses
static public battery levels, adds the bolt only for an actual charging state,
and falls back to a resolution-independent template drawing when a symbol is
unavailable on an older supported system.

## Data Flow

### App-owned toggle

`checkbox/menu item -> Settings typed setter -> UserDefaults -> Settings.didChange`

Consumers reload only the affected presentation. The menu-bar percentage
redraws through the existing StatusItem observer. Module changes reuse the
existing popover visibility/layout path and do no hidden rendering.

### Launch at Login

`window opens -> LoginItemController.refresh -> section state`

`checkbox -> checking/disabled -> setEnabled -> helper/launchd readback -> authoritative state`

The quick menu reads the same cached controller state on its next presentation.

### System battery icon

`window/popover opens -> SystemBatteryIconController.refresh -> shared cached state + notification`

`checkbox -> updating/disabled -> setHidden -> Control Center write/restart/readback -> shared cached state + notification`

Both surfaces restore the authoritative value from the notification.

## Error and Concurrency Behavior

- System-backed controls are disabled while reading or mutating.
- Closing the window does not cancel a helper request, but completions capture
  views weakly and update the shared controller state safely.
- An unavailable helper leaves relevant controls disabled and explains that the
  full installer is required.
- A read failure displays an unavailable state, not a false `off` value.
- A mutation failure restores the last authoritative state, presents one
  concise inline error, updates the affected switch's accessibility help, and
  posts exactly one high-priority accessibility announcement. Existing
  popover error behavior remains unchanged.
- Repeated clicks cannot enqueue duplicate mutations because the control is
  disabled and the existing controller also rejects in-flight updates.
- Opening Settings repeatedly coalesces reads through existing workers and
  never creates additional windows.
- No Settings code adds timers, display links, sampling requests, or background
  polling. Authoritative reads occur only on show and explicit mutation.

## Menu and Command Behavior

- The quick menu preserves module toggles, menu-bar percentage, launch at
  login, version, and quit.
- `Settings…` is added without removing those shortcuts.
- A minimal application menu owns the standard Command-Comma equivalent and a
  Quit command while Wattson is active.
- Both routes call the same idempotent presenter.
- Activation policy remains unchanged and is covered by a regression test.

## Verification Plan

Implementation follows test-first development. Each behavior is first observed
failing, then implemented minimally.

### Unit and contract tests

- Existing UserDefaults keys/defaults remain unchanged.
- Typed module access posts one change notification only for an effective
  change.
- Quick menu and Settings writes update the same module state.
- A live popover reloads module visibility and height on change.
- Section registry identifiers are unique and default order is General then
  Modules.
- The window is 792×794 points with a 232-point sidebar, General is initially
  selected, and selecting Modules swaps the content host without constructing
  another page/window instance.
- Geometry matches the authoritative measurements above within one point:
  54-point traffic-safe area, 96-point identity row, 56-point navigation rows,
  25-point horizontal content insets, 100-point General rows, 16-point grid
  gaps, 246.5×258-point cards, and 112×108-point preview regions.
- Sidebar selection is keyboard accessible and persists across close/reopen
  only within the current process.
- General renders exactly four rows; Modules renders exactly four cards in a
  2×2 grid; module preview glyphs remain static when hidden or visible.
- Window show-close-show preserves one `NSWindow` identity.
- Repeated show produces one Settings window.
- The window is nonrestorable and nonreleased. All three native traffic-light
  controls remain visible; equal min/max content sizes keep the artwork fixed.
- Command-Comma and quick-menu Settings call the same presenter once.
- Opening Settings closes the popover first.
- Launch-at-login and battery-icon states cover checking, unavailable, read
  failure, success, mutation failure, and stale completion.
- Test dependencies are injected closures/fakes; tests pass a nil frame
  autosave name and never mutate the installed helper or user preferences
  outside a temporary UserDefaults suite.
- Settings observers and window controller release without cycles.

The ordinary Python contract compiles and type-checks the real AppKit source
and exercises section/layout seams without showing an `NSWindow`. Tests that
actually show, key, close, or release windows run only when
`WATTSON_RUN_INTERACTION=1` is set in an interactive disposable GUI session.

### Real AppKit tests

- Open twice, close, and reopen; verify visibility, key-window behavior, and
  single-instance identity.
- Verify native and legacy material popovers close before Settings appears.
- Exercise keyboard navigation, Command-Comma, VoiceOver metadata, Reduce
  Motion, and Reduce Transparency.
- Toggle every app-owned row and verify immediate popover/menu-bar
  presentation with no stale state.
- Verify no animation or render activity after the Settings window closes.

### Compatibility and performance gates

- Full Swift and Python suites.
- ASan, TSan, and UBSan Swift tests.
- arm64 and x86_64 release builds with deployment target macOS 12.
- Existing default and forced-legacy interaction harnesses.
- Switching pages 1,000 times preserves the same two section-view identities
  and exactly one content-host child.
- After 150 warm-up controller cycles, 500 additional create/show/close/release cycles in
  the opt-in GUI harness release weak controller/window references, keep file
  descriptors within the warm baseline plus 2, and keep resident memory within
  8 MiB of the post-warm baseline.
- Source and runtime checks reject Settings-owned `Timer`, display-link,
  repeating-dispatch, layer-animation, sampling, or polling work.
- The later integration harness verifies closing Settings does not increase
  the already-closed popover's render count.

## Review and Release Gates

After implementation and local verification, at least three independent agents
perform read-only, defect-first reviews using the repository instructions and
`review-agent` criteria. Reviews cover:

1. Settings state consistency, asynchronous failure recovery, and concurrency;
2. AppKit window/menu lifecycle, accessibility, and performance;
3. macOS 12–26, arm64/x86_64, packaging, and regression compatibility.

Every evidence-backed finding is reproduced, fixed test-first, and re-reviewed.
Only after all three reviews return no actionable findings does the release
proceed through a new patch version, full packaging gates, exact local PKG
installation, post-install probes, and the approved Cody email workflow.
