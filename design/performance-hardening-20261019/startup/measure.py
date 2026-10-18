import hashlib
import json
import pathlib
import statistics
import subprocess
import sys
import time

root, executable, source_dir, evidence = map(pathlib.Path, sys.argv[1:])
production_files = [
    "Core/PowerSnapshot.swift",
    "Core/BatterySampler.swift",
    "Core/BatteryRuntimeEstimate.swift",
]


def command(*arguments):
    return subprocess.check_output(arguments, text=True, timeout=10).strip()


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def canonical_pids():
    # Inspect only; the harness never starts or stops the installed app.
    result = subprocess.run(
        ["/usr/bin/pgrep", "-f", "^/Applications/Wattson[.]app/Contents/MacOS/Wattson( |$)"],
        capture_output=True, text=True, timeout=5,
    )
    if result.returncode not in (0, 1):
        raise RuntimeError("Cannot inspect canonical process identity")
    return sorted(int(pid) for pid in result.stdout.split())


metadata = {
    "head": command("/usr/bin/git", "-C", str(root), "rev-parse", "HEAD"),
    "osVersion": command("/usr/bin/sw_vers", "-productVersion"),
    "osBuild": command("/usr/bin/sw_vers", "-buildVersion"),
    "architecture": command("/usr/bin/uname", "-m"),
    "compiler": command("/usr/bin/xcrun", "swiftc", "--version"),
    "sourceFiles": {
        name: {"compiledSHA256": sha(source_dir / pathlib.Path(name).name)}
        for name in production_files
    },
    "optimization": "-O -whole-module-optimization; arm64-apple-macos12.0",
    "sampleCount": 24,
    "minimumProcessSpacingSeconds": 2,
    "perProcessTimeoutSeconds": 5,
    "canonicalPIDsBefore": canonical_pids(),
    "wallStartedUTC": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "limitations": [
        "First sampler call in each fresh CLI process; OS/disk/IOKit caches are not flushed.",
        "Does not measure dyld/process launch, NSApplication startup, status item creation, or time to first frame.",
        "Optimized unsandboxed CLI; app sandbox and complete app image may have different costs.",
        "One host and session; background load is not controlled and no macOS 27 runtime was tested.",
        "Existing canonical app remains running; measurements neither restart it nor call the helper.",
    ],
}
(evidence / "metadata.json").write_text(json.dumps(metadata, indent=2) + "\n")
rows = []
previous_start = None
with (evidence / "measurements.jsonl").open("w") as stream:
    for index in range(metadata["sampleCount"]):
        if previous_start is not None:
            time.sleep(max(0, previous_start + 2 - time.monotonic()))
        previous_start = time.monotonic()
        completed = subprocess.run(
            [str(executable)], capture_output=True, text=True, check=True, timeout=5,
        )
        row = json.loads(completed.stdout)
        row["iteration"] = index + 1
        row["childProcessWallMilliseconds"] = (time.monotonic() - previous_start) * 1_000
        if completed.stderr:
            row["stderr"] = completed.stderr
        rows.append(row)
        stream.write(json.dumps(row, sort_keys=True) + "\n")
        stream.flush()

elapsed_ms = sorted(row["elapsedNanoseconds"] / 1_000_000 for row in rows)
cpu_ms = sorted(row["processCPUNanoseconds"] / 1_000_000 for row in rows)
source_unchanged = all(
    sha(root / name) == info["compiledSHA256"]
    for name, info in metadata["sourceFiles"].items()
)
summary = {
    "samples": len(rows),
    "uniqueFreshProcesses": len({row["pid"] for row in rows}),
    "allMainThread": all(row["mainThread"] for row in rows),
    "allFirstSamplerCalls": all(row["firstSamplerCall"] for row in rows),
    "outcomes": {value: sum(row["outcome"] == value for row in rows) for value in {row["outcome"] for row in rows}},
    "samplerElapsedMilliseconds": {
        "minimum": min(elapsed_ms), "median": statistics.median(elapsed_ms),
        "p95NearestRank": elapsed_ms[-2], "maximum": max(elapsed_ms),
        "firstProcess": rows[0]["elapsedNanoseconds"] / 1_000_000,
    },
    "processCPUMilliseconds": {
        "minimum": min(cpu_ms), "median": statistics.median(cpu_ms), "maximum": max(cpu_ms),
    },
    "over60HzFrameBudgetCount": sum(value > 1_000 / 60 for value in elapsed_ms),
    "over120HzFrameBudgetCount": sum(value > 1_000 / 120 for value in elapsed_ms),
    "productionSourcesUnchangedDuringMeasurement": source_unchanged,
    "canonicalPIDsAfter": canonical_pids(),
    "canonicalPIDsUnchanged": canonical_pids() == metadata["canonicalPIDsBefore"],
    "wallFinishedUTC": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
}
(evidence / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
print(json.dumps(summary, indent=2))
if not source_unchanged:
    raise RuntimeError("Production inputs changed during measurement")
