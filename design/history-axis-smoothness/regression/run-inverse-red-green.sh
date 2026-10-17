#!/bin/bash
set -euo pipefail
repo='/Users/leoarrow/Project/mypackage/agents/电池功率'
qa="$repo/.build/history-axis-smoothness.noindex/qa"
results="$repo/.build/history-axis-smoothness.noindex/host/inverse-red-green"
source "$repo/scripts/lib/local_cleanup.sh"
wattson_cleanup_init
mkdir -p "$results" "$repo/.build/history-axis-smoothness.noindex/red-green.noindex"
run="$(mktemp -d "$repo/.build/history-axis-smoothness.noindex/red-green.noindex/run.XXXXXX")"
wattson_cleanup_add_dir "$run"
for item in 'old:15146fefd08e9b967534e05cd5d91267649b0e8b' 'new:f818ae3e06c1fcbd69d506d7631d905a37228ce2'; do
  label="${item%%:*}"; ref="${item#*:}"
  git -C "$repo" show "$ref:Core/HistoryChart.swift" > "$run/HistoryChart.swift"
  /usr/bin/shasum -a 256 "$run/HistoryChart.swift" "$qa/head-inverse-regression.swift" > "$results/$label-inputs.sha256"
  wattson_run /usr/bin/nice -n 15 /usr/bin/xcrun swiftc -O -module-cache-path "$run/module-cache" -parse-as-library "$run/HistoryChart.swift" "$qa/head-inverse-regression.swift" -o "$run/test"
  wattson_run_timeout 15 "$run/test" > "$results/$label.json"
done
wattson_run /usr/bin/python3 -c 'import json,sys;from pathlib import Path;p=Path(sys.argv[1]);a=json.loads((p/"old.json").read_text());b=json.loads((p/"new.json").read_text());assert a["checks"]==b["checks"] and a["failures"]>0 and b["failures"]==0;print(a);print(b)' "$results"
