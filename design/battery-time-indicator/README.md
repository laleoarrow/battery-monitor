# Battery time source indicator — design review

Waiting for the user's visual review (2026-10-27). The user requested the design
before continuing implementation. No installed app or release was updated.
The Swift changes are a draft prototype, not accepted product work.

`planet-source-preview.html` compares four states, light/dark appearance and two
placements: beside the caption or on the clock corner. It shows the actual size
and a magnified detail. This browser mockup is not native-rendering evidence.
The user's latest change sets the orbit's initial wait to **2 seconds**. Apply
that approved timing to the draft Swift prototype if implementation proceeds;
the prototype still has its initial 3-second wait and caption-adjacent placement.

The preview's state/theme controls, moving orbit and narrow-width fit were
checked before the two-second timing edit. `design-preview.png` records that
earlier light-appearance preview.

Prototype verification so far:

- 734 Swift tests pass; the owned runner removed all 183 registered preference
  domains (`remaining=0`). The initial direction-specific help-text failure was
  corrected before the passing run.
- Python module contracts: 26/27 pass. The remaining static check selects the
  first `setPresentationActive` in the file, now the runtime forwarding method,
  rather than the content controller. Scope that check to the content controller
  if implementation proceeds; keep the footer's existing behavior.
- Native GUI verification was interrupted for design-first review and remains
  incomplete. The owned VM clone was removed; both pre-existing VMs retained
  their states. The final normal-glow capture runner has not been run.
- A separate read-only review found no blocking status or lifecycle defect.

After visual approval, apply the selected placement and timing, finish the
Python check and native six-state/animation validation. Release work remains
subject to the project workflow and the user's authorized scope.
