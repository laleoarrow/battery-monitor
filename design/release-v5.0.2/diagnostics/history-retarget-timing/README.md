# Retarget timing comparison

This isolated diagnostic extracts the complete History section from frozen
commit `26aac163f39be608c079b6b39a782e34892af4ba`, including its preceding local
lifecycle, subsequent contraction, negative controls and independent fresh
completion fixture. Earlier non-History suite sections are not replayed. The
production sources, formal harness, global application runner, 0.5-point
tolerance and original one-second completion waits remain unchanged.

One binary runs four cases in one owned disposable GUI VM: original timing;
original timing with an extra 0.20-second wait; fixed fixture time; fixed fixture
time with the same extra wait. The extra wait is inserted only after the
intermediate-frame/width checks, immediately before reading `beforeStrokePath`.
Every original assertion and its exit result is preserved. The owner can report
successful evidence collection while the expected original delayed case still
has exit 1; the raw case statuses remain explicit.

The candidate pauses the root fixture clock before the first 180 W update,
advances its local time exactly 0.1 seconds before the original composition
wait, and keeps that phase during the 300 W retarget and continuity checks.
It then restores speed 1 using a begin-time offset that preserves local time,
before the unchanged natural-completion wait. It neither removes nor re-adds
the running animation keys to achieve completion. Later original fixture
cancellation and injected-key controls remain as originally written.

Recording includes projected before/after coordinates, dx/dy, actual old/new
path anchors, both m22/m41 transforms, the distance from 350/250 and each
original predicate, sample/update elapsed times, animation begin/duration,
before/after clock recovery, and visibility. These sequential layer-property
observations do not establish physical frame delivery or FPS. The hosted CI
log suggested a timing-sensitive guard; only the new measured comparison can
establish which subcondition fails locally.

The managed VM and guest owners reuse the existing lifecycle helpers, keep
scratch in owned `.noindex` directories, preserve every log and status, audit
delayed preferences and remove their clone. Owner cleanup errors remain
separate from final resource absence. No host desktop UI is used.
