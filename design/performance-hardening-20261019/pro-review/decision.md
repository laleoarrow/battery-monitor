# Actual Pro review and local disposition

The user manually unlocked the Mac. The existing running SunBrowser 150 app was
bound by its full path. Immediately before submission, its actual model selector
reported **“Pro, 5 of 5”**. The uploaded `source-context.txt` was 27,497 bytes,
SHA-256 `e6d990ccde8bfef9bd1d385e7adc0919453c2316f641b47490ce5369afee58b2`.

The completed conversation is [审查补丁风险](https://chatgpt.com/c/6ad58891-d4ac-83ee-9892-4acc9fc80fef).
The UI showed “Worked for 10m 4s” and “Response complete”. This record is a local
summary and disposition of the response, not a verbatim transcript. The exact
submitted message and full response remain in that conversation. Pro independently
retrieved the three complete public v4.3.22 files, applied the supplied exact diff,
and reported all three complete-file hashes matched frozen `df7d4bc`.
Pro used the supplied test reports; it explicitly did not claim to rerun our GUI
or test suites.

## Verdict

Pro found no newly introduced regression or race requiring a production change,
and recommended retaining the three minimal patches. Its checks included initial
button-image creation, enabled/tint/theme/selection refresh responsibility,
Reduce Transparency notification propagation, actual focus ownership, identity
rebinding, reader deadlines, EINTR handling, listener wakeup and the complete
worker response/pending lifetime.

The root's independent source review and the previously completed native results
support retaining the production patch. No additional production code is changed
in response to this review.

## Clarifications adopted

- An unavailable action falls back to the same process row only while its
  `Selection` key remains equal. Losing a termination identity changes an
  `.identified` key into `.unavailable`; old selection/focus is retired. The
  existing unavailable PID/name key cannot distinguish every PID reuse, but its
  action is disabled and the action handler requires a validated identity.
- `makeFirstResponder` is a request. Tests must inspect the resulting responder
  object and actual dispatch, not infer success solely from its Bool result.
- The new **100 ms is a requested poll interval**, not a hard real-time bound
  on idle exit. Scheduling can add delay. Worker replies are independent of
  the listener wait, and the patch does not create a worker-cancellation policy.
- Do not add a simplistic “current responder must still equal the captured
  object” guard. Hiding the old action can itself move AppKit focus, after which
  identity-based restoration is still required. Apple documents this behavior in
  [Hiding Views](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CocoaViewsGuide/WorkingWithAViewHierarchy/WorkingWithAViewHierarchy.html).
  The root rechecked this primary source. No production callback or nested event
  loop currently establishes the speculative reentrancy path.

## Targeted follow-up

Pro's tables are a checklist to compare with existing assertions, not a claim
that all listed cases are missing. Already-covered cases are mapped, not repeated.

Focus follow-up strengthens the persistent native harness with real
`NSWindow.sendEvent`, independent focus-A/selection-B state and arrow dispatch,
both action rerank directions, audit-token-only replacement and external field
editor truncation/empty-list handling. Existing independent 34-check coverage
continues to cover Escape, surviving-identity Top N fallback, start-time change,
identity loss and status clearing. See `focus-followup/coverage-mapping.json`.

Helper follow-up compares the existing executable deadline tests against the
checklist and adds only missing boundary/worker lifecycle observations. A fault
injected EINTR test must be labeled as such; it is not a real-kernel signal test.
The actual poll semantics were also checked against Apple's
[poll manual](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/poll.2.html).

The test-only follow-up is now executed against frozen `163f990`: the three native
variants pass 463/461/455 checks (1,379 total), plus all 34 independent focus checks
and 20,000 stress iterations. All new actual window dispatch assertions execute;
no native-button focus path is skipped. Guest and host cleanup are verified.
See [native proof](focus-followup/native-163f990/owned-source-verification.json).
Four targeted helper executables also pass, with fault injection explicitly
labeled. Existing successful results remain under their original commit identities.

## Limits retained

The review does not quantify whole-app CPU/energy savings or full launch latency.
Cross-building Intel/macOS 12 metadata is not Intel/macOS 12 runtime acceptance.
The existing synchronous-close timing qualification remains intact. A later
macOS 27 CI result must identify its actual OS/SDK/image and cannot establish
physical battery/SMC success or an unexecuted installation/helper lifecycle.


## Actual Pro follow-up after the target-OS findings

The target runner subsequently passed all 664 Swift tests but exposed one
Settings standalone `-warnings-as-errors` compile failure for Swift's new
`ImplicitStrongCapture` diagnostic. `67f3910` changes only that feedback-worker
outer closure from implicit strong capture to explicit `[self]`; its inner main
callback remains weak. The root and an independent reviewer found the ownership
relationship unchanged. The focused Settings contract passes on the 26 host.

The same SunBrowser conversation was used for a bounded follow-up. The selector
again showed **Pro, 5 of 5** before submission; its final response and
**Response complete** were observed. Pro approved the one-line explicit capture,
confirmed it preserves the existing strong/weak lifetimes without adding a
cycle in the shown code, and retained its original three-patch verdict. It did
not claim to execute tests. The Settings fixture now passes in the final full 27
rerun; see [capture verification](capture-followup/verification.json).

The separate defaults diagnostic-format compatibility patch affects only the
test cleanup fixture. It does not change production preferences APIs.


## Final automated acceptance

Frozen `4532daa` passes the complete hosted macOS27/SDK27 workflow: 664 Swift
tests, 613 Python tests (four expected opt-in GUI skips), three actual native
completion markers, 20,000 animation stress iterations and universal App/helper
build verification. Each native run retains the synchronous-close mid-reopening
qualification; actual process button focus paths execute. The only later build
fix checks the same required architectures separately for `lipo` compatibility;
it does not change runtime App source. Full proof and remaining hardware/
installation/signing boundaries are in
[final hosted verification](../compatibility/ci-39198225803/verification.json).
