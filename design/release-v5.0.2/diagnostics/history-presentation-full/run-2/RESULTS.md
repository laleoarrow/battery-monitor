# Full fixed-phase interaction result

Frozen commit: `35339ef0e764a2672a9aa2a6990d56b64894f005`. One owned VM run completed with owner exit 0.
Normal, legacy and legacy accessibility configurations passed 499, 497 and 491
assertions respectively, with zero failures. Retarget continuity, its natural
completion, later contraction and the independent never-paused completion
fixture all passed. Every variant also rejected all three injected animation
keys at the original one-second deadline.

All 61 recorded source digests match the frozen commit. The global application
runner matches the original release candidate; the original tolerance and
completion deadline remain unchanged. This run uses the fixed 0.1-second
fixture phase and continuous clock resume before natural completion.

Owner cleanup warning scan: 0. Separately, the final guest audit
passed after 37.402 seconds of preference-file
observation, the owned clone was deleted, original VM states were preserved,
and host-owned scratch has zero entries. The earlier retarget diagnostic's
owner exit 1 and four defaults-delete warnings remain preserved as failures.

See `verification-summary.json`, `full-results.json`, the three raw variant
logs, `guest-cleanup-audit.json` and `vm-cleanup-summary.json`. Earlier
non-History suite state was replayed in every variant. This local result does
not replace the hosted release gate or prove physical frame delivery/FPS.
