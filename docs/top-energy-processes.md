# Process Activity

The popover's **Process Activity** module ranks recent process activity.
Settings > Modules provides its visibility switch, reorder handle, and
**Processes shown** choice (1–10, default 3). Existing saved module orders keep
their positions and append the new module. The list shares Wattson's transparent
surface, inset separators and semantic colors. Blue gradient
bars with neutral outlines follow the supplied module-icon reference.

## Reading the values

The blue bars use a fixed **0–100 pts** scale. An idle process therefore keeps a
short or empty bar even when it ranks first. Scores above 100 retain their real
numeric value, with a full bar and an overflow mark. The scale stays the same
when the ranking or the configured process count changes.

The single blue color family follows the same fixed scale: low activity uses
paler blue and high activity uses deeper blue. A subtle vertical highlight
preserves the bar's shape. Above 100 the color stays at the deepest endpoint;
the numeric value and overflow mark still show the distinction. High contrast
uses solid system blue, with values and lengths carrying the information.

Each row shows its activity points and the two inputs: **CPU %** and **Idle
wakeups /s**. The information control explains their meaning. CPU is measured
per logical core: 100% means one fully occupied core, and multicore work can
exceed 100%. Platform idle wakeups count interruptions of platform idle time,
not all process wakeups. Neither component measures per-process electrical
power.

The CPU-and-wakeup score follows the POWER metric used by Stats'
battery process list. It is not watts, a percentage of the battery's measured
power, or Activity Monitor's private Energy Impact calculation. The visible
activity points use this formula, alongside its concrete component readings:

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

Stats launches `top` for this metric. Wattson calculates the same score from
native counters to avoid repeatedly traversing process memory maps. The upstream
references are [Stats' battery reader](https://github.com/exelban/stats/blob/a2836b697de33d71a8bbb880a41c7e12304de9a2/Modules/Battery/readers.swift#L246-L307),
[Apple top's POWER calculation](https://github.com/apple-oss-distributions/top/blob/1e3b6cace1cbca04536cf325da9adc7389a27e8f/power.c#L82-L89)
and [XNU process resource counters](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/osfmk/kern/bsd_kern.c#L1186-L1197).
Apple's libproc header labels the interface subject to change. Failures show an
unavailable state; no CPU-only or inferred-watt fallback changes its meaning.

## Sampling and availability

The sandboxed app reads one fixed `getTopProcesses` operation from Wattson's
existing helper. Clients cannot supply PIDs, paths, commands or sample counts.
The read runs separately from power/control requests and retains console-user
authorization. An app-only installation or older helper shows **Unavailable**;
updating both app and helper through the native PKG enables the new operation.

Sampling starts when the popup opens with the module enabled. Its existing
display clock requests another sample ten seconds after the previous completion;
there is no additional repeating timer. Closing the popup, opening Settings or
disabling the module stops requests and invalidates late completions. Reopening
starts with **Measuring…** and a fresh sample. A failed read replaces previous
rows with **Unavailable** and can recover on the next interval. No process list
is saved to preferences, diagnostics or disk.
