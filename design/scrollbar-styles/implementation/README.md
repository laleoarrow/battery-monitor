# Native scrollbar implementation — 2026-10-31

The final user instruction sets **Flow as the default**. Settings → General →
Appearance → Scrollbar now offers Hidden, Simple and Flow. The right-side slot,
existing body layout and instrument renderers remain unchanged by this patch.
Simple delegates its gray drawing and interaction to AppKit. Flow keeps five
unevenly spaced white points inside a 6pt theme-gradient capsule; they travel
downward and reset only while transparent.

One native scroller instance retains the original gutter across all preferences.
The hidden native artwork also clamps its alpha to zero because AppKit caches
overlay parts independently of `drawKnob()`. The independent Flow control uses
native scroller drag tracking inside that same right-hand slot. Wheel events go
to the original scroll view. The accessibility relation returns the active
control, or nil for Hidden. No sampling timer or body drawing was added.

## Accepted evidence

- `swift-focused-final.log`: 9 focused Swift tests pass, including saved/default
  settings, real Settings selector actions, geometry/offset preservation for
  both native scroller modes, scroll endpoints, accessibility routing, clipping,
  palette, animation phases and teardown. Registered preference domains: 5;
  remaining after the owner exited: 0.
- `triage-python-focused.log`: 55 Settings/StatusItem contract tests pass after
  updating the two existing contracts for the new preference and keyboard row.
- `native-clean/scrollbar/evidence.json`: 1,517 assertions, 0 failures. The 72
  geometry cases cover six battery states, Light/Dark, overlay/legacy and all
  three preferences. Native dragging reaches both ends; wheel scrolling works
  in all modes; the Settings selector is saved and keyboard-accessible.
- The same native run records 107 live Core Animation frames over more than five
  seconds: 523 downward steps, 7 transparent resets, uneven spacing in all 107
  frames, no visible upward movement or clipping failure. Animation begin times
  remain stable; Reduce Motion and closing remove all Flow animations.
- `native-clean/scrollbar/switch-{light,dark}-{simple,hidden,flow}.png` were
  visually reviewed: gray Simple, completely blank Hidden, theme-gradient Flow,
  with the same body content and right-side position. All body captures are
  720×480 px (360×240 pt); Settings captures are 1600×1040 px.
- `native/captures/evidence.json`: the earlier production-renderer matrix passed
  6,926 assertions across six battery states, Light/Dark, real Classic/Glass
  hosts, full layouts and Settings. This predates the native-instance/cache
  fixes. The final six-state component window run above verifies those fixes;
  it does not pretend to be a new Classic/Glass host matrix.

`verification.json` summarizes the accepted records and source checks.
`native-clean/scrollbar/capture-inputs.sha256` and the frozen source archive hash
identify the actual GUI input. The shared workspace also contained independent
full-charge-indicator changes during verification; those are not part of the
scrollbar patch and are not attributed to it.

## Broader regression limits

The full Swift sweep ran 748 tests and recorded four failed assertions in two
tests. Both reproduced alone without running the new Settings tests:

- The parallel full-charge change updated runtime help text while its older
  assertion still expected charging wording for `.full`.
- The existing mode-selector fixture measured a 31pt view against the native
  control's 30pt design height, producing three 15 versus 15.5 radius failures.

See `swift-tests.log` and `triage-focused.log`. This task did not change either
product component to make those assertions pass. The full Python sweep ran 653
tests with four expected opt-in skips; its two outdated setting contracts were
fixed and their 55-test subset then passed. See `python-tests.log` and the
focused log above. These records are not a claim that every full-suite test
passed on the final shared working tree.

## Diagnostic iterations and cleanup

Earlier `native-*` directories retain failure diagnostics, not acceptance:
replacing native scroller instances reset AppKit's style; the fixture initially
sampled before layout and later exposed a collapsed 1pt window; native cached
gray artwork remained after hiding; an absolute frame-count threshold was
inappropriate for variable VM sampling. The final harness establishes a real
240pt window, settles layout, refuses collapsed captures, records actual
animation samples and verifies invisible resets directly.

Each invocation used the shared lifecycle owner. Every owned VM clone was
stopped/deleted and every guest audit passed, including delayed preference
writes, app registrations, containers, scratch and child processes. Two early
host inventory checks reported a mismatch because an unrelated concurrent
test clone disappeared between their before/after snapshots; their own clones
were removed and the two fixed TestLab VMs retained their states. The final
accepted run's complete guest and host cleanup checks passed, including
preservation of the concurrent clone present during that run. Final
evidence is retained here intentionally. No canonical App, helper, production
preferences or user browser profile was changed.

Reproduce only the scrollbar GUI check with:

```sh
WATTSON_SCROLLBAR_ONLY=1 bash scripts/verify_process_whitelist_vm.sh NEW_OUTPUT_DIRECTORY
```

The default VM entrypoint still runs the broader existing matrices and native
interaction checks before this probe. This source implementation has not been
packaged, installed or published as a new release.
