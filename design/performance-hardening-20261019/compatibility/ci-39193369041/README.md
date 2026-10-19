# First macOS 27 validation attempt

[Run 39193369041](https://github.com/laleoarrow/battery-monitor/actions/runs/39193369041)
used source `000fdeb268940c99b9ea5ce727eecad6469207c9` on the codex branch and
the documented `xcode-27` runner. Root requested cancellation after the Swift
test step remained in progress without an observable completion. GitHub
recorded the run as **cancelled** at 03:27:18 UTC on 2026-10-19. This attempt is
neither a compatibility pass nor a confirmed application failure.

The retained job metadata records successful environment assertions and Swift
package build. The assertions checked macOS major 27, SDK major 27, arm64, and
the source commit. Swift testing entered at 03:11:30 UTC; at run completion,
948 seconds had elapsed without a recorded step completion. Python, the three
native variants/stress, and universal release-build verification did not run.
The independent website job passed.

The Swift job raw-log endpoint returned HTTP 404 after completion, and
`gh run view --log` reported `log not found: 117870777961`. The official
run-level log archive contained only the website job's 12 files; see
`log-archive-members.json`. A final retry still yielded no Swift job log.
The available website raw log is retained as `job-117870777766.log`.

Consequently the last XCTest case, test count, all-tests summary, and whether
the test process finished but failed to exit are **unknown**. Actual OS/SDK
minor versions, image version, and Xcode build stdout are also unavailable;
the documented image versions must not substitute for missing run output.
No cause is assigned to the waiting or missing logs.

`verification.json` consolidates the qualified result. Run/job API JSON and
timestamped status history preserve the progression. No production or CI code
was changed and no cancel or rerun was dispatched by this monitoring agent.
Downloads used shared owned-process lifecycle helpers and a unique project
`.noindex` scratch directory. Temporary ZIPs/scratch were removed, with only
logs and metadata retained. Remote test resource cleanup could not be
independently verified from missing logs; cancellation alone does not prove it.
