# Ring Gauge metric selection

The production Ring Gauge keeps its four default readings and offers fourteen
metrics through Settings > Modules > Ring Gauge > Metrics. At most four can be
selected. Selecting a fifth removes the oldest selection and appends the new
one; the user's selection order is the reading order.
Battery and adapter voltage/current have separate captions and source fields.
Battery current is signed: positive charges the battery and negative discharges
it. Missing readings use an em dash (`—`); unplugged adapter voltage/current
remain unavailable instead of inheriting battery measurements.
The gauge's section remains 138 points tall; selecting none retains the charge
ring without changing the popover height.

Run the hidden production-renderer verification from the project root:

```sh
./scripts/verify_ring_metrics.sh design/ring-metrics/production-captures
```

The runner creates an invocation-owned `.build/ring-metrics-capture.noindex`
bundle with a unique identifier, includes all three in-app logo resources,
and uses `scripts/lib/local_cleanup.sh` for process, bundle registration,
defaults, container and scratch cleanup. The explicit output directory is
caller-owned and preserved. It launches with prohibited activation policy;
it never orders a window front or opens a native menu. No live telemetry or
privileged Settings operation is used, and Settings preferences live in memory.

## Production capture evidence

The [machine-readable evidence](production-captures/evidence.json) records
46 cases and 658 assertions with no failures:

- Six fixture states (charging, full, on battery, mixed supply, low battery,
  and Low Power), in Light and Dark, with default, electrical, and
  time/health/capacity groups of four: 36 cases.
- Charging fixtures in both themes with a four-metric power/device group:
  two cases.
- Empty metric selection in both themes: two cases.
- Actual Settings Modules windows with default, electrical and empty selections in
  both themes: six cases. Actual native menu-item titles and checked states
  are recorded without opening the menu.

Each case retains the full content image and a section or row crop rendered
from its production root so transparent section views retain their background.
Assertions cover metric selection, reading presence, text and frame fit,
non-overlap, fixed section and content heights, adjacent
sections, footer containment, disabled animation and explicit Battery/Adapter
electrical captions. Final checks confirm unchanged foreground application,
production app/helper/preferences hashes, and cleared in-memory preferences.
Input source and executable hashes are in
[capture-inputs.sha256](production-captures/capture-inputs.sha256).
The [post-run cleanup audit](production-captures/cleanup-audit.json) checks
removal of the invocation's bundle, workspace, preference file, containers,
LaunchServices and Spotlight registration, and confirms every captured
selection contains at most four metrics while all fourteen choices are covered.

Representative images:

- [Dark default](production-captures/ring-metrics-dark-charging-default-section.png)
- [Dark electrical metrics](production-captures/ring-metrics-dark-charging-electrical-section.png)
- [Light fully charged health metrics](production-captures/ring-metrics-light-full-health-section.png)
- [Empty selection in the full popover](production-captures/ring-metrics-dark-charging-none.png)
- [Dark Settings](production-captures/ring-metrics-settings-dark-default.png)
- [Light Settings](production-captures/ring-metrics-settings-light-default.png)

These are real AppKit bitmap layout captures, not WindowServer-composited
Liquid Glass screenshots. Native menu interaction, pointer/keyboard use and
VoiceOver are outside this capture's scope. All sensor values are fixtures.

The final source passed all 655 Swift tests and 91 focused Python checks across
the popover, sampler, status item and Settings contracts. Native menu target/action
tests cover fifth/sixth-choice replacement, persistence and cross-window checks.
The footer uses the process's cached/default energy mode; the Low Power fixture
exercises the snapshot presentation without changing the Mac's hardware mode.
