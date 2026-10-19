# Wattson 4.3.23 release

This maintenance release preserves existing UI, features, settings, activity-score
formula and helper permissions. It reduces redundant action-image refreshes,
preserves process keyboard focus across ranking updates, bounds an overdue
worker idle-poll edge case, and makes an existing feedback capture explicit.
Test cleanup and universal architecture verification support the current tools.

Runtime source and macOS27 evidence are recorded in
[the performance review](../performance-hardening-20261019/README.md).
Published [v4.3.23](https://github.com/laleoarrow/battery-monitor/releases/tag/v4.3.23)
from frozen source `23185f299ce61b8e373ebf5115b461ad2aa01226`.
Exact-source Headless CI, the candidate build and five installation jobs,
exact-tap CI, public Intel/Apple-silicon Homebrew lifecycles, and Pages all passed.
Anonymous downloads match the accepted candidate byte for byte. The canonical
Mac now has the exact public PKG App/helper/daemon and receipt at 4.3.23;
16 stored settings remained unchanged after normal launch. The user confirmed
the popup and Process Activity display normally. CUA itself could not read the
menu-bar popup, so that visual confirmation is attributed to the user.

See [final release gates](publication/root-final-gates.json),
[installation verification](installation/local-install-verified.json),
[Git cleanup](cleanup/git-summary.json), and
[artifact cleanup](cleanup/artifact-summary.json). Local and remote feature
branches and old worktrees were removed after verified recovery archives were
made. Historical tags, failed CI audit records, unique installers and design
sources were preserved. Only main remains; publication records are committed
after the frozen-source release gates. No new UI or measured whole-app
speed/energy claim is made.

Community distribution: App/helper ad-hoc, unsigned PKG/DMG, not notarized.
No release email was sent in this task.
