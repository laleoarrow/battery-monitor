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
- After with macOS 26 selected: Glass × Light/Dark with percentage On, two
  additional captures to inspect the lower selected row against the surface.
- After with macOS 27 selected: Glass × Light/Dark × percentage Off/On, four
  captures of the embedded-percentage artwork.
- General and Modules: Glass × Light/Dark, four captures of the other consumers
  of the shared Settings glass surface.

Each frame has real view geometry, native image sizes, visible text/font sizes
and intrinsic text widths recorded alongside its PNG. NSTextField frame padding,
alignment rectangles, cell drawing/title rectangles and attributed text sizes
are recorded separately, so transparent native frame padding is not mistaken
for clipped text. Native button titles, fonts, cells, title/image rectangles
and default focus properties are recorded without using private KVC. Actual
glass corner radii are compared with a freshly constructed native glass view;
boxed controls record their matching radius separately. The fixture
uses environment-only accessibility overrides; system accessibility preferences
are never changed. The 26 VM then runs only `BatteryIcon27Tests` (nine tests)
and `MenuBarIconStyleSettingsTests` (five tests), with package caches in owned
scratch and an exact parent-owned preferences suite. The complete native
Settings contract runs once with `WATTSON_RUN_INTERACTION=1`. Its assertions cover persistence, keyboard,
focus, real preview bounds and in-place appearance refreshes.

Acceptance also requires matching production-source hashes before and after
execution, the actual contract completion marker, exact-suite cleanup, a
35-second guest preference observation, absent owned processes/registrations/
containers/mounts, deletion of the owned VM, and matching host canonical app,
helper, daemon, PID and app setting hashes. Logs and screenshots are final
evidence; runnable bundles, source/build scratch and shares are disposable.

`scripts/verify_display_settings.sh NEW_EVIDENCE_DIRECTORY_UNDER_PROJECT` is the
portable GUI-only entrypoint for an isolated hosted runner. It preserves the
same fixture and capture driver and runs the 34 after-change captures and the
full eight-test native Settings contract, without the four original baseline
frames or the separately executed focused Swift tests.
It requires an Aqua session, no canonical Wattson installation, clean tracked
inputs and a new caller-owned evidence directory. Its app bundle, unique
preferences domain, container and build/process resources use the same shared
cleanup helpers. Successful exit requires actual capture markers, all 34 PNG
and geometry files, the actual native completion marker and eight-test result,
source-byte verification, all 21 original-size previews,
correct external-versus-embedded percentage presentation and shared glass
corners matching that OS's fresh native view. The local VM flow retains the
four original baseline captures, for 38 frames total, and its full contract and
canonical-preservation gates.
