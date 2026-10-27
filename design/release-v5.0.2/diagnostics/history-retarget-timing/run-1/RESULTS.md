# Retarget timing result

The single four-case comparison reproduced the failure without changing the
original condition or tolerance. Baseline passed. With the 0.20-second delay,
its only failed assertion was retarget continuity's composite guard: dx and dy
were both zero, while the remaining scale distance from 350/250 was 0.098398,
below the required 0.5. The sample arrived about 0.315135 seconds after expansion.

Both fixed-clock cases passed the entire retained History section. Their
remaining scale distance was 4.121298, dx was zero and dy was approximately
7.1e-15, even when wall time reached 0.314387 seconds. Local animation phase was
kept at 0.1 seconds. Continuous clock restoration preserved the active retarget
animation; subsequent original one-second completion, contraction, negative
controls and the independent never-paused completion fixture all passed.

This is local controlled reproduction. The hosted CI log did not record these
exact subcondition values, and the earlier non-History suite was not replayed.
The observations do not prove frame delivery or FPS.

**Owner cleanup failed (exit 1): four defaults-delete warnings remain in
`probe-owner.log`.** The later resource audit passed after 37.517 seconds, the
owned clone was deleted, original VM states were preserved and host scratch was
empty. Those final observations do not erase the owner failures.

See `verification-summary.json`, `comparison.json`, each original case JSON/log
and exit-code file, `guest-cleanup-audit.json` and `vm-cleanup-summary.json`.
No diagnostic rerun was performed.
