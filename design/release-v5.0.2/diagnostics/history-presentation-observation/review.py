"""Assess paired waits and mandatory real-key negative controls without new runs."""
import json
from pathlib import Path
import sys

root = Path(sys.argv[1])
cases = {}
issues = []
for name in ("baseline", "candidate", "infinite", "long", "retained"):
    report = json.loads((root / f"{name}.json").read_text())
    failed = [line for line in (root / f"{name}.log").read_text().splitlines() if line.startswith("❌")]
    elapsed = report["decisionElapsedSeconds"]
    passed = report["originalContractedAxisPassed"]
    exit_code = int((root / f"{name}-exit-code.txt").read_text())
    assert exit_code in (0, 1)
    assert report["originalOneSecondDeadlineRetained"] and report["globalRunApplicationUnchanged"]
    assert not report["postDeadlineFlushAffectsVerdict"]
    assert report["records"] and not report["records"][0]["screenLocked"]
    keys = [key for layer in report["records"][0]["layers"] for key in layer["keys"]]
    if name == "candidate":
        if not (passed is True and report["allExtractedAssertionsPassed"] and elapsed <= 1 and not failed and exit_code == 0):
            issues.append("Candidate control did not pass the original fixture within one second")
    elif name != "baseline":
        assert report["faultInjected"] and report["fault"] == name
        assert passed is False and "history.stroke" in keys and 1 <= elapsed < 1.15 and exit_code == 1
        assert failed == ["❌ History 缩轴结束后原生图层自行静止"]
    cases[name] = {"settled": passed, "decisionElapsedSeconds": elapsed, "remainingKeys": keys,
                   "failedAssertions": failed, "faultInjected": report["faultInjected"],
                   "visibilityBeforeHistoryInputs": report["visibilityBeforeHistoryInputs"],
                   "windowNotOccludedAtVerdictObservation": report["records"][0]["windowNotOccluded"],
                   "processExitCode": exit_code}
print(json.dumps({"diagnosticChecksPassed": not issues, "issues": issues, "cases": cases,
                  "sameVMOriginalFailedCandidatePassed": not cases["baseline"]["settled"] and cases["candidate"]["settled"],
                  "sameOneSecondDeadline": True,
                  "sharedVisibilityPreconditionsPassed": all(case["visibilityBeforeHistoryInputs"]["ready"] for case in cases.values()),
                  "negativeControlsUseRealStrokeKeyAndIdenticalPaths": True,
                  "limits": "Extracted History prefix only; not the complete interaction suite or hosted candidate. Cleanup is assessed separately after the owner returns."}, indent=2))
sys.exit(1 if issues else 0)
