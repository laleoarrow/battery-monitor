# Pending helper sampler can exhaust the idle deadline without permitting exit

Audit and minimal defensive fix on the 4.3.22 source. This is an ordinary
correctness and performance finding, not a security scan. The reproduction
does not modify the installed application/helper, protocol, permissions,
sampling formula or UI.

`Helper/wattson-helper.swift:1596` computes the listener's wait from the last
request's activity time plus twelve seconds. The exact production
`socketPollTimeoutMilliseconds` returns zero once that deadline passes
(`:411`). However, the exit guard (`:1617`) also requires the asynchronous
process sampler to have finished. Therefore a pending sample after twelve
seconds makes each loop call `poll(..., 0)` and then reject its own idle exit.

The sampler's five-second checks do not impose a kernel-call or scheduling
deadline, and its shared credential lock uses `NSLock.lock()`
(`HelperV5/TopProcesses.swift:111,165`). A worker delayed past twelve seconds
therefore exposes this conditional loop defect. A blocked native process query
or unusually delayed utility scheduling is a possible trigger; the probe does
not reproduce either naturally. In particular, a blocked login-agent filesystem
operation runs on the FIFO/main executor and stalls that executor itself. It
cannot simultaneously drive a poll spin while holding the lock. When it
releases, a deadline-expired sampler normally settles quickly. The injected
lock is a deterministic way to create the pending-worker condition, not proof
of an ordinary-production lock-contention stall. The lock remains necessary:
effective credential changes must never race native process reads.

The owned probe deliberately holds that actual lock for 12.205 seconds while
running the actual `HelperTopProcesses.sample`. It then calls the unmodified
production timeout function and real Darwin `poll` on an owned pipe that has no
readiness event. Three 250 ms rounds make 35,904–39,266 polls and consume
50.164–55.197 ms process CPU each. A diagnostic 100 ms wait control makes three
polls and consumes 0.043–0.088 ms CPU per approximately 303 ms round. The worker
returns after releasing the lock. A pending two-millisecond reader deadline
continues to return two milliseconds. Raw results and source SHA-256 hashes are
in [reproduction.json](reproduction.json).

These numbers characterize the deliberately blocked boundary. They are not a
measurement of normal sampling CPU, battery consumption or the entire app.

## Production change

The fix keeps the twelve-second idle timestamp and exit condition unchanged. Once that
deadline has passed, if the sampler remains pending and no incomplete reader
owns its own deadline, it uses a finite 100 ms listener wait
before rechecking worker completion. Incoming connections still wake `poll`
immediately. Pending reader deadlines retain priority. A completed worker may
delay observation of an already-eligible idle exit by the requested poll interval
plus scheduling delay; 100 ms is not a hard real-time exit bound.
The process reply itself does not wait for the listener: the sampler's own
`queue.async` closure directly calls `writeAll(line, to: fd)`
(`Helper/wattson-helper.swift:1505,1520`) before its deferred socket close and
pending-state reset. The new wait therefore adds no 100 ms reply delay; only
the main loop's later idle-exit check may wait for the next poll timeout.

The pure timeout function accepts one `backgroundWorkPending` Boolean; the
main loop passes the existing thread-safe `topProcessesWorker.hasPending`.
Only its no-reader/already-idle/pending-worker case needs new behavior. Do not
reset `lastActivityUptime` on every pending-worker loop: that would alter the
meaning of the idle lifetime. Do not remove the credential lock.

The executable regression cases verify: expired idle + pending worker returns the
finite wait; expired idle + completed worker remains zero; idle not yet expired
retains the original wait; incomplete reader deadlines and expiration override
the background wait; rounding and Int32 clamping retain their existing results.
The existing inbox executable tests continue to verify framing and cleanup.

The strengthened executable test was first run against the original timeout
body. A harness-only overload accepts the new Boolean and forwards the old
four arguments, changing no timeout calculation. It fails at runtime with
`an idle-expired pending worker must not cause zero-timeout polling`, rather
than failing compilation. [baseline-regression.log](baseline-regression.log)
and [baseline-regression.json](baseline-regression.json) retain that red result;
[baseline-timeout.swift](baseline-timeout.swift) retains the original function.

With the fix, all **53 helper contract tests pass** in 17.644 seconds, including
the executable deadline, socket, bounded-command and inbox regressions. See
[helper-contract.log](helper-contract.log).

The updated owned probe compares the retained baseline and fixed production
functions directly, with the real production sampler blocked past twelve
seconds as above. Three fixed rounds each make three poll calls per approximately
303 ms and consume 0.045–0.081 ms process CPU; baseline rounds make 30,226–38,921
poll calls per approximately 250 ms and consume 51.305–56.075 ms process CPU.
The fixed timeout is 100 ms in every blocked-worker round and reader priority
remains two milliseconds. [fixed-reproduction.json](fixed-reproduction.json)
records exact source hashes, raw timings and limitations. This is a rare-edge
measurement, not a general app speedup claim.

Run `python3 design/performance-hardening-20261019/helper-poll/reproduce.py`
from the repository. It uses `tests/local_runtime.py` for registered temporary
directories and bounded process groups. The fixture owns and closes both pipe
ends, releases the lock and joins the worker; no installed helper, socket,
process signal, preference, credential or UI is touched. Generated Swift and
the compiled binary are removed; only the explicit evidence files remain.
