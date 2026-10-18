#!/bin/bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
EVIDENCE="$TASK_ROOT/design/performance-hardening-20261019/startup"
source "$TASK_ROOT/scripts/lib/local_cleanup.sh"
wattson_cleanup_init
mkdir -p "$TASK_ROOT/.build/startup-sampling.noindex"
SCRATCH="$(mktemp -d "$TASK_ROOT/.build/startup-sampling.noindex/probe.XXXXXX")"
wattson_cleanup_add_dir "$SCRATCH"
mkdir -p "$SCRATCH/sources" "$SCRATCH/module-cache"
for SOURCE in Core/PowerSnapshot.swift Core/BatterySampler.swift Core/BatteryRuntimeEstimate.swift; do
    cp "$TASK_ROOT/$SOURCE" "$SCRATCH/sources/$(basename "$SOURCE")"
done
cp "$EVIDENCE/main.swift" "$SCRATCH/sources/main.swift"
wattson_run_timeout 60 /usr/bin/xcrun swiftc -O -whole-module-optimization \
    -module-cache-path "$SCRATCH/module-cache" \
    -target arm64-apple-macos12.0 \
    "$SCRATCH/sources/PowerSnapshot.swift" \
    "$SCRATCH/sources/BatterySampler.swift" \
    "$SCRATCH/sources/BatteryRuntimeEstimate.swift" \
    "$SCRATCH/sources/main.swift" \
    -o "$SCRATCH/startup-read-probe" >"$EVIDENCE/build.log" 2>&1
wattson_cleanup_add_executable "$SCRATCH/startup-read-probe"
wattson_run_timeout 60 /usr/bin/python3 "$EVIDENCE/measure.py" \
    "$TASK_ROOT" "$SCRATCH/startup-read-probe" "$SCRATCH/sources" "$EVIDENCE"
