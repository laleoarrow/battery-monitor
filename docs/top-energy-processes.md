# Process Activity

The popover's **Process Activity** module ranks recent process activity.
Settings > Modules provides its visibility switch, reorder handle, and
**Processes shown** choice (1–10, default 3). Existing saved module orders keep
their positions and append the new module. The list shares Wattson's transparent
surface, inset separators and semantic colors. Gradient bars and their outlines
follow the App's existing main-chart palette.

## Reading the values

The bars use a fixed **0–100 Activity Score** scale. An idle process therefore keeps a
short or empty bar even when it ranks first. Scores above 100 retain their real
numeric value, with a full bar and an overflow mark. The scale stays the same
when the ranking or the configured process count changes.

Each complete 0–100 track has a horizontal gradient from pale on the left to
deep on the right within the same color family. The score reveals only that portion of the gradient:
8.1 reveals the pale first 8.1%, while 100 reveals the full gradient. Rows share
the same colors and scale. Above 100 the full bar retains its overflow mark and
real numeric value. High contrast uses the same App color as an opaque solid
fill with a label-color outline.

The palette matches Power History and the power lanes: green while charging,
blue while plugged in without charging or on mixed supply, and neutral on
battery. Low battery and Low Power retain the existing main-chart palette;
the activity score does not introduce a separate severity color. Changes apply
immediately even when the process readings are unchanged. Light/dark appearance
refreshes resolve the adaptive colors again, without adding timers or sampling.

Settings > Modules > Process Activity also provides **Compact view**, a small
Off/On selector matching Processes shown. It defaults to Off. Enabling it hides
the CPU and idle-wakeup line and reduces each row
from 44 to 28 points. Names, scores and bar lengths remain the same; the inputs
remain available in tooltips and accessibility descriptions. The choice persists
when the module is hidden and updates an open popover without resampling.

Hovering a row shows only its full name/PID and one compact line of rounded
score, CPU and wakeup values. The information button's tooltip is **About
Activity Score**; click it for the full explanation. Hover text never includes
the scoring explanation or raw floating-point precision.

Each row shows its **Activity Score** and the two inputs: **CPU %** and **Idle
wakeups /s**. The information control explains their meaning. CPU is measured
per logical core: 100% means one fully occupied core, and multicore work can
exceed 100%. Platform idle wakeups count interruptions of platform idle time,
not all process wakeups. Neither component measures per-process electrical
power.

Wattson independently samples CPU time and platform idle wakeups through
`libproc`, then calculates Activity Score. The user-facing explanation is:

> Activity Score combines CPU usage and idle wakeups. Higher scores indicate
> greater process activity, not measured power consumption.

The information control also explains the fixed scale, overflow mark and
one-logical-core CPU convention. Formula provenance stays in developer
documentation and source comments. The score does not represent watts,
battery-power share or Activity Monitor's private Energy Impact calculation.

For a process present in two snapshots one second apart:

```
score = 100 × (Δuser CPU ns + Δsystem CPU ns + 500,000 × Δplatform idle wakeups)
              / Δmonotonic elapsed ns

cpuPercent = 100 × (Δuser CPU ns + Δsystem CPU ns) / Δmonotonic elapsed ns
idleWakeupsPerSecond = Δplatform idle wakeups / Δmonotonic elapsed seconds
score = cpuPercent + 0.05 × idleWakeupsPerSecond
```

The helper returns both components from the same snapshots.

The native reader uses `proc_listallpids`, `proc_pid_rusage(RUSAGE_INFO_V0)` and
`proc_name`, converting CPU Mach ticks with the host's timebase before applying
the formula. Start timestamps must match; exited processes, PID reuse,
unreadable counters and counter regressions are excluded. It resolves names
only for the highest ranked candidates, bounds response size and process count,
and never reads command-line arguments or process memory. This is an interval
ranking: it does not aggregate an application's child processes or attribute
GPU, display or whole-machine power to an application.

