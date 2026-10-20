"""Aggregate read-only production sampling timings without retaining sensor values."""
import os
import sys

os.environ.pop("PYTHONOPTIMIZE", None)
sys.dont_write_bytecode = True
if sys.flags.optimize:
    raise SystemExit("Optimized Python is unsupported; unset PYTHONOPTIMIZE and do not pass -O.")

import collections
import hashlib
import json
import math
import pathlib
import platform
import statistics
import subprocess
import time

ROOT = pathlib.Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tests"))
from local_runtime import TemporaryDirectory, run

root, executable, evidence = map(pathlib.Path, sys.argv[1:])
BASELINE = "d6b40247cd50c05af4ec9a99956c8ff1937c4894"


def command(*args):
    return subprocess.check_output(args, text=True, timeout=10).strip()


def process_metrics(path):
    found = subprocess.run(
        ["/usr/bin/pgrep", "-f", "^" + str(path).replace(".", "[.]") + "( |$)"],
        capture_output=True, text=True, timeout=5,
    )
    if found.returncode not in (0, 1):
        raise RuntimeError("Cannot inspect canonical process identity")
    result = {}
    for pid in found.stdout.split():
        values = command("/bin/ps", "-p", pid, "-o", "time=,rss=").split()
        if not values:
            continue
        parts = values[0].split(":")
        seconds = float(parts[-1]) + 60 * int(parts[-2])
        if len(parts) == 3:
            seconds += 3600 * int(parts[0])
        result[int(pid)] = {"cpuSeconds": seconds, "rssKiB": int(values[1])}
    return result


def distribution(values):
    values = sorted(values)
    return {"count": len(values), "minimum": min(values), "median": statistics.median(values),
            "p95NearestRank": values[math.ceil(len(values) * .95) - 1],
            "maximum": max(values), "sum": sum(values)}


