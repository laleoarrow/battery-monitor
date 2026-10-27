#!/bin/bash
# Reuse the original app/container/process/defaults owner for each full run.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
OUTPUT_DIR="$1"
source "$ROOT_DIR/scripts/lib/local_cleanup.sh"
wattson_cleanup_init
/usr/bin/shasum -a 256 "$ROOT_DIR"/Core/*.swift "$ROOT_DIR"/MenuBar/*.swift \
    "$ROOT_DIR"/Popover/*.swift "$ROOT_DIR/tests/interaction/main.swift" \
    "$ROOT_DIR/scripts/verify_interaction.sh" > "$OUTPUT_DIR/source-digests.txt"
/bin/cp "$ROOT_DIR/tests/interaction/main.swift" "$OUTPUT_DIR/interaction-main.swift"
status=0
for variant in normal legacy legacy-accessibility; do
    legacy=0; motion=0; transparency=0
    if [[ "$variant" != normal ]]; then legacy=1; fi
    if [[ "$variant" == legacy-accessibility ]]; then motion=1; transparency=1; fi
    run_status=0
    WATTSON_FORCE_LEGACY_KNOB="$legacy" WATTSON_FORCE_REDUCE_MOTION="$motion" \
        WATTSON_FORCE_REDUCE_TRANSPARENCY="$transparency" \
        wattson_run_script "$ROOT_DIR/scripts/verify_interaction.sh" \
        > "$OUTPUT_DIR/$variant.log" 2>&1 || run_status=$?
    printf '%s\n' "$run_status" > "$OUTPUT_DIR/$variant-exit-code.txt"
    [[ "$run_status" == 0 ]] || status=1
done
/usr/bin/python3 - "$OUTPUT_DIR" <<'PYREVIEW'
import json
from pathlib import Path
import sys
p = Path(sys.argv[1])
results = []
for variant in ("normal", "legacy", "legacy-accessibility"):
    text = (p / f"{variant}.log").read_text()
    status = int((p / f"{variant}-exit-code.txt").read_text())
    controls = [line for line in text.splitlines() if "原一秒期限仍被拒绝" in line]
    unexpected_timeouts = [line for line in text.splitlines()
                           if line.startswith("HISTORY_COMPLETION_TIMEOUT")
                           and "negative-control-" not in line]
    passed = (status == 0 and "ALL_INTERACTION_CHECKS_PASSED" in text
              and text.count("✅") >= 32 and len(controls) == 3
              and all(line.startswith("✅") for line in controls)
              and "SCREEN_LOCKED_CHECKS_SKIPPED" not in text
              and "HISTORY_MOTION_CHECKS_SKIPPED" not in text
              and not unexpected_timeouts)
    results.append({"variant": variant, "exitCode": status,
                    "passedAssertions": text.count("✅"),
                    "failedAssertions": text.count("❌"),
                    "negativeControlRejections": controls,
                    "unexpectedHistoryTimeouts": unexpected_timeouts,
                    "passed": passed})
report = {"schema": 1, "completeInteractionHarness": True,
          "originalRunnerAndDeadlinesPreserved": True,
          "allPassed": all(r["passed"] for r in results), "variants": results}
(p / "full-results.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
if not report["allPassed"]:
    raise SystemExit(1)
PYREVIEW
exit "$status"
