# Process Activity

The user-requested Pro redesign replaces the rejected thin relative bars with
a fixed scale, visible gradients and concrete CPU/wakeup readings. The new
native previews below are implementation review evidence; user approval is not
implied. The [Pro design specification](pro-design.md) records the direction
and the verified ChatGPT Pro consultation.

Development source based on Wattson 4.3.17. The canonical installed app and
helper are preserved; this review does not publish or install a release.

The independent module defaults to three processes. Settings > Modules
supports 1–10, visibility and the existing module ordering controls. Its icon
uses three horizontal bars, descending in length, with neutral outlines and
blue gradients. Process rows share Wattson's transparent surface and separators.

The fixed **0–100 pts** scale prevents an idle first-ranked process from filling
its bar. Each row shows its real activity points and the underlying CPU percent
and idle wakeups per second. Every twelve-point filled bar has its own complete
horizontal gradient from pale to deep blue. Rows use the same colors, while
length and the numeric **Activity Score** convey activity. A chevron at the
bar's end marks scores above 100 without hiding the
numeric value. Zero remains empty and tiny values are not inflated. A small
native information button explains Wattson's CPU-and-wakeup activity indicator
and the fixed scale; formula lineage is retained in developer documentation.
These values are not watts or shares of measured battery power. See
[the data model and formula](../../docs/top-energy-processes.md).

## Native visual evidence

These images come from real AppKit renderers in an owned ARM GUI VM. Process
names and scores are fixed validation fixtures. The module-only images show
Classic views in an actual window with an opaque background; they are not a
demonstration of Liquid Glass translucency.

| Dark | Light |
| --- | --- |
| ![Horizontal blue gradient, dark](horizontal-gradient-module-dark.png) | ![Horizontal blue gradient, light](horizontal-gradient-module-light.png) |

[Supplied style reference](reference-style.png) ·
[Settings quantity control and horizontal icon](pro-settings-light.png)

[Earlier Glass host layout](pro-glass-dark-bottom.png) ·
[Earlier overflow](pro-overflow-dark.png) · [Earlier tiny and zero values](pro-tiny-light.png) ·
[Current information popover](horizontal-gradient-help-dark.png)

The Modules list scrolls below its fixed subtitle and Restore button. Native
coordinate assertions cover focusing the quantity control at the bottom without
overlapping that header or clipping the row. Width checks use the native clip
view's available width, including the space reserved by legacy scrollbars.

The preceding Pro native matrix has 126 captures and 5,134 assertions with zero
failures. All 571 Swift tests and the universal macOS 12 build pass. One real
root-helper read returns the CPU/wakeup components consistently with the
activity formula. High-contrast colors are covered by component tests.
[Pro verification metadata](pro-verification.json) records the source/image hashes,
Python Settings-test correction, fixture limitations and build scope.

The preceding per-score blue-tint interpretation passed nine focused view tests,
two native captures with 102
assertions, and a fresh universal macOS 12 build. The test preference domain
stays absent through 35 seconds of filesystem observation; all ten resource
checks pass and the disposable VM has been removed, preserving the original VMs.
[Its verification](blue-scale-review.json) preserves those results and hashes.
The user subsequently clarified that the gradient belongs inside each bar;
the current previews above show that horizontal treatment and the final
Activity Score wording. Earlier [per-score dark](blue-scale-module-dark.png),
[per-score light](blue-scale-module-light.png), [uniform-blue dark](pro-module-dark.png)
and [uniform-blue light](pro-module-light.png) images remain historical evidence.
The corrected horizontal gradient and final Activity Score wording pass nine
focused view tests and three real-window captures with 107 assertions. The
information text fits its actual native text cell without clipping.
[Current verification](verification.json) records this final source and evidence.

## Earlier rejected candidate

The following images preserve the user's rejected thin-bar candidate. Its
highest-process normalization and thin fills are not the current design.

[Rejected dark module](module-dark.png) ·
[Rejected light module](module-light.png) ·
[Earlier Settings](settings-light.png)

## Reproduce

```sh
swift test
python3 -B -m unittest discover -s tests -v
bash scripts/build_release.sh
```

The explicit GUI entrypoints run in the disposable test VM:

```sh
WATTSON_RUN_GUI_TESTS=1 bash scripts/verify_top_processes.sh OUTPUT_DIRECTORY
WATTSON_RUN_GUI_TESTS=1 bash scripts/verify_top_processes.sh --module-only OUTPUT_DIRECTORY
bash scripts/verify_interaction.sh
bash scripts/verify_animation_stress.sh
```

The GUI scripts use the existing lifecycle helpers for exact test preference
domains, temporary bundles, child processes and app registrations. They do not
replace the canonical app or modify production user preferences.
