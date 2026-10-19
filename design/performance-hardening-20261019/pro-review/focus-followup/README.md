# Pro follow-up: native focus boundaries

Pro's final review accepted the three production changes and proposed boundary
assertions to cross-check. `coverage-mapping.json` distinguishes the existing
34-case independent oracle from the small persistent test-only additions.
Existing Escape, smaller-Top-N action fallback, start-time replacement,
unavailable identity and loading/empty focus checks were mapped without copying
them into another test fixture.

The persistent test now sends Space and Down Arrow through the real
`NSWindow.sendEvent`. It separately verifies focus A with selection B, moves the
focused action down and up before recording each action on A, handles an
audit-token-only identity replacement, and retains an unrelated field editor
through smaller Top N and an empty list. The patch is 47 inserted / 21 deleted
lines; production files are unchanged.

`native-163f990/owned-source-verification.json` records actual execution from
frozen `163f9902df566d02fbc235b1a2027583ad76c638`, using the unchanged v2 harness
and independent oracle. All 34 independent checks passed. All 21 persistent
focus assertions passed in every native variant with no qualified focus paths.
Complete native checks passed 463 / 461 / 455 (1,379 total), each with its actual
completion marker. The 20,000-iteration stress marker is retained verbatim.
All 157 frozen input source files matched before and after execution, and all
persistent harness hashes remained unchanged. Guest resources, preferences,
app registrations, processes, containers and mounts were clean; after the
35-second preference observation the owned VM and host snapshot were removed.
The two pre-existing VMs remained stopped.

This execution used ARM macOS 26.6.1 (25G76). It is not a macOS 27 runtime claim.
One existing accessibility variant restriction remains explicit: closing
completed synchronously, so that mid-close reopening timing path could not be
exercised. Actual force quitting is outside this focus fixture; handlers only
recorded mocked identities and never contacted the helper.
