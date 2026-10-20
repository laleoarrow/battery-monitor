# Wattson 5.0.0 performance and stability review

Reviewed public source `39c48e3e0564384f4aefb4aff1c1f6e99c6a9c7b`
from documentation head `6c4d1e50d52458cd8a814e09e67d8059b642d1a0`.
The scope preserves existing features, visuals, sampling cadence and metrics.

## Source review

Three independent local reviews covered battery sampling, runtime estimates and
health caching; helper/socket/process-action lifetimes; and AppKit refresh,
focus, appearance and animation lifetimes. They found no new product defect
with sufficient evidence to justify a runtime behavior change. Existing
single-flight work, generation checks, strict process identity and stopped
hidden animations remain in place.

Settings appearance changes repeat a traversal of the visible section. This
is an infrequent path with no measured user-visible cost; it is retained rather
than changing refresh coverage, focus or key-loop behavior without evidence.

SunBrowser's existing signed-in session was used for the
[Pro review](https://chatgpt.com/c/6ad73e62-83a8-83ec-91e6-8dfd8d374842).
The selector was verified at Pro, 5 of 5, before submission. Its completed
8-minute-16-second response was read in the browser. Pro reviewed the frozen
source, found no new confirmed bug, recommended only the health-reader test
seam and real fault coverage, and advised retaining Settings refresh behavior.
Pro's environment was Linux; the native test results below come from this Mac.

## Real health-reader regression coverage

`SystemBatteryHealth.readLivePercent()` still invokes only
`/usr/sbin/system_profiler SPPowerDataType -json -timeout 5`, with the same
locale, 7.5-second deadline, 262144-byte limit, TERM/100 ms/KILL cleanup and
result parsing. Its existing body is a private function with a DEBUG-only test
entry. There is no production setting or external command configuration.
The private budget argument lets fault fixtures finish in 600 ms rather than
waiting the full production deadline twice; production always supplies 7.5 s.

The new Python runtime contract compiles that actual reader with a self-running
Swift fixture. It checks split output including its final bytes, valid JSON
with nonzero exit, exactly 262144 bytes, 262145 bytes, silent timeout, ignored
SIGTERM and failed launch. All six started direct children must be gone before
the reader returns. This tests real process and pipe behavior; it does not
claim to force a precise EAGAIN/exit race or manage arbitrary profiler
descendants.

The fixture uses `tests/local_runtime.py` for owned process groups, bounded
commands, isolated preferences and project-local scratch cleanup, including
failure, timeout and catchable interruption. No App bundle is registered.

## Verification

Local environment: macOS 26.5.2 (25F84), SDK 26.5.

- Targeted health runtime contract: passed (six reaped children and failed launch).
- Full Swift suite after the change: 700 tests, zero failures, 19.243 seconds.
- Full Python headless suite: 627 tests, zero failures, four expected opt-in
  skips, 263.738 seconds.
- Existing no-window animation stress: 20000 iterations, 0.649 seconds.

Three one-off source-copy mutations confirmed test sensitivity: removing the
exit-status guard fails the nonzero-exit case; raising the limit to 262145
fails the over-limit case; changing `<=` to `<` fails the exact-limit case.
Each failed with its expected assertion, while the unchanged source passed
again. Mutant files and owned process groups were removed, and the production
source/test hashes remained unchanged. These are deliberate test mutations,
not evidence of a previously present product bug.

An initial Swift invocation wrapped in Python's runtime fixture introduced
`CFFIXED_USER_HOME`, conflicting with a test that intentionally checks the real
unique test-suite plist path. That invocation had one test-environment failure;
the individual check and the complete suite passed under the standard Swift
environment. Production preferences were not involved.

These checks do not measure display FPS, whole-app CPU, battery-life improvement
or physical macOS 27 hardware behavior. The canonical 5.0.0 installation is
untouched by this source/test review.
