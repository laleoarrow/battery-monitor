#!/bin/bash
set -euo pipefail
repo="${WATTSON_HISTORY_SOURCE_ROOT:?}"
tools="${WATTSON_HISTORY_TOOLS_DIR:?}"
results="${WATTSON_HISTORY_RESULTS:?}"
source "$repo/scripts/lib/local_cleanup.sh"
wattson_cleanup_init
cd "$repo"
mkdir -p "$results/interaction" "$results/animation" "$results/captures" "$results/motion"
/usr/bin/sw_vers > "$results/system.txt"
return_status() { return "$1"; }
finish() {
  local status=$?
  trap - EXIT
  trap '' HUP INT TERM
  set +e
  if [[ -n "${_WATTSON_RUNNER_PID:-}" ]]; then kill -TERM "$_WATTSON_RUNNER_PID" 2>/dev/null; wait "$_WATTSON_RUNNER_PID" 2>/dev/null; _WATTSON_RUNNER_PID=''; fi
  for bundle_id in "${owned_bundle_ids[@]+"${owned_bundle_ids[@]}"}"; do
    wattson_run_timeout 20 /usr/bin/osascript -l JavaScript "$tools/synchronize-owned-defaults.js" "$bundle_id" >> "$results/defaults-synchronized.log" 2>&1 || status=1
    wattson_run_timeout 25 /usr/bin/python3 "$tools/finalize-owned-defaults.py" "$bundle_id" >> "$results/defaults-finalized.jsonl" 2>&1 || status=1
  done
  printf '%s\n' "$status" > "$results/qa-exit-code.txt"
  return_status "$status"
  _wattson_cleanup
}
owned_bundle_ids=()
trap finish EXIT
mkdir -p "$repo/.build/history-axis-captures.noindex"
run_dir="$(mktemp -d "$repo/.build/history-axis-captures.noindex/run.XXXXXX")"
wattson_cleanup_add_dir "$run_dir"
wattson_run /usr/bin/xcrun clang -mmacosx-version-min=12.0 -Wno-deprecated-declarations -c tests/visual/capture_glass_shadow.c -o "$run_dir/capture.o" > "$results/captures/build.log" 2>&1
for kind in motion gallery; do
  app="$run_dir/$kind.app"
  bundle_id="com.leoarrow.wattson.historyaxisqa.$(/usr/bin/uuidgen | /usr/bin/tr '[:upper:]' '[:lower:]')"
  owned_bundle_ids+=("$bundle_id")
  wattson_cleanup_add_app "$app"
  wattson_cleanup_add_container "$bundle_id"
  wattson_cleanup_add_defaults "$bundle_id"
  wattson_cleanup_add_executable "$app/Contents/MacOS/HistoryProbe"
  printf '%s\t%s\n' "$bundle_id" "$app" >> "$results/capture-bundles.tsv"
  mkdir -p "$results/provenance/$kind"
  printf 'bundleID=%s\nbundlePath=%s\nsourceCommit=%s\n' "$bundle_id" "$app" "$WATTSON_HISTORY_SOURCE_COMMIT" > "$results/provenance/$kind/capture-provenance.txt"
  mkdir -p "$app/Contents/MacOS"
  if [[ "$kind" == gallery ]]; then
    wattson_run /usr/bin/python3 "$tools/prepare-gallery.py" tests/visual/capture_production_glass.swift "$run_dir/$kind.swift" "$tools/prepare-sixstate-harness.py"
  else
    cp "$tools/capture-axis-motion.swift" "$run_dir/$kind.swift"
  fi
  cp "$run_dir/$kind.swift" "$results/$kind-harness.swift"
  /usr/bin/shasum -a 256 "$run_dir/$kind.swift" Core/HistoryChart.swift Popover/HistoryLayer.swift >> "$results/capture-inputs.sha256"
  wattson_run /usr/bin/xcrun swiftc Core/*.swift MenuBar/*.swift Popover/*.swift "$run_dir/$kind.swift" "$run_dir/capture.o" -D DEBUG -swift-version 5 -warnings-as-errors -import-objc-header tests/visual/capture_glass_shadow.h -framework AppKit -framework CoreGraphics -framework IOKit -o "$app/Contents/MacOS/HistoryProbe" >> "$results/captures/build.log" 2>&1
  cat > "$app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>$bundle_id</string>
<key>CFBundleName</key><string>HistoryProbe</string>
<key>CFBundleExecutable</key><string>HistoryProbe</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$(cat VERSION)</string>
<key>CFBundleVersion</key><string>$(cat VERSION)</string>
<key>LSUIElement</key><true/>
</dict></plist>
EOF
  wattson_run /usr/bin/codesign --force --sign - "$app" >> "$results/captures/build.log" 2>&1
  if [[ "$kind" == gallery ]]; then
    for scenario in charging full on-battery mixed-supply low-battery low-power; do
      output="$results/captures/$scenario"
      mkdir -p "$output"
      wattson_run_timeout 150 /usr/bin/env WATTSON_FORCE_REDUCE_MOTION=0 WATTSON_FORCE_REDUCE_TRANSPARENCY=0 WATTSON_FORCE_INCREASE_CONTRAST=0 WATTSON_CAPTURE_SCENARIO="$scenario" WATTSON_CAPTURE_POPOVER_ARROW=1 WATTSON_CAPTURE_GLASS_TRANSPARENCY=1 "$app/Contents/MacOS/HistoryProbe" "$output" > "$output/run.log" 2> "$output/run.err"
      [[ -s "$output/complete.json" ]]
      printf 'PASS capture %s\n' "$scenario"
    done
  else
    for mode in scalar frames; do
      output="$results/motion/$mode"
      mkdir -p "$output"
      wattson_run_timeout 60 /usr/bin/env WATTSON_FORCE_REDUCE_MOTION=0 WATTSON_FORCE_REDUCE_TRANSPARENCY=0 WATTSON_FORCE_INCREASE_CONTRAST=0 "$app/Contents/MacOS/HistoryProbe" "$output" "$mode" > "$output/run.log" 2> "$output/run.err"
      [[ -s "$output/axis-motion.json" ]]
      printf 'PASS motion capture %s\n' "$mode"
    done
  fi
done
wattson_run_script -x scripts/verify_interaction.sh > "$results/interaction/run.log" 2>&1
wattson_run /usr/bin/python3 "$tools/extract-owned-domains.py" "$results/interaction/run.log" "$results/interaction/owned-domains.txt"
wattson_run_script -x scripts/verify_animation_stress.sh 20000 > "$results/animation/run.log" 2>&1
echo HISTORY_AXIS_NATIVE_QA_COMPLETED_ANALYSIS_PENDING
