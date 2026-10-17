# Normal slow drag, owned guest fixture

This is test infrastructure. It observes an unchanged frozen production renderer and forwards each intercepted native callback to its original implementation exactly once. It does not generate input or call production reorder methods. Both production DEBUG preflight closures must remain nil, verified by read-only reflection before observation starts and in every state snapshot.

The frozen 5d5c896b7a15 / 4.3.12 source archive has SHA-256 `8aa52b90ec8f2e7f93e2ccc7ebc2fd9ab7e89217a95bfd93edccbb3e90156ca3`; its 52 Core/MenuBar/Popover Swift files match installed production commit 5d5c896b7a1531ce4f9783fa467ff8c8eb62b82e byte for byte. Original v6 tools SHA-256 is `89343e38e8ce2e0327bef3324d6a0d308dbfa1a99368409454c190dbe913c9a5`. The native callback interceptor and capture bridge remain byte-identical to that original tools archive. The preference finalizer only adapts its exact owned UUID prefix to `com.leoarrow.wattson.modules-slow.`. The adapted overlay hash and entry command are in `provenance.json`.

Only run inside the newly owned `Wattson-NormalSlowDrag-20261017` VM. Mount the parent `.build/normal-slow-drag.noindex` folder as share `normaldrag`. Before input, independently verify the expected VM hardware UUID, fixture PID/bundle/window, and active guest application. Guest VNC input requires explicit user authorization before posting any event; no TCC or screen-recording permissions are changed by this fixture. CGEvent preflight found post-event access unavailable without attempting input; this is retained as a backend limitation, not a product failure. VNC uses the guest's existing Apple ScreenSharing service; this fixture does not create a listener or alter host UI.

The stage entry compiles/signs the app and writes:

`/Volumes/My Shared Files/normaldrag/normal-slow-drag-v2/drag/manual-classic-0/compiled-ready.json`

It then waits up to 1800 seconds for a regular `start-manual` marker in that directory. Creating `cancel-before-start` exits without starting the GUI. The app's separate 600-second deadline begins only when the app starts. The stage owns its source extraction, compiled app, process group, unique preference suites, and newly created guest project/container paths. Shared lifecycle cleanup runs after success, failure, timeout, and catchable signals. Result files in the caller-owned shared directory remain available for review.

`state.json` contains `inputTargets.drop` and `.outside`; each has hardwareUUID, pid, bundleID, windowID, caseName, source/target `{x,y}`, duration 1.5, holdBefore 0.3, and holdAfter 0.5. Coordinates are logical CG global screen coordinates with a top-left origin. `cgWindow` and `inputGeometry` expose independent owned-window/display bounds for the input driver's checks. These coordinates are observations, not an instruction to bypass driver safety checks.

For each of Classic, Standard, and Clear, use unique cases for a held drop and an outside release. Atomically write `reset.json` with `{"case":"classic-slow-drop","style":"classic","reduceMotion":false}` and wait for `lastCommand.result == "applied"`, the matching case/style, clear feedback, and button-up state before using its targets. Reset never changes order during an active gesture. It writes only the owned fixture's preference suite.

After input, wait for the genuine native endedAt callback, button-up state, alpha 1, and clear drag state. Freeze `state.json` and `history.jsonl` into an exclusive per-case evidence folder before another reset. Evaluate with:

```sh
python3 evaluate-normal-slow-drag.py FROZEN_CASE_DIRECTORY --case classic-slow-drop --kind drop
```

Use `--kind outside` for the cancellation case. The evaluator requires the exact four native callback phases for one session/source, original forwarding, left-button down at native start, more than one second from native willBegin to endedAt, active-row feedback, final alpha/state restoration, retained rows/window/scroll/visibility, expected saved/display order, exact write/notification counts, and nil production preflight overrides. Missing native callbacks yield unverified (78), not a pass. Expected successful drop moves `flow` after `runtime` with one saved write; outside release preserves default order with zero writes.

Optional `capture.json` with `{"name":"classic-slow-drop-final"}` captures only the owned Settings window; no full guest or host desktop screenshot is taken. Creating `done` ends the fixture and starts cleanup. Neither a done marker, `complete.json`, nor a zero session exit is itself a test verdict.

These tests establish native drag behavior under authorized guest VNC input. They do not establish human mouse input, host-desktop interaction, FPS, or subjective smoothness. No VM, GUI app, or input was started during preparation; only Swift syntax parsing, shell syntax, Python AST, immutable input hashes, and production-byte identity were checked.

The independent pure-data evaluator self-test completed 28/28 checks, including refusal of missing native callbacks, short or exactly-one-second duration, incorrect button masks, non-nil test seams, mismatched sessions/sources, and extra writes. Its synthetic positive controls are labelled non-product evidence. Two historical v6 native records were read-only reviewed and were ineligible for this new slow-drag gate. See `evaluator-mutation-results.json` and `historical-native-eligibility.json`.

The prior cfca fixture preparation, e627 archive, and original v6 archive are preserved as historical, unexecuted inputs. The current stage uses the distinct `normal-slow-drag-v2-tools.tar.gz`; do not run the old e627 stage or old cfca overlay for this installed 4.3.12 gate.
