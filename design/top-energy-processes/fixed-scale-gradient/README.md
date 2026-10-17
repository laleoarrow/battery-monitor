# Selected fixed-scale gradient and compact view

The user selected option A from the [native gradient comparison](../gradient-comparison/README.md).
The production renderer now places the pale-to-deep blue gradient across the
complete 0–100 scale and reveals only the prefix through the current score.
At 8.1 only the pale first 8.1% is visible. Zero is empty; scores over 100 keep
their real number and overflow mark. High contrast retains solid system blue.

Settings > Modules > Process Activity includes **Compact view**, off by default.
It hides the CPU/idle-wakeup line and reduces each row from 44 to 28 points.
With the default three processes the section changes from 168 to 120 points.
The setting persists while the module is disabled. Toggling it updates the
existing view and retains readings, counts, scale, tooltips and accessibility
details. It does not request another sample or change the helper protocol.

The module remains **Process Activity**, with **Activity Score** as its metric
and its existing information popover explaining the CPU and idle-wakeup inputs.
No per-process watt measurement or direct macOS `top` data source is claimed.

## Native previews

| Detailed, dark | Detailed, light |
| --- | --- |
| ![Detailed dark](module-dark.png) | ![Detailed light](module-light.png) |

| Compact, dark | Compact, light |
| --- | --- |
| ![Compact dark](compact-module-dark.png) | ![Compact light](compact-module-light.png) |

[Settings switch](settings-compact-light.png)

These are actual production AppKit renderers captured in a disposable ARM GUI
VM. Process names, scores and battery states are deterministic fixtures;
screenshots do not verify measured process power or physical battery telemetry.
The development change does not install or publish a release.

## Verification

The final native runs passed 10,932 assertions across 154 captures: 130 in the
full production matrix, 12 detailed/compact captures at counts 1/3/10 in light
and dark, and 12 matching high-contrast captures. The matrix covers charging,
full, on-battery, mixed supply, low battery and Low Power states, retained
Classic/Glass hosts, overflow and tiny readings, Settings and information
popover lifetimes. High contrast intentionally uses solid blue while retaining
the same fixed-scale mask geometry.

The targeted local checks passed 35 Swift tests and 55 Python contract tests.
The universal macOS 12 build passed for arm64 and x86_64 after the final keyboard
fix. The first Settings-window run caught a disabled-control keyboard-loop
regression; filtering was narrowed to the new compact control and all eight
window checks then passed. See [verification.json](verification.json) for input
hashes, the final native results and cleanup evidence.

Each native run passed a separate 35-second filesystem-only preference
observation. All ten resource checks passed, the owned VM was deleted, and
the original test VMs remained stopped. The canonical installation was untouched.

## Reproduce

Run the real-window checks inside a disposable macOS GUI VM:

```sh
WATTSON_RUN_GUI_TESTS=1 bash scripts/verify_top_processes.sh OUTPUT_DIRECTORY
WATTSON_RUN_GUI_TESTS=1 bash scripts/verify_top_processes.sh --compact-only OUTPUT_DIRECTORY
WATTSON_FORCE_INCREASE_CONTRAST=1 WATTSON_RUN_GUI_TESTS=1 bash scripts/verify_top_processes.sh --compact-only HIGH_CONTRAST_OUTPUT_DIRECTORY
```

The scripts own and clean their scratch, app registrations, preferences and
processes. The surrounding owned session creates and deletes the temporary VM.
