# Pro review input

Conversation: [Wattson History 坐标缩放复核](https://chatgpt.com/c/6ad23678-eaf8-83ee-b2f8-2d98419b6742).

The first performance review advised emitting projected stroke controls directly,
reusing the final target path, and using two path endpoints only when the actual
captured viewport scale is strictly one. Other scales retain the existing
keyframes. Matching run boundaries, time intervals, raw anchors, timing and
actual presentation capture remain required.

The follow-up reply (2m42s, read in SunBrowser on 2026-10-17) reviewed the supplied
implementation and ABBA summary. It found no new concrete History installation
blocker from that description, subject to the existing integration/native/manual
gates. It supported reporting each scenario separately: three measured medians
improved, expansion increased 6.8% (23.4 µs), and no-op was unchanged. That increase
alone did not establish visible interaction regression or justify speculative
restructuring. It explicitly rejected an averaged overall speedup, treating
correlated no-op calls as independent, or inferring FPS, CPU time or energy.

This is reviewer advice based on the supplied description, not an independent
execution or acceptance result. The follow-up preceded final construction counts
and native acceptance; those actual measurements are retained separately.