canonical_path = pathlib.Path("/Applications/Wattson.app/Contents/MacOS/Wattson")
helper_path = pathlib.Path("/Library/PrivilegedHelperTools/com.leoarrow.wattson.helper")
before_app = process_metrics(canonical_path)
before_helper = process_metrics(helper_path)
metadata = {
    "baseline": BASELINE, "repositoryHEAD": command("/usr/bin/git", "-C", str(root), "rev-parse", "HEAD"),
    "osVersion": command("/usr/bin/sw_vers", "-productVersion"),
    "osBuild": command("/usr/bin/sw_vers", "-buildVersion"), "architecture": platform.machine(),
    "compiler": command("/usr/bin/xcrun", "swiftc", "--version"),
    "optimization": "-O -whole-module-optimization -swift-version 5 arm64-apple-macos12.0",
    "compiledSources": [
        {"path": ("tests/performance/sampling/main.swift" if path.name == "main.swift" else "Core/" + path.name),
         "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
        for path in sorted((executable.parent / "sources").glob("*.swift"))
    ],
    "runtimeSamples": 32, "targetSpacingSeconds": 2, "topProcessesReads": 3,
    "healthCacheBatchCount": 10, "healthReadsPerBatch": 10_000,
    "wallStartedUTC": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "limitations": [
        "Real optimized unsandboxed CLI calling frozen production sources; not the canonical app's complete process image.",
        "Production dependency injection wraps real IOKit/IOPS/helper/live-health reads; no sensor or duration fixtures.",
        "The health cache's default fixed profiler reader runs on an instrumented utility queue so actual child launches can be counted.",
        "Cold means empty in-process health cache; no OS, filesystem or firmware cache was flushed.",
        "Per-stage wall times overlap between parallel battery and helper branches; they must not be added as serialized costs.",
        "Client CPU is getrusage(RUSAGE_SELF); helper and profiler child CPU are not included in runtime sample CPU.",
        "Canonical/helper process CPU is coarse ps cumulative time over the window, shared with ordinary app work; it is not exclusive attribution.",
        "Thermal state and power-source state were not recorded or experimentally controlled for this run.",
        "One live host, naturally varying workload; no display FPS, battery-life or macOS 27 physical hardware claim.",
        "Process Activity returns up to 10 helper rows regardless of the UI Top N setting; only row counts are retained.",
    ],
}
(evidence / "metadata.json").write_text(json.dumps(metadata, indent=2) + "\n")
started = time.monotonic()
with TemporaryDirectory(prefix="sampling-measure-"):
    result = run([str(executable), "--measure"], capture_output=True, text=True, timeout=100, check=True)
    if result.stderr:
        raise RuntimeError("Probe produced unexpected diagnostic output")
(evidence / "measurements.jsonl").write_text(result.stdout)
rows = [json.loads(line) for line in result.stdout.splitlines()]
after_app = process_metrics(canonical_path)
after_helper = process_metrics(helper_path)
samples = [row for row in rows if row["stage"] == "runtime_sample"]
assert len(samples) == 32
assert all(not row["mainThread"] for row in samples)
cold = next(row for row in rows if row["stage"] == "health_cold")
assert len(cold["calls"]) == 1 and cold["calls"][0]["stage"] == "health_live_profiler"
assert all(not (call["stage"] == "health_live_profiler") for row in samples for call in row["calls"])
assert rows[-1] == {"stage": "end", "remainingHealthLiveReads": []}
stages = collections.defaultdict(list)
counts = collections.Counter()
for row in samples:
    for call in row["calls"]:
        stages[call["stage"]].append(call["wallNanoseconds"] / 1_000_000)
        counts[call["stage"]] += 1
for key in ("registry_allowlisted_read", "iops_system_read", "health_cache_read", "battery_runtime_branch", "helper_v5_ipc"):
    assert counts[key] == 32
summary = {
    "baseline": BASELINE,
    "runtimeWallMilliseconds": distribution([row["wallNanoseconds"] / 1_000_000 for row in samples]),
    "runtimeClientCPUMilliseconds": distribution([row["selfCPUNanoseconds"] / 1_000_000 for row in samples]),
    "runtimeClientMeanCPUCoresAt2SecondCadence": statistics.mean(row["selfCPUNanoseconds"] / 2_000_000_000 for row in samples),
    "stagesWallMilliseconds": {key: distribution(values) for key, values in stages.items()},
    "callsDuringRuntime": dict(counts),
    "allSnapshotsAvailable": all(row["snapshotAvailable"] for row in samples),
    "helperOutcomes": dict(collections.Counter(row["helperOutcome"] for row in samples)),
    "healthCold": cold,
    "healthHotNanosecondsPerCall": distribution([
        row["wallNanoseconds"] / row["iterations"] for row in rows if row["stage"] == "health_hot_batch"
    ]),
    "topProcessesWallMilliseconds": distribution([
        row["wallNanoseconds"] / 1_000_000 for row in rows if row["stage"] == "top_processes_read"
    ]),
    "topProcessesClientCPUMilliseconds": distribution([
        row["selfCPUNanoseconds"] / 1_000_000 for row in rows if row["stage"] == "top_processes_read"
    ]),
    "topProcessesRowCounts": [row["returnedRowCount"] for row in rows if row["stage"] == "top_processes_read"],
    "canonicalPIDsUnchanged": set(before_app) == set(after_app),
    "canonicalBefore": list(before_app.values()), "canonicalAfter": list(after_app.values()),
    "canonicalCPUSecondsDelta": sum(after_app[pid]["cpuSeconds"] - before_app[pid]["cpuSeconds"] for pid in set(before_app) & set(after_app)),
    "helperPIDSetUnchanged": set(before_helper) == set(after_helper),
    "helperCPUSecondsDelta": sum(after_helper[pid]["cpuSeconds"] - before_helper[pid]["cpuSeconds"] for pid in set(before_helper) & set(after_helper)),
    "helperObservedBeforeCount": len(before_helper), "helperObservedAfterCount": len(after_helper),
    "windowWallSeconds": time.monotonic() - started,
    "wallFinishedUTC": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
}
(evidence / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
print(json.dumps(summary, indent=2))
assert summary["canonicalPIDsUnchanged"], "Canonical app process changed during measurement"
