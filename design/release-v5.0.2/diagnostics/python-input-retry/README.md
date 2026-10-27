# Python input retry diagnostic

Candidate `40531167341` on frozen commit `e4dcd5a78eed2dbe94a1e984b0dab9f2371cd443`
finished **cancelled** after the job deadline. Swift completed 735 tests and
reported `registered=183 remaining=0`. Python last reported
`test_cleanup_failure_after_success_is_an_error` complete at 15:32:19Z; the
next test in unittest's alphabetical order exercises `communicate` retries.
Cancellation followed at 16:12:52Z. The exact live Python stack was not captured,
so attribution of the CI stall to the next test remains an evidence-backed
inference, separate from the deterministic local reproduction below.

On the inspected local Apple Python 3.9.6, `Popen._communicate` registers stdin
for writing only when `self.stdin and input`. The wrapper retried every 100 ms,
then set `input=None` after the first timeout. If the initial payload had not
finished, retries abandoned stdin without delivering EOF. Passing the original
input again is also rejected by `communicate` once communication has started.
The relevant actual standard-library conditions are retained in
[python-3.9-stdin-conditions.txt](python-3.9-stdin-conditions.txt).

Before editing, one owned isolated probe ran both byte and text input cases:
a child waited 0.3 seconds before reading 140,000 bytes from stdin. Both old
paths hit the one-second inner deadline with no output; the outer owner had a
20-second deadline and removed both workspaces. The original test used
`timeout=None`, allowing this failure to exhaust the hosted job deadline.

The repair is confined to `tests/local_runtime.py` and its cleanup tests.
Finite fixture input is written to a temporary file inside the owned workspace,
rewound, and inherited as child stdin. The parent handle closes immediately
after process creation/registration; the child retains its descriptor. This
changes finite input from a pipe to a seekable file. The only other input caller
is finite JSON sent to the Perl sanitizer, which does not depend on pipe or
non-seekable behavior. This helper accepts fixture data, not credentials.
`input=None`, explicit stdin, empty EOF, text/byte output, encoding/errors,
argument mutual exclusion, short output polling, and signal ownership remain
covered.

The regression forces the delayed read and verifies the complete payload and
stderr in both modes under a two-second deadline, then checks `timeout=None`
after the bounded case has proved progress. The full cleanup suite passed
17 checks in 33.132 seconds, including locked-signal delivery, TERM/INT,
descendant cleanup, nested lifecycle cleanup and timeout/error handling.
The actual caller's socket/sanitizer suite passed 8 checks in 5.318 seconds.
Both invocations had outer owned deadlines. Existing post-run checks found
zero entries in the test and reproduction scratch roots; `git diff --check`
passed. An independent read-only review found no remaining input-lifetime,
encoding or EOF issue.

[summary.json](summary.json) contains the exact source hashes and boundaries;
[retained-output-excerpts.txt](retained-output-excerpts.txt) preserves excerpts
from the already completed commands. No test was rerun while writing this
record. The final candidate JSON and complete cancelled-job log remain in
`../../publication/`. Formal CI has **not** been rerun, and the original
cancelled candidate remains a failed release gate.
