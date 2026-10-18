# Native release gates after the History fixture flush

Accepted source and release commit:
`9d157d496024d32b0f65ec3fe9b1c927678352fc`.

| Gate | Result | Previously failing matched-tail check |
| --- | --- | --- |
| Native interaction | Exit 0; 440 checks; full pass | Pass, log line 444 |
| Legacy interaction | Exit 0; 438 checks; full pass | Pass, log line 442 |
| Reduce Motion/Transparency fallback | Exit 0; 432 checks; full pass | Pass, log line 437 |
| Animation stress | Exit 0; 20000 iterations; reported elapsed 0.095 s | — |

All three interaction logs contain the successful
`History 控制点过渡到达新曲线后自动静止` assertion and no matched-tail completion
timeout or tail-settle failure diagnostics. The original one-second deadline,
exact geometry comparison and automatic animation-key removal assertion remain
unchanged. This local pass does not substitute for the hosted candidate rerun.

The guest archive and host cleanup library match the frozen commit. All 157
source, script, test and asset inputs matched before and after execution and
matched the release commit. Relative to the prior cleanup-fix gate, only
`tests/interaction/main.swift` changed; no production AppKit or helper code
changed. Previous native evidence remains untouched.

The three interaction configurations match the existing release workflow and
ran in one new disposable ARM GUI VM. Guest scratch, full-command-path
processes, app registrations, test preferences (including a 35-second
observation), containers, Application Scripts and mounts all passed cleanup.
The owned VM was stopped and deleted; both original TestLab VMs remained
stopped. Host snapshot scratch is empty. No canonical app/helper or user
process was modified.

The display-policy comparison covers only the four `DisplayProbe` fields. The
stress elapsed value is not an app performance benchmark. Local GUI gates do
not replace the hosted candidate/install matrix or GitHub publishing gates.

Reproduce from a checkout with the matching lifecycle library and a new output
directory:

```bash
bash design/release-v4.3.22/native/run-owned.sh \
  9d157d496024d32b0f65ec3fe9b1c927678352fc \
  "$PWD/design/release-v4.3.22/native/after-resume-flush/another-run"
```

See `owned-source-verification.json`, `accepted/matched-tail-results.json`,
`accepted/release-source-identity.json`, `accepted/results/gate-results.json`
and the resource/VM audit JSON files. Raw log bytes remain in adjacent `.raw.gz`
files when whitespace normalization was needed.
