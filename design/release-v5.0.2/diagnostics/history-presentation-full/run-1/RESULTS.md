# Complete interaction result

Frozen commit: `26aac163f39be608c079b6b39a782e34892af4ba`. One owned VM run completed with owner exit 0.
The normal, legacy, and legacy accessibility variants passed 499, 497, and 491
assertions respectively, with zero failures. All three variants rejected the
infinite, two-second and retained `history.stroke` controls at the original
one-second deadline. No unexpected History timeout was recorded.

All recorded source digests match the committed snapshot. The global
`runApplication` implementation matches the original failed release candidate.
Production renderers and the original deadlines are unchanged.

Owner cleanup warning scan: 0. This is separate from the final
resource audit: guest checks passed after 37.732
seconds of preference-file observation, the owned clone was deleted, both
original VM states were preserved, and host-owned scratch has zero entries.
Earlier diagnostic cleanup warnings remain preserved in their own records;
this result does not retroactively clear them.

See `verification-summary.json`, `full-results.json`, all three raw variant
logs, `guest-cleanup-audit.json` and `vm-cleanup-summary.json`. The complete
non-History prefix was executed for every variant. These results do not prove
physical frame delivery or the final Core Animation root cause, and do not
replace the hosted release gate.
