#!/bin/bash
# Compile an owned VM fixture, then wait for a separate caller-owned start marker.
set -euo pipefail
[[ $# == 2 ]] || exit 64
suffix="$1"; overlay_sha="$2"
[[ "$suffix" =~ ^[A-Za-z0-9][A-Za-z0-9._-]+$ && "$overlay_sha" =~ ^[a-f0-9]{64}$ ]] || exit 64
[[ "$HOME" == /Users/admin && "$(/usr/sbin/sysctl -n hw.model)" == VirtualMac* ]] || exit 65
share='/Volumes/My Shared Files/normaldrag'
fixture="$share/fixture"
project="$HOME/Project/Wattson-NormalSlowDrag-QA"
source "$fixture/lifecycle/local_cleanup.sh"
wattson_cleanup_init
[[ -d "$share" && ! -e "$share/$suffix" && ! -L "$project" ]] || exit 65
if [[ ! -e "$project" ]]; then mkdir -p "$project"; wattson_cleanup_add_dir "$project"; fi
mkdir -p "$project/.build/normal-slow-drag.noindex"
run_dir="$(mktemp -d "$project/.build/normal-slow-drag.noindex/run.XXXXXX")"
wattson_cleanup_add_dir "$run_dir"
results="$share/$suffix"
mkdir "$results"
return_status() { return "$1"; }
finish() {
  local status=$?
  trap - EXIT
  trap '' HUP INT TERM
  set +e
  if [[ -n "${_WATTSON_RUNNER_PID:-}" ]]; then
    kill -TERM "$_WATTSON_RUNNER_PID" 2>/dev/null
    wait "$_WATTSON_RUNNER_PID" 2>/dev/null
    _WATTSON_RUNNER_PID=''
  fi
  if [[ -s "$results/source-production-before.json" && -d "$run_dir/source" ]]; then
    /usr/bin/python3 "$fixture/verify-production.py" "$run_dir/source" "$results" after || status=1
  fi
  printf '%s\n' "$status" > "$results/stage-exit-code.txt"
  return_status "$status"
  _wattson_cleanup
}
trap finish EXIT
cp "$fixture/source-5d5c896b7a15.tar.gz" "$run_dir/source.tar.gz"
cp "$fixture/qa-tools-v6.tar.gz" "$run_dir/base-tools.tar.gz"
cp "$fixture/normal-slow-drag-v2-tools.tar.gz" "$run_dir/overlay-tools.tar.gz"
[[ "$(/usr/bin/shasum -a 256 "$run_dir/source.tar.gz" | /usr/bin/awk '{print $1}')" == 8aa52b90ec8f2e7f93e2ccc7ebc2fd9ab7e89217a95bfd93edccbb3e90156ca3 ]] || exit 65
[[ "$(/usr/bin/shasum -a 256 "$run_dir/base-tools.tar.gz" | /usr/bin/awk '{print $1}')" == 89343e38e8ce2e0327bef3324d6a0d308dbfa1a99368409454c190dbe913c9a5 ]] || exit 65
[[ "$(/usr/bin/shasum -a 256 "$run_dir/overlay-tools.tar.gz" | /usr/bin/awk '{print $1}')" == "$overlay_sha" ]] || exit 65
/usr/bin/python3 "$fixture/validate-archives.py" "$run_dir/source.tar.gz" "$run_dir/base-tools.tar.gz"
/usr/bin/python3 "$fixture/validate-archives.py" "$run_dir/overlay-tools.tar.gz" "$run_dir/overlay-tools.tar.gz"
mkdir "$run_dir/source" "$run_dir/base-tools" "$run_dir/tools"
/usr/bin/tar -xzf "$run_dir/source.tar.gz" -C "$run_dir/source"
/usr/bin/tar -xzf "$run_dir/base-tools.tar.gz" -C "$run_dir/base-tools"
/usr/bin/tar -xzf "$run_dir/overlay-tools.tar.gz" -C "$run_dir/tools"
# Unchanged v6 runtime interception forwards each native original exactly once.
/usr/bin/cmp "$run_dir/base-tools/native-drag-observer-v6.swift" "$run_dir/tools/native-drag-observer-v6.swift"
/usr/bin/shasum -a 256 "$run_dir/source.tar.gz" "$run_dir/base-tools.tar.gz" "$run_dir/overlay-tools.tar.gz" > "$results/native-inputs.sha256"
/usr/bin/python3 "$fixture/verify-production.py" "$run_dir/source" "$results" before
export WATTSON_MODULES_SOURCE_COMMIT=5d5c896b7a1531ce4f9783fa467ff8c8eb62b82e
export WATTSON_MODULES_SOURCE_ROOT="$run_dir/source"
export WATTSON_MODULES_TOOLS_DIR="$run_dir/tools"
export WATTSON_MODULES_RESULTS="$results"
export WATTSON_MODULES_MANUAL_STYLE=classic
export WATTSON_FORCE_REDUCE_MOTION=0
code=0
/usr/bin/python3 "$run_dir/source/scripts/lib/run_owned.py" --grace 300 --timeout 3000 -- /bin/bash "$run_dir/tools/run-normal-slow-drag.sh" &
_WATTSON_RUNNER_PID=$!
wait "$_WATTSON_RUNNER_PID" || code=$?
_WATTSON_RUNNER_PID=''
printf '%s\n' "$code" > "$results/runner-exit-code.txt"
exit "$code"
