# Wattson Settings Window Design

Date: 2026-08-13
Status: Approved design
Scope: Native macOS Settings window for existing Wattson controls

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
- Organize all seven existing persistent or system-backed choices into a clear
  single page.
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

The window is a standard titled, closable AppKit Settings window with one
fixed-content page. It has no minimize or zoom affordance because there is no
alternate useful size. It is centered only on first presentation, uses one
frame-autosave name to preserve a user-moved position across launches, does not
restore visibility, and never opens automatically at application launch.

Closing hides the window without terminating Wattson. Reopening, repeated
menu commands, and repeated Command-Comma actions all reuse the same window and
bring it forward.

### Content

The page uses native checkbox controls, system typography, standard group
spacing, and concise secondary descriptions. It has two vertically stacked
sections:

1. **General**
   - Show Battery Percentage in Menu Bar
   - Launch at Login
   - Hide System Battery Icon
2. **Modules**
   - Energy Flow
   - Ring Gauge
   - Power Lanes
   - Power History

The current version and Quit remain commands in the quick menu, not settings.

All controls expose explicit accessibility labels and help. Tab and full
keyboard access follow AppKit's native checkbox order. The design does not add
custom motion.

## Architecture

### Window ownership

`StatusItemController` remains the UI lifetime root and strongly owns one lazy
`SettingsWindowController`. `AppDelegate` and `main.swift` keep their current
roles. The controller creates one `NSWindow`, sets
`isReleasedWhenClosed = false` and `isRestorable = false`, and exposes one
idempotent `show(activateApp:)` operation. Tests can pass `activateApp: false`
to avoid stealing focus.

The presentation callback crosses the existing hierarchy:

`PopoverFooterView -> PopoverContentViewController -> PopoverController -> StatusItemController`

`PopoverController` closes the popover before invoking the Settings presenter.

### Section extension boundary

The window consumes an ordered collection of objects conforming to a narrow
`SettingsSectionController` protocol:

- stable identifier;
- user-facing title;
- an AppKit content view;
- `refresh()` for authoritative state when the window opens.

The default registry contains `GeneralSettingsSectionController` and
`ModuleSettingsSectionController`. A future section is appended to the
registry; it does not modify window ownership, activation, layout, or menu
commands. This is the only extension interface added now. There is no generic
schema, plugin loader, or speculative settings DSL.

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
- A mutation failure restores the last authoritative state and presents one
  concise inline error. Existing popover error behavior remains unchanged.
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
- Window show-close-show preserves one `NSWindow` identity.
- Repeated show produces one Settings window.
- The window is nonrestorable, nonreleased, nonminimizable, and nonzoomable.
- Command-Comma and quick-menu Settings call the same presenter once.
- Opening Settings closes the popover first.
- Launch-at-login and battery-icon states cover checking, unavailable, read
  failure, success, mutation failure, and stale completion.
- Test dependencies are injected closures/fakes; tests never mutate the
  installed helper or user preferences outside a temporary UserDefaults suite.
- Settings observers and window controller release without cycles.

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
- Settings show/close stress: stable FD count, bounded RSS plateau, one window,
  no timers, and no increase in closed-popover render count.

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
