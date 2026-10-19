# Display production-renderer verification

`run-owned.sh FROZEN_COMMIT NEW_ABSOLUTE_EVIDENCE_DIRECTORY_UNDER_PROJECT`
archives the approved source and the pre-change `b079f29` renderer. It clones
only its uniquely named VM from the stopped `macOS-TestLab-Base`, shares the
archives read-only, and deletes that owned clone and source share on exit.
The two existing TestLab VMs and the canonical installed Wattson are preserved.

The exact same `tests/visual/capture_display_settings.swift` fixture compiles
against both archived production `Core`, `MenuBar`, and `Popover` source trees.
It instantiates the shipping `SettingsWindowController`, injects in-memory
settings and simulated system dependencies, and displays its unchanged
720 × 520 point window. No application delegate, sampling, helper request,
login-item operation, or persistent setting is used by the capture fixture.
The fixture app is ad hoc signed without a sandbox; the separate contract
harness retains its existing own application and preferences isolation.

The fixture uses ScreenCaptureKit `SCShareableContent.currentProcess` to select
only its own exact NSWindow ID, followed by `SCScreenshotManager.captureImage`.
The macOS SDK documents this enumeration as available without TCC user consent.
These are actual WindowServer compositor captures, including the real Glass
surface, rather than bitmap approximations. The expected set is:

- Before: Classic/Glass × Light/Dark with percentage On, four captures.
- After: Classic/Glass × Light/Dark × percentage Off/On, eight captures.
- After with forced Increase Contrast: the same eight captures.
- After with forced Reduce Transparency: the same eight captures.

Each frame has real view geometry, native image sizes, visible text/font sizes
and intrinsic text widths recorded alongside its PNG. The unmodified fixture
uses environment-only accessibility overrides; system accessibility preferences
are never changed. The complete native Settings contract then runs once with
`WATTSON_RUN_INTERACTION=1`. Its own assertions cover persistence, keyboard,
focus, real preview bounds and in-place appearance refreshes.

Acceptance also requires matching production-source hashes before and after
execution, the actual contract completion marker, exact-suite cleanup, a
35-second guest preference observation, absent owned processes/registrations/
containers/mounts, deletion of the owned VM, and matching host canonical app,
helper, daemon, PID and app setting hashes. Logs and screenshots are final
evidence; runnable bundles, source/build scratch and shares are disposable.