The formula references Apple's published `top` POWER calculation, which Stats
reads by launching `top`. Wattson computes its own score from native counters;
it does not execute `top` or consume its POWER output. A shared formula does
not guarantee identical observations across sampling intervals and process
coverage. The upstream
references are [Stats' battery reader](https://github.com/exelban/stats/blob/a2836b697de33d71a8bbb880a41c7e12304de9a2/Modules/Battery/readers.swift#L246-L307),
[Apple top's POWER calculation](https://github.com/apple-oss-distributions/top/blob/1e3b6cace1cbca04536cf325da9adc7389a27e8f/power.c#L82-L89)
and [XNU process resource counters](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/osfmk/kern/bsd_kern.c#L1186-L1197).
Apple's libproc header labels the interface subject to change. Failures show an
unavailable state; no CPU-only or inferred-watt fallback changes its meaning.

## Sampling and availability

The sandboxed app reads one fixed `getTopProcesses` operation from Wattson's
existing helper. This read accepts no PIDs, paths, commands or sample counts.
The read runs separately from power/control requests and retains console-user
authorization. An app-only installation or older helper shows **Unavailable**;
updating both app and helper through the native PKG enables the new operation.

Sampling starts when the popup opens with the module enabled. Its existing
display clock requests another sample ten seconds after the previous completion;
there is no additional repeating timer. Closing the popup, opening Settings or
disabling the module stops requests and invalidates late completions. Reopening
within ten seconds of a successful sample immediately reuses it without moving
its original refresh deadline. An expired or missing sample starts with
**Measuring…** and a fresh read. Wake and a force-quit action clear the cache;
force quit also stops monitoring before the popup's closing animation. A failed read replaces previous
rows with **Unavailable** and can recover on the next interval. No process list
is saved to preferences, diagnostics or disk.

## Ending a process

Click a process row to select it and reveal a small **×** capsule over its
right-hand score. The process name, activity bar and other text never move. Click the
selected row again or press Escape to clear the selection. The interaction is
the same in Compact view. The score returns when selection clears. Arrow keys
move the selection between visible rows, and the selected button is exposed to
accessibility clients.

The action is a fixed 38 × 16-point native glass capsule on macOS 26, aligned
with the score text's right edge. Every process uses the same width, independent
of its score's digit count or eligibility. It has a soft blue gradient and
reflected rim; unavailable actions use the disabled appearance. Older systems
use the same compact capsule shape.
One shared pointer-feedback surface provides the light effect without a timer.
Reduced Motion/Transparency and high contrast use static, legible feedback.
Hiding, deselecting or closing clears the reflection immediately.

Clicking **×** closes the popup and opens Wattson's native confirmation dialog.
**Escape** cancels; Return leaves the confirmation open. **Force Quit** requires
an explicit choice, sends SIGKILL and can discard unsaved
work. Only processes owned by the current console user are eligible; system and
other users' processes are not eligible. Missing identity support leaves the
readings usable and the selected button disabled. Failed requests show a native
explanation. Reopening after this action always measures a fresh list.

Selection and confirmation retain the PID, monotonic start time and complete
32-byte kernel audit token, including the process incarnation. Selection follows
this identity when the ranking changes and clears when the target disappears or
the popup/module closes. The helper accepts only the fixed `forceQuitProcess`
operation with that identity. A short-lived worker permanently drops root
credentials to the authenticated console user before checking the identity and
sending the fixed signal. The daemon itself never signals a listed process.

The worker uses public `task_name_for_pid` and `task_info(TASK_AUDIT_TOKEN)` to
validate the identity, then `proc_signal_with_audittoken` to select the original
kernel process atomically. It never falls back to PID-only signaling if that API
or identity access is unavailable. The symbol is resolved at runtime so older
macOS versions and helpers retain monitoring without this optional action.
These name ports do not provide process memory access. No shell commands,
user-chosen signals or privileged termination operations are accepted.
