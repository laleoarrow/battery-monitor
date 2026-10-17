#!/bin/bash
set -euo pipefail
project="/Users/leoarrow/Project/mypackage/agents/电池功率"
source "$project/scripts/lib/local_cleanup.sh"
wattson_cleanup_init
out="$project/.build/normal-slow-drag.noindex/control-v6-prep"
run_dir="$(mktemp -d "$out/typecheck.XXXXXX")"
wattson_cleanup_add_dir "$run_dir"
wattson_run_timeout 60 /usr/bin/xcrun swiftc -swift-version 5 -warnings-as-errors "$out/headless-target-check.swift" -o "$run_dir/check" > "$out/headless-target-build.log" 2>&1
wattson_run_timeout 15 "$run_dir/check" > "$out/headless-target-result.json" 2> "$out/headless-target-stderr.log"
